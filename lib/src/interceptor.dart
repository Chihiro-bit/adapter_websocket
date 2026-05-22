import 'dart:async';
import 'websocket_message.dart';

/// Interceptor that can inspect and transform messages before sending or after receiving.
///
/// Return `null` from any method to suppress the message entirely.
abstract class WebSocketInterceptor {
  /// Called before a message is sent. Return `null` to drop the message.
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async => message;

  /// Called after a message is received. Return `null` to drop the message.
  Future<WebSocketMessage?> onReceive(WebSocketMessage message) async => message;

  /// Called when a connection error occurs. Return `null` to suppress the error.
  Future<dynamic> onError(dynamic error) async => error;
}

/// Manages an ordered chain of [WebSocketInterceptor]s.
class InterceptorChain {
  final List<WebSocketInterceptor> _interceptors = [];

  List<WebSocketInterceptor> get interceptors =>
      List.unmodifiable(_interceptors);

  void add(WebSocketInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  void remove(WebSocketInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  void clear() => _interceptors.clear();

  bool get isEmpty => _interceptors.isEmpty;

  /// Runs message through each interceptor's [onSend]. Returns `null` if suppressed.
  Future<WebSocketMessage?> processSend(WebSocketMessage message) async {
    WebSocketMessage? current = message;
    for (final interceptor in _interceptors) {
      if (current == null) return null;
      current = await interceptor.onSend(current);
    }
    return current;
  }

  /// Runs message through each interceptor's [onReceive]. Returns `null` if suppressed.
  Future<WebSocketMessage?> processReceive(WebSocketMessage message) async {
    WebSocketMessage? current = message;
    for (final interceptor in _interceptors) {
      if (current == null) return null;
      current = await interceptor.onReceive(current);
    }
    return current;
  }

  /// Runs error through each interceptor's [onError]. Returns `null` if suppressed.
  Future<dynamic> processError(dynamic error) async {
    dynamic current = error;
    for (final interceptor in _interceptors) {
      if (current == null) return null;
      current = await interceptor.onError(current);
    }
    return current;
  }
}

/// A simple logging interceptor for debugging.
class LoggingInterceptor extends WebSocketInterceptor {
  final void Function(String message) _logger;
  final String tag;

  LoggingInterceptor({
    required void Function(String) logger,
    this.tag = 'WS',
  }) : _logger = logger;

  @override
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async {
    _logger('[$tag][SEND] type=${message.type} data=${_truncate(message.data)}');
    return message;
  }

  @override
  Future<WebSocketMessage?> onReceive(WebSocketMessage message) async {
    _logger('[$tag][RECV] type=${message.type} data=${_truncate(message.data)}');
    return message;
  }

  @override
  Future<dynamic> onError(dynamic error) async {
    _logger('[$tag][ERR] $error');
    return error;
  }

  String _truncate(dynamic data) {
    final s = data.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
