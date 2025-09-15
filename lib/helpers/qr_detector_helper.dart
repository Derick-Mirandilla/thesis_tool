// File: lib/helpers/qr_detector_helper.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class QRDetectorHelper {
  /// Improved QR code pattern detection with multiple algorithms
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

      // Convert to grayscale for analysis
      image = img.grayscale(image);
      
      // Run multiple detection algorithms
      final patternScore = _analyzeQRPatterns(image);
      final finderScore = _detectFinderPatterns(image);
      final geometryScore = _analyzeGeometry(image);
      final contrastScore = _checkContrast(image);
      final edgeScore = _analyzeEdgeStructure(image);
      
      // Weighted combination of scores
      final combinedScore = (
        patternScore * 0.25 +
        finderScore * 0.30 +
        geometryScore * 0.20 +
        contrastScore * 0.15 +
        edgeScore * 0.10
      ).clamp(0.0, 1.0);
      
      print("🔍 QR Detection Scores:");
      print("   Pattern: ${(patternScore * 100).toStringAsFixed(1)}%");
      print("   Finder: ${(finderScore * 100).toStringAsFixed(1)}%");
      print("   Geometry: ${(geometryScore * 100).toStringAsFixed(1)}%");
      print("   Contrast: ${(contrastScore * 100).toStringAsFixed(1)}%");
      print("   Edge: ${(edgeScore * 100).toStringAsFixed(1)}%");
      print("   Combined: ${(combinedScore * 100).toStringAsFixed(1)}%");
      
      // Lower threshold for better detection of partial/embedded QR codes
      final hasQR = combinedScore > 0.25; // Reduced from 0.3
      
      return QRDetectionResult(
        hasQRCode: hasQR,
        confidence: combinedScore,
        reason: _getDetectionReason(hasQR, combinedScore, patternScore, finderScore),
        imageSize: "${image.width}x${image.height}",
      );
    } catch (e) {
      return QRDetectionResult(
        hasQRCode: false,
        confidence: 0.0,
        reason: "Error analyzing image: $e",
      );
    }
  }

  /// Generate detailed detection reason
  static String _getDetectionReason(bool hasQR, double combined, double pattern, double finder) {
    if (hasQR) {
      if (combined > 0.7) return "Strong QR code patterns detected";
      if (combined > 0.5) return "QR code patterns detected";
      if (finder > 0.4) return "QR code finder patterns detected";
      return "Possible QR code detected";
    } else {
      if (combined > 0.15) return "Weak QR-like patterns but low confidence";
      if (pattern > 0.2) return "Some geometric patterns but not QR-like";
      return "No QR code patterns found";
    }
  }

  /// Enhanced pattern analysis
  static double _analyzeQRPatterns(img.Image image) {
    double score = 0.0;
    
    // Check for high contrast (QR codes are typically black and white)
    score += _checkContrast(image) * 0.3;
    
    // Check for square-like regions (finder patterns)
    score += _detectFinderPatterns(image) * 0.4;
    
    // Check for regular patterns/modules
    score += _checkModularPattern(image) * 0.3;
    
    return score.clamp(0.0, 1.0);
  }

  /// Improved finder pattern detection
  static double _detectFinderPatterns(img.Image image) {
    final width = image.width;
    final height = image.height;
    int finderLikeRegions = 0;
    int totalChecked = 0;
    
    // Multi-scale detection
    final scales = [20, 30, 40, 50];
    
    for (final scale in scales) {
      if (scale > width || scale > height) continue;
      
      // Check multiple positions with overlapping
      final stepX = math.max(1, width ~/ 10);
      final stepY = math.max(1, height ~/ 10);
      
      for (int y = 0; y <= height - scale; y += stepY) {
        for (int x = 0; x <= width - scale; x += stepX) {
          totalChecked++;
          
          if (_hasFinderPatternAt(image, x, y, scale)) {
            finderLikeRegions++;
          }
        }
      }
    }
    
    if (totalChecked == 0) return 0.0;
    
    final finderRatio = finderLikeRegions / totalChecked;
    return math.min(1.0, finderRatio * 10); // Scale up the score
  }

  /// More sophisticated finder pattern detection
  static bool _hasFinderPatternAt(img.Image image, int startX, int startY, int size) {
    try {
      // QR finder patterns have a specific 1:1:3:1:1 ratio
      final centerSize = size ~/ 3;
      final borderSize = (size - centerSize) ~/ 2;
      
      // Check outer border (should be dark)
      final outerDarkness = _calculateRegionDarkness(image, startX, startY, size, size);
      
      // Check inner white region
      final innerStart = startX + borderSize;
      final innerSize = centerSize;
      final innerBrightness = 1.0 - _calculateRegionDarkness(image, innerStart, innerStart, innerSize, innerSize);
      
      // Check center dark square
      final centerStart = innerStart + innerSize ~/ 4;
      final centerSize2 = innerSize ~/ 2;
      final centerDarkness = _calculateRegionDarkness(image, centerStart, centerStart, centerSize2, centerSize2);
      
      // Finder pattern should have dark outer, bright inner, dark center
      return outerDarkness > 0.6 && innerBrightness > 0.6 && centerDarkness > 0.6;
    } catch (e) {
      return false;
    }
  }

  /// Calculate darkness ratio of a region
  static double _calculateRegionDarkness(img.Image image, int startX, int startY, int width, int height) {
    int darkPixels = 0;
    int totalPixels = 0;
    
    final endX = math.min(startX + width, image.width);
    final endY = math.min(startY + height, image.height);
    
    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).round();
        
        totalPixels++;
        if (luminance < 128) darkPixels++;
      }
    }
    
    return totalPixels > 0 ? darkPixels / totalPixels : 0.0;
  }

  /// Analyze geometric structure
  static double _analyzeGeometry(img.Image image) {
    double score = 0.0;
    
    // Check for rectangular structures
    score += _detectRectangularStructures(image) * 0.4;
    
    // Check for square-like aspect ratios
    score += _analyzeAspectRatios(image) * 0.3;
    
    // Check for corner alignments
    score += _detectCornerAlignments(image) * 0.3;
    
    return score.clamp(0.0, 1.0);
  }

  /// Detect rectangular structures in the image
  static double _detectRectangularStructures(img.Image image) {
    // Simple edge-based rectangle detection
    int rectangularRegions = 0;
    final blockSize = math.min(image.width, image.height) ~/ 8;
    
    if (blockSize < 10) return 0.0;
    
    for (int y = 0; y <= image.height - blockSize; y += blockSize ~/ 2) {
      for (int x = 0; x <= image.width - blockSize; x += blockSize ~/ 2) {
        if (_hasRectangularEdges(image, x, y, blockSize)) {
          rectangularRegions++;
        }
      }
    }
    
    // Normalize by potential regions
    final maxRegions = ((image.width / (blockSize / 2)) * (image.height / (blockSize / 2))).round();
    return maxRegions > 0 ? (rectangularRegions / maxRegions).clamp(0.0, 1.0) : 0.0;
  }

  /// Check if a region has rectangular edges
  static bool _hasRectangularEdges(img.Image image, int startX, int startY, int size) {
    int horizontalEdges = 0;
    int verticalEdges = 0;
    
    // Check top and bottom edges
    for (int x = startX; x < startX + size && x < image.width - 1; x++) {
      // Top edge
      final topDiff = (img.getLuminance(image.getPixel(x, startY)) - 
                      img.getLuminance(image.getPixel(x, math.min(startY + 1, image.height - 1)))).abs();
      if (topDiff > 50) horizontalEdges++;
      
      // Bottom edge
      final bottomY = math.min(startY + size - 1, image.height - 1);
      final bottomDiff = (img.getLuminance(image.getPixel(x, bottomY)) - 
                         img.getLuminance(image.getPixel(x, math.max(bottomY - 1, 0)))).abs();
      if (bottomDiff > 50) horizontalEdges++;
    }
    
    // Check left and right edges
    for (int y = startY; y < startY + size && y < image.height - 1; y++) {
      // Left edge
      final leftDiff = (img.getLuminance(image.getPixel(startX, y)) - 
                       img.getLuminance(image.getPixel(math.min(startX + 1, image.width - 1), y))).abs();
      if (leftDiff > 50) verticalEdges++;
      
      // Right edge
      final rightX = math.min(startX + size - 1, image.width - 1);
      final rightDiff = (img.getLuminance(image.getPixel(rightX, y)) - 
                        img.getLuminance(image.getPixel(math.max(rightX - 1, 0), y))).abs();
      if (rightDiff > 50) verticalEdges++;
    }
    
    // Need reasonable number of edges on both dimensions
    return horizontalEdges > size * 0.3 && verticalEdges > size * 0.3;
  }

  /// Analyze aspect ratios for square-like structures
  static double _analyzeAspectRatios(img.Image image) {
    // QR codes are square, so look for square-like structures
    final aspectRatio = image.width / image.height;
    
    // Perfect square gets full score, degrade as it deviates
    if (aspectRatio >= 0.8 && aspectRatio <= 1.25) {
      return 1.0 - (aspectRatio - 1.0).abs() * 2;
    }
    
    return 0.0;
  }

  /// Detect corner alignments (simplified)
  static double _detectCornerAlignments(img.Image image) {
    // Look for patterns in corners that might indicate alignment patterns
    final corners = [
      [0, 0], // Top-left
      [image.width - 20, 0], // Top-right
      [0, image.height - 20], // Bottom-left
      [image.width - 20, image.height - 20], // Bottom-right
    ];
    
    int alignmentLikeCorners = 0;
    
    for (final corner in corners) {
      final x = corner[0].clamp(0, image.width - 10);
      final y = corner[1].clamp(0, image.height - 10);
      
      if (_hasAlignmentPattern(image, x, y, 10)) {
        alignmentLikeCorners++;
      }
    }
    
    return alignmentLikeCorners / 4.0; // Normalize by number of corners
  }

  /// Check for alignment pattern at position
  static bool _hasAlignmentPattern(img.Image image, int startX, int startY, int size) {
    // Simple check for alternating dark/light patterns
    int transitions = 0;
    bool? lastDark;
    
    // Check diagonal pattern
    for (int i = 0; i < size && startX + i < image.width && startY + i < image.height; i++) {
      final luminance = img.getLuminance(image.getPixel(startX + i, startY + i));
      final isDark = luminance < 128;
      
      if (lastDark != null && lastDark != isDark) {
        transitions++;
      }
      lastDark = isDark;
    }
    
    // Alignment patterns should have some transitions
    return transitions >= 2 && transitions <= size / 2;
  }

  /// Enhanced contrast checking
  static double _checkContrast(img.Image image) {
    final pixels = <int>[];
    final sampleSize = math.min(image.width * image.height, 10000); // Limit sample size
    final step = math.max(1, (image.width * image.height / sampleSize).ceil());
    
    int pixelIndex = 0;
    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        if (pixelIndex >= sampleSize) break;
        final pixel = image.getPixel(x, y);
        pixels.add(img.getLuminance(pixel).round());
        pixelIndex++;
      }
      if (pixelIndex >= sampleSize) break;
    }
    
    if (pixels.length < 10) return 0.0;
    
    pixels.sort();
    final q1 = pixels[pixels.length ~/ 4];
    final q3 = pixels[pixels.length * 3 ~/ 4];
    final median = pixels[pixels.length ~/ 2];
    
    // Multiple contrast measures
    final iqrContrast = (q3 - q1) / 255.0;
    final rangeContrast = (pixels.last - pixels.first) / 255.0;
    
    // Check for bimodal distribution (typical of QR codes)
    int darkCount = 0;
    int lightCount = 0;
    
    for (final pixel in pixels) {
      if (pixel < 85) darkCount++;
      else if (pixel > 170) lightCount++;
    }
    
    final bimodalScore = math.min(darkCount, lightCount) / pixels.length.toDouble();
    
    // Combined contrast score
    final combinedScore = (iqrContrast * 0.4 + rangeContrast * 0.3 + bimodalScore * 0.3);
    
    return combinedScore.clamp(0.0, 1.0);
  }

  /// Analyze edge structure for QR-like patterns
  static double _analyzeEdgeStructure(img.Image image) {
    // Count edge transitions that might indicate module structure
    int horizontalTransitions = 0;
    int verticalTransitions = 0;
    int totalHorizontalChecks = 0;
    int totalVerticalChecks = 0;
    
    // Sample horizontal lines
    for (int y = 0; y < image.height; y += math.max(1, image.height ~/ 20)) {
      bool? lastDark;
      for (int x = 0; x < image.width; x++) {
        final isDark = img.getLuminance(image.getPixel(x, y)) < 128;
        if (lastDark != null && lastDark != isDark) {
          horizontalTransitions++;
        }
        lastDark = isDark;
        totalHorizontalChecks++;
      }
    }
    
    // Sample vertical lines
    for (int x = 0; x < image.width; x += math.max(1, image.width ~/ 20)) {
      bool? lastDark;
      for (int y = 0; y < image.height; y++) {
        final isDark = img.getLuminance(image.getPixel(x, y)) < 128;
        if (lastDark != null && lastDark != isDark) {
          verticalTransitions++;
        }
        lastDark = isDark;
        totalVerticalChecks++;
      }
    }
    
    // Calculate transition rates
    final horizontalRate = totalHorizontalChecks > 0 ? horizontalTransitions / totalHorizontalChecks : 0.0;
    final verticalRate = totalVerticalChecks > 0 ? verticalTransitions / totalVerticalChecks : 0.0;
    
    // QR codes should have moderate transition rates (not too smooth, not too noisy)
    final optimalRate = 0.15; // Typical for QR modules
    final horizontalScore = 1.0 - (horizontalRate - optimalRate).abs() / optimalRate;
    final verticalScore = 1.0 - (verticalRate - optimalRate).abs() / optimalRate;
    
    return ((horizontalScore + verticalScore) / 2).clamp(0.0, 1.0);
  }

  /// Check for modular/grid-like patterns (enhanced version)
  static double _checkModularPattern(img.Image image) {
    final width = image.width;
    final height = image.height;
    
    int regularSections = 0;
    int totalSections = 0;
    
    // Check both horizontal and vertical patterns with multiple scales
    final scales = [5, 8, 12, 16];
    
    for (final scale in scales) {
      // Horizontal patterns
      for (int y = scale; y < height - scale; y += scale * 2) {
        totalSections++;
        int changes = 0;
        bool? lastState;
        
        for (int x = scale; x < width - scale; x += scale) {
          final regionDarkness = _calculateRegionDarkness(image, x, y, scale, scale);
          final isDark = regionDarkness > 0.5;
          
          if (lastState != null && lastState != isDark) {
            changes++;
          }
          lastState = isDark;
        }
        
        // Regular pattern should have moderate number of changes
        if (changes >= 2 && changes <= (width / scale) * 0.6) {
          regularSections++;
        }
      }
      
      // Vertical patterns
      for (int x = scale; x < width - scale; x += scale * 2) {
        totalSections++;
        int changes = 0;
        bool? lastState;
        
        for (int y = scale; y < height - scale; y += scale) {
          final regionDarkness = _calculateRegionDarkness(image, x, y, scale, scale);
          final isDark = regionDarkness > 0.5;
          
          if (lastState != null && lastState != isDark) {
            changes++;
          }
          lastState = isDark;
        }
        
        // Regular pattern should have moderate number of changes
        if (changes >= 2 && changes <= (height / scale) * 0.6) {
          regularSections++;
        }
      }
    }
    
    if (totalSections == 0) return 0.0;
    return (regularSections / totalSections).clamp(0.0, 1.0);
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