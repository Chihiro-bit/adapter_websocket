import 'dart:async';
import 'websocket_adapter.dart';
import 'websocket_config.dart';
import 'websocket_message.dart';
import 'websocket_state.dart';
import 'heartbeat_manager.dart';
import 'reconnection_manager.dart';
import 'websocket_interceptor.dart';

/// High-level WebSocket client that uses adapters for implementation
class WebSocketClient {
  final WebSocketAdapter _adapter;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _statsController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController<dynamic>.broadcast();

  final List<WebSocketInterceptor> interceptors = [];
  
  late final HeartbeatManager _heartbeatManager;
  late final ReconnectionManager _reconnectionManager;
  
  bool _disposed = false;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _errorSubscription;

  WebSocketClient(this._adapter) {
    _initializeManagers();
    _setupSubscriptions();
  }

  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream => _adapter.stateStream;

  /// Stream of incoming messages
  Stream<WebSocketMessage> get messageStream => _messageController.stream;

  /// Stream of connection errors
  Stream<dynamic> get errorStream => _errorController.stream;

  /// Stream of log messages (if logging is enabled)
  Stream<String> get logStream => _logController.stream;

  /// Stream of connection and heartbeat statistics
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;

  /// Current connection state
  WebSocketState get currentState => _adapter.currentState;

  /// Configuration used for this client
  WebSocketConfig get config => _adapter.config;

  /// Checks if the connection is currently active
  bool get isConnected => _adapter.isConnected;

  /// Checks if the connection is in a connecting state
  bool get isConnecting => _adapter.isConnecting;

  /// Checks if the connection is closed
  bool get isClosed => _adapter.isClosed;

  /// Gets current connection statistics
  Map<String, dynamic> get connectionStats {
    return {
      'connectionState': currentState.description,
      'isConnected': isConnected,
      'heartbeat': _heartbeatManager.getStats(),
      'reconnection': _reconnectionManager.getStats(),
      'config': {
        'url': config.url,
        'autoReconnect': config.autoReconnect,
        'enableHeartbeat': config.enableHeartbeat,
        'heartbeatInterval': config.heartbeatInterval.inSeconds,
        'maxReconnectAttempts': config.maxReconnectAttempts,
      },
    };
  }

  /// Registers a WebSocket interceptor
  void addInterceptor(WebSocketInterceptor interceptor) {
    interceptors.add(interceptor);
  }

  /// Removes a previously registered interceptor
  void removeInterceptor(WebSocketInterceptor interceptor) {
    interceptors.remove(interceptor);
  }

