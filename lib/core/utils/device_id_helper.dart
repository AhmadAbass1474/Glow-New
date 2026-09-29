import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdHelper {
  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'glow_device_id';

  static Future<String> getDeviceId() async {
    // 1. أولاً نبحث عن الـ ID في الـ Secure Storage (Keychain في الايفون)
    // لأن البيانات في الـ Keychain تبقى محفوظة حتى بعد حذف التطبيق.
    String? storedDeviceId = await _storage.read(key: _deviceIdKey);
    
    if (storedDeviceId != null && storedDeviceId.isNotEmpty) {
      return storedDeviceId;
    }

    // 2. إذا لم يكن موجوداً، نقوم بتوليد واحد جديد أو إحضار الخاص بالجهاز
    String newDeviceId;
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    
    if (Platform.isIOS) {
      // في الايفون: الـ identifierForVendor يتغير عند حذف التطبيق
      // لذلك نحفظه في الـ Keychain ليظل ثابتاً للأبد
      final iosDeviceInfo = await deviceInfo.iosInfo;
      newDeviceId = iosDeviceInfo.identifierForVendor ?? const Uuid().v4();
    } else if (Platform.isAndroid) {
      // في الأندرويد عادة يكون ثابتاً
      final androidDeviceInfo = await deviceInfo.androidInfo;
      newDeviceId = androidDeviceInfo.id;
    } else {
      newDeviceId = const Uuid().v4();
    }

    // 3. نحفظه للمرات القادمة حتى لو تم حذف التطبيق
    await _storage.write(key: _deviceIdKey, value: newDeviceId);
    
    return newDeviceId;
  }

  static String generateDeviceEmail(String deviceId) {
    return emailFor(deviceId, '');
  }

  static String generateDevicePassword(String deviceId) {
    return passwordFor(deviceId, '');
  }

  /// Empty [slot] is the first child on this phone. Later children get their own slot.
  static String emailFor(String deviceId, String slot) {
    if (slot.isEmpty) return '$deviceId@glow.app';
    return '$deviceId.$slot@glow.app';
  }

  static String passwordFor(String deviceId, String slot) {
    if (slot.isEmpty) return '${deviceId}_secret_glow_2026';
    return '${deviceId}.${slot}_secret_glow_2026';
  }
}
