class NotificationDeliverySummary {
  const NotificationDeliverySummary({
    required this.id,
    required this.notificationId,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.provider,
    required this.status,
    required this.attempts,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.userName,
    this.lastError,
    this.sentAt,
  });

  factory NotificationDeliverySummary.fromMap(Map<String, dynamic> map) {
    return NotificationDeliverySummary(
      id: map['id'] as String,
      notificationId: map['notification_id'] as String,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String?,
      type: map['type'] as String? ?? 'general',
      title: map['title'] as String? ?? 'Luumoh update',
      body: map['body'] as String? ?? '',
      provider: map['provider'] as String? ?? 'test',
      status: map['status'] as String? ?? 'pending',
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastError: map['last_error'] as String?,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? const {}),
      createdAt: DateTime.parse(map['created_at'] as String),
      sentAt: map['sent_at'] == null
          ? null
          : DateTime.parse(map['sent_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String notificationId;
  final String userId;
  final String? userName;
  final String type;
  final String title;
  final String body;
  final String provider;
  final String status;
  final int attempts;
  final String? lastError;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime updatedAt;
}
