import 'child_profile_model.dart';

class DeviceChildAccount {
  final String id;
  final String name;
  final int age;
  final String avatarUrl;
  final String childCode;
  final String slot;
  final bool linkedRemotely;
  final String? parentId;
  final String? loginEmail;
  final String? loginPassword;

  const DeviceChildAccount({
    required this.id,
    required this.name,
    required this.age,
    required this.avatarUrl,
    required this.childCode,
    required this.slot,
    required this.linkedRemotely,
    this.parentId,
    this.loginEmail,
    this.loginPassword,
  });

  bool get isLocalOnly => id.startsWith('local:');

  ChildProfileModel toProfile() {
    return ChildProfileModel(
      id: id,
      name: name,
      age: age,
      avatarUrl: avatarUrl,
      childCode: childCode,
      parentId: parentId,
    );
  }

  DeviceChildAccount copyWith({
    String? id,
    String? name,
    int? age,
    String? avatarUrl,
    String? childCode,
    String? slot,
    bool? linkedRemotely,
    String? parentId,
    String? loginEmail,
    String? loginPassword,
  }) {
    return DeviceChildAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      childCode: childCode ?? this.childCode,
      slot: slot ?? this.slot,
      linkedRemotely: linkedRemotely ?? this.linkedRemotely,
      parentId: parentId ?? this.parentId,
      loginEmail: loginEmail ?? this.loginEmail,
      loginPassword: loginPassword ?? this.loginPassword,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'avatar_url': avatarUrl,
      'child_code': childCode,
      'slot': slot,
      'linked_remotely': linkedRemotely,
      'parent_id': parentId,
      'login_email': loginEmail,
      'login_password': loginPassword,
    };
  }

  factory DeviceChildAccount.fromJson(Map<String, dynamic> json) {
    return DeviceChildAccount(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      age: (json['age'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatar_url'] as String? ?? '',
      childCode: json['child_code'] as String? ?? '',
      slot: json['slot'] as String? ?? '',
      linkedRemotely: json['linked_remotely'] as bool? ?? false,
      parentId: json['parent_id'] as String?,
      loginEmail: json['login_email'] as String?,
      loginPassword: json['login_password'] as String?,
    );
  }

  factory DeviceChildAccount.fromProfile(
    ChildProfileModel profile, {
    required String slot,
    required bool linkedRemotely,
  }) {
    return DeviceChildAccount(
      id: profile.id,
      name: profile.name,
      age: profile.age,
      avatarUrl: profile.avatarUrl,
      childCode: profile.childCode,
      slot: slot,
      linkedRemotely: linkedRemotely,
      parentId: profile.parentId,
    );
  }
}
