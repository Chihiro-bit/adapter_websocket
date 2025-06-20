## 0.0.6

* Added `certificateErrorCallback` handling in `WebSocketClient`.
* `WebSocketChannelAdapter` invokes this callback when certificate
  validation fails.

* Added `sslContext` and `badCertificateCallback` options to `WebSocketConfig`.
* Existing `httpClient` parameter remains supported.
* The adapter now inspects the provided `HttpClient` and applies the callback
  when a custom `SecurityContext` is used.
