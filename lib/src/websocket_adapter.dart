import 'dart:async';
import 'websocket_config.dart';
import 'websocket_message.dart';
import 'websocket_state.dart';

/// Abstract adapter interface for WebSocket implementations
/// This allows for easy switching between different WebSocket libraries
abstract class WebSocketAdapter {
  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream;

  /// Stream of incoming messages
  Stream<WebSocketMessage> get messageStream;

  /// Stream of connection errors
  Stream<dynamic> get errorStream;

  /// Current connection state
  WebSocketState get currentState;

  /// Configuration used for this adapter
  WebSocketConfig get config;

  /// Establishes a WebSocket connection
  Future<void> connect();

  /// Sends a message through the WebSocket
  Future<void> sendMessage(WebSocketMessage message);

  /// Sends raw data through the WebSocket
  Future<void> send(dynamic data);

  /// Closes the WebSocket connection
  Future<void> disconnect([int? code, String? reason]);

  /// Disposes of the adapter and cleans up resources
  Future<void> dispose();

  /// Checks if the connection is currently active
  bool get isConnected => currentState == WebSocketState.connected;

  /// Checks if the connection is in a connecting state
  bool get isConnecting => currentState == WebSocketState.connecting;

  /// Checks if the connection is closed
  bool get isClosed => currentState == WebSocketState.disconnected;
}
