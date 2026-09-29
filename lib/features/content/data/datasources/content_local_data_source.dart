import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/world_model.dart';
import '../models/mission_model.dart';
import '../models/story_model.dart';
import '../models/question_model.dart';
import '../models/child_progress_model.dart';

abstract class ContentLocalDataSource {
  // Worlds
  Future<void> cacheWorlds(List<WorldModel> worlds);
  Future<List<WorldModel>> getCachedWorlds();

  // Missions
  Future<void> cacheMissions(String worldId, List<MissionModel> missions);
  Future<List<MissionModel>> getCachedMissions(String worldId);
  Future<List<MissionModel>> getAllCachedMissions();

  // Stories
  Future<void> cacheStories(String missionId, List<StoryModel> stories);
  Future<List<StoryModel>> getCachedStories(String missionId);
  Future<List<StoryModel>> getAllCachedStories();

  // Questions
  Future<void> cacheQuestions(String missionId, List<QuestionModel> questions);
  Future<List<QuestionModel>> getCachedQuestions(String missionId);

  // Child Progress
  Future<void> cacheChildProgress(String childId, List<ChildProgressModel> progressList);
  Future<List<ChildProgressModel>> getCachedChildProgress(String childId);
  Future<void> saveLocalCompletedMission({
    required String childId,
    required String missionId,
    String? missionTitle,
    String? badgeName,
    int? starsReward,
  });

  // Pending Offline Sync Queue
  Future<void> addPendingCompletion(String childId, String missionId);
  Future<List<Map<String, String>>> getPendingCompletions();
  Future<void> removePendingCompletion(String childId, String missionId);
  Future<void> clearPendingCompletions();
  Future<void> reassignChildId(String fromId, String toId);
}

class ContentLocalDataSourceImpl implements ContentLocalDataSource {
  final Box worldsBox;
  final Box missionsBox;
  final Box storiesBox;
  final Box questionsBox;
  final Box progressBox;
  final Box pendingBox;

  ContentLocalDataSourceImpl({
    required this.worldsBox,
    required this.missionsBox,
    required this.storiesBox,
    required this.questionsBox,
    required this.progressBox,
    required this.pendingBox,
  });

  // Worlds
  @override
  Future<void> cacheWorlds(List<WorldModel> worlds) async {
    final list = worlds.map((w) => w.toJson()).toList();
    await worldsBox.put('all_worlds', json.encode(list));
  }

  @override
  Future<List<WorldModel>> getCachedWorlds() async {
    final raw = worldsBox.get('all_worlds') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => WorldModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  // Missions
  @override
  Future<void> cacheMissions(String worldId, List<MissionModel> missions) async {
    final list = missions.map((m) => m.toJson()).toList();
    await missionsBox.put('missions_$worldId', json.encode(list));

    // Also update all_missions cache
    final existingAll = await getAllCachedMissions();
    final Map<String, MissionModel> map = {for (var m in existingAll) m.id: m};
    for (var m in missions) {
      map[m.id] = m;
    }
    final allList = map.values.map((m) => m.toJson()).toList();
    await missionsBox.put('all_missions', json.encode(allList));
  }

  @override
  Future<List<MissionModel>> getCachedMissions(String worldId) async {
    final raw = missionsBox.get('missions_$worldId') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => MissionModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<MissionModel>> getAllCachedMissions() async {
    final raw = missionsBox.get('all_missions') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => MissionModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  // Stories
  @override
  Future<void> cacheStories(String missionId, List<StoryModel> stories) async {
    final list = stories.map((s) => s.toJson()).toList();
    await storiesBox.put('stories_$missionId', json.encode(list));
  }

  @override
  Future<List<StoryModel>> getCachedStories(String missionId) async {
    final raw = storiesBox.get('stories_$missionId') as String?;
    return _decodeStories(raw);
  }

  @override
  Future<List<StoryModel>> getAllCachedStories() async {
    final stories = <StoryModel>[];
    for (final key in storiesBox.keys) {
      if (key is! String || !key.startsWith('stories_')) continue;
      stories.addAll(_decodeStories(storiesBox.get(key) as String?));
    }
    return stories;
  }

  List<StoryModel> _decodeStories(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .map((item) => StoryModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Questions
  @override
  Future<void> cacheQuestions(String missionId, List<QuestionModel> questions) async {
    final list = questions.map((q) => q.toJson()).toList();
    await questionsBox.put('questions_$missionId', json.encode(list));
  }

  @override
  Future<List<QuestionModel>> getCachedQuestions(String missionId) async {
    final raw = questionsBox.get('questions_$missionId') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => QuestionModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  // Child Progress
  @override
  Future<void> cacheChildProgress(String childId, List<ChildProgressModel> progressList) async {
    final list = progressList.map((p) => p.toLocalJson()).toList();
    await progressBox.put('progress_$childId', json.encode(list));
  }

  @override
  Future<List<ChildProgressModel>> getCachedChildProgress(String childId) async {
    final raw = progressBox.get('progress_$childId') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => ChildProgressModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveLocalCompletedMission({
    required String childId,
    required String missionId,
    String? missionTitle,
    String? badgeName,
    int? starsReward,
  }) async {
    final existing = await getCachedChildProgress(childId);
    // Check if already in progress list
    final alreadyCompleted = existing.any((p) => p.missionId == missionId);
    if (!alreadyCompleted) {
      final newProgress = ChildProgressModel(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        childId: childId,
        missionId: missionId,
        completedAt: DateTime.now(),
        missionTitle: missionTitle,
        badgeName: badgeName,
        starsReward: starsReward,
      );
      existing.insert(0, newProgress);
      await cacheChildProgress(childId, existing);
    }
  }

  // Pending Offline Sync Queue
  @override
  Future<void> addPendingCompletion(String childId, String missionId) async {
    final existing = await getPendingCompletions();
    final exists = existing.any((e) => e['child_id'] == childId && e['mission_id'] == missionId);
    if (!exists) {
      existing.add({'child_id': childId, 'mission_id': missionId});
      await pendingBox.put('pending_list', json.encode(existing));
    }
  }

  @override
  Future<List<Map<String, String>>> getPendingCompletions() async {
    final raw = pendingBox.get('pending_list') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((item) => Map<String, String>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> removePendingCompletion(String childId, String missionId) async {
    final existing = await getPendingCompletions();
    existing.removeWhere((e) => e['child_id'] == childId && e['mission_id'] == missionId);
    await pendingBox.put('pending_list', json.encode(existing));
  }

  @override
  Future<void> clearPendingCompletions() async {
    await pendingBox.delete('pending_list');
  }

  @override
  Future<void> reassignChildId(String fromId, String toId) async {
    if (fromId == toId) return;
    final progress = await getCachedChildProgress(fromId);
    if (progress.isNotEmpty) {
      final kept = await getCachedChildProgress(toId);
      final seen = kept.map((item) => item.missionId).toSet();
      for (final item in progress) {
        if (!seen.add(item.missionId)) continue;
        kept.add(ChildProgressModel(
          id: item.id,
          childId: toId,
          missionId: item.missionId,
          completedAt: item.completedAt,
          missionTitle: item.missionTitle,
          badgeName: item.badgeName,
          starsReward: item.starsReward,
        ));
      }
      await cacheChildProgress(toId, kept);
      await progressBox.delete('progress_$fromId');
    }

    final pending = await getPendingCompletions();
    var changed = false;
    for (var index = 0; index < pending.length; index++) {
      if (pending[index]['child_id'] != fromId) continue;
      pending[index] = {
        'child_id': toId,
        'mission_id': pending[index]['mission_id'] ?? '',
      };
      changed = true;
    }
    if (changed) {
      await pendingBox.put('pending_list', json.encode(pending));
    }
  }
}
