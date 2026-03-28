/// Application-wide constants for the PINE pest detection app.
///
/// Centralizes magic numbers and strings for maintainability
/// and academic defensibility of design decisions.
library;

/// Model and inference constants.
abstract final class AppConstants {
  AppConstants._();

  /// Path to the TFLite model in assets.
  /// Model must be exported from YOLO 11 as Float16 quantized.
  static const String modelPath = 'assets/model/best.tflite';

  /// YOLO inference input size. 640x640 balances accuracy and performance
  /// on 3GB RAM devices. Smaller objects benefit from this resolution.
  static const int inputSize = 640;

  /// Minimum confidence threshold for displaying detections.
  /// Range 0.25-0.35 recommended for small pest detection to avoid
  /// filtering out low-confidence but valid detections.
  static const double detectionThreshold = 0.30;

  /// IoU threshold for Non-Max Suppression (NMS).
  /// Removes overlapping duplicate boxes. 0.45 is standard for YOLO.
  static const double nmsThreshold = 0.45;

  /// Maximum number of detections to return per inference.
  /// Limits memory and UI overhead on low-end devices.
  static const int maxDetections = 50;

  /// Number of threads for TFLite interpreter.
  /// Limited to avoid overwhelming 3GB RAM devices.
  static const int interpreterThreads = 2;

  /// Label for unknown class index (fallback).
  static const String unknownLabel = 'Unknown';
}
