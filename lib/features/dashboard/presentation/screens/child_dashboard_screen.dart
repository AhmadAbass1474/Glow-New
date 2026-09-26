import 'dart:async';

import 'package:Glow/core/network/network_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../content/presentation/bloc/content_bloc.dart';
import '../../../content/presentation/bloc/content_event.dart';
import '../../../content/presentation/bloc/content_state.dart';

import '../../../../core/widgets/offline_aware_image.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../content/data/services/sync_service.dart';
import '../../../content/domain/repositories/content_repository.dart';
import '../../../../core/utils/logout_helper.dart';
import '../../../../core/widgets/custom_loader.dart';
import '../../../../core/services/character_asset_cache.dart';

class ChildDashboardScreen extends StatefulWidget {
  const ChildDashboardScreen({super.key});

  @override
  State<ChildDashboardScreen> createState() => _ChildDashboardScreenState();
}

class _ChildDashboardScreenState extends State<ChildDashboardScreen> {
  late ContentBloc _contentBloc;
  final ValueNotifier<({int stars, int badges, int completedMissionsCount})>
  _statsNotifier =
      ValueNotifier<({int stars, int badges, int completedMissionsCount})>((
        stars: 0,
        badges: 0,
        completedMissionsCount: 0,
      ));
  String? _childId;
  String? _childCode;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _syncService = sl<SyncService>();
    _initChildAndSync();
    unawaited(CharacterAssetCache.instance.prewarm());
  }

  Future<void> _initChildAndSync() async {
    final cachedChild = await sl<AuthLocalDataSource>().getLastChild();
    final childId =
        cachedChild?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (mounted && childId != null) {
      setState(() {
        _childId = childId;
        _childCode = cachedChild?.childCode;
      });
    }

    final isConnected = await sl<NetworkInfo>().isConnected;
    if (!isConnected) {
      _syncService.syncState.value = const SyncStatusState(
        status: SyncStatus.offline,
        message: 'وضع عدم الاتصال (أوفلاين)',
      );
    }

    _contentBloc.add(const ContentEvent.getWorlds());
    await _fetchProgress();

    _syncService.syncState.addListener(_onSyncStateChanged);
  }

  void _onSyncStateChanged() {
    // Sync errors and success are now completely silent to the child.
    // The top status bar icon (cloud) alone will reflect the current state.
  }

  Future<void> _fetchProgress() async {
    if (_childId == null) {
      final cachedChild = await sl<AuthLocalDataSource>().getLastChild();
      _childId =
          cachedChild?.id ?? Supabase.instance.client.auth.currentUser?.id;
    }

    if (_childId != null) {
      final result = await sl<ContentRepository>().getCompletedMissions(
        _childId!,
      );
      result.fold((_) {}, (progressList) {
        int stars = 0;
        int badges = 0;
        for (var p in progressList) {
          stars += p.starsReward ?? 0;
          if (p.badgeName != null && p.badgeName!.isNotEmpty) {
            badges++;
          }
        }
        // Only notify stats listener; does NOT rebuild worlds list
        _statsNotifier.value = (
          stars: stars,
          badges: badges,
          completedMissionsCount: progressList.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _syncService.syncState.removeListener(_onSyncStateChanged);
    _statsNotifier.dispose();
    _contentBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'عوالم المغامرات',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1.2,
                  color: Color(0xFF2C3E50),
                ),
              ),
              if (_childCode != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'كود الربط: $_childCode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _childCode!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'تم نسخ كود الربط بنجاح!',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: const Color(0xFF2ECC71),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppColors.border_radius,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          centerTitle: false,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.8),
                  Colors.white.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          actions: [
            ValueListenableBuilder<
              ({int stars, int badges, int completedMissionsCount})
            >(
              valueListenable: _statsNotifier,
              builder: (context, stats, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Stars
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${stats.stars}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE67E22),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Badges
                    GestureDetector(
                      onTap: () {
                        context
                            .push('/child/badges')
                            .then((_) => _fetchProgress());
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppColors.border_radius,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              size: 22,
                              color: Color(0xFF9B59B6),
                            ),
                            Text(
                              ' ${stats.badges}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF9B59B6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<SyncStatusState>(
              valueListenable: _syncService.syncState,
              builder: (context, syncState, _) {
                IconData icon;
                if (syncState.isOffline ||
                    syncState.status == SyncStatus.error) {
                  icon = Icons.cloud_off_rounded;
                } else if (syncState.status == SyncStatus.syncing) {
                  icon = Icons.cloud_sync_rounded;
                } else {
                  icon = Icons.cloud_done_rounded;
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 22, color: Colors.black),
                    if (syncState.status == SyncStatus.syncing)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(width: 5),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: InkWell(
                onTap: () => showLogoutBottomSheet(context),
                child: const Icon(
                  Icons.more_vert,
                  color: Colors.black,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE0F7FA), Color(0xFFF3E5F5), Color(0xFFFFF3E0)],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: BlocBuilder<ContentBloc, ContentState>(
                  builder: (context, state) {
                    return state.maybeWhen(
                      loading: () => const ShimmerLoading(),
                      error: (msg) => Center(
                        child: Text(
                          'خطأ: $msg',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      worldsLoaded: (worlds) {
                        Future<void> _handleRefresh() async {
                          HapticFeedback.mediumImpact();
                          _contentBloc.add(const ContentEvent.getWorlds());
                          if (_childId != null) {
                            _syncService.syncAll(
                              childId: _childId,
                              silent: true,
                            );
                          }
                          await Future.delayed(
                            const Duration(milliseconds: 800),
                          );
                        }

                        if (worlds.isEmpty) {
                          return RefreshIndicator(
                            onRefresh: _handleRefresh,
                            color: const Color(0xFF9B59B6),
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  child: const Center(
                                    child: Text(
                                      'لا توجد عوالم بعد. احبس أنفاسك واسحب للأسفل للتحديث!',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ValueListenableBuilder<
                          ({int stars, int badges, int completedMissionsCount})
                        >(
                          valueListenable: _statsNotifier,
                          builder: (context, stats, child) {
                            return RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: const Color(0xFF9B59B6),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                cacheExtent: 500,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                itemCount: worlds.length,
                                itemBuilder: (context, index) {
                                  final world = worlds[index];
                                  final bool isLocked =
                                      index > 0 &&
                                      stats.completedMissionsCount <
                                          (index * 2);

                                  return RepaintBoundary(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (isLocked) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'أكمل العالم السابق لفتح هذا العالم!',
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }
                                        HapticFeedback.lightImpact();
                                        context.push(
                                          '/child/world-missions',
                                          extra: world,
                                        );
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 24,
                                        ),
                                        height: 200,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            AppColors.border_radius,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isLocked
                                                  ? Colors.black.withOpacity(
                                                      0.05,
                                                    )
                                                  : Colors.black.withOpacity(
                                                      0.15,
                                                    ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          children: [
                                            // Background Image with Offline Support
                                            if (world.imageUrl.isNotEmpty)
                                              ColorFiltered(
                                                colorFilter: isLocked
                                                    ? const ColorFilter.matrix([
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0,
                                                        0,
                                                        0,
                                                        1,
                                                        0,
                                                      ])
                                                    : const ColorFilter.mode(
                                                        Colors.transparent,
                                                        BlendMode.multiply,
                                                      ),
                                                child: OfflineAwareImage(
                                                  imageUrl: world.imageUrl,
                                                  height: double.infinity,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            else
                                              Container(
                                                color: isLocked
                                                    ? Colors.grey
                                                    : const Color(0xFF3498DB),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.public,
                                                    size: 80,
                                                    color: Colors.white30,
                                                  ),
                                                ),
                                              ),

                                            // Vibrant Overlay (Darker if locked)
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.black.withOpacity(
                                                        isLocked ? 0.95 : 0.85,
                                                      ),
                                                      Colors.black.withOpacity(
                                                        isLocked ? 0.6 : 0.2,
                                                      ),
                                                      isLocked
                                                          ? Colors.black
                                                                .withOpacity(
                                                                  0.4,
                                                                )
                                                          : Colors.transparent,
                                                    ],
                                                    begin:
                                                        Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Decorative elements (stars or lock)
                                            Positioned(
                                              top: isLocked ? 20 : -20,
                                              right: isLocked ? 20 : -20,
                                              child: Icon(
                                                isLocked
                                                    ? Icons.lock_rounded
                                                    : Icons.star_rounded,
                                                size: isLocked ? 40 : 100,
                                                color: Colors.white.withOpacity(
                                                  isLocked ? 0.8 : 0.1,
                                                ),
                                              ),
                                            ),

                                            // Lock overlay text in the center
                                            if (isLocked)
                                              Center(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black45,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'مغلق - أكمل العالم السابق',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                            // Content
                                            Positioned(
                                              bottom: 20,
                                              left: 20,
                                              right: 20,
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          world.title,
                                                          style: TextStyle(
                                                            color: isLocked
                                                                ? Colors.white70
                                                                : Colors.white,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            letterSpacing: 1.1,
                                                            shadows: const [
                                                              Shadow(
                                                                color: Colors
                                                                    .black54,
                                                                blurRadius: 4,
                                                                offset: Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Text(
                                                          world.description,
                                                          style: TextStyle(
                                                            color: isLocked
                                                                ? Colors.white54
                                                                : Colors.white
                                                                      .withOpacity(
                                                                        0.9,
                                                                      ),
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}
