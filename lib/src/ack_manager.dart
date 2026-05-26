import 'dart:async';
import 'dart:math';
import 'websocket_message.dart';

/// Metadata key injected into outgoing messages.
const _kAckIdKey = '__ack_id__';

/// Key the server must include in its ACK response payload.
const _kAckResponseKey = '__ack__';

class _PendingAck {
  final String id;
  final WebSocketMessage message;
  int retryCount = 0;
  Timer? _timer;
  final Completer<void> _completer = Completer<void>();

  _PendingAck({required this.id, required this.message});

  Future<void> get future => _completer.future;

  void scheduleTimeout(Duration duration, void Function(_PendingAck) onTimeout) {
    _timer?.cancel();
    _timer = Timer(duration, () => onTimeout(this));
  }

  void complete() {
    _timer?.cancel();
    if (!_completer.isCompleted) _completer.complete();
  }

  void fail(Object error) {
    _timer?.cancel();
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}

typedef _RawSender = Future<void> Function(WebSocketMessage message);

/// Tracks outgoing messages and waits for server ACK responses.
///
/// Outgoing messages receive an `__ack_id__` injected into their metadata.
/// The server must respond with `{"__ack__": "<id>"}` to acknowledge receipt.
/// On timeout the message is retried up to [maxRetries] times before failing.
class AckManager {
  final Duration timeout;
  final int maxRetries;
  final _RawSender _sender;
  final void Function(String) _log;

  final Map<String, _PendingAck> _pending = {};
  bool _disposed = false;

  AckManager({
    required this.timeout,
    required this.maxRetries,
    required Future<void> Function(WebSocketMessage message) sender,
    required void Function(String) log,
  })  : _sender = sender,
        _log = log;

  static String _generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(99999).toString().padLeft(5, '0');
    return '${ts}_$rand';
  }

  /// Sends [message] and returns a [Future] that completes when the server
  /// acknowledges it, or throws [TimeoutException] after retries are exhausted.
  ///
  /// The `__ack_id__` is embedded directly in the wire payload so the server
  /// can read it without any custom framing. For Map payloads the key is merged
  /// at the top level; for all other payloads the data is wrapped as
  /// `{"__ack_id__": id, "payload": data}`.
  Future<void> sendWithAck(WebSocketMessage message) {
    if (_disposed) return Future.error(StateError('AckManager disposed'));

    final id = _generateId();
    final meta = Map<String, dynamic>.from(message.metadata ?? {});
    meta[_kAckIdKey] = id;

    // Embed __ack_id__ into the wire payload so the server receives it.
    final dynamic wireData;
    final data = message.data;
    if (data is Map<String, dynamic>) {
      wireData = {...data, _kAckIdKey: id};
    } else {
      wireData = {_kAckIdKey: id, 'payload': data};
    }

    final wrapped = WebSocketMessage(
      data: wireData,
      timestamp: message.timestamp,
      type: 'json',
      metadata: meta,
    );

    final pending = _PendingAck(id: id, message: wrapped);
    _pending[id] = pending;

    _sender(wrapped).then((_) {
      pending.scheduleTimeout(timeout, _onTimeout);
    }).catchError((e) {
      _pending.remove(id);
      pending.fail(e);
    });

    return pending.future;
  }

  /// Call with every incoming message. Returns `true` if the message was an ACK
  /// (it should not be forwarded to the user in that case).
  bool handleIncomingMessage(WebSocketMessage message) {
    final data = message.data;
    if (data is! Map) return false;
    final ackId = data[_kAckResponseKey];
    if (ackId is! String) return false;

    final pending = _pending.remove(ackId);
    if (pending == null) return false;

    _log('ACK received for $ackId');
    pending.complete();
    return true;
  }

  void _onTimeout(_PendingAck pending) {
    if (!_pending.containsKey(pending.id)) return;

    if (pending.retryCount < maxRetries) {
      pending.retryCount++;
      _log('ACK timeout for ${pending.id} — retry ${pending.retryCount}/$maxRetries');
      _sender(pending.message).then((_) {
        pending.scheduleTimeout(timeout, _onTimeout);
      }).catchError((e) {
        _pending.remove(pending.id);
        pending.fail(e);
      });
    } else {
      _log('ACK max retries exhausted for ${pending.id}');
      _pending.remove(pending.id);
      pending.fail(TimeoutException(
        'No ACK received for ${pending.id} after $maxRetries retries',
        timeout,
      ));
    }
  }

  void dispose() {
    _disposed = true;
    for (final p in _pending.values) {
      p.fail(StateError('AckManager disposed'));
    }
    _pending.clear();
  }

  Map<String, dynamic> getStats() => {
        'pendingAcks': _pending.length,
        'timeoutMs': timeout.inMilliseconds,
        'maxRetries': maxRetries,
      };
}
