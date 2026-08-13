## 0.1.8

### Bug Fixes

- **Connection**: Fixed a race in `WebSocketChannelAdapter.connect()` where a stale connection's callbacks could overwrite the state of a newer one, subscriptions leaked across reconnects, and a stalled handshake could leave `connect()` hanging forever (connection generation counting + timeout now terminates the pending future).
- **ACK**: Fixed `__ack__`-pending messages being silently lost on disconnect — pending ACKs are now requeued for redelivery and late ACK frames are consumed instead of leaking into the message stream.
- **ACK / Queue**: Draining the message queue no longer blocks behind one unacknowledged ACK message (previously up to `ackTimeout × maxAckRetries`), and failed sends while connected now fall back to the queue instead of being lost.
- **Heartbeat**: Fixed a race where `stop()` during an in-flight heartbeat send could re-arm a zombie timeout timer and trigger auto-reconnect after an intentional disconnect.
- **Heartbeat**: The mechanism now deactivates cleanly after `maxMissedHeartbeats` (stats no longer report a dead heartbeat as active) and can be restarted after reconnection.
- **Reconnection**: Fixed disconnections that occurred while a reconnect attempt was in flight being swallowed, which could leave the client permanently offline; superseded attempts can no longer report success or cancel a newer cycle. Also fixed an exponent overflow crash in exponential backoff with unlimited retries.
- **Topics**: `ChannelManager.route()` no longer throws on malformed envelopes from the server (non-string `topic`/`event` values are now guarded instead of hardcast).
- **Interceptors**: The public `errorStream` now forwards errors through the error interceptor chain — returning `null` from `onError` actually suppresses the error, matching `onSend`/`onReceive` semantics.
- Added `WebSocketClient.isReconnecting` to distinguish "disconnected" from "automatically reconnecting".

### Improvements

- Restored the **web** platform declaration in `pubspec.yaml` (a Dart-only registrant via `dartPluginClass`) so pub.dev correctly shows web support — it had been dropped accidentally in 0.1.7.
- Added a canonical entry point at `package:adapter_websocket/adapter_websocket.dart`; the old `websocket_plugin.dart` import remains as a backwards-compatible alias.

### Example

- Added a self-driving in-process mock WebSocket server (`example/lib/local_mock_websocket_adapter.dart`) that answers heartbeat/ACK/topic traffic and broadcasts periodic events with zero network access — switch between **Mock (local)** and **Real server** right in the demo UI. Native builds use a real local WebSocket server; web builds use an in-memory transport with identical behaviour.

### Tests

- Added 13 regression tests covering all of the above fixes, plus an example integration test exercising the full mock flow (echo, ACK, heartbeat, topics, simulated disconnect → auto-reconnect).
- Made the previously jitter-dependent exponential-backoff test deterministic.

---

## 0.1.7

### New Features

- `WebSocketMessage` now has a `copyWith()` method for convenient object duplication.

### Improvements

- **ACK**: `AckManager.sendWithAck()` now embeds `__ack_id__` directly into the JSON payload so the server can echo it back without out-of-band framing.
- **Message Queue**: Added `useAck` flag support; messages that were originally sent with ACK enabled are re-enqueued with the flag preserved and re-sent with ACK on reconnect.
- **Channel Manager**: `ChannelManager` now passes a `WebSocketMessage` (instead of raw data) to the underlying send path, enabling full interceptor and ACK pipeline support for topic messages.
- **Reconnection Manager**: Infinite-retry configuration (`maxReconnectAttempts = 0`) is now displayed correctly in connection stats.
- **WebSocket Client**: Refactored the message stream processing pipeline for clearer separation between raw transport, interceptor chain, and topic dispatch.
- **WebSocketConfig.copyWith()**: Supports explicit `null` clearing for optional fields (e.g. `httpClient`, `expectedPongMessagePattern`) so callers can reset a field without creating a whole new config.
- **README**: Extended cross-platform availability table to document which configuration fields are supported on Web vs. native.

### Build

- Updated package version to `0.1.7`.
- Removed resource files that are not supported on the Web platform from the asset bundle.

---

## 0.1.6

### Bug Fixes

- Fixed Swift Package Manager (SPM) support for iOS and macOS: added `Package.swift` at `ios/adapter_websocket/Package.swift` and `macos/adapter_websocket/Package.swift`, which is the path Flutter's SPM integration actually resolves. The previously existing root-level `ios/Package.swift` and `macos/Package.swift` were not found by the pub.dev validator or Flutter tooling.

---

## 0.1.5

### Improvements

- Explicitly declared the web platform in `pubspec.yaml` (`pluginClass: none`), confirming that web WebSocket support is handled entirely in Dart via `web_socket_channel` with no native plugin class required.

---

## 0.1.4

