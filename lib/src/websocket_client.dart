import 'dart:async';
import 'websocket_adapter.dart';
import 'websocket_config.dart';
import 'websocket_message.dart';
import 'websocket_state.dart';
import 'heartbeat_manager.dart';
import 'reconnection_manager.dart';
import 'interceptor.dart';
import 'message_queue.dart';
import 'ack_manager.dart';
import 'channel_manager.dart';
import 'websocket_topic.dart';

/// High-level WebSocket client that integrates all plugin features:
/// heartbeat, reconnection, interceptors, message queue, ACK, and topic channels.
class WebSocketClient {
  final WebSocketAdapter _adapter;

  // Core streams
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _statsController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Managers
  late final HeartbeatManager _heartbeatManager;
  late final ReconnectionManager _reconnectionManager;
  late final ChannelManager _channelManager;

  // Feature: interceptors
  final InterceptorChain _interceptors = InterceptorChain();

  // Feature: message queue
  MessageQueue? _messageQueue;

  // Feature: ACK
  AckManager? _ackManager;

  bool _disposed = false;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _errorSubscription;

  WebSocketClient(this._adapter) {
    _initFeatures();
    _initializeManagers();
    _setupSubscriptions();
  }

  // ─── Public streams ────────────────────────────────────────────────────────

  Stream<WebSocketState> get stateStream => _adapter.stateStream;
  Stream<WebSocketMessage> get messageStream => _adapter.messageStream;
  Stream<dynamic> get errorStream => _adapter.errorStream;
  Stream<String> get logStream => _logController.stream;
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;

  // ─── State ─────────────────────────────────────────────────────────────────

  WebSocketState get currentState => _adapter.currentState;
  WebSocketConfig get config => _adapter.config;
  bool get isConnected => _adapter.isConnected;
  bool get isConnecting => _adapter.isConnecting;
  bool get isClosed => _adapter.isClosed;

  // ─── Statistics ────────────────────────────────────────────────────────────

  Map<String, dynamic> get connectionStats => {
        'connectionState': currentState.description,
        'isConnected': isConnected,
        'heartbeat': _heartbeatManager.getStats(),
        'reconnection': _reconnectionManager.getStats(),
        'messageQueue': _messageQueue?.getStats() ??
            {'enabled': false},
        'ack': _ackManager?.getStats() ?? {'enabled': false},
        'channels': _channelManager.getStats(),
        'interceptors': _interceptors.interceptors.length,
        'config': {
          'url': config.url,
          'autoReconnect': config.autoReconnect,
          'enableHeartbeat': config.enableHeartbeat,
          'heartbeatInterval': config.heartbeatInterval.inMilliseconds,
          'maxReconnectAttempts': config.maxReconnectAttempts,
          'enableMessageQueue': config.enableMessageQueue,
          'enableAck': config.enableAck,
        },
      };

  // ─── Interceptor API ───────────────────────────────────────────────────────

  /// Adds an interceptor to the end of the chain.
  void addInterceptor(WebSocketInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  /// Removes a previously added interceptor.
  void removeInterceptor(WebSocketInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  // ─── Topic / Channel API ───────────────────────────────────────────────────

  /// Returns (or creates) a [WebSocketTopic] for [topic].
  ///
  /// All messages whose JSON envelope has `"topic": "<topic>"` are routed here.
  WebSocketTopic channel(String topic) => _channelManager.channel(topic);

  // ─── Connection ────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_disposed) throw StateError('WebSocketClient has been disposed');
    _log('Attempting to connect to ${config.url}');
    try {
      await _adapter.connect();
      _log('Successfully connected to ${config.url}');
      _reconnectionManager.reset();
      if (config.enableHeartbeat) _heartbeatManager.start();
      _drainQueue();
      _publishStats();
    } catch (error) {
      _log('Failed to connect: $error');
      if (config.autoReconnect) _reconnectionManager.startReconnection();
      rethrow;
    }
  }

  Future<void> disconnect([int? code, String? reason]) async {
    _log('Disconnecting WebSocket');
    _heartbeatManager.stop();
    _reconnectionManager.stopReconnection();
    await _adapter.disconnect(code, reason);
  }

  Future<void> forceReconnect() async {
    _log('Forcing reconnection');
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 100));
    await connect();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _log('Disposing WebSocket client');

    _heartbeatManager.dispose();
    _reconnectionManager.dispose();
    _ackManager?.dispose();
    await _channelManager.dispose();

    await _stateSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();

    await _adapter.dispose();
    await _logController.close();
    await _statsController.close();
  }

  // ─── Sending ───────────────────────────────────────────────────────────────

  /// Sends a [WebSocketMessage]. Runs interceptors, queues if offline, and
  /// optionally tracks ACK.
  ///
  /// Set [useAck] to `true` to require server acknowledgement (only works when
  /// [WebSocketConfig.enableAck] is `true`).
  Future<void> sendMessage(WebSocketMessage message, {bool useAck = false}) {
    return _dispatch(message, useAck: useAck);
  }

  /// Sends raw data (string, binary, or any dart object).
  Future<void> send(dynamic data) {
    final message = data is WebSocketMessage
        ? data
        : WebSocketMessage.now(data: data);
    return _dispatch(message, useAck: false);
  }

  Future<void> sendText(String text) =>
      sendMessage(WebSocketMessage.text(text));

  Future<void> sendJson(Map<String, dynamic> json) =>
      sendMessage(WebSocketMessage.json(json));

  Future<void> sendBinary(List<int> bytes) =>
      sendMessage(WebSocketMessage.binary(bytes));

  // ─── Internal send pipeline ────────────────────────────────────────────────

  Future<void> _dispatch(WebSocketMessage message,
      {required bool useAck}) async {
    // 1. Interceptors (e.g., compression, logging)
    final processed = await _interceptors.processSend(message);
    if (processed == null) return; // suppressed by interceptor

    // 2. Send or queue
    if (isConnected) {
      await _sendToAdapter(processed, useAck: useAck);
    } else if (_messageQueue != null) {
      if (!_messageQueue!.enqueue(processed)) {
        throw StateError(
            'Message queue is full (max ${config.maxQueueSize} messages)');
      }
      _log('Message queued (${_messageQueue!.length}/${config.maxQueueSize})');
    } else {
      throw StateError('WebSocket is not connected');
    }
  }

  Future<void> _sendToAdapter(WebSocketMessage message,
      {required bool useAck}) async {
    if (useAck && _ackManager != null) {
      await _ackManager!.sendWithAck(message);
    } else {
      await _adapter.sendMessage(message);
    }
  }

  void _drainQueue() {
    final queue = _messageQueue;
    if (queue == null || queue.isEmpty) return;

    final messages = queue.drain();
    _log('Draining ${messages.length} queued message(s)');
    for (final msg in messages) {
      _sendToAdapter(msg, useAck: false).catchError((e) {
        _log('Failed to send queued message: $e');
      });
    }
  }

  // ─── Initialization ────────────────────────────────────────────────────────

  void _initFeatures() {
    if (config.enableMessageQueue) {
      _messageQueue = MessageQueue(
        maxSize: config.maxQueueSize,
        messageTimeout: config.messageQueueTimeout,
      );
    }

    if (config.enableAck) {
      _ackManager = AckManager(
        timeout: config.ackTimeout,
        maxRetries: config.maxAckRetries,
        sender: (msg) => _adapter.sendMessage(msg),
        log: _log,
      );
    }

    _channelManager =
        ChannelManager(rawSend: (data) => _adapter.send(data));
  }

  void _initializeManagers() {
    _heartbeatManager = HeartbeatManager(
      config: config,
      sendMessage: (msg) => send(msg),
      log: _log,
    );

    _reconnectionManager = ReconnectionManager(
      config: config,
      reconnectCallback: () => _adapter.connect(),
      log: _log,
    );

    _heartbeatManager.setOnHeartbeatTimeout(() {
      _log('Heartbeat timeout — initiating reconnection');
      if (config.autoReconnect) {
        _reconnectionManager.startReconnection();
        _publishStats();
      }
    });

    _heartbeatManager.setOnConnectionHealthy(() => _publishStats());
    _heartbeatManager.setOnConnectionUnhealthy(() => _publishStats());

    _reconnectionManager.setOnReconnectAttempt(() {
      _log('Reconnection attempt started');
      _publishStats();
    });

    _reconnectionManager.setOnReconnectSuccess(() {
      _log('Reconnection successful — restarting heartbeat');
      if (config.enableHeartbeat) _heartbeatManager.start();
      _drainQueue();
      _publishStats();
    });

    _reconnectionManager.setOnReconnectFailure((error) {
      _log('Reconnection failed: $error');
      _publishStats();
    });

    _reconnectionManager.setOnMaxAttemptsReached(() {
      _log('Maximum reconnection attempts reached');
      _publishStats();
    });
  }

  void _setupSubscriptions() {
    _stateSubscription = stateStream.listen((state) {
      _log('State changed to: ${state.description}');

      if (state == WebSocketState.connected) {
        if (config.enableHeartbeat) _heartbeatManager.start();
      } else if (state == WebSocketState.disconnected) {
        _heartbeatManager.stop();
        if (config.autoReconnect && !_disposed) {
          _reconnectionManager.startReconnection();
        }
      } else if (state == WebSocketState.error) {
        _heartbeatManager.stop();
      }
      _publishStats();
    });

    _messageSubscription = messageStream.listen((message) async {
      // ACK check (before interceptors — ACK frames are not user data)
      if (_ackManager != null && _ackManager!.handleIncomingMessage(message)) {
        return; // consumed as ACK
      }

      // Interceptors (e.g., decompress)
      final processed = await _interceptors.processReceive(message);
      if (processed == null) return; // suppressed

      // Route to topic channel if applicable
      _channelManager.route(processed);

      // Heartbeat manager
      _heartbeatManager.handleIncomingMessage(processed);
    });

    _errorSubscription = errorStream.listen((error) async {
      final processed = await _interceptors.processError(error);
      if (processed != null) {
        _log('WebSocket error: $processed');
        _publishStats();
      }
    });
  }

  void _publishStats() {
    if (!_statsController.isClosed) {
      _statsController.add(connectionStats);
    }
  }

  void _log(String message) {
    if (config.enableLogging && !_logController.isClosed) {
      _logController.add('[${DateTime.now().toIso8601String()}] $message');
    }
  }
}
