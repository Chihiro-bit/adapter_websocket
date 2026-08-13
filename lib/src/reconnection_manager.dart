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

  /// Bumped by [stopReconnection]/[reset] to invalidate an in-flight attempt,
  /// so a superseded attempt can neither report success nor reschedule.
  int _generation = 0;

  /// Whether a reconnect attempt is currently awaiting [_reconnectCallback].
  bool _attemptInProgress = false;

  // Callbacks
  void Function()? _onReconnectAttempt;
  void Function()? _onReconnectSuccess;
  void Function(dynamic error)? _onReconnectFailure;
  void Function()? _onMaxAttemptsReached;

  ReconnectionManager({
    required WebSocketConfig config,
    required ReconnectionCallback reconnectCallback,
    required void Function(String) log,
  }) : _config = config,
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

  /// Whether a reconnect attempt is currently in flight.
  ///
  /// When `true`, callers observing a fresh disconnection should
  /// [stopReconnection] before [startReconnection] so the event is not lost.
  bool get isAttemptInProgress => _attemptInProgress;

  bool get isReconnecting => _isReconnecting;

  /// Starts reconnection process
  void startReconnection() {
    if (!_config.autoReconnect || _isReconnecting) {
      return;
    }

    final maxAttempts = _config.maxReconnectAttempts;
    final hasLimit = maxAttempts > 0;

    if (hasLimit && _reconnectAttempts >= maxAttempts) {
      _log('Maximum reconnection attempts ($maxAttempts) reached');
      _onMaxAttemptsReached?.call();
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;
    _generation++;

    final delay = _calculateDelay();
    final limitText = hasLimit ? '$maxAttempts' : 'unlimited';
    _log(
      'Scheduling reconnection attempt $_reconnectAttempts/$limitText in ${delay.inSeconds}s',
    );

    final generation = _generation;
    _reconnectTimer = Timer(delay, () => _attemptReconnection(generation));
  }

  /// Stops reconnection process (invalidates any in-flight attempt)
  void stopReconnection() {
    _generation++;
    _isReconnecting = false;
    _attemptInProgress = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Resets reconnection state (call on successful connection)
  void reset() {
    _generation++;
    _reconnectAttempts = 0;
    _currentDelay = _config.reconnectDelay;
    _isReconnecting = false;
    _attemptInProgress = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Gets current reconnection statistics
  Map<String, dynamic> getStats() {
    final maxAttempts = _config.maxReconnectAttempts;
    return {
      'isReconnecting': _isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': maxAttempts > 0 ? maxAttempts : 'unlimited',
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

    // Exponential backoff with jitter. The exponent is capped so pow() never
    // overflows to Infinity with unlimited retries (would crash on round()).
    final baseDelay = _config.reconnectDelay.inMilliseconds;
    final exponent = min(_reconnectAttempts - 1, 60);
    final exponentialDelay =
        baseDelay * pow(_config.backoffMultiplier, exponent);

    // Add jitter (±25% of the delay)
    final jitter = exponentialDelay * 0.25 * (Random().nextDouble() * 2 - 1);
    final totalDelay = (exponentialDelay + jitter).round();

    // Cap at maximum delay
    final cappedDelay = min(
      totalDelay,
      _config.maxReconnectDelay.inMilliseconds,
    );

    _currentDelay = Duration(milliseconds: cappedDelay);
    return _currentDelay;
  }

  /// Attempts to reconnect
  Future<void> _attemptReconnection(int generation) async {
    if (!_isReconnecting || generation != _generation) {
      return;
    }
    _attemptInProgress = true;

    _log('Attempting reconnection (attempt $_reconnectAttempts)');
    _onReconnectAttempt?.call();

    try {
      await _reconnectCallback();
      if (generation != _generation) return;
      _log('Reconnection successful');
      _onReconnectSuccess?.call();
      reset();
    } catch (error) {
      if (generation != _generation) return;
      _log('Reconnection attempt $_reconnectAttempts failed: $error');
      _onReconnectFailure?.call(error);
      _isReconnecting = false;

      // Schedule next attempt
      startReconnection();
    } finally {
      // A superseded attempt (stopReconnection() mid-flight) already cleared
      // this flag; clearing it again is harmless.
      _attemptInProgress = false;
    }
  }

  /// Disposes the reconnection manager
  void dispose() {
    stopReconnection();
  }
}