### Improvements

- Removed unused plugin scaffold files (`adapter_websocket_web.dart`, `untitled5_method_channel.dart`, `websocket_platform_interface.dart`) that were generated by `flutter create --template=plugin` but never wired into actual functionality.
- Removed corresponding unused dependencies: `flutter_web_plugins`, `plugin_platform_interface`.
- Removed the empty web plugin class registration from `pubspec.yaml`; web WebSocket support continues to work through `web_socket_channel`.

---

## 0.1.3

### Improvements

- Refactored `WebSocketChannelAdapter` internals to fully support the WASM platform, removing remaining `dart:io` dependencies from the connection path via conditional imports.
- Improved `CompressionInterceptor` reliability on native platforms.
- Added GitHub Pages live demo (automatically deployed on every push to `master`).

---

## 0.1.2

### Bug Fixes

- Fixed `CompressionInterceptor` not actually applying gzip on native platforms — replaced stub with proper conditional import of `dart:io` `GZipCodec`.
- Fixed `library_private_types_in_public_api` lint violations in `AckManager` and `WebSocketTopic` constructors by inlining function types.
- Removed unnecessary `library` directive from `websocket_plugin.dart`.

### Improvements

- WASM compatibility: removed top-level `dart:io` dependency from `WebSocketConfig` and `WebSocketChannelAdapter` using conditional imports; package now compiles for WASM targets.
- Added Swift Package Manager support (`Package.swift`) for iOS and macOS.
- `WebSocketConfig.httpClient` field is now typed as `Object?` to avoid a `dart:io` import in the public API; the native adapter casts it internally.

## 0.1.1

### Bug Fixes

- Fixed messages whose content contains the heartbeat string (e.g. JSON payloads that include `"ping"` or `"pong"`) being incorrectly classified as heartbeat responses.

### Improvements

- Refactored example application with additional usage demos and improved UI.
- Added iOS and Dart CI workflows.

## 0.1.0

### New Features

- **Interceptor / Middleware** — `WebSocketInterceptor` abstract class and `InterceptorChain` for inspecting, transforming, or suppressing messages at send and receive time. Ships with a built-in `LoggingInterceptor`.
- **Message Queue (offline buffer)** — `MessageQueue` buffers outgoing messages while the connection is down and automatically flushes them on reconnect. Configurable via `enableMessageQueue`, `maxQueueSize`, and `messageQueueTimeout`.
- **ACK Confirmation** — `AckManager` injects a unique `__ack_id__` into outgoing messages and waits for server acknowledgement. Supports configurable timeout and automatic retries. Configurable via `enableAck`, `ackTimeout`, and `maxAckRetries`.
- **Topic Multiplexing (Channel/Topic)** — `ChannelManager` and `WebSocketTopic` enable multiple logical channels over a single WebSocket connection using a JSON envelope format (`{"topic":"…","event":"…","payload":…}`). Access via `client.channel('topic:name')`.
- **Compression** — `CompressionInterceptor` transparently gzip-compresses outgoing messages above a configurable byte threshold and decompresses incoming messages. Available on native platforms (not web).
- **Connection Pool** — `WebSocketPool` manages multiple `WebSocketClient` instances across different server endpoints with round-robin, random, or least-connections load balancing. Supports `broadcast()` to all connected clients.

### Improvements

- `WebSocketConfig.copyWith()` now includes `expectedPongMessagePattern`.
- `WebSocketClient` message pipeline runs through the interceptor chain before sending and after receiving.
- `WebSocketClient.send()` and `sendMessage()` enqueue messages when disconnected (if `enableMessageQueue` is enabled) instead of immediately throwing.
- Queue is drained automatically on reconnect success (both from `connect()` and from the reconnection manager).
- `connectionStats` now includes `messageQueue`, `ack`, `channels`, and `interceptors` fields.

### Bug Fixes

- Fixed `_isHeartbeatMessage()` null dereference when only `expectedPongMessage` was set.
- Fixed `copyWith()` dropping `expectedPongMessagePattern`.
- Fixed heartbeat pong waiting logic ignoring `expectedPongMessagePattern`.
- Fixed `handleIncomingMessage()` not recognising pong responses matched by `expectedPongMessagePattern`.
- Fixed `WebSocketClient._publishStats()` not being called after initiating reconnection from heartbeat timeout.
- Fixed shadowed variable in `reconnection_manager_test.dart` causing NullPointerException.
- Fixed `ReconnectionManager` timer leak between tests by adding `tearDown`.
- Fixed `reconnection_manager_test.dart` "max attempts" test not waiting long enough for exponential backoff.
- Fixed `websocket_plugin_test.dart` unstable-connection test relying on 30-second instability timer.

## 0.0.2

* TODO: Describe initial release.
