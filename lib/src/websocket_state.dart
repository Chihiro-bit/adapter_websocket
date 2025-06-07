/// Represents the current state of a WebSocket connection
enum WebSocketState {
  /// Connection is being established
  connecting,
  /// Connection is established and ready for communication
  connected,
  /// Connection is being closed
  disconnecting,
  /// Connection is closed
  disconnected,
  /// Connection failed or encountered an error
  error,
}

/// Extension to provide human-readable descriptions
extension WebSocketStateExtension on WebSocketState {
  String get description {
    switch (this) {
      case WebSocketState.connecting:
        return 'Connecting';
      case WebSocketState.connected:
        return 'Connected';
      case WebSocketState.disconnecting:
        return 'Disconnecting';
      case WebSocketState.disconnected:
        return 'Disconnected';
      case WebSocketState.error:
        return 'Error';
    }
  }
}
