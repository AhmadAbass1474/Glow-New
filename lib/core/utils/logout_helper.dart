import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../di/injection_container.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../theme/app_colors.dart';
import '../audio/child_button_voice.dart';

void showLogoutBottomSheet(BuildContext context, {bool readAloud = false}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.border_radius),
                        ),
                      ),
                      onPressed: () async {
                        Future<void> leave() async {
                          final localDataSource = sl<AuthLocalDataSource>();
                          await localDataSource.clearCache();
                          if (context.mounted) {
                            context.go('/role-selection');
                          }
                        }

                        if (readAloud) {
                          await ChildButtonVoice.press('خروج', leave, single: true);
                        } else {
                          await leave();
                        }
                      },
                      child: const Text('خروج', style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
