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
