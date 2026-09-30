import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_qr_scanner.dart';
import '../../../auth/data/child_account_service.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../data/organization_service.dart';

Future<void> startStudentJoin(BuildContext context) async {
  final raw = await showAppSheet<String>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => const _StudentScanner(),
  );
  if (raw == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );

  try {
    if (!await sl<NetworkInfo>().isConnected) {
      throw Exception('يحتاج الطالب اتصالاً بالإنترنت عند أول دخول');
    }
    final service = OrganizationService(Supabase.instance.client);
    final preview = await service.previewInvite(raw);
    await sl<ChildAccountService>().register(
      name: preview.name,
      age: preview.age,
      avatarUrl: 'fort_frontal.glb',
    );
    await service.claimInvite(raw);
    await sl<AuthLocalDataSource>().forgetUser();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    context.go('/child-dashboard');
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر دخول الطالب: $error')),
    );
  }
}

class _StudentScanner extends StatelessWidget {
  const _StudentScanner();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: 48),
        Text(
          'مسح رمز الطالب',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'امسح الرمز الذي يعرضه المعلم على هاتفه.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AppQrScanner(
            onCode: (raw) {
              final trimmed = raw.trim();
              if (!trimmed.startsWith(OrganizationService.studentPrefix)) return false;
              Navigator.of(context).pop(trimmed);
              return true;
            },
          ),
        ),
      ],
    );
  }
}
