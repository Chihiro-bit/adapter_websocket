import 'package:adapter_websocket/src/reconnection_manager.dart';
import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReconnectionManager Tests', () {
    late ReconnectionManager reconnectionManager;
    late WebSocketConfig config;
    final List<String> logs = [];
    int reconnectCallCount = 0;
    bool shouldFailReconnect = false;

    setUp(() {
      logs.clear();
      reconnectCallCount = 0;
      shouldFailReconnect = false;
      
      config = WebSocketConfig(
        url: 'wss://test.example.com',
        autoReconnect: true,
        maxReconnectAttempts: 3,
        reconnectDelay: Duration(milliseconds: 100),
        useExponentialBackoff: true,
        backoffMultiplier: 2.0,
        maxReconnectDelay: Duration(seconds: 10),
      );

      reconnectionManager = ReconnectionManager(
        config: config,
        reconnectCallback: () async {
          reconnectCallCount++;
          if (shouldFailReconnect) {
            throw Exception('Reconnection failed');
          }
        },
        log: (message) {
          logs.add(message);
        },
      );
    });



    test('should attempt reconnection with exponential backoff', () async {
      bool attemptCalled = false;
      var reconnectionManager;
      reconnectionManager.setOnReconnectAttempt(() {
        attemptCalled = true;
      });

      shouldFailReconnect = true;
      reconnectionManager.startReconnection();
      
      // Wait for first attempt
      await Future.delayed(Duration(milliseconds: 200));
      
      expect(attemptCalled, isTrue);
      expect(reconnectCallCount, greaterThan(0));
      expect(logs.any((log) => log.contains('Scheduling reconnection attempt')), isTrue);
    });

    test('should succeed on successful reconnection', () async {
      bool successCalled = false;
      reconnectionManager.setOnReconnectSuccess(() {
        successCalled = true;
      });

      reconnectionManager.startReconnection();
      
      // Wait for reconnection attempt
      await Future.delayed(Duration(milliseconds: 200));
      
      expect(successCalled, isTrue);
      expect(reconnectCallCount, equals(1));
      expect(logs.any((log) => log.contains('Reconnection successful')), isTrue);
    });

    test('should stop after max attempts reached', () async {
      bool maxAttemptsCalled = false;
      reconnectionManager.setOnMaxAttemptsReached(() {
        maxAttemptsCalled = true;
      });

      shouldFailReconnect = true;
      
      // Exhaust all attempts
      for (int i = 0; i < config.maxReconnectAttempts; i++) {
        reconnectionManager.startReconnection();
        await Future.delayed(Duration(milliseconds: 150));
      }
      
      // Try one more time
      reconnectionManager.startReconnection();
      
      expect(maxAttemptsCalled, isTrue);
      expect(logs.any((log) => log.contains('Maximum reconnection attempts')), isTrue);
    });

    test('should reset state on successful connection', () {
      shouldFailReconnect = true;
      reconnectionManager.startReconnection();
      
      expect(reconnectionManager.getStats()['reconnectAttempts'], greaterThan(0));
      
      reconnectionManager.reset();
      
      expect(reconnectionManager.getStats()['reconnectAttempts'], equals(0));
      expect(reconnectionManager.getStats()['isReconnecting'], isFalse);
    });

    test('should provide accurate statistics', () {
      reconnectionManager.startReconnection();
      
      final stats = reconnectionManager.getStats();
      
      expect(stats['isReconnecting'], isA<bool>());
      expect(stats['reconnectAttempts'], isA<int>());
      expect(stats['maxReconnectAttempts'], equals(config.maxReconnectAttempts));
      expect(stats['currentDelay'], isA<int>());
    });

    test('should calculate exponential backoff correctly', () async {
      shouldFailReconnect = true;
      
      final delays = <int>[];
      reconnectionManager.setOnReconnectAttempt(() {
        final stats = reconnectionManager.getStats();
        delays.add(stats['currentDelay'] as int);
      });

      // Make multiple failed attempts
      for (int i = 0; i < 3; i++) {
        reconnectionManager.startReconnection();
        await Future.delayed(Duration(milliseconds: 150));
      }

      // Verify exponential increase (allowing for jitter)
      expect(delays.length, greaterThan(1));
      // First delay should be base delay (with jitter)
      expect(delays[0], closeTo(config.reconnectDelay.inSeconds, 1));
    });
  });
}
