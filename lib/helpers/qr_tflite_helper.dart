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
  
  // Model specifications based on your research paper
  static const int INPUT_SIZE = 69;
  static const int NUM_CHANNELS = 1;
  static const double DEFAULT_THRESHOLD = 0.5;
  
  // Enhanced debugging
  static bool _debugMode = true;
  static int _predictionCount = 0;
  
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
      
      // Validate expected dimensions
      if (inputShape.length != 4 || 
          inputShape[1] != INPUT_SIZE || 
          inputShape[2] != INPUT_SIZE || 
          inputShape[3] != NUM_CHANNELS) {
        print("WARNING: Model input shape $inputShape doesn't match expected [1, $INPUT_SIZE, $INPUT_SIZE, $NUM_CHANNELS]");
      }
      
      // Run multiple test predictions to verify model variability
      await _runVariabilityTest();
      
      _isInitialized = true;
      print("Model loaded and validated successfully");
      
    } catch (e) {
      print("Model initialization failed: $e");
      throw Exception("Model initialization failed: $e");
    }
  }

  /// Test model with different inputs to verify it produces different outputs
  static Future<void> _runVariabilityTest() async {
    print("=== Model Variability Test ===");
    
    final inputShape = _interpreter.getInputTensor(0).shape;
    final outputShape = _interpreter.getOutputTensor(0).shape;
    
    // Test with different patterns
    final testInputs = [
      _createTestInput(0.0),    // All black
      _createTestInput(1.0),    // All white
      _createTestInput(0.5),    // All gray
      _createRandomInput(),     // Random pattern
      _createQRLikeInput(),     // QR-like pattern
    ];
    
    final outputs = <double>[];
    
    for (int i = 0; i < testInputs.length; i++) {
      final output = List.generate(outputShape[0], (j) => List.filled(outputShape[1], 0.0));
      _interpreter.run(testInputs[i], output);
      final rawOutput = output[0][0] as double;
      outputs.add(rawOutput);
      print("Test $i output: $rawOutput (sigmoid: ${_sigmoid(rawOutput).toStringAsFixed(4)})");
    }
    
    // Check for variability
    final minOutput = outputs.reduce(math.min);
    final maxOutput = outputs.reduce(math.max);
    final range = maxOutput - minOutput;
    
    print("Output range: $range (min: $minOutput, max: $maxOutput)");
    
    if (range < 0.01) {
      print("WARNING: Model shows very low variability - may be stuck or improperly loaded");
    } else {
      print("✓ Model shows good variability");
    }
    print("=== End Variability Test ===");
  }

  static List<List<List<List<double>>>> _createTestInput(double value) {
    return List.generate(1, (batch) => 
      List.generate(INPUT_SIZE, (y) => 
        List.generate(INPUT_SIZE, (x) => 
          List.generate(NUM_CHANNELS, (c) => value))));
  }

  static List<List<List<List<double>>>> _createRandomInput() {
    final random = math.Random();
    return List.generate(1, (batch) => 
      List.generate(INPUT_SIZE, (y) => 
        List.generate(INPUT_SIZE, (x) => 
          List.generate(NUM_CHANNELS, (c) => random.nextDouble()))));
  }

  static List<List<List<List<double>>>> _createQRLikeInput() {
    return List.generate(1, (batch) => 
      List.generate(INPUT_SIZE, (y) => 
        List.generate(INPUT_SIZE, (x) => 
          List.generate(NUM_CHANNELS, (c) => 
            (x + y) % 8 < 4 ? 0.0 : 1.0)))); // Checkerboard pattern
  }

  /// Enhanced classification with better QR detection and preprocessing validation
  static Future<QRSecurityResult> classifyQRFromBytes(
    Uint8List imageBytes, {
    String? qrContent,
  }) async {
    if (!_isInitialized) {
      throw Exception("Model not initialized. Call init() first.");
    }

    _predictionCount++;
    
    try {
      if (_debugMode) {
        print('=== QR Classification #$_predictionCount ===');
        print('Image bytes: ${imageBytes.length}');
        print('QR Content provided: ${qrContent != null}');
      }
      
      // Decode the image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception("Unable to decode image");
      }

      if (_debugMode) {
        print('Image decoded: ${image.width}x${image.height}');
      }

      // IMPROVED: Better QR detection before model analysis
      final hasQRFeatures = await _improvedQRDetection(image);
      
      if (!hasQRFeatures && qrContent == null) {
        print('No QR features detected and no QR content provided - skipping analysis');
        return QRSecurityResult(
          hasQRCode: false,
          classificationResult: null,
          qrContent: null,
        );
      }

      if (_debugMode) {
        print('QR features detected: $hasQRFeatures');
        print('Proceeding with model analysis');
      }

      // Enhanced preprocessing with validation
      final input = await _enhancedPreprocessing(image);
      
      // Run inference
      final outputShape = _interpreter.getOutputTensor(0).shape;
      final output = List.generate(
        outputShape[0], 
        (i) => List.filled(outputShape[1], 0.0)
      );
      
      if (_debugMode) {
        print("Running inference...");
      }
      
      _interpreter.run(input, output);
      
      final rawOutput = output[0][0] as double;
      
      if (_debugMode) {
        print("Raw output: $rawOutput");
        print("Sigmoid probability: ${_sigmoid(rawOutput).toStringAsFixed(4)}");
      }
      
      // Enhanced classification processing
      final classificationResult = _enhancedClassificationProcessing(rawOutput);
      
      if (_debugMode) {
        print("Final classification: $classificationResult");
        print('=== End Classification #$_predictionCount ===');
      }
      
      return QRSecurityResult(
        hasQRCode: true,
        classificationResult: classificationResult,
        qrContent: qrContent,
      );
    } catch (e) {
      print("Classification failed: $e");
      rethrow;
    }
  }

  /// Improved QR detection using multiple visual analysis methods
  static Future<bool> _improvedQRDetection(img.Image image) async {
    if (_debugMode) {
      print('Analyzing QR features...');
    }

    // Convert to grayscale for analysis
    final grayImage = img.grayscale(image);
    
    // Multiple detection criteria
    final criteria = <String, bool>{};
    
    // 1. Check image contrast (QR codes have high contrast)
    criteria['contrast'] = _hasHighContrast(grayImage);
    
    // 2. Check for square regions (finder patterns)
    criteria['squares'] = _hasSquareRegions(grayImage);
    
    // 3. Check for regular patterns
    criteria['patterns'] = _hasRegularPatterns(grayImage);
    
    // 4. Check aspect ratio (QR codes are square-ish)
    criteria['aspect'] = _hasSquareAspect(image);
    
    if (_debugMode) {
      print('QR detection criteria: $criteria');
    }
    
    // More lenient detection - any 2 out of 4 criteria
    final passedCount = criteria.values.where((v) => v).length;
    final hasQR = passedCount >= 2;
    
    if (_debugMode) {
      print('QR detection result: $hasQR (passed $passedCount/4 criteria)');
    }
    
    return hasQR;
  }

  static bool _hasHighContrast(img.Image image) {
    final pixels = <int>[];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        pixels.add(img.getLuminance(image.getPixel(x, y)).round());
      }
    }
    
    if (pixels.isEmpty) return false;
    
    pixels.sort();
    final q1 = pixels[pixels.length ~/ 4];
    final q3 = pixels[3 * pixels.length ~/ 4];
    final iqr = q3 - q1;
    
    return iqr > 80; // High interquartile range indicates good contrast
  }

  static bool _hasSquareRegions(img.Image image) {
    // Simple edge detection to find square regions
    int edgeCount = 0;
    const threshold = 128;
    
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final center = img.getLuminance(image.getPixel(x, y)).round();
        final left = img.getLuminance(image.getPixel(x-1, y)).round();
        final right = img.getLuminance(image.getPixel(x+1, y)).round();
        final top = img.getLuminance(image.getPixel(x, y-1)).round();
        final bottom = img.getLuminance(image.getPixel(x, y+1)).round();
        
        final gradient = (center - left).abs() + (center - right).abs() + 
                        (center - top).abs() + (center - bottom).abs();
        
        if (gradient > threshold) edgeCount++;
      }
    }
    
    final edgeRatio = edgeCount / (image.width * image.height);
    return edgeRatio > 0.1; // At least 10% edges
  }

  static bool _hasRegularPatterns(img.Image image) {
    // Sample a grid and look for alternating patterns
    const step = 4;
    final samples = <int>[];
    
    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        final luminance = img.getLuminance(image.getPixel(x, y)).round();
        samples.add(luminance > 127 ? 1 : 0);
      }
    }
    
    if (samples.length < 4) return false;
    
    // Count transitions
    int transitions = 0;
    for (int i = 1; i < samples.length; i++) {
      if (samples[i] != samples[i-1]) transitions++;
    }
    
    final transitionRatio = transitions / samples.length;
    return transitionRatio > 0.2; // At least 20% transitions
  }

  static bool _hasSquareAspect(img.Image image) {
    final aspectRatio = image.width / image.height;
    return aspectRatio > 0.7 && aspectRatio < 1.3; // Roughly square
  }

  /// Enhanced preprocessing with better validation and debugging
  static Future<List<List<List<List<double>>>>> _enhancedPreprocessing(img.Image image) async {
    try {
      if (_debugMode) {
        print("Enhanced preprocessing: ${image.width}x${image.height}");
      }

      // Convert to grayscale
      image = img.grayscale(image);

      // Resize to model input size
      image = img.copyResize(
        image, 
        width: INPUT_SIZE, 
        height: INPUT_SIZE,
        interpolation: img.Interpolation.linear,
      );
      
      if (_debugMode) {
        print("Resized to: ${image.width}x${image.height}");
      }

      // Create input tensor
      final input = List.generate(1, (batch) => 
        List.generate(INPUT_SIZE, (y) => 
          List.generate(INPUT_SIZE, (x) => 
            List.generate(NUM_CHANNELS, (c) => 0.0))));

      // Fill tensor with proper normalization
      final pixelValues = <double>[];
      
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = image.getPixel(x, y);
          final grayValue = img.getLuminance(pixel);
          final normalizedValue = grayValue / 255.0;
          input[0][y][x][0] = normalizedValue;
          pixelValues.add(normalizedValue);
        }
      }
      
      // Validate preprocessing
      if (pixelValues.isNotEmpty) {
        final min = pixelValues.reduce(math.min);
        final max = pixelValues.reduce(math.max);
        final mean = pixelValues.reduce((a, b) => a + b) / pixelValues.length;
        final variance = pixelValues.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / pixelValues.length;
        
        if (_debugMode) {
          print('Preprocessing validation:');
          print('  Min: ${min.toStringAsFixed(3)}, Max: ${max.toStringAsFixed(3)}');
          print('  Mean: ${mean.toStringAsFixed(3)}, Variance: ${variance.toStringAsFixed(3)}');
        }
        
        // Check for preprocessing issues
        if (min == max) {
          print('WARNING: Uniform image - all pixels have same value!');
        }
        if (min < 0 || max > 1) {
          print('WARNING: Values outside [0,1] range!');
        }
        if (variance < 0.001) {
          print('WARNING: Very low variance - image may be too uniform');
        }
      }
      
      return input;
    } catch (e) {
      throw Exception("Enhanced preprocessing failed: $e");
    }
  }

  /// Enhanced classification processing with better threshold handling
  static QRClassificationResult _enhancedClassificationProcessing(double rawOutput) {
    if (_debugMode) {
      print("Enhanced classification processing - Raw: $rawOutput");
    }
    
    // Apply sigmoid to get probability
    final probability = _sigmoid(rawOutput);
    
    // Use standard threshold
    final threshold = DEFAULT_THRESHOLD;
    final isMalicious = probability > threshold;
    
    // Calculate proper confidence
    final confidence = isMalicious ? probability : (1 - probability);
    final confidencePercentage = "${(confidence * 100).toStringAsFixed(1)}%";
    
    // Enhanced risk level determination
    String riskLevel = _determineEnhancedRiskLevel(confidence, isMalicious, rawOutput);
    
    if (_debugMode) {
      print("Enhanced classification result:");
      print("  Probability: ${probability.toStringAsFixed(4)}");
      print("  Threshold: $threshold");
      print("  Is Malicious: $isMalicious");
      print("  Confidence: ${confidence.toStringAsFixed(4)}");
      print("  Risk Level: $riskLevel");
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

  static String _determineEnhancedRiskLevel(double confidence, bool isMalicious, double rawOutput) {
    if (isMalicious) {
      if (rawOutput > 2.0) return "Very High Risk";  // Very high logit
      if (rawOutput > 1.0) return "High Risk";       // High logit
      if (confidence > 0.7) return "Medium Risk";
      return "Low Risk";
    } else {
      if (rawOutput < -2.0) return "Very Safe";      // Very negative logit
      if (rawOutput < -1.0) return "Safe";           // Negative logit
      if (confidence > 0.7) return "Likely Safe";
      return "Uncertain";
    }
  }

  /// Apply sigmoid activation function
  static double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }

  /// Classify QR code from file
  static Future<QRSecurityResult> classifyQRImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return classifyQRFromBytes(bytes);
  }

  /// Toggle debug mode
  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  /// Get prediction statistics
  static int get predictionCount => _predictionCount;

  /// Reset prediction counter
  static void resetPredictionCount() {
    _predictionCount = 0;
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

/// Result classes remain the same
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
           'qrContent: ${qrContent != null ? '${qrContent!.length} chars' : 'null'})';
  }
}

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
           'confidence: ${confidence.toStringAsFixed(3)}, '
           'confidencePercentage: $confidencePercentage, '
           'rawOutput: ${rawOutput.toStringAsFixed(4)}, '
           'threshold: $threshold, '
           'riskLevel: $riskLevel)';
  }
}