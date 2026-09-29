import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../../../core/utils/device_id_helper.dart';
import '../models/child_profile_model.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<ChildProfileModel> registerChild({
    required String name,
    required int age,
    required String avatarUrl,
  });

  Future<UserModel> registerParent({
    required String email,
    required String password,
    required String childCode,
  });

  Future<UserModel> loginAdmin({
    required String email,
    required String password,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient supabaseClient;

  AuthRemoteDataSourceImpl(this.supabaseClient);

  String _generateChildCode() {
    final random = Random();
    final code = random.nextInt(9999).toString().padLeft(4, '0');
    return 'CH-$code';
  }

  @override
  Future<ChildProfileModel> registerChild({
    required String name,
    required int age,
    required String avatarUrl,
  }) async {
    try {
      // 1. Get device ID and generate credentials
      final deviceId = await DeviceIdHelper.getDeviceId();
      final email = DeviceIdHelper.generateDeviceEmail(deviceId);
      final password = DeviceIdHelper.generateDevicePassword(deviceId);

      // 2. Sign up (or sign in if already exists but somehow data was cleared)
      User? user;
      try {
        final authResponse = await supabaseClient.auth.signUp(
          email: email,
          password: password,
        );
        user = authResponse.user;
      } on AuthException catch (e) {
        if (e.message.contains('already registered') || e.message.contains('User already registered')) {
          final authResponse = await supabaseClient.auth.signInWithPassword(
            email: email,
            password: password,
          );
          user = authResponse.user;
        } else {
          rethrow;
        }
      }

      if (user == null) throw Exception('Failed to create device-bound user');

      // Check if profile already exists for this device
      try {
        final existingData = await supabaseClient
            .from('children_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
            
        if (existingData != null) {
          return ChildProfileModel.fromJson(existingData);
        }
      } catch (_) {
        // Ignore and proceed to insert
      }

      // 3. Generate Child Code
      final childCode = _generateChildCode();

      // 4. Save to children_profiles table
      final data = await supabaseClient.from('children_profiles').insert({
        'id': user.id,
        'name': name,
        'age': age,
        'avatar_url': avatarUrl,
        'child_code': childCode,
        'total_stars': 0,
        'total_badges': 0,
      }).select().single();

      return ChildProfileModel.fromJson(data);
    } catch (e) {
      throw Exception('Failed to register child: $e');
    }
  }

  @override
  Future<UserModel> registerParent({
    required String email,
    required String password,
    required String childCode,
  }) async {
    try {
      User? user;
      try {
        final authResponse = await supabaseClient.auth.signUp(
          email: email,
          password: password,
        );
        user = authResponse.user;
      } on AuthException catch (e) {
        if (e.message.contains('already registered')) {
          final authResponse = await supabaseClient.auth.signInWithPassword(
            email: email,
            password: password,
          );
          user = authResponse.user;
        } else {
          rethrow;
        }
      }

      if (user == null) throw Exception('Failed to sign up parent');

      final code = childCode.trim();
      if (code.isNotEmpty) {
        await supabaseClient.rpc('link_parent_to_child', params: {
          'p_parent_id': user.id,
          'p_child_code': code,
        });
      }

      // 3. Assuming parents are also in a users table or we just construct the model
      return UserModel(id: user.id, email: email, role: 'parent');
    } catch (e) {
      throw Exception('Failed to register parent: $e');
    }
  }

  @override
  Future<UserModel> loginAdmin({
    required String email,
    required String password,
  }) async {
    try {
      User? user;
      try {
        final authResponse = await supabaseClient.auth.signInWithPassword(
          email: email,
          password: password,
        );
        user = authResponse.user;
      } on AuthException catch (e) {
        if (e.message.contains('Invalid login credentials')) {
          // Auto-create the admin if they don't exist
          final authResponse = await supabaseClient.auth.signUp(
            email: email,
            password: password,
          );
          user = authResponse.user;
          if (user != null) {
            // Promote to admin immediately via RPC to bypass RLS
            await supabaseClient.rpc('make_me_admin');
          }
        } else {
          rethrow;
        }
      }

      if (user == null) throw Exception('Failed to login admin');

      // Check role
      final data = await supabaseClient
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();

      if (data['role'] != 'admin') {
        await supabaseClient.auth.signOut();
        throw Exception('Unauthorized access. Admins only.');
      }

      return UserModel(id: user.id, email: email, role: 'admin');
    } catch (e) {
      throw Exception('Failed to login admin: $e');
    }
  }
}
