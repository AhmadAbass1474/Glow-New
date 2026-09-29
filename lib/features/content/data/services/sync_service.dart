import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../../auth/data/child_account_service.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/audio/admin_phrase_voice.dart';
import '../../../../core/audio/child_button_clips.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/services/resource_manager.dart';
import '../datasources/content_local_data_source.dart';
import '../datasources/content_remote_data_source.dart';

enum SyncStatus { idle, syncing, success, offline, error }

class SyncStatusState {
  final SyncStatus status;
  final String message;
  final int pendingCount;

  const SyncStatusState({
    required this.status,
    required this.message,
    this.pendingCount = 0,
  });

  bool get isSyncing => status == SyncStatus.syncing;
  bool get isOffline => status == SyncStatus.offline;
}

class SyncService {
  final ContentRemoteDataSource remoteDataSource;
  final ContentLocalDataSource localDataSource;
  final ResourceManager resourceManager;
  final NetworkInfo networkInfo;
  final InternetConnectionChecker connectionChecker;
  final SharedPreferences preferences;

  static const _lastSyncKey = 'glow_last_content_sync_ms';
  static const syncFreshFor = Duration(hours: 6);

  final ValueNotifier<SyncStatusState> syncState = ValueNotifier<SyncStatusState>(
    const SyncStatusState(status: SyncStatus.idle, message: 'جاهز'),
  );

  StreamSubscription<InternetConnectionStatus>? _networkSubscription;
  bool _isSyncRunning = false;

  SyncService({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.resourceManager,
    required this.networkInfo,
    required this.connectionChecker,
    required this.preferences,
  });

