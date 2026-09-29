import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

import '../../core/network/network_info.dart';
import '../../core/services/resource_manager.dart';
import '../../features/auth/data/account_transfer.dart';
import '../../features/auth/data/child_account_service.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_admin_usecase.dart';
import '../../features/auth/domain/usecases/register_child_usecase.dart';
import '../../features/auth/domain/usecases/register_parent_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

import '../../features/content/data/datasources/content_remote_data_source.dart';
import '../../features/content/data/datasources/content_local_data_source.dart';
import '../../features/content/data/repositories/content_repository_impl.dart';
import '../../features/content/data/services/sync_service.dart';
import '../../features/dashboard/data/child_activity.dart';
import '../../features/content/domain/repositories/content_repository.dart';
import '../../features/content/domain/usecases/world_usecases.dart';
import '../../features/content/domain/usecases/mission_usecases.dart';
import '../../features/content/domain/usecases/story_usecases.dart';
import '../../features/content/domain/usecases/question_usecases.dart';
import '../../features/content/presentation/bloc/content_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  
  const secureStorage = FlutterSecureStorage();
  sl.registerLazySingleton(() => secureStorage);

  sl.registerLazySingleton(() => Supabase.instance.client);
  
  final authBox = Hive.box('auth');
  sl.registerLazySingleton(() => authBox);

  const reachabilityTimeout = Duration(milliseconds: 700);
  final connectionChecker = InternetConnectionChecker.createInstance(
    checkTimeout: reachabilityTimeout,
    addresses: [
      AddressCheckOption(
        uri: Uri.parse('https://sqvbbsqmwktxuapwivnk.supabase.co/auth/v1/health'),
        timeout: reachabilityTimeout,
      ),
    ],
  );
  sl.registerLazySingleton(() => connectionChecker);
  sl.registerLazySingleton(() => Connectivity());

  // Core
  sl.registerLazySingleton<NetworkInfo>(
    () => NetworkInfoImpl(sl(), sl()),
  );

  // Core - Services
  final resourceBox = Hive.box('resource_cache_meta');
  final resourceManager = ResourceManager(resourceBox);
  await resourceManager.init();
  sl.registerLazySingleton<ResourceManager>(() => resourceManager);

  // Features - Auth
  // Data Sources
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(sl()),
  );
  
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(sl()),
  );
  
  // Repositories
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      networkInfo: sl(),
    ),
  );
  
  // Use Cases
  sl.registerLazySingleton(() => RegisterChildUseCase(sl()));
  sl.registerLazySingleton(() => RegisterParentUseCase(sl()));
  sl.registerLazySingleton(() => LoginAdminUseCase(sl()));
  
  // Blocs
  sl.registerFactory(() => AuthBloc(
    registerChild: sl(),
    registerParent: sl(),
    loginAdmin: sl(),
  ));

  // Features - Content
  // Data Sources
  sl.registerLazySingleton<ContentRemoteDataSource>(
    () => ContentRemoteDataSourceImpl(sl()),
  );

  sl.registerLazySingleton(
    () => ChildActivityLogger(
      Hive.box('content_pending_sync'),
      sl(),
      sl(),
    ),
  );

  sl.registerLazySingleton<ContentLocalDataSource>(
    () => ContentLocalDataSourceImpl(
      worldsBox: Hive.box('content_worlds'),
      missionsBox: Hive.box('content_missions'),
      storiesBox: Hive.box('content_stories'),
      questionsBox: Hive.box('content_questions'),
      progressBox: Hive.box('content_progress'),
      pendingBox: Hive.box('content_pending_sync'),
    ),
  );

  // Repositories
  sl.registerLazySingleton<ContentRepository>(
    () => ContentRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      networkInfo: sl(),
      resourceManager: sl(),
    ),
  );

  sl.registerLazySingleton<AccountTransfer>(
    () => AccountTransfer(
      accounts: sl(),
      supabase: sl(),
      networkInfo: sl(),
    ),
  );

  sl.registerLazySingleton<ChildAccountService>(
    () => ChildAccountService(
      box: sl(),
      supabase: sl(),
      networkInfo: sl(),
      localDataSource: sl(),
      contentLocalDataSource: sl(),
    ),
  );

  // Services
  sl.registerLazySingleton<SyncService>(
    () => SyncService(
      remoteDataSource: sl(),
      localDataSource: sl(),
      resourceManager: sl(),
      networkInfo: sl(),
      connectionChecker: sl(),
      preferences: sl(),
    ),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetWorldsUseCase(sl()));
  sl.registerLazySingleton(() => AddWorldUseCase(sl()));
  sl.registerLazySingleton(() => UpdateWorldUseCase(sl()));
  sl.registerLazySingleton(() => DeleteWorldUseCase(sl()));

  sl.registerLazySingleton(() => GetMissionsUseCase(sl()));
  sl.registerLazySingleton(() => AddMissionUseCase(sl()));
  sl.registerLazySingleton(() => UpdateMissionUseCase(sl()));
  sl.registerLazySingleton(() => DeleteMissionUseCase(sl()));

  sl.registerLazySingleton(() => GetStoriesUseCase(sl()));
  sl.registerLazySingleton(() => AddStoryUseCase(sl()));
  sl.registerLazySingleton(() => UpdateStoryUseCase(sl()));
  sl.registerLazySingleton(() => DeleteStoryUseCase(sl()));

  sl.registerLazySingleton(() => GetQuestionsUseCase(sl()));
  sl.registerLazySingleton(() => AddQuestionUseCase(sl()));
  sl.registerLazySingleton(() => UpdateQuestionUseCase(sl()));
  sl.registerLazySingleton(() => DeleteQuestionUseCase(sl()));

  sl.registerLazySingleton(() => CompleteMissionUseCase(sl()));
  sl.registerLazySingleton(() => GetCompletedMissionsUseCase(sl()));

  // Blocs
  sl.registerFactory(
    () => ContentBloc(
      getWorlds: sl(),
      addWorld: sl(),
      getMissions: sl(),
      addMission: sl(),
      getStories: sl(),
      addStory: sl(),
      getQuestions: sl(),
      addQuestion: sl(),
      completeMission: sl(),
      getCompletedMissions: sl(),
      updateWorld: sl(),
      deleteWorld: sl(),
      updateMission: sl(),
      deleteMission: sl(),
      updateStory: sl(),
      deleteStory: sl(),
      updateQuestion: sl(),
      deleteQuestion: sl(),
    ),
  );
}
