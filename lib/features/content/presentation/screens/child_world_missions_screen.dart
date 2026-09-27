import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/world_entity.dart';
import '../bloc/content_bloc.dart';
import '../bloc/content_event.dart';
import '../bloc/content_state.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../domain/repositories/content_repository.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../../../core/services/character_asset_cache.dart';

class ChildWorldMissionsScreen extends StatefulWidget {
  final WorldEntity world;

  const ChildWorldMissionsScreen({super.key, required this.world});

  @override
  State<ChildWorldMissionsScreen> createState() => _ChildWorldMissionsScreenState();
}

class _ChildWorldMissionsScreenState extends State<ChildWorldMissionsScreen> {
  late ContentBloc _contentBloc;
  List<String> _completedMissionIds = [];
  bool _isLoadingProgress = true;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _contentBloc.add(ContentEvent.getMissions(widget.world.id));
    _fetchProgress();
    // Warm the shared mascot before the child opens a story.
    unawaited(CharacterAssetCache.instance.prewarm());
  }

  Future<void> _fetchProgress() async {
    final cachedChild = await sl<AuthLocalDataSource>().getLastChild();
    final childId = cachedChild?.id ?? Supabase.instance.client.auth.currentUser?.id;

    if (childId != null) {
      final result = await sl<ContentRepository>().getCompletedMissions(childId);
      if (mounted) {
        result.fold(
          (_) => setState(() => _isLoadingProgress = false),
          (list) => setState(() {
            _completedMissionIds = list.map((p) => p.missionId).toList();
            _isLoadingProgress = false;
          }),
        );
      }
    } else {
      if (mounted) setState(() => _isLoadingProgress = false);
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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            widget.world.title,
            style: const TextStyle(
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE0F7FA),
                Color(0xFFF3E5F5),
                Color(0xFFFFF3E0),
              ],
            ),
          ),
          child: SafeArea(
            child: BlocBuilder<ContentBloc, ContentState>(
              builder: (context, state) {
                return state.maybeWhen(
                  loading: () => const ShimmerLoading(),
                  error: (msg) => Center(child: Text('خطأ: $msg', style: const TextStyle(color: Colors.red))),
                  missionsLoaded: (missions) {
                    if (_isLoadingProgress) {
                      return const ShimmerLoading();
                    }
                    if (missions.isEmpty) {
                      return const Center(child: Text('لا توجد مهام في هذا العالم بعد.', style: TextStyle(fontSize: 14, color: Colors.grey)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      cacheExtent: 400,
                      physics: const BouncingScrollPhysics(),
                      itemCount: missions.length,
                      itemBuilder: (context, index) {
                        final mission = missions[index];
                        final isCompleted = _completedMissionIds.contains(mission.id);
                        final isUnlocked = index == 0 || _completedMissionIds.contains(missions[index - 1].id);
                        
                        // Colors array for missions
                        final List<Color> cardColors = [
                          const Color(0xFFFFF9C4), // Light Yellow
                          const Color(0xFFE1BEE7), // Light Purple
                          const Color(0xFFC8E6C9), // Light Green
                          const Color(0xFFFFCCBC), // Light Orange
                          const Color(0xFFBBDEFB), // Light Blue
                        ];
                        final cardColor = isUnlocked ? cardColors[index % cardColors.length] : Colors.grey.shade300;
                        
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: isUnlocked ? () {
                              HapticFeedback.lightImpact();
                              ChildButtonVoice.press(mission.title, () async {
                                if (!context.mounted) return;
                                await context.push('/child/story-viewer', extra: mission);
                                if (mounted) {
                                  setState(() => _isLoadingProgress = true);
                                  _fetchProgress();
                                }
                              }, single: true);
                            } : null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(AppColors.border_radius),
                                border: Border.all(color: Colors.grey.shade300, width: 2),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  // Level Indicator
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: Center(
                                      child: isCompleted
                                          ? const Icon(Icons.check_rounded, color: Color(0xFF2ECC71), size: 24)
                                          : !isUnlocked
                                              ? const Icon(Icons.lock_rounded, color: Colors.grey, size: 20)
                                              : Text(
                                                  '${index + 1}',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade800,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mission.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: isUnlocked ? const Color(0xFF2C3E50) : Colors.grey,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            if (mission.badgeName.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.7),
                                                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(mission.badgeName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                                  ],
                                                ),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.7),
                                                borderRadius: BorderRadius.circular(AppColors.border_radius),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                                  const SizedBox(width: 4),
                                                  Text('${mission.starsReward}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

