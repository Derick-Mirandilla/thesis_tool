// File: lib/helpers/qr_tflite_helper.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class QRTFLiteHelper {
  static late Interpreter _interpreter;
  static List<String> _labels = [];
  static bool _isInitialized = false;
  
  // Model specifications based on your CNN architecture
  static const int INPUT_SIZE = 69; // Your model uses 69x69 input
  static const int NUM_CHANNELS = 1; // Grayscale input (not RGB)
  
  static Future<void> init({
    required String modelPath,
    required String labelsPath,
  }) async {
    try {
      print("Attempting to load model from: $modelPath");
      print("Attempting to load labels from: $labelsPath");
      
      // Load the TFLite model
      _interpreter = await Interpreter.fromAsset(modelPath);
      
      // Load labels
      final labelsData = await rootBundle.loadString(labelsPath);
      _labels = labelsData.trim().split('\n');
      
      // Validate labels
      if (_labels.length < 2) {
        throw Exception("Labels file must contain at least 2 labels (malicious, benign)");
      }
      
      _isInitialized = true;
      print("✅ QR Security Model loaded successfully");
      print("📊 Model input shape: ${_interpreter.getInputTensors()}");
      print("📊 Model output shape: ${_interpreter.getOutputTensors()}");
      print("🏷️  Labels loaded: $_labels");
      print("🔧 Expected input: [1, $INPUT_SIZE, $INPUT_SIZE, $NUM_CHANNELS]");
    } catch (e) {
      print("❌ Failed to load QR security model: $e");
      print("📁 Make sure the following files exist and are properly configured:");
      print("   - $modelPath");
      print("   - $labelsPath");
      print("📝 Check your pubspec.yaml assets section");
      throw Exception("Model initialization failed: $e");
    }
  }

  static Future<QRClassificationResult> classifyQRImage(File imageFile) async {
    if (!_isInitialized) {
      throw Exception("Model not initialized. Call init() first.");
    }

    try {
      // Preprocess the image
      final input = await _preprocessImage(imageFile);
      
      // Prepare output tensor for binary classification (single sigmoid output)
      final output = List.filled(1, 0.0).reshape([1, 1]);
      
      // Run inference
      _interpreter.run(input, output);
      
      // Process results for binary classification
      final sigmoidOutput = output[0][0];
      return _processBinaryResults(sigmoidOutput);
    } catch (e) {
      throw Exception("QR classification failed: $e");
    }
  }

  static Future<List<List<List<List<double>>>>> _preprocessImage(File imageFile) async {
    try {
      // Read and decode the image
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception("Unable to decode image");
      }

      // Resize image to model input size (69x69)
      image = img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE);
      
      // Convert to grayscale since your model expects 1 channel
      image = img.grayscale(image);

      // Create input tensor [1, 69, 69, 1]
      final input = List.generate(
        1, // batch size
        (batch) => List.generate(
          INPUT_SIZE, // height
          (y) => List.generate(
            INPUT_SIZE, // width
            (x) => List.generate(
              NUM_CHANNELS, // channels (1 for grayscale)
              (c) => 0.0,
            ),
          ),
        ),
      );

      // Normalize pixels to [0, 1] range for grayscale
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = image.getPixel(x, y);
          // For grayscale, all RGB components are the same, so we use red channel
          final grayValue = img.getLuminance(pixel) / 255.0;
          input[0][y][x][0] = grayValue;
        }
      }

      return input;
    } catch (e) {
      throw Exception("Image preprocessing failed: $e");
    }
  }

  static QRClassificationResult _processBinaryResults(double sigmoidOutput) {
    // Your model uses sigmoid activation, so output is between 0 and 1
    // Typically: > 0.5 = malicious, <= 0.5 = benign
    final isMalicious = sigmoidOutput > 0.5;
    
    // Calculate confidence as distance from the threshold (0.5)
    final confidence = isMalicious ? sigmoidOutput : (1.0 - sigmoidOutput);
    
    // Determine the predicted label
    final predictedLabel = isMalicious ? _labels[0] : _labels[1]; 
    // Assuming labels[0] = "malicious", labels[1] = "benign"
    
    // Create scores for both classes
    final maliciousScore = sigmoidOutput;
    final benignScore = 1.0 - sigmoidOutput;
    
    return QRClassificationResult(
      label: predictedLabel,
      confidence: confidence,
      isMalicious: isMalicious,
      allScores: {
        _labels[0]: maliciousScore,  // malicious score
        _labels[1]: benignScore,     // benign score
      },
      rawOutput: sigmoidOutput,
    );
  }

  static void dispose() {
    if (_isInitialized) {
      _interpreter.close();
      _isInitialized = false;
    }
  }
}

// Data class for classification results
class QRClassificationResult {
  final String label;
  final double confidence;
  final bool isMalicious;
  final Map<String, double> allScores;
  final double rawOutput; // Raw sigmoid output for debugging

  QRClassificationResult({
    required this.label,
    required this.confidence,
    required this.isMalicious,
    required this.allScores,
    required this.rawOutput,
  });

  String get confidencePercentage => "${(confidence * 100).toStringAsFixed(1)}%";
  
  String get riskLevel {
    if (confidence < 0.6) return "Low Confidence";
    if (confidence < 0.8) return "Medium Confidence";
    return "High Confidence";
  }
  
  String get debugInfo => "Raw output: ${rawOutput.toStringAsFixed(4)}";
  
  String get thresholdInfo {
    if (isMalicious) {
      return "Sigmoid: ${rawOutput.toStringAsFixed(4)} > 0.5 → Malicious";
    } else {
      return "Sigmoid: ${rawOutput.toStringAsFixed(4)} ≤ 0.5 → Benign";
    }
  }
}