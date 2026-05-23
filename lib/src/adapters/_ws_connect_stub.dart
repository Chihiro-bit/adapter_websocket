import 'package:web_socket_channel/web_socket_channel.dart';
import '../websocket_config.dart';

WebSocketChannel connectChannel(Uri uri, WebSocketConfig config) =>
    WebSocketChannel.connect(uri, protocols: config.protocols);
