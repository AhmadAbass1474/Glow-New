import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/utils/device_id_helper.dart';
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
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final localDataSource = sl<AuthLocalDataSource>();
    final cachedUser = await localDataSource.getLastUser();

    if (cachedUser != null) {
      if (!mounted) return;
      if (cachedUser.role == 'admin') {
        context.go('/admin-dashboard');
      } else {
        context.go('/parent-dashboard');
      }
      return;
    }

    final cachedChild = await localDataSource.getLastChild();
    final isConnected = await sl<NetworkInfo>().isConnected;

    if (!isConnected) {
      if (cachedChild != null) {
        if (mounted) context.go('/child-dashboard');
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
        setState(() => _showButton = true);
      }
      return;
    }

    if (cachedChild != null) {
      await _syncChildIfNeeded(cachedChild.id);
      if (mounted) context.go('/child-dashboard');
      return;
    }

    try {
      if (mounted) setState(() => _isSyncing = true);
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
          await localDataSource.cacheChild(child);
          await _syncChildIfNeeded(child.id);
          if (mounted) {
            context.go('/child-dashboard');
            return;
          }
        }
      }
    } catch (_) {
      // Silent login failed, proceed to show button
    }

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _showButton = true;
      });
    }
  }

  Future<void> _syncChildIfNeeded(String childId) async {
    final sync = sl<SyncService>();
    if (!await sync.needsSync()) return;
    if (mounted) setState(() => _isSyncing = true);
    await sync.syncAll(childId: childId, silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Image.asset('assets/images/logo.png', width: double.infinity),
                if (_isSyncing) ...[
                  const SizedBox(height: 28),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
                if (_showButton)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.go('/role-selection');
                        },
                        child: const Text('ابدأ الرحلة'),
                      ),
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
