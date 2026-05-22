import 'dart:async';
import 'websocket_message.dart';

typedef _TopicSender = Future<void> Function(
    String topic, String event, dynamic payload);

/// A logical sub-channel scoped to a specific [topic] name.
///
/// Messages are exchanged using an envelope format:
/// `{"topic": "<topic>", "event": "<event>", "payload": <payload>}`
///
/// Obtain an instance via [WebSocketClient.channel].
class WebSocketTopic {
  final String topic;
  final _TopicSender _sender;
  final StreamController<WebSocketMessage> _controller =
      StreamController<WebSocketMessage>.broadcast();
  bool _disposed = false;

  WebSocketTopic({required this.topic, required _TopicSender sender})
      : _sender = sender;

  /// Stream of messages received on this topic.
  Stream<WebSocketMessage> get messageStream => _controller.stream;

  bool get isDisposed => _disposed;

  /// Sends [payload] to the server under this topic with the given [event] name.
  Future<void> send(String event, dynamic payload) {
    if (_disposed) throw StateError('Topic "$topic" has been disposed');
    return _sender(topic, event, payload);
  }

  /// Pushes a received message into this topic's stream. Called by [ChannelManager].
  void push(WebSocketMessage message) {
    if (!_disposed && !_controller.isClosed) {
      _controller.add(message);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
