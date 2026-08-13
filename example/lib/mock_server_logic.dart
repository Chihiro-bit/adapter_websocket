import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:adapter_websocket/adapter_websocket.dart';

/// Transport-agnostic handle for one server-side connection.
abstract class MockConnection {
  /// Server → client frame.
  void add(dynamic data);

  /// Server-side close.
  Future<void> close();
}

/// The mock server behaviour, shared by the native transport (a real local
/// WebSocket server) and the web transport (an in-memory duplex link):
/// auto-pong, auto-ack, topic echo, periodic broadcasts and simulated
/// disconnects.
class MockServerLogic {
  final WebSocketConfig _config;
  final Set<MockConnection> _clients = {};
  final Random _random = Random();

  Timer? _broadcastTimer;
  Timer? _disconnectTimer;
  int _broadcastCount = 0;

  MockServerLogic(this._config);

  // ─── Connection lifecycle ─────────────────────────────────────────────────

  void attach(MockConnection connection) => _clients.add(connection);

  void detach(MockConnection connection) => _clients.remove(connection);

  // ─── Behaviours ───────────────────────────────────────────────────────────

  void startBroadcasts() {
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_clients.isEmpty) return;
      _broadcastCount++;
      final event = jsonEncode({
        'type': 'server_event',
        'content': _randomBroadcast(),
        'seq': _broadcastCount,
        'time': DateTime.now().toIso8601String(),
      });
      for (final connection in _clients.toList()) {
        connection.add(event);
      }
    });
  }

  /// Toggles periodic abrupt server-side disconnections (every 12 s) to
  /// demonstrate the plugin's auto-reconnection.
  void setSimulateDisconnects(bool value) {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    if (value) {
      _disconnectTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        dropAllConnections();
      });
    }
  }

  /// Closes every connection server-side. The plugin's auto-reconnect then
  /// kicks in on the client.
  void dropAllConnections() {
    for (final connection in _clients.toList()) {
      connection.close();
    }
  }

  Future<void> dispose() async {
    _broadcastTimer?.cancel();
    _disconnectTimer?.cancel();
    for (final connection in _clients.toList()) {
      await connection.close();
    }
    _clients.clear();
  }

  /// Handles one client → server frame.
  void handleClientData(MockConnection connection, dynamic data) {
    if (data is! String) {
      connection.add(data); // echo binary frames
      return;
    }

    final Map<String, dynamic>? map = _tryDecodeMap(data);
    if (map == null) {
      connection.add(jsonEncode({'type': 'echo', 'content': data}));
      return;
    }

    // 1. ACK control frames: reply with {"__ack__": "<id>"}.
    final ackId = map['__ack_id__'];
    if (ackId is String) {
      connection.add(jsonEncode({'__ack__': ackId}));
      return;
    }

    // 2. Heartbeat: reply with the configured pong message.
    if (_config.enableHeartbeat && map['type'] == 'heartbeat') {
      connection.add(_config.expectedPongMessage ?? 'pong');
      return;
    }

    // 3. Topic envelopes: reply on the same topic.
    final topic = map['topic'];
    if (topic is String) {
      connection.add(
        jsonEncode({
          'topic': topic,
          'event': 'mock_reply',
          'payload': {'reply': 'hello from local mock', 'echo': map['payload']},
        }),
      );
      return;
    }

    // 4. Anything else: echo it back as a server event.
    connection.add(
      jsonEncode({
        'type': 'server_echo',
        'content': map,
        'time': DateTime.now().toIso8601String(),
      }),
    );
  }

  String _randomBroadcast() {
    const messages = [
      'Local mock server: connection is healthy',
      'Periodic event from the in-process mock',
      'You are testing adapter_websocket offline',
      'Try the Queue tab: disconnect, send a message, then reconnect',
      'Toggle "Simulate disconnects" to watch auto-reconnect',
    ];
    return messages[_random.nextInt(messages.length)];
  }

  Map<String, dynamic>? _tryDecodeMap(String data) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
