import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'helpers/qr_tflite_helper.dart';
import 'screens/qr_security_scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QRSecurityApp());
}

class QRSecurityApp extends StatelessWidget {
  const QRSecurityApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Security Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ModelInitializationWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ModelInitializationWrapper extends StatefulWidget {
  const ModelInitializationWrapper({Key? key}) : super(key: key);

  @override
  State<ModelInitializationWrapper> createState() => _ModelInitializationWrapperState();
}

class _ModelInitializationWrapperState extends State<ModelInitializationWrapper> {
  bool _isInitializing = true;
  String? _initializationError;
  List<String> _debugInfo = [];

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _debugAssets() async {
    try {
      _debugInfo.add("=== ASSET DEBUG INFO ===");
      
      // Get the asset manifest
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      _debugInfo.add("📁 ALL AVAILABLE ASSETS:");
      manifestMap.keys.forEach((key) {
        _debugInfo.add("  - $key");
        print("  - $key");
      });
      
      _debugInfo.add("\n🔍 CHECKING OUR SPECIFIC ASSETS:");
      
      // Check for our specific assets
      final ourAssets = [
        'assets/qr_cnn_float32.tflite',
        'assets/labels.txt',
      ];
      
      for (String asset in ourAssets) {
        if (manifestMap.containsKey(asset)) {
          try {
            final data = await rootBundle.load(asset);
            _debugInfo.add("  ✅ Found: $asset (${data.lengthInBytes} bytes)");
            print("  ✅ Found: $asset (${data.lengthInBytes} bytes)");
          } catch (e) {
            _debugInfo.add("  ❌ Found in manifest but can't load: $asset - $e");
            print("  ❌ Found in manifest but can't load: $asset - $e");
          }
        } else {
          _debugInfo.add("  ❌ Missing: $asset");
          print("  ❌ Missing: $asset");
        }
      }
      
      // Try to read labels
      try {
        final labelsContent = await rootBundle.loadString('assets/labels.txt');
        _debugInfo.add("📝 Labels content: '$labelsContent'");
        print("📝 Labels content: '$labelsContent'");
      } catch (e) {
        _debugInfo.add("❌ Labels read error: $e");
        print("❌ Labels read error: $e");
      }
      
    } catch (e) {
      _debugInfo.add("❌ Asset debug failed: $e");
      print("❌ Asset debug failed: $e");
    }
  }

  Future<void> _initializeModel() async {
    try {
      // Debug assets first
      await _debugAssets();
      
      // Initialize the QR security model
      await QRTFLiteHelper.init(
        modelPath: 'assets/qr_cnn_float32.tflite',
        labelsPath: 'assets/labels.txt',
      );
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print('Failed to initialize model: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _initializationError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Initializing QR Security Model...'),
              const SizedBox(height: 8),
              const Text(
                'Loading CNN model (69×69 grayscale)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              if (_debugInfo.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Debug Info:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _debugInfo.join('\n'),
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_initializationError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('QR Security Scanner'),
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.error,
                size: 64,
                color: Colors.red.shade600,
              ),
              const SizedBox(height: 16),
              const Text(
                'Model Initialization Failed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Error Details:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _initializationError!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              if (_debugInfo.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Debug Information:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        child: SingleChildScrollView(
                          child: Text(
                            _debugInfo.join('\n'),
                            style: const TextStyle(
                              color: Colors.green,
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isInitializing = true;
                    _initializationError = null;
                    _debugInfo.clear();
                  });
                  _initializeModel();
                },
                child: const Text('Retry Initialization'),
              ),
            ],
          ),
        ),
      );
    }

    return const QRSecurityScannerScreen();
  }
}