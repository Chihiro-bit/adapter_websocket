import 'dart:io';

/// Configuration class for WebSocket connections
class WebSocketConfig {
  final String url;
  final List<String>? protocols;
  final Map<String, String>? headers;
  final HttpClient? httpClient;
  final Duration? pingInterval;
  final Duration connectionTimeout;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final bool autoReconnect;
  final bool enableLogging;

  // Heartbeat
  final bool enableHeartbeat;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final String heartbeatMessage;
  final String? expectedPongMessage;
  final RegExp? expectedPongMessagePattern;
  final int maxMissedHeartbeats;
  final bool useExponentialBackoff;
  final Duration maxReconnectDelay;
  final double backoffMultiplier;

  // Feature: Message queue (offline buffer)
  /// Buffer outgoing messages when disconnected and flush on reconnect.
  final bool enableMessageQueue;

  /// Maximum number of messages to buffer. 0 = unlimited.
  final int maxQueueSize;

  /// How long a queued message remains valid. `null` = no expiry.
  final Duration? messageQueueTimeout;

  // Feature: ACK confirmation
  /// Require server acknowledgement for sent messages.
  final bool enableAck;

  /// How long to wait for an ACK before retrying.
  final Duration ackTimeout;

  /// Maximum retry attempts before the send Future fails.
  final int maxAckRetries;

  const WebSocketConfig({
    required this.url,
    this.protocols,
    this.headers,
    this.pingInterval,
    this.connectionTimeout = const Duration(seconds: 10),
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectAttempts = 3,
    this.autoReconnect = true,
    this.enableLogging = false,
    // Heartbeat defaults
    this.enableHeartbeat = true,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.heartbeatMessage = 'ping',
    this.expectedPongMessage,
    this.expectedPongMessagePattern,
    this.maxMissedHeartbeats = 3,
    this.useExponentialBackoff = true,
    this.maxReconnectDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.httpClient,
    // Message queue defaults
    this.enableMessageQueue = false,
    this.maxQueueSize = 100,
    this.messageQueueTimeout,
    // ACK defaults
    this.enableAck = false,
    this.ackTimeout = const Duration(seconds: 30),
    this.maxAckRetries = 3,
  });

  WebSocketConfig copyWith({
    String? url,
    List<String>? protocols,
    Map<String, String>? headers,
    Duration? pingInterval,
    Duration? connectionTimeout,
    Duration? reconnectDelay,
    int? maxReconnectAttempts,
    bool? autoReconnect,
    bool? enableLogging,
    bool? enableHeartbeat,
    Duration? heartbeatInterval,
    Duration? heartbeatTimeout,
    String? heartbeatMessage,
    String? expectedPongMessage,
    RegExp? expectedPongMessagePattern,
    int? maxMissedHeartbeats,
    bool? useExponentialBackoff,
    Duration? maxReconnectDelay,
    double? backoffMultiplier,
    HttpClient? httpClient,
    bool? enableMessageQueue,
    int? maxQueueSize,
    Duration? messageQueueTimeout,
    bool? enableAck,
    Duration? ackTimeout,
    int? maxAckRetries,
  }) {
    return WebSocketConfig(
      url: url ?? this.url,
      protocols: protocols ?? this.protocols,
      headers: headers ?? this.headers,
      pingInterval: pingInterval ?? this.pingInterval,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      enableLogging: enableLogging ?? this.enableLogging,
      enableHeartbeat: enableHeartbeat ?? this.enableHeartbeat,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      heartbeatTimeout: heartbeatTimeout ?? this.heartbeatTimeout,
      heartbeatMessage: heartbeatMessage ?? this.heartbeatMessage,
      expectedPongMessage: expectedPongMessage ?? this.expectedPongMessage,
      expectedPongMessagePattern:
          expectedPongMessagePattern ?? this.expectedPongMessagePattern,
      maxMissedHeartbeats: maxMissedHeartbeats ?? this.maxMissedHeartbeats,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      maxReconnectDelay: maxReconnectDelay ?? this.maxReconnectDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      httpClient: httpClient ?? this.httpClient,
      enableMessageQueue: enableMessageQueue ?? this.enableMessageQueue,
      maxQueueSize: maxQueueSize ?? this.maxQueueSize,
      messageQueueTimeout: messageQueueTimeout ?? this.messageQueueTimeout,
      enableAck: enableAck ?? this.enableAck,
      ackTimeout: ackTimeout ?? this.ackTimeout,
      maxAckRetries: maxAckRetries ?? this.maxAckRetries,
    );
  }

  @override
  String toString() =>
      'WebSocketConfig(url: $url, autoReconnect: $autoReconnect, '
      'enableHeartbeat: $enableHeartbeat, enableMessageQueue: $enableMessageQueue, '
      'enableAck: $enableAck)';
}
