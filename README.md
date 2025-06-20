# WebSocket Plugin

A robust Flutter WebSocket plugin utilizing the Adapter design pattern for flexible WebSocket communication. This plugin provides a modular, testable, and easy-to-use interface for WebSocket connections with support for automatic reconnection, different message types, comprehensive error handling, and enhanced resilience.

## Features

- **Adapter Design Pattern**: Easy switching between different WebSocket implementations
- **Automatic Reconnection**: Configurable auto-reconnect with exponential backoff
- **Multiple Message Types**: Support for text, JSON, and binary messages
- **Comprehensive State Management**: Real-time connection state tracking
- **Error Handling**: Robust error handling and reporting
- **Testing Support**: Built-in mock adapter for unit testing
- **Logging**: Optional detailed logging for debugging
- **Type Safety**: Full TypeScript-like type safety with Dart
- **Heartbeat Mechanism**: Keep connections alive with customizable ping/pong cycles
- **Server Inactivity Detection**: Automatically detect when the server stops responding
- **Missed Heartbeat Tracking**: Monitor connection health with configurable thresholds
- **Automatic Recovery**: Trigger reconnection when heartbeat failures exceed limits
- **Enhanced Reconnection**: Intelligent retry delays that increase exponentially
- **Jitter Support**: Randomized delays to prevent thundering herd problems
- **Maximum Delay Caps**: Configurable upper limits for reconnection delays
- **Connection Resilience**: Robust handling of network instability
- **Advanced Monitoring**: Comprehensive connection and heartbeat metrics
- **Health Monitoring**: Track connection quality and performance
- **Detailed Logging**: Enhanced debugging with heartbeat and reconnection logs

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
adapter_websocket: 0.0.1
```

## Quick Start

### Basic Usage

```dart
import 'package:websocket_plugin/websocket_plugin.dart';

// Create configuration
final config = WebSocketConfig(
url: 'wss://echo.websocket.org',
autoReconnect: true,
maxReconnectAttempts: 3,
enableLogging: true,
);

// Create adapter and client
final adapter = WebSocketChannelAdapter(config);
final client = WebSocketClient(adapter);

// Listen to messages
client.messageStream.listen((message) {
print('Received: ${message.data}');
});

// Connect and send messages
await client.connect();
await client.sendText('Hello, WebSocket!');
await client.sendJson({'type': 'greeting', 'message': 'Hello'});
```

### Advanced Configuration

```dart
final config = WebSocketConfig(
url: 'wss://your-websocket-server.com',
protocols: ['chat', 'superchat'],
headers: {'Authorization': 'Bearer your-token'},
pingInterval: Duration(seconds: 30),
connectionTimeout: Duration(seconds: 10),
reconnectDelay: Duration(seconds: 5),
maxReconnectAttempts: 5,
autoReconnect: true,
enableLogging: true,

// Enhanced reconnection with exponential backoff
useExponentialBackoff: true,
maxReconnectDelay: Duration(minutes: 5),
backoffMultiplier: 2.0,

// Heartbeat configuration
enableHeartbeat: true,
heartbeatInterval: Duration(seconds: 30),
heartbeatTimeout: Duration(seconds: 10),
heartbeatMessage: 'ping',
expectedPongMessage: 'pong',
maxMissedHeartbeats: 3,
);
```

### SSL Configuration

```dart
final (context, callback) = await setupSecurity();

final config = WebSocketConfig(
  url: 'wss://secure.example.com',
  sslContext: context,
  badCertificateCallback: callback,
  // httpClient: myPinnedHttpClient,
);

final adapter = WebSocketChannelAdapter(config);
final client = WebSocketClient(
  adapter,
  certificateErrorCallback: (
    X509Certificate cert,
    String host,
    int port,
  ) {
    print('Invalid certificate from ' + host);
  },
);
```

## Architecture

### Adapter Pattern Implementation

The plugin uses the Adapter design pattern to provide flexibility in WebSocket implementations:

```dart
// Abstract adapter interface
abstract class WebSocketAdapter {
Stream<WebSocketState> get stateStream;
Stream<WebSocketMessage> get messageStream;
Stream<dynamic> get errorStream;
Stream<Map<String, dynamic>> get statsStream;

Future<void> connect();
Future<void> sendMessage(WebSocketMessage message);
Future<void> disconnect([int? code, String? reason]);
Future<void> forceReconnect();
}

// Concrete implementation using web_socket_channel
class WebSocketChannelAdapter implements WebSocketAdapter {
// Implementation details...
}

