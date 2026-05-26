import 'dart:collection';
import 'websocket_message.dart';

/// A single message held in the queue with metadata for expiry tracking.
class QueuedMessage {
  final WebSocketMessage message;
  final DateTime enqueuedAt;
  final Duration? timeout;
  final bool useAck;

  QueuedMessage({
    required this.message,
    required this.enqueuedAt,
    this.timeout,
    this.useAck = false,
  });

  bool get isExpired {
    if (timeout == null) return false;
    return DateTime.now().difference(enqueuedAt) > timeout!;
  }
}

/// Buffers outgoing messages while the connection is down.
///
/// When the connection is restored, call [drain] to retrieve all valid
/// (non-expired) messages and send them in order.
class MessageQueue {
  final int maxSize;
  final Duration? messageTimeout;

  final Queue<QueuedMessage> _queue = Queue();

  MessageQueue({
    this.maxSize = 100,
    this.messageTimeout,
  });

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Returns `true` when the queue has reached [maxSize].
  bool get isFull => maxSize > 0 && _queue.length >= maxSize;

  /// Adds [message] to the queue. Returns `false` if the queue is full.
  bool enqueue(WebSocketMessage message, {bool useAck = false}) {
    if (isFull) return false;
    _queue.add(QueuedMessage(
      message: message,
      enqueuedAt: DateTime.now(),
      timeout: messageTimeout,
      useAck: useAck,
    ));
    return true;
  }

  /// Removes and returns all non-expired messages. Expired messages are discarded.
  List<QueuedMessage> drain() {
    final result = <QueuedMessage>[];
    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      if (!item.isExpired) result.add(item);
    }
    return result;
  }

  /// Re-inserts [item] at the front of the queue (used to requeue on send failure).
  void requeueFront(QueuedMessage item) {
    _queue.addFirst(item);
  }

  /// Removes messages that have exceeded their [messageTimeout].
  void purgeExpired() {
    _queue.removeWhere((m) => m.isExpired);
  }

  void clear() => _queue.clear();

  Map<String, dynamic> getStats() => {
        'queueLength': _queue.length,
        'maxSize': maxSize,
        'isFull': isFull,
        'timeoutMs': messageTimeout?.inMilliseconds,
      };
}
