// File: lib/services/qr_security_model_service.dart
import 'package:flutter/foundation.dart';
import '../helpers/qr_tflite_helper.dart';

class QRSecurityModelService {
  static bool _isInitialized = false;
  static String? _initializationError;
  
  /// Initialize the QR security model
  static Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }
    
    try {
      print("Initializing QR Security Model...");
      
      // Initialize TFLite model
      await QRTFLiteHelper.init(
        modelPath: 'assets/models/qr_security_model.tflite',
        labelsPath: 'assets/models/labels.txt',
      );
      
      _isInitialized = true;
      _initializationError = null;
      
      print("QR Security Model initialized successfully");
      return true;
      
    } catch (e) {
      _initializationError = e.toString();
      print("Failed to initialize QR Security Model: $e");
      return false;
    }
  }
  
  /// Check if model is ready to use
  static bool get isReady => _isInitialized && QRTFLiteHelper.isInitialized;
  
  /// Get initialization error if any
  static String? get initializationError => _initializationError;
  
  /// Dispose model resources
  static void dispose() {
    QRTFLiteHelper.dispose();
    _isInitialized = false;
    _initializationError = null;
  }
  
  /// Retry initialization if failed
  static Future<bool> retryInitialization() async {
    dispose();
    return await initialize();
  }
}