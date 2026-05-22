# adapter_websocket

A robust Flutter WebSocket plugin built on the **Adapter design pattern**, providing a modular and fully testable interface for WebSocket communication. Features automatic reconnection, heartbeat monitoring, offline message buffering, ACK confirmation, topic-based multiplexing, transparent compression, and a flexible interceptor pipeline.

## Features

| Feature | Description |
|---|---|
| **Adapter Pattern** | Swap implementations (real / mock) without changing client code |
| **Auto-Reconnect** | Exponential backoff with jitter and configurable retry limits |
| **Heartbeat** | Customisable ping/pong with missed-heartbeat detection |
| **Interceptors** | Transform or suppress messages at send/receive time (logging, auth, etc.) |
| **Message Queue** | Buffer outgoing messages offline; flush automatically on reconnect |
| **ACK Confirmation** | Reliable delivery with server acknowledgement and auto-retry |
| **Topic Channels** | Multiplex logical channels over one connection |
| **Compression** | Transparent gzip compression for large messages |
| **Connection Pool** | Balance load across multiple server endpoints |
| **Statistics** | Real-time metrics for heartbeat, reconnection, queue, and ACK |
| **Mock Adapter** | Full-featured test double with failure injection |

## Installation

```yaml
dependencies:
  adapter_websocket: ^0.1.0
```

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

await client.connect();
await client.sendText('Hello, WebSocket!');
await client.sendJson({'type': 'greeting', 'message': 'Hello'});
await client.dispose();
```

## Configuration

```dart
final config = WebSocketConfig(
  url: 'wss://your-server.com',
  protocols: ['chat'],
  headers: {'Authorization': 'Bearer token'},
  connectionTimeout: Duration(seconds: 10),

  // Reconnection
  autoReconnect: true,
  maxReconnectAttempts: 5,
  reconnectDelay: Duration(seconds: 2),
  useExponentialBackoff: true,
  maxReconnectDelay: Duration(minutes: 5),
  backoffMultiplier: 2.0,

  // Heartbeat
  enableHeartbeat: true,
  heartbeatInterval: Duration(seconds: 30),
  heartbeatTimeout: Duration(seconds: 10),
  heartbeatMessage: 'ping',
  expectedPongMessage: 'pong',
  maxMissedHeartbeats: 3,

  // Message queue
  enableMessageQueue: true,
  maxQueueSize: 200,
  messageQueueTimeout: Duration(minutes: 10),

  // ACK
  enableAck: true,
  ackTimeout: Duration(seconds: 30),
  maxAckRetries: 3,
);
```

## Feature Guide

### Interceptors

Interceptors run in order on every outgoing and incoming message. Return `null` to suppress a message entirely.

```dart
class AuthInterceptor extends WebSocketInterceptor {
  @override
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async {
    final meta = {...?message.metadata, 'token': myToken};
    return WebSocketMessage(
      data: message.data,
      timestamp: message.timestamp,
      type: message.type,
      metadata: meta,
    );
  }
}

client.addInterceptor(AuthInterceptor());
client.addInterceptor(LoggingInterceptor(logger: print));
```

### Message Queue (Offline Buffer)

Enable in `WebSocketConfig`. Messages sent while disconnected are buffered and flushed automatically on reconnect.

```dart
final config = WebSocketConfig(
  url: 'wss://server.com',
  enableMessageQueue: true,
  maxQueueSize: 100,
  messageQueueTimeout: Duration(minutes: 5),
);

// Safe to call even when offline — message is queued
await client.sendText('will be sent on reconnect');
```

### ACK Confirmation

The client injects a unique `__ack_id__` into each message metadata. The server must reply with `{"__ack__": "<id>"}` to confirm receipt.

```dart
final config = WebSocketConfig(
  url: 'wss://server.com',
  enableAck: true,
  ackTimeout: Duration(seconds: 30),
  maxAckRetries: 3,
);

// Returns only after server ACK, or throws TimeoutException
await client.sendMessage(
  WebSocketMessage.json({'type': 'order', 'id': 42}),
  useAck: true,
);
```

### Topic Channels (Multiplexing)

Send and receive on named logical channels over a single connection.

Wire format: `{"topic":"room:lobby","event":"new_message","payload":{…}}`

```dart
final lobby = client.channel('room:lobby');
final alerts = client.channel('system:alerts');

// Listen per topic
lobby.messageStream.listen((msg) => print('Lobby: ${msg.data}'));
alerts.messageStream.listen((msg) => print('Alert: ${msg.data}'));

// Send to a topic
await lobby.send('new_message', {'text': 'Hello!', 'user': 'Alice'});
```

### Compression

Add `CompressionInterceptor` to automatically gzip messages above the byte threshold. Available on native platforms only (not web).

```dart
client.addInterceptor(CompressionInterceptor(threshold: 1024)); // compress if > 1 KB
```

### Connection Pool

Distribute load across multiple server endpoints.

```dart
final pool = WebSocketPool(
  configs: [
    WebSocketConfig(url: 'wss://server1.example.com'),
    WebSocketConfig(url: 'wss://server2.example.com'),
    WebSocketConfig(url: 'wss://server3.example.com'),
  ],
  strategy: PoolStrategy.roundRobin,
);

await pool.connectAll();

final client = pool.acquire();
await client.sendText('hello');

await pool.broadcast('ping'); // sends to all connected clients
await pool.dispose();
```

## State Management

```dart
client.stateStream.listen((state) {
  switch (state) {
    case WebSocketState.connecting:    print('Connecting…'); break;
    case WebSocketState.connected:     print('Connected'); break;
    case WebSocketState.disconnecting: print('Disconnecting…'); break;
    case WebSocketState.disconnected:  print('Disconnected'); break;
    case WebSocketState.error:         print('Error'); break;
  }
});
```

## Message Types

```dart
await client.sendText('plain text');
await client.sendJson({'key': 'value'});
await client.sendBinary([0x01, 0x02, 0x03]);

// Custom message
await client.sendMessage(WebSocketMessage(
  data: 'custom',
  timestamp: DateTime.now(),
  type: 'custom',
  metadata: {'priority': 'high'},
));
```

## Statistics

```dart
client.statsStream.listen((stats) {
  print('Queue: ${stats['messageQueue']['queueLength']}');
  print('Pending ACKs: ${stats['ack']['pendingAcks']}');
  print('Topics: ${stats['channels']['activeTopics']}');
  print('Missed heartbeats: ${stats['heartbeat']['missedHeartbeats']}');
});
```

## Testing

```dart
final config = WebSocketConfig(
  url: 'wss://test.example.com',
  enableMessageQueue: true,
  enableAck: true,
);
final mock = MockWebSocketAdapter(config);
final client = WebSocketClient(mock);

await client.connect();

// Send while offline
await mock.disconnect();
await client.sendText('queued message');  // queued, not thrown

// Reconnect — queue is flushed automatically
await client.connect();
expect(mock.sentMessages.length, greaterThan(0));
```

## Best Practices

1. Always call `client.dispose()` when done.
2. Use `MockWebSocketAdapter` for unit tests — no network required.
3. Enable `enableMessageQueue` for critical data to survive disconnections.
4. Use `enableAck` only for important messages that need guaranteed delivery.
5. Add `LoggingInterceptor` during development to trace all messages.
6. Use `CompressionInterceptor` for large JSON payloads to save bandwidth.
7. Use `WebSocketPool` when connecting to clustered or replicated servers.

## License

MIT License — see LICENSE for details.
