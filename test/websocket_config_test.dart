import 'dart:io';
import 'package:adapter_websocket/src/websocket_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSocketConfig.copyWith', () {
    test('should override httpClient when provided', () {
      final original = WebSocketConfig(url: 'ws://example.com');
      final customClient = HttpClient();

      final copy = original.copyWith(httpClient: customClient);

      expect(copy.httpClient, same(customClient));
      expect(copy.url, original.url);
    });
  });
}