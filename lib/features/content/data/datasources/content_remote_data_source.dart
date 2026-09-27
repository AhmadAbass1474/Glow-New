import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/world_model.dart';
import '../models/mission_model.dart';
import '../models/story_model.dart';
import '../models/question_model.dart';
import '../models/child_progress_model.dart';

abstract class ContentRemoteDataSource {
  // Worlds
  Future<List<WorldModel>> getWorlds();
  Future<WorldModel> addWorld(WorldModel world);
  Future<WorldModel> updateWorld(WorldModel world);
  Future<void> deleteWorld(String id);

  // Missions
  Future<List<MissionModel>> getMissions(String worldId);
  Future<MissionModel> addMission(MissionModel mission);
  Future<MissionModel> updateMission(MissionModel mission);
  Future<void> deleteMission(String id);

  // Stories
  Future<List<StoryModel>> getStories(String missionId);
  Future<StoryModel> addStory(
    StoryModel story, {
    File? audioFile,
    File? characterFile,
  });
  Future<StoryModel> updateStory(
    StoryModel story, {
    File? audioFile,
    File? characterFile,
  });
  Future<void> deleteStory(String id);

  // Questions
  Future<List<QuestionModel>> getQuestions(String missionId);
  Future<QuestionModel> addQuestion(QuestionModel question);
  Future<QuestionModel> updateQuestion(QuestionModel question);
  Future<void> deleteQuestion(String id);

  // Progress
  Future<void> completeMission(String missionId, String childId);
  Future<List<ChildProgressModel>> getCompletedMissions(String childId);
}

class ContentRemoteDataSourceImpl implements ContentRemoteDataSource {
  final SupabaseClient supabaseClient;

  ContentRemoteDataSourceImpl(this.supabaseClient);

  @override
  Future<List<WorldModel>> getWorlds() async {
    final response = await supabaseClient
        .from('worlds')
        .select()
        .order('created_at', ascending: true);
    return response.map((json) => WorldModel.fromJson(json)).toList();
  }

  @override
  Future<WorldModel> addWorld(WorldModel world) async {
    final response = await supabaseClient
        .from('worlds')
        .insert(world.toJson())
        .select()
        .single();
    return WorldModel.fromJson(response);
  }

  @override
  Future<WorldModel> updateWorld(WorldModel world) async {
    final response = await supabaseClient
        .from('worlds')
        .update(world.toJson())
        .eq('id', world.id)
        .select()
        .single();
    return WorldModel.fromJson(response);
  }

  @override
  Future<void> deleteWorld(String id) async {
    await supabaseClient.from('worlds').delete().eq('id', id);
  }

  @override
  Future<List<MissionModel>> getMissions(String worldId) async {
    final response = await supabaseClient
        .from('missions')
        .select()
        .eq('world_id', worldId)
        .order('order_index', ascending: true);
    return response.map((json) => MissionModel.fromJson(json)).toList();
  }

  @override
  Future<MissionModel> addMission(MissionModel mission) async {
    final response = await supabaseClient
        .from('missions')
        .insert(mission.toJson())
        .select()
        .single();
    return MissionModel.fromJson(response);
  }

  @override
  Future<MissionModel> updateMission(MissionModel mission) async {
    final response = await supabaseClient
        .from('missions')
        .update(mission.toJson())
        .eq('id', mission.id)
        .select()
        .single();
    return MissionModel.fromJson(response);
  }

  @override
  Future<void> deleteMission(String id) async {
    await supabaseClient.from('missions').delete().eq('id', id);
  }

  @override
  Future<List<StoryModel>> getStories(String missionId) async {
    final response = await supabaseClient
        .from('stories')
        .select()
        .eq('mission_id', missionId)
        .order('order_index', ascending: true);
    return response.map((json) => StoryModel.fromJson(json)).toList();
  }

  @override
  Future<StoryModel> addStory(
    StoryModel story, {
    File? audioFile,
    File? characterFile,
  }) async {
    String? audioUrl = story.audioUrl;

    if (audioFile != null) {
      final ext = audioFile.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_audio.$ext';
      await supabaseClient.storage.from('story_audio').upload(
            fileName,
            audioFile,
            fileOptions: FileOptions(contentType: _audioContentType(ext)),
          );
      audioUrl = supabaseClient.storage
          .from('story_audio')
          .getPublicUrl(fileName);
    }

    String characterName = story.characterName;
    if (characterFile != null) {
      final ext = characterFile.path.split('.').last;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_character.$ext';
      await supabaseClient.storage
          .from('story_characters')
          .upload(fileName, characterFile);
      final publicUrl = supabaseClient.storage
          .from('story_characters')
          .getPublicUrl(fileName);
          
      if (characterName.startsWith('custom|')) {
        final parts = characterName.split('|');
        if (parts.length >= 3) {
          final colorKey = parts[1];
          final customName = parts[2];
          characterName = '$publicUrl?color=$colorKey&name=${Uri.encodeComponent(customName)}';
        } else {
          characterName = publicUrl;
        }
      } else {
        characterName = publicUrl;
      }
    }

    final storyToSave = StoryModel(
      id: story.id,
      missionId: story.missionId,
      title: story.title,
      content: story.content,
      characterName: characterName,
      imageUrl: story.imageUrl,
      orderIndex: story.orderIndex,
      audioUrl: audioUrl,
      timelineData: story.timelineData,
    );

    final response = await supabaseClient
        .from('stories')
        .insert(storyToSave.toJson())
        .select()
        .single();
    return StoryModel.fromJson(response);
  }

