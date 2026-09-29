import 'dart:io';
import 'package:fpdart/fpdart.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/services/resource_manager.dart';
import '../../domain/entities/world_entity.dart';
import '../../domain/entities/mission_entity.dart';
import '../../domain/entities/story_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/child_progress_entity.dart';
import '../../domain/repositories/content_repository.dart';
import '../datasources/content_local_data_source.dart';
import '../datasources/content_remote_data_source.dart';
import '../models/world_model.dart';
import '../models/mission_model.dart';
import '../models/story_model.dart';
import '../models/question_model.dart';

class ContentRepositoryImpl implements ContentRepository {
  final ContentRemoteDataSource remoteDataSource;
  final ContentLocalDataSource localDataSource;
  final NetworkInfo networkInfo;
  final ResourceManager resourceManager;

  ContentRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.networkInfo,
    required this.resourceManager,
  });

  @override
  Future<Either<Failure, List<WorldEntity>>> getWorlds({bool forceRefresh = false}) async {
    final cachedWorlds = await localDataSource.getCachedWorlds();

    if (await networkInfo.isConnected) {
      // Trigger background sync
      remoteDataSource.getWorlds().then((worlds) async {
        await localDataSource.cacheWorlds(worlds);
        for (var w in worlds) {
          if (w.imageUrl.isNotEmpty) {
            resourceManager.downloadAndCacheInBackground(w.imageUrl, folder: 'images');
          }
        }
      }).catchError((_) {});

      if (!forceRefresh && cachedWorlds.isNotEmpty) {
        return Right(cachedWorlds);
      } else {
        try {
          final worlds = await remoteDataSource.getWorlds();
          await localDataSource.cacheWorlds(worlds);
          return Right(worlds);
        } catch (e) {
          if (cachedWorlds.isNotEmpty) {
            return Right(cachedWorlds);
          }
          return const Left(ServerFailure('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.'));
        }
      }
    } else {
      if (cachedWorlds.isNotEmpty) {
        return Right(cachedWorlds);
      }
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت ولا توجد بيانات محفوظة محلياً'));
    }
  }

  @override
  Future<Either<Failure, WorldEntity>> addWorld(WorldEntity world) async {
    if (await networkInfo.isConnected) {
      try {
        final model = WorldModel(
          id: world.id,
          title: world.title,
          description: world.description,
          imageUrl: world.imageUrl,
        );
        final result = await remoteDataSource.addWorld(model);
        // Update local cache
        final current = await localDataSource.getCachedWorlds();
        current.add(result);
        await localDataSource.cacheWorlds(current);
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, List<MissionEntity>>> getMissions(String worldId, {bool forceRefresh = false}) async {
    final cachedMissions = await localDataSource.getCachedMissions(worldId);

    if (await networkInfo.isConnected) {
      // Trigger background sync
      remoteDataSource.getMissions(worldId).then((missions) async {
        await localDataSource.cacheMissions(worldId, missions);
      }).catchError((_) {});

      if (!forceRefresh && cachedMissions.isNotEmpty) {
        return Right(cachedMissions);
      } else {
        try {
          final missions = await remoteDataSource.getMissions(worldId);
          await localDataSource.cacheMissions(worldId, missions);
          return Right(missions);
        } catch (e) {
          if (cachedMissions.isNotEmpty) {
            return Right(cachedMissions);
          }
          return const Left(ServerFailure('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.'));
        }
      }
    } else {
      if (cachedMissions.isNotEmpty) {
        return Right(cachedMissions);
      }
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت ولا توجد مهام محفوظة'));
    }
  }

  @override
  Future<Either<Failure, MissionEntity>> addMission(MissionEntity mission) async {
    if (await networkInfo.isConnected) {
      try {
        final model = MissionModel(
          id: mission.id,
          worldId: mission.worldId,
          title: mission.title,
          badgeName: mission.badgeName,
          starsReward: mission.starsReward,
          orderIndex: mission.orderIndex,
        );
        final result = await remoteDataSource.addMission(model);
        final current = await localDataSource.getCachedMissions(mission.worldId);
        current.add(result);
        await localDataSource.cacheMissions(mission.worldId, current);
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, List<StoryEntity>>> getStories(String missionId, {bool forceRefresh = false}) async {
    final cachedStories = await localDataSource.getCachedStories(missionId);

    if (await networkInfo.isConnected) {
      // Background sync
      remoteDataSource.getStories(missionId).then((stories) async {
        await localDataSource.cacheStories(missionId, stories);
          for (var s in stories) {
            resourceManager.cacheCharacterModels(s.characterName, s.timelineData);
          if (s.audioUrl != null && s.audioUrl!.isNotEmpty) {
            resourceManager.downloadAndCacheInBackground(s.audioUrl!, folder: 'audio');
          }
          if (s.imageUrl.isNotEmpty) {
            resourceManager.downloadAndCacheInBackground(s.imageUrl, folder: 'images');
          }
        }
      }).catchError((_) {});

      if (!forceRefresh && cachedStories.isNotEmpty) {
        return Right(cachedStories);
      } else {
        try {
          final stories = await remoteDataSource.getStories(missionId);
          await localDataSource.cacheStories(missionId, stories);
          return Right(stories);
        } catch (e) {
          if (cachedStories.isNotEmpty) {
            return Right(cachedStories);
          }
          return const Left(ServerFailure('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.'));
        }
      }
    } else {
      if (cachedStories.isNotEmpty) {
        return Right(cachedStories);
      }
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت ولا توجد قصص محفوظة'));
    }
  }

  @override
  Future<Either<Failure, StoryEntity>> addStory(StoryEntity story, {File? audioFile, File? characterFile}) async {
    if (await networkInfo.isConnected) {
      try {
        final model = StoryModel.fromEntity(story);
        final result = await remoteDataSource.addStory(model, audioFile: audioFile, characterFile: characterFile);
        final current = await localDataSource.getCachedStories(story.missionId);
        current.add(result);
        await localDataSource.cacheStories(story.missionId, current);
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, List<QuestionEntity>>> getQuestions(String missionId, {bool forceRefresh = false}) async {
    final cachedQuestions = await localDataSource.getCachedQuestions(missionId);

    if (await networkInfo.isConnected) {
      // Background sync
      remoteDataSource.getQuestions(missionId).then((questions) async {
        await localDataSource.cacheQuestions(missionId, questions);
      }).catchError((_) {});

      if (!forceRefresh && cachedQuestions.isNotEmpty) {
        return Right(cachedQuestions);
      } else {
        try {
          final questions = await remoteDataSource.getQuestions(missionId);
          await localDataSource.cacheQuestions(missionId, questions);
          return Right(questions);
        } catch (e) {
          if (cachedQuestions.isNotEmpty) {
            return Right(cachedQuestions);
          }
          return const Left(ServerFailure('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.'));
        }
      }
    } else {
      if (cachedQuestions.isNotEmpty) {
        return Right(cachedQuestions);
      }
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت ولا توجد أسئلة محفوظة'));
    }
  }

  @override
  Future<Either<Failure, QuestionEntity>> addQuestion(QuestionEntity question) async {
    try {
      final questionModel = QuestionModel(
        id: question.id,
        missionId: question.missionId,
        questionText: question.questionText,
        options: question.options,
        correctAnswerIndex: question.correctAnswerIndex,
      );
      final addedQuestion = await remoteDataSource.addQuestion(questionModel);
      final current = await localDataSource.getCachedQuestions(question.missionId);
      current.add(addedQuestion);
      await localDataSource.cacheQuestions(question.missionId, current);
      return Right(addedQuestion);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> completeMission(String missionId, String childId) async {
    try {
      // 1. Find mission details for badge & stars reward from local cache
      final allMissions = await localDataSource.getAllCachedMissions();
      MissionModel? matchedMission;
      for (var m in allMissions) {
        if (m.id == missionId) {
          matchedMission = m;
          break;
        }
      }

      // 2. Save locally immediately so child progress is updated with 0 latency
      await localDataSource.saveLocalCompletedMission(
        childId: childId,
        missionId: missionId,
        missionTitle: matchedMission?.title,
        badgeName: matchedMission?.badgeName,
        starsReward: matchedMission?.starsReward,
      );

      // 3. Sync to Supabase in background if connected, otherwise queue for later
      if (await networkInfo.isConnected) {
        remoteDataSource.completeMission(missionId, childId).catchError((_) async {
          await localDataSource.addPendingCompletion(childId, missionId);
        });
      } else {
        await localDataSource.addPendingCompletion(childId, missionId);
      }

      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ChildProgressEntity>>> getCompletedMissions(String childId) async {
    final cachedProgress = await localDataSource.getCachedChildProgress(childId);

    if (await networkInfo.isConnected) {
      // Background sync
      remoteDataSource.getCompletedMissions(childId).then((progressList) async {
        final local = await localDataSource.getCachedChildProgress(childId);
        final remoteIds = progressList.map((item) => item.missionId).toSet();
        final kept = local.where((item) => !remoteIds.contains(item.missionId));
        await localDataSource.cacheChildProgress(childId, [
          ...progressList,
          ...kept,
        ]);
      }).catchError((_) {});

      if (cachedProgress.isNotEmpty) {
        return Right(cachedProgress);
      } else {
        try {
          final progressList = await remoteDataSource.getCompletedMissions(childId);
          await localDataSource.cacheChildProgress(childId, progressList);
          return Right(progressList);
        } catch (e) {
          if (cachedProgress.isNotEmpty) {
            return Right(cachedProgress);
          }
          return Left(ServerFailure(e.toString()));
        }
      }
    } else {
      return Right(cachedProgress);
    }
  }

  @override
  Future<Either<Failure, WorldEntity>> updateWorld(WorldEntity world) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.updateWorld(WorldModel.fromEntity(world));
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteWorld(String id) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.deleteWorld(id);
        return const Right(null);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, MissionEntity>> updateMission(MissionEntity mission) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.updateMission(MissionModel.fromEntity(mission));
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteMission(String id) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.deleteMission(id);
        return const Right(null);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, StoryEntity>> updateStory(StoryEntity story, {File? audioFile, File? characterFile}) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.updateStory(
          StoryModel.fromEntity(story),
          audioFile: audioFile,
          characterFile: characterFile,
        );
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteStory(String id) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.deleteStory(id);
        return const Right(null);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, QuestionEntity>> updateQuestion(QuestionEntity question) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.updateQuestion(QuestionModel.fromEntity(question));
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteQuestion(String id) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.deleteQuestion(id);
        return const Right(null);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    } else {
      return const Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
    }
  }
}
