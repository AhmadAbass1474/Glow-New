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
}

const CACHED_USER = 'CACHED_USER';
const CACHED_CHILD = 'CACHED_CHILD';
const PARENT_SELECTED_CHILD = 'PARENT_SELECTED_CHILD';

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
  }

  @override
  Future<void> forgetUser() async {
    await box.delete(CACHED_USER);
  }
}
