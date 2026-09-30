import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/network_info.dart';
import '../../../core/utils/device_id_helper.dart';
import '../../content/data/datasources/content_local_data_source.dart';
import 'datasources/auth_local_data_source.dart';
import 'models/child_profile_model.dart';
import 'models/device_child_account.dart';

/// Children that share one phone.
///
/// The list lives on the device so switching works offline. When the network
/// is back, each child is created in Supabase and linked in `device_children`.
class ChildAccountService {
  ChildAccountService({
    required Box box,
    required SupabaseClient supabase,
    required NetworkInfo networkInfo,
    required AuthLocalDataSource localDataSource,
    required ContentLocalDataSource contentLocalDataSource,
  }) : _box = box,
       _supabase = supabase,
       _networkInfo = networkInfo,
       _local = localDataSource,
       _content = contentLocalDataSource;

  static const _accountsKey = 'DEVICE_CHILD_ACCOUNTS';
  static const _activeKey = 'ACTIVE_CHILD_ID';

  final Box _box;
  final SupabaseClient _supabase;
  final NetworkInfo _networkInfo;
  final AuthLocalDataSource _local;
  final ContentLocalDataSource _content;
  List<DeviceChildAccount>? _cachedAccounts;
  String? _cachedDeviceId;

  String? get activeId => _box.get(_activeKey) as String?;

  DeviceChildAccount? get currentAccount => _active();

  /// Empty when this phone has no child yet, otherwise a fresh slot.
  String freeSlot() {
    if (_read().isEmpty) return '';
    return _newSlot();
  }

  String extraSlot() => _newSlot();

  /// Removes the account from this phone and keeps another one active when it exists.
  Future<DeviceChildAccount?> forget(String id) async {
    final next = _read().where((item) => item.id != id).toList();
    await _persist(next);
    if (activeId != id) return _active();
    if (next.isEmpty) {
      await _box.delete(_activeKey);
      await _local.clearCache();
      return null;
    }
    final active = next.first;
    await _box.put(_activeKey, active.id);
    await _local.cacheChild(active.toProfile());
    return active;
  }

  Future<String> _deviceId() {
    final cached = _cachedDeviceId;
    if (cached != null) return Future.value(cached);
    return DeviceIdHelper.getDeviceId().then((id) => _cachedDeviceId = id);
  }

  Future<List<DeviceChildAccount>> list() async {
    await adoptCached();
    return _read();
  }

  /// Last child on this phone, including after a cold start with no network.
  Future<ChildProfileModel?> restoreLastChild() async {
    await adoptCached();
    if (await _networkInfo.isConnected) {
      final pending = _read().where((account) => !account.linkedRemotely);
      if (pending.isNotEmpty) {
        await publishPending();
      } else {
        unawaited(pullFromServer());
      }
    }
    final active = _active();
    if (active == null) return null;
    final profile = active.toProfile();
    await _local.cacheChild(profile);
    return profile;
  }

  /// Accounts to show when the child role is chosen.
  Future<List<DeviceChildAccount>> accountsForPicker() async {
    await adoptCached();
    if (await _networkInfo.isConnected) {
      await publishPending();
      await pullFromServer();
    }
    return _read();
  }

  Future<ChildProfileModel> register({
    required String name,
    required int age,
    required String avatarUrl,
  }) async {
    await adoptCached();
    final online = await _networkInfo.isConnected;
    final slot = _read().isEmpty ? '' : _newSlot();
    var account = DeviceChildAccount(
      id: 'local:${const Uuid().v4()}',
      name: name.trim(),
      age: age,
      avatarUrl: avatarUrl,
      childCode: _newChildCode(),
      slot: slot,
      linkedRemotely: false,
    );
    if (online) {
      account = await _createRemote(account);
    }
    await _writeAccount(account, makeActive: true);
    final profile = account.toProfile();
    await _local.cacheChild(profile);
    return profile;
  }

