/// In-process mock WebSocket adapter for the demo app.
///
/// Lets the user test every plugin feature (heartbeat, ACK, topic channels,
/// message queue, auto-reconnect) without any network access:
///
///  * **native platforms** — a real WebSocket server bound to 127.0.0.1
///    (genuine wire protocol over localhost);
///  * **web** — an in-memory duplex link with identical server behaviour.
///
/// Both variants expose the same API:
///
/// ```dart
/// final mock = await LocalMockWebSocketAdapter.create(config);
/// final client = WebSocketClient(mock);
/// await client.connect();
/// ```
library;

export 'local_mock_websocket_adapter_stub.dart'
    if (dart.library.io) 'local_mock_websocket_adapter_io.dart';