  @override
  Future<StoryModel> updateStory(
    StoryModel story, {
    File? audioFile,
    File? characterFile,
  }) async {
    String? audioUrl = story.audioUrl;

    if (audioFile != null) {
      final ext = audioFile.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_audio.$ext';
      await supabaseClient.storage.from('story_audio').upload(
            fileName,
            audioFile,
            fileOptions: FileOptions(contentType: _audioContentType(ext)),
          );
      audioUrl = supabaseClient.storage
          .from('story_audio')
          .getPublicUrl(fileName);
    }

    String characterName = story.characterName;
    if (characterFile != null) {
      final ext = characterFile.path.split('.').last;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_character.$ext';
      await supabaseClient.storage
          .from('story_characters')
          .upload(fileName, characterFile);
      final publicUrl = supabaseClient.storage
          .from('story_characters')
          .getPublicUrl(fileName);
          
      if (characterName.startsWith('custom|')) {
        final parts = characterName.split('|');
        if (parts.length >= 3) {
          final colorKey = parts[1];
          final customName = parts[2];
          characterName = '$publicUrl?color=$colorKey&name=${Uri.encodeComponent(customName)}';
        } else {
          characterName = publicUrl;
        }
      } else {
        characterName = publicUrl;
      }
    }

    final storyToSave = StoryModel(
      id: story.id,
      missionId: story.missionId,
      title: story.title,
      content: story.content,
      characterName: characterName,
      imageUrl: story.imageUrl,
      orderIndex: story.orderIndex,
      audioUrl: audioUrl,
      timelineData: story.timelineData,
    );

    final response = await supabaseClient
        .from('stories')
        .update(storyToSave.toJson())
        .eq('id', storyToSave.id)
        .select()
        .single();
    return StoryModel.fromJson(response);
  }

  @override
  Future<void> deleteStory(String id) async {
    await supabaseClient.from('stories').delete().eq('id', id);
  }

  @override
  Future<List<QuestionModel>> getQuestions(String missionId) async {
    final response = await supabaseClient
        .from('questions')
        .select()
        .eq('mission_id', missionId);
    return response.map((json) => QuestionModel.fromJson(json)).toList();
  }

  @override
  Future<QuestionModel> addQuestion(QuestionModel question) async {
    final response = await supabaseClient
        .from('questions')
        .insert(question.toJson())
        .select()
        .single();
    return QuestionModel.fromJson(response);
  }

  @override
  Future<QuestionModel> updateQuestion(QuestionModel question) async {
    final response = await supabaseClient
        .from('questions')
        .update(question.toJson())
        .eq('id', question.id)
        .select()
        .single();
    return QuestionModel.fromJson(response);
  }

  @override
  Future<void> deleteQuestion(String id) async {
    await supabaseClient.from('questions').delete().eq('id', id);
  }

  @override
  Future<void> completeMission(String missionId, String childId) async {
    // Check if already completed to avoid infinite star farming
    final existing = await supabaseClient
        .from('child_progress')
        .select()
        .eq('child_id', childId)
        .eq('mission_id', missionId)
        .maybeSingle();

    if (existing == null) {
      // First time completion! Let's award stars and badges to the profile.
      final mission = await supabaseClient
          .from('missions')
          .select('stars_reward, badge_name')
          .eq('id', missionId)
          .single();

      int starsReward = mission['stars_reward'] ?? 0;
      int badgeCount =
          (mission['badge_name'] != null &&
              mission['badge_name'].toString().trim().isNotEmpty)
          ? 1
          : 0;

      // Fetch current profile stats safely
      final childProfile = await supabaseClient
          .from('children_profiles')
          .select('*')
          .eq('id', childId)
          .single();

      int currentStars = childProfile['total_stars'] ?? 0;
      int currentBadges = childProfile['total_badges'] ?? 0;

      // Update profile
      await supabaseClient
          .from('children_profiles')
          .update({
            'total_stars': currentStars + starsReward,
            'total_badges': currentBadges + badgeCount,
          })
          .eq('id', childId);
          
      // Record progress
      await supabaseClient.from('child_progress').insert({
        'child_id': childId,
        'mission_id': missionId,
      });
    }
  }

  @override
  Future<List<ChildProgressModel>> getCompletedMissions(String childId) async {
    final response = await supabaseClient
        .from('child_progress')
        .select('*, missions(title, badge_name, stars_reward)')
        .eq('child_id', childId)
        .order('completed_at', ascending: false);

    return response.map((json) => ChildProgressModel.fromJson(json)).toList();
  }
}

String _audioContentType(String ext) {
  switch (ext.toLowerCase()) {
    case 'wav':
      return 'audio/wav';
    case 'm4a':
      return 'audio/mp4';
    case 'ogg':
      return 'audio/ogg';
    default:
      return 'audio/mpeg';
  }
}
