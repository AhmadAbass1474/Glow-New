import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/child_profile_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel userToCache);
  Future<UserModel?> getLastUser();
  Future<void> cacheChild(ChildProfileModel childToCache);
  Future<ChildProfileModel?> getLastChild();
  Future<void> cacheParentSelectedChild(String childId);
  Future<String?> getParentSelectedChild();
  Future<void> clearCache();
  Future<void> forgetUser();
  Future<void> saveParentChildLogin({
    required String childId,
    required String email,
    required String password,
  });
  Future<({String email, String password})?> parentChildLogin(String childId);
}

const CACHED_USER = 'CACHED_USER';
const CACHED_CHILD = 'CACHED_CHILD';
const PARENT_SELECTED_CHILD = 'PARENT_SELECTED_CHILD';
const PARENT_CHILD_LOGINS = 'PARENT_CHILD_LOGINS';

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final Box box;

  AuthLocalDataSourceImpl(this.box);

  @override
  Future<void> cacheUser(UserModel userToCache) async {
    final jsonString = json.encode(userToCache.toJson());
    await box.put(CACHED_USER, jsonString);
  }

  @override
  Future<UserModel?> getLastUser() async {
    final jsonString = box.get(CACHED_USER);
    if (jsonString != null) {
      return UserModel.fromJson(json.decode(jsonString));
    }
    return null;
  }

  @override
  Future<void> cacheChild(ChildProfileModel childToCache) async {
    final jsonString = json.encode(childToCache.toJson());
    await box.put(CACHED_CHILD, jsonString);
  }

  @override
  Future<ChildProfileModel?> getLastChild() async {
    final jsonString = box.get(CACHED_CHILD);
    if (jsonString != null) {
      return ChildProfileModel.fromJson(json.decode(jsonString));
    }
    return null;
  }

  @override
  Future<void> cacheParentSelectedChild(String childId) async {
    await box.put(PARENT_SELECTED_CHILD, childId);
  }

  @override
  Future<String?> getParentSelectedChild() async {
    final value = box.get(PARENT_SELECTED_CHILD);
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  @override
  Future<void> clearCache() async {
    await box.delete(CACHED_USER);
    await box.delete(CACHED_CHILD);
    await box.delete(PARENT_SELECTED_CHILD);
    await box.delete(PARENT_CHILD_LOGINS);
  }

  @override
  Future<void> forgetUser() async {
    await box.delete(CACHED_USER);
  }

  @override
  Future<void> saveParentChildLogin({
    required String childId,
    required String email,
    required String password,
  }) async {
    final current = _readParentLogins();
    current[childId] = {'email': email, 'password': password};
    await box.put(PARENT_CHILD_LOGINS, json.encode(current));
  }

  @override
  Future<({String email, String password})?> parentChildLogin(String childId) async {
    final row = _readParentLogins()[childId];
    if (row == null) return null;
    final email = row['email'] ?? '';
    final password = row['password'] ?? '';
    if (email.isEmpty || password.isEmpty) return null;
    return (email: email, password: password);
  }

  Map<String, Map<String, String>> _readParentLogins() {
    final raw = box.get(PARENT_CHILD_LOGINS);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): {
              'email': (entry.value['email'] ?? '').toString(),
              'password': (entry.value['password'] ?? '').toString(),
            },
      };
    } catch (_) {
      return {};
    }
  }
}
