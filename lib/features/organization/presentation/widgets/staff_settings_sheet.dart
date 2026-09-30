import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';

class StaffSetting {
  const StaffSetting({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Future<void> Function(BuildContext sheetContext) onTap;
}

Future<void> showStaffSettingsSheet(
  BuildContext context, {
  required List<StaffSetting> settings,
  required Future<void> Function() onLogout,
}) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.92,
    builder: (sheetContext) {
      return _StaffSettings(
        settings: settings,
        onLogout: () async {
          Navigator.of(sheetContext).pop();
          await onLogout();
        },
      );
    },
  );
}

class _StaffSettings extends StatelessWidget {
  const _StaffSettings({required this.settings, required this.onLogout});

  final List<StaffSetting> settings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sheetContext = context;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'الإعدادات',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < settings.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              _SettingTile(
                title: settings[index].title,
                subtitle: settings[index].subtitle,
                onTap: () => settings[index].onTap(sheetContext),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: onLogout,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.burgundy,
                foregroundColor: AppColors.onError,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
                textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        side: const BorderSide(color: AppColors.inputBorder),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: AppColors.secondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
