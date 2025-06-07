import 'package:adapter_websocket/websocket_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';


/// An implementation of [Untitled5Platform] that uses method channels.
class MethodChannelUntitled5 extends WebsocketPlatformInterface {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('untitled5');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
