import 'dart:io';

class MLService {
  MLService() {
    // Model loading skipped on unsupported platforms
  }

  Future<Map<String, dynamic>> processImage(File imageFile) async {
    // Always use mock inference on web/unsupported platforms
    return await _mockInference(imageFile);
  }

  Future<Map<String, dynamic>> _mockInference(File imageFile) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate processing time
    
    // Simple mock logic
    bool isParasitized = false;
    double mockConfidence = 90.0;
    
    try {
      final length = await imageFile.length();
      isParasitized = length % 2 == 0; 
      mockConfidence = 85.0 + (length % 15);
    } catch (_) {
      // Fallback if imageFile.length() fails on web
    }
    
    return {
      'status': isParasitized ? 'Parasitized' : 'Uninfected',
      'confidence': mockConfidence,
    };
  }
}
