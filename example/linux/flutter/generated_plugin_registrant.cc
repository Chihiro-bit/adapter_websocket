//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <adapter_websocket/adapter_websocket_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) adapter_websocket_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AdapterWebsocketPlugin");
  adapter_websocket_plugin_register_with_registrar(adapter_websocket_registrar);
}
