import 'dart:async';
import 'dart:math';
import 'websocket_adapter.dart';
import 'websocket_client.dart';
import 'websocket_config.dart';
import 'websocket_message.dart';
import 'websocket_state.dart';
import 'adapters/web_socket_channel_adapter.dart';

/// Strategy for selecting a client from the pool.
enum PoolStrategy {
  /// Cycles through clients in order.
  roundRobin,

  /// Picks a client at random.
  random,

  /// Picks the client with the fewest total uses.
  leastConnections,
}

class _PoolEntry {
  final WebSocketClient client;
  int useCount = 0;
  bool _connecting = false;

  _PoolEntry(this.client);

  Future<void> ensureConnected() async {
    if (client.isConnected || _connecting) return;
    _connecting = true;
    try {
      await client.connect();
    } finally {
      _connecting = false;
    }
  }
}

/// Manages a pool of [WebSocketClient] instances across multiple server endpoints.
///
/// ```dart
/// final pool = WebSocketPool(
///   configs: [
///     WebSocketConfig(url: 'wss://server1.example.com'),
///     WebSocketConfig(url: 'wss://server2.example.com'),
///   ],
///   strategy: PoolStrategy.roundRobin,
/// );
///
/// await pool.connectAll();
/// final client = pool.acquire();   // picks next client
/// await client.sendText('hello');
///
/// await pool.broadcast('ping');    // sends to all connected clients
/// await pool.dispose();
/// ```
class WebSocketPool {
  final PoolStrategy strategy;
  final List<_PoolEntry> _entries;
  int _rrIndex = 0;
  bool _disposed = false;

  WebSocketPool({
    required List<WebSocketConfig> configs,
    this.strategy = PoolStrategy.roundRobin,
    /// Optional factory to create adapters; defaults to [WebSocketChannelAdapter].
    WebSocketAdapter Function(WebSocketConfig)? adapterFactory,
  }) : _entries = configs.map((c) {
          final adapter =
              adapterFactory?.call(c) ?? WebSocketChannelAdapter(c);
          return _PoolEntry(WebSocketClient(adapter));
        }).toList();

  /// Number of clients in the pool.
  int get size => _entries.length;

  /// Number of currently connected clients.
  int get connectedCount =>
      _entries.where((e) => e.client.isConnected).length;

  /// Connects all clients in parallel.
  Future<void> connectAll() =>
      Future.wait(_entries.map((e) => e.ensureConnected()));

  /// Connects the first client only (lazy startup).
  Future<void> connectFirst() async {
    if (_entries.isNotEmpty) await _entries.first.ensureConnected();
  }

  /// Returns a client according to the pool [strategy].
  ///
  /// Prefers connected clients; falls back to any client if none are connected.
  WebSocketClient acquire() {
    if (_entries.isEmpty) throw StateError('WebSocketPool is empty');
    final entry = _pick();
    entry.useCount++;
    return entry.client;
  }

  _PoolEntry _pick() {
    final live = _entries.where((e) => e.client.isConnected).toList();
    final pool = live.isEmpty ? _entries : live;

    switch (strategy) {
      case PoolStrategy.roundRobin:
        final e = pool[_rrIndex % pool.length];
        _rrIndex++;
        return e;
      case PoolStrategy.random:
        return pool[Random().nextInt(pool.length)];
      case PoolStrategy.leastConnections:
        return pool.reduce((a, b) => a.useCount <= b.useCount ? a : b);
    }
  }

  /// Sends [data] to every connected client.
  Future<void> broadcast(dynamic data) => Future.wait(
        _entries
            .where((e) => e.client.isConnected)
            .map((e) => e.client.send(data)),
      );

  /// Sends a [WebSocketMessage] to every connected client.
  Future<void> broadcastMessage(WebSocketMessage message) => Future.wait(
        _entries
            .where((e) => e.client.isConnected)
            .map((e) => e.client.sendMessage(message)),
      );

  /// Returns per-client statistics.
  List<Map<String, dynamic>> getStats() => _entries
      .map((e) => {
            'url': e.client.config.url,
            'isConnected': e.client.isConnected,
            'useCount': e.useCount,
            'state': e.client.currentState.description,
          })
      .toList();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_entries.map((e) => e.client.dispose()));
    _entries.clear();
  }
}
