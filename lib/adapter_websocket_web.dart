import 'package:adapter_websocket/websocket_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class AdapterWebsocketWeb extends WebsocketPlatformInterface  {
  AdapterWebsocketWeb();

  static void registerWith(Registrar registrar) {
    WebsocketPlatformInterface.instance = AdapterWebsocketWeb();
  }
}