  /// True when local progress must be uploaded, content is missing,
  /// or the last successful sync is older than [syncFreshFor].
  Future<bool> needsSync() async {
    final pending = await localDataSource.getPendingCompletions();
    if (pending.isNotEmpty) return true;

    final worlds = await localDataSource.getCachedWorlds();
    if (worlds.isEmpty) return true;

    final missions = await localDataSource.getAllCachedMissions();
    if (missions.isEmpty) return true;

    final lastMs = preferences.getInt(_lastSyncKey);
    if (lastMs == null) {
      await preferences.setInt(
        _lastSyncKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      return false;
    }

    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= syncFreshFor;
  }

  /// Downloads story audio that is already known locally. Splash starts this
  /// and continues to the dashboard without waiting for the files.
  void prefetchCachedStoryAudio() {
    unawaited(_prefetchCachedStoryAudio());
  }

  Future<void> _prefetchCachedStoryAudio() async {
    try {
      final stories = await localDataSource.getAllCachedStories();
      final phrases = <String>{};
      final worlds = await localDataSource.getCachedWorlds();
      final missions = await localDataSource.getAllCachedMissions();
      for (final world in worlds) {
        phrases.add(world.title);
      }
      for (final mission in missions) {
        phrases.add(mission.title);
        phrases.add(mission.badgeName);
        final questions = await localDataSource.getCachedQuestions(mission.id);
        for (final question in questions) {
          phrases.addAll(question.options);
        }
      }
      for (final story in stories) {
        phrases.add(story.title);
      }
      await Future.wait([
        ...stories.map((story) {
          final url = story.audioUrl?.trim() ?? '';
          if (!url.startsWith('http')) return Future<void>.value();
          return resourceManager.downloadAndCacheFile(url, folder: 'audio');
        }),
        ...phrases
            .map((phrase) => phrase.trim())
            .where(
              (phrase) =>
                  phrase.isNotEmpty && !childButtonClips.containsKey(phrase),
            )
            .map(
              (phrase) => resourceManager.downloadAndCacheFile(
                AdminPhraseVoice.urlFor(phrase),
                folder: 'audio',
              ),
            ),
      ]);
    } catch (error) {
      debugPrint('Story audio prefetch failed: $error');
    }
  }

  void startAutoSyncListener({String? childId}) {
    _networkSubscription?.cancel();
    _networkSubscription = connectionChecker.onStatusChange.listen((status) {
      if (status == InternetConnectionStatus.connected) {
        syncAll(childId: childId, silent: true);
      } else {
        syncState.value = const SyncStatusState(
          status: SyncStatus.offline,
          message: 'وضع عدم الاتصال (أوفلاين) - الموارد متاحة محلياً',
        );
      }
    });
  }

  void stopAutoSyncListener() {
    _networkSubscription?.cancel();
    _networkSubscription = null;
  }

  DateTime? _lastSyncTime;

  Future<void> syncAll({String? childId, bool silent = false}) async {
    if (_isSyncRunning) return;

    // Throttle silent background syncs if synced recently (within 30 seconds)
    if (silent && _lastSyncTime != null && DateTime.now().difference(_lastSyncTime!).inSeconds < 30) {
      return;
    }

    _isSyncRunning = true;

    final isConnected = await networkInfo.isConnected;
    if (!isConnected) {
      syncState.value = const SyncStatusState(
        status: SyncStatus.offline,
        message: 'وضع عدم الاتصال (أوفلاين) - الموارد متاحة محلياً',
      );
      _isSyncRunning = false;
      return;
    }

    if (!silent) {
      syncState.value = const SyncStatusState(
        status: SyncStatus.syncing,
        message: 'جارٍ تنزيل وتحديث المغامرات والموارد...',
      );
    }

    try {
      // 1. Upload pending completions for the child who earned them.
      final accounts = GetIt.instance<ChildAccountService>();
      try {
        await accounts.prepareForSync();
      } catch (error) {
        debugPrint('child account sync skipped: $error');
      }
      final pending = await localDataSource.getPendingCompletions();
      for (var item in pending) {
        final cId = item['child_id'];
        final mId = item['mission_id'];
        if (cId == null || mId == null) continue;
        if (!await accounts.ensureSession(cId)) continue;
        try {
          await remoteDataSource.completeMission(mId, cId);
          await localDataSource.removePendingCompletion(cId, mId);
        } catch (e) {
          syncState.value = SyncStatusState(
            status: SyncStatus.error,
            message: 'تعذر رفع الإنجازات لسوبابيز. تأكد من إعدادات الأمان (RLS):\n$e',
          );
          _isSyncRunning = false;
          return;
        }
      }

      // 2. Sync Worlds and collect media tasks
      final remoteWorlds = await remoteDataSource.getWorlds();
      await localDataSource.cacheWorlds(remoteWorlds);
      
      final List<Future> mediaTasks = [];
      for (var world in remoteWorlds) {
        if (world.imageUrl.isNotEmpty) {
          mediaTasks.add(resourceManager.downloadAndCacheFile(world.imageUrl, folder: 'images'));
        }
      }

      // 3. Parallel Sync for Worlds, Missions, Stories, Questions
      await Future.wait(remoteWorlds.map((world) async {
        final remoteMissions = await remoteDataSource.getMissions(world.id);
        await localDataSource.cacheMissions(world.id, remoteMissions);

        await Future.wait(remoteMissions.map((mission) async {
          try {
            final storiesFuture = remoteDataSource.getStories(mission.id);
            final questionsFuture = remoteDataSource.getQuestions(mission.id);
            final remoteStories = await storiesFuture;
            final remoteQuestions = await questionsFuture;

            await localDataSource.cacheStories(mission.id, remoteStories);
            await localDataSource.cacheQuestions(mission.id, remoteQuestions);

            for (var story in remoteStories) {
              resourceManager.cacheCharacterModels(story.characterName, story.timelineData);
              if (story.audioUrl != null && story.audioUrl!.isNotEmpty) {
                mediaTasks.add(resourceManager.downloadAndCacheFile(story.audioUrl!, folder: 'audio'));
              }
              if (story.imageUrl.isNotEmpty) {
                mediaTasks.add(resourceManager.downloadAndCacheFile(story.imageUrl, folder: 'images'));
              }
            }
          } catch (e) {
            debugPrint('Failed to sync mission ${mission.id}: $e');
          }
        }));
      }));

      // 4. Trigger media downloads in background without blocking
      Future.wait(mediaTasks);

      // 5. Sync Child Progress
      if (childId != null && childId.isNotEmpty) {
        final ready = await GetIt.instance<ChildAccountService>().ensureSession(childId);
        if (ready) {
          try {
            final remoteProgress = await remoteDataSource.getCompletedMissions(childId);
            await localDataSource.cacheChildProgress(childId, remoteProgress);
          } catch (_) {}
        }
      }

      _lastSyncTime = DateTime.now();
      await preferences.setInt(
        _lastSyncKey,
        _lastSyncTime!.millisecondsSinceEpoch,
      );

      syncState.value = const SyncStatusState(
        status: SyncStatus.success,
        message: 'تم تحديث وتنزيل جميع الموارد بنجاح ✓',
      );
    } catch (e) {
      syncState.value = SyncStatusState(
        status: SyncStatus.error,
        message: 'حدث خطأ أثناء المزامنة: $e',
      );
    } finally {
      _isSyncRunning = false;
    }
  }

  void dispose() {
    _networkSubscription?.cancel();
    syncState.dispose();
  }
}
