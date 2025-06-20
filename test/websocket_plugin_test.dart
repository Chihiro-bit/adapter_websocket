import 'dart:convert';
import 'dart:io';
import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

Future<HttpClient> createPinnedHttpClient({required String assetPath}) async {
  final ByteData certData = await rootBundle.load(assetPath);
  final Uint8List certBytes = certData.buffer.asUint8List();

  final SecurityContext securityContext = SecurityContext(
    withTrustedRoots: false,
  );
  securityContext.setTrustedCertificatesBytes(certBytes);

  final HttpClient client = HttpClient(context: securityContext);

  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) {
    final String incomingPem = cert.pem;
    final String pinnedPem = utf8.decode(certBytes);
    return incomingPem == pinnedPem;
  };

  return client;
}

void main() {
  group('Enhanced WebSocket Plugin Tests', () {
    late MockWebSocketAdapter mockAdapter;
    late WebSocketClient client;
    late WebSocketConfig config;
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() async {
      final httpClient =
          await createPinnedHttpClient(assetPath: 'assets/ssl/test_cert.pem');

      config = WebSocketConfig(
        url: 'ws://124.222.6.60:8800',
        autoReconnect: true,
        maxReconnectAttempts: 3,
        enableLogging: true,
        enableHeartbeat: true,
        heartbeatInterval: Duration(milliseconds: 100),
        heartbeatTimeout: Duration(milliseconds: 50),
        heartbeatMessage: 'ping',
        expectedPongMessage: 'pong',
        maxMissedHeartbeats: 2,
        httpClient: httpClient,
      );
      mockAdapter = MockWebSocketAdapter(config);
      client = WebSocketClient(
        mockAdapter,
        certificateErrorCallback: (
          X509Certificate cert,
          String host,
          int port,
        ) {},
      );
    });

    tearDown(() async {
      await client.dispose();
    });

    test('should initialize with enhanced configuration', () {
      expect(client.config.enableHeartbeat, isTrue);
      expect(
        client.config.heartbeatInterval,
        equals(Duration(milliseconds: 100)),
      );
      expect(client.config.maxMissedHeartbeats, equals(2));
      expect(client.config.useExponentialBackoff, isTrue);
    });

    test('should start heartbeat on connection', () async {
      await client.connect();

      // Wait for heartbeat to start
      await Future.delayed(Duration(milliseconds: 150));

      // Check if ping was sent
      final sentMessages = mockAdapter.sentMessages;
      expect(sentMessages.any((msg) => msg.data == 'ping'), isTrue);
    });

    test('should handle heartbeat responses', () async {
      await client.connect();

      // Wait for ping to be sent
      await Future.delayed(Duration(milliseconds: 150));

      // Simulate pong response
      mockAdapter.simulatePongMessage();

      // Verify heartbeat continues
      await Future.delayed(Duration(milliseconds: 150));

      final stats = client.connectionStats;
      expect(stats['heartbeat']['missedHeartbeats'], equals(0));
    });

    test('should detect connection issues via missed heartbeats', () async {
      mockAdapter.setAutoRespondToPing(false);

      final connectionIssues = <bool>[];
      client.statsStream.listen((stats) {
        final missedHeartbeats = stats['heartbeat']['missedHeartbeats'] as int;
        if (missedHeartbeats > 0) {
          connectionIssues.add(true);
        }
      });

      await client.connect();

      // Wait for heartbeats to be missed
      await Future.delayed(Duration(milliseconds: 400));

      expect(connectionIssues.isNotEmpty, isTrue);
    });

    test('should attempt reconnection on heartbeat timeout', () async {
      mockAdapter.setAutoRespondToPing(false);

      final reconnectionAttempts = <bool>[];
      client.statsStream.listen((stats) {
        final isReconnecting = stats['reconnection']['isReconnecting'] as bool;
        if (isReconnecting) {
          reconnectionAttempts.add(true);
        }
      });

      await client.connect();

      // Wait for heartbeat timeout and reconnection
      await Future.delayed(Duration(milliseconds: 500));

      expect(reconnectionAttempts.isNotEmpty, isTrue);
    });

    test('should handle unstable connections', () async {
      mockAdapter.setSimulateUnstableConnection(true);

      final stateChanges = <WebSocketState>[];
      client.stateStream.listen((state) {
        stateChanges.add(state);
      });

      await client.connect();

      // Wait for instability simulation
      await Future.delayed(Duration(milliseconds: 200));

      // Should have multiple state changes due to instability
      expect(stateChanges.length, greaterThan(2));
      expect(stateChanges, contains(WebSocketState.connected));
      expect(stateChanges, contains(WebSocketState.disconnected));
    });

    test('should provide comprehensive statistics', () async {
      await client.connect();

      final stats = client.connectionStats;

      expect(stats['connectionState'], isA<String>());
      expect(stats['isConnected'], isA<bool>());
      expect(stats['heartbeat'], isA<Map>());
      expect(stats['reconnection'], isA<Map>());
      expect(stats['config'], isA<Map>());

      // Heartbeat stats
      final heartbeatStats = stats['heartbeat'] as Map;
      expect(heartbeatStats['isActive'], isA<bool>());
      expect(heartbeatStats['missedHeartbeats'], isA<int>());
      expect(heartbeatStats['heartbeatInterval'], isA<int>());

      // Reconnection stats
      final reconnectionStats = stats['reconnection'] as Map;
      expect(reconnectionStats['isReconnecting'], isA<bool>());
      expect(reconnectionStats['reconnectAttempts'], isA<int>());
    });

    test('should force reconnection successfully', () async {
      await client.connect();
      expect(client.isConnected, isTrue);

      await client.forceReconnect();
      expect(client.isConnected, isTrue);
    });

    test('should handle exponential backoff in reconnection', () async {
      mockAdapter.setShouldFailConnection(true);

      final reconnectionDelays = <int>[];
      client.statsStream.listen((stats) {
        final currentDelay = stats['reconnection']['currentDelay'] as int?;
        if (currentDelay != null &&
            !reconnectionDelays.contains(currentDelay)) {
          reconnectionDelays.add(currentDelay);
        }
      });

      // Attempt multiple failed connections
      for (int i = 0; i < 3; i++) {
        try {
          await client.connect();
        } catch (_) {
          // Expected to fail
        }
        await Future.delayed(Duration(milliseconds: 200));
      }

      // Should have different delays due to exponential backoff
      expect(reconnectionDelays.length, greaterThan(1));
    });
  });

  group('Mock Adapter Enhanced Features Tests', () {
    late MockWebSocketAdapter adapter;
    late WebSocketConfig config;

    setUp(() {
      config = WebSocketConfig(
        url: 'wss://test.example.com',
        heartbeatMessage: 'ping',
        expectedPongMessage: 'pong',
      );
      adapter = MockWebSocketAdapter(config);
    });

    tearDown(() async {
      await adapter.dispose();
    });

    test('should auto-respond to ping messages', () async {
      await adapter.connect();

      final receivedMessages = <WebSocketMessage>[];
      adapter.messageStream.listen((message) {
        receivedMessages.add(message);
      });

      await adapter.send('ping');

      // Wait for auto-response
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedMessages.any((msg) => msg.data == 'pong'), isTrue);
    });

    test('should simulate network instability', () async {
      adapter.setSimulateUnstableConnection(true);

      final stateChanges = <WebSocketState>[];
      adapter.stateStream.listen((state) {
        stateChanges.add(state);
      });

      await adapter.connect();

      // Trigger instability
      adapter.simulateNetworkInstability();

      expect(stateChanges, contains(WebSocketState.connected));
      expect(stateChanges, contains(WebSocketState.disconnected));
    });

    test('should disable auto ping response when configured', () async {
      adapter.setAutoRespondToPing(false);
      await adapter.connect();
      final receivedMessages = <WebSocketMessage>[];
      adapter.messageStream.listen((message) {
        receivedMessages.add(message);
      });

      await adapter.send('ping');

      // Wait to ensure no auto-response
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedMessages.any((msg) => msg.data == 'pong'), isFalse);
    });
  });
}
