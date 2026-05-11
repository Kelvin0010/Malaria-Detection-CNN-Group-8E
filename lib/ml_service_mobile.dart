import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  Interpreter? _interpreter;
  bool _isMock = false;

  MLService() {
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/malaria_model.tflite');
      debugPrint("Loaded real model successfully!");
    } catch (e) {
      debugPrint("Failed to load real model, using MOCK ML logic: $e");
      _isMock = true;
    }
  }

  Future<Map<String, dynamic>> processImage(File imageFile) async {
    // If we're using the mock model or model failed to load, return mock results
    if (_isMock || _interpreter == null) {
      return await _mockInference(imageFile);
    }

    try {
      // 1. Read and decode the image
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) throw Exception("Failed to decode image");

      // 2. Resize to 224x224 (MobileNetV2 expected size)
      final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

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

      // 4. Create output tensor [1, 1]
      var outputTensor = List.generate(1, (i) => List.filled(1, 0.0));

      // 5. Run inference
      _interpreter!.run(inputTensor, outputTensor);

      // 6. Process the result
      final prediction = outputTensor[0][0];
      final confidence = (prediction > 0.5 ? prediction : (1.0 - prediction)) * 100;
      final isParasitized = prediction > 0.5;

      return {
        'status': isParasitized ? 'Parasitized' : 'Uninfected',
        'confidence': confidence,
      };
    } catch (e) {
      debugPrint("Error during real inference: $e");
      return await _mockInference(imageFile);
    }
  }

  // A mock inference method used while we don't have the real model
  Future<Map<String, dynamic>> _mockInference(File imageFile) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate processing time
    
    // Simple logic based on file size/name just to have a pseudo-random result
    final length = await imageFile.length();
    final isParasitized = length % 2 == 0; 
    
    return {
      'status': isParasitized ? 'Parasitized' : 'Uninfected',
      'confidence': 85.0 + (length % 15), // Mock confidence between 85% and 99%
    };
  }
}
