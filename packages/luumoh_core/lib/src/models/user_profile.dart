class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.fullName,
    this.phone,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      role: map['role'] as String? ?? 'customer',
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String?,
    );
  }

  final String id;
  final String role;
  final String fullName;
  final String? phone;

  String get displayName => fullName.trim().isEmpty ? id : fullName;
}
