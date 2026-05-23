import 'dart:io' show HttpClient;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../websocket_config.dart';

WebSocketChannel connectChannel(Uri uri, WebSocketConfig config) =>
    IOWebSocketChannel.connect(
      uri,
      protocols: config.protocols,
      headers: config.headers,
      customClient: config.httpClient as HttpClient?,
      pingInterval: config.pingInterval,
      connectTimeout: config.connectionTimeout,
    );
