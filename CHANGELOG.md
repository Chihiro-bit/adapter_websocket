## 0.0.7

* Added `certificateErrorCallback` handling in `WebSocketClient`.
* `WebSocketChannelAdapter` invokes this callback when certificate
  validation fails.

* Removed the `sslContext` option from `WebSocketConfig`.
* Custom TLS contexts should now be configured on the provided `HttpClient`.
