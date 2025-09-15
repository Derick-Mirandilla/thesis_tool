// File: lib/models/qr_classification_result.dart
class QRClassificationResult {
  final String label;           // final predicted label string
  final double confidence;      // distance from threshold (0..1)
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
}
