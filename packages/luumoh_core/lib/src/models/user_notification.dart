class UserNotification {
  const UserNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.actorId,
    this.readAt,
  });

  factory UserNotification.fromMap(Map<String, dynamic> map) {
    return UserNotification(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      actorId: map['actor_id'] as String?,
      type: map['type'] as String? ?? 'general',
      title: map['title'] as String? ?? 'Luumoh update',
      body: map['body'] as String? ?? '',
      data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String userId;
  final String? actorId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;
}
