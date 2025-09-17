// File: lib/helpers/qr_tflite_helper.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class QRTFLiteHelper {
  static late Interpreter _interpreter;
  static List<String> _labels = [];
  static bool _isInitialized = false;
  
  // Model specifications
  static const int INPUT_SIZE = 69;
  static const int NUM_CHANNELS = 1;
  static const double DEFAULT_THRESHOLD = 0.5;
  
  static Future<void> init({
    required String modelPath,
    required String labelsPath,
  }) async {
    try {
      print("Loading model from: $modelPath");
      _interpreter = await Interpreter.fromAsset(modelPath);
      
      final labelsData = await rootBundle.loadString(labelsPath);
      _labels = labelsData.trim().split('\n').where((label) => label.isNotEmpty).toList();
      
      if (_labels.length < 2) {
        throw Exception("Labels file must contain at least 2 labels");
      }
      
      // Verify model input/output shapes
      final inputShape = _interpreter.getInputTensor(0).shape;
      final outputShape = _interpreter.getOutputTensor(0).shape;
      print("Model input shape: $inputShape");
      print("Model output shape: $outputShape");
      print("Labels: $_labels");
      
      // Check if shapes match expectations
      if (inputShape.length != 4 || 
          inputShape[1] != INPUT_SIZE || 
          inputShape[2] != INPUT_SIZE || 
          inputShape[3] != NUM_CHANNELS) {
        throw Exception("Model input shape mismatch! Expected [1,$INPUT_SIZE,$INPUT_SIZE,$NUM_CHANNELS], got $inputShape");
      }
      
      _isInitialized = true;
      print("Model loaded successfully");
      
    } catch (e) {
      print("Model initialization failed: $e");
      throw Exception("Model initialization failed: $e");
    }
  }

  /// Classify QR code from bytes (works with mobile_scanner capture)
  static Future<QRSecurityResult> classifyQRFromBytes(
    Uint8List imageBytes, {
    String? qrContent,
  }) async {
    if (!_isInitialized) {
      throw Exception("Model not initialized. Call init() first.");
    }

    try {
      // Decode the image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception("Unable to decode image");
      }

      // Preprocess for the model
      final input = await _preprocessQRImage(image);
      
      // Run inference
      final output = List.generate(1, (i) => List.filled(1, 0.0));
      
      print("Running model inference...");
      _interpreter.run(input, output);
      
      final rawOutput = output[0][0] as double;
      print("Raw model output: $rawOutput");
      
      // Process results
      final classificationResult = _processClassificationResult(rawOutput);
      
      return QRSecurityResult(
        hasQRCode: true,
        classificationResult: classificationResult,
        qrContent: qrContent,
      );
    } catch (e) {
      print("Classification failed: $e");
      throw Exception("Classification failed: $e");
    }
  }

  /// Classify QR code from file
  static Future<QRSecurityResult> classifyQRImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return classifyQRFromBytes(bytes);
  }

  /// Preprocess QR image for the model
  static Future<List<List<List<List<double>>>>> _preprocessQRImage(img.Image image) async {
    try {
      print("Original image: ${image.width}x${image.height}");

      // Step 1: Extract QR region (crop to content)
      image = _extractQRRegion(image);
      print("After extraction: ${image.width}x${image.height}");

      // Step 2: Resize to model input size
      image = img.copyResize(
        image, 
        width: INPUT_SIZE, 
        height: INPUT_SIZE,
        interpolation: img.Interpolation.cubic,
      );
      
      // Step 3: Convert to grayscale
      image = img.grayscale(image);

      // Step 4: Apply adaptive binarization for QR codes
      image = _binarizeQRCode(image);

      // Step 5: Create normalized input tensor
      final input = List.generate(1, (batch) => 
        List.generate(INPUT_SIZE, (y) => 
          List.generate(INPUT_SIZE, (x) => 
            List.generate(NUM_CHANNELS, (c) => 0.0))));

      // Normalize to [0, 1] range
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = image.getPixel(x, y);
          final grayValue = img.getLuminance(pixel);
          input[0][y][x][0] = grayValue / 255.0;
        }
      }
      
      return input;
    } catch (e) {
      throw Exception("Image preprocessing failed: $e");
    }
  }

  /// Extract QR code region from image
  static img.Image _extractQRRegion(img.Image image) {
    // Convert to grayscale for analysis
    final gray = img.grayscale(image);
    
    // Find the bounding box of high contrast areas (likely QR code)
    int minX = image.width, maxX = 0;
    int minY = image.height, maxY = 0;
    
    // Calculate adaptive threshold
    final histogram = List.filled(256, 0);
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final luminance = img.getLuminance(gray.getPixel(x, y)).round();
        histogram[luminance]++;
      }
    }
    
    // Find Otsu threshold
    final threshold = _calculateOtsuThreshold(histogram, gray.width * gray.height);
    
    // Find boundaries of QR code
    bool foundContent = false;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final luminance = img.getLuminance(gray.getPixel(x, y)).round();
        
        // Check if this pixel is part of QR pattern (high contrast)
        if ((luminance < threshold && luminance < 100) || 
            (luminance > threshold && luminance > 200)) {
          if (!foundContent) {
            minX = maxX = x;
            minY = maxY = y;
            foundContent = true;
          } else {
            minX = math.min(minX, x);
            maxX = math.max(maxX, x);
            minY = math.min(minY, y);
            maxY = math.max(maxY, y);
          }
        }
      }
    }
    
    // If no QR-like pattern found, return center crop
    if (!foundContent || (maxX - minX) < 10 || (maxY - minY) < 10) {
      final size = math.min(image.width, image.height);
      final offsetX = (image.width - size) ~/ 2;
      final offsetY = (image.height - size) ~/ 2;
      return img.copyCrop(image, 
        x: offsetX, 
        y: offsetY, 
        width: size, 
        height: size
      );
    }
    
    // Add padding around detected QR region
    const padding = 20;
    minX = math.max(0, minX - padding);
    minY = math.max(0, minY - padding);
    maxX = math.min(image.width - 1, maxX + padding);
    maxY = math.min(image.height - 1, maxY + padding);
    
    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    
    return img.copyCrop(image, 
      x: minX, 
      y: minY, 
      width: width, 
      height: height
    );
  }

  /// Calculate Otsu threshold for image binarization
  static int _calculateOtsuThreshold(List<int> histogram, int totalPixels) {
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumB = 0;
    int wB = 0;
    int wF = 0;
    double varMax = 0;
    int threshold = 0;

    for (int i = 0; i < 256; i++) {
      wB += histogram[i];
      if (wB == 0) continue;
      
      wF = totalPixels - wB;
      if (wF == 0) break;

      sumB += i * histogram[i];
      
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      
      final varBetween = wB * wF * (mB - mF) * (mB - mF);
      
      if (varBetween > varMax) {
        varMax = varBetween;
        threshold = i;
      }
    }

    return threshold;
  }

  /// Apply adaptive binarization for QR codes
  static img.Image _binarizeQRCode(img.Image image) {
    final result = img.Image.from(image);
    
    // Calculate local threshold using adaptive method
    const int blockSize = 15;
    const double c = 10; // Constant subtracted from mean
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Calculate local mean in block around pixel
        double sum = 0;
        int count = 0;
        
        final startY = math.max(0, y - blockSize ~/ 2);
        final endY = math.min(image.height - 1, y + blockSize ~/ 2);
        final startX = math.max(0, x - blockSize ~/ 2);
        final endX = math.min(image.width - 1, x + blockSize ~/ 2);
        
        for (int by = startY; by <= endY; by++) {
          for (int bx = startX; bx <= endX; bx++) {
            sum += img.getLuminance(image.getPixel(bx, by));
            count++;
          }
        }
        
        final localMean = sum / count;
        final currentPixel = img.getLuminance(image.getPixel(x, y));
        
        // Apply adaptive threshold
        final binaryValue = currentPixel > (localMean - c) ? 255 : 0;
        result.setPixel(x, y, img.ColorRgb8(binaryValue, binaryValue, binaryValue));
      }
    }
    
    return result;
  }

  /// Process raw model output into classification result
  static QRClassificationResult _processClassificationResult(double rawOutput) {
    // Apply sigmoid activation if needed (depends on your model)
    final probability = _sigmoid(rawOutput);
    
    // Determine if malicious based on threshold
    final isMalicious = probability > DEFAULT_THRESHOLD;
    
    // Calculate confidence percentage
    final confidence = isMalicious ? probability : (1 - probability);
    final confidencePercentage = "${(confidence * 100).toStringAsFixed(1)}%";
    
    // Determine risk level
    String riskLevel;
    if (confidence > 0.9) {
      riskLevel = isMalicious ? "High Risk" : "Very Safe";
    } else if (confidence > 0.7) {
      riskLevel = isMalicious ? "Medium Risk" : "Safe";
    } else if (confidence > 0.6) {
      riskLevel = isMalicious ? "Low Risk" : "Likely Safe";
    } else {
      riskLevel = "Uncertain";
    }
    
    return QRClassificationResult(
      isMalicious: isMalicious,
      confidence: confidence,
      confidencePercentage: confidencePercentage,
      rawOutput: rawOutput,
      threshold: DEFAULT_THRESHOLD,
      riskLevel: riskLevel,
    );
  }

  /// Apply sigmoid activation function
  static double _sigmoid(double x) {
    return 1 / (1 + math.exp(-x));
  }

  /// Dispose resources
  static void dispose() {
    if (_isInitialized) {
      _interpreter.close();
      _isInitialized = false;
    }
  }

  /// Check if model is initialized
  static bool get isInitialized => _isInitialized;
  
  /// Get model labels
  static List<String> get labels => List.from(_labels);
}

/// Result class for QR security analysis
class QRSecurityResult {
  final bool hasQRCode;
  final QRClassificationResult? classificationResult;
  final String? qrContent;

  QRSecurityResult({
    required this.hasQRCode,
    this.classificationResult,
    this.qrContent,
  });

  @override
  String toString() {
    return 'QRSecurityResult(hasQRCode: $hasQRCode, '
           'classificationResult: $classificationResult, '
           'qrContent: $qrContent)';
  }
}

/// Classification result with detailed metrics
class QRClassificationResult {
  final bool isMalicious;
  final double confidence;
  final String confidencePercentage;
  final double rawOutput;
  final double threshold;
  final String riskLevel;

  QRClassificationResult({
    required this.isMalicious,
    required this.confidence,
    required this.confidencePercentage,
    required this.rawOutput,
    required this.threshold,
    required this.riskLevel,
  });

  @override
  String toString() {
    return 'QRClassificationResult('
           'isMalicious: $isMalicious, '
           'confidence: $confidence, '
           'confidencePercentage: $confidencePercentage, '
           'rawOutput: $rawOutput, '
           'threshold: $threshold, '
           'riskLevel: $riskLevel)';
  }
}