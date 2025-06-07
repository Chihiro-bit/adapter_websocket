import 'dart:async';
import 'dart:math';
import 'websocket_config.dart';

/// Callback type for reconnection attempts
typedef ReconnectionCallback = Future<void> Function();

/// Manages reconnection logic with exponential backoff
class ReconnectionManager {
  final WebSocketConfig _config;
  final ReconnectionCallback _reconnectCallback;
  final void Function(String) _log;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;
  Duration _currentDelay;

  // Callbacks
  void Function()? _onReconnectAttempt;
  void Function()? _onReconnectSuccess;
  void Function(dynamic error)? _onReconnectFailure;
  void Function()? _onMaxAttemptsReached;

  ReconnectionManager({
    required WebSocketConfig config,
    required ReconnectionCallback reconnectCallback,
    required void Function(String) log,
  })  : _config = config,
        _reconnectCallback = reconnectCallback,
        _log = log,
        _currentDelay = config.reconnectDelay;

  /// Sets callback for reconnection attempt events
  void setOnReconnectAttempt(void Function() callback) {
    _onReconnectAttempt = callback;
  }

  /// Sets callback for successful reconnection
  void setOnReconnectSuccess(void Function() callback) {
    _onReconnectSuccess = callback;
  }

  /// Sets callback for failed reconnection
  void setOnReconnectFailure(void Function(dynamic error) callback) {
    _onReconnectFailure = callback;
  }

  /// Sets callback for max attempts reached
  void setOnMaxAttemptsReached(void Function() callback) {
    _onMaxAttemptsReached = callback;
  }

  /// Starts reconnection process
  void startReconnection() {
    if (!_config.autoReconnect || _isReconnecting) {
      return;
    }

    if (_reconnectAttempts >= _config.maxReconnectAttempts) {
      _log('Maximum reconnection attempts (${_config.maxReconnectAttempts}) reached');
      _onMaxAttemptsReached?.call();
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;
    
    final delay = _calculateDelay();
    _log('Scheduling reconnection attempt $_reconnectAttempts/${_config.maxReconnectAttempts} in ${delay.inSeconds}s');
    
    _reconnectTimer = Timer(delay, _attemptReconnection);
  }

  /// Stops reconnection process
  void stopReconnection() {
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Resets reconnection state (call on successful connection)
  void reset() {
    _reconnectAttempts = 0;
    _currentDelay = _config.reconnectDelay;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Gets current reconnection statistics
  Map<String, dynamic> getStats() {
    return {
      'isReconnecting': _isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': _config.maxReconnectAttempts,
      'currentDelay': _currentDelay.inSeconds,
      'nextAttemptIn': _reconnectTimer?.isActive == true 
          ? 'scheduled' 
          : 'not scheduled',
    };
  }

  /// Calculates the delay for the next reconnection attempt
  Duration _calculateDelay() {
    if (!_config.useExponentialBackoff) {
      return _config.reconnectDelay;
    }

    // Exponential backoff with jitter
    final baseDelay = _config.reconnectDelay.inMilliseconds;
    final exponentialDelay = baseDelay * pow(_config.backoffMultiplier, _reconnectAttempts - 1);
    
    // Add jitter (±25% of the delay)
    final jitter = exponentialDelay * 0.25 * (Random().nextDouble() * 2 - 1);
    final totalDelay = (exponentialDelay + jitter).round();
    
    // Cap at maximum delay
    final cappedDelay = min(totalDelay, _config.maxReconnectDelay.inMilliseconds);
    
    _currentDelay = Duration(milliseconds: cappedDelay);
    return _currentDelay;
  }

  /// Attempts to reconnect
  Future<void> _attemptReconnection() async {
    if (!_isReconnecting) {
      return;
    }

    _log('Attempting reconnection (attempt $_reconnectAttempts)');
    _onReconnectAttempt?.call();

    try {
      await _reconnectCallback();
      _log('Reconnection successful');
      _onReconnectSuccess?.call();
      reset();
    } catch (error) {
      _log('Reconnection attempt $_reconnectAttempts failed: $error');
      _onReconnectFailure?.call(error);
      _isReconnecting = false;
      
      // Schedule next attempt
      startReconnection();
    }
  }

  /// Disposes the reconnection manager
  void dispose() {
    stopReconnection();
  }
}
