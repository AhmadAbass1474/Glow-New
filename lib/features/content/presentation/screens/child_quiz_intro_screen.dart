import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../domain/entities/mission_entity.dart';

class ChildQuizIntroScreen extends StatelessWidget {
  final MissionEntity mission;

  const ChildQuizIntroScreen({super.key, required this.mission});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F7FA), // Light Blue
              Color(0xFFF3E5F5), // Light Purple
              Color(0xFFFFF3E0), // Light Orange
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                
                // Icon / Illustration
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 100,
                    color: Colors.amber,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Title
                const Text(
                  'عمل رائع يا بطل! 🌟',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2C3E50),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Subtitle
                const Text(
                  'لقد أنهيت مشاهد القصة بنجاح.\nالآن حان وقت التحدي لإثبات مهارتك وجمع النقاط!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const Spacer(),
                
                // Start Quiz Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () {
                      ChildButtonVoice.press('اختبر نفسك', () async {
                        if (!context.mounted) return;
                        context.pushReplacement('/child/quiz', extra: mission);
                      }, single: true);
                    },
                    icon: const Icon(Icons.rocket_launch_rounded, size: 24),
                    label: const Text(
                      'اختبر نفسك',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                      ),
                      elevation: 0,
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
