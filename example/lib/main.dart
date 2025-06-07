import 'package:flutter/material.dart';
import 'package:adapter_websocket/websocket_plugin.dart';
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced WebSocket Plugin Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: WebSocketDemo(),
    );
  }
}

class WebSocketDemo extends StatefulWidget {
  @override
  _WebSocketDemoState createState() => _WebSocketDemoState();
}

class _WebSocketDemoState extends State<WebSocketDemo> {
  late WebSocketClient _client;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _urlController = TextEditingController(
    text: 'wss://echo.websocket.org',
  );
  final List<String> _messages = [];
  final List<String> _logs = [];
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _initializeWebSocket();
  }

  void _initializeWebSocket() {
    final config = WebSocketConfig(
      url: _urlController.text,
      autoReconnect: true,
      maxReconnectAttempts: 5,
      reconnectDelay: Duration(seconds: 2),
      useExponentialBackoff: true,
      maxReconnectDelay: Duration(minutes: 2),
      enableLogging: true,
      // Enhanced heartbeat configuration
      enableHeartbeat: true,
      heartbeatInterval: Duration(seconds: 15),
      heartbeatTimeout: Duration(seconds: 5),
      heartbeatMessage: 'ping',
      expectedPongMessage: 'pong',
      maxMissedHeartbeats: 3,
    );

    final adapter = WebSocketChannelAdapter(config);
    _client = WebSocketClient(adapter);

    // Listen to state changes
    _client.stateStream.listen((state) {
      setState(() {
        _logs.add('State: ${state.description}');
      });
    });

    // Listen to messages
    _client.messageStream.listen((message) {
      setState(() {
        if (message.metadata?['isHeartbeat'] == true) {
          _logs.add('Heartbeat: ${message.data}');
        } else {
          _messages.add('Received: ${message.data}');
        }
      });
    });

    // Listen to errors
    _client.errorStream.listen((error) {
      setState(() {
        _logs.add('Error: $error');
      });
    });

    // Listen to logs
    _client.logStream.listen((log) {
      setState(() {
        _logs.add(log);
      });
    });

    // Listen to statistics
    _client.statsStream.listen((stats) {
      setState(() {
        _stats = stats;
      });
    });
  }

  Future<void> _connect() async {
    try {
      await _client.connect();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $error')),
      );
    }
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
  }

  Future<void> _forceReconnect() async {
    await _client.forceReconnect();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      try {
        await _client.sendText(_messageController.text);
        setState(() {
          _messages.add('Sent: ${_messageController.text}');
        });
        _messageController.clear();
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $error')),
        );
      }
    }
  }

  Future<void> _sendJsonMessage() async {
    try {
      final jsonMessage = {
        'type': 'greeting',
        'message': 'Hello from Flutter!',
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _client.sendJson(jsonMessage);
      setState(() {
        _messages.add('Sent JSON: $jsonMessage');
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON send failed: $error')),
      );
    }
  }

  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  @override
  void dispose() {
    _client.dispose();
    _messageController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enhanced WebSocket Plugin Demo'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Connection controls
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: 'WebSocket URL',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        _initializeWebSocket();
                      },
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _client.isConnected ? null : _connect,
                            child: Text('Connect'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _client.isConnected ? _disconnect : null,
                            child: Text('Disconnect'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _forceReconnect,
                            child: Text('Force Reconnect'),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Status: ${_client.currentState.description}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _client.isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Statistics
            if (_stats.isNotEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connection Statistics', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Heartbeat Active: ${_stats['heartbeat']?['isActive'] ?? false}'),
                      Text('Missed Heartbeats: ${_stats['heartbeat']?['missedHeartbeats'] ?? 0}'),
                      Text('Reconnect Attempts: ${_stats['reconnection']?['reconnectAttempts'] ?? 0}'),
                      Text('Is Reconnecting: ${_stats['reconnection']?['isReconnecting'] ?? false}'),
                    ],
                  ),
                ),
              ),
            
            SizedBox(height: 16),
            
            // Message sending
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _client.isConnected ? _sendMessage : null,
                            child: Text('Send Text'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _client.isConnected ? _sendJsonMessage : null,
                            child: Text('Send JSON'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Messages and logs
            Expanded(
              child: Row(
                children: [
                  // Messages
                  Expanded(
                    child: Card(
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Messages', style: TextStyle(fontWeight: FontWeight.bold)),
                                TextButton(
                                  onPressed: _clearMessages,
                                  child: Text('Clear'),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                  child: Text(
                                    _messages[index],
                                    style: TextStyle(fontSize: 12),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(width: 8),
                  
                  // Logs
                  Expanded(
                    child: Card(
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Logs & Heartbeat', style: TextStyle(fontWeight: FontWeight.bold)),
                                TextButton(
                                  onPressed: _clearLogs,
                                  child: Text('Clear'),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                final isHeartbeat = log.contains('Heartbeat:') || log.contains('heartbeat');
                                return Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontSize: 10, 
                                      color: isHeartbeat ? Colors.blue[600] : Colors.grey[600],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
