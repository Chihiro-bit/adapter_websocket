import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adapter_websocket/websocket_plugin.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'adapter_websocket Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WebSocketDemoPage(),
    );
  }
}

// ─── SSL helper ────────────────────────────────────────────────────────────────

Future<HttpClient> createPinnedHttpClient({required String assetPath}) async {
  final certData = await rootBundle.load(assetPath);
  final certBytes = certData.buffer.asUint8List();
  final ctx = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(certBytes);
  final client = HttpClient(context: ctx);
  client.badCertificateCallback = (cert, host, port) {
    return cert.pem == utf8.decode(certBytes);
  };
  return client;
}

// ─── Demo Page ─────────────────────────────────────────────────────────────────

class WebSocketDemoPage extends StatefulWidget {
  const WebSocketDemoPage({super.key});
  @override
  State<WebSocketDemoPage> createState() => _WebSocketDemoPageState();
}

class _WebSocketDemoPageState extends State<WebSocketDemoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Core client
  WebSocketClient? _client;
  final _urlCtrl = TextEditingController(text: 'ws://124.222.6.60:8800');
  final _msgCtrl = TextEditingController();

  // General
  final List<String> _messages = [];
  final List<String> _logs = [];
  Map<String, dynamic> _stats = {};

  // Feature: message queue
  bool _queueEnabled = true;
  int _queuedCount = 0;

  // Feature: ACK
  bool _ackEnabled = false;
  final List<String> _ackLog = [];

  // Feature: Topic channels
  final _topicCtrl = TextEditingController(text: 'room:lobby');
  final _eventCtrl = TextEditingController(text: 'new_message');
  final List<String> _topicMessages = [];
  WebSocketTopic? _activeTopic;

  // Feature: Compression
  bool _compressionEnabled = false;

  // Feature: Connection pool
  WebSocketPool? _pool;
  List<Map<String, dynamic>> _poolStats = [];

  // Feature: Logging interceptor
  bool _loggingInterceptorEnabled = false;
  LoggingInterceptor? _loggingInterceptor;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _initClient();
  }

  Future<void> _initClient() async {
    await _client?.dispose();

    final config = WebSocketConfig(
      url: _urlCtrl.text,
      autoReconnect: true,
      maxReconnectAttempts: 5,
      reconnectDelay: const Duration(seconds: 2),
      useExponentialBackoff: true,
      maxReconnectDelay: const Duration(minutes: 2),
      enableLogging: true,
      enableHeartbeat: true,
      heartbeatInterval: const Duration(seconds: 15),
      heartbeatTimeout: const Duration(seconds: 5),
      heartbeatMessage: '{"type":"heartbeat"}',
      expectedPongMessage: '{"type":"heartbeat_ack"}',
      maxMissedHeartbeats: 3,
      // Message queue
      enableMessageQueue: _queueEnabled,
      maxQueueSize: 50,
      messageQueueTimeout: const Duration(minutes: 5),
      // ACK
      enableAck: _ackEnabled,
      ackTimeout: const Duration(seconds: 15),
      maxAckRetries: 2,
    );

    final adapter = WebSocketChannelAdapter(config);
    _client = WebSocketClient(adapter);

    // Logging interceptor (Feature 6)
    if (_loggingInterceptorEnabled) {
      _loggingInterceptor = LoggingInterceptor(
        logger: (msg) => setState(() => _logs.add(msg)),
        tag: 'INTERCEPT',
      );
      _client!.addInterceptor(_loggingInterceptor!);
    }

    // Compression interceptor (Feature 4)
    if (_compressionEnabled) {
      _client!.addInterceptor(CompressionInterceptor(threshold: 256));
    }

    _client!.stateStream.listen((state) {
      setState(() => _logs.add('State → ${state.description}'));
    });

    _client!.messageStream.listen((msg) {
      if (msg.metadata?['isHeartbeat'] == true) {
        setState(() => _logs.add('♥ heartbeat: ${msg.data}'));
      } else {
        setState(() => _messages.add('↓ ${msg.data}'));
      }
    });

    _client!.errorStream.listen((err) {
      setState(() => _logs.add('✖ Error: $err'));
    });

    _client!.logStream.listen((log) {
      setState(() => _logs.add(log));
    });

    _client!.statsStream.listen((stats) {
      setState(() {
        _stats = stats;
        _queuedCount =
            (stats['messageQueue']?['queueLength'] as int?) ?? 0;
      });
    });
  }

  Future<void> _connect() async {
    try {
      await _client?.connect();
    } catch (e) {
      _snack('Connection failed: $e');
    }
  }

  Future<void> _disconnect() => _client?.disconnect() ?? Future.value();

  Future<void> _forceReconnect() =>
      _client?.forceReconnect() ?? Future.value();

  Future<void> _sendMessage({bool useAck = false}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _client?.sendMessage(
        WebSocketMessage.json({'type': 'broadcast', 'content': text}),
        useAck: useAck,
      );
      setState(() => _messages.add('↑ $text${useAck ? ' [ACK]' : ''}'));
      _msgCtrl.clear();
      if (useAck) {
        setState(() => _ackLog.add('✔ ACK confirmed: $text'));
      }
    } catch (e) {
      _snack('Send failed: $e');
      if (useAck) setState(() => _ackLog.add('✖ ACK failed: $e'));
    }
  }

  void _subscribeToTopic() {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty || _client == null) return;
    _activeTopic = _client!.channel(topic);
    _activeTopic!.messageStream.listen((msg) {
      setState(() =>
          _topicMessages.add('[${msg.type}] ${jsonEncode(msg.data)}'));
    });
    setState(() => _logs.add('Subscribed to topic: $topic'));
  }

  Future<void> _sendToTopic() async {
    if (_activeTopic == null) {
      _snack('Subscribe to a topic first');
      return;
    }
    final event = _eventCtrl.text.trim().isEmpty ? 'msg' : _eventCtrl.text.trim();
    final payload = {'text': _msgCtrl.text, 'user': 'demo'};
    try {
      await _activeTopic!.send(event, payload);
      setState(() => _topicMessages.add('↑ [$event] ${jsonEncode(payload)}'));
      _msgCtrl.clear();
    } catch (e) {
      _snack('Topic send failed: $e');
    }
  }

  Future<void> _initPool() async {
    await _pool?.dispose();
    _pool = WebSocketPool(
      configs: [
        WebSocketConfig(url: _urlCtrl.text, enableLogging: false),
        WebSocketConfig(url: _urlCtrl.text, enableLogging: false),
      ],
      strategy: PoolStrategy.roundRobin,
    );
    await _pool!.connectAll();
    setState(() => _poolStats = _pool!.getStats());
    _snack('Pool connected (${_pool!.connectedCount}/${_pool!.size})');
  }

  Future<void> _poolBroadcast() async {
    if (_pool == null) {
      _snack('Init the pool first');
      return;
    }
    await _pool!.broadcast(jsonEncode({'type': 'broadcast', 'content': 'pool hello'}));
    setState(() => _poolStats = _pool!.getStats());
    _snack('Broadcast sent to ${_pool!.connectedCount} clients');
  }

  void _toggleLoggingInterceptor(bool val) {
    setState(() => _loggingInterceptorEnabled = val);
    _initClient();
  }

  void _toggleCompression(bool val) {
    setState(() => _compressionEnabled = val);
    _initClient();
  }

  void _toggleQueue(bool val) {
    setState(() => _queueEnabled = val);
    _initClient();
  }

  void _toggleAck(bool val) {
    setState(() => _ackEnabled = val);
    _initClient();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
    _client?.dispose();
    _pool?.dispose();
    _tabs.dispose();
    _urlCtrl.dispose();
    _msgCtrl.dispose();
    _topicCtrl.dispose();
    _eventCtrl.dispose();
    super.dispose();
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = _client?.isConnected ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('adapter_websocket Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Connection'),
            Tab(text: 'Interceptors'),
            Tab(text: 'Queue'),
            Tab(text: 'ACK'),
            Tab(text: 'Topics'),
            Tab(text: 'Pool'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildConnectionTab(connected),
          _buildInterceptorTab(),
          _buildQueueTab(connected),
          _buildAckTab(connected),
          _buildTopicsTab(connected),
          _buildPoolTab(),
        ],
      ),
    );
  }

  // ── Tab: Connection ─────────────────────────────────────────────────────────

  Widget _buildConnectionTab(bool connected) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: 'WebSocket URL',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          onSubmitted: (_) => _initClient(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: connected ? null : _connect,
              icon: const Icon(Icons.wifi),
              label: const Text('Connect'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              onPressed: connected ? _disconnect : null,
              child: const Text('Disconnect'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _forceReconnect,
              child: const Text('Force Reconnect'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _StatCard(stats: _stats, queuedCount: _queuedCount),
        const SizedBox(height: 8),
        TextField(
          controller: _msgCtrl,
          decoration: InputDecoration(
            labelText: 'Message',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
            ),
          ),
          onSubmitted: (_) => _sendMessage(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(children: [
            Expanded(child: _LogPane(title: 'Messages', items: _messages,
                onClear: () => setState(() => _messages.clear()))),
            const SizedBox(width: 8),
            Expanded(child: _LogPane(title: 'Logs', items: _logs,
                onClear: () => setState(() => _logs.clear()))),
          ]),
        ),
      ]),
    );
  }

  // ── Tab: Interceptors ───────────────────────────────────────────────────────

  Widget _buildInterceptorTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Interceptors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Interceptors process every message before it is sent or after it is received.\n'
          'They run in the order they were added. Returning null suppresses the message.',
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 24),
        SwitchListTile(
          title: const Text('LoggingInterceptor'),
          subtitle: const Text('Prints every sent/received message to the Logs panel'),
          value: _loggingInterceptorEnabled,
          onChanged: _toggleLoggingInterceptor,
        ),
        SwitchListTile(
          title: const Text('CompressionInterceptor'),
          subtitle: const Text('gzip-compresses messages > 256 bytes (native only)'),
          value: _compressionEnabled,
          onChanged: _toggleCompression,
        ),
        const Divider(height: 24),
        const Text('Custom interceptor example:', style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SelectableText(
            'class AuthInterceptor extends WebSocketInterceptor {\n'
            '  @override\n'
            '  Future<WebSocketMessage?> onSend(WebSocketMessage msg) async {\n'
            '    final meta = {...?msg.metadata, \'token\': myToken};\n'
            '    return msg.copyWith(metadata: meta);\n'
            '  }\n'
            '}\n\n'
            'client.addInterceptor(AuthInterceptor());',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ]),
    );
  }

  // ── Tab: Message Queue ──────────────────────────────────────────────────────

  Widget _buildQueueTab(bool connected) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Message Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'When enabled, messages sent while offline are buffered and automatically '
          'flushed when the connection is restored.',
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 24),
        SwitchListTile(
          title: const Text('Enable message queue'),
          subtitle: Text('maxQueueSize: 50 • timeout: 5 min • queued now: $_queuedCount'),
          value: _queueEnabled,
          onChanged: _toggleQueue,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: connected ? null : () async {
                // Send while disconnected — message will be queued
                await _client?.sendText('queued: ${DateTime.now()}');
                setState(() {});
              },
              child: const Text('Send while offline (queue it)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: connected ? null : _connect,
              child: const Text('Reconnect (flush queue)'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _InfoCard(title: 'How it works', body:
          '1. Call send() or sendMessage() while disconnected.\n'
          '2. If enableMessageQueue is true, the message is buffered.\n'
          '3. On the next successful connect() or reconnect, the queue\n'
          '   is drained and all messages are sent in order.\n'
          '4. Expired messages (past messageQueueTimeout) are discarded.'),
      ]),
    );
  }

  // ── Tab: ACK ────────────────────────────────────────────────────────────────

  Widget _buildAckTab(bool connected) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ACK Confirmation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'ACK mode waits for the server to echo back {"__ack__": "<id>"}. '
          'If no ACK arrives within ackTimeout, the message is retried up to maxAckRetries times.',
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 24),
        SwitchListTile(
          title: const Text('Enable ACK'),
          subtitle: const Text('ackTimeout: 15 s • maxAckRetries: 2'),
          value: _ackEnabled,
          onChanged: _toggleAck,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _msgCtrl,
          decoration: const InputDecoration(
            labelText: 'Message to send with ACK',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: connected && _ackEnabled ? () => _sendMessage(useAck: true) : null,
          icon: const Icon(Icons.verified),
          label: const Text('Send with ACK'),
        ),
        const SizedBox(height: 16),
        Expanded(child: _LogPane(
          title: 'ACK Log',
          items: _ackLog,
          onClear: () => setState(() => _ackLog.clear()),
        )),
      ]),
    );
  }

  // ── Tab: Topics ─────────────────────────────────────────────────────────────

  Widget _buildTopicsTab(bool connected) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Topic Channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Multiplex logical channels over one WebSocket connection using a JSON '
          'envelope: {"topic":"…","event":"…","payload":…}.',
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: TextField(
            controller: _topicCtrl,
            decoration: const InputDecoration(
              labelText: 'Topic name',
              border: OutlineInputBorder(),
            ),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: connected ? _subscribeToTopic : null,
            child: const Text('Subscribe'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _eventCtrl,
            decoration: const InputDecoration(
              labelText: 'Event name',
              border: OutlineInputBorder(),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _msgCtrl,
            decoration: const InputDecoration(
              labelText: 'Payload',
              border: OutlineInputBorder(),
            ),
          )),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _activeTopic != null ? _sendToTopic : null,
            child: const Text('Send'),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(child: _LogPane(
          title: 'Topic Messages (${_topicCtrl.text})',
          items: _topicMessages,
          onClear: () => setState(() => _topicMessages.clear()),
        )),
      ]),
    );
  }

  // ── Tab: Pool ───────────────────────────────────────────────────────────────

  Widget _buildPoolTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Connection Pool', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Manage multiple WebSocket connections to distribute load. '
          'Supports round-robin, random, and least-connections strategies.',
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: _initPool,
            icon: const Icon(Icons.lan),
            label: const Text('Init Pool (2 clients, round-robin)'),
          )),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _pool != null ? _poolBroadcast : null,
            child: const Text('Broadcast'),
          ),
        ]),
        const SizedBox(height: 16),
        if (_poolStats.isNotEmpty) ...[
          const Text('Pool Status', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...(_poolStats.asMap().entries.map((e) => Card(
            child: ListTile(
              leading: Icon(
                e.value['isConnected'] == true ? Icons.wifi : Icons.wifi_off,
                color: e.value['isConnected'] == true ? Colors.green : Colors.red,
              ),
              title: Text('Client ${e.key + 1}: ${e.value['url']}'),
              subtitle: Text(
                'State: ${e.value['state']}  •  Uses: ${e.value['useCount']}',
              ),
            ),
          ))),
        ] else
          _InfoCard(title: 'How it works', body:
            '1. Create a WebSocketPool with a list of server URLs.\n'
            '2. Call connectAll() to establish all connections.\n'
            '3. Call acquire() to get the next client per strategy.\n'
            '4. Call broadcast() to send to every connected client.\n'
            '5. Call dispose() to clean up all connections.'),
      ]),
    );
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final int queuedCount;
  const _StatCard({required this.stats, required this.queuedCount});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    final hb = stats['heartbeat'] as Map? ?? {};
    final rc = stats['reconnection'] as Map? ?? {};
    final ack = stats['ack'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 24, children: [
          _Stat('Heartbeat', hb['isActive'] == true ? 'active' : 'off'),
          _Stat('Missed', '${hb['missedHeartbeats'] ?? 0}'),
          _Stat('Reconnects', '${rc['reconnectAttempts'] ?? 0}'),
          _Stat('Queue', '$queuedCount'),
          _Stat('Pending ACK', '${ack['pendingAcks'] ?? 0}'),
          _Stat('Interceptors', '${stats['interceptors'] ?? 0}'),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}

class _LogPane extends StatelessWidget {
  final String title;
  final List<String> items;
  final VoidCallback onClear;
  const _LogPane({required this.title, required this.items, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            reverse: true,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                items[items.length - 1 - i],
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  const _InfoCard({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.blue[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 13, height: 1.6)),
          ]),
        ),
      );
}
