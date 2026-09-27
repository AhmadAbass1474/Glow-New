import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/mission_entity.dart';
import '../bloc/content_bloc.dart';
import '../bloc/content_event.dart';
import '../bloc/content_state.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/audio/child_button_voice.dart';

class ChildQuizScreen extends StatefulWidget {
  final MissionEntity mission;

  const ChildQuizScreen({super.key, required this.mission});

  @override
  State<ChildQuizScreen> createState() => _ChildQuizScreenState();
}

class _ChildQuizScreenState extends State<ChildQuizScreen> {
  late ContentBloc _contentBloc;
  int _currentQuestionIndex = 0;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _contentBloc.add(ContentEvent.getQuestions(widget.mission.id));
  }

  @override
  void dispose() {
    _contentBloc.close();
    super.dispose();
  }

  void _submitAnswer(int correctIndex, int totalQuestions) {
    if (_selectedIndex == null) return;
    
    if (_selectedIndex == correctIndex) {
      // Show Success Snack
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('إجابة صحيحة! أحسنت 🌟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: const Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.border_radius)),
          duration: const Duration(seconds: 1),
        ),
      );
      
      // Small delay then advance
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          if (_currentQuestionIndex < totalQuestions - 1) {
            setState(() {
              _currentQuestionIndex++;
              _selectedIndex = null;
            });
          } else {
            sl<AuthLocalDataSource>().getLastChild().then((cachedChild) {
              final childId = cachedChild?.id ?? Supabase.instance.client.auth.currentUser?.id;
              if (childId != null) {
                _contentBloc.add(ContentEvent.completeMission(widget.mission.id, childId));
              }
              if (mounted) {
                context.go('/child/mission-complete', extra: widget.mission);
              }
            });
          }
        }
      });
    } else {
      // Show Error Snack
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('إجابة خاطئة، حاول مرة أخرى! 💪'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _selectedIndex = null; // reset
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text(
            'التحدي',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.2,
              color: Color(0xFF2C3E50),
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.white.withOpacity(0.4),
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.8), Colors.white.withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          foregroundColor: const Color(0xFF2C3E50),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              ChildButtonVoice.press('رجوع', () async {
                if (!context.mounted) return;
                context.pop();
              }, single: true);
            },
          ),
        ),
        body: Container(
          color: Colors.white,
          child: SafeArea(
            child: BlocBuilder<ContentBloc, ContentState>(
              builder: (context, state) {
                return state.maybeWhen(
                  loading: () => const ShimmerLoading(type: ShimmerType.card),
                  error: (msg) => Center(child: Text('خطأ: $msg', style: const TextStyle(color: Colors.red))),
                  questionsLoaded: (questions) {
                    if (questions.isEmpty) {
                      return const Center(child: Text('لا توجد تحديات حالياً.', style: TextStyle(fontSize: 14, color: Colors.grey)));
                    }

                final currentQ = questions[_currentQuestionIndex];
                final options = currentQ.options;
                final letters = ['A', 'B', 'C', 'D'];
                
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Progress and Question Number
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'السؤال ${_currentQuestionIndex + 1} من ${questions.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3498DB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppColors.border_radius),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                SizedBox(width: 4),
                                Text(
                                  'نقاط التحدي',
                                  style: TextStyle(
                                    color: Color(0xFF3498DB),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        child: LinearProgressIndicator(
                          value: (_currentQuestionIndex + 1) / questions.length,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Question Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppColors.border_radius),
                          border: Border.all(color: Colors.grey.shade300, width: 2),
                        ),
                        child: Text(
                          currentQ.questionText,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2C3E50),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Options List
                      Expanded(
                        child: ListView.separated(
                          itemCount: options.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final opt = options[index];
                            final isSelected = _selectedIndex == index;
                            final letter = index < letters.length ? letters[index] : '';
                            
                            return GestureDetector(
                              onTap: () {
                                ChildButtonVoice.press(opt, () async {
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedIndex = index;
                                  });
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF3498DB) : Colors.white,
                                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF3498DB) : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : const Color(0xFFF0F4F8),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          letter,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: isSelected ? const Color(0xFF3498DB) : const Color(0xFF2C3E50),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        opt,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.white : const Color(0xFF2C3E50),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Submit Button
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: _selectedIndex == null ? null : () {
                            ChildButtonVoice.press('إرسال الإجابة', () async {
                              _submitAnswer(currentQ.correctAnswerIndex, questions.length);
                            }, single: true);
                          },
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('إرسال الإجابة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2ECC71),
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppColors.border_radius),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox(),
            );
          },
        ),
          ),
        ),
      ),
    );
  }
}

