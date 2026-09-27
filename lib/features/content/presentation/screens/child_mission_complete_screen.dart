import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../domain/entities/mission_entity.dart';

class ChildMissionCompleteScreen extends StatelessWidget {
  final MissionEntity mission;

  const ChildMissionCompleteScreen({super.key, required this.mission});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // Calm, flat off-white background
      body: Container(
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 40.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Title
                const Text(
                  'أحسنت يا بطل !',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10B981), // Calmer green
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Subtitle
                const Text(
                  'لقد أتممت المهمة بالكامل وأجبت على جميع التحديات بنجاح. لقد ربحت أوسمة ونقاطاً جديدة!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569), // Calmer slate text
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Earned Badge Card (Flat with simple border)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      AppColors.border_radius,
                    ),
                    border: Border.all(
                      color: AppColors.inputBorder,
                      width: 2,
                    ), // Unified simple border
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Badge
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'الوسام المكتسب',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mission.badgeName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF334155),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Divider
                      Container(
                        height: 50,
                        width: 2,
                        color: const Color(0xFFF1F5F9), // Very soft divider
                      ),
                      // Points
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFBBF24),
                              size: 36,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'النقاط',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '+${mission.starsReward}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // See Badges Button (Flat)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () {
                      ChildButtonVoice.press('رؤية أوسمتي', () async {
                        if (!context.mounted) return;
                        context.push('/child/badges');
                      }, single: true);
                    },
                    icon: const Icon(
                      Icons.workspace_premium_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'رؤية أوسمتي',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      // Flat calm purple
                      elevation: 0,
                      // No shadow
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Go to Dashboard Button (Flat Outline)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () {
                      ChildButtonVoice.press('العودة للرئيسية', () async {
                        if (!context.mounted) return;
                        context.go('/child-dashboard');
                      }, single: true);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFCBD5E1),
                        width: 2,
                      ),
                      // Unified soft border
                      backgroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                      ),
                    ),
                    child: const Text(
                      'العودة للرئيسية',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B), // Soft text
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