  /// Establishes a WebSocket connection with automatic reconnection support
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('WebSocketClient has been disposed');
    }

    _log('Attempting to connect to ${config.url}');
    
    try {
      await _adapter.connect();
      _log('Successfully connected to ${config.url}');
      
      // Reset reconnection manager on successful connection
      _reconnectionManager.reset();
      
      // Start heartbeat if enabled
      if (config.enableHeartbeat) {
        _heartbeatManager.start();
      }
      
      _publishStats();
    } catch (error) {
      _log('Failed to connect: $error');

      if (config.autoReconnect) {
        _reconnectionManager.startReconnection();
      }
      _handleError(error);
      rethrow;
    }
  }

  /// Sends a message through the WebSocket
  Future<void> sendMessage(WebSocketMessage message) async {
    if (!isConnected) {
      throw StateError('WebSocket is not connected');
    }

    _log('Sending message: ${message.type ?? 'unknown'} type');

    WebSocketMessage? processed = message;
    for (final interceptor in interceptors) {
      try {
        processed = await interceptor.onSend(processed!);
        if (processed == null) {
          _log('Message cancelled by onSend interceptor');
          return;
        }
      } catch (e) {
        _handleError(e);
        return;
      }
    }

    try {
      await _adapter.sendMessage(processed!);
    } catch (error) {
      _handleError(error);
      rethrow;
    }
  }

  /// Sends raw data through the WebSocket
  Future<void> send(dynamic data) async {
    if (!isConnected) {
      throw StateError('WebSocket is not connected');
    }

    _log('Sending raw data');
    try {
      await _adapter.send(data);
    } catch (error) {
      _handleError(error);
      rethrow;
    }
  }

  /// Sends a text message
  Future<void> sendText(String text) async {
    await sendMessage(WebSocketMessage.text(text));
  }

  /// Sends a JSON message
  Future<void> sendJson(Map<String, dynamic> json) async {
    await sendMessage(WebSocketMessage.json(json));
  }

  /// Sends binary data
  Future<void> sendBinary(List<int> bytes) async {
    await sendMessage(WebSocketMessage.binary(bytes));
  }

  /// Closes the WebSocket connection
  Future<void> disconnect([int? code, String? reason]) async {
    _log('Disconnecting WebSocket');
    _heartbeatManager.stop();
    _reconnectionManager.stopReconnection();
    await _adapter.disconnect(code, reason);
  }

  /// Forces a reconnection (useful for testing connection resilience)
  Future<void> forceReconnect() async {
    _log('Forcing reconnection');
    await disconnect();
    await Future.delayed(Duration(milliseconds: 100));
    await connect();
  }

  /// Disposes of the client and cleans up resources
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _log('Disposing WebSocket client');

    _heartbeatManager.dispose();
    _reconnectionManager.dispose();

    await _stateSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();

    await _adapter.dispose();
    await _logController.close();
    await _statsController.close();
    await _messageController.close();
    await _errorController.close();
  }

  /// Initializes the heartbeat and reconnection managers
  void _initializeManagers() {
    _heartbeatManager = HeartbeatManager(
      config: config,
      sendMessage: (message) => send(message),
      log: _log,
    );

    _reconnectionManager = ReconnectionManager(
      config: config,
      reconnectCallback: () => _adapter.connect(),
      log: _log,
    );

    // Set up heartbeat callbacks
    _heartbeatManager.setOnHeartbeatTimeout(() {
      _log('Heartbeat timeout detected - initiating reconnection');
      if (config.autoReconnect) {
        _reconnectionManager.startReconnection();
      }
    });

    _heartbeatManager.setOnConnectionHealthy(() {
      _publishStats();
    });

    _heartbeatManager.setOnConnectionUnhealthy(() {
      _publishStats();
    });

    // Set up reconnection callbacks
    _reconnectionManager.setOnReconnectAttempt(() {
      _log('Reconnection attempt started');
      _publishStats();
    });

    _reconnectionManager.setOnReconnectSuccess(() {
      _log('Reconnection successful - restarting heartbeat');
      if (config.enableHeartbeat) {
        _heartbeatManager.start();
      }
      _publishStats();
    });

    _reconnectionManager.setOnReconnectFailure((error) {
      _log('Reconnection failed: $error');
      _publishStats();
    });

    _reconnectionManager.setOnMaxAttemptsReached(() {
      _log('Maximum reconnection attempts reached - giving up');
      _publishStats();
    });
  }

  /// Sets up stream subscriptions
  void _setupSubscriptions() {
    _stateSubscription = _adapter.stateStream.listen((state) {
      _log('State changed to: ${state.description}');
      
      if (state == WebSocketState.connected) {
        if (config.enableHeartbeat) {
          _heartbeatManager.start();
        }
      } else if (state == WebSocketState.disconnected) {
        _heartbeatManager.stop();
        if (config.autoReconnect && !_disposed) {
          _reconnectionManager.startReconnection();
        }
      } else if (state == WebSocketState.error) {
        _heartbeatManager.stop();
      }
      
      _publishStats();
    });

    _messageSubscription = _adapter.messageStream.listen(_handleIncomingMessage);

    _errorSubscription = _adapter.errorStream.listen(_handleError);
  }

  Future<void> _handleIncomingMessage(WebSocketMessage message) async {
    try {
      WebSocketMessage? processed = message;
      for (final interceptor in interceptors) {
        processed = await interceptor.onReceive(processed!);
        if (processed == null) {
          _log('Message cancelled by onReceive interceptor');
          return;
        }
      }
      // Let heartbeat manager handle incoming messages
      _heartbeatManager.handleIncomingMessage(processed);
      if (!_messageController.isClosed) {
        _messageController.add(processed);
      }
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleError(dynamic error) {
    _log('WebSocket error: $error');
    for (final interceptor in interceptors) {
      try {
        final result = interceptor.onError(error);
        if (result is Future) {
          result.catchError((_) {});
        }
      } catch (_) {}
    }
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    _publishStats();
  }

  /// Publishes current statistics
  void _publishStats() {
    if (!_statsController.isClosed) {
      _statsController.add(connectionStats);
    }
  }

  /// Logs a message if logging is enabled
  void _log(String message) {
    if (config.enableLogging && !_logController.isClosed) {
      final timestamp = DateTime.now().toIso8601String();
      _logController.add('[$timestamp] $message');
    }
  }
}
