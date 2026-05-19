import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Smart image compression utility for base64 encoding
/// Handles dimension-based resizing and quality reduction to ensure images fit within size limits
class ImageCompressionUtils {
  // Maximum base64 string length (approximately 150KB actual size)
  static const int maxBase64Length = 200000;

  // Minimum allowed image dimensions (pixels)
  static const int minDimension = 50;

  // Maximum allowed image dimensions before auto-resize (pixels)
  static const int maxDimension = 2000;

  /// Compress image with fallback for unsupported platforms
  static Future<Uint8List?> _compressImageSafely(
    String path,
    int minWidth,
    int minHeight,
    int quality,
  ) async {
    try {
      // Try flutter_image_compress first (works on Android/iOS)
      return await FlutterImageCompress.compressWithFile(
        path,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
      );
    } catch (e) {
      debugPrint('[ImageCompression] FlutterImageCompress failed: $e, using fallback');

      // Fallback: Use image package for desktop/web platforms
      try {
        final imageFile = File(path);
        final imageBytes = await imageFile.readAsBytes();
        final decodedImage = img.decodeImage(imageBytes);

        if (decodedImage == null) return null;

        // Resize image if needed
        img.Image resized = decodedImage;
        if (decodedImage.width > minWidth || decodedImage.height > minHeight) {
          resized = img.copyResize(
            decodedImage,
            width: minWidth,
            height: minHeight,
          );
        }

        // Encode to JPEG with quality setting
        final compressed = img.encodeJpg(resized, quality: quality);
        return Uint8List.fromList(compressed);
      } catch (fallbackError) {
        debugPrint('[ImageCompression] Fallback compression also failed: $fallbackError');
        return null;
      }
    }
  }
  /// Smart compress image with dimension-based resizing
  /// Returns base64 encoded string of compressed image
  /// Throws exception if image cannot be compressed to acceptable size
  static Future<String> smartCompressImage(File imageFile) async {
    try {
      // First, get image dimensions to validate
      final imageData = await imageFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(imageData);

      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      int width = decodedImage.width;
      int height = decodedImage.height;

      debugPrint('[ImageCompression] Original dimensions: $width x $height');

      // Validate minimum dimensions
      if (width < minDimension || height < minDimension) {
        throw Exception('Image too small. Minimum size is ${minDimension}x${minDimension}px');
      }

      // Start compression with quality reduction
      int quality = 50;
      int targetWidth = width;
      int targetHeight = height;
      String? base64Result;

      // Phase 1: Try quality reduction first
      while (quality >= 10) {
        final compressed = await _compressImageSafely(
          imageFile.absolute.path,
          targetWidth,
          targetHeight,
          quality,
        );

        if (compressed != null) {
          base64Result = base64Encode(compressed);
          debugPrint('[ImageCompression] Quality $quality: ${base64Result.length} chars');

          if (base64Result.length <= maxBase64Length) {
            debugPrint('[ImageCompression] ✓ Success at quality $quality');
            return base64Result;
          }
        }

        quality -= 10;
      }

      // Phase 2: If quality reduction alone isn't enough, reduce dimensions
      debugPrint('[ImageCompression] Quality reduction insufficient, attempting dimension reduction');

      quality = 50;
      int maxResizeIterations = 0;

      while (targetWidth > minDimension && targetHeight > minDimension && maxResizeIterations < 5) {
        // Reduce dimensions by 20% each iteration
        targetWidth = (targetWidth * 0.8).toInt();
        targetHeight = (targetHeight * 0.8).toInt();
        maxResizeIterations++;

        quality = 50;
        while (quality >= 10) {
          final compressed = await _compressImageSafely(
            imageFile.absolute.path,
            targetWidth,
            targetHeight,
            quality,
          );

          if (compressed != null) {
            base64Result = base64Encode(compressed);
            debugPrint('[ImageCompression] Resize iteration $maxResizeIterations, Quality $quality: ${base64Result.length} chars');

            if (base64Result.length <= maxBase64Length) {
              debugPrint('[ImageCompression] ✓ Success at $targetWidth x $targetHeight, quality $quality');
              return base64Result;
            }
          }

          quality -= 10;
        }
      }

      // Phase 3: Last resort - use uncompressed but resized
      debugPrint('[ImageCompression] Attempting fallback: direct base64 of compressed file');
      final lastAttempt = await _compressImageSafely(
        imageFile.absolute.path,
        minDimension,
        minDimension,
        10,
      );

      if (lastAttempt != null) {
        base64Result = base64Encode(lastAttempt);
        if (base64Result.length <= maxBase64Length) {
          debugPrint('[ImageCompression] ✓ Success with minimum settings');
          return base64Result;
        }
      }

      // If we still can't fit it, throw error
      throw Exception(
        'Image cannot be compressed to acceptable size. '
        'Try using a smaller image or different image format.'
      );
    } catch (e) {
      debugPrint('[ImageCompression] Error: $e');
      rethrow;
    }
  }

  /// Validate image dimensions
  /// Returns error message if validation fails, null if valid
  static Future<String?> validateImageDimensions(File imageFile) async {
    try {
      final imageData = await imageFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(imageData);

      if (decodedImage == null) {
        return 'Failed to read image. Please try a different image.';
      }

      final width = decodedImage.width;
      final height = decodedImage.height;

      if (width < minDimension || height < minDimension) {
        return 'Image is too small ($width x $height). Minimum size is ${minDimension}x${minDimension}px.';
      }

      return null; // Valid
    } catch (e) {
      return 'Error validating image: $e';
    }
  }
}
