// File: lib/helpers/qr_tflite_helper.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'qr_detector_helper.dart';

class QRTFLiteHelper {
  static late Interpreter _interpreter;
  static List<String> _labels = [];
  static bool _isInitialized = false;
  
  // Model specifications based on your CNN architecture
  static const int INPUT_SIZE = 69; // Your model uses 69x69 input
  static const int NUM_CHANNELS = 1; // Grayscale input (not RGB)
  static const double DEFAULT_THRESHOLD = 0.5; // Classification threshold
  
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
      _labels = labelsData.trim().split('\n').where((label) => label.isNotEmpty).toList();
      
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

  static Future<QRSecurityResult> classifyQRImage(File imageFile) async {
    if (!_isInitialized) {
      throw Exception("Model not initialized. Call init() first.");
    }

    try {
      print("🔍 Starting QR classification for: ${imageFile.path}");
      
      // Step 1: Improved QR code detection
      final qrDetection = await QRDetectorHelper.detectQRCode(imageFile);
      print("🔍 QR Detection result: hasQR=${qrDetection.hasQRCode}, confidence=${qrDetection.confidencePercentage}");
      
      if (!qrDetection.hasQRCode) {
        return QRSecurityResult(
          hasQRCode: false,
          qrDetection: qrDetection,
          classificationResult: null,
        );
      }

      // Step 2: If QR code detected, classify it
      print("🖼️  Preprocessing image for CNN model...");
      final input = await _preprocessImage(imageFile);
      
      // Prepare output tensor for binary classification (single sigmoid output)
      final output = List.filled(1, 0.0).reshape([1, 1]);
      
      print("🧠 Running CNN inference...");
      // Run inference
      _interpreter.run(input, output);
      
      // Process results for binary classification
      final sigmoidOutput = output[0][0] as double;
      print("📊 Raw sigmoid output: $sigmoidOutput");
      
      final classificationResult = _processBinaryResults(sigmoidOutput);
      
      return QRSecurityResult(
        hasQRCode: true,
        qrDetection: qrDetection,
        classificationResult: classificationResult,
      );
    } catch (e) {
      print("❌ QR classification failed: $e");
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

      print("🖼️  Original image size: ${image.width}x${image.height}");

      // First, try to detect and crop QR code region for better accuracy
      final qrRegion = _detectAndCropQRRegion(image);
      image = qrRegion ?? image;

      // Resize image to model input size (69x69)
      image = img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE, interpolation: img.Interpolation.cubic);
      
      // Convert to grayscale since your model expects 1 channel
      image = img.grayscale(image);

      // Apply contrast enhancement for better feature extraction
      image = _enhanceContrast(image);

      print("🔧 Preprocessed image size: ${image.width}x${image.height}");

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

      // Normalize pixels
      double minPixel = double.infinity;
      double maxPixel = -double.infinity;
      
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = image.getPixel(x, y);
          final grayValue = img.getLuminance(pixel).toDouble();
          
          // Track min/max for debugging
          minPixel = grayValue < minPixel ? grayValue : minPixel;
          maxPixel = grayValue > maxPixel ? grayValue : maxPixel;
          
          // [0, 1] normalization
          input[0][y][x][0] = grayValue / 255.0;
        }
      }

      print("📊 Pixel range: $minPixel - $maxPixel");
      print("📊 Normalized range: ${input[0][0][0][0]} - ${input[0][INPUT_SIZE-1][INPUT_SIZE-1][0]}");

      return input;
    } catch (e) {
      throw Exception("Image preprocessing failed: $e");
    }
  }

  // FIXED: Correct interpretation of sigmoid output
  static QRClassificationResult _processBinaryResults(double sigmoidOutput) {
    const double threshold = DEFAULT_THRESHOLD;

    // CRITICAL FIX: Sigmoid output interpretation
    // In binary classification with sigmoid:
    // - sigmoid > 0.5 = positive class (malicious)
    // - sigmoid <= 0.5 = negative class (benign)
    
    final maliciousProb = sigmoidOutput;  // This is P(malicious)
    final benignProb = 1.0 - sigmoidOutput;  // This is P(benign)

    final isMalicious = sigmoidOutput >= threshold;
    final predictedLabel = isMalicious ? 'malicious' : 'benign';

    // Confidence is the maximum probability
    final confidence = math.max(maliciousProb, benignProb);

    final Map<String, double> scores = {
      'malicious': maliciousProb,
      'benign': benignProb,
    };

    print("🔎 CORRECT Processing:");
    print("   Raw sigmoid: $sigmoidOutput");
    print("   Malicious prob: ${maliciousProb.toStringAsFixed(4)}");
    print("   Benign prob: ${benignProb.toStringAsFixed(4)}");
    print("   Prediction: $predictedLabel");
    print("   Confidence: ${confidence.toStringAsFixed(4)}");

    return QRClassificationResult(
      label: predictedLabel,
      confidence: confidence,
      isMalicious: isMalicious,
      allScores: scores,
      rawOutput: sigmoidOutput,
      threshold: threshold,
    );
  }

  // Enhanced QR region detection and cropping
  static img.Image? _detectAndCropQRRegion(img.Image image) {
    try {
      final gray = img.grayscale(image);
      
      // Find potential QR regions using edge detection
      final edges = _detectEdges(gray);
      final qrBounds = _findLargestRectangularRegion(edges);
      
      if (qrBounds != null) {
        print("🎯 Detected QR region: ${qrBounds['x']},${qrBounds['y']} ${qrBounds['width']}x${qrBounds['height']}");
        
        // Add padding around detected region
        final padding = 20;
        final x = math.max(0, qrBounds['x']! - padding);
        final y = math.max(0, qrBounds['y']! - padding);
        final width = math.min(image.width - x, qrBounds['width']! + 2 * padding);
        final height = math.min(image.height - y, qrBounds['height']! + 2 * padding);
        
        return img.copyCrop(image, x: x, y: y, width: width, height: height);
      }
    } catch (e) {
      print("⚠️ QR region detection failed: $e, using full image");
    }
    return null;
  }

  // Simple edge detection
  static img.Image _detectEdges(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        // Sobel operator
        final gx = (
          img.getLuminance(image.getPixel(x + 1, y - 1)) * 1 +
          img.getLuminance(image.getPixel(x + 1, y)) * 2 +
          img.getLuminance(image.getPixel(x + 1, y + 1)) * 1 -
          img.getLuminance(image.getPixel(x - 1, y - 1)) * 1 -
          img.getLuminance(image.getPixel(x - 1, y)) * 2 -
          img.getLuminance(image.getPixel(x - 1, y + 1)) * 1
        );
        
        final gy = (
          img.getLuminance(image.getPixel(x - 1, y + 1)) * 1 +
          img.getLuminance(image.getPixel(x, y + 1)) * 2 +
          img.getLuminance(image.getPixel(x + 1, y + 1)) * 1 -
          img.getLuminance(image.getPixel(x - 1, y - 1)) * 1 -
          img.getLuminance(image.getPixel(x, y - 1)) * 2 -
          img.getLuminance(image.getPixel(x + 1, y - 1)) * 1
        );
        
        final magnitude = math.sqrt(gx * gx + gy * gy);
        final intensity = math.min(255, magnitude.round());
        
        result.setPixel(x, y, img.ColorRgb8(intensity, intensity, intensity));
      }
    }
    
    return result;
  }

  // Find largest rectangular region (potential QR code)
  static Map<String, int>? _findLargestRectangularRegion(img.Image edges) {
    int maxArea = 0;
    Map<String, int>? bestRegion;
    
    // Simple approach: scan for high-density edge regions
    final blockSize = 20;
    
    for (int y = 0; y < edges.height - blockSize; y += blockSize ~/ 2) {
      for (int x = 0; x < edges.width - blockSize; x += blockSize ~/ 2) {
        int edgeCount = 0;
        
        // Count edges in this block
        for (int by = y; by < math.min(y + blockSize, edges.height); by++) {
          for (int bx = x; bx < math.min(x + blockSize, edges.width); bx++) {
            if (img.getLuminance(edges.getPixel(bx, by)) > 128) {
              edgeCount++;
            }
          }
        }
        
        // If this region has many edges, consider it as potential QR region
        if (edgeCount > blockSize * blockSize * 0.3) { // 30% edge density
          final area = blockSize * blockSize;
          if (area > maxArea) {
            maxArea = area;
            bestRegion = {
              'x': x,
              'y': y,
              'width': blockSize,
              'height': blockSize,
            };
          }
        }
      }
    }
    
    return bestRegion;
  }

  // Enhance contrast for better feature extraction
  static img.Image _enhanceContrast(img.Image image) {
    // Apply histogram equalization-like enhancement
    final pixels = <int>[];
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        pixels.add(img.getLuminance(image.getPixel(x, y)).round());
      }
    }
    
    pixels.sort();
    final min = pixels.first;
    final max = pixels.last;
    
    if (max == min) return image; // No contrast to enhance
    
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final oldValue = img.getLuminance(image.getPixel(x, y)).round();
        final newValue = ((oldValue - min) * 255 / (max - min)).clamp(0, 255).round();
        result.setPixel(x, y, img.ColorRgb8(newValue, newValue, newValue));
      }
    }
    
    return result;
  }

  // Alternative method with configurable threshold
  static QRClassificationResult classifyWithThreshold(double sigmoidOutput, double customThreshold) {
    final maliciousProb = sigmoidOutput;
    final benignProb = 1.0 - sigmoidOutput;
    final isMalicious = sigmoidOutput >= customThreshold;
    final predictedLabel = isMalicious ? 'malicious' : 'benign';
    final confidence = math.max(maliciousProb, benignProb);

    final Map<String, double> scores = {
      'malicious': maliciousProb,
      'benign': benignProb,
    };

    return QRClassificationResult(
      label: predictedLabel,
      confidence: confidence,
      isMalicious: isMalicious,
      allScores: scores,
      rawOutput: sigmoidOutput,
      threshold: customThreshold,
    );
  }

  // Get model info
  static Map<String, dynamic> getModelInfo() {
    if (!_isInitialized) {
      return {'error': 'Model not initialized'};
    }
    
    return {
      'isInitialized': _isInitialized,
      'inputSize': INPUT_SIZE,
      'channels': NUM_CHANNELS,
      'labels': _labels,
      'threshold': DEFAULT_THRESHOLD,
      'inputShape': [1, INPUT_SIZE, INPUT_SIZE, NUM_CHANNELS],
      'inputTensors': _interpreter.getInputTensors().map((t) => {
        'name': t.name,
        'type': t.type.toString(),
        'shape': t.shape,
      }).toList(),
      'outputTensors': _interpreter.getOutputTensors().map((t) => {
        'name': t.name,
        'type': t.type.toString(),
        'shape': t.shape,
      }).toList(),
    };
  }

  static void dispose() {
    if (_isInitialized) {
      _interpreter.close();
      _isInitialized = false;
      print("🔄 QR Security Model disposed");
    }
  }
}

