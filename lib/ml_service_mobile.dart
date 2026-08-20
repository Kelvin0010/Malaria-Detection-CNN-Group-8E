import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  Interpreter? _interpreter;

  late final Future<void> _initialization;
  List<int>? _outputShape; // will be populated after model load

  // Class labels aligned with model output order:
  // Index 0: Parasitized, Index 1: Uninfected, Index 2: Other (if present)
  static const List<String> _classLabels = [
    'Parasitized',
    'Uninfected',
    'Other'
  ];

  MLService() {
    _initialization = _loadModel();
  }

  Future<void> _loadModel() async {
    // Load the model from assets. The asset name should be the filename
    // as declared under `flutter.assets` in pubspec.yaml.
    _interpreter = await Interpreter.fromAsset('assets/malaria_model.tflite');
    // Capture the output tensor shape after loading the model
    _outputShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint("Loaded real model successfully! Output shape: $_outputShape");
  }

  Future<Map<String, dynamic>> processImage(File imageFile) async {
    await _initialization;

    // 1. Read and decode the image
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

    // 2. Resize to 224x224 (MobileNetV2 expected size)
    final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

    // Simple brightness heuristic: if the image is excessively bright (typical of selfies),
    // flag as Invalid to avoid mis‑classification.
    // Compute average brightness (kept for potential future use)
    double totalBrightness = 0.0;
    final int totalPixels = resizedImage.width * resizedImage.height;
    for (int y = 0; y < resizedImage.height; y++) {
      for (int x = 0; x < resizedImage.width; x++) {
        final pixel = resizedImage.getPixel(x, y);
        totalBrightness += (pixel.r + pixel.g + pixel.b) / 3.0;
      }
    }
    final avgBrightness = totalBrightness / totalPixels;

    // ---- Giemsa hue filter ---------------------------------------------------
    // Giemsa‑stained blood smears typically contain purple‑magenta hues (≈260°–340°).
    // We count pixels whose hue falls in this range; if the proportion is low,
    // the image is unlikely to be a blood smear.
    int huePixelCount = 0;
    for (int y = 0; y < resizedImage.height; y++) {
      for (int x = 0; x < resizedImage.width; x++) {
        final pixel = resizedImage.getPixel(x, y);
        // Convert RGB (0‑255) to HSV hue (0‑360)
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


    try {
      // Ensure the model is loaded; if not, return an error map.
      if (_interpreter == null) {
        return {
          'status': 'Error',
          'reason':
              'TFLite model failed to load. Check asset path and compatibility.',
        };
      }

      // 3. Convert image to a 3D float tensor (1, 224, 224, 3)
      // MobileNetV2 preprocessing: pixels between -1 and 1
      var inputTensor = List.generate(
        1,
        (i) => List.generate(
          224,
          (y) => List.generate(
            224,
            (x) {
              final pixel = resizedImage.getPixel(x, y);
              final r = (pixel.r.toInt() / 127.5) - 1.0;
              final g = (pixel.g.toInt() / 127.5) - 1.0;
              final b = (pixel.b.toInt() / 127.5) - 1.0;
              return [r, g, b];
            },
          ),
        ),
      );

      // 5. Create output tensor based on the model's actual output shape
      late List<List<double>> outputTensor;
      if (_outputShape != null && _outputShape!.length == 2) {
        outputTensor = [List.filled(_outputShape![1], 0.0)];
      } else {
        // Fallback allocation
        outputTensor = [List.filled(2, 0.0)];
      }

      // 6. Run inference
      _interpreter!.run(inputTensor, outputTensor);
      debugPrint("Raw TFLite output: ${outputTensor[0]}");

      // 7. Process the result
      String predictedLabel;
      double confidence;
      final rawOut = outputTensor[0];

      if (rawOut.length == 2) {
        // Standard NIH TFLite model output: Index 0 = Parasitized, Index 1 = Uninfected
        final double pParasitized = rawOut[0];
        final double pUninfected = rawOut[1];

        if (pParasitized > pUninfected) {
          predictedLabel = 'Parasitized';
          confidence = (pParasitized <= 1.0) ? pParasitized * 100.0 : pParasitized;
        } else {
          predictedLabel = 'Uninfected';
          confidence = (pUninfected <= 1.0) ? pUninfected * 100.0 : pUninfected;
        }
      } else if (rawOut.length == 1) {
        // Single sigmoid output (0.0 to 1.0): >= 0.5 Parasitized, < 0.5 Uninfected
        final prob = rawOut[0];
        if (prob >= 0.5) {
          predictedLabel = 'Parasitized';
          confidence = prob * 100.0;
        } else {
          predictedLabel = 'Uninfected';
          confidence = (1.0 - prob) * 100.0;
        }
      } else {
        return {
          'status': 'Error',
          'reason': 'Unexpected output size: ${rawOut.length}',
        };
      }

      // Ensure confidence is formatted reasonably (e.g. if raw value is >100 or negative)
      if (confidence < 0) confidence = 0;
      if (confidence > 100) confidence = 100;

      // Apply confidence threshold: require at least 60% confidence for a result
      const double confidenceThreshold = 60.0;
      if (confidence < confidenceThreshold) {
        return {
          'status': 'Invalid',
          'confidence': confidence,
          'reason': 'Confidence below threshold; image may not be a blood smear.',
        };
      }

      debugPrint('→ Final prediction: $predictedLabel (${confidence.toStringAsFixed(1)}%)');

      // If predictedLabel is 'Other' treat as Invalid
      if (predictedLabel == 'Other') {
        return {
          'status': 'Invalid',
          'reason': 'This image does not match our diagnostic categories.',
        };
      }

      return {
        'status': predictedLabel,
        'confidence': confidence,
      };
    } catch (e) {
      debugPrint("Error during real inference: $e");
      return {
        'status': 'Error',
        'reason': 'Inference failed due to model error.',
      };
    }
  }

  // A mock inference method used while we don't have the real model.
  // It now returns an "Invalid" status for clearly non‑blood images (e.g. filenames
  // containing keywords like "invalid", "nonblood", or "testdata"). This enables the
  // UI to show the appropriate message without requiring a trained "Other" class.
  Future<Map<String, dynamic>> _mockInference(File imageFile) async {
    await Future.delayed(
        const Duration(seconds: 2)); // Simulate processing time

    // If the filename suggests the image is not a blood smear, return Invalid.
    final filename = imageFile.path.toLowerCase();
    if (filename.contains('invalid') ||
        filename.contains('nonblood') ||
        filename.contains('testdata')) {
      return {
        'status': 'Invalid',
        'confidence': 0.0,
        'reason':
            'Mock inference: image does not appear to be a blood smear slide.',
      };
    }

    // Otherwise, fall back to a simple parity‑based heuristic.
    final length = await imageFile.length();
    final isParasitized = length % 2 == 0;
    return {
      'status': isParasitized ? 'Parasitized' : 'Uninfected',
      'confidence': 85.0 + (length % 15), // Mock confidence between 85% and 99%
    };
  }
}
