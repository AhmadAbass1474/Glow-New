import 'dart:async';
import 'core/services/character_asset_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/di/injection_container.dart' as di;
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

const _whiteNavigationBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.white,
  systemNavigationBarDividerColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(_whiteNavigationBar);
  unawaited(CharacterAssetCache.instance.prewarm());

  await Supabase.initialize(
    url: 'https://sqvbbsqmwktxuapwivnk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNxdmJic3Ftd2t0eHVhcHdpdm5rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxMzY3NTAsImV4cCI6MjEwNDcxMjc1MH0.w4rUqvb8eXZ77x6nHiDX004jPdctHX7CJLVdVVEaOnI',
  );

  await Hive.initFlutter();
  await Hive.openBox('auth');
  await Hive.openBox('content_worlds');
  await Hive.openBox('content_missions');
  await Hive.openBox('content_stories');
  await Hive.openBox('content_questions');
  await Hive.openBox('content_progress');
  await Hive.openBox('content_pending_sync');
  await Hive.openBox('resource_cache_meta');

  await di.init();

  runApp(const GlowApp());
}

class GlowApp extends StatelessWidget {
  const GlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [BlocProvider(create: (_) => di.sl<AuthBloc>())],
      child: MaterialApp.router(
        title: 'رحلة الأبطال',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: AppRouter.router,
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _whiteNavigationBar,
            child: Directionality(
              textDirection: TextDirection.rtl, // For Arabic UI
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
