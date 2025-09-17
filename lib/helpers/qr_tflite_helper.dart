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
  
  // Model specifications - adjust these based on your actual model
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
      
      // Validate model architecture
      if (inputShape.length != 4) {
        throw Exception("Expected 4D input tensor, got ${inputShape.length}D");
      }
      
      _isInitialized = true;
      print("Model loaded successfully");
      
    } catch (e) {
      print("Model initialization failed: $e");
      throw Exception("Model initialization failed: $e");
    }
  }

  /// Classify QR code from bytes - now with proper QR validation
  static Future<QRSecurityResult> classifyQRFromBytes(
    Uint8List imageBytes, {
    String? qrContent,
  }) async {
    if (!_isInitialized) {
      throw Exception("Model not initialized. Call init() first.");
    }

    try {
      print('Processing image bytes: ${imageBytes.length} bytes');
      
      // Decode the image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception("Unable to decode image");
      }

      print('Image decoded: ${image.width}x${image.height}');

      // Check if this is likely a QR code image first
      if (!_hasQRLikeFeatures(image)) {
        print('No QR-like features detected in image');
        return QRSecurityResult(
          hasQRCode: false,
          classificationResult: null,
          qrContent: qrContent,
        );
      }

      // Preprocess for the model
      final input = await _preprocessQRImage(image);
      
      // Run inference
      final outputShape = _interpreter.getOutputTensor(0).shape;
      final output = List.generate(
        outputShape[0], 
        (i) => List.filled(outputShape[1], 0.0)
      );
      
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

  /// Check if image has QR-like visual features before processing
  static bool _hasQRLikeFeatures(img.Image image) {
    try {
      // Convert to grayscale for analysis
      final grayImage = img.grayscale(image);
      
      // Calculate basic statistics
      final stats = _calculateImageStats(grayImage);
      
      // Check for high contrast (QR codes have very black and white pixels)
      final contrastRatio = _calculateContrastRatio(grayImage, stats);
      print('Contrast ratio: $contrastRatio');
      
      // QR codes typically have high contrast
      if (contrastRatio < 0.3) {
        print('Low contrast - unlikely to be QR code');
        return false;
      }
      
      // Check for square-like high contrast regions (finder patterns)
      final hasFinderPatterns = _detectFinderPatterns(grayImage, stats);
      print('Has finder patterns: $hasFinderPatterns');
      
      // Check for regular patterns typical of QR codes
      final hasRegularPatterns = _detectRegularPatterns(grayImage);
      print('Has regular patterns: $hasRegularPatterns');
      
      // Must have either finder patterns OR regular patterns + high contrast
      return hasFinderPatterns || (hasRegularPatterns && contrastRatio > 0.5);
      
    } catch (e) {
      print('QR feature detection failed: $e');
      // If detection fails, assume it might be a QR code
      return true;
    }
  }

  /// Calculate image statistics for analysis
  static Map<String, double> _calculateImageStats(img.Image image) {
    final histogram = List.filled(256, 0);
    double sum = 0;
    int totalPixels = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final luminance = img.getLuminance(image.getPixel(x, y)).round();
        histogram[luminance]++;
        sum += luminance;
        totalPixels++;
      }
    }
    
    final mean = sum / totalPixels;
    final otsuThreshold = _calculateOtsuThreshold(histogram, totalPixels).toDouble();
    
    return {
      'mean': mean,
      'otsuThreshold': otsuThreshold,
      'histogram': 0.0, // Placeholder for histogram data
    };
  }

  /// Calculate contrast ratio in the image
  static double _calculateContrastRatio(img.Image image, Map<String, double> stats) {
    final threshold = stats['otsuThreshold']!.round();
    int darkPixels = 0;
    int lightPixels = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final luminance = img.getLuminance(image.getPixel(x, y)).round();
        if (luminance < threshold) {
          darkPixels++;
        } else {
          lightPixels++;
        }
      }
    }
    
    final totalPixels = image.width * image.height;
    final darkRatio = darkPixels / totalPixels;
    final lightRatio = lightPixels / totalPixels;
    
    // High contrast means significant amount of both dark and light pixels
    return math.min(darkRatio, lightRatio) * 2; // Scale to [0, 1]
  }

  /// Detect QR finder patterns (corner squares)
  static bool _detectFinderPatterns(img.Image image, Map<String, double> stats) {
    final threshold = stats['otsuThreshold']!.round();
    const int minPatternSize = 7; // Minimum size for a finder pattern
    const int maxPatternSize = 50; // Maximum reasonable size
    
    // Look for square patterns in corners and center
    final regions = [
      {'x': 0, 'y': 0, 'w': image.width ~/ 3, 'h': image.height ~/ 3}, // Top-left
      {'x': 2 * image.width ~/ 3, 'y': 0, 'w': image.width ~/ 3, 'h': image.height ~/ 3}, // Top-right
      {'x': 0, 'y': 2 * image.height ~/ 3, 'w': image.width ~/ 3, 'h': image.height ~/ 3}, // Bottom-left
    ];
    
    int patternsFound = 0;
    
    for (final region in regions) {
      if (_findSquarePatternInRegion(image, threshold, 
          region['x']!, region['y']!, region['w']!, region['h']!, 
          minPatternSize, maxPatternSize)) {
        patternsFound++;
      }
    }
    
    // Need at least 2 out of 3 corner patterns
    return patternsFound >= 2;
  }

  /// Find square patterns in a specific region
  static bool _findSquarePatternInRegion(img.Image image, int threshold, 
      int regionX, int regionY, int regionW, int regionH,
      int minSize, int maxSize) {
    
    for (int size = minSize; size <= maxSize; size += 2) {
      for (int y = regionY; y <= regionY + regionH - size; y += 3) {
        for (int x = regionX; x <= regionX + regionW - size; x += 3) {
          if (_isSquarePattern(image, x, y, size, threshold)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Check if a specific area matches a square pattern (dark border, light inside, dark center)
  static bool _isSquarePattern(img.Image image, int startX, int startY, int size, int threshold) {
    try {
      final centerSize = size ~/ 3;
      final centerOffset = (size - centerSize) ~/ 2;
      
      int darkBorderPixels = 0;
      int totalBorderPixels = 0;
      int darkCenterPixels = 0;
      int totalCenterPixels = 0;
      
      // Check border (should be mostly dark)
      for (int y = startY; y < startY + size; y++) {
        for (int x = startX; x < startX + size; x++) {
          if (x >= image.width || y >= image.height) continue;
          
          // Border pixels (outer ring)
          if (x == startX || x == startX + size - 1 || 
              y == startY || y == startY + size - 1) {
            final luminance = img.getLuminance(image.getPixel(x, y)).round();
            if (luminance < threshold) darkBorderPixels++;
            totalBorderPixels++;
          }
          
          // Center pixels
          if (x >= startX + centerOffset && x < startX + centerOffset + centerSize &&
              y >= startY + centerOffset && y < startY + centerOffset + centerSize) {
            final luminance = img.getLuminance(image.getPixel(x, y)).round();
            if (luminance < threshold) darkCenterPixels++;
            totalCenterPixels++;
          }
        }
      }
      
      // Pattern should have dark border (>70%) and dark center (>50%)
      final darkBorderRatio = totalBorderPixels > 0 ? darkBorderPixels / totalBorderPixels : 0;
      final darkCenterRatio = totalCenterPixels > 0 ? darkCenterPixels / totalCenterPixels : 0;
      
      return darkBorderRatio > 0.7 && darkCenterRatio > 0.5;
      
    } catch (e) {
      return false;
    }
  }

  /// Detect regular patterns typical of QR codes
  static bool _detectRegularPatterns(img.Image image) {
    try {
      // Subsample the image for pattern detection
      const int sampleStep = 4;
      final samples = <int>[];
      
      for (int y = 0; y < image.height; y += sampleStep) {
        for (int x = 0; x < image.width; x += sampleStep) {
          final luminance = img.getLuminance(image.getPixel(x, y)).round();
          samples.add(luminance > 127 ? 1 : 0); // Binarize
        }
      }
      
      // Look for alternating patterns (typical in QR codes)
      int alternations = 0;
      for (int i = 1; i < samples.length; i++) {
        if (samples[i] != samples[i-1]) {
          alternations++;
        }
      }
      
      final alternationRatio = alternations / samples.length;
      
      // QR codes typically have many alternating patterns
      return alternationRatio > 0.3;
      
    } catch (e) {
      return false;
    }
  }

  /// Improved preprocessing that only runs on verified QR images
  static Future<List<List<List<List<double>>>>> _preprocessQRImage(img.Image image) async {
    try {
      print("Preprocessing verified QR image: ${image.width}x${image.height}");

      // Convert to grayscale
      image = img.grayscale(image);

      // Extract QR region more accurately
      image = _extractQRRegionImproved(image);
      print("After QR extraction: ${image.width}x${image.height}");

      // Resize to model input size
      final inputShape = _interpreter.getInputTensor(0).shape;
      final targetWidth = inputShape[2];
      final targetHeight = inputShape[1];
      
      image = img.copyResize(
        image, 
        width: targetWidth, 
        height: targetHeight,
        interpolation: img.Interpolation.cubic,
      );
      
      // Enhanced QR preprocessing
      image = _enhanceQRImage(image);

      // Create input tensor with correct dimensions
      final input = List.generate(inputShape[0], (batch) => 
        List.generate(inputShape[1], (y) => 
          List.generate(inputShape[2], (x) => 
            List.generate(inputShape[3], (c) => 0.0))));

      // Normalize to [0, 1] range
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final pixel = image.getPixel(x, y);
          final grayValue = img.getLuminance(pixel);
          // Normalize pixel value
          input[0][y][x][0] = grayValue / 255.0;
        }
      }
      
      return input;
    } catch (e) {
      throw Exception("Image preprocessing failed: $e");
    }
  }

  /// Improved QR region extraction
  static img.Image _extractQRRegionImproved(img.Image image) {
    try {
      final stats = _calculateImageStats(image);
      final threshold = stats['otsuThreshold']!.round();
      
      // Find the bounding box of the QR code
      int minX = image.width, maxX = 0;
      int minY = image.height, maxY = 0;
      bool foundContent = false;
      
      // Look for non-background pixels
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final luminance = img.getLuminance(image.getPixel(x, y)).round();
          
          // Consider both very dark and very light pixels as QR content
          if (luminance < threshold - 20 || luminance > threshold + 20) {
            minX = math.min(minX, x);
            maxX = math.max(maxX, x);
            minY = math.min(minY, y);
            maxY = math.max(maxY, y);
            foundContent = true;
          }
        }
      }
      
      if (foundContent && maxX > minX && maxY > minY) {
        // Add padding around detected region
        final padding = math.min(10, math.min(image.width, image.height) ~/ 20);
        final cropX = math.max(0, minX - padding);
        final cropY = math.max(0, minY - padding);
        final cropWidth = math.min(image.width - cropX, maxX - minX + 2 * padding);
        final cropHeight = math.min(image.height - cropY, maxY - minY + 2 * padding);
        
        if (cropWidth > 20 && cropHeight > 20) {
          print('Cropping to detected QR region: ${cropX}x$cropY, ${cropWidth}x$cropHeight');
          return img.copyCrop(image, x: cropX, y: cropY, width: cropWidth, height: cropHeight);
        }
      }
      
      // Fallback: center square crop
      final size = math.min(image.width, image.height);
      final offsetX = (image.width - size) ~/ 2;
      final offsetY = (image.height - size) ~/ 2;
      return img.copyCrop(image, x: offsetX, y: offsetY, width: size, height: size);
      
    } catch (e) {
      print('QR extraction failed, using center crop: $e');
      final size = math.min(image.width, image.height);
      final offsetX = (image.width - size) ~/ 2;
      final offsetY = (image.height - size) ~/ 2;
      return img.copyCrop(image, x: offsetX, y: offsetY, width: size, height: size);
    }
  }

  /// Enhanced QR image processing
  static img.Image _enhanceQRImage(img.Image image) {
    // Apply moderate contrast enhancement
    image = img.contrast(image, contrast: 1.1);
    
    // Apply histogram equalization for better feature visibility
    image = _applyHistogramEqualization(image);
    
    return image;
  }

  /// Apply histogram equalization
  static img.Image _applyHistogramEqualization(img.Image image) {
    // Calculate histogram
    final histogram = List.filled(256, 0);
    final totalPixels = image.width * image.height;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final luminance = img.getLuminance(image.getPixel(x, y)).round();
        histogram[luminance]++;
      }
    }
    
    // Calculate cumulative distribution function
    final cdf = List.filled(256, 0.0);
    cdf[0] = histogram[0] / totalPixels;
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + (histogram[i] / totalPixels);
    }
    
    // Apply equalization
    final result = img.Image.from(image);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final luminance = img.getLuminance(image.getPixel(x, y)).round();
        final newLuminance = (cdf[luminance] * 255).round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgb8(newLuminance, newLuminance, newLuminance));
      }
    }
    
    return result;
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

  /// Process raw model output with better threshold handling
  static QRClassificationResult _processClassificationResult(double rawOutput) {
    // Apply sigmoid if needed (depends on your model)
    final probability = _sigmoid(rawOutput);
    
    // Use dynamic threshold based on confidence
    final threshold = _calculateDynamicThreshold(probability);
    final isMalicious = probability > threshold;
    
    // Calculate confidence percentage
    final confidence = isMalicious ? probability : (1 - probability);
    final confidencePercentage = "${(confidence * 100).toStringAsFixed(1)}%";
    
    // Determine risk level
    String riskLevel;
    if (confidence > 0.9) {
      riskLevel = isMalicious ? "High Risk" : "Very Safe";
    } else if (confidence > 0.8) {
      riskLevel = isMalicious ? "Medium Risk" : "Safe";
    } else if (confidence > 0.7) {
      riskLevel = isMalicious ? "Low Risk" : "Likely Safe";
    } else {
      riskLevel = "Uncertain";
    }
    
    return QRClassificationResult(
      isMalicious: isMalicious,
      confidence: confidence,
      confidencePercentage: confidencePercentage,
      rawOutput: rawOutput,
      threshold: threshold,
      riskLevel: riskLevel,
    );
  }

  /// Calculate dynamic threshold based on model output distribution
  static double _calculateDynamicThreshold(double probability) {
    // Adjust threshold based on how confident the model is
    if (probability > 0.8 || probability < 0.2) {
      return 0.4; // Lower threshold for high confidence
    } else if (probability > 0.7 || probability < 0.3) {
      return 0.45;
    } else {
      return DEFAULT_THRESHOLD; // Standard threshold for uncertain cases
    }
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