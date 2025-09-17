// File: lib/helpers/qr_detector_helper.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class QRDetectorHelper {
  /// MUCH MORE STRICT QR detection - only proceed if we're very confident
  static Future<QRDetectionResult> detectQRCode(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      
      if (image == null) {
        return QRDetectionResult(
          hasQRCode: false,
          confidence: 0.0,
          reason: "Unable to decode image",
        );
      }

      print("\n--- QR DETECTION ANALYSIS ---");
      print("Image size: ${image.width}x${image.height}");

      // Convert to grayscale for analysis
      image = img.grayscale(image);

      // STRICTER detection tests with higher requirements
      final contrastScore = _checkImageContrast(image);
      final squareScore = _detectSquareRegions(image);
      final patternScore = _checkForModularPatterns(image);
      final finderPatternScore = _detectFinderPatterns(image);
      final edgeScore = _detectQREdges(image);
      
      print("Detection scores:");
      print("  Contrast: ${(contrastScore * 100).toStringAsFixed(1)}%");
      print("  Square regions: ${(squareScore * 100).toStringAsFixed(1)}%");
      print("  Modular patterns: ${(patternScore * 100).toStringAsFixed(1)}%");
      print("  Finder patterns: ${(finderPatternScore * 100).toStringAsFixed(1)}%");
      print("  Edge patterns: ${(edgeScore * 100).toStringAsFixed(1)}%");
      
      // MUCH STRICTER weighted combination - require multiple strong indicators
      final combinedScore = (
        contrastScore * 0.20 +
        squareScore * 0.15 +
        patternScore * 0.20 +
        finderPatternScore * 0.35 + // Most important
        edgeScore * 0.10
      ).clamp(0.0, 1.0);
      
      print("Combined score: ${(combinedScore * 100).toStringAsFixed(1)}%");
      
      // BALANCED THRESHOLD - selective but not too strict
      // Require either strong patterns OR good combined score with some structure
      final hasStrongFinderPatterns = finderPatternScore > 0.3;
      final hasDecentContrast = contrastScore > 0.4;
      final hasStructure = patternScore > 0.2;
      
      // Multiple ways to qualify as QR:
      // 1. High combined score (strong overall evidence)
      // 2. Strong finder patterns + decent contrast (classic QR indicators)  
      // 3. Very high single indicator (e.g., excellent finder patterns)
      final hasQR = (combinedScore > 0.45) || // Reasonable combined score
                    (hasStrongFinderPatterns && hasDecentContrast) || // Classic QR signs
                    (finderPatternScore > 0.5) || // Very strong finder patterns alone
                    (contrastScore > 0.7 && hasStructure); // High contrast + structure
      
      final reason = _getDetailedReason(hasQR, combinedScore, {
        'contrast': contrastScore,
        'squares': squareScore,
        'patterns': patternScore,
        'finders': finderPatternScore,
        'edges': edgeScore,
      });
      
      print("Decision: ${hasQR ? 'QR DETECTED' : 'NO QR'} - $reason");
      
      return QRDetectionResult(
        hasQRCode: hasQR,
        confidence: combinedScore,
        reason: reason,
        imageSize: "${image.width}x${image.height}",
      );
    } catch (e) {
      print("QR detection error: $e");
      return QRDetectionResult(
        hasQRCode: false,
        confidence: 0.0,
        reason: "Error analyzing image: $e",
      );
    }
  }

  static String _getDetailedReason(bool hasQR, double score, Map<String, double> scores) {
    if (hasQR) {
      final strongFeatures = <String>[];
      if (scores['contrast']! > 0.7) strongFeatures.add('excellent contrast');
      else if (scores['contrast']! > 0.5) strongFeatures.add('good contrast');
      
      if (scores['finders']! > 0.6) strongFeatures.add('strong finder patterns');
      else if (scores['finders']! > 0.4) strongFeatures.add('finder patterns');
      
      if (scores['patterns']! > 0.5) strongFeatures.add('clear modular structure');
      
      if (scores['edges']! > 0.4) strongFeatures.add('defined edges');
      
      return "QR detected: ${strongFeatures.join(', ')}";
    } else {
      final problems = <String>[];
      if (scores['contrast']! < 0.5) problems.add('insufficient contrast');
      if (scores['finders']! < 0.4) problems.add('no clear finder patterns');
      if (scores['patterns']! < 0.3) problems.add('no modular structure');
      
      return "Not a QR code: ${problems.join(', ')}";
    }
  }

  /// Enhanced contrast detection for QR codes specifically
  static double _checkImageContrast(img.Image image) {
    final pixels = <int>[];
    
    // More comprehensive sampling
    final sampleSize = math.min(1000, (image.width * image.height) ~/ 20);
    final stepX = math.max(1, image.width ~/ math.sqrt(sampleSize).round());
    final stepY = math.max(1, image.height ~/ math.sqrt(sampleSize).round());
    
    for (int y = 0; y < image.height; y += stepY) {
      for (int x = 0; x < image.width; x += stepX) {
        final pixel = image.getPixel(x, y);
        pixels.add(img.getLuminance(pixel).round());
      }
    }
    
    if (pixels.length < 10) return 0.0;
    
    pixels.sort();
    
    final min = pixels.first;
    final max = pixels.last;
    final range = max - min;
    
    // QR codes need STRONG contrast
    if (range < 100) return 0.0; // Minimum contrast requirement
    
    // Calculate percentiles for better analysis
    final p10 = pixels[(pixels.length * 0.1).round()];
    final p90 = pixels[(pixels.length * 0.9).round()];
    final effectiveRange = p90 - p10;
    
    // Count truly dark and light pixels
    final threshold = (min + max) ~/ 2;
    int darkPixels = pixels.where((p) => p < threshold - 30).length;
    int lightPixels = pixels.where((p) => p > threshold + 30).length;
    
    final bimodalRatio = (darkPixels + lightPixels) / pixels.length;
    
    print("    Range: $min-$max ($range), Effective: $effectiveRange");
    print("    Dark pixels: ${darkPixels}, Light pixels: ${lightPixels}");
    print("    Bimodal ratio: ${(bimodalRatio*100).toStringAsFixed(1)}%");
    
    // QR codes should have:
    // - High range (good separation)
    // - High effective range (not just outliers)  
    // - Strong bimodal distribution (mostly black/white)
    final rangeScore = math.min(1.0, range / 180.0);
    final effectiveRangeScore = math.min(1.0, effectiveRange / 120.0);
    final bimodalScore = math.min(1.0, bimodalRatio / 0.6);
    
    return (rangeScore * 0.3 + effectiveRangeScore * 0.4 + bimodalScore * 0.3).clamp(0.0, 1.0);
  }

  /// NEW: Detect QR-specific edge patterns
  static double _detectQREdges(img.Image image) {
    // QR codes have very defined rectangular boundaries
    final edges = _detectEdges(image);
    if (edges == null) return 0.0;
    
    // Look for rectangular structures
    final rectangleScore = _findRectangularStructures(edges);
    final cornerScore = _findCornerPatterns(edges);
    
    print("    Rectangle score: ${(rectangleScore*100).toStringAsFixed(1)}%");
    print("    Corner score: ${(cornerScore*100).toStringAsFixed(1)}%");
    
    return (rectangleScore * 0.7 + cornerScore * 0.3).clamp(0.0, 1.0);
  }

  static img.Image? _detectEdges(img.Image image) {
    try {
      // Simple edge detection using gradient
      final edges = img.Image(width: image.width, height: image.height);
      
      for (int y = 1; y < image.height - 1; y++) {
        for (int x = 1; x < image.width - 1; x++) {
          final center = img.getLuminance(image.getPixel(x, y));
          final left = img.getLuminance(image.getPixel(x - 1, y));
          final right = img.getLuminance(image.getPixel(x + 1, y));
          final top = img.getLuminance(image.getPixel(x, y - 1));
          final bottom = img.getLuminance(image.getPixel(x, y + 1));
          
          final gradientX = (right - left).abs();
          final gradientY = (bottom - top).abs();
          final gradient = math.sqrt(gradientX * gradientX + gradientY * gradientY);
          
          final edgeStrength = math.min(255, gradient.round());
          edges.setPixel(x, y, img.ColorRgb8(edgeStrength, edgeStrength, edgeStrength));
        }
      }
      
      return edges;
    } catch (e) {
      return null;
    }
  }

  static double _findRectangularStructures(img.Image edges) {
    int strongHorizontalLines = 0;
    int strongVerticalLines = 0;
    int totalLines = 0;
    
    final threshold = 100; // Edge strength threshold
    
    // Check horizontal lines
    for (int y = 0; y < edges.height; y += edges.height ~/ 20) {
      totalLines++;
      int edgePixels = 0;
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        if (img.getLuminance(pixel) > threshold) {
          edgePixels++;
        }
      }
      if (edgePixels > edges.width * 0.6) {
        strongHorizontalLines++;
      }
    }
    
    // Check vertical lines
    for (int x = 0; x < edges.width; x += edges.width ~/ 20) {
      totalLines++;
      int edgePixels = 0;
      for (int y = 0; y < edges.height; y++) {
        final pixel = edges.getPixel(x, y);
        if (img.getLuminance(pixel) > threshold) {
          edgePixels++;
        }
      }
      if (edgePixels > edges.height * 0.6) {
        strongVerticalLines++;
      }
    }
    
    if (totalLines == 0) return 0.0;
    return ((strongHorizontalLines + strongVerticalLines) / totalLines).clamp(0.0, 1.0);
  }

  static double _findCornerPatterns(img.Image edges) {
    final corners = [
      {'x': 0, 'y': 0}, // Top-left
      {'x': edges.width - 20, 'y': 0}, // Top-right
      {'x': 0, 'y': edges.height - 20}, // Bottom-left
      {'x': edges.width - 20, 'y': edges.height - 20}, // Bottom-right
    ];
    
    int goodCorners = 0;
    
    for (final corner in corners) {
      final x = corner['x']!.toInt().clamp(0, edges.width - 20);
      final y = corner['y']!.toInt().clamp(0, edges.height - 20);
      
      int edgePixels = 0;
      int totalPixels = 0;
      
      // Sample corner region
      for (int dy = 0; dy < 20 && y + dy < edges.height; dy++) {
        for (int dx = 0; dx < 20 && x + dx < edges.width; dx++) {
          final pixel = edges.getPixel(x + dx, y + dy);
          totalPixels++;
          if (img.getLuminance(pixel) > 100) {
            edgePixels++;
          }
        }
      }
      
      // Good corners should have some edge pixels but not too many
      final edgeRatio = totalPixels > 0 ? edgePixels / totalPixels : 0.0;
      if (edgeRatio > 0.2 && edgeRatio < 0.8) {
        goodCorners++;
      }
    }
    
    return goodCorners / 4.0;
  }

  /// Enhanced finder pattern detection with stricter requirements
  static double _detectFinderPatterns(img.Image image) {
    final minSize = math.min(image.width, image.height);
    if (minSize < 50) return 0.0; // Too small for reliable detection
    
    // Look for the characteristic 7x7 finder pattern structure
    final patternSize = math.max(15, minSize ~/ 8);
    
    final regions = [
      // QR finder patterns are in these relative positions
      {'x': 0.05, 'y': 0.05}, // Top-left
      {'x': 0.75, 'y': 0.05}, // Top-right  
      {'x': 0.05, 'y': 0.75}, // Bottom-left
      {'x': 0.4, 'y': 0.4}, // Center (for good measure)
    ];
    
    int strongPatterns = 0;
    int totalSearches = regions.length;
    
    for (final region in regions) {
      final centerX = (image.width * region['x']!).round();
      final centerY = (image.height * region['y']!).round();
      
      final score = _analyzeFinderPatternCandidate(image, centerX, centerY, patternSize);
      print("    Region ($centerX,$centerY): ${(score*100).toStringAsFixed(1)}%");
      
      if (score > 0.6) { // Much higher threshold
        strongPatterns++;
      }
    }
    
    final ratio = strongPatterns / totalSearches;
    print("    Strong finder patterns: $strongPatterns/$totalSearches");
    
    // Bonus for having multiple patterns (real QR codes have 3)
    if (strongPatterns >= 2) {
      return math.min(1.0, ratio * 1.3);
    }
    
    return ratio;
  }

  static double _analyzeFinderPatternCandidate(img.Image image, int centerX, int centerY, int size) {
    final halfSize = size ~/ 2;
    
    if (centerX < halfSize || centerY < halfSize || 
        centerX + halfSize >= image.width || centerY + halfSize >= image.height) {
      return 0.0;
    }
    
    // Sample concentric squares to detect 1:1:3:1:1 ratio pattern
    final rings = <List<bool>>[];
    
    for (int ringSize = 2; ringSize <= halfSize; ringSize += 2) {
      final ringPixels = <bool>[];
      
      // Sample border pixels of this ring
      for (int dy = -ringSize; dy <= ringSize; dy++) {
        for (int dx = -ringSize; dx <= ringSize; dx++) {
          // Only border pixels
          if (dx.abs() == ringSize || dy.abs() == ringSize) {
            final x = centerX + dx;
            final y = centerY + dy;
            
            if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
              final pixel = image.getPixel(x, y);
              final isDark = img.getLuminance(pixel) < 128;
              ringPixels.add(isDark);
            }
          }
        }
      }
      
      rings.add(ringPixels);
    }
    
    if (rings.length < 3) return 0.0;
    
    // Analyze ring patterns - should alternate dark/light/dark
    final ringDarkRatios = rings.map((ring) {
      if (ring.isEmpty) return 0.0;
      return ring.where((isDark) => isDark).length / ring.length;
    }).toList();
    
    // Look for alternating pattern
    double patternScore = 0.0;
    for (int i = 0; i < ringDarkRatios.length - 2; i++) {
      final inner = ringDarkRatios[i];
      final middle = ringDarkRatios[i + 1];
      final outer = ringDarkRatios[i + 2];
      
      // QR finder pattern: dark center, light ring, dark border
      if (inner > 0.6 && middle < 0.4 && outer > 0.6) {
        patternScore = math.max(patternScore, 1.0);
      }
      // Or inverted
      else if (inner < 0.4 && middle > 0.6 && outer < 0.4) {
        patternScore = math.max(patternScore, 0.8);
      }
    }
    
    // Also check for high contrast in the region
    final contrastScore = _getRegionContrast(image, centerX - halfSize, centerY - halfSize, size);
    
    return (patternScore * 0.8 + contrastScore * 0.2).clamp(0.0, 1.0);
  }

  static double _getRegionContrast(img.Image image, int startX, int startY, int size) {
    final pixels = <int>[];
    
    for (int y = startY; y < startY + size && y < image.height; y++) {
      for (int x = startX; x < startX + size && x < image.width; x++) {
        if (x >= 0 && y >= 0) {
          final pixel = image.getPixel(x, y);
          pixels.add(img.getLuminance(pixel).round());
        }
      }
    }
    
    if (pixels.length < 4) return 0.0;
    
    pixels.sort();
    final range = pixels.last - pixels.first;
    return math.min(1.0, range / 200.0); // Need strong contrast
  }

  /// Keep existing pattern detection but make it stricter
  static double _detectSquareRegions(img.Image image) {
    int excellentSquares = 0;
    int goodSquares = 0;
    int totalSquares = 0;
    
    final minSize = math.min(image.width, image.height);
    final sizes = [
      (minSize * 0.08).round(),
      (minSize * 0.12).round(),
      (minSize * 0.15).round(),
    ].where((size) => size >= 10 && size <= minSize ~/ 3).toList();
    
    for (final size in sizes) {
      final stepX = math.max(size ~/ 2, image.width ~/ 10);
      final stepY = math.max(size ~/ 2, image.height ~/ 10);
      
      for (int y = 0; y <= image.height - size; y += stepY) {
        for (int x = 0; x <= image.width - size; x += stepX) {
          totalSquares++;
          
          final squareScore = _analyzeSquareRegion(image, x, y, size);
          if (squareScore > 0.8) {
            excellentSquares++;
          } else if (squareScore > 0.5) {
            goodSquares++;
          }
        }
      }
    }
    
    if (totalSquares == 0) return 0.0;
    
    // Weight excellent squares more heavily
    final score = (excellentSquares * 2 + goodSquares) / (totalSquares * 2);
    print("    Squares - Excellent: $excellentSquares, Good: $goodSquares, Total: $totalSquares");
    
    return math.min(1.0, score * 1.5);
  }

  static double _analyzeSquareRegion(img.Image image, int startX, int startY, int size) {
    final pixels = <int>[];
    
    for (int y = startY; y < startY + size && y < image.height; y++) {
      for (int x = startX; x < startX + size && x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels.add(img.getLuminance(pixel).round());
      }
    }
    
    if (pixels.length < 9) return 0.0;
    
    pixels.sort();
    final range = pixels.last - pixels.first;
    final median = pixels[pixels.length ~/ 2];
    
    // Much stricter requirements for QR modules
    if (range < 80) return 0.0; // Need good contrast
    
    // Check for bimodal distribution (most pixels should be dark or light)
    int darkCount = 0;
    int midCount = 0;
    int lightCount = 0;
    
    for (final pixel in pixels) {
      if (pixel < median - 40) darkCount++;
      else if (pixel > median + 40) lightCount++;
      else midCount++;
    }
    
    final bimodalRatio = (darkCount + lightCount) / pixels.length;
    final contrastScore = math.min(1.0, range / 150.0);
    
    // QR modules should be strongly bimodal with high contrast
    if (bimodalRatio < 0.6) return 0.3; // Weak
    if (bimodalRatio < 0.8) return 0.6; // Good
    
    return (contrastScore * 0.4 + bimodalRatio * 0.6).clamp(0.0, 1.0);
  }

  static double _checkForModularPatterns(img.Image image) {
    int strongPatternLines = 0;
    int moderatePatternLines = 0;
    int totalLines = 0;
    
    // Sample fewer lines but analyze them more thoroughly
    final verticalStep = math.max(5, image.height ~/ 12);
    for (int y = verticalStep; y < image.height - verticalStep; y += verticalStep) {
      totalLines++;
      final score = _analyzeLinePattern(image, y, true);
      if (score > 0.7) strongPatternLines++;
      else if (score > 0.4) moderatePatternLines++;
    }
    
    final horizontalStep = math.max(5, image.width ~/ 12);
    for (int x = horizontalStep; x < image.width - horizontalStep; x += horizontalStep) {
      totalLines++;
      final score = _analyzeLinePattern(image, x, false);
      if (score > 0.7) strongPatternLines++;
      else if (score > 0.4) moderatePatternLines++;
    }
    
    if (totalLines == 0) return 0.0;
    
    // Weight strong patterns much more heavily
    final score = (strongPatternLines * 2 + moderatePatternLines) / (totalLines * 2);
    print("    Pattern lines - Strong: $strongPatternLines, Moderate: $moderatePatternLines, Total: $totalLines");
    
    return score.clamp(0.0, 1.0);
  }

  static double _analyzeLinePattern(img.Image image, int position, bool isHorizontal) {
    final samples = <int>[]; // Store actual luminance values
    
    final maxLength = isHorizontal ? image.width : image.height;
    final step = math.max(1, maxLength ~/ 50); // More detailed sampling
    
    for (int i = 0; i < maxLength; i += step) {
      final x = isHorizontal ? i : position;
      final y = isHorizontal ? position : i;
      
      if (x < image.width && y < image.height) {
        final pixel = image.getPixel(x, y);
        samples.add(img.getLuminance(pixel).round());
      }
    }
    
    if (samples.length < 10) return 0.0;
    
    // Analyze the pattern more thoroughly
    final binaryPattern = samples.map((val) => val < 128).toList();
    
    // Count transitions
    int transitions = 0;
    for (int i = 1; i < binaryPattern.length; i++) {
      if (binaryPattern[i] != binaryPattern[i - 1]) {
        transitions++;
      }
    }
    
    // Analyze run lengths
    final runs = <int>[];
    int currentRunLength = 1;
    
    for (int i = 1; i < binaryPattern.length; i++) {
      if (binaryPattern[i] == binaryPattern[i - 1]) {
        currentRunLength++;
      } else {
        runs.add(currentRunLength);
        currentRunLength = 1;
      }
    }
    runs.add(currentRunLength);
    
    if (runs.length < 4) return 0.0;
    
    // QR codes have regular module patterns
    runs.sort();
    final median = runs[runs.length ~/ 2];
    
    // Check uniformity - most runs should be similar length
    final uniformRuns = runs.where((run) => (run - median).abs() <= 2).length;
    final uniformityScore = uniformRuns / runs.length;
    
    // Check transition density - should have regular transitions but not too many
    final transitionDensity = transitions / samples.length;
    double transitionScore = 0.0;
    
    if (transitionDensity >= 0.1 && transitionDensity <= 0.4) {
      transitionScore = 1.0;
    } else if (transitionDensity >= 0.05 && transitionDensity <= 0.6) {
      transitionScore = 0.5;
    }
    
    // Combine scores with strict requirements
    final finalScore = (uniformityScore * 0.6 + transitionScore * 0.4).clamp(0.0, 1.0);
    
    // Require both good uniformity AND appropriate transitions
    if (uniformityScore < 0.4 || transitionScore < 0.3) {
      return math.min(0.3, finalScore);
    }
    
    return finalScore;
  }
}

class QRDetectionResult {
  final bool hasQRCode;
  final double confidence;
  final String reason;
  final String? imageSize;

  QRDetectionResult({
    required this.hasQRCode,
    required this.confidence,
    required this.reason,
    this.imageSize,
  });

  String get confidencePercentage => "${(confidence * 100).toStringAsFixed(1)}%";
}