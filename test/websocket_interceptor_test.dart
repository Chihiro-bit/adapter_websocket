import 'dart:async';
import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingInterceptor implements WebSocketInterceptor {
  int sendCount = 0;
  int receiveCount = 0;
  int errorCount = 0;

  @override
  FutureOr<WebSocketMessage?> onSend(WebSocketMessage message) async {
    sendCount++;
    await Future.delayed(Duration(milliseconds: 1));
    return message;
  }

  @override
  FutureOr<WebSocketMessage?> onReceive(WebSocketMessage message) async {
    receiveCount++;
    await Future.delayed(Duration(milliseconds: 1));
    return message;
  }

  @override
  FutureOr<void> onError(error) {
    errorCount++;
  }
}

class CancelingInterceptor implements WebSocketInterceptor {
  @override
  FutureOr<WebSocketMessage?> onSend(WebSocketMessage message) => null;

  @override
  FutureOr<WebSocketMessage?> onReceive(WebSocketMessage message) => message;

  @override
  FutureOr<void> onError(error) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebSocket interceptors', () {
    late MockWebSocketAdapter adapter;
    late WebSocketClient client;
    late WebSocketConfig config;

    setUp(() {
      config = WebSocketConfig(url: 'wss://test');
      adapter = MockWebSocketAdapter(config);
      client = WebSocketClient(adapter);
    });

    tearDown(() async {
      await client.dispose();
    });

    test('interceptors handle send and receive', () async {
      final interceptor = CountingInterceptor();
      client.addInterceptor(interceptor);

      await client.connect();
      await client.sendText('hi');
      adapter.simulateTextMessage('pong');
      await Future.delayed(Duration(milliseconds: 10));

      expect(interceptor.sendCount, 1);
      expect(interceptor.receiveCount, 1);
    });

    test('interceptor can cancel outgoing message', () async {
      final interceptor = CancelingInterceptor();
      client.addInterceptor(interceptor);

      await client.connect();
      await client.sendText('hi');

      expect(adapter.sentMessages, isEmpty);
    });

    test('interceptor receives errors', () async {
      final interceptor = CountingInterceptor();
      client.addInterceptor(interceptor);

      await client.connect();
      adapter.simulateError(Exception('boom'));
      await Future.delayed(Duration(milliseconds: 10));

      expect(interceptor.errorCount, 1);
    });
  });
}
