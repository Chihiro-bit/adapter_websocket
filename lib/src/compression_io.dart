import 'dart:io';

List<int> platformGzipEncode(List<int> data) => gzip.encode(data);
List<int> platformGzipDecode(List<int> data) => gzip.decode(data);
const bool platformSupportsCompression = true;
