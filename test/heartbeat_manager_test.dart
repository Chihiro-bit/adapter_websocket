import 'package:adapter_websocket/src/heartbeat_manager.dart';
import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeartbeatManager Tests', () {
    late HeartbeatManager heartbeatManager;
    late WebSocketConfig config;
    final List<String> sentMessages = [];
    final List<String> logs = [];

    setUp(() {
      sentMessages.clear();
      logs.clear();
      
      config = WebSocketConfig(
        url: 'wss://test.example.com',
        enableHeartbeat: true,
        heartbeatInterval: Duration(milliseconds: 100),
        heartbeatTimeout: Duration(milliseconds: 50),
        heartbeatMessage: 'ping',
        expectedPongMessage: 'pong',
        maxMissedHeartbeats: 2,
      );

      heartbeatManager = HeartbeatManager(
        config: config,
        sendMessage: (message) async {
          sentMessages.add(message);
        },
        log: (message) {
          logs.add(message);
        },
      );
    });

    tearDown(() {
      heartbeatManager.dispose();
    });

    test('should start heartbeat and send ping messages', () async {
      bool timeoutCalled = false;
      heartbeatManager.setOnHeartbeatTimeout(() {
        timeoutCalled = true;
      });

      heartbeatManager.start();
      
      // Wait for first heartbeat
      await Future.delayed(Duration(milliseconds: 150));
      
      expect(sentMessages.length, greaterThan(0));
      expect(sentMessages.first, equals('ping'));
      expect(logs.any((log) => log.contains('Starting heartbeat')), isTrue);
    });

    test('should handle pong responses correctly', () async {
      bool healthyCalled = false;
      heartbeatManager.setOnConnectionHealthy(() {
        healthyCalled = true;
      });

      heartbeatManager.start();
      
      // Wait for heartbeat to be sent
      await Future.delayed(Duration(milliseconds: 150));
      
      // Simulate pong response
      heartbeatManager.handlePong('pong');
      
      expect(healthyCalled, isTrue);
      expect(logs.any((log) => log.contains('Received pong response')), isTrue);
    });

    test('should detect missed heartbeats and trigger timeout', () async {
      bool timeoutCalled = false;
      bool unhealthyCalled = false;
      
      heartbeatManager.setOnHeartbeatTimeout(() {
        timeoutCalled = true;
      });
      
      heartbeatManager.setOnConnectionUnhealthy(() {
        unhealthyCalled = true;
      });

      heartbeatManager.start();
      
      // Wait for multiple heartbeat cycles without responding
      await Future.delayed(Duration(milliseconds: 400));
      
      expect(timeoutCalled, isTrue);
      expect(unhealthyCalled, isTrue);
      expect(logs.any((log) => log.contains('Maximum missed heartbeats reached')), isTrue);
    });

    test('should reset missed heartbeats on incoming message', () async {
      heartbeatManager.start();
      
      // Wait for some heartbeats to be missed
      await Future.delayed(Duration(milliseconds: 200));
      
      // Simulate incoming message
      final message = WebSocketMessage.text('Hello');
      heartbeatManager.handleIncomingMessage(message);
      
      final stats = heartbeatManager.getStats();
      expect(stats['missedHeartbeats'], equals(0));
    });

    test('should provide accurate statistics', () {
      heartbeatManager.start();
      
      final stats = heartbeatManager.getStats();
      
      expect(stats['isActive'], isTrue);
      expect(stats['missedHeartbeats'], isA<int>());
      expect(stats['heartbeatInterval'], equals(config.heartbeatInterval.inSeconds));
      expect(stats['maxMissedHeartbeats'], equals(config.maxMissedHeartbeats));
    });

    test('should stop heartbeat properly', () {
      heartbeatManager.start();
      expect(heartbeatManager.getStats()['isActive'], isTrue);
      
      heartbeatManager.stop();
      expect(heartbeatManager.getStats()['isActive'], isFalse);
      expect(logs.any((log) => log.contains('Stopping heartbeat')), isTrue);
    });
  });
}
