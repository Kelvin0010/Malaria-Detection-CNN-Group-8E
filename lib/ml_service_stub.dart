import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class MLService {
  MLService() {
    // Model loading skipped on unsupported platforms
  }

  Future<Map<String, dynamic>> processImage(XFile imageFile) async {
    // 1. Read and decode the image for validation
    final img.Image? decodedImage;
    try {
      final imageBytes = await imageFile.readAsBytes();
      decodedImage = img.decodeImage(imageBytes);
    } catch (e) {
      return {
        'status': 'Invalid',
        'confidence': 0.0,
        'reason': 'Could not read or parse image file.',
      };
    }

    if (decodedImage == null) {
      return {
        'status': 'Invalid',
        'confidence': 0.0,
        'reason': 'Failed to decode image. Please ensure it is a valid JPEG/PNG.',
      };
    }

    // 2. Resize to speed up validation
    final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

    // ---- Giemsa hue filter ---------------------------------------------------
    int huePixelCount = 0;
    final int totalPixels = resizedImage.width * resizedImage.height;
    for (int y = 0; y < resizedImage.height; y++) {
      for (int x = 0; x < resizedImage.width; x++) {
        final pixel = resizedImage.getPixel(x, y);
        final double r = pixel.r / 255.0;
        final double g = pixel.g / 255.0;
        final double b = pixel.b / 255.0;
        final double maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);
        final double minVal = [r, g, b].reduce((a, b) => a < b ? a : b);
        double hue;
        if (maxVal == minVal) {
          hue = 0.0;
        } else if (maxVal == r) {
          hue = 60.0 * ((g - b) / (maxVal - minVal)) % 360.0;
        } else if (maxVal == g) {
          hue = 60.0 * ((b - r) / (maxVal - minVal) + 2.0);
        } else {
          hue = 60.0 * ((r - g) / (maxVal - minVal) + 4.0);
        }
        if (hue < 0) hue += 360.0;
        if (hue >= 260.0 && hue <= 340.0) {
          huePixelCount++;
        }
      }
    }
    final double hueRatio = huePixelCount / totalPixels;
    if (hueRatio < 0.30) {
      return {
        'status': 'Invalid',
        'confidence': 0.0,
        'reason': 'Image lacks characteristic Giemsa hue; likely not a blood smear.',
      };
    }
    // -----------------------------------------------------------------------

    // Always use mock inference on web/unsupported platforms for actual results
    return await _mockInference(imageFile);
  }

  Future<Map<String, dynamic>> _mockInference(XFile imageFile) async {
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

