import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registration for `adapter_websocket`.
///
/// All web functionality is provided directly by `web_socket_channel`
/// (a pure-Dart implementation), so nothing needs to be registered at
/// startup. This class exists solely so the package can declare Dart-only
/// web support in `pubspec.yaml` via [AdapterWebsocketWeb.registerWith].
class AdapterWebsocketWeb {
  static void registerWith(Registrar registrar) {}
}
