// Regression tests for the 2026-08 high-severity fixes:
// connect() timeout/race, heartbeat stop race, heartbeat threshold
// deactivation, reconnection supersede, route() hardcast, ACK requeue,
// drain fire-and-forget, error interceptor forwarding, queue fallback.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adapter_websocket/adapter_websocket.dart';
import 'package:adapter_websocket/src/heartbeat_manager.dart';
import 'package:adapter_websocket/src/reconnection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void _noopLog(String _) {}

WebSocketConfig _config({
  String url = 'ws://localhost:8080/ws',
  bool enableHeartbeat = false,
  bool enableMessageQueue = false,
  bool enableAck = false,
  bool autoReconnect = false,
  Duration ackTimeout = const Duration(seconds: 30),
  int maxAckRetries = 3,
}) {
  return WebSocketConfig(
    url: url,
    enableHeartbeat: enableHeartbeat,
    enableMessageQueue: enableMessageQueue,
    enableAck: enableAck,
    autoReconnect: autoReconnect,
    ackTimeout: ackTimeout,
    maxAckRetries: maxAckRetries,
    reconnectDelay: const Duration(milliseconds: 50),
    enableLogging: false,
  );
}

/// Starts a TCP server that accepts connections but never completes the
/// WebSocket handshake — used to reproduce a stalled connection.
Future<ServerSocket> _startHangingServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    // Swallow all data and never respond: the handshake stalls forever.
    socket.listen((_) {});
  });
  return server;
}

void main() {
  group('WebSocketChannelAdapter connect()', () {
    test(
      'timeout completes connect() with an error instead of hanging',
      () async {
        final server = await _startHangingServer();
        final adapter = WebSocketChannelAdapter(
          _config(
            url: 'ws://127.0.0.1:${server.port}/ws',
          ).copyWith(connectionTimeout: const Duration(milliseconds: 200)),
        );

        final errors = <dynamic>[];
        adapter.errorStream.listen(errors.add);

        // With the old code this future never completed. It must now throw.
        await expectLater(adapter.connect(), throwsA(anything));

        expect(adapter.currentState, WebSocketState.error);
        // The failure is reported exactly once (not by both the internal timer
        // and the channel's own timeout).
        expect(errors, hasLength(1));

        await server.close();
        await adapter.dispose();
      },
    );

    test('connect/echo/disconnect against a real local server', () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final echoStreams = <WebSocket>[];
      http.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        echoStreams.add(ws);
        ws.listen(ws.add);
      });

      final adapter = WebSocketChannelAdapter(
        _config(url: 'ws://127.0.0.1:${http.port}/ws'),
      );

      final messages = <WebSocketMessage>[];
      adapter.messageStream.listen(messages.add);

      await adapter.connect();
      expect(adapter.isConnected, isTrue);

      await adapter.sendMessage(WebSocketMessage.text('hello'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(messages.map((m) => m.data), contains('hello'));

      await adapter.disconnect();
      expect(adapter.isClosed, isTrue);

      // Reconnect exercises the generation counter / resubscribe path.
      await adapter.connect();
      expect(adapter.isConnected, isTrue);
      await adapter.disconnect();

      await http.close(force: true);
      await adapter.dispose();
    });
  });

  group('HeartbeatManager', () {
    test(
      'stop() during an in-flight send does not re-arm the timeout timer',
      () async {
        final gate = Completer<void>();
        final manager = HeartbeatManager(
          config: WebSocketConfig(
            url: 'ws://localhost:8080/ws',
            enableHeartbeat: true,
            heartbeatInterval: const Duration(milliseconds: 30),
            heartbeatTimeout: const Duration(milliseconds: 50),
            expectedPongMessage: 'pong',
            maxMissedHeartbeats: 2,
          ),
          sendMessage: (_) => gate.future,
          log: _noopLog,
        );

        var timeouts = 0;
        manager.setOnHeartbeatTimeout(() => timeouts++);
        manager.start();

        // Heartbeat fires at ~30ms and the send is now in-flight on `gate`.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        manager.stop();
        // The send completes only after stop() — with the old code this
        // re-armed a zombie timeout timer that eventually triggered the
        // timeout callback after a user-initiated disconnect.
        gate.complete();

        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(timeouts, 0);
        expect(manager.getStats()['isActive'], isFalse);
      },
    );

    test(
      'deactivates after max missed heartbeats and can be restarted',
      () async {
        final manager = HeartbeatManager(
          config: WebSocketConfig(
            url: 'ws://localhost:8080/ws',
            enableHeartbeat: true,
            heartbeatInterval: const Duration(milliseconds: 30),
            heartbeatTimeout: const Duration(milliseconds: 40),
            expectedPongMessage: 'pong',
            maxMissedHeartbeats: 2,
          ),
          sendMessage: (_) async {}, // pong never arrives
          log: _noopLog,
        );

        var timeouts = 0;
        manager.setOnHeartbeatTimeout(() => timeouts++);
        manager.start();

        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(timeouts, 1);
        // With the old code the manager stayed "active" but permanently dead.
        expect(manager.getStats()['isActive'], isFalse);

        // A later start() (e.g. after reconnection) must work again.
        manager.start();
        expect(manager.getStats()['isActive'], isTrue);
        manager.stop();
      },
    );
  });

  group('ReconnectionManager', () {
    test('a disconnect during an in-flight attempt is not swallowed', () async {
      final gate = Completer<void>();
      var calls = 0;
      var successes = 0;

      final manager = ReconnectionManager(
        config: WebSocketConfig(
          url: 'ws://localhost:8080/ws',
          autoReconnect: true,
          reconnectDelay: const Duration(milliseconds: 50),
          maxReconnectAttempts: 3,
          useExponentialBackoff: false,
        ),
        reconnectCallback: () async {
          calls++;
          if (calls == 1) await gate.future; // first attempt stalls
        },
        log: _noopLog,
      );
      manager.setOnReconnectSuccess(() => successes++);

      manager.startReconnection();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(manager.isAttemptInProgress, isTrue);

      // A fresh disconnection arrives while the attempt is in flight: the
      // client restarts the cycle so the event is not lost.
      manager.stopReconnection();
      manager.startReconnection();
      expect(manager.isAttemptInProgress, isFalse);

      // The stalled attempt "succeeds" now, but it has been superseded and
      // must neither report success nor cancel the new cycle.
      gate.complete();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      // The new cycle ran a real attempt which succeeded.
      expect(calls, 2);
      expect(successes, 1);
      expect(manager.isReconnecting, isFalse);
    });
  });

  group('ChannelManager.route', () {
    test('does not throw on server-controlled malformed envelopes', () async {
      final manager = ChannelManager(sendMessage: (_) async {});
      final topic = manager.channel('room');
      final received = <WebSocketMessage>[];
      topic.messageStream.listen(received.add);

      // topic is not a string → not routed, no TypeError.
      expect(manager.route(WebSocketMessage.json({'topic': 123})), isFalse);

      // event is not a string → falls back to 'message'.
      expect(
        manager.route(
          WebSocketMessage.json({
            'topic': 'room',
            'event': 42,
            'payload': {'x': 1},
          }),
        ),
        isTrue,
      );

      // String-encoded envelope.
      expect(
        manager.route(
          WebSocketMessage.text(jsonEncode({'topic': 'room', 'payload': 'hi'})),
        ),
        isTrue,
      );

      // Broadcast stream delivery is asynchronous.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].type, 'message');
      expect(received[0].data, {'x': 1});
      expect(received[1].data, 'hi');
    });
  });

  group('AckManager', () {
    test(
      'detach + requeue reuses the pending entry and completes on ACK',
      () async {
        final sent = <WebSocketMessage>[];
        final manager = AckManager(
          timeout: const Duration(milliseconds: 100),
          maxRetries: 1,
          sender: (m) async => sent.add(m),
          log: _noopLog,
        );

        final future = manager.sendWithAck(
          WebSocketMessage.json({'hello': 'world'}),
        );
        expect(sent, hasLength(1));

        // On disconnect the client detaches pendings and requeues them.
        final detached = manager.detachPendingForRequeue();
        expect(detached, hasLength(1));
        // Idempotent: a second disconnect event returns nothing new.
        expect(manager.detachPendingForRequeue(), isEmpty);

        // The queue drain re-sends the wrapped message; the original id and
        // pending entry are reused so the caller's future still completes.
        final resent = manager.sendWithAck(detached.single.message);
        expect(identical(future, resent), isTrue);
        expect(sent, hasLength(2));

        // Server acknowledges with the ORIGINAL id.
        manager.handleIncomingMessage(
          WebSocketMessage.json({'__ack__': detached.single.id}),
        );
        await future; // completes without error
        expect(manager.getStats()['pendingAcks'], 0);
      },
    );

    test('consumes late ACK frames even without a pending entry', () {
      final manager = AckManager(
        timeout: const Duration(milliseconds: 100),
        maxRetries: 1,
        sender: (_) async {},
        log: _noopLog,
      );

      // A late ACK (retries already exhausted) must not leak into the
      // business message stream.
      expect(
        manager.handleIncomingMessage(
          WebSocketMessage.json({'__ack__': 'unknown'}),
        ),
        isTrue,
      );
      // Non-ACK frames are not consumed.
      expect(
        manager.handleIncomingMessage(WebSocketMessage.json({'x': 1})),
        isFalse,
      );
    });

    test('failAllPending fails every outstanding caller', () async {
      final manager = AckManager(
        timeout: const Duration(milliseconds: 100),
        maxRetries: 1,
        sender: (_) async {},
        log: _noopLog,
      );

      final f1 = manager.sendWithAck(WebSocketMessage.text('a'));
      final f2 = manager.sendWithAck(WebSocketMessage.text('b'));
      manager.failAllPending(StateError('Client disconnected'));

      await expectLater(f1, throwsStateError);
      await expectLater(f2, throwsStateError);
    });
  });

  group('WebSocketClient drain', () {
    test(
      'unacknowledged ACK message does not block the rest of the queue',
      () async {
        final mock = MockWebSocketAdapter(
          _config(
            enableMessageQueue: true,
            enableAck: true,
            ackTimeout: const Duration(milliseconds: 200),
            maxAckRetries: 0,
          ),
        );
        final client = WebSocketClient(mock);

        // Queue three messages while disconnected; the first requires an ACK
        // that the server will never send.
        await client.sendMessage(
          WebSocketMessage.json({'ack': 1}),
          useAck: true,
        );
        await client.sendText('two');
        await client.sendText('three');
        expect(mock.sentMessages, isEmpty);

        await client.connect();
        // Well before the first message's ACK timeout, all three messages must
        // already be on the wire (old code blocked the queue behind the first
        // message for the full ACK timeout).
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(mock.sentMessages, hasLength(3));

        // Let the ACK timeout fire and settle so no timers leak.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await client.dispose();
      },
    );

    test(
      'send failure while connected falls back to the message queue',
      () async {
        final mock = MockWebSocketAdapter(_config(enableMessageQueue: true));
        final client = WebSocketClient(mock);
        await client.connect();

        mock.setShouldFailSending(true);
        // With the old code this threw and the message was lost.
        await client.sendText('hello');
        expect(client.connectionStats['messageQueue']['queueLength'], 1);

        mock.setShouldFailSending(false);
        await client.connect(); // triggers drain
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(mock.sentMessages.map((m) => m.data), contains('hello'));
        expect(client.connectionStats['messageQueue']['queueLength'], 0);

        await client.dispose();
      },
    );
  });

  group('WebSocketClient errorStream', () {
    test('forwards errors through the error interceptors', () async {
      final mock = MockWebSocketAdapter(_config());
      final client = WebSocketClient(mock);
      client.addInterceptor(_TransformingErrorInterceptor());

      await client.connect();
      final emitted = expectLater(client.errorStream, emits('wrapped:boom'));
      mock.simulateError('boom');
      await emitted;

      await client.dispose();
    });

    test('an interceptor returning null suppresses the error', () async {
      final mock = MockWebSocketAdapter(_config());
      final client = WebSocketClient(mock);
      client.addInterceptor(_SuppressingErrorInterceptor());

      await client.connect();
      final seen = <dynamic>[];
      client.errorStream.listen(seen.add);
      mock.simulateError('boom');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen, isEmpty);

      await client.dispose();
    });
  });
}

class _TransformingErrorInterceptor extends WebSocketInterceptor {
  @override
  Future<dynamic> onError(dynamic error) async => 'wrapped:$error';
}

class _SuppressingErrorInterceptor extends WebSocketInterceptor {
  @override
  Future<dynamic> onError(dynamic error) async => null;
}
