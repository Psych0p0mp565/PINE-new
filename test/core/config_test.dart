// Unit tests for AppConfig and factory constructors.

import 'package:flutter_test/flutter_test.dart';
import 'package:pine/core/config.dart';
import 'package:pine/core/constants.dart';

void main() {
  group('AppConfig', () {
    test('default constructor uses AppConstants values', () {
      final config = AppConfig();
      expect(config.inputSize, AppConstants.inputSize);
      expect(config.detectionThreshold, AppConstants.detectionThreshold);
      expect(config.nmsThreshold, AppConstants.nmsThreshold);
      expect(config.confidenceTemperature, AppConstants.confidenceTemperature);
      expect(config.maxDetections, AppConstants.maxDetections);
      expect(config.interpreterThreads, AppConstants.interpreterThreads);
      expect(config.modelPath, AppConstants.modelPath);
    });

    test('lowEnd factory sets expected values for low-end devices', () {
      final config = AppConfig.lowEnd();
      expect(config.inputSize, 640);
      expect(config.interpreterThreads, 1);
      expect(config.maxDetections, 30);
    });

    test('balanced factory sets expected values', () {
      final config = AppConfig.balanced();
      expect(config.inputSize, 640);
      expect(config.interpreterThreads, 2);
      expect(config.maxDetections, 50);
    });

    test('custom constructor overrides apply', () {
      final config = AppConfig(
        inputSize: 320,
        detectionThreshold: 0.25,
        modelPath: 'custom/model.tflite',
      );
      expect(config.inputSize, 320);
      expect(config.detectionThreshold, 0.25);
      expect(config.modelPath, 'custom/model.tflite');
    });
  });
}
