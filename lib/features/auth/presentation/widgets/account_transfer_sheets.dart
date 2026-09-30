import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_qr_scanner.dart';
import '../../../../core/widgets/custom_loader.dart';
import '../../data/account_transfer.dart';
import '../../data/child_account_service.dart';
import '../../data/models/device_child_account.dart';

Future<void> showAccountTransferSheet(
  BuildContext context, {
  required DeviceChildAccount account,
  required void Function(bool stillOnDevice) onMoved,
}) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.92,
    builder: (sheetContext) {
      return _TransferQr(
        account: account,
        onMoved: (stillHere) {
          Navigator.of(sheetContext).pop();
          onMoved(stillHere);
        },
      );
    },
  );
}

/// Opens the camera only for this sheet and closes it on the first valid code.
Future<String?> showAccountScanner(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => const _TransferScanner(),
  );
}

class _TransferQr extends StatefulWidget {
  const _TransferQr({required this.account, required this.onMoved});

  final DeviceChildAccount account;
  final void Function(bool stillOnDevice) onMoved;

  @override
  State<_TransferQr> createState() => _TransferQrState();
}

class _TransferQrState extends State<_TransferQr> {
  TransferTicket? _ticket;
  String? _error;
  Timer? _poll;
  var _leaving = false;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final ticket = await sl<AccountTransfer>().issue(widget.account);
      if (!mounted) return;
      setState(() => _ticket = ticket);
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        unawaited(_check());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'يلزم اتصال بالإنترنت قبل نقل الحساب');
    }
  }

  Future<void> _check() async {
    final ticket = _ticket;
    if (ticket == null || _leaving || _checking) return;
    if (DateTime.now().isAfter(ticket.expiresAt)) {
      _poll?.cancel();
      if (mounted) setState(() => _error = 'انتهت صلاحية الرمز. أغلق الورقة وافتحها من جديد');
      return;
    }
    _checking = true;
    try {
      final claimed = await sl<AccountTransfer>().isClaimed(ticket.id);
      if (!claimed || _leaving) return;
      _leaving = true;
      _poll?.cancel();
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      final left = await sl<ChildAccountService>().forget(ticket.childId);
      if (!mounted) return;
      widget.onMoved(left != null);
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ticket = _ticket;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(AppColors.border_radius),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'نقل الحساب',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.account.name,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, constraints.maxHeight);
                  if (ticket != null) {
                    return Center(
                      child: QrImageView(
                        data: ticket.payload,
                        size: side,
                        gapless: true,
                        errorCorrectionLevel: QrErrorCorrectLevel.L,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.secondary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.secondary,
                        ),
                      ),
                    );
                  }
                  if (_error == null) return const Center(child: CustomLoader());
                  return Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ولي الأمر يعرض هذا الرمز لهاتف الطفل الآخر. الرمز يعمل ثلاث دقائق.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferScanner extends StatefulWidget {
  const _TransferScanner();

  @override
  State<_TransferScanner> createState() => _TransferScannerState();
}

class _TransferScannerState extends State<_TransferScanner> {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(AppColors.border_radius),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'مسح نقل الحساب',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                child: AppQrScanner(
                  onCode: (raw) {
                    if (!raw.startsWith(AccountTransfer.prefix) || !mounted) return false;
                    Navigator.of(context).pop(raw);
                    return true;
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ضع الرمز داخل الإطار الأصفر',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> claimScannedCode(BuildContext context, String code) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CustomLoader(),
  );
  try {
    await sl<AccountTransfer>().claim(code);
    if (context.mounted) {
      Navigator.of(context).pop();
      context.go('/child-dashboard');
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر نقل الحساب. تأكد أن الرمز ما زال ظاهرًا والجهازين متصلين.'),
        ),
      );
    }
  }
}
