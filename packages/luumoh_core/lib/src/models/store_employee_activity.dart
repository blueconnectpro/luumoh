class StoreEmployeeActivity {
  const StoreEmployeeActivity({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.action,
    required this.entityType,
    required this.summary,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.actorRole,
    this.entityId,
    this.metadata = const {},
  });

  factory StoreEmployeeActivity.fromMap(Map<String, dynamic> map) {
    return StoreEmployeeActivity(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      storeName: map['store_name'] as String? ?? 'Store',
      actorId: map['actor_id'] as String?,
      actorName: map['actor_name'] as String?,
      actorRole: map['actor_role'] as String?,
      action: map['action'] as String? ?? 'activity',
      entityType: map['entity_type'] as String? ?? 'record',
      entityId: map['entity_id'] as String?,
      summary: map['summary'] as String? ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? const {}),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String storeId;
  final String storeName;
  final String? actorId;
  final String? actorName;
  final String? actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final String summary;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
}
