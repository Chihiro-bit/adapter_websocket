import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  group('MockWebSocketAdapter Tests', () {
    late MockWebSocketAdapter adapter;
    late WebSocketConfig config;

    setUp(() {
      config = WebSocketConfig(url: 'ws://124.222.6.60:8800');
      adapter = MockWebSocketAdapter(config);
    });

    tearDown(() async {
      await adapter.dispose();
    });

    test('should start in disconnected state', () {
      expect(adapter.currentState, equals(WebSocketState.disconnected));
      expect(adapter.isConnected, isFalse);
      expect(adapter.isClosed, isTrue);
    });

    test('should connect successfully', () async {
      await adapter.connect();
      expect(adapter.currentState, equals(WebSocketState.connected));
      expect(adapter.isConnected, isTrue);
    });

    test('should handle connection delay', () async {
      adapter.setConnectionDelay(Duration(milliseconds: 100));
      
      final stopwatch = Stopwatch()..start();
      await adapter.connect();
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));
      expect(adapter.isConnected, isTrue);
    });

    test('should simulate connection failure', () async {
      adapter.setShouldFailConnection(true);
      
      expect(() => adapter.connect(), throwsException);
      expect(adapter.currentState, equals(WebSocketState.error));
    });

    test('should track sent messages', () async {
      await adapter.connect();
      
      await adapter.send('text message');
      await adapter.send({'json': 'data'});
      await adapter.send([1, 2, 3]);
      
      expect(adapter.sentMessages.length, equals(3));
      expect(adapter.sentMessages[0].data, equals('text message'));
      expect(adapter.sentMessages[1].data, equals({'json': 'data'}));
      expect(adapter.sentMessages[2].data, equals([1, 2, 3]));
    });

    test('should simulate message reception', () async {
      await adapter.connect();
      
      final receivedMessages = <WebSocketMessage>[];
      adapter.messageStream.listen((message) {
        receivedMessages.add(message);
      });
      
      adapter.simulateTextMessage('Hello');
      adapter.simulateJsonMessage({'type': 'greeting'});
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(receivedMessages.length, equals(2));
      expect(receivedMessages[0].data, equals('Hello'));
      expect(receivedMessages[1].data, equals({'type': 'greeting'}));
    });

    test('should simulate errors', () async {
      final errors = <dynamic>[];
      adapter.errorStream.listen((error) {
        errors.add(error);
      });
      
      final testError = Exception('Test error');
      adapter.simulateError(testError);
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(errors.length, equals(1));
      expect(errors.first, equals(testError));
    });

    test('should simulate disconnection', () async {
      await adapter.connect();
      expect(adapter.isConnected, isTrue);
      
      adapter.simulateDisconnection();
      expect(adapter.currentState, equals(WebSocketState.disconnected));
    });

    test('should handle sending failures', () async {
      await adapter.connect();
      adapter.setShouldFailSending(true);
      
      expect(() => adapter.send('test'), throwsException);
    });

    test('should clear sent messages', () async {
      await adapter.connect();
      await adapter.send('test message');
      
      expect(adapter.sentMessages.length, equals(1));
      
      adapter.clearSentMessages();
      expect(adapter.sentMessages.length, equals(0));
    });
  });
}
