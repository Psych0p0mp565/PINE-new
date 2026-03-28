/// TFLite inference service for YOLO object detection.
///
/// Runs inference in a separate isolate to avoid blocking the UI.
/// Handles preprocessing, model execution, and post-processing
/// (NMS, threshold filtering, coordinate transformation).
library;

import 'dart:typed_data';
import 'dart:math' as math;

import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/app_logger.dart';
import '../core/config.dart';
import '../models/detection_result.dart';
import '../utils/detection_coordinate_transform.dart';
import '../utils/image_preprocessor.dart';

/// Service for running YOLO TFLite inference.
///
/// Optimization decisions:
/// - Isolate-based inference to prevent UI jank
/// - Limited interpreter threads for 3GB RAM devices
/// - Float16 model for smaller size and faster inference
class InferenceService {
  InferenceService({AppConfig? config})
      : _config = config ?? AppConfig.balanced();

  final AppConfig _config;
  bool _initialized = false;

  /// Class labels from your trained model (e.g., ['mealybug', 'aphid']).
  /// Must match the order used during training.
  List<String> classLabels = ['mealybug'];

  /// Number of classes in the model. Inferred from output shape if not set.
  int? numClasses;

  /// Initializes the TFLite interpreter. Call once before inference.
  Future<void> initialize() async {
    if (_initialized) return;
    // Interpreter is loaded per-isolate in compute()
    _initialized = true;
  }

  /// Runs inference on [imageBytes] in a separate isolate.
  /// Returns [DetectionResult] with boxes in original image coordinates.
  Future<DetectionResult> runInference(Uint8List imageBytes) async {
    return _runInferenceIsolate(
      _InferenceParams(
        imageBytes: imageBytes,
        modelPath: _config.modelPath,
        inputSize: _config.inputSize,
        detectionThreshold: _config.detectionThreshold,
        nmsThreshold: _config.nmsThreshold,
        maxDetections: _config.maxDetections,
        interpreterThreads: _config.interpreterThreads,
        classLabels: List.from(classLabels),
        numClasses: numClasses,
      ),
    );
  }

  void dispose() {
    _initialized = false;
  }
}

/// Parameters passed to the inference isolate.
class _InferenceParams {
  _InferenceParams({
    required this.imageBytes,
    required this.modelPath,
    required this.inputSize,
    required this.detectionThreshold,
    required this.nmsThreshold,
    required this.maxDetections,
    required this.interpreterThreads,
    required this.classLabels,
    this.numClasses,
  });

  final Uint8List imageBytes;
  final String modelPath;
  final int inputSize;
  final double detectionThreshold;
  final double nmsThreshold;
  final int maxDetections;
  final int interpreterThreads;
  final List<String> classLabels;
  final int? numClasses;
}