  Future<ChildProfileModel> adoptFromParent({
    required String email,
    required String password,
  }) async {
    await adoptCached();
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) throw Exception('تعذر فتح الحساب');
    final row = await _supabase
        .from('children_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) throw Exception('حساب الطفل غير موجود');
    final account = DeviceChildAccount(
      id: user.id,
      name: row['name'] as String? ?? '',
      age: (row['age'] as num?)?.toInt() ?? 0,
      avatarUrl: row['avatar_url'] as String? ?? 'fort_frontal.glb',
      childCode: row['child_code'] as String? ?? '',
      slot: _newSlot(),
      linkedRemotely: true,
      parentId: row['parent_id'] as String?,
      loginEmail: email,
      loginPassword: password,
    );
    await _writeAccount(account, makeActive: true);
    await _upsertDeviceRow(account);
    final profile = account.toProfile();
    await _local.cacheChild(profile);
    await _local.forgetUser();
    return profile;
  }

  Future<void> activate(DeviceChildAccount account) async {
    var current = _find(account.id) ?? account;
    if (await _networkInfo.isConnected) {
      if (!current.linkedRemotely) {
        current = await _createRemote(current);
      } else {
        await _signIn(current);
        await _upsertDeviceRow(current);
      }
    }
    await _writeAccount(current, makeActive: true);
    await _local.cacheChild(current.toProfile());
  }

  Future<void> rememberExisting({
    required ChildProfileModel child,
    required String slot,
    bool upload = true,
  }) async {
    await _writeAccount(
      DeviceChildAccount.fromProfile(child, slot: slot, linkedRemotely: true),
      makeActive: true,
    );
    await _local.cacheChild(child);
    if (!upload || !await _networkInfo.isConnected) return;
    final saved = _find(child.id);
    if (saved != null) await _upsertDeviceRow(saved);
  }

  /// Creates any offline accounts, then signs in as the active child.
  Future<void> prepareForSync() async {
    if (!await _networkInfo.isConnected) return;
    await publishPending();
    final active = _active();
    if (active == null || active.isLocalOnly) return;
    await ensureSession(active.id);
  }

  /// Signs in as [childId] so progress is uploaded for that child only.
  Future<bool> ensureSession(String childId) async {
    if (childId.startsWith('local:')) return false;
    if (!await _networkInfo.isConnected) return false;
    if (_supabase.auth.currentUser?.id == childId) return true;
    final account = _find(childId);
    if (account == null || !account.linkedRemotely) return false;
    try {
      await _signIn(account);
      return _supabase.auth.currentUser?.id == childId;
    } catch (error) {
      debugPrint('child sign-in failed: $error');
      return false;
    }
  }

  Future<void> publishPending() async {
    if (!await _networkInfo.isConnected) return;
    final pending = _read()
        .where((account) => !account.linkedRemotely)
        .toList();
    for (final account in pending) {
      try {
        final saved = await _createRemote(account);
        await _replace(account.id, saved);
        if (activeId == account.id || activeId == saved.id) {
          await _box.put(_activeKey, saved.id);
          await _local.cacheChild(saved.toProfile());
        }
      } catch (error) {
        debugPrint('publish child failed: $error');
      }
    }
    await _signInActive();
  }

  Future<void> pullFromServer() async {
    if (!await _networkInfo.isConnected) return;
    final deviceId = await _deviceId();
    var user = _supabase.auth.currentUser;
    if (user == null) {
      try {
        final response = await _supabase.auth.signInWithPassword(
          email: DeviceIdHelper.emailFor(deviceId, ''),
          password: DeviceIdHelper.passwordFor(deviceId, ''),
        );
        user = response.user;
      } catch (_) {
        return;
      }
    }
    if (user == null) return;
    await _rememberAuthUser(user, deviceId);
    final self = _find(user.id);
    if (self != null) await _upsertDeviceRow(self);
    try {
      final rows = await _supabase
          .from('device_children')
          .select()
          .eq('device_id', deviceId);
      for (final row in rows) {
        await _mergeRemoteRow(Map<String, dynamic>.from(row as Map));
      }
    } catch (error) {
      debugPrint('device_children unavailable: $error');
    }
    await _signInActive();
  }

