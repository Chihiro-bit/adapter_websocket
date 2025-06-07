#include "include/adapter_websocket/adapter_websocket_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "adapter_websocket_plugin.h"

void AdapterWebsocketPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  adapter_websocket::AdapterWebsocketPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
