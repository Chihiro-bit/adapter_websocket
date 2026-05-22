import 'dart:async';
import 'dart:convert';
import 'websocket_message.dart';
import 'websocket_topic.dart';

/// Routes incoming messages to registered [WebSocketTopic]s and wraps outgoing
/// messages in the topic envelope format.
///
/// Envelope format (JSON string over the wire):
/// ```json
/// {"topic": "room:lobby", "event": "new_message", "payload": {...}}
/// ```
class ChannelManager {
  final Future<void> Function(dynamic data) _rawSend;
  final Map<String, WebSocketTopic> _topics = {};

  static const _kTopic = 'topic';
  static const _kEvent = 'event';
  static const _kPayload = 'payload';

  ChannelManager({required Future<void> Function(dynamic) rawSend})
      : _rawSend = rawSend;

  /// Returns (creating if necessary) the [WebSocketTopic] for [topic].
  WebSocketTopic channel(String topic) {
    return _topics.putIfAbsent(
      topic,
      () => WebSocketTopic(
        topic: topic,
        sender: (t, event, payload) => _sendEnvelope(t, event, payload),
      ),
    );
  }

  Future<void> _sendEnvelope(
      String topic, String event, dynamic payload) async {
    final envelope = jsonEncode({
      _kTopic: topic,
      _kEvent: event,
      _kPayload: payload,
    });
    await _rawSend(envelope);
  }

  /// Tries to route [message] to a registered topic.
  ///
  /// Returns `true` if the message was a topic envelope and was routed.
  bool route(WebSocketMessage message) {
    Map<String, dynamic>? envelope;

    final data = message.data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) envelope = decoded;
      } catch (_) {
        return false;
      }
    } else if (data is Map<String, dynamic>) {
      envelope = data;
    }

    if (envelope == null) return false;
    final topicName = envelope[_kTopic] as String?;
    if (topicName == null) return false;

    final topic = _topics[topicName];
    if (topic == null) return false;

    final event = envelope[_kEvent] as String? ?? 'message';
    final payload = envelope[_kPayload];

    topic.push(WebSocketMessage(
      data: payload,
      timestamp: DateTime.now(),
      type: event,
      metadata: {_kTopic: topicName, _kEvent: event},
    ));
    return true;
  }

  Future<void> dispose() async {
    for (final t in _topics.values) {
      await t.dispose();
    }
    _topics.clear();
  }

  Map<String, dynamic> getStats() => {
        'activeTopics': _topics.length,
        'topics': _topics.keys.toList(),
      };
}