  Future<void> _signInActive() async {
    final active = _active();
    if (active == null || !active.linkedRemotely) return;
    if (_supabase.auth.currentUser?.id == active.id) return;
    try {
      await _signIn(active);
    } catch (error) {
      debugPrint('restore active child failed: $error');
    }
  }

  Future<void> adoptCached() async {
    final cached = await _local.getLastChild();
    if (cached == null) return;
    if (_find(cached.id) != null) {
      if (activeId == null) await _box.put(_activeKey, cached.id);
      return;
    }
    await _writeAccount(
      DeviceChildAccount.fromProfile(
        cached,
        slot: cached.id.startsWith('local:') ? _newSlot() : '',
        linkedRemotely: !cached.id.startsWith('local:'),
      ),
      makeActive: activeId == null,
    );
  }

  Future<DeviceChildAccount> _createRemote(DeviceChildAccount account) async {
    final deviceId = await _deviceId();
    final email = DeviceIdHelper.emailFor(deviceId, account.slot);
    final password = DeviceIdHelper.passwordFor(deviceId, account.slot);
    User? user;
    try {
      user = (await _supabase.auth.signUp(
        email: email,
        password: password,
      )).user;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (!message.contains('already')) rethrow;
    }
    if (user == null || _supabase.auth.currentUser?.id != user.id) {
      user = (await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      )).user;
    }
    if (user == null) {
      throw Exception('تعذر إنشاء الحساب');
    }

    final existing = await _supabase
        .from('children_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      final serverName = existing['name'] as String? ?? '';
      final localNewcomer = account.isLocalOnly && account.slot.isEmpty;
      if (localNewcomer && serverName.trim() != account.name.trim()) {
        return _createRemote(account.copyWith(slot: _newSlot()));
      }
      final saved = DeviceChildAccount(
        id: user.id,
        name: serverName.isEmpty ? account.name : serverName,
        age: (existing['age'] as num?)?.toInt() ?? account.age,
        avatarUrl: existing['avatar_url'] as String? ?? account.avatarUrl,
        childCode: existing['child_code'] as String? ?? account.childCode,
        slot: account.slot,
        linkedRemotely: true,
        parentId: existing['parent_id'] as String?,
      );
      if (account.id != saved.id) {
        await _content.reassignChildId(account.id, saved.id);
      }
      await _upsertDeviceRow(saved);
      return saved;
    }

    final inserted = await _supabase
        .from('children_profiles')
        .insert({
          'id': user.id,
          'name': account.name,
          'age': account.age,
          'avatar_url': account.avatarUrl,
          'child_code': account.childCode,
          'total_stars': 0,
          'total_badges': 0,
        })
        .select()
        .single();

