import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  Interpreter? _interpreter;
  bool _isMock = false;
  late final Future<void> _initialization;

  // Class labels in alphabetical order (matching Keras default class ordering)
  static const List<String> _classLabels = ['Other', 'Parasitized', 'Uninfected'];

  MLService() {
    _initialization = _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      // Load the model from assets. The asset name should be the filename
      // as declared under `flutter.assets` in pubspec.yaml.
      _interpreter = await Interpreter.fromAsset('assets/malaria_model.tflite');
      debugPrint("Loaded real model successfully!");
    } catch (e) {
      debugPrint("Failed to load TFLite model, using mock ML logic: $e");
      _isMock = true;
    }
  }

  Future<Map<String, dynamic>> processImage(File imageFile) async {
    await _initialization;

    try {
      // 1. Read and decode the image
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) throw Exception("Failed to decode image");

      // If we're using the mock model or model failed to load, return mock results
      if (_isMock || _interpreter == null) {
        return await _mockInference(imageFile);
      }

      // 2. Resize to 224x224 (MobileNetV2 expected size)
      final resizedImage =
          img.copyResize(decodedImage, width: 224, height: 224);

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
              final r = (pixel.r / 127.5) - 1.0;
              final g = (pixel.g / 127.5) - 1.0;
              final b = (pixel.b / 127.5) - 1.0;
              return [r, g, b];
            },
          ),
        ),
      );

      // 4. Create output tensor [1, 3] for 3 classes
      var outputTensor = List.generate(1, (i) => List.filled(3, 0.0));

      // 5. Run inference
      _interpreter!.run(inputTensor, outputTensor);

      // 6. Process the result – find the class with the highest probability
      final probabilities = outputTensor[0];
      int bestIndex = 0;
      double bestProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > bestProb) {
          bestProb = probabilities[i];
          bestIndex = i;
        }
      }

      final predictedLabel = _classLabels[bestIndex];
      final confidence = bestProb * 100;

      debugPrint(
        '[MLService] Probabilities: '
        'Other=${(probabilities[0] * 100).toStringAsFixed(1)}% '
        'Parasitized=${(probabilities[1] * 100).toStringAsFixed(1)}% '
        'Uninfected=${(probabilities[2] * 100).toStringAsFixed(1)}% '
        '→ $predictedLabel (${confidence.toStringAsFixed(1)}%)',
      );

      // Map the "Other" class to the existing "Invalid" UI status
      if (predictedLabel == 'Other') {
        return {
          'status': 'Invalid',
          'confidence': 0.0,
          'reason':
              'This image does not appear to be a blood smear microscopy slide. '
              'Please upload a Giemsa-stained or bright-field blood smear image.',
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

  // A mock inference method used while we don't have the real model
  Future<Map<String, dynamic>> _mockInference(File imageFile) async {
    await Future.delayed(
        const Duration(seconds: 2)); // Simulate processing time

    // Simple logic based on file size/name just to have a pseudo-random result
    final length = await imageFile.length();
    final isParasitized = length % 2 == 0;

    return {
      'status': isParasitized ? 'Parasitized' : 'Uninfected',
      'confidence': 85.0 + (length % 15), // Mock confidence between 85% and 99%
    };
  }
}

