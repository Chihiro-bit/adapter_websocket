import 'dart:async';

import 'websocket_message.dart';

/// Allows interception of messages sent or received through [WebSocketClient].
///
/// Implementations can inspect, modify or replace messages. Returning a new
/// [WebSocketMessage] from either method will cause that message to be used in
/// place of the original.
abstract class WebSocketInterceptor {
  /// Called before a message is sent. The returned [WebSocketMessage] will be
  /// forwarded to the underlying adapter.
  FutureOr<WebSocketMessage> onSend(WebSocketMessage message) => message;

  /// Called for each incoming message before it is exposed via
  /// [WebSocketClient.messageStream]. The returned message will be emitted to
  /// listeners.
  FutureOr<WebSocketMessage> onReceive(WebSocketMessage message) => message;
}
