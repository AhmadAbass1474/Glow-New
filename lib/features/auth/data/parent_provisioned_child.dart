import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/injection_container.dart';
import 'datasources/auth_local_data_source.dart';

class ProvisionedChildLogin {
  const ProvisionedChildLogin({
    required this.childId,
    required this.name,
    required this.email,
    required this.password,
  });

  final String childId;
  final String name;
  final String email;
  final String password;

  String get qrPayload => 'gpa:$email|$password';
}

class ParentProvisionedChild {
  ParentProvisionedChild(this._client);

  final SupabaseClient _client;

  static ProvisionedChildLogin? parse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('gpa:')) return null;
    final body = trimmed.substring(4);
    final split = body.split('|');
    if (split.length != 2) return null;
    final email = split[0].trim();
    final password = split[1].trim();
    if (email.isEmpty || password.isEmpty) return null;
    return ProvisionedChildLogin(
      childId: '',
      name: '',
      email: email,
      password: password,
    );
  }

  Future<ProvisionedChildLogin> create({
    required String name,
    required int age,
  }) async {
    final refresh = _client.auth.currentSession?.refreshToken;
    final parentId = _client.auth.currentUser?.id;
    final parent = await sl<AuthLocalDataSource>().getLastUser();
    if (refresh == null || parentId == null) {
      throw Exception('جلسة ولي الأمر انتهت');
    }
    final stamp = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    final email = 'pchild.$stamp@glow.app';
    final password = 'P$stamp-glow';
    final code = 'CH-${(Random().nextInt(9000) + 1000)}';
    try {
      User? user;
      try {
        user = (await _client.auth.signUp(email: email, password: password)).user;
      } on AuthException catch (error) {
        final message = error.message.toLowerCase();
        if (!message.contains('already')) rethrow;
      }
      if (_client.auth.currentUser?.id != user?.id) {
        user = (await _client.auth.signInWithPassword(
          email: email,
          password: password,
        )).user;
      }
      if (user == null) throw Exception('تعذر إنشاء الحساب');
      await _client.from('children_profiles').insert({
        'id': user.id,
        'name': name,
        'age': age,
        'avatar_url': 'fort_frontal.glb',
        'child_code': code,
        'total_stars': 0,
        'total_badges': 0,
      });
      await _client.rpc('attach_my_parent', params: {'p_parent_id': parentId});
      await sl<AuthLocalDataSource>().saveParentChildLogin(
        childId: user.id,
        email: email,
        password: password,
      );
      return ProvisionedChildLogin(
        childId: user.id,
        name: name,
        email: email,
        password: password,
      );
    } finally {
      await _client.auth.setSession(refresh);
      if (parent != null) {
        await sl<AuthLocalDataSource>().cacheUser(parent);
      }
    }
  }
}