    final saved = DeviceChildAccount(
      id: user.id,
      name: inserted['name'] as String? ?? account.name,
      age: (inserted['age'] as num?)?.toInt() ?? account.age,
      avatarUrl: inserted['avatar_url'] as String? ?? account.avatarUrl,
      childCode: inserted['child_code'] as String? ?? account.childCode,
      slot: account.slot,
      linkedRemotely: true,
      parentId: inserted['parent_id'] as String?,
    );
    if (account.id != saved.id) {
      await _content.reassignChildId(account.id, saved.id);
    }
    await _upsertDeviceRow(saved);
    return saved;
  }

  Future<void> _signIn(DeviceChildAccount account) async {
    final email = account.loginEmail;
    final password = account.loginPassword;
    if (email != null &&
        email.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      return;
    }
    final deviceId = await _deviceId();
    await _supabase.auth.signInWithPassword(
      email: DeviceIdHelper.emailFor(deviceId, account.slot),
      password: DeviceIdHelper.passwordFor(deviceId, account.slot),
    );
  }

  Future<void> _upsertDeviceRow(DeviceChildAccount account) async {
    if (account.isLocalOnly) return;
    try {
      final deviceId = await _deviceId();
      await _supabase.from('device_children').upsert({
        'child_id': account.id,
        'device_id': deviceId,
        'slot': account.slot,
        'name': account.name,
        'age': account.age,
        'avatar_url': account.avatarUrl,
        'child_code': account.childCode,
      }, onConflict: 'child_id');
    } catch (error) {
      debugPrint('device_children upsert skipped: $error');
    }
  }

  Future<void> _rememberAuthUser(User user, String deviceId) async {
    final data = await _supabase
        .from('children_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (data == null) return;
    final profile = ChildProfileModel.fromJson(data);
    final slot = _slotFromEmail(user.email, deviceId);
    if (_find(profile.id) != null) return;
    await _writeAccount(
      DeviceChildAccount.fromProfile(profile, slot: slot, linkedRemotely: true),
      makeActive: activeId == null,
    );
  }

  Future<void> _mergeRemoteRow(Map<String, dynamic> row) async {
    final id = row['child_id'] as String?;
    if (id == null || id.isEmpty) return;
    final slot = row['slot'] as String? ?? '';
    final account = DeviceChildAccount(
      id: id,
      name: row['name'] as String? ?? '',
      age: (row['age'] as num?)?.toInt() ?? 0,
      avatarUrl: row['avatar_url'] as String? ?? '',
      childCode: row['child_code'] as String? ?? '',
      slot: slot,
      linkedRemotely: true,
    );
    final bySlot = _read().where(
      (item) => item.slot == slot && item.isLocalOnly,
    );
    if (bySlot.isNotEmpty) {
      await _replace(bySlot.first.id, account);
      return;
    }
    if (_find(id) != null) {
      final existing = _find(id);
      await _replace(
        id,
        account.copyWith(
          loginEmail: existing?.loginEmail,
          loginPassword: existing?.loginPassword,
        ),
      );
      return;
    }
    await _writeAccount(account, makeActive: activeId == null);
  }

  Future<void> _replace(String oldId, DeviceChildAccount saved) async {
    final next =
        _read()
            .where((item) => item.id != oldId && item.id != saved.id)
            .toList()
          ..add(saved);
    await _persist(next);
    if (activeId == oldId) await _box.put(_activeKey, saved.id);
  }

  Future<void> _writeAccount(
    DeviceChildAccount account, {
    required bool makeActive,
  }) async {
    final next = _read().where((item) => item.id != account.id).toList()
      ..add(account);
    await _persist(next);
    if (makeActive || activeId == null) {
      await _box.put(_activeKey, account.id);
    }
  }

  Future<void> _persist(List<DeviceChildAccount> accounts) async {
    _cachedAccounts = accounts;
    await _box.put(
      _accountsKey,
      json.encode(accounts.map((item) => item.toJson()).toList()),
    );
  }

  List<DeviceChildAccount> _read() {
    final cached = _cachedAccounts;
    if (cached != null) return cached;
    final raw = _box.get(_accountsKey) as String?;
    if (raw == null || raw.isEmpty) {
      _cachedAccounts = const [];
      return _cachedAccounts!;
    }
    try {
      final list = json.decode(raw) as List;
      _cachedAccounts = list
          .map(
            (item) => DeviceChildAccount.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      _cachedAccounts = const [];
    }
    return _cachedAccounts!;
  }

  DeviceChildAccount? _find(String id) {
    for (final account in _read()) {
      if (account.id == id) return account;
    }
    return null;
  }

  DeviceChildAccount? _active() {
    final id = activeId;
    if (id == null) return null;
    return _find(id);
  }

  String _slotFromEmail(String? email, String deviceId) {
    if (email == null) return '';
    final prefix = '$deviceId.';
    const suffix = '@glow.app';
    if (email.startsWith(prefix) && email.endsWith(suffix)) {
      return email.substring(prefix.length, email.length - suffix.length);
    }
    return '';
  }

  String _newSlot() {
    return const Uuid().v4().replaceAll('-', '').substring(0, 8);
  }

  String _newChildCode() {
    final code = Random().nextInt(9999).toString().padLeft(4, '0');
    return 'CH-$code';
  }
}
