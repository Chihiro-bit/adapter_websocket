import 'dart:async';
import 'dart:convert';
import '../websocket_adapter.dart';
import '../websocket_config.dart';
import '../websocket_message.dart';
import '../websocket_state.dart';

/// Mock WebSocket adapter for testing purposes
class MockWebSocketAdapter implements WebSocketAdapter {
  final WebSocketConfig _config;
  
  final StreamController<WebSocketState> _stateController = StreamController<WebSocketState>.broadcast();
  final StreamController<WebSocketMessage> _messageController = StreamController<WebSocketMessage>.broadcast();
  final StreamController<dynamic> _errorController = StreamController<dynamic>.broadcast();
  
  WebSocketState _currentState = WebSocketState.disconnected;
  final List<WebSocketMessage> _sentMessages = [];
  bool _shouldFailConnection = false;
  bool _shouldFailSending = false;
  Duration _connectionDelay = Duration.zero;
  bool _autoRespondToPing = true;
  bool _simulateUnstableConnection = false;
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

  /// List of messages that were sent through this adapter
  List<WebSocketMessage> get sentMessages => List.unmodifiable(_sentMessages);

  /// Configure the adapter to fail connection attempts
  void setShouldFailConnection(bool shouldFail) {
    _shouldFailConnection = shouldFail;
  }

  /// Configure the adapter to fail message sending
  void setShouldFailSending(bool shouldFail) {
    _shouldFailSending = shouldFail;
  }

  /// Set a delay for connection establishment
  void setConnectionDelay(Duration delay) {
    _connectionDelay = delay;
  }

  /// Configure automatic ping response
  void setAutoRespondToPing(bool autoRespond) {
    _autoRespondToPing = autoRespond;
  }

  /// Simulate unstable connection (random disconnections)
  void setSimulateUnstableConnection(bool simulate) {
    _simulateUnstableConnection = simulate;
    if (simulate && _currentState == WebSocketState.connected) {
      _startInstabilitySimulation();
    } else {
      _stopInstabilitySimulation();
    }
  }

  /// Simulate receiving a message
  void simulateMessage(WebSocketMessage message) {
    if (_currentState == WebSocketState.connected) {
      _messageController.add(message);
    }
  }

  /// Simulate receiving a text message
  void simulateTextMessage(String text) {
    simulateMessage(WebSocketMessage.text(text));
  }

  /// Simulate receiving a JSON message
  void simulateJsonMessage(Map<String, dynamic> json) {
    simulateMessage(WebSocketMessage.json(json));
  }

  /// Simulate receiving a pong message
  void simulatePongMessage([String? customPong]) {
    final pongMessage = customPong ?? _config.expectedPongMessage ?? 'pong';
    simulateMessage(WebSocketMessage(
      data: pongMessage,
      timestamp: DateTime.now(),
      type: 'heartbeat',
      metadata: {'isHeartbeat': true},
    ));
  }

  /// Simulate an error
  void simulateError(dynamic error) {
    _errorController.add(error);
  }

  /// Simulate connection loss
  void simulateDisconnection() {
    _updateState(WebSocketState.disconnected);
  }

  /// Simulate network instability
  void simulateNetworkInstability() {
    if (_currentState == WebSocketState.connected) {
      simulateDisconnection();
    }
  }

  @override
  Future<void> connect() async {
    if (_currentState == WebSocketState.connecting || _currentState == WebSocketState.connected) {
      return;
    }

    _updateState(WebSocketState.connecting);

    if (_connectionDelay > Duration.zero) {
      await Future.delayed(_connectionDelay);
    }

    if (_shouldFailConnection) {
      _updateState(WebSocketState.error);
      final error = Exception('Mock connection failure');
      _errorController.add(error);
      throw error;
    }

    _updateState(WebSocketState.connected);
    
    if (_simulateUnstableConnection) {
      _startInstabilitySimulation();
    }
  }

  @override
  Future<void> sendMessage(WebSocketMessage message) async {
    if (_currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    if (_shouldFailSending) {
      final error = Exception('Mock sending failure');
      _errorController.add(error);
      throw error;
    }

    _sentMessages.add(message);
    
    // Auto-respond to ping messages if enabled
    if (_autoRespondToPing && _isPingMessage(message)) {
      Timer(Duration(milliseconds: 50), () {
        simulatePongMessage();
      });
    }
  }

  @override
  Future<void> send(dynamic data) async {
    if (_currentState != WebSocketState.connected) {
      throw StateError('WebSocket is not connected');
    }

    if (_shouldFailSending) {
      final error = Exception('Mock sending failure');
      _errorController.add(error);
      throw error;
    }

    WebSocketMessage message;
    if (data is String) {
      // Check if it's a ping message
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
    
    // Auto-respond to ping messages if enabled
    if (_autoRespondToPing && _isPingMessage(message)) {
      Timer(Duration(milliseconds: 50), () {
        simulatePongMessage();
      });
    }
  }

  @override
  Future<void> disconnect([int? code, String? reason]) async {
    if (_currentState == WebSocketState.disconnected) {
      return;
    }

    _updateState(WebSocketState.disconnecting);
    _stopInstabilitySimulation();
    await Future.delayed(Duration(milliseconds: 100)); // Simulate disconnect delay
    _updateState(WebSocketState.disconnected);
  }

  @override
  Future<void> dispose() async {
    _stopInstabilitySimulation();
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
    _sentMessages.clear();
  }

  void _updateState(WebSocketState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Checks if a message is a ping message
  bool _isPingMessage(WebSocketMessage message) {
    return _isPingMessageData(message.data.toString());
  }

  /// Checks if data represents a ping message
  bool _isPingMessageData(String data) {
    final lowerData = data.toLowerCase();
    return lowerData == 'ping' || 
           lowerData == _config.heartbeatMessage.toLowerCase() ||
           lowerData.contains('ping');
  }

  /// Starts simulating connection instability
  void _startInstabilitySimulation() {
    _stopInstabilitySimulation();
    
    // Randomly disconnect every 30-120 seconds
    final randomDelay = Duration(seconds: 30 + (90 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round());
    
    _instabilityTimer = Timer(randomDelay, () {
      if (_currentState == WebSocketState.connected) {
        simulateNetworkInstability();
      }
    });
  }

  /// Stops simulating connection instability
  void _stopInstabilitySimulation() {
    _instabilityTimer?.cancel();
    _instabilityTimer = null;
  }

  /// Clear all sent messages (useful for testing)
  void clearSentMessages() {
    _sentMessages.clear();
  }

  @override
  bool get isClosed => currentState  == WebSocketState.disconnected;

  @override
  bool get isConnected => currentState == WebSocketState.connected;

  @override
  bool get isConnecting => currentState == WebSocketState.connecting;
}
