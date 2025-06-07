import 'dart:async';
import 'websocket_config.dart';
import 'websocket_message.dart';

/// Callback type for sending heartbeat messages
typedef HeartbeatSender = Future<void> Function(String message);

/// Callback type for heartbeat events
typedef HeartbeatCallback = void Function();

/// Manages heartbeat functionality for WebSocket connections
class HeartbeatManager {
  final WebSocketConfig _config;
  final HeartbeatSender _sendMessage;
  final void Function(String) _log;

  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  int _missedHeartbeats = 0;
  bool _isActive = false;
  bool _waitingForPong = false;
  DateTime? _lastHeartbeatSent;
  DateTime? _lastPongReceived;

  // Callbacks
  HeartbeatCallback? _onHeartbeatTimeout;
  HeartbeatCallback? _onConnectionHealthy;
  HeartbeatCallback? _onConnectionUnhealthy;

  HeartbeatManager({
    required WebSocketConfig config,
    required HeartbeatSender sendMessage,
    required void Function(String) log,
  })  : _config = config,
        _sendMessage = sendMessage,
        _log = log;

  /// Sets callback for heartbeat timeout events
  void setOnHeartbeatTimeout(HeartbeatCallback callback) {
    _onHeartbeatTimeout = callback;
  }

  /// Sets callback for connection health events
  void setOnConnectionHealthy(HeartbeatCallback callback) {
    _onConnectionHealthy = callback;
  }

  /// Sets callback for connection unhealthy events
  void setOnConnectionUnhealthy(HeartbeatCallback callback) {
    _onConnectionUnhealthy = callback;
  }

  /// Starts the heartbeat mechanism
  void start() {
    if (!_config.enableHeartbeat || _isActive) {
      return;
    }

    _isActive = true;
    _missedHeartbeats = 0;
    _waitingForPong = false;
    _log('Starting heartbeat with interval: ${_config.heartbeatInterval}');
    
    _scheduleNextHeartbeat();
  }

  /// Stops the heartbeat mechanism
  void stop() {
    if (!_isActive) {
      return;
    }

    _isActive = false;
    _log('Stopping heartbeat');
    
    _heartbeatTimer?.cancel();
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer = null;
    _waitingForPong = false;
  }

  /// Handles incoming pong messages
  void handlePong(String? message) {
    if (!_isActive) {
      return;
    }

    _lastPongReceived = DateTime.now();
    
    // Check if this is the expected pong response
    bool isExpectedPong = true;
    if (_config.expectedPongMessage != null) {
      isExpectedPong = message == _config.expectedPongMessage;
    }

    if (_waitingForPong && isExpectedPong) {
      _waitingForPong = false;
      _missedHeartbeats = 0;
      _heartbeatTimeoutTimer?.cancel();
      
      _log('Received pong response - connection healthy');
      _onConnectionHealthy?.call();
      
      // Schedule next heartbeat
      _scheduleNextHeartbeat();
    } else if (!isExpectedPong) {
      _log('Received unexpected pong message: $message');
    }
  }

  /// Handles any incoming message (resets heartbeat timeout)
  void handleIncomingMessage(WebSocketMessage message) {
    if (!_isActive) {
      return;
    }

    // Any incoming message indicates the connection is alive
    if (_waitingForPong) {
      // Check if this is a pong message
      if (message.data == _config.expectedPongMessage || 
          (_config.expectedPongMessage == null && message.data.toString().toLowerCase().contains('pong'))) {
        handlePong(message.data.toString());
      }
    }
    
    // Reset missed heartbeats on any activity
    if (_missedHeartbeats > 0) {
      _log('Received message - resetting missed heartbeat count');
      _missedHeartbeats = 0;
      _onConnectionHealthy?.call();
    }
  }

  /// Gets heartbeat statistics
  Map<String, dynamic> getStats() {
    return {
      'isActive': _isActive,
      'missedHeartbeats': _missedHeartbeats,
      'waitingForPong': _waitingForPong,
      'lastHeartbeatSent': _lastHeartbeatSent?.toIso8601String(),
      'lastPongReceived': _lastPongReceived?.toIso8601String(),
      'heartbeatInterval': _config.heartbeatInterval.inSeconds,
      'maxMissedHeartbeats': _config.maxMissedHeartbeats,
    };
  }

  /// Schedules the next heartbeat
  void _scheduleNextHeartbeat() {
    if (!_isActive) {
      return;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(_config.heartbeatInterval, _sendHeartbeat);
  }

  /// Sends a heartbeat message
  Future<void> _sendHeartbeat() async {
    if (!_isActive) {
      return;
    }

    try {
      _lastHeartbeatSent = DateTime.now();
      await _sendMessage(_config.heartbeatMessage);
      _log('Sent heartbeat: ${_config.heartbeatMessage}');
      
      // Start timeout timer if expecting a pong response
      if (_config.expectedPongMessage != null) {
        _waitingForPong = true;
        _startHeartbeatTimeout();
      } else {
        // If not expecting pong, schedule next heartbeat immediately
        _scheduleNextHeartbeat();
      }
    } catch (error) {
      _log('Failed to send heartbeat: $error');
      _handleHeartbeatFailure();
    }
  }

  /// Starts the heartbeat timeout timer
  void _startHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = Timer(_config.heartbeatTimeout, _handleHeartbeatTimeout);
  }

  /// Handles heartbeat timeout
  void _handleHeartbeatTimeout() {
    _missedHeartbeats++;
    _waitingForPong = false;
    
    _log('Heartbeat timeout - missed heartbeats: $_missedHeartbeats/${_config.maxMissedHeartbeats}');
    
    if (_missedHeartbeats >= _config.maxMissedHeartbeats) {
      _log('Maximum missed heartbeats reached - connection considered dead');
      _onConnectionUnhealthy?.call();
      _onHeartbeatTimeout?.call();
    } else {
      _onConnectionUnhealthy?.call();
      // Try again
      _scheduleNextHeartbeat();
    }
  }

  /// Handles heartbeat sending failure
  void _handleHeartbeatFailure() {
    _missedHeartbeats++;
    _waitingForPong = false;
    
    if (_missedHeartbeats >= _config.maxMissedHeartbeats) {
      _log('Maximum heartbeat failures reached');
      _onHeartbeatTimeout?.call();
    } else {
      // Retry after a short delay
      Timer(Duration(seconds: 1), () {
        if (_isActive) {
          _scheduleNextHeartbeat();
        }
      });
    }
  }

  /// Disposes the heartbeat manager
  void dispose() {
    stop();
  }
}
