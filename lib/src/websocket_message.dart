/// Represents a WebSocket message with metadata
class WebSocketMessage {
  final dynamic data;
  final DateTime timestamp;
  final String? type;
  final Map<String, dynamic>? metadata;

  const WebSocketMessage({
    required this.data,
    required this.timestamp,
    this.type,
    this.metadata,
  });

  /// Creates a message with current timestamp
  factory WebSocketMessage.now({
    required dynamic data,
    String? type,
    Map<String, dynamic>? metadata,
  }) {
    return WebSocketMessage(
      data: data,
      timestamp: DateTime.now(),
      type: type,
      metadata: metadata,
    );
  }

  /// Creates a text message
  factory WebSocketMessage.text(String text) {
    return WebSocketMessage.now(
      data: text,
      type: 'text',
    );
  }

  /// Creates a JSON message
  factory WebSocketMessage.json(Map<String, dynamic> json) {
    return WebSocketMessage.now(
      data: json,
      type: 'json',
    );
  }

  /// Creates a binary message
  factory WebSocketMessage.binary(List<int> bytes) {
    return WebSocketMessage.now(
      data: bytes,
      type: 'binary',
    );
  }

  @override
  String toString() {
    return 'WebSocketMessage(data: $data, timestamp: $timestamp, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebSocketMessage &&
        other.data == data &&
        other.timestamp == timestamp &&
        other.type == type;
  }

  @override
  int get hashCode {
    return data.hashCode ^ timestamp.hashCode ^ type.hashCode;
  }
}
