import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

// Import both implementations
import 'ml_service_mobile.dart' as mobile;
import 'ml_service_stub.dart' as stub;

/// A unified MLService that routes to the TFLite implementation on
/// Android/iOS and falls back to the stub on Windows/macOS/Linux desktop.
class MLService {
  final _isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  late final dynamic _delegate;

  MLService() {
    if (_isMobile) {
      _delegate = mobile.MLService();
    } else {
      _delegate = stub.MLService();
    }
  }

  Future<Map<String, dynamic>> processImage(XFile imageFile) {
    return _delegate.processImage(imageFile);
  }
}
