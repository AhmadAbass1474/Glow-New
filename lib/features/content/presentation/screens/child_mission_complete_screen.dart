import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../domain/entities/mission_entity.dart';

class ChildMissionCompleteScreen extends StatefulWidget {
  final MissionEntity mission;

  const ChildMissionCompleteScreen({super.key, required this.mission});

  @override
  State<ChildMissionCompleteScreen> createState() =>
      _ChildMissionCompleteScreenState();
}

class _ChildMissionCompleteScreenState extends State<ChildMissionCompleteScreen> {
  @override
  void initState() {
    super.initState();
    ChildButtonVoice.playSequence(const ['أحسنت يا بطل']);
  }

  @override
  void dispose() {
    ChildButtonVoice.stop();
    super.dispose();
  }

  void _tap(String phrase, void Function(GoRouter router) navigate) {
    final router = GoRouter.of(context);
    navigate(router);
    unawaited(ChildButtonVoice.press(phrase, () async {}));
  }

  @override
  Widget build(BuildContext context) {
    final mission = widget.mission;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SizedBox(
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
                const Text(
                  'أحسنت يا بطل !',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10B981),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'لقد أتممت المهمة بالكامل وأجبت على جميع التحديات بنجاح. لقد ربحت أوسمة ونقاطاً جديدة!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
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
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                      Container(
                        height: 50,
                        width: 2,
                        color: const Color(0xFFF1F5F9),
                      ),
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
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () {
                      _tap('رؤية أوسمتي', (router) {
                        router.push('/child/badges');
                      });
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
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () {
                      _tap('العودة للرئيسية', (router) {
                        router.go('/child-dashboard');
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFCBD5E1),
                        width: 2,
                      ),
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
                        color: Color(0xFF64748B),
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