// Combined result class
class QRSecurityResult {
  final bool hasQRCode;
  final QRDetectionResult qrDetection;
  final QRClassificationResult? classificationResult;

  QRSecurityResult({
    required this.hasQRCode,
    required this.qrDetection,
    this.classificationResult,
  });

  // Helper getters
  bool get isMalicious => classificationResult?.isMalicious ?? false;
  String get securityStatus {
    if (!hasQRCode) return "No QR Code Detected";
    if (classificationResult == null) return "Classification Failed";
    return classificationResult!.isMalicious ? "⚠️ Malicious QR Code" : "✅ Benign QR Code";
  }
  
  String get summary {
    if (!hasQRCode) {
      return "No QR code detected in image (${qrDetection.confidencePercentage} confidence)";
    }
    
    if (classificationResult == null) {
      return "QR code detected but classification failed";
    }
    
    final result = classificationResult!;
    return "QR code detected and classified as ${result.label} with ${result.confidencePercentage} confidence";
  }
}

// Data class for classification results
class QRClassificationResult {
  final String label;           // final predicted label string
  final double confidence;      // confidence in the prediction (0..1)
  final bool isMalicious;       // boolean flag
  final Map<String, double> allScores; // map label -> probability (0..1)
  final double rawOutput;       // raw sigmoid output (0..1)
  final double threshold;       // threshold used for decision

  QRClassificationResult({
    required this.label,
    required this.confidence,
    required this.isMalicious,
    required this.allScores,
    required this.rawOutput,
    required this.threshold,
  });

  String get confidencePercentage => "${(confidence * 100).toStringAsFixed(1)}%";

  String get debugInfo => "Raw output: ${rawOutput.toStringAsFixed(4)}";

  String get thresholdInfo {
    if (isMalicious) {
      return "Sigmoid: ${rawOutput.toStringAsFixed(4)} >= ${threshold.toStringAsFixed(2)} → Malicious";
    } else {
      return "Sigmoid: ${rawOutput.toStringAsFixed(4)} < ${threshold.toStringAsFixed(2)} → Benign";
    }
  }

  String get riskLevel {
    if (confidence < 0.6) return "Low Confidence";
    if (confidence < 0.8) return "Medium Confidence";
    return "High Confidence";
  }

  // Additional helper methods
  String get maliciousPercentage => "${(allScores['malicious']! * 100).toStringAsFixed(1)}%";
  String get benignPercentage => "${(allScores['benign']! * 100).toStringAsFixed(1)}%";
  
  String get detailedSummary {
    return """
Classification Result:
• Prediction: $label (${confidencePercentage} confidence)
• Risk Level: $riskLevel
• Malicious Score: $maliciousPercentage
• Benign Score: $benignPercentage
• $thresholdInfo
    """.trim();
  }

  // Risk assessment based on both confidence and raw score
  String get riskAssessment {
    if (!isMalicious) {
      if (rawOutput < 0.2) return "Very Low Risk";
      if (rawOutput < 0.4) return "Low Risk";
      return "Medium Risk (Close to threshold)";
    } else {
      if (rawOutput > 0.8) return "Very High Risk";
      if (rawOutput > 0.6) return "High Risk";
      return "Medium Risk (Close to threshold)";
    }
  }

  // Color code for UI
  String get riskColor {
    if (!isMalicious) {
      if (rawOutput < 0.3) return "green";
      return "yellow";
    } else {
      if (rawOutput > 0.7) return "red";
      return "orange";
    }
  }

  // Convert to JSON for logging/debugging
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'confidence': confidence,
      'isMalicious': isMalicious,
      'allScores': allScores,
      'rawOutput': rawOutput,
      'threshold': threshold,
      'confidencePercentage': confidencePercentage,
      'riskLevel': riskLevel,
      'riskAssessment': riskAssessment,
      'thresholdInfo': thresholdInfo,
    };
  }

  // Create from JSON
  factory QRClassificationResult.fromJson(Map<String, dynamic> json) {
    return QRClassificationResult(
      label: json['label'],
      confidence: json['confidence'],
      isMalicious: json['isMalicious'],
      allScores: Map<String, double>.from(json['allScores']),
      rawOutput: json['rawOutput'],
      threshold: json['threshold'],
    );
  }

  @override
  String toString() {
    return 'QRClassificationResult(label: $label, confidence: $confidence, isMalicious: $isMalicious, rawOutput: $rawOutput)';
  }
}