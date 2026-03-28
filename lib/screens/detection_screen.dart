/// Main detection screen for pest identification.
///
/// Supports image capture with geo-tagging and geo-fencing.
/// Overlays bounding boxes using CustomPainter.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../core/user_facing_errors.dart';
import '../models/detection_result.dart';
import '../services/detection_flow_service.dart';
import '../utils/bounding_box_painter.dart';

/// Screen for capturing images and running pest detection.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  late final DetectionFlowController _flowController;

  bool _isLoading = true;
  String? _error;
  Uint8List? _capturedImage;
  DetectionResult? _detectionResult;
  bool _isInferring = false;
  bool _outsideBoundary = false;
  String? _landName;
  double? _latitude;
  double? _longitude;
  String? _geoError;

  @override
  void initState() {
    super.initState();
    _flowController = DetectionFlowController();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _flowController.initialize();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = userFacingMessage(e);
        });
      }
    }
  }

  Future<void> _captureAndDetect() async {
    if (_isInferring) return;

    setState(() {
      _isInferring = true;
      _capturedImage = null;
      _detectionResult = null;
      _outsideBoundary = false;
      _landName = null;
      _latitude = null;
      _longitude = null;
    });

    try {
      final DetectionFlowOutcome outcome =
          await _flowController.captureAndDetect();

      if (!outcome.isSuccess) {
        if (mounted) {
          setState(() {
            _error = outcome.errorMessage;
            _isInferring = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _capturedImage = outcome.imageBytes;
          _detectionResult = outcome.detectionResult;
          _isInferring = false;
          _outsideBoundary = !(outcome.geoFenceResult?.isInside ?? false);
          _landName = outcome.geoFenceResult?.land?.landName;
          _latitude = outcome.geoLocation?.latitude;
          _longitude = outcome.geoLocation?.longitude;
          _geoError = outcome.geoLocation?.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInferring = false;
        });
      }
    }
  }

  void _clearResult() {
    setState(() {
      _capturedImage = null;
      _detectionResult = null;
      _outsideBoundary = false;
      _landName = null;
      _latitude = null;
      _longitude = null;
      _geoError = null;
    });
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing camera and model...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PINE - Pest Detection')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PINE - Pest Detection'),
        actions: [
          if (_capturedImage != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearResult,
              tooltip: 'Clear result',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _capturedImage != null
                ? _buildResultView()
                : _buildCameraPreview(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hide the live preview while inferring to reduce frame pressure.
        // This prevents buffer queue spam on some devices.
        if (_flowController.cameraController != null && !_isInferring)
          CameraPreview(_flowController.cameraController!),
        if (_isInferring)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Detecting pests...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultView() {
    if (_capturedImage == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<Size>(
          future: _getImageSize(_capturedImage!),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final imageSize = snapshot.data!;
            final displaySize = _fitSize(imageSize, constraints.biggest);
            final detections = _scaleDetections(
              _detectionResult?.detections ?? [],
              imageSize,
              displaySize,
            );

            return SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: displaySize.width,
                      height: displaySize.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            _capturedImage!,
                            fit: BoxFit.contain,
                            width: displaySize.width,
                            height: displaySize.height,
                          ),
                          CustomPaint(
                            size: displaySize,
                            painter: BoundingBoxPainter(
                              detections: detections,
                              imageSize: displaySize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_detectionResult?.inferenceTimeMs != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inference: ${_detectionResult!.inferenceTimeMs!.toStringAsFixed(0)} ms | '
                              'Detections: ${_detectionResult!.detections.length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_latitude != null && _longitude != null)
                              Text(
                                'GPS: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (_landName != null)
                              Text(
                                'Land: $_landName',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (_geoError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'GPS: $_geoError',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (_outsideBoundary)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber,
                                          color: Colors.orange.shade800),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Detection outside any defined land boundary',
                                          style: TextStyle(
                                            color: Colors.orange.shade900,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Size> _getImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
  }

  Size _fitSize(Size imageSize, Size maxSize) {
    final scale = (maxSize.width / imageSize.width)
        .clamp(0.0, maxSize.height / imageSize.height);
    return Size(
      imageSize.width * scale,
      imageSize.height * scale,
    );
  }

  List<Detection> _scaleDetections(
    List<Detection> detections,
    Size originalSize,
    Size displaySize,
  ) {
    final scaleX = displaySize.width / originalSize.width;
    final scaleY = displaySize.height / originalSize.height;

    return detections.map((d) {
      return Detection(
        left: d.left * scaleX,
        top: d.top * scaleY,
        width: d.width * scaleX,
        height: d.height * scaleY,
        confidence: d.confidence,
        classIndex: d.classIndex,
        label: d.label,
      );
    }).toList();
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isInferring ? null : _captureAndDetect,
            icon: _isInferring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(
                _capturedImage != null ? 'Capture again' : 'Capture & Detect'),
          ),
        ),
      ),
    );
  }
}
