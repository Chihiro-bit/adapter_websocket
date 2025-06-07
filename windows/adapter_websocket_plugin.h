#ifndef FLUTTER_PLUGIN_ADAPTER_WEBSOCKET_PLUGIN_H_
#define FLUTTER_PLUGIN_ADAPTER_WEBSOCKET_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace adapter_websocket {

class AdapterWebsocketPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AdapterWebsocketPlugin();

  virtual ~AdapterWebsocketPlugin();

  // Disallow copy and assign.
  AdapterWebsocketPlugin(const AdapterWebsocketPlugin&) = delete;
  AdapterWebsocketPlugin& operator=(const AdapterWebsocketPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace adapter_websocket

#endif  // FLUTTER_PLUGIN_ADAPTER_WEBSOCKET_PLUGIN_H_
