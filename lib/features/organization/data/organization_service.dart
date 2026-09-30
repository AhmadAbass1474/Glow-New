import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/di/injection_container.dart';
import '../../auth/data/datasources/auth_local_data_source.dart';
import '../../auth/data/models/user_model.dart';

class OrgTeacher {
  const OrgTeacher({required this.id, required this.name});

  final String id;
  final String name;
}

class OrgStudent {
  const OrgStudent({
    required this.id,
    required this.name,
    required this.age,
    required this.stars,
  });

  final String id;
  final String name;
  final int age;
  final int stars;
}

class PendingStudentInvite {
  const PendingStudentInvite({
    required this.name,
    required this.age,
    required this.code,
  });

  final String name;
  final int age;
  final String code;
}

class StudentInvitePreview {
  const StudentInvitePreview({required this.name, required this.age});

  final String name;
  final int age;
}

class OrganizationService {
  OrganizationService(this._client);

  final SupabaseClient _client;

  static const studentPrefix = 'gst:';

  Future<void> createOrganizationAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final refresh = _client.auth.currentSession?.refreshToken;
    final admin = await sl<AuthLocalDataSource>().getLastUser();
    if (refresh == null) throw Exception('جلسة الأدمن انتهت');
    try {
      final created = await _signInOrUp(email: email, password: password);
      if (_client.auth.currentUser?.id != created.id) {
        await _client.auth.signInWithPassword(email: email, password: password);
      }
      await _client.from('organizations').upsert({
        'id': created.id,
        'name': name,
      });
    } finally {
      await _client.auth.setSession(refresh);
      if (admin != null) {
        await sl<AuthLocalDataSource>().cacheUser(admin);
      }
    }
  }

  Future<String> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) throw Exception('تعذر الدخول');
    final role = await _roleOf(user.id);
    if (role == null) throw Exception('هذا الحساب ليس منظمة ولا معلماً');
    await _remember(user.id, email, role);
    return role;
  }

  Future<void> addTeacher({
    required String name,
    required String email,
    required String password,
  }) async {
    final refresh = _client.auth.currentSession?.refreshToken;
    final orgId = _client.auth.currentUser?.id;
    if (refresh == null || orgId == null) {
      throw Exception('جلسة المنظمة انتهت');
    }
    try {
      final created = await _signInOrUp(email: email, password: password);
      if (_client.auth.currentUser?.id != created.id) {
        await _client.auth.signInWithPassword(email: email, password: password);
      }
      await _client.from('organization_teachers').upsert({
        'id': created.id,
        'organization_id': orgId,
        'name': name,
      });
    } finally {
      await _client.auth.setSession(refresh);
    }
  }

  Future<String> organizationName() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return '';
    final row = await _client
        .from('organizations')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    return row?['name'] as String? ?? '';
  }

  Future<String> teacherName() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return '';
    final row = await _client
        .from('organization_teachers')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    return row?['name'] as String? ?? '';
  }

  Future<List<OrgTeacher>> teachers() async {
    final orgId = _client.auth.currentUser?.id;
    if (orgId == null) return const [];
    final rows = await _client
        .from('organization_teachers')
        .select('id, name')
        .eq('organization_id', orgId)
        .order('name');
    return [
      for (final row in rows)
        OrgTeacher(id: row['id'] as String, name: row['name'] as String? ?? ''),
    ];
  }

  Future<List<OrgStudent>> studentsOf(String teacherId) async {
    final rows = await _client
        .from('children_profiles')
        .select('id, name, age, total_stars')
        .eq('teacher_id', teacherId)
        .order('name');
    return [
      for (final row in rows)
        OrgStudent(
          id: row['id'] as String,
          name: row['name'] as String? ?? '',
          age: (row['age'] as num?)?.toInt() ?? 0,
          stars: (row['total_stars'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<List<PendingStudentInvite>> pendingInvites() async {
    final teacherId = _client.auth.currentUser?.id;
    if (teacherId == null) return const [];
    final rows = await _client
        .from('student_invites')
        .select('name, age, code')
        .eq('teacher_id', teacherId)
        .filter('student_id', 'is', null)
        .order('created_at');
    return [
      for (final row in rows)
        PendingStudentInvite(
          name: row['name'] as String? ?? '',
          age: (row['age'] as num?)?.toInt() ?? 0,
          code: row['code'] as String? ?? '',
        ),
    ];
  }

  Future<String> createStudentInvite({
    required String name,
    required int age,
  }) async {
    final teacherId = _client.auth.currentUser?.id;
    if (teacherId == null) throw Exception('جلسة المعلم انتهت');
    final teacher = await _client
        .from('organization_teachers')
        .select('organization_id')
        .eq('id', teacherId)
        .single();
    final code = _inviteCode();
    await _client.from('student_invites').insert({
      'organization_id': teacher['organization_id'],
      'teacher_id': teacherId,
      'name': name,
      'age': age,
      'code': code,
    });
    return code;
  }

  Future<StudentInvitePreview> previewInvite(String raw) async {
    final code = _codeFrom(raw);
    final rows = await _client.rpc('preview_student_invite', params: {
      'p_code': code,
    });
    if (rows is! List || rows.isEmpty) {
      throw Exception('الرمز غير صالح أو استُخدم من قبل');
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return StudentInvitePreview(
      name: row['name'] as String? ?? '',
      age: (row['age'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> claimInvite(String raw) async {
    await _client.rpc('claim_student_invite', params: {
      'p_code': _codeFrom(raw),
    });
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await sl<AuthLocalDataSource>().clearCache();
  }

  Future<User> _signInOrUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user != null) return user;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (!message.contains('already')) rethrow;
    }
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) throw Exception('تعذر إنشاء الحساب');
    return user;
  }

  Future<String?> _roleOf(String userId) async {
    final org = await _client
        .from('organizations')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (org != null) return 'organization';
    final teacher = await _client
        .from('organization_teachers')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (teacher != null) return 'teacher';
    return null;
  }

  Future<void> _remember(String id, String email, String role) {
    return sl<AuthLocalDataSource>().cacheUser(
      UserModel(id: id, email: email, role: role),
    );
  }

  String _inviteCode() {
    final value = Random().nextInt(900000) + 100000;
    return 'ST-$value';
  }

  String _codeFrom(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith(studentPrefix)) {
      return trimmed.substring(studentPrefix.length).trim();
    }
    return trimmed;
  }
}
