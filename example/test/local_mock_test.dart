// Integration test for the example's LocalMockWebSocketAdapter: verifies the
// in-process mock server answers echo/heartbeat/ACK/topic traffic and that
// simulated disconnects trigger the plugin's auto-reconnection.
import 'dart:async';

import 'package:adapter_websocket/adapter_websocket.dart';
import 'package:adapter_websocket_example/local_mock_websocket_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

WebSocketConfig _config() => WebSocketConfig(
  url: 'ws://127.0.0.1:0/ws',
  autoReconnect: true,
  reconnectDelay: const Duration(milliseconds: 300),
  useExponentialBackoff: false,
  enableLogging: false,
  enableHeartbeat: true,
  heartbeatInterval: const Duration(milliseconds: 300),
  heartbeatTimeout: const Duration(milliseconds: 600),
  heartbeatMessage: '{"type":"heartbeat"}',
  expectedPongMessage: '{"type":"heartbeat_ack"}',
  maxMissedHeartbeats: 2,
  enableMessageQueue: true,
  enableAck: true,
  ackTimeout: const Duration(seconds: 2),
  maxAckRetries: 1,
);

void main() {
  test('mock server answers echo, heartbeat, ACK and topic traffic', () async {
    final mock = await LocalMockWebSocketAdapter.create(_config());
    final client = WebSocketClient(mock);
    addTearDown(client.dispose);

    // The adapter's config.url is the real local server URL on native;
    // the web transport uses an in-memory link instead.
    expect(
      mock.serverUrl,
      anyOf(startsWith('ws://127.0.0.1:'), 'mock://in-memory'),
    );

    await client.connect();
    expect(client.isConnected, isTrue);

    // ── Echo ──────────────────────────────────────────────────────────
    final received = <WebSocketMessage>[];
    client.messageStream.listen(received.add);

    await client.sendText('hello');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      received.any((m) => m.data is Map && m.data['type'] == 'echo'),
      isTrue,
      reason: 'server should echo non-JSON text as {"type":"echo",…}',
    );

    // ── ACK ───────────────────────────────────────────────────────────
    await client.sendMessage(WebSocketMessage.json({'x': 1}), useAck: true);
    expect(
      client.connectionStats['ack']?['pendingAcks'],
      0,
      reason: 'server must auto-ack __ack_id__ frames',
    );

    // ── Heartbeat ─────────────────────────────────────────────────────
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final hb = client.connectionStats['heartbeat'] as Map;
    expect(
      hb['missedHeartbeats'],
      0,
      reason: 'server must answer the heartbeat with the configured pong',
    );
    expect(hb['lastPongReceived'], isNotNull);

    // ── Topic ─────────────────────────────────────────────────────────
    final topic = client.channel('room:test');
    final topicReceived = <WebSocketMessage>[];
    topic.messageStream.listen(topicReceived.add);
    await topic.send('ping_topic', {'a': 1});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(topicReceived, hasLength(1));
    expect(topicReceived.single.data, {
      'reply': 'hello from local mock',
      'echo': {'a': 1},
    });

    // ── Simulated disconnect → auto-reconnect ─────────────────────────
    final disconnected = Completer<void>();
    client.stateStream.listen((state) {
      if (state == WebSocketState.disconnected) {
        if (!disconnected.isCompleted) disconnected.complete();
      }
    });

    mock.simulateDisconnectNow();
    await disconnected.future.timeout(const Duration(seconds: 3));

    // The plugin reconnects automatically (autoReconnect + fast delay).
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(
      client.isConnected,
      isTrue,
      reason: 'client must auto-reconnect after a simulated drop',
    );
  });
}
