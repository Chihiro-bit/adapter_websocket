import 'package:adapter_websocket/untitled5_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class WebsocketPlatformInterface extends PlatformInterface {
  WebsocketPlatformInterface() : super(token: _token);

  static final Object _token = Object();

  static WebsocketPlatformInterface _instance = MethodChannelUntitled5();

  static WebsocketPlatformInterface get instance => _instance;

  static set instance(WebsocketPlatformInterface instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
