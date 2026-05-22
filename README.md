# adapter_websocket

[![pub version](https://img.shields.io/pub/v/adapter_websocket.svg)](https://pub.dev/packages/adapter_websocket)
[![CI](https://github.com/Chihiro-bit/adapter_websocket/actions/workflows/dart.yml/badge.svg)](https://github.com/Chihiro-bit/adapter_websocket/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios%20%7C%20web%20%7C%20macos%20%7C%20linux%20%7C%20windows-lightgrey)](https://pub.dev/packages/adapter_websocket)

A production-ready Flutter WebSocket package built on the **Adapter pattern**. Swap real and mock implementations without touching client code, while getting automatic reconnection, heartbeat monitoring, offline message buffering, ACK confirmation, topic-based multiplexing, transparent compression, and a flexible interceptor pipeline out of the box.

---

## Table of Contents

- [Features](#features)
- [Platform Support](#platform-support)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Feature Guide](#feature-guide)
  - [Interceptors](#interceptors)
  - [Offline Message Queue](#offline-message-queue)
  - [ACK Confirmation](#ack-confirmation)
  - [Topic Channels](#topic-channels)
  - [Compression](#compression)
  - [Connection Pool](#connection-pool)
  - [State & Statistics](#state--statistics)
- [Testing with MockAdapter](#testing-with-mockadapter)
- [Best Practices](#best-practices)
- [License](#license)

---

## Features

| Feature | Description |
|---|---|
| **Adapter Pattern** | Swap real / mock implementations without changing any client code |
| **Auto-Reconnect** | Exponential backoff with jitter and configurable retry limits |
| **Heartbeat** | Customisable ping/pong with missed-heartbeat detection and disconnect |
| **Interceptors** | Transform or suppress messages at send/receive time (logging, auth, …) |
| **Message Queue** | Buffer outgoing messages while offline; flush automatically on reconnect |
| **ACK Confirmation** | Reliable delivery with server acknowledgement and automatic retry |
| **Topic Channels** | Multiplex logical channels over a single WebSocket connection |
| **Compression** | Transparent gzip compression for large payloads (native platforms) |
| **Connection Pool** | Round-robin, random, or least-connections load balancing across endpoints |
| **Statistics** | Real-time metrics for heartbeat, reconnection, queue, ACK, and channels |
| **Mock Adapter** | Full-featured test double — no network required, supports failure injection |

---

## Platform Support

| Android | iOS | Web | macOS | Linux | Windows |
|:---:|:---:|:---:|:---:|:---:|:---:|
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> **Note:** `CompressionInterceptor` uses `dart:io` and is not available on Web.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  adapter_websocket: ^0.1.0
```

Then run:

```
flutter pub get
```

---

## Quick Start

```dart
import 'package:adapter_websocket/websocket_plugin.dart';

final config = WebSocketConfig(
  url: 'wss://echo.websocket.org',
  autoReconnect: true,
  enableLogging: true,
);

final client = WebSocketClient(WebSocketChannelAdapter(config));

client.messageStream.listen((msg) => print('Received: ${msg.data}'));
client.stateStream.listen((state) => print('State: $state'));

await client.connect();
await client.sendText('Hello, WebSocket!');
await client.sendJson({'type': 'greeting', 'message': 'Hello'});

await client.dispose();
```

---

## Configuration

`WebSocketConfig` is immutable and supports `copyWith`. Every field has a sensible default.

```dart
final config = WebSocketConfig(
  url: 'wss://your-server.com',
  protocols: ['chat'],
  headers: {'Authorization': 'Bearer <token>'},
  connectionTimeout: Duration(seconds: 10),

  // ── Reconnection ──────────────────────────────────────────────
  autoReconnect: true,
  maxReconnectAttempts: 5,       // 0 = unlimited
  reconnectDelay: Duration(seconds: 2),
  useExponentialBackoff: true,
  backoffMultiplier: 2.0,
  maxReconnectDelay: Duration(minutes: 5),

  // ── Heartbeat ─────────────────────────────────────────────────
  enableHeartbeat: true,
  heartbeatInterval: Duration(seconds: 30),
  heartbeatTimeout: Duration(seconds: 10),
  heartbeatMessage: 'ping',
  expectedPongMessage: 'pong',   // or use expectedPongMessagePattern
  maxMissedHeartbeats: 3,

  // ── Offline message queue ─────────────────────────────────────
  enableMessageQueue: true,
  maxQueueSize: 200,             // 0 = unlimited
  messageQueueTimeout: Duration(minutes: 10),

  // ── ACK confirmation ──────────────────────────────────────────
  enableAck: true,
  ackTimeout: Duration(seconds: 30),
  maxAckRetries: 3,
);
```

---

## Feature Guide

### Interceptors

Interceptors run in order on every outgoing and incoming message. Return `null` to drop a message entirely.

```dart
class AuthInterceptor extends WebSocketInterceptor {
  @override
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async {
    return message.copyWith(
      metadata: {...?message.metadata, 'token': myToken},
    );
  }
}

client.addInterceptor(AuthInterceptor());
client.addInterceptor(LoggingInterceptor(logger: print)); // built-in
```

---

### Offline Message Queue

Enable in `WebSocketConfig`. Messages sent while disconnected are buffered and flushed automatically when the connection is re-established.

```dart
final config = WebSocketConfig(
  url: 'wss://server.com',
  enableMessageQueue: true,
  maxQueueSize: 100,
  messageQueueTimeout: Duration(minutes: 5),
);

// Safe to call even when offline — the message is queued, not thrown away
await client.sendText('queued while offline');
```

---

### ACK Confirmation

The client injects a unique `__ack_id__` into each message's metadata. The server must reply with `{"__ack__": "<id>"}` to confirm receipt. Unacknowledged messages are retried up to `maxAckRetries` times.

```dart
final config = WebSocketConfig(
  url: 'wss://server.com',
  enableAck: true,
  ackTimeout: Duration(seconds: 30),
  maxAckRetries: 3,
);

// Resolves only after the server ACK is received, or throws TimeoutException
await client.sendMessage(
  WebSocketMessage.json({'type': 'order', 'id': 42}),
  useAck: true,
);
```

---

### Topic Channels

Multiplex logical channels over a single connection. Wire format:

```json
{"topic": "room:lobby", "event": "new_message", "payload": {}}
```

```dart
final lobby  = client.channel('room:lobby');
final alerts = client.channel('system:alerts');

lobby.messageStream.listen((msg) => print('Lobby: ${msg.data}'));
alerts.messageStream.listen((msg) => print('Alert: ${msg.data}'));

await lobby.send('new_message', {'text': 'Hello!', 'user': 'Alice'});
```

---

### Compression

Add `CompressionInterceptor` to gzip messages above a configurable byte threshold. Decompression is applied automatically to incoming messages.

> Available on **native platforms only** (Android, iOS, macOS, Linux, Windows). Not supported on Web.

```dart
// Compress outgoing messages larger than 1 KB
client.addInterceptor(CompressionInterceptor(threshold: 1024));
```

---

### Connection Pool

Distribute load across multiple server endpoints.

```dart
final pool = WebSocketPool(
  configs: [
    WebSocketConfig(url: 'wss://server1.example.com'),
    WebSocketConfig(url: 'wss://server2.example.com'),
    WebSocketConfig(url: 'wss://server3.example.com'),
  ],
  strategy: PoolStrategy.roundRobin, // or .random / .leastConnections
);

await pool.connectAll();

final client = pool.acquire();
await client.sendText('hello');

await pool.broadcast('ping'); // sends to every connected client
await pool.dispose();
```

---

### State & Statistics

**Connection state:**

```dart
client.stateStream.listen((state) {
  switch (state) {
    case WebSocketState.connecting:    print('Connecting…');
    case WebSocketState.connected:     print('Connected');
    case WebSocketState.disconnecting: print('Disconnecting…');
    case WebSocketState.disconnected:  print('Disconnected');
    case WebSocketState.error:         print('Error');
  }
});
```

**Real-time metrics:**

```dart
client.statsStream.listen((stats) {
  print('Queued messages : ${stats['messageQueue']['queueLength']}');
  print('Pending ACKs    : ${stats['ack']['pendingAcks']}');
  print('Active topics   : ${stats['channels']['activeTopics']}');
  print('Missed heartbeat: ${stats['heartbeat']['missedHeartbeats']}');
});
```

**Send message types:**

```dart
await client.sendText('plain text');
await client.sendJson({'key': 'value'});
await client.sendBinary([0x01, 0x02, 0x03]);

// Custom envelope
await client.sendMessage(WebSocketMessage(
  data: 'custom',
  timestamp: DateTime.now(),
  type: 'custom',
  metadata: {'priority': 'high'},
));
```

---

## Testing with MockAdapter

`MockWebSocketAdapter` is a full-featured test double: no network required, supports artificial failures, and records all sent messages.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adapter_websocket/websocket_plugin.dart';

void main() {
  test('queues messages while offline and flushes on reconnect', () async {
    final config = WebSocketConfig(
      url: 'wss://test.example.com',
      enableMessageQueue: true,
    );
    final mock   = MockWebSocketAdapter(config);
    final client = WebSocketClient(mock);

    await client.connect();

    // Simulate disconnection
    await mock.disconnect();

    // Send while offline — message is buffered, not thrown
    await client.sendText('queued message');

    // Reconnect — the queue is flushed automatically
    await client.connect();

    expect(mock.sentMessages, isNotEmpty);

    await client.dispose();
  });
}
```

---

## Best Practices

1. **Always call `client.dispose()`** when the client is no longer needed to release timers and stream controllers.
2. **Use `MockWebSocketAdapter` for unit tests** — no network required, deterministic, and fast.
3. **Enable `enableMessageQueue`** for data that must survive transient disconnections (e.g., chat messages, telemetry).
4. **Enable `enableAck` selectively** — ACK adds latency per message; reserve it for critical operations like order submission.
5. **Add `LoggingInterceptor` during development** to trace the full message pipeline without polluting production logs.
6. **Use `CompressionInterceptor`** for large JSON payloads to reduce bandwidth on poor networks.
7. **Use `WebSocketPool`** when your backend is clustered or replicated to spread load and improve fault tolerance.
8. **Tune `heartbeatInterval` to match your server's idle timeout** — a too-short interval wastes bandwidth; a too-long one misses outages.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
