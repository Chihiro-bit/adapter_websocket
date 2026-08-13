import 'dart:async';
import 'dart:convert';

import 'package:adapter_websocket/adapter_websocket.dart';

import 'mock_server_logic.dart';

/// Web build of [LocalMockWebSocketAdapter]: same public API and server
/// behaviour, but the transport is an in-memory duplex link instead of a real
/// local socket (browsers cannot host a WebSocket server).
///
/// All mock behaviours (auto-pong, auto-ack, topic echo, periodic broadcasts,
/// simulated disconnects) work identically, so the demo is fully usable on
/// the web — including auto-reconnect after [setSimulateDisconnects] drops
/// the link.
class LocalMockWebSocketAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;
  final MockServerLogic _logic;

  _SelfConnection? _connection;

  final StreamController<WebSocketState> _stateController =
      StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController<dynamic>.broadcast();

  WebSocketState _currentState = WebSocketState.disconnected;
  bool _disposed = false;

  LocalMockWebSocketAdapter._(this._config, this._logic);

  /// Creates an adapter wired to an in-memory mock connection.
  static Future<LocalMockWebSocketAdapter> create(
    WebSocketConfig config,
  ) async {
    final adapter = LocalMockWebSocketAdapter._(
      config,
      MockServerLogic(config),
    );
    adapter._logic.startBroadcasts();
    return adapter;
  }

  // ─── WebSocketAdapter interface ────────────────────────────────────────────

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
  bool get isClosed => _currentState == WebSocketState.disconnected;

  @override
  bool get isConnected => _currentState == WebSocketState.connected;

  @override
  bool get isConnecting => _currentState == WebSocketState.connecting;

  /// Descriptive URL for display (no real socket exists on the web build).
  String get serverUrl => 'mock://in-memory';

  /// Toggles periodic abrupt server-side disconnections (every 12 s) to
  /// demonstrate the plugin's auto-reconnection.
  void setSimulateDisconnects(bool value) =>
      _logic.setSimulateDisconnects(value);

  /// Immediately drops the mock link — handy to demo (or test) auto-reconnect
  /// on demand.
  void simulateDisconnectNow() => _logic.dropAllConnections();

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('LocalMockWebSocketAdapter has been disposed');
    }
    if (_currentState == WebSocketState.connecting ||
        _currentState == WebSocketState.connected) {
      return;
    }

    _updateState(WebSocketState.connecting);
    final connection = _SelfConnection(this);
    _connection = connection;
    _logic.attach(connection);
    _updateState(WebSocketState.connected);
  }

  @override
  Future<void> sendMessage(WebSocketMessage message) async {
    final connection = _connection;
    if (connection == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    dynamic dataToSend = message.data;
    if (message.type == 'json' && message.data is Map) {
      dataToSend = jsonEncode(message.data);
    }
    _logic.handleClientData(connection, dataToSend);
  }

  @override
  Future<void> send(dynamic data) async {
    final connection = _connection;
    if (connection == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }
    _logic.handleClientData(connection, data);
  }

  @override
  Future<void> disconnect([int? code, String? reason]) async {
    if (_currentState == WebSocketState.disconnected) {
      return;
    }

    _updateState(WebSocketState.disconnecting);
    final connection = _connection;
    _connection = null;
    if (connection != null) _logic.detach(connection);
    _updateState(WebSocketState.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connection = null;
    await _logic.dispose();
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
  }

  // ─── Internal handlers ─────────────────────────────────────────────────────

  void _handleMessage(dynamic data) {
    try {
      WebSocketMessage message;
      if (data is String) {
        if (_config.enableHeartbeat && _isPongMessage(data)) {
          message = WebSocketMessage(
            data: data,
            timestamp: DateTime.now(),
            type: 'heartbeat',
            metadata: {'isHeartbeat': true},
          );
        } else {
          try {
            message = WebSocketMessage.json(jsonDecode(data));
          } catch (_) {
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

  bool _isPongMessage(String message) {
    final pong = _config.expectedPongMessage;
    final pattern = _config.expectedPongMessagePattern;
    if (pong == null && pattern == null) return false;
    if (pong != null && message == pong) return true;
    return pattern?.hasMatch(message) ?? false;
  }

  /// Called by [_SelfConnection.close] when the mock drops the link.
  void _handleServerDrop(_SelfConnection connection) {
    if (_connection == connection) {
      _connection = null;
      _logic.detach(connection);
      if (_currentState == WebSocketState.connected) {
        _updateState(WebSocketState.disconnected);
      }
    }
  }

  void _updateState(WebSocketState newState) {
    if (_disposed) return;
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }
}

/// The in-memory "server side" of the mock link: server → client frames are
/// delivered straight into the adapter's message pipeline.
class _SelfConnection implements MockConnection {
  final LocalMockWebSocketAdapter _adapter;

  _SelfConnection(this._adapter);

  @override
  void add(dynamic data) => _adapter._handleMessage(data);

  @override
  Future<void> close() async => _adapter._handleServerDrop(this);
}
