import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_info.dart';
import '../../../core/utils/device_id_helper.dart';
import 'child_account_service.dart';
import 'models/child_profile_model.dart';
import 'models/device_child_account.dart';

/// One-time move of the signed-in child onto another phone.
///
/// The QR holds a short code only. The camera and the poll live only while
/// that screen is open.
class AccountTransfer {
  AccountTransfer({
    required ChildAccountService accounts,
    required SupabaseClient supabase,
    required NetworkInfo networkInfo,
  }) : _accounts = accounts,
       _supabase = supabase,
       _networkInfo = networkInfo;

  static const prefix = 'gtx:';
  static const lifetime = Duration(minutes: 3);

  final ChildAccountService _accounts;
  final SupabaseClient _supabase;
  final NetworkInfo _networkInfo;

  Future<TransferTicket> issue(DeviceChildAccount account) async {
    if (!await _networkInfo.isConnected) {
      throw StateError('offline');
    }
    await _accounts.prepareForSync();
    final current = _accounts.currentAccount ?? account;
    if (!current.linkedRemotely || current.isLocalOnly) {
      throw StateError('offline');
    }
    if (!await _accounts.ensureSession(current.id)) {
      throw StateError('session');
    }
    final code = _code();
    final row = await _supabase
        .from('account_transfers')
        .insert({
          'child_id': current.id,
          'code': code,
          'expires_at': DateTime.now().toUtc().add(lifetime).toIso8601String(),
        })
        .select('id')
        .single();
    return TransferTicket(
      id: row['id'] as String,
      childId: current.id,
      code: code,
      expiresAt: DateTime.now().add(lifetime),
    );
  }

  /// One column. The sheet stops calling this as soon as it closes.
  Future<bool> isClaimed(String transferId) async {
    final row = await _supabase
        .from('account_transfers')
        .select('consumed_at')
        .eq('id', transferId)
        .maybeSingle();
    return row != null && row['consumed_at'] != null;
  }

  Future<void> claim(String raw) async {
    final code = _parse(raw);
    if (code == null) throw StateError('code');
    if (!await _networkInfo.isConnected) throw StateError('offline');
    final deviceId = await DeviceIdHelper.getDeviceId();
    var slot = _accounts.freeSlot();
    Map<String, dynamic> payload;
    try {
      payload = await _claim(code, deviceId, slot);
    } catch (error) {
      if (slot.isNotEmpty || !_slotTaken(error)) rethrow;
      slot = _accounts.extraSlot();
      payload = await _claim(code, deviceId, slot);
    }
    await _supabase.auth.signInWithPassword(
      email: DeviceIdHelper.emailFor(deviceId, slot),
      password: DeviceIdHelper.passwordFor(deviceId, slot),
    );
    await _accounts.rememberExisting(
      child: ChildProfileModel.fromJson(payload),
      slot: slot,
      upload: false,
    );
  }

  Future<Map<String, dynamic>> _claim(
    String code,
    String deviceId,
    String slot,
  ) async {
    final result = await _supabase.rpc(
      'claim_account_transfer',
      params: {'p_code': code, 'p_device_id': deviceId, 'p_slot': slot},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  String? _parse(String raw) {
    final value = raw.trim();
    if (!value.startsWith(prefix)) return null;
    final code = value.substring(prefix.length);
    if (code.length < 20 || code.length > 80) return null;
    return code;
  }

  bool _slotTaken(Object error) => error.toString().contains('slot_taken');

  String _code() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class TransferTicket {
  const TransferTicket({
    required this.id,
    required this.childId,
    required this.code,
    required this.expiresAt,
  });

  final String id;
  final String childId;
  final String code;
  final DateTime expiresAt;

  String get payload => '${AccountTransfer.prefix}$code';
}
