import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../websocket_adapter.dart';
import '../websocket_config.dart';
import '../websocket_message.dart';
import '../websocket_state.dart';

/// WebSocket adapter implementation using the web_socket_channel package
class WebSocketChannelAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;
  
  WebSocketChannel? _channel;
  final StreamController<WebSocketState> _stateController = StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController = StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController = StreamController<dynamic>.broadcast();
  
  WebSocketState _currentState = WebSocketState.disconnected;
  StreamSubscription? _channelSubscription;
  Timer? _connectionTimeoutTimer;

  WebSocketChannelAdapter(this._config);

  @override
  Stream<WebSocketState> get stateStream => _stateController.stream;

  @override
  Stream<WebSocketMessage> get messageStream => _messageController.stream;

  @override
  Stream<dynamic> get errorStream => _errorController.stream;

  @override
  WebSocketState get currentState => _currentState;

  @override
  WebSocketConfig get config => _config;

  @override
  Future<void> connect() async {
    if (_currentState == WebSocketState.connecting || _currentState == WebSocketState.connected) {
      return;
    }

    _updateState(WebSocketState.connecting);

    try {
      final uri = Uri.parse(_config.url);
      
      // Set up connection timeout
      _connectionTimeoutTimer = Timer(_config.connectionTimeout, () {
        if (_currentState == WebSocketState.connecting) {
          _handleError(TimeoutException('Connection timeout', _config.connectionTimeout));
        }
      });
      
      _channel = IOWebSocketChannel.connect(
        uri,
        protocols: _config.protocols,
        headers: _config.headers,
      );

      // Listen to the channel stream
      _channelSubscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Wait for connection to be established
      await _channel!.ready;
      _connectionTimeoutTimer?.cancel();
      _updateState(WebSocketState.connected);
      
    } catch (error) {
      _connectionTimeoutTimer?.cancel();
      _updateState(WebSocketState.error);
      _errorController.add(error);
      rethrow;
    }
  }

  @override
  Future<void> sendMessage(WebSocketMessage message) async {
    if (_channel == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    try {
      dynamic dataToSend = message.data;
      
      // Handle JSON serialization
      if (message.type == 'json' && message.data is Map) {
        dataToSend = jsonEncode(message.data);
      }
      
      _channel!.sink.add(dataToSend);
    } catch (error) {
      _errorController.add(error);
      rethrow;
    }
  }

  @override
  Future<void> send(dynamic data) async {
    if (_channel == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    try {
      _channel!.sink.add(data);
    } catch (error) {
      _errorController.add(error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect([int? code, String? reason]) async {
    if (_currentState == WebSocketState.disconnected) {
      return;
    }

    _updateState(WebSocketState.disconnecting);
    _connectionTimeoutTimer?.cancel();
    
    try {
      await _channelSubscription?.cancel();
      await _channel?.sink.close(code, reason);
    } catch (error) {
      _errorController.add(error);
    } finally {
      _updateState(WebSocketState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    _connectionTimeoutTimer?.cancel();
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
  }

  void _handleMessage(dynamic data) {
    try {
      WebSocketMessage message;
      
      if (data is String) {
        // Check if it's a heartbeat response
        if (_isHeartbeatMessage(data)) {
          message = WebSocketMessage(
            data: data,
            timestamp: DateTime.now(),
            type: 'heartbeat',
            metadata: {'isHeartbeat': true},
          );
        } else {
          // Try to parse as JSON
          try {
            final jsonData = jsonDecode(data);
            message = WebSocketMessage.json(jsonData);
          } catch (_) {
            // If JSON parsing fails, treat as text
            message = WebSocketMessage.text(data);
          }
        }
      } else if (data is List<int>) {
        message = WebSocketMessage.binary(data);
      } else {
        message = WebSocketMessage.now(data: data);
      }
      
      _messageController.add(message);
    } catch (error) {
      _errorController.add(error);
    }
  }

  void _handleError(dynamic error) {
    _connectionTimeoutTimer?.cancel();
    _updateState(WebSocketState.error);
    _errorController.add(error);
  }

  void _handleDone() {
    _connectionTimeoutTimer?.cancel();
    _updateState(WebSocketState.disconnected);
  }

  void _updateState(WebSocketState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Checks if a message is a heartbeat message
  bool _isHeartbeatMessage(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage == 'pong' || 
           lowerMessage == _config.expectedPongMessage?.toLowerCase() ||
           lowerMessage.contains('ping') || 
           lowerMessage.contains('pong');
  }

  @override
  bool get isClosed => currentState  == WebSocketState.disconnected;

  @override
  bool get isConnected => currentState == WebSocketState.connected;

  @override
  bool get isConnecting => currentState == WebSocketState.connecting;
}
