import 'dart:async';
import 'dart:convert';
import 'package:adapter_websocket/websocket_plugin.dart';

/// Mock WebSocket adapter for testing purposes
class MockWebSocketAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;

  final StreamController<WebSocketState> _stateController =
      StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController<dynamic>.broadcast();

  WebSocketState _currentState = WebSocketState.disconnected;
  final List<WebSocketMessage> _sentMessages = [];
  bool _shouldFailConnection = false;
  bool _shouldFailSending = false;
  Duration _connectionDelay = Duration.zero;
  bool _autoRespondToPing = true;
  bool _simulateUnstableConnection = false;

  // track all created timers for cleanup
  final List<Timer> _timers = [];
  bool _disposed = false;
  Timer? _instabilityTimer;

  MockWebSocketAdapter(this._config);

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

  List<WebSocketMessage> get sentMessages => List.unmodifiable(_sentMessages);

  void setShouldFailConnection(bool shouldFail) {
    _shouldFailConnection = shouldFail;
  }

  void setShouldFailSending(bool shouldFail) {
    _shouldFailSending = shouldFail;
  }

  void setConnectionDelay(Duration delay) {
    _connectionDelay = delay;
  }

  void setAutoRespondToPing(bool autoRespond) {
    _autoRespondToPing = autoRespond;
  }

  void setSimulateUnstableConnection(bool simulate) {
    _simulateUnstableConnection = simulate;
    if (simulate && _currentState == WebSocketState.connected) {
      _startInstabilitySimulation();
    } else {
      _stopInstabilitySimulation();
    }
  }

  void simulateMessage(WebSocketMessage message) {
    if (_disposed) return;
    if (_currentState == WebSocketState.connected) {
      _messageController.add(message);
    }
  }

  void simulateTextMessage(String text) {
    simulateMessage(WebSocketMessage.text(text));
  }

  void simulateJsonMessage(Map<String, dynamic> json) {
    simulateMessage(WebSocketMessage.json(json));
  }

  void simulatePongMessage([String? customPong]) {
    final pongMessage = customPong ?? _config.expectedPongMessage ?? 'pong';
    simulateMessage(
      WebSocketMessage(
        data: pongMessage,
        timestamp: DateTime.now(),
        type: 'heartbeat',
        metadata: {'isHeartbeat': true},
      ),
    );
  }

  void simulateError(dynamic error) {
    if (_disposed) return;
    _errorController.add(error);
  }

  void simulateDisconnection() {
    _updateState(WebSocketState.disconnected);
  }

  void simulateNetworkInstability() {
    if (_currentState == WebSocketState.connected) {
      simulateDisconnection();
    }
  }

  @override
  Future<void> connect() async {
    if (_disposed) return;
    if (_currentState == WebSocketState.connecting ||
        _currentState == WebSocketState.connected) {
      return;
    }

    _updateState(WebSocketState.connecting);

    if (_connectionDelay > Duration.zero) {
      await Future.delayed(_connectionDelay);
    }

    if (_shouldFailConnection) {
      _updateState(WebSocketState.error);
      final error = Exception('Mock connection failure');
      if (!_disposed) _errorController.add(error);
      throw error;
    }

    _updateState(WebSocketState.connected);

    if (_simulateUnstableConnection) {
      _startInstabilitySimulation();
    }
  }

  @override
  Future<void> sendMessage(WebSocketMessage message) async {
    if (_disposed) return;
    if (_currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    if (_shouldFailSending) {
      final error = Exception('Mock sending failure');
      if (!_disposed) _errorController.add(error);
      throw error;
    }

    _sentMessages.add(message);

    if (_autoRespondToPing && _isPingMessage(message)) {
      final t = Timer(Duration(milliseconds: 50), () {
        if (!_disposed) simulatePongMessage();
      });
      _timers.add(t);
    }
  }

  @override
  Future<void> send(dynamic data) async {
    if (_disposed) return;
    if (_currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    if (_shouldFailSending) {
      final error = Exception('Mock sending failure');
      if (!_disposed) _errorController.add(error);
      throw error;
    }

    WebSocketMessage message;
    if (data is String) {
      if (_isPingMessageData(data)) {
        message = WebSocketMessage(
          data: data,
          timestamp: DateTime.now(),
          type: 'heartbeat',
          metadata: {'isHeartbeat': true},
        );
      } else {
        try {
          final jsonData = jsonDecode(data);
          message = WebSocketMessage.json(jsonData);
        } catch (_) {
          message = WebSocketMessage.text(data);
        }
      }
    } else if (data is List<int>) {
      message = WebSocketMessage.binary(data);
    } else {
      message = WebSocketMessage.now(data: data);
    }

    _sentMessages.add(message);

    if (_autoRespondToPing && _isPingMessage(message)) {
      final t = Timer(Duration(milliseconds: 50), () {
        if (!_disposed) simulatePongMessage();
      });
      _timers.add(t);
    }
  }

  @override
  Future<void> disconnect([int? code, String? reason]) async {
    if (_disposed) return;
    if (_currentState == WebSocketState.disconnected) {
      return;
    }

    _updateState(WebSocketState.disconnecting);
    _stopInstabilitySimulation();
    await Future.delayed(Duration(milliseconds: 100));
    _updateState(WebSocketState.disconnected);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopInstabilitySimulation();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
    _sentMessages.clear();
  }

  void _updateState(WebSocketState newState) {
    if (_disposed) return;
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  bool _isPingMessage(WebSocketMessage message) {
    return _isPingMessageData(message.data.toString());
  }

  bool _isPingMessageData(String data) {
    final lowerData = data.toLowerCase();
    return lowerData == 'ping' ||
        lowerData == _config.heartbeatMessage.toLowerCase() ||
        lowerData.contains('ping');
  }

  void _startInstabilitySimulation() {
    _stopInstabilitySimulation();
    final randomMillis =
        30000 + (DateTime.now().millisecondsSinceEpoch % 90000);
    _instabilityTimer = Timer(Duration(milliseconds: randomMillis), () {
      if (!_disposed && _currentState == WebSocketState.connected) {
        simulateNetworkInstability();
      }
    });
    _timers.add(_instabilityTimer!);
  }

  void _stopInstabilitySimulation() {
    _instabilityTimer?.cancel();
    _timers.remove(_instabilityTimer);
    _instabilityTimer = null;
  }

  void clearSentMessages() {
    _sentMessages.clear();
  }

  @override
  bool get isClosed => _disposed || currentState == WebSocketState.disconnected;

  @override
  bool get isConnected => currentState == WebSocketState.connected;

  @override
  bool get isConnecting => currentState == WebSocketState.connecting;
}
