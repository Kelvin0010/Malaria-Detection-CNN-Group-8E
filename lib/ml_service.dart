// Platform-aware ML service.
// On web: uses stub (no dart:io).
// On mobile (Android/iOS): uses real TFLite model via ml_service_platform.dart.
// On desktop (Windows/macOS/Linux): uses stub via ml_service_platform.dart.
export 'ml_service_stub.dart'
    if (dart.library.io) 'ml_service_platform.dart';
