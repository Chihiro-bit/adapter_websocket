import 'dart:async';
import 'websocket_message.dart';

/// Interface for intercepting WebSocket messages and errors.
abstract class WebSocketInterceptor {
  /// Called before a message is sent. Returning `null` cancels the send.
  FutureOr<WebSocketMessage?> onSend(WebSocketMessage message);

  /// Called when a message is received. Returning `null` stops propagation.
  FutureOr<WebSocketMessage?> onReceive(WebSocketMessage message);

  /// Called when an error occurs in the WebSocket pipeline.
  FutureOr<void> onError(dynamic error);
}
