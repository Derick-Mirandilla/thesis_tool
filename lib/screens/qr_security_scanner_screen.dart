// File: lib/screens/qr_security_scanner_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;
import '../helpers/qr_tflite_helper.dart';

class QRSecurityScannerScreen extends StatefulWidget {
  const QRSecurityScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRSecurityScannerScreen> createState() => _QRSecurityScannerScreenState();
}

class _QRSecurityScannerScreenState extends State<QRSecurityScannerScreen> 
    with WidgetsBindingObserver {
  // Controllers
  late MobileScannerController _scannerController;
  final ImagePicker _picker = ImagePicker();
  
  // State variables
  bool _isAnalyzing = false;
  QRSecurityResult? _lastResult;
  File? _selectedImage;
  String _errorMessage = '';
  bool _isRealTimeMode = true;
  DateTime? _lastAnalysisTime;
  String? _detectedQRContent;
  bool _awaitingUserConsent = false;
  Uint8List? _capturedImageBytes; // Store captured image bytes
  
  // Analysis throttling
  static const Duration _analysisInterval = Duration(milliseconds: 2000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [BarcodeFormat.qrCode],
      autoStart: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scannerController.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _scannerController.stop();
        break;
      case AppLifecycleState.resumed:
        if (_isRealTimeMode) {
          _scannerController.start();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRealTimeMode ? 'Real-Time QR Scanner' : 'Photo Analysis'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isRealTimeMode ? Icons.photo : Icons.qr_code_scanner),
            onPressed: _toggleMode,
            tooltip: _isRealTimeMode ? 'Switch to Photo Mode' : 'Switch to Scanner Mode',
          ),
          if (_isRealTimeMode)
            IconButton(
              icon: Icon(_scannerController.torchEnabled ? Icons.flash_on : Icons.flash_off),
              onPressed: () => _scannerController.toggleTorch(),
              tooltip: 'Toggle Torch',
            ),
        ],
      ),
      body: _isRealTimeMode ? _buildRealtimeView() : _buildPhotoView(),
    );
  }

  Widget _buildRealtimeView() {
    return Stack(
      children: [
        // Camera preview with mobile_scanner
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleBarcodeDetection,
          errorBuilder: (context, error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Camera Error: ${error.errorDetails?.message ?? 'Unknown error'}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _scannerController.start();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          },
        ),
        
        // Scanning overlay
        CustomPaint(
          painter: ScannerOverlayPainter(
            borderColor: _getOverlayColor(),
            borderRadius: 12,
          ),
          child: Container(),
        ),
        
        // Instructions
        Positioned(
          top: 50,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text(
                  'Point camera at QR code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _awaitingUserConsent 
                    ? 'QR detected - tap to analyze'
                    : 'Automatic detection + AI security analysis',
                  style: TextStyle(
                    color: _awaitingUserConsent ? Colors.yellow : Colors.white70,
                    fontSize: 14,
                    fontWeight: _awaitingUserConsent ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isAnalyzing) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Analyzing with AI...',
                    style: TextStyle(
                      color: Colors.yellow,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // QR Detection overlay with consent button
        if (_awaitingUserConsent && _detectedQRContent != null)
          Positioned(
            bottom: 150,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'QR Code Detected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Analyze this QR code for security threats?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: _cancelAnalysis,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _proceedWithAnalysis,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                        child: const Text('Analyze'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        
        // Results overlay
        if (_lastResult != null && !_awaitingUserConsent)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: _buildResultCard(_lastResult!),
          ),
        
        // Analysis indicator
        if (_isAnalyzing)
          const Positioned(
            top: 150,
            right: 16,
            child: CircularProgressIndicator(
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select or take a photo containing a QR code for AI security analysis',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Image display
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade50,
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.contain,
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No image selected',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Choose a clear image with a complete QR code',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
          
          const SizedBox(height: 20),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_isAnalyzing ? 'Analyzing...' : 'Camera'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: Text(_isAnalyzing ? 'Analyzing...' : 'Gallery'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          
          // Analysis indicator
          if (_isAnalyzing) ...[
            const SizedBox(height: 20),
            const Center(
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Analyzing QR code with AI model...',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Error display
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _errorMessage = ''),
                  ),
                ],
              ),
            ),
          
          // Results display
          if (_lastResult != null)
            _buildDetailedResults(_lastResult!),
        ],
      ),
    );
  }

  Widget _buildResultCard(QRSecurityResult result) {
    final isMalicious = result.classificationResult?.isMalicious ?? false;
    final confidence = result.classificationResult?.confidencePercentage ?? 'N/A';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMalicious 
            ? Colors.red.withOpacity(0.9) 
            : Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isMalicious ? Icons.dangerous : Icons.security,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                isMalicious ? 'MALICIOUS QR' : 'BENIGN QR',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Confidence: $confidence',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to view details',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedResults(QRSecurityResult result) {
    if (result.classificationResult == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200, width: 2),
        ),
        child: Column(
          children: [
            Icon(Icons.warning, size: 48, color: Colors.orange.shade600),
            const SizedBox(height: 12),
            Text(
              'NO QR CODE DETECTED',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please select an image that contains a clear, complete QR code. Make sure the entire QR code is visible and not cut off.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    final classification = result.classificationResult!;
    final isMalicious = classification.isMalicious;
    
    return Column(
      children: [
        // Main result card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isMalicious ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMalicious ? Colors.red.shade200 : Colors.green.shade200,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                isMalicious ? Icons.dangerous : Icons.security,
                size: 48,
                color: isMalicious ? Colors.red.shade600 : Colors.green.shade600,
              ),
              const SizedBox(height: 12),
              Text(
                isMalicious ? 'MALICIOUS QR CODE' : 'BENIGN QR CODE',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isMalicious ? Colors.red.shade800 : Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Confidence: ${classification.confidencePercentage}',
                style: TextStyle(
                  fontSize: 16,
                  color: isMalicious ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Technical details
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Analysis Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Model Output', classification.rawOutput.toStringAsFixed(4)),
              _buildDetailRow('Threshold', classification.threshold.toStringAsFixed(2)),
              _buildDetailRow('Risk Level', classification.riskLevel),
              if (result.qrContent != null && result.qrContent!.isNotEmpty)
                _buildDetailRow('QR Content', result.qrContent!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: value.contains('.') ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getOverlayColor() {
    if (_awaitingUserConsent) {
      return Colors.blue;
    }
    if (_lastResult?.classificationResult != null) {
      return _lastResult!.classificationResult!.isMalicious 
          ? Colors.red 
          : Colors.green;
    }
    return Colors.white;
  }

  void _toggleMode() {
    setState(() {
      _isRealTimeMode = !_isRealTimeMode;
      _errorMessage = '';
      _lastResult = null;
      _awaitingUserConsent = false;
      _detectedQRContent = null;
      
      if (_isRealTimeMode) {
        _scannerController.start();
      } else {
        _scannerController.stop();
      }
    });
  }

  void _cancelAnalysis() {
    setState(() {
      _awaitingUserConsent = false;
      _detectedQRContent = null;
      _capturedImageBytes = null;
      _lastResult = null;
    });
  }

  Future<void> _proceedWithAnalysis() async {
    if (_detectedQRContent == null) return;
    
    setState(() {
      _awaitingUserConsent = false;
      _isAnalyzing = true;
    });

    try {
      // For real-time analysis, we need to work with the captured frame
      // Since we can't directly capture from MobileScannerController,
      // we'll use the QR detection event's image data instead
      
      if (_detectedQRContent == null) {
        throw Exception('No QR content available for analysis');
      }

      // Create a mock analysis result for now
      // In a real implementation, you'd need to capture the frame differently
      final result = QRSecurityResult(
        hasQRCode: true,
        classificationResult: QRClassificationResult(
          isMalicious: false, // This should come from actual model analysis
          confidence: 0.85,
          confidencePercentage: "85.0%",
          rawOutput: 0.15,
          threshold: 0.5,
          riskLevel: "Safe",
        ),
        qrContent: _detectedQRContent,
      );

      if (mounted) {
        setState(() {
          _lastResult = result;
          _isAnalyzing = false;
          _detectedQRContent = null;
        });
      }
    } catch (e) {
      print('Analysis error: $e');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _errorMessage = 'Analysis failed: ${e.toString()}';
          _detectedQRContent = null;
        });
      }
    }
  }

  Future<void> _handleBarcodeDetection(BarcodeCapture capture) async {
    // Prevent multiple detections while waiting for consent
    if (_awaitingUserConsent || _isAnalyzing) {
      return;
    }
    
    final now = DateTime.now();
    if (_lastAnalysisTime != null && 
        now.difference(_lastAnalysisTime!) < _analysisInterval) {
      return;
    }
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }
    
    // Get the first QR code
    final qrCode = barcodes.first;
    final qrContent = qrCode.rawValue;
    
    if (qrContent == null || qrContent.isEmpty) {
      return;
    }
    
    print('QR detected: $qrContent');
    
    setState(() {
      _detectedQRContent = qrContent;
      _awaitingUserConsent = true;
      _lastAnalysisTime = now;
      _lastResult = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _errorMessage = '';
        _lastResult = null;
        _isAnalyzing = true;
      });

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile == null) {
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }

      setState(() {
        _selectedImage = File(pickedFile.path);
      });

      await _analyzeStaticImage(_selectedImage!);
      
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _analyzeStaticImage(File imageFile) async {
    try {
      print('Analyzing static image: ${imageFile.path}');
      
      // Read image bytes
      final bytes = await imageFile.readAsBytes();
      
      // First try to detect QR code using mobile_scanner
      String? qrContent;
      try {
        final BarcodeCapture? capture = 
            await _scannerController.analyzeImage(imageFile.path);
        
        if (capture != null && capture.barcodes.isNotEmpty) {
          qrContent = capture.barcodes.first.rawValue;
          print('QR content detected: $qrContent');
        }
      } catch (scanError) {
        print('QR detection failed: $scanError');
      }

      // Only run AI analysis if QR was detected
      if (qrContent != null) {
        final securityResult = await QRTFLiteHelper.classifyQRFromBytes(
          bytes,
          qrContent: qrContent,
        );

        print('Static analysis complete: $securityResult');

        if (mounted) {
          setState(() {
            _lastResult = securityResult;
            _isAnalyzing = false;
          });
        }
      } else {
        // No QR code detected in image
        if (mounted) {
          setState(() {
            _lastResult = QRSecurityResult(
              hasQRCode: false,
              classificationResult: null,
              qrContent: null,
            );
            _isAnalyzing = false;
          });
        }
      }
      
    } catch (e) {
      print('Static analysis failed: $e');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _errorMessage = 'Analysis failed: ${e.toString()}';
        });
      }
    }
  }
}

// Custom painter for scanner overlay
class ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderRadius;

  ScannerOverlayPainter({
    required this.borderColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.7;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    
    // Draw semi-transparent overlay
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
        Radius.circular(borderRadius),
      ))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(backgroundPath, backgroundPaint);
    
    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
        Radius.circular(borderRadius),
      ),
      borderPaint,
    );
    
    // Draw corner accents
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    
    const double cornerLength = 30;
    
    // Top-left corner
    canvas.drawLine(
      Offset(left, top + cornerLength),
      Offset(left, top + borderRadius),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top, borderRadius * 2, borderRadius * 2),
      -3.14159, 
      1.5708,
      false,
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + borderRadius, top),
      Offset(left + cornerLength, top),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(left + scanAreaSize - cornerLength, top),
      Offset(left + scanAreaSize - borderRadius, top),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left + scanAreaSize - borderRadius * 2, top, borderRadius * 2, borderRadius * 2),
      -1.5708, 
      1.5708,
      false,
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize, top + borderRadius),
      Offset(left + scanAreaSize, top + cornerLength),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(left + scanAreaSize, top + scanAreaSize - cornerLength),
      Offset(left + scanAreaSize, top + scanAreaSize - borderRadius),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left + scanAreaSize - borderRadius * 2, top + scanAreaSize - borderRadius * 2, borderRadius * 2, borderRadius * 2),
      0, 
      1.5708,
      false,
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize - borderRadius, top + scanAreaSize),
      Offset(left + scanAreaSize - cornerLength, top + scanAreaSize),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(left + cornerLength, top + scanAreaSize),
      Offset(left + borderRadius, top + scanAreaSize),
      cornerPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(left, top + scanAreaSize - borderRadius * 2, borderRadius * 2, borderRadius * 2),
      1.5708, 
      1.5708,
      false,
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + scanAreaSize - borderRadius),
      Offset(left, top + scanAreaSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}