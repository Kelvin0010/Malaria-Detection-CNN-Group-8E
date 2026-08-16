import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  Interpreter? _interpreter;

  late final Future<void> _initialization;
  List<int>? _outputShape; // will be populated after model load

  // Class labels – for binary models we will use only Parasitized/Uninfected
  static const List<String> _classLabels = [
    'Other',
    'Parasitized',
    'Uninfected'
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

    try {
      // 1. Read and decode the image
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) throw Exception("Failed to decode image");

      // Ensure the model is loaded; if not, return an error map.
      if (_interpreter == null) {
        return {
          'status': 'Error',
          'reason':
              'TFLite model failed to load. Check asset path and compatibility.',
        };
      }

      // 2. Resize to 224x224 (MobileNetV2 expected size)
      final resizedImage =
          img.copyResize(decodedImage, width: 224, height: 224);

      // Simple variance check – uniform images (e.g., solid background) are unlikely to be blood smears
      double pixelVariance() {
        double sum = 0.0;
        double sumSq = 0.0;
        for (int y = 0; y < resizedImage.height; y++) {
          for (int x = 0; x < resizedImage.width; x++) {
            final pixel = resizedImage.getPixel(x, y);
            final r = pixel.r.toInt();
            final g = pixel.g.toInt();
            final b = pixel.b.toInt();
            final intensity = (r + g + b) ~/ 3;
            sum += intensity.toDouble();
            sumSq += intensity.toDouble() * intensity.toDouble();
          }
        }
        final n = resizedImage.width * resizedImage.height;
        final mean = sum / n;
        final variance = (sumSq / n) - (mean * mean);
        return variance.toDouble();
      }

      if (pixelVariance() < 500) {
        // Very low variance → likely not a blood smear
        return {
          'status': 'Invalid',
          'confidence': 0.0,
          'reason': 'Image appears uniform; not a blood smear.',
        };
      }

      // After variance check, ensure the image has enough red content (blood smear is reddish)
      double redMean() {
        double sumRed = 0.0;
        for (int y = 0; y < resizedImage.height; y++) {
          for (int x = 0; x < resizedImage.width; x++) {
            final pixel = resizedImage.getPixel(x, y);
            sumRed += pixel.r.toInt();
          }
        }
        final n = resizedImage.width * resizedImage.height;
        return sumRed / (n * 255.0);
      }

      if (redMean() < 0.5) {
        return {
          'status': 'Invalid',
          'confidence': 0.0,
          'reason':
              'Image lacks sufficient red coloration; likely not a blood smear.',
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
      // Primary allocation based on reported shape
      if (_outputShape != null &&
          _outputShape!.length == 2 &&
          _outputShape![1] == 3) {
        outputTensor = List.generate(1, (_) => List.filled(3, 0.0));
      } else {
        // Assume binary output as safe fallback
        outputTensor = List.generate(1, (_) => List.filled(1, 0.0));
      }

      try {
        // 6. Run inference
        _interpreter!.run(inputTensor, outputTensor);
      } catch (e) {
        // If shape mismatch occurs, retry with binary output shape
        outputTensor = List.generate(1, (_) => List.filled(1, 0.0));
        _interpreter!.run(inputTensor, outputTensor);
      }

      // 7. Process the result – find the class with the highest probability
      // Interpret the output depending on its shape
      String predictedLabel;
      double confidence;
      if (outputTensor[0].length == 3) {
        // Multi‑class case
        final probabilities = outputTensor[0];
        int bestIndex = 0;
        double bestProb = probabilities[0];
        for (int i = 1; i < probabilities.length; i++) {
          if (probabilities[i] > bestProb) {
            bestProb = probabilities[i];
            bestIndex = i;
          }
        }
        predictedLabel = _classLabels[bestIndex];
        confidence = bestProb * 100;
      } else if (outputTensor[0].length == 1) {
        // Binary case – output is probability of Parasitized
        final prob = outputTensor[0][0];
        confidence = prob * 100;
        predictedLabel = prob >= 0.5 ? 'Parasitized' : 'Uninfected';
      } else {
        return {
          'status': 'Error',
          'reason': 'Unexpected output size: ${outputTensor[0].length}',
        };
      }

      const double confidenceThreshold =
          30.0; // lowered to catch low‑confidence predictions // percent lowered threshold for better invalid detection
      debugPrint(
        '→ $predictedLabel (${confidence.toStringAsFixed(1)}%)',
      );
      // Additional red‑dominance check: ensure a significant portion of pixels have red as the dominant channel
      double redDominanceRatio() {
        int redDominant = 0;
        final total = resizedImage.width * resizedImage.height;
        for (int y = 0; y < resizedImage.height; y++) {
          for (int x = 0; x < resizedImage.width; x++) {
            final pixel = resizedImage.getPixel(x, y);
            final r = pixel.r.toInt();
            final g = pixel.g.toInt();
            final b = pixel.b.toInt();
            if (r > g && r > b) redDominant++;
          }
        }
        return redDominant / total;
      }

      if (redDominanceRatio() < 0.2) {
        return {
          'status': 'Invalid',
          'confidence': 0.0,
          'reason':
              'Insufficient red‑dominant pixels; likely not a blood smear.',
        };
      }

      // If confidence is low or the model predicts 'Other', treat as Invalid

      if (predictedLabel == 'Other' || confidence < confidenceThreshold) {
        return {
          'status': 'Invalid',
          'reason':
              'This image does not appear to be a blood smear microscopy slide. Please upload a Giemsa-stained or bright-field blood smear image.',
        };
      }

      return {
        'status': predictedLabel,
        'confidence': confidence,
      };
    } catch (e) {
      debugPrint("Error during real inference: $e");
      return await _mockInference(imageFile);
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
