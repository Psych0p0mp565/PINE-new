/// Runtime configuration for the PINE pest detection app.
///
/// Separates configurable behavior from constants.
/// Enables easy tuning for different device capabilities.
library;

import 'constants.dart';

/// Application configuration.
class AppConfig {
  AppConfig({
    this.inputSize = AppConstants.inputSize,
    this.detectionThreshold = AppConstants.detectionThreshold,
    this.nmsThreshold = AppConstants.nmsThreshold,
    this.confidenceTemperature = AppConstants.confidenceTemperature,
    this.maxDetections = AppConstants.maxDetections,
    this.interpreterThreads = AppConstants.interpreterThreads,
    this.modelPath = AppConstants.modelPath,
  });

  /// Model input size (width and height).
  final int inputSize;

  /// Minimum confidence for detections.
  final double detectionThreshold;

  /// IoU threshold for NMS.
  final double nmsThreshold;

  /// Temperature scaling for box confidences (1.0 = off).
  final double confidenceTemperature;

  /// Maximum detections per inference.
  final int maxDetections;

  /// TFLite interpreter threads.
  final int interpreterThreads;

  /// Path to TFLite model asset.
  final String modelPath;

  /// Creates a config optimized for low-end devices (3GB RAM).
  factory AppConfig.lowEnd() {
    return AppConfig(
      inputSize: 640,
      interpreterThreads: 1,
      maxDetections: 30,
    );
  }

  /// Creates a config for balanced devices.
  factory AppConfig.balanced() {
    return AppConfig(
      inputSize: 640,
      interpreterThreads: 2,
      maxDetections: 50,
    );
  }
}
