import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/audio/child_button_clips.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/utils/device_id_helper.dart';
import '../../data/child_account_service.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/models/child_profile_model.dart';
import '../../../content/data/services/sync_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    unawaited(ChildButtonVoice.warm());
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final localDataSource = sl<AuthLocalDataSource>();
    final cachedUser = await localDataSource.getLastUser();

    if (cachedUser != null) {
      if (!mounted) return;
      if (cachedUser.role == 'admin') {
        _go('/admin-dashboard');
      } else {
        _go('/parent-dashboard');
      }
      return;
    }

    final restored = await sl<ChildAccountService>().restoreLastChild();
    final cachedChild = restored ?? await localDataSource.getLastChild();
    final isConnected = await sl<NetworkInfo>().isConnected;

    if (!isConnected) {
      if (cachedChild != null) {
        if (mounted) _go('/child-dashboard');
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'يجب الاتصال بالإنترنت في أول تشغيل للتطبيق لتنزيل المحتوى.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _revealStartButton();
      }
      return;
    }

    if (cachedChild != null) {
      unawaited(_syncChildIfNeeded(cachedChild.id));
      sl<SyncService>().prefetchCachedStoryAudio();
      if (mounted) await _go('/child-dashboard');
      return;
    }

    try {
      final deviceId = await DeviceIdHelper.getDeviceId();
      final email = DeviceIdHelper.generateDeviceEmail(deviceId);
      final password = DeviceIdHelper.generateDevicePassword(deviceId);

      final supabase = Supabase.instance.client;
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        final data = await supabase
            .from('children_profiles')
            .select()
            .eq('id', response.user!.id)
            .maybeSingle();

        if (data != null) {
          final child = ChildProfileModel.fromJson(data);
          await sl<ChildAccountService>().rememberExisting(child: child, slot: '');
          await _syncChildIfNeeded(child.id);
          sl<SyncService>().prefetchCachedStoryAudio();
          if (mounted) {
            _go('/child-dashboard');
            return;
          }
        }
      }
    } catch (_) {
      // Silent login failed, proceed to show button
    }

    if (mounted) _revealStartButton();
  }

  Future<void> _go(String route) async {
    await _sayAppName();
    if (!mounted) return;
    context.go(route);
  }

  void _revealStartButton() {
    setState(() => _showButton = true);
    unawaited(_welcomeFirstVisit());
  }

  /// Every splash says the app name from a bundled clip.
  Future<void> _sayAppName() async {
    if (!childButtonClips.containsKey('Glow')) return;
    await ChildButtonVoice.warm();
    await ChildButtonVoice.playSequence(const ['Glow']);
  }

  /// The first time the start button appears, greet the child, say Glow,
  /// then read the button. Later splash visits only say the name.
  Future<void> _welcomeFirstVisit() async {
    const first = ['أهلاً بك', 'Glow', 'ابدأ الرحلة'];
    final box = Hive.box('auth');
    final heard = box.get('SPLASH_WELCOME_HEARD') == true;
    final phrases = heard ? const ['Glow'] : first;
    if (phrases.any((phrase) => !childButtonClips.containsKey(phrase))) return;
    if (!heard) await box.put('SPLASH_WELCOME_HEARD', true);
    await ChildButtonVoice.warm();
    await ChildButtonVoice.playSequence(phrases);
  }

  Future<void> _syncChildIfNeeded(String childId) async {
    final sync = sl<SyncService>();
    if (!await sync.needsSync()) return;
    await sync.syncAll(childId: childId, silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
                  const Spacer(),
                  Image.asset('assets/images/logo.png', width: double.infinity),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _showButton ? 1 : 0,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOut,
                    child: IgnorePointer(
                      ignoring: !_showButton,
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ChildButtonVoice.press('ابدأ الرحلة', () async {
                              if (context.mounted) context.go('/role-selection');
                            });
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'ابدأ الرحلة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