/// Top-level function for isolate (must be top-level or static).
Future<DetectionResult> _runInferenceIsolate(_InferenceParams params) async {
  final stopwatch = Stopwatch()..start();

  Interpreter? interpreter;
  try {
    AppLogger.debug('Inference: Loading model from ${params.modelPath}');
    final options = InterpreterOptions()..threads = params.interpreterThreads;
    interpreter = await Interpreter.fromAsset(
      params.modelPath,
      options: options,
    );

    final inputTensors = interpreter.getInputTensors();
    final numInputs = inputTensors.length;
    AppLogger.debug(
      'Inference: Model loaded. Inputs=$numInputs Outputs=${interpreter.getOutputTensors().length}',
    );

    // YOLO TFLite exports use the image tensor at input index 0.
    // Some models may have auxiliary inputs, but the image is still 0.
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    AppLogger.debug(
      'Inference: Input shape=${inputTensor.shape} Output shape=$outputShape',
    );
    AppLogger.debug(
      'Inference: Input type=${inputTensor.type} Output type=${outputTensor.type}',
    );

    final preprocessor = ImagePreprocessor(inputSize: params.inputSize);
    final preprocessResult =
        await preprocessor.preprocessFromBytes(params.imageBytes);

    // Input: typically [1, height, width, 3] (NHWC).
    // Some exported models expect float32 normalized [0,1], others expect uint8 [0,255].
    final inputFloat = preprocessResult.input;
    // Quick sanity check: ensure input isn't all zeros.
    var maxIn = 0.0;
    var sumIn = 0.0;
    for (final v in inputFloat) {
      final dv = v.toDouble();
      sumIn += dv;
      if (dv > maxIn) maxIn = dv;
    }
    AppLogger.debug(
      'Inference: inputStats max=${maxIn.toStringAsFixed(3)} mean=${(sumIn / inputFloat.length).toStringAsFixed(3)}',
    );

    // Output: allocate buffer matching output shape
    final outputSize = outputShape.fold<int>(1, (a, b) => a * b);
    final outputBuffer = Float32List(outputSize);
    // IMPORTANT:
    // tflite_flutter writes into the structured output object passed to `run()`.
    // Using `reshape()` can produce a nested structure not backed by `outputBuffer`,
    // leaving `outputBuffer` unchanged (all zeros). For 3D outputs, allocate an
    // explicit nested List, run into it, then flatten into `outputBuffer`.
    final bool outputIs3d = outputShape.length == 3;
    final List<List<List<double>>>? output3d = outputIs3d
        ? List<List<List<double>>>.generate(
            outputShape[0],
            (_) => List<List<double>>.generate(
              outputShape[1],
              (_) => List<double>.filled(outputShape[2], 0.0),
            ),
          )
        : null;

    // Ensure tensors are allocated before running.
    interpreter.allocateTensors();

    // Run inference.
    //
    // tflite_flutter expects the input to match the tensor rank.
    // Our preprocessor returns a flat Float32List; wrap it as a 4D view
    // [1, H, W, 3] to satisfy the interpreter.
    final h = inputTensor.shape.length >= 4 ? inputTensor.shape[1] : params.inputSize;
    final w = inputTensor.shape.length >= 4 ? inputTensor.shape[2] : params.inputSize;
    final c = inputTensor.shape.length >= 4 ? inputTensor.shape[3] : 3;
    final expected = h * w * c;
    if (inputFloat.length != expected) {
      throw StateError(
        'Model expects input size $expected (H=$h W=$w C=$c) but got ${inputFloat.length}',
      );
    }
    // In tflite_flutter 0.11.0 this is TensorType (not TfLiteType).
    final TensorType inputType = inputTensor.type;
    if (inputType == TensorType.float32) {
      // Try normalized (0..1). If output looks all-zero, retry with 0..255 float.
      final input4d = inputFloat.reshape(<int>[1, h, w, c]);
      if (output3d != null) {
        interpreter.run(input4d, output3d);
        _flatten3d(output3d, outputBuffer);
      } else {
        interpreter.run(input4d, outputBuffer);
      }

      var allZero = true;
      final probe = outputBuffer.length < 64 ? outputBuffer.length : 64;
      for (var i = 0; i < probe; i++) {
        if (outputBuffer[i] != 0.0) {
          allZero = false;
          break;
        }
      }
      if (allZero) {
        AppLogger.debug(
          'Inference: output all zeros with 0..1 float input; retrying 0..255 float input',
        );
        final inputFloat255 = Float32List(expected);
        for (var i = 0; i < expected; i++) {
          inputFloat255[i] = inputFloat[i] * 255.0;
        }
        final input4d255 = inputFloat255.reshape(<int>[1, h, w, c]);
        if (output3d != null) {
          // Reset output3d to zeros before re-run (avoid mixing runs).
          for (var b = 0; b < output3d.length; b++) {
            for (var i = 0; i < output3d[b].length; i++) {
              final row = output3d[b][i];
              for (var j = 0; j < row.length; j++) {
                row[j] = 0.0;
              }
            }
          }
          interpreter.run(input4d255, output3d);
          _flatten3d(output3d, outputBuffer);
        } else {
          interpreter.run(input4d255, outputBuffer);
        }
      }
    } else if (inputType == TensorType.uint8) {
      // Convert normalized float [0,1] -> uint8 [0,255]
      final inputU8 = Uint8List(expected);
      for (var i = 0; i < expected; i++) {
        final v = (inputFloat[i] * 255.0).round();
        inputU8[i] = v.clamp(0, 255);
      }
      final input4d = inputU8.reshape(<int>[1, h, w, c]);
      if (output3d != null) {
        interpreter.run(input4d, output3d);
        _flatten3d(output3d, outputBuffer);
      } else {
        interpreter.run(input4d, outputBuffer);
      }
    } else {
      throw StateError('Unsupported input tensor type: $inputType');
    }

    // Parse YOLO output and post-process
    //
    // Our model reports output shape like [1, 300, 6] where 6 is often (4 + obj + nc).
    // Prefer using provided label count when it matches output layout.
    final int numClasses = params.numClasses ??
        _inferNumClasses(outputShape, labelCount: params.classLabels.length);
    final bool hasObjectness = _inferHasObjectness(
      outputShape,
      inferredNumClasses: numClasses,
      labelCount: params.classLabels.length,
    );
    // Special-case common "final detections" export:
    // [1, 300, 6] where each row is one detection:
    // either [x1,y1,x2,y2,score,class] or [cx,cy,w,h,score,class].
    final rawDetections = (outputShape.length == 3 && outputShape[2] == 6)
        ? _parseFinalDetections6(outputBuffer, outputShape)
        : _parseYoloOutput(outputBuffer, outputShape, numClasses, hasObjectness);

    // Print quick stats to validate model output.
    if (rawDetections.isNotEmpty) {
      final maxC = rawDetections
          .map((d) => d.confidence)
          .reduce((a, b) => a > b ? a : b);
      AppLogger.debug(
        'Inference: rawDetections=${rawDetections.length} maxConf=${(maxC * 100).toStringAsFixed(1)}%',
      );
    } else {
      AppLogger.debug(
        'Inference: rawDetections=0 (outputShape=$outputShape)',
      );
      AppLogger.debug(
        'Inference: outputSample=${outputBuffer.length >= 12 ? outputBuffer.sublist(0, 12) : outputBuffer.toList()}',
      );
    }

    final filtered = _applyNms(
      rawDetections,
      params.nmsThreshold,
      params.maxDetections,
    );
    final aboveThreshold = filtered
        .where((d) => d.confidence >= params.detectionThreshold)
        .toList();

    // Transform coordinates to original image space
    final List<Detection> displayDetections = transformModelBoxesToOriginal(
      aboveThreshold
          .map(
            (_RawDetection r) => ModelBox(
              cx: r.cx,
              cy: r.cy,
              w: r.w,
              h: r.h,
              confidence: r.confidence,
              classIndex: r.classIndex,
            ),
          )
          .toList(),
      preprocessResult,
      params.inputSize,
      params.classLabels,
    );

    stopwatch.stop();
    AppLogger.debug(
      'Inference: Done in ${stopwatch.elapsedMilliseconds}ms, '
      'detections=${displayDetections.length} (raw=${rawDetections.length}, '
      'afterNms=${filtered.length}, threshold=${params.detectionThreshold}, '
      'hasObj=$hasObjectness, numClasses=$numClasses)',
    );

    final double? maxRaw = rawDetections.isEmpty
        ? null
        : rawDetections
            .map((d) => d.confidence)
            .reduce((a, b) => a > b ? a : b);
    final sample = outputBuffer.length >= 12
        ? outputBuffer.sublist(0, 12).map((v) => v.toDouble()).toList()
        : outputBuffer.map((v) => v.toDouble()).toList();

    return DetectionResult(
      detections: displayDetections,
      inferenceTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      originalWidth: preprocessResult.originalWidth,
      originalHeight: preprocessResult.originalHeight,
      rawDetectionsCount: rawDetections.length,
      maxRawConfidence: maxRaw,
      outputShape: outputShape,
      outputSample: sample,
    );
  } catch (e, stack) {
    AppLogger.error('InferenceService', e, stack);
    rethrow;
  } finally {
    interpreter?.close();
  }
}

int _inferNumClasses(List<int> outputShape, {required int labelCount}) {
  // YOLO output is typically one of:
  // - [1, 4+nc, num_boxes]  (channels-first)
  // - [1, num_boxes, 4+nc]  (boxes-first)
  //
  // The (4/5+nc) dimension is usually "small" (<= ~256), while num_boxes is large.
  if (outputShape.length < 3) return 1;
  final dim1 = outputShape[1];
  final dim2 = outputShape[2];

  final small = dim1 < dim2 ? dim1 : dim2;
  final large = dim1 < dim2 ? dim2 : dim1;

  // If labels are known and match common layouts, trust them.
  if (labelCount > 0) {
    if (small == 5 + labelCount || small == 4 + labelCount) {
      return labelCount;
    }
    if (large == 5 + labelCount || large == 4 + labelCount) {
      return labelCount;
    }
  }

  // Prefer using the small dimension as (5+nc) or (4+nc) when it looks plausible.
  if (small > 4 && small <= 256) {
    // Try objectness layout first (5+nc) because it's common for YOLO.
    if (small - 5 >= 1) return small - 5;
    return small - 4;
  }
  if (large > 4 && large <= 256) {
    if (large - 5 >= 1) return large - 5;
    return large - 4;
  }
  // Fallback: assume dim1 is (4+nc)
  return (dim1 > 4 ? dim1 - 4 : 1);
}

