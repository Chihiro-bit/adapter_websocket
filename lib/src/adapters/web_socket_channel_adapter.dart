import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../websocket_adapter.dart';
import '../websocket_config.dart';
import '../websocket_message.dart';
import '../websocket_state.dart';
import '_ws_connect_stub.dart' if (dart.library.io) '_ws_connect_io.dart';

/// WebSocket adapter implementation using the web_socket_channel package
class WebSocketChannelAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;

  WebSocketChannel? _channel;
  final StreamController<WebSocketState> _stateController =
      StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController<dynamic>.broadcast();

  WebSocketState _currentState = WebSocketState.disconnected;
  StreamSubscription? _channelSubscription;
  Timer? _connectionTimeoutTimer;

  /// Incremented on every [connect] attempt (and when an attempt times out).
  /// Callbacks from an earlier generation are ignored so a stale connection
  /// can never overwrite the state of a newer one.
  int _connectGeneration = 0;

  /// Whether the current attempt's handshake has completed successfully.
  /// Used to distinguish a failed handshake (→ error state) from a clean
  /// close after a successful connection (→ disconnected state).
  bool _handshakeCompleted = false;

  bool _disposed = false;

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
    if (_currentState == WebSocketState.connecting ||
        _currentState == WebSocketState.connected) {
      return;
    }

    // Invalidate any in-flight attempt from a previous connect().
    _connectGeneration++;
    final generation = _connectGeneration;
    _handshakeCompleted = false;

    _updateState(WebSocketState.connecting);

    final channel = connectChannel(Uri.parse(_config.url), _config);
    _channel = channel;

    // Drives the result of this connect() so a timeout can terminate the
    // Future even when `ready` itself never completes (e.g. on web where the
    // browser handshake can stall).
    final completer = Completer<void>();

    final timeoutTimer = Timer(_config.connectionTimeout, () {
      if (_disposed || generation != _connectGeneration) return;
      if (_currentState != WebSocketState.connecting) return;
      // This attempt is dead: invalidate its callbacks, terminate the hung
      // handshake, and report the failure exactly once.
      _connectGeneration++;
      _connectionTimeoutTimer = null;
      try {
        _channelSubscription?.cancel();
      } catch (_) {}
      try {
        channel.sink.close();
      } catch (_) {}
      final error = TimeoutException(
        'Connection timeout',
        _config.connectionTimeout,
      );
      if (!completer.isCompleted) completer.completeError(error);
      _updateState(WebSocketState.error);
      _emitError(error);
    });
    _connectionTimeoutTimer = timeoutTimer;

    // Close any subscription from a previous attempt before overwriting it,
    // so an old channel can never inject messages into the new one.
    await _channelSubscription?.cancel();
    _channelSubscription = channel.stream.listen(
      (data) {
        if (!_disposed && generation == _connectGeneration) {
          _handleMessage(data);
        }
      },
      onError: (error) {
        if (!_disposed && generation == _connectGeneration) {
          _handleError(error);
        }
      },
      onDone: () {
        if (!_disposed && generation == _connectGeneration) {
          _handleDone();
        }
      },
    );

    channel.ready
        .then((_) {
          if (_disposed || generation != _connectGeneration) return;
          timeoutTimer.cancel();
          _connectionTimeoutTimer = null;
          if (!completer.isCompleted) completer.complete();
          // Only report success if nothing (e.g. disconnect()) superseded us.
          if (_currentState == WebSocketState.connecting) {
            _handshakeCompleted = true;
            _updateState(WebSocketState.connected);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (_disposed || generation != _connectGeneration) return;
          timeoutTimer.cancel();
          _connectionTimeoutTimer = null;
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          if (_currentState == WebSocketState.connecting) {
            _updateState(WebSocketState.error);
            _emitError(error);
          }
        });

    return completer.future;
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
    _disposed = true;
    _connectionTimeoutTimer?.cancel();
    await _channelSubscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}

    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
  }

  void _handleMessage(dynamic data) {
    try {
      WebSocketMessage message;

      if (data is String) {
        // Check if it's a heartbeat response
        if (_config.enableHeartbeat && _isHeartbeatMessage(data)) {
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
    _emitError(error);
  }

  void _handleDone() {
    _connectionTimeoutTimer?.cancel();
    if (_currentState == WebSocketState.connecting) {
      // The stream closed before the handshake completed: the connect
      // attempt failed, so surface it as an error rather than a clean
      // disconnect.
      _updateState(WebSocketState.error);
      _emitError(StateError('WebSocket connection closed during handshake'));
    } else if (_currentState == WebSocketState.error && !_handshakeCompleted) {
      // The handshake failure was already reported (by the ready error or
      // the branch above) — keep the error state.
    } else {
      // Clean close after a successful connection (or after a mid-operation
      // error, where the client relies on `disconnected` to reconnect).
      _updateState(WebSocketState.disconnected);
    }
  }

  void _emitError(dynamic error) {
    if (!_disposed && !_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  void _updateState(WebSocketState newState) {
    if (_disposed) return;
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Checks if a message is a heartbeat message
  bool _isHeartbeatMessage(String message) {
    if (_config.expectedPongMessage == null &&
        _config.expectedPongMessagePattern == null) {
      return false;
    }
    if (_config.expectedPongMessage != null &&
        message == _config.expectedPongMessage) {
      return true;
    }
    return _config.expectedPongMessagePattern?.hasMatch(message) ?? false;
  }

  @override
  bool get isClosed => currentState == WebSocketState.disconnected;

  @override
  bool get isConnected => currentState == WebSocketState.connected;

  @override
  bool get isConnecting => currentState == WebSocketState.connecting;
}