// Mock implementation for testing
class MockWebSocketAdapter implements WebSocketAdapter {
// Mock implementation...
}
```

### Key Components

1. **WebSocketClient**: High-level client interface with auto-reconnection
2. **WebSocketAdapter**: Abstract interface for different implementations
3. **WebSocketConfig**: Configuration class for connection parameters
4. **WebSocketMessage**: Typed message container with metadata
5. **WebSocketState**: Enumeration of connection states
6. **WebSocketStats**: Comprehensive statistics for connection and heartbeat health

## Message Types

### Text Messages
```dart
await client.sendText('Hello, World!');
```

### JSON Messages
```dart
await client.sendJson({
'type': 'chat',
'message': 'Hello',
'timestamp': DateTime.now().toIso8601String(),
});
```

### Binary Messages
```dart
await client.sendBinary([1, 2, 3, 4, 5]);
```

### Custom Messages
```dart
final message = WebSocketMessage(
data: 'custom data',
timestamp: DateTime.now(),
type: 'custom',
metadata: {'priority': 'high'},
);
await client.sendMessage(message);
```

## State Management

The plugin provides real-time state tracking:

```dart
client.stateStream.listen((state) {
switch (state) {
case WebSocketState.connecting:
print('Connecting...');
break;
case WebSocketState.connected:
print('Connected!');
break;
case WebSocketState.disconnecting:
print('Disconnecting...');
break;
case WebSocketState.disconnected:
print('Disconnected');
break;
case WebSocketState.error:
print('Connection error');
break;
}
});
```

## Error Handling

Comprehensive error handling with detailed error streams:

```dart
client.errorStream.listen((error) {
print('WebSocket error: $error');
// Handle error appropriately
});
```

## Testing

The plugin includes enhanced mock capabilities for testing heartbeat and reconnection scenarios:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:websocket_plugin/websocket_plugin.dart';

void main() {
test('should send and receive messages', () async {
final config = WebSocketConfig(url: 'wss://test.example.com');
final mockAdapter = MockWebSocketAdapter(config);
final client = WebSocketClient(mockAdapter);

    await client.connect();
    await client.sendText('test message');
    
    expect(mockAdapter.sentMessages.length, equals(1));
    expect(mockAdapter.sentMessages.first.data, equals('test message'));
    
    // Simulate receiving a message
    mockAdapter.simulateTextMessage('response');
    
    // Verify message was received
    // ... test assertions
});

test('should handle heartbeat timeouts', () async {
final config = WebSocketConfig(
url: 'wss://test.com',
enableHeartbeat: true,
heartbeatInterval: Duration(milliseconds: 100),
maxMissedHeartbeats: 2,
);

    final mockAdapter = MockWebSocketAdapter(config);
    mockAdapter.setAutoRespondToPing(false); // Simulate unresponsive server
    
    final client = WebSocketClient(mockAdapter);
    
    // Monitor for reconnection attempts
    bool reconnectionTriggered = false;
    client.statsStream.listen((stats) {
      if (stats['reconnection']['isReconnecting'] == true) {
        reconnectionTriggered = true;
      }
    });
    
    await client.connect();
    await Future.delayed(Duration(milliseconds: 500));
    
    expect(reconnectionTriggered, isTrue);
});

test('should simulate network instability', () async {
final mockAdapter = MockWebSocketAdapter(config);
mockAdapter.setSimulateUnstableConnection(true);

    final client = WebSocketClient(mockAdapter);
    await client.connect();
    
    // Connection will randomly disconnect and reconnect
    // Perfect for testing resilience
});
}
```

## Logging

Enable detailed logging for debugging:

```dart
final config = WebSocketConfig(
url: 'wss://your-server.com',
enableLogging: true,
);

client.logStream.listen((log) {
print('WebSocket Log: $log');
});
```

## Best Practices

1. **Always dispose clients**: Call `client.dispose()` when done
2. **Handle connection states**: Listen to state changes for UI updates
3. **Implement error handling**: Always listen to error streams
4. **Use appropriate message types**: Choose the right message type for your data
5. **Configure timeouts**: Set appropriate connection and reconnection timeouts
6. **Test with mocks**: Use the mock adapter for unit testing
7. **Configure appropriate heartbeat intervals** based on your network conditions
8. **Use exponential backoff** for production environments
9. **Monitor connection statistics** to optimize settings
10. **Test with mock adapter** to verify resilience
11. **Enable logging** during development for debugging

## Examples

See the `example/` directory for a complete Flutter app demonstrating all features of the WebSocket plugin.

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.
 
## License

This project is licensed under the MIT License - see the LICENSE file for details.