bool _inferHasObjectness(
  List<int> shape, {
  required int inferredNumClasses,
  required int labelCount,
}) {
  // Many YOLO exports are (cx,cy,w,h,obj, classes...) => 5+nc.
  // Some exports omit objectness => 4+nc.
  if (shape.length < 3) return true;
  final dim1 = shape[1];
  final dim2 = shape[2];
  final small = dim1 < dim2 ? dim1 : dim2;

  if (labelCount > 0) {
    if (small == 5 + labelCount) return true;
    if (small == 4 + labelCount) return false;
  }

  final total4 = 4 + inferredNumClasses;
  final total5 = 5 + inferredNumClasses;
  if (dim1 == total5 || dim2 == total5) return true;
  if (dim1 == total4 || dim2 == total4) return false;

  // Default to objectness (safer for most YOLO models).
  return true;
}

List<_RawDetection> _parseYoloOutput(
  Float32List output,
  List<int> shape,
  int numClasses,
  bool hasObjectness,
) {
  final detections = <_RawDetection>[];
  final totalElements = (hasObjectness ? 5 : 4) + numClasses;

  if (shape.length < 3) return detections;

  final dim1 = shape[1];
  final dim2 = shape[2];
  // Determine layout by matching the (4+nc) dimension.
  // If dim2 == totalElements -> [1, num_boxes, 4+nc] (boxes-first)
  // If dim1 == totalElements -> [1, 4+nc, num_boxes] (channels-first)
  final bool boxesFirst = dim2 == totalElements
      ? true
      : dim1 == totalElements
          ? false
          : (dim1 > dim2); // heuristic fallback

  final numBoxes = boxesFirst ? dim1 : dim2;
  final stride = numBoxes;

  // Layout: [1, 4+nc, num_boxes] -> for box k: values at k, stride+k, 2*stride+k, ...
  // Layout: [1, num_boxes, 4+nc] -> for box k: values at k*totalElements, k*totalElements+1, ...
  final isTransposed = boxesFirst;

  for (var k = 0; k < numBoxes; k++) {
    double cx, cy, w, h;
    double obj = 1.0;
    if (isTransposed) {
      final offset = k * totalElements;
      cx = output[offset];
      cy = output[offset + 1];
      w = output[offset + 2];
      h = output[offset + 3];
      if (hasObjectness) obj = output[offset + 4];
    } else {
      cx = output[k];
      cy = output[stride + k];
      w = output[2 * stride + k];
      h = output[3 * stride + k];
      if (hasObjectness) obj = output[4 * stride + k];
    }

    var maxScore = 0.0;
    var maxClass = 0;
    for (var c = 0; c < numClasses; c++) {
      final classOffset = hasObjectness ? 5 : 4;
      final score = isTransposed
          ? output[k * totalElements + classOffset + c]
          : output[(classOffset + c) * stride + k];
      if (score > maxScore) {
        maxScore = score;
        maxClass = c;
      }
    }

    final confidence = obj * maxScore;
    if (confidence > 0.01) {
      detections.add(_RawDetection(
        cx: cx,
        cy: cy,
        w: w,
        h: h,
        confidence: confidence,
        classIndex: maxClass,
      ));
    }
  }

  return detections;
}

