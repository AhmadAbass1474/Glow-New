import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Import screens (to be created)
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/role_selection_screen.dart';
import '../../features/auth/presentation/screens/child_onboarding_screen.dart';
import '../../features/auth/presentation/screens/parent_auth_screen.dart';
import '../../features/auth/presentation/screens/admin_login_screen.dart';
import '../../features/dashboard/presentation/screens/child_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/parent_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/parent_reports_screen.dart';
import '../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../features/content/presentation/screens/add_world_screen.dart';
import '../../features/content/presentation/screens/world_missions_screen.dart';
import '../../features/content/presentation/screens/add_mission_screen.dart';
import '../../features/content/presentation/screens/mission_stories_screen.dart';
import '../../features/content/presentation/screens/add_story_screen.dart';
import '../../features/content/presentation/screens/story_preview_screen.dart';
import '../../features/content/presentation/screens/mission_questions_screen.dart';
import '../../features/content/presentation/screens/add_question_screen.dart';

// Child Scenario Screens
import '../../features/content/presentation/screens/child_world_missions_screen.dart';
import '../../features/content/presentation/screens/child_story_viewer_screen.dart';
import '../../features/content/presentation/screens/child_quiz_intro_screen.dart';
import '../../features/content/presentation/screens/child_quiz_screen.dart';
import '../../features/content/presentation/screens/child_mission_complete_screen.dart';
import '../../features/content/presentation/screens/child_badges_screen.dart';

import '../../features/content/domain/entities/world_entity.dart';
import '../../features/content/domain/entities/mission_entity.dart';
import '../../features/content/domain/entities/story_entity.dart';
import '../../features/content/domain/entities/question_entity.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/child-onboarding',
        builder: (context, state) => const ChildOnboardingScreen(),
      ),
      GoRoute(
        path: '/child-dashboard',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const ChildDashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 150),
        ),
      ),
      GoRoute(
        path: '/child/story-viewer',
        pageBuilder: (context, state) {
          final mission = state.extra as MissionEntity;
          return CustomTransitionPage(
            child: ChildStoryViewerScreen(mission: mission),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 90),
            reverseTransitionDuration: const Duration(milliseconds: 80),
          );
        },
      ),
      GoRoute(
        path: '/child/world-missions',
        pageBuilder: (context, state) {
          final world = state.extra as WorldEntity;
          return CustomTransitionPage(
            child: ChildWorldMissionsScreen(world: world),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 120),
            reverseTransitionDuration: const Duration(milliseconds: 90),
          );
        },
      ),
      GoRoute(
        path: '/child/quiz',
        pageBuilder: (context, state) {
          final mission = state.extra as MissionEntity;
          return CustomTransitionPage(
            child: ChildQuizScreen(mission: mission),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 150),
          );
        },
      ),
      GoRoute(
        path: '/child/quiz-intro',
        pageBuilder: (context, state) {
          final mission = state.extra as MissionEntity;
          return CustomTransitionPage(
            child: ChildQuizIntroScreen(mission: mission),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 150),
          );
        },
      ),
      GoRoute(
        path: '/child/mission-complete',
        pageBuilder: (context, state) {
          final mission = state.extra as MissionEntity;
          return CustomTransitionPage(
            child: ChildMissionCompleteScreen(mission: mission),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 150),
          );
        },
      ),
      GoRoute(
        path: '/child/badges',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const ChildBadgesScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 150),
        ),
      ),
      GoRoute(
        path: '/parent-auth',
        builder: (context, state) => const ParentAuthScreen(),
      ),
      GoRoute(
        path: '/parent-dashboard',
        builder: (context, state) => const ParentDashboardScreen(),
      ),
      GoRoute(
        path: '/parent/reports',
        builder: (context, state) {
          final args = state.extra;
          return ParentReportsScreen(
            args: args is ParentReportArgs ? args : const ParentReportArgs(),
          );
        },
      ),
      GoRoute(
        path: '/admin-login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/add-world',
        builder: (context, state) {
          final world = state.extra as WorldEntity?;
          return AddWorldScreen(worldToEdit: world);
        },
      ),
      GoRoute(
        path: '/admin/world-missions',
        builder: (context, state) {
          final world = state.extra as WorldEntity;
          return WorldMissionsScreen(world: world);
        },
      ),
      GoRoute(
        path: '/admin/add-mission',
        builder: (context, state) {
          if (state.extra is Map<String, dynamic>) {
            final args = state.extra as Map<String, dynamic>;
            return AddMissionScreen(
              world: args['world'] as WorldEntity,
              missionToEdit: args['missionToEdit'] as MissionEntity?,
            );
          }
          final world = state.extra as WorldEntity;
          return AddMissionScreen(world: world);
        },
      ),
      GoRoute(
        path: '/admin/mission-stories',
        builder: (context, state) {
          final mission = state.extra as MissionEntity;
          return MissionStoriesScreen(mission: mission);
        },
      ),
      GoRoute(
        path: '/admin/story-preview',
        builder: (context, state) {
          final story = state.extra as StoryEntity;
          return StoryPreviewScreen(story: story);
        },
      ),
      GoRoute(
        path: '/admin/add-story',
        builder: (context, state) {
          if (state.extra is Map<String, dynamic>) {
            final args = state.extra as Map<String, dynamic>;
            return AddStoryScreen(
              mission: args['mission'] as MissionEntity,
              storyToEdit: args['storyToEdit'] as StoryEntity?,
            );
          }
          final mission = state.extra as MissionEntity;
          return AddStoryScreen(mission: mission);
        },
      ),
      GoRoute(
        path: '/admin/mission-questions',
        builder: (context, state) {
          final mission = state.extra as MissionEntity;
          return MissionQuestionsScreen(mission: mission);
        },
      ),
      GoRoute(
        path: '/admin/add-question',
        builder: (context, state) {
          if (state.extra is Map<String, dynamic>) {
            final args = state.extra as Map<String, dynamic>;
            return AddQuestionScreen(
              mission: args['mission'] as MissionEntity,
              questionToEdit: args['questionToEdit'] as QuestionEntity?,
            );
          }
          final mission = state.extra as MissionEntity;
          return AddQuestionScreen(mission: mission);
        },
      ),
    ],
  );
}
