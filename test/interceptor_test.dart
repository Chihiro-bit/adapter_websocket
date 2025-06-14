import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestInterceptor implements WebSocketInterceptor {
  final List<String> events;
  _TestInterceptor(this.events);

  @override
  Future<WebSocketMessage> onSend(WebSocketMessage message) async {
    events.add('send:${message.data}');
    return WebSocketMessage.now(data: '${message.data}-out');
  }

  @override
  Future<WebSocketMessage> onReceive(WebSocketMessage message) async {
    events.add('recv:${message.data}');
    return WebSocketMessage.now(data: '${message.data}-in');
  }
}

void main() {
  group('WebSocketInterceptor', () {
    late MockWebSocketAdapter adapter;
    late WebSocketClient client;
    late List<String> events;

    setUp(() {
      final config = WebSocketConfig(url: 'wss://test.example.com');
      adapter = MockWebSocketAdapter(config);
      events = <String>[];
      client = WebSocketClient(adapter, interceptors: [_TestInterceptor(events)]);
    });

    tearDown(() async {
      await client.dispose();
    });

    test('outgoing messages are intercepted', () async {
      await adapter.connect();
      await client.sendText('hello');

      expect(adapter.sentMessages.first.data, equals('hello-out'));
      expect(events, contains('send:hello'));
    });

    test('incoming messages are intercepted', () async {
      await adapter.connect();

      final received = <WebSocketMessage>[];
      client.messageStream.listen(received.add);

      adapter.simulateTextMessage('server');
      await Future.delayed(Duration(milliseconds: 10));

      expect(received.first.data, equals('server-in'));
      expect(events, contains('recv:server'));
    });
  });
}