List<_RawDetection> _parseFinalDetections6(
  Float32List output,
  List<int> shape,
) {
  // Shape is expected to be [1, N, 6]
  if (shape.length != 3 || shape[0] != 1 || shape[2] != 6) return <_RawDetection>[];
  final n = shape[1];
  final out = <_RawDetection>[];
  for (var i = 0; i < n; i++) {
    final off = i * 6;
    if (off + 5 >= output.length) break;

    final a0 = output[off];
    final a1 = output[off + 1];
    final a2 = output[off + 2];
    final a3 = output[off + 3];
    final v4 = output[off + 4];
    final v5 = output[off + 5];

    // Auto-detect score vs class columns.
    // Common layouts:
    // - [x1,y1,x2,y2,score,class]
    // - [x1,y1,x2,y2,class,score]
    // - score might be 0..1, 0..100, 0..255, or logits.
    final bool v4LooksInt = (v4.isFinite && (v4 - v4.round()).abs() < 1e-3);
    final bool v5LooksInt = (v5.isFinite && (v5 - v5.round()).abs() < 1e-3);
    final bool v4Prob = v4.isFinite && v4 >= 0 && v4 <= 1;
    final bool v5Prob = v5.isFinite && v5 >= 0 && v5 <= 1;

    double rawScore;
    double clsRaw;
    if (v4Prob && v5LooksInt && !v4LooksInt) {
      rawScore = v4;
      clsRaw = v5;
    } else if (v5Prob && v4LooksInt && !v5LooksInt) {
      rawScore = v5;
      clsRaw = v4;
    } else if (v4Prob && !v5Prob) {
      rawScore = v4;
      clsRaw = v5;
    } else if (v5Prob && !v4Prob) {
      rawScore = v5;
      clsRaw = v4;
    } else {
      // Fall back: treat the larger magnitude as score.
      if (v4.abs() >= v5.abs()) {
        rawScore = v4;
        clsRaw = v5;
      } else {
        rawScore = v5;
        clsRaw = v4;
      }
    }

    final score = _normalizeScore(rawScore);

    // Skip empty rows (common padding)
    if (score <= 0.001) continue;

    // Heuristic: if a2>a0 and a3>a1 treat as xyxy, else treat as cxcywh.
    final bool isXyxy = (a2 > a0) && (a3 > a1);
    double cx, cy, w, h;
    if (isXyxy) {
      final x1 = a0;
      final y1 = a1;
      final x2 = a2;
      final y2 = a3;
      w = (x2 - x1);
      h = (y2 - y1);
      cx = x1 + w / 2;
      cy = y1 + h / 2;
    } else {
      cx = a0;
      cy = a1;
      w = a2;
      h = a3;
    }

    final classIndex =
        clsRaw.isFinite ? clsRaw.round().clamp(0, 9999) : 0;
    out.add(
      _RawDetection(
        cx: cx.toDouble(),
        cy: cy.toDouble(),
        w: w.toDouble(),
        h: h.toDouble(),
        confidence: score.clamp(0.0, 1.0),
        classIndex: classIndex,
      ),
    );
  }
  return out;
}

double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

double _normalizeScore(double raw) {
  if (!raw.isFinite) return 0.0;
  // If already probability.
  if (raw >= 0.0 && raw <= 1.0) return raw;
  // If looks like percent.
  if (raw > 1.0 && raw <= 100.0) return raw / 100.0;
  // If looks like 0..255.
  if (raw > 1.0 && raw <= 255.0) return raw / 255.0;
  // If logits (can be negative/positive large), sigmoid it.
  if (raw < 0.0 || raw > 1.0) return _sigmoid(raw);
  return 0.0;
}

void _flatten3d(
  List<List<List<double>>> src,
  Float32List dst,
) {
  var k = 0;
  for (final b in src) {
    for (final row in b) {
      for (final v in row) {
        if (k >= dst.length) return;
        dst[k++] = v.toDouble();
      }
    }
  }
}

List<_RawDetection> _applyNms(
  List<_RawDetection> detections,
  double iouThreshold,
  int maxDetections,
) {
  detections.sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <_RawDetection>[];

  for (final d in detections) {
    if (kept.length >= maxDetections) break;
    var overlap = false;
    for (final k in kept) {
      if (_iou(d, k) > iouThreshold) {
        overlap = true;
        break;
      }
    }
    if (!overlap) kept.add(d);
  }

  return kept;
}

double _iou(_RawDetection a, _RawDetection b) {
  final aLeft = a.cx - a.w / 2;
  final aTop = a.cy - a.h / 2;
  final aRight = a.cx + a.w / 2;
  final aBottom = a.cy + a.h / 2;

  final bLeft = b.cx - b.w / 2;
  final bTop = b.cy - b.h / 2;
  final bRight = b.cx + b.w / 2;
  final bBottom = b.cy + b.h / 2;

  final interLeft = aLeft > bLeft ? aLeft : bLeft;
  final interTop = aTop > bTop ? aTop : bTop;
  final interRight = aRight < bRight ? aRight : bRight;
  final interBottom = aBottom < bBottom ? aBottom : bBottom;

  final interW = (interRight - interLeft).clamp(0.0, double.infinity);
  final interH = (interBottom - interTop).clamp(0.0, double.infinity);
  final interArea = interW * interH;

  final aArea = a.w * a.h;
  final bArea = b.w * b.h;
  final unionArea = aArea + bArea - interArea;

  return unionArea > 0 ? interArea / unionArea : 0;
}

class _RawDetection {
  _RawDetection({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.confidence,
    required this.classIndex,
  });
  final double cx, cy, w, h, confidence;
  final int classIndex;
}
