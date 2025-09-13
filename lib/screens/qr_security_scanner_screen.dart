// File: lib/screens/qr_security_scanner_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import '../helpers/qr_tflite_helper.dart';

class QRSecurityScannerScreen extends StatefulWidget {
  const QRSecurityScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRSecurityScannerScreen> createState() => _QRSecurityScannerScreenState();
}

class _QRSecurityScannerScreenState extends State<QRSecurityScannerScreen> {
  // Static image analysis
  File? _selectedImage;
  QRClassificationResult? _result;
  bool _isLoading = false;
  String _errorMessage = '';
  final ImagePicker _picker = ImagePicker();
  
  // Real-time camera analysis
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isRealTimeMode = false;
  bool _isAnalyzing = false;
  QRClassificationResult? _realtimeResult;
  DateTime? _lastAnalysisTime;
  
  // Analysis throttling - faster due to smaller model
  static const Duration _analysisInterval = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        
        await _cameraController!.initialize();
        
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRealTimeMode ? 'Real-Time QR Scanner' : 'QR Security Scanner'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isRealTimeMode ? Icons.photo : Icons.videocam),
            onPressed: _toggleMode,
            tooltip: _isRealTimeMode ? 'Switch to Photo Mode' : 'Switch to Real-Time Mode',
          ),
        ],
      ),
      body: _isRealTimeMode ? _buildRealtimeView() : _buildStaticView(),
    );
  }

  Widget _buildStaticView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode Toggle Info
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
                  child: Text('Static Mode: Select images for detailed analysis. Tap the camera icon above for real-time scanning.'),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Model Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'CNN Model Info',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Input: 69×69 grayscale • Output: Sigmoid (0-1) • Threshold: 0.5',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Image Display Section
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
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
                          'Select a QR code image to analyze',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Loading Indicator
          if (_isLoading)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing QR code with CNN model...'),
              ],
            ),

          // Error Message
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
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
                ],
              ),
            ),

          // Results Section
          if (_result != null) _buildResultsSection(_result!),
        ],
      ),
    );
  }

  Widget _buildRealtimeView() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera Preview
        Positioned.fill(
          child: CameraPreview(_cameraController!),
        ),
        
        // Overlay for QR detection area with 69x69 aspect ratio guide
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(50),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0, // Square aspect ratio for 69x69
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _realtimeResult?.isMalicious == true 
                          ? Colors.red.withOpacity(0.8)
                          : _realtimeResult?.isMalicious == false 
                              ? Colors.green.withOpacity(0.8)
                              : Colors.white.withOpacity(0.8),
                      width: 3,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Instructions overlay
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
                  'Point camera at QR code for real-time analysis',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'CNN Model: 69×69 grayscale input',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        // Real-time results overlay
        if (_realtimeResult != null)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: _buildRealtimeResultsOverlay(_realtimeResult!),
          ),

        // Analysis indicator
        if (_isAnalyzing)
          const Positioned(
            top: 120,
            right: 16,
            child: CircularProgressIndicator(
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),

        // Control buttons
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FloatingActionButton(
                heroTag: "capture",
                onPressed: _captureAndAnalyze,
                backgroundColor: Colors.white,
                child: const Icon(Icons.camera, color: Colors.black),
              ),
              FloatingActionButton(
                heroTag: "toggle",
                onPressed: _toggleRealtimeAnalysis,
                backgroundColor: _isAnalyzing ? Colors.red : Colors.green,
                child: Icon(
                  _isAnalyzing ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRealtimeResultsOverlay(QRClassificationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: result.isMalicious 
            ? Colors.red.withOpacity(0.9) 
            : Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                result.isMalicious ? Icons.dangerous : Icons.security,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                result.isMalicious ? 'MALICIOUS' : 'BENIGN',
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
            'Confidence: ${result.confidencePercentage}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          Text(
            result.thresholdInfo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection(QRClassificationResult result) {
    final isMalicious = result.isMalicious;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Result Card
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
                'Confidence: ${result.confidencePercentage}',
                style: TextStyle(
                  fontSize: 16,
                  color: isMalicious ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
              Text(
                'Risk Level: ${result.riskLevel}',
                style: TextStyle(
                  fontSize: 14,
                  color: isMalicious ? Colors.red.shade600 : Colors.green.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                result.thresholdInfo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Technical Details Card
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
                  Icon(Icons.psychology, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'CNN Model Analysis',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTechnicalDetail('Input Size', '69×69 pixels (grayscale)'),
              _buildTechnicalDetail('Model Output', result.debugInfo),
              _buildTechnicalDetail('Classification', result.thresholdInfo),
              _buildTechnicalDetail('Architecture', 'CNN: 3 Conv Blocks + GAP + Sigmoid'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Warning/Info Message
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isMalicious ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isMalicious ? Colors.orange.shade200 : Colors.blue.shade200,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isMalicious ? Icons.warning : Icons.info,
                color: isMalicious ? Colors.orange.shade700 : Colors.blue.shade700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isMalicious
                      ? 'This QR code appears to have suspicious visual patterns detected by our CNN model. Avoid scanning it with QR code readers.'
                      : 'This QR code appears to have normal visual patterns according to our CNN model. However, always be cautious about the content it links to.',
                  style: TextStyle(
                    color: isMalicious ? Colors.orange.shade800 : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Detailed Scores (Expandable)
        ExpansionTile(
          title: const Text('Detailed Analysis'),
          children: [
            ...result.allScores.entries.map(
              (entry) => ListTile(
                title: Text(entry.key.toUpperCase()),
                subtitle: Text('Sigmoid-based probability'),
                trailing: Text(
                  '${(entry.value * 100).toStringAsFixed(2)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              title: const Text('Raw Model Output'),
              subtitle: const Text('Direct sigmoid activation value'),
              trailing: Text(
                result.rawOutput.toStringAsFixed(4),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTechnicalDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontFamily: value.contains('0.') ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _isRealTimeMode = !_isRealTimeMode;
      _errorMessage = '';
      _result = null;
      _realtimeResult = null;
      
      if (!_isRealTimeMode) {
        _isAnalyzing = false;
      }
    });
  }

  void _toggleRealtimeAnalysis() {
    setState(() {
      _isAnalyzing = !_isAnalyzing;
    });
    
    if (_isAnalyzing) {
      _startRealtimeAnalysis();
    }
  }

  void _startRealtimeAnalysis() async {
    if (!_isAnalyzing || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      // Check if enough time has passed since last analysis
      final now = DateTime.now();
      if (_lastAnalysisTime != null && 
          now.difference(_lastAnalysisTime!) < _analysisInterval) {
        // Wait a bit before next analysis
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isAnalyzing) _startRealtimeAnalysis();
        return;
      }

      _lastAnalysisTime = now;
      
      // Capture frame from camera
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Analyze the frame
      final result = await QRTFLiteHelper.classifyQRImage(File(imageFile.path));
      
      if (mounted && _isAnalyzing) {
        setState(() {
          _realtimeResult = result;
        });
      }
      
      // Clean up the temporary file
      File(imageFile.path).delete().catchError((e) => print('Error deleting temp file: $e'));
      
      // Continue analysis if still active
      if (_isAnalyzing) {
        _startRealtimeAnalysis();
      }
    } catch (e) {
      print('Real-time analysis error: $e');
      // Continue analysis despite errors, but with a longer delay
      if (_isAnalyzing) {
        await Future.delayed(const Duration(milliseconds: 1000));
        _startRealtimeAnalysis();
      }
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      setState(() {
        _selectedImage = File(imageFile.path);
        _isRealTimeMode = false;
        _isAnalyzing = false;
        _isLoading = true;
      });

      final result = await QRTFLiteHelper.classifyQRImage(_selectedImage!);
      
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error capturing and analyzing image: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _errorMessage = '';
        _result = null;
      });

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _selectedImage = File(pickedFile.path);
        _isLoading = true;
      });

      final result = await QRTFLiteHelper.classifyQRImage(_selectedImage!);

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error analyzing image: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
}