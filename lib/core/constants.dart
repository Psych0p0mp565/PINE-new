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
  /// Small pests (mealybugs) often score well below 0.9; 0.25–0.35 is typical.
  /// Values like 0.9 discard almost all real hits and produce false "0%" results.
  static const double detectionThreshold = 0.30;

  /// IoU threshold for Non-Max Suppression (NMS).
  /// Removes overlapping duplicate boxes. 0.45 is standard for YOLO.
  static const double nmsThreshold = 0.45;

  /// Post-hoc **temperature scaling** on each box probability before NMS/threshold.
  ///
  /// - `1.0` = no change (default).
  /// - `T < 1.0` sharpens (higher confidences).
  /// - `T > 1.0` softens.
  ///
  /// Fit **T** on a labeled validation set (e.g. via calibration tooling); do not
  /// tune arbitrarily to force “90%” without data.
  static const double confidenceTemperature = 1.0;

  /// Maximum number of detections to return per inference.
  /// Limits memory and UI overhead on low-end devices.
  static const int maxDetections = 50;

  /// Number of threads for TFLite interpreter.
  /// Limited to avoid overwhelming 3GB RAM devices.
  static const int interpreterThreads = 2;

  /// Label for unknown class index (fallback).
  static const String unknownLabel = 'Unknown';
}
