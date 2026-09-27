import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../bloc/content_bloc.dart';
import '../bloc/content_event.dart';
import '../bloc/content_state.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/audio/child_button_voice.dart';

class ChildBadgesScreen extends StatefulWidget {
  const ChildBadgesScreen({super.key});

  @override
  State<ChildBadgesScreen> createState() => _ChildBadgesScreenState();
}

class _ChildBadgesScreenState extends State<ChildBadgesScreen> {
  late ContentBloc _contentBloc;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    final cachedChild = await sl<AuthLocalDataSource>().getLastChild();
    final childId = cachedChild?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (childId != null) {
      _contentBloc.add(ContentEvent.getCompletedMissions(childId));
    }
  }

  @override
  void dispose() {
    _contentBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'أوسمتي المكتسبة',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.2,
              color: Color(0xFF2C3E50),
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Color(0xFFF3E5F5), // Light purple
              ],
            ),
          ),
          child: SafeArea(
            child: BlocBuilder<ContentBloc, ContentState>(
              builder: (context, state) {
                return state.maybeWhen(
                  loading: () => const ShimmerLoading(type: ShimmerType.grid),
                  error: (msg) => Center(child: Text('خطأ: $msg', style: const TextStyle(color: Colors.red))),
                  completedMissionsLoaded: (progressList) {
                    if (progressList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.workspace_premium_rounded, size: 100, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'لم تحصل على أية أوسمة بعد.\nأكمل المهام لتبدأ بجمع الأوسمة!',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: progressList.length,
                      itemBuilder: (context, index) {
                        final progress = progressList[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppColors.border_radius),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFF9B59B6).withOpacity(0.3), width: 2),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                progress.badgeName ?? 'وسام الإنجاز',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2C3E50),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${progress.starsReward ?? 0} نقطة',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE67E22),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
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
