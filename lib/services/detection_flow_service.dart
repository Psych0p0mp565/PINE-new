library;

import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../core/config.dart';
import '../core/service_locator.dart';
import '../core/user_facing_errors.dart';
import '../models/detection_record.dart';
import '../models/detection_result.dart';
import '../models/land.dart';
import 'camera_service.dart';
import 'database_service.dart';
import 'geo_fence_service.dart';
import 'geo_service.dart';
import 'image_storage_service.dart';
import 'inference_service.dart';

class DetectionFlowOutcome {
  const DetectionFlowOutcome.success({
    required this.imageBytes,
    required this.detectionResult,
    required this.geoLocation,
    required this.geoFenceResult,
    required this.imagePath,
  })  : errorMessage = null,
        isSuccess = true;

  const DetectionFlowOutcome.failure(this.errorMessage)
      : imageBytes = null,
        detectionResult = null,
        geoLocation = null,
        geoFenceResult = null,
        imagePath = null,
        isSuccess = false;

  final bool isSuccess;
  final Uint8List? imageBytes;
  final DetectionResult? detectionResult;
  final GeoLocationResult? geoLocation;
  final GeoFenceResult? geoFenceResult;
  final String? imagePath;
  final String? errorMessage;
}

class DetectionFlowController {
  DetectionFlowController({
    CameraService? cameraService,
    InferenceService? inferenceService,
    DatabaseService? databaseService,
    GeoService? geoService,
    GeoFenceService? geoFenceService,
    ImageStorageService? imageStorageService,
  })  : _cameraService = cameraService ??
            (ServiceLocator.instance.isRegistered<CameraService>()
                ? ServiceLocator.instance.get<CameraService>()
                : CameraService()),
        _inferenceService = inferenceService ??
            (ServiceLocator.instance.isRegistered<InferenceService>()
                ? ServiceLocator.instance.get<InferenceService>()
                : InferenceService(config: AppConfig.balanced())),
        _databaseService = databaseService ??
            (ServiceLocator.instance.isRegistered<DatabaseService>()
                ? ServiceLocator.instance.get<DatabaseService>()
                : DatabaseService()),
        _geoService = geoService ??
            (ServiceLocator.instance.isRegistered<GeoService>()
                ? ServiceLocator.instance.get<GeoService>()
                : GeoService()),
        _geoFenceService = geoFenceService ??
            (ServiceLocator.instance.isRegistered<GeoFenceService>()
                ? ServiceLocator.instance.get<GeoFenceService>()
                : GeoFenceService()),
        _imageStorageService = imageStorageService ??
            (ServiceLocator.instance.isRegistered<ImageStorageService>()
                ? ServiceLocator.instance.get<ImageStorageService>()
                : ImageStorageService());

  final CameraService _cameraService;
  final InferenceService _inferenceService;
  final DatabaseService _databaseService;
  final GeoService _geoService;
  final GeoFenceService _geoFenceService;
  final ImageStorageService _imageStorageService;

  CameraController? get cameraController => _cameraService.controller;

  Future<void> initialize() async {
    await _inferenceService.initialize();
    await _databaseService.initialize();
    await _cameraService.initialize();

    if (!await _geoService.hasPermission()) {
      await _geoService.requestPermission();
    }
  }

  Future<DetectionFlowOutcome> captureAndDetect() async {
    try {
      final Uint8List imageBytes = await _cameraService.takePicture();

      final DetectionResult result =
          await _inferenceService.runInference(imageBytes);

      final GeoLocationResult geoResult =
          await _geoService.getCurrentPosition();

      if (!geoResult.isSuccess) {
        final String message =
            geoResult.error ?? 'Unable to acquire GPS location.';
        return DetectionFlowOutcome.failure(message);
      }

      final double lat = geoResult.latitude!;
      final double lng = geoResult.longitude!;

      final List<Land> lands = await _databaseService.getAllLands();
      final GeoFenceResult fenceResult =
          _geoFenceService.findLandForPoint(lat, lng, lands);

      final String imagePath =
          await _imageStorageService.saveDetectionImage(imageBytes);

      final int bugCount = result.detections.length;
      final double avgConfidence = bugCount > 0
          ? result.detections
                  .map((Detection d) => d.confidence)
                  .reduce((double a, double b) => a + b) /
              bugCount
          : 0.0;

      await _databaseService.insertDetection(
        DetectionRecord(
          imagePath: imagePath,
          latitude: lat,
          longitude: lng,
          landId: fenceResult.landId,
          bugCount: bugCount,
          confidenceScore: avgConfidence,
          timestamp: DateTime.now(),
        ),
      );

      return DetectionFlowOutcome.success(
        imageBytes: imageBytes,
        detectionResult: result,
        geoLocation: geoResult,
        geoFenceResult: fenceResult,
        imagePath: imagePath,
      );
    } on CameraException catch (e) {
      return DetectionFlowOutcome.failure(
        'Camera error: ${e.description ?? e.code}',
      );
    } catch (e) {
      return DetectionFlowOutcome.failure(userFacingMessage(e));
    }
  }

  Future<void> dispose() async {
    await _cameraService.dispose();
    _inferenceService.dispose();
  }
}

