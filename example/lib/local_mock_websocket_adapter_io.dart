import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adapter_websocket/adapter_websocket.dart';

import 'mock_server_logic.dart';

/// A self-driving mock [WebSocketAdapter] backed by an in-process WebSocket
/// server, so the demo can exercise every plugin feature (heartbeat, ACK,
/// topic channels, message queue, auto-reconnect) with zero network access.
///
/// Native platforms: the server binds to `127.0.0.1` on an ephemeral port and
/// upgrades real WebSocket connections, meaning the client speaks the genuine
/// wire protocol. (The web build uses an in-memory transport instead — see
/// `local_mock_websocket_adapter_stub.dart`.)
///
/// Server behaviours (all handled automatically): auto-pong, auto-ack,
/// topic echo, periodic broadcasts every 5 s, and optional simulated
/// disconnects every 12 s ([setSimulateDisconnects]).
///
/// ```dart
/// final mock = await LocalMockWebSocketAdapter.create(config);
/// final client = WebSocketClient(mock);
/// await client.connect();
/// ```
class LocalMockWebSocketAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;
  final MockServerLogic _logic;
  HttpServer? _httpServer;

  WebSocket? _socket;
  StreamSubscription? _subscription;

  final StreamController<WebSocketState> _stateController =
      StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController<dynamic>.broadcast();

  WebSocketState _currentState = WebSocketState.disconnected;
  bool _disposed = false;

  LocalMockWebSocketAdapter._(this._config, this._logic);

  /// Starts the in-process mock server and returns an adapter pointing at it.
  ///
  /// The adapter's [config] is a copy of [config] whose `url` is the real
  /// local server URL (`ws://127.0.0.1:<port>/ws`).
  static Future<LocalMockWebSocketAdapter> create(
    WebSocketConfig config,
  ) async {
    final logic = MockServerLogic(config);
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final adapter = LocalMockWebSocketAdapter._(
      config.copyWith(url: 'ws://127.0.0.1:${httpServer.port}/ws'),
      logic,
    );
    adapter._httpServer = httpServer;
    httpServer.listen(adapter._handleRequest);
    logic.startBroadcasts();
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

  /// The local server URL this adapter connects to.
  String get serverUrl => _config.url;

  /// Toggles periodic abrupt server-side disconnections (every 12 s) to
  /// demonstrate the plugin's auto-reconnection.
  void setSimulateDisconnects(bool value) =>
      _logic.setSimulateDisconnects(value);

  /// Immediately closes every server-side connection — handy to demo (or
  /// test) auto-reconnect on demand.
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
    try {
      _socket = await WebSocket.connect(_config.url);
      _subscription = _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
      _updateState(WebSocketState.connected);
    } catch (error) {
      _updateState(WebSocketState.error);
      _errorController.add(error);
      rethrow;
    }
  }

  @override
  Future<void> sendMessage(WebSocketMessage message) async {
    final socket = _socket;
    if (socket == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    dynamic dataToSend = message.data;
    if (message.type == 'json' && message.data is Map) {
      dataToSend = jsonEncode(message.data);
    }
    socket.add(dataToSend);
  }

  @override
  Future<void> send(dynamic data) async {
    final socket = _socket;
    if (socket == null || _currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }
    socket.add(data);
  }

  @override
  Future<void> disconnect([int? code, String? reason]) async {
    if (_currentState == WebSocketState.disconnected) {
      return;
    }

    _updateState(WebSocketState.disconnecting);
    try {
      await _socket?.close(code, reason);
    } catch (error) {
      _errorController.add(error);
    } finally {
      _updateState(WebSocketState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    await _logic.dispose();
    await _httpServer?.close(force: true);
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
  }

  // ─── Server side ───────────────────────────────────────────────────────────

  void _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final connection = _IoMockConnection(socket);
    _logic.attach(connection);
    socket.listen(
      (data) => _logic.handleClientData(connection, data),
      onError: (_) => _logic.detach(connection),
      onDone: () => _logic.detach(connection),
    );
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

  void _handleError(dynamic error) {
    _updateState(WebSocketState.error);
    _errorController.add(error);
  }

  void _handleDone() {
    if (_currentState == WebSocketState.connected) {
      _updateState(WebSocketState.disconnected);
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

/// Bridges one server-side [WebSocket] to the transport-agnostic mock logic.
class _IoMockConnection implements MockConnection {
  final WebSocket socket;

  _IoMockConnection(this.socket);

  @override
  void add(dynamic data) => socket.add(data);

  @override
  Future<void> close() => socket.close();
}
