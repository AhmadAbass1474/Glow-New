import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_qr_scanner.dart';
import '../../data/child_account_service.dart';
import '../../data/parent_provisioned_child.dart';

Future<bool> showParentCreateChild(BuildContext context) async {
  final created = await showAppSheet<ProvisionedChildLogin>(
    context: context,
    heightFactor: 0.62,
    avoidKeyboard: true,
    builder: (sheetContext) => _CreateChildForm(
      onCreated: (login) {
        if (sheetContext.mounted) Navigator.of(sheetContext).pop(login);
      },
    ),
  );
  if (created == null || !context.mounted) return false;
  await showAppSheet<void>(
    context: context,
    heightFactor: 0.78,
    builder: (_) => _ChildLoginQr(login: created),
  );
  return true;
}

Future<void> claimParentChildAccount(
  BuildContext context, {
  required Future<void> Function() onReady,
}) async {
  final raw = await showAppSheet<String>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => const _ParentAccountScanner(),
  );
  if (raw == null || !context.mounted) return;
  final parsed = ParentProvisionedChild.parse(raw);
  if (parsed == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('هذا الرمز ليس حساباً من ولي الأمر')),
    );
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    ),
  );
  try {
    await sl<ChildAccountService>().adoptFromParent(
      email: parsed.email,
      password: parsed.password,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await onReady();
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر إضافة الحساب: $error')),
    );
  }
}

class _CreateChildForm extends StatefulWidget {
  const _CreateChildForm({required this.onCreated});

  final void Function(ProvisionedChildLogin login) onCreated;

  @override
  State<_CreateChildForm> createState() => _CreateChildFormState();
}

class _CreateChildFormState extends State<_CreateChildForm> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final age = int.tryParse(_age.text.trim());
    if (_name.text.trim().isEmpty || age == null || age < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم الطفل وعمره')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final login = await ParentProvisionedChild(Supabase.instance.client).create(
        name: _name.text.trim(),
        age: age,
      );
      if (!mounted) return;
      widget.onCreated(login);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء الحساب: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'حساب لطفلي',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ينشأ الحساب هنا ويرتبط بك. الطفل يمسح الرمز من هاتفه من دون أن يسجّل بنفسه.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'اسم الطفل'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'العمر'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'جارٍ الإنشاء' : 'إنشاء الحساب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildLoginQr extends StatelessWidget {
  const _ChildLoginQr({required this.login});

  final ProvisionedChildLogin login;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
        child: Column(
          children: [
            Text(
              'رمز ${login.name}',
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'من هاتف الطفل اختر إضافة حساب من ولي الأمر وامسح هذا الرمز.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, constraints.maxHeight);
                  return Center(
                    child: QrImageView(
                      data: login.qrPayload,
                      size: side,
                      backgroundColor: AppColors.surface,
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentAccountScanner extends StatelessWidget {
  const _ParentAccountScanner();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: 48),
        Text(
          'حساب من ولي الأمر',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'امسح الرمز الذي يعرضه ولي الأمر بعد إنشاء الحساب.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AppQrScanner(
            onCode: (raw) {
              if (ParentProvisionedChild.parse(raw) == null) return false;
              Navigator.of(context).pop(raw.trim());
              return true;
            },
          ),
        ),
      ],
    );
  }
}
