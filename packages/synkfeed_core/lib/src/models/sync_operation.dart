class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payload,
    required this.clientSequence,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.status = 'pending',
    this.errorCode,
  });

  final String operationId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operationType;
  final Map<String, Object?> payload;
  final int clientSequence;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String status;
  final String? errorCode;

  SyncOperation copyWith({
    String? operationId,
    String? deviceId,
    String? entityType,
    String? entityId,
    String? operationType,
    Map<String, Object?>? payload,
    int? clientSequence,
    DateTime? createdAt,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? status,
    String? errorCode,
  }) {
    return SyncOperation(
      operationId: operationId ?? this.operationId,
      deviceId: deviceId ?? this.deviceId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      clientSequence: clientSequence ?? this.clientSequence,
      createdAt: createdAt ?? this.createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'operation_id': operationId,
      'device_id': deviceId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation_type': operationType,
      'payload_json': payload,
      'client_sequence': clientSequence,
      'created_at': createdAt.toUtc().toIso8601String(),
      'attempt_count': attemptCount,
      'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
      'status': status,
      'error_code': errorCode,
    };
  }

  static SyncOperation fromMap(Map<String, Object?> map) {
    final payload = map['payload_json'];
    return SyncOperation(
      operationId: map['operation_id'] as String,
      deviceId: map['device_id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operationType: map['operation_type'] as String,
      payload: payload is Map<String, Object?> ? payload : <String, Object?>{},
      clientSequence: map['client_sequence'] as int? ?? 0,
      createdAt:
          _parseDate(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      attemptCount: map['attempt_count'] as int? ?? 0,
      lastAttemptAt: _parseDate(map['last_attempt_at']),
      status: map['status'] as String? ?? 'pending',
      errorCode: map['error_code'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
