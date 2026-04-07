library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/detection_result.dart';
import '../core/map_tiles.dart';
import '../core/theme.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/image_storage_service.dart';
import '../utils/severity_score.dart';
import '../widgets/severity_glow_marker.dart';
import '../widgets/action_popup.dart';

class CapturedPhotoDetailScreen extends StatefulWidget {
  const CapturedPhotoDetailScreen({
    super.key,
    required this.capturedPhotoId,
  });

  final int capturedPhotoId;

  @override
  State<CapturedPhotoDetailScreen> createState() =>
      _CapturedPhotoDetailScreenState();
}

class _CapturedPhotoDetailScreenState extends State<CapturedPhotoDetailScreen> {
  late final DatabaseService _db;
  late final ImageStorageService _images;
  late final ExportService _export;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _db = DatabaseService();
    _images = ImageStorageService();
    _export = ExportService(databaseService: _db, imageStorageService: _images);
  }

  Future<Map<String, dynamic>?> _load() async {
    await _db.initialize();
    return _db.getCapturedPhotoById(widget.capturedPhotoId);
  }

  Future<Uint8List?> _loadCaptureBytes({
    required String localPath,
    String? remoteUrl,
  }) async {
    if (localPath != DatabaseService.remoteOnlyLocalPath) {
      final File? f = await _images.getImageFile(localPath);
      if (f != null) return f.readAsBytes();
    }
    final String? u = remoteUrl?.trim();
    if (u != null && u.isNotEmpty) {
      try {
        final http.Response r = await http.get(Uri.parse(u));
        if (r.statusCode == 200) return r.bodyBytes;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Captured Picture'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final row = snapshot.data;
          if (row == null) {
            return const Center(child: Text('Capture not found.'));
          }

          final String fieldName = (row['field_name'] as String?) ?? 'Field';
          final String fieldLabel = fieldName;
          final int confidence = (row['confidence'] as num?)?.toInt() ?? 0;
          final int count = (row['count'] as num?)?.toInt() ?? 0;
          final double? lat = row['latitude'] == null
              ? null
              : (row['latitude'] as num).toDouble();
          final double? lng = row['longitude'] == null
              ? null
              : (row['longitude'] as num).toDouble();
          final String localPath = row['local_image_path'] as String;
          final String? remoteUrl = row['remote_image_url'] as String?;
          final String createdAt = (row['created_at'] as String?) ?? '';
          final List<Detection> detections = _parseDetections(
            row['detections_json'] as String?,
          );
          final double sev = severity01(
            bugCount: count,
            confidencePct: confidence,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FutureBuilder<Uint8List?>(
                future: _loadCaptureBytes(
                  localPath: localPath,
                  remoteUrl: remoteUrl,
                ),
                builder: (context, snap) {
                  final Uint8List? bytes = snap.data;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: bytes == null
                        ? Container(
                            height: 220,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.image_not_supported),
                            ),
                          )
                        : InkWell(
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => _SavedDetectionImageViewer(
                                    imageBytes: bytes,
                                    detections: detections,
                                  ),
                                ),
                              );
                            },
                            child: SizedBox(
                              height: 260,
                              width: double.infinity,
                              child: _SavedDetectionOverlayImage(
                                imageBytes: bytes,
                                detections: detections,
                              ),
                            ),
                          ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fieldLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _row('Mealybug Count', '$count'),
                      _row('Confidence', '$confidence%'),
                      if (detections.isNotEmpty)
                        _row('Detection Labels', '${detections.length} markers'),
                      if (createdAt.isNotEmpty) _row('Captured at', createdAt),
                      if (lat != null && lng != null)
                        _row('GPS', '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
                    ],
                  ),
                ),
              ),
              if (lat != null && lng != null) ...[
                const SizedBox(height: 14),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.my_location,
                              color: severityColor(sev),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Location',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 180,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(lat, lng),
                                initialZoom: 18,
                                maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                                minZoom: 3,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: MapTiles.esriWorldImagery,
                                  userAgentPackageName: 'com.pine.pine',
                                  maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                                  maxNativeZoom: MapTiles.maxZoomSatellite,
                                ),
                                MarkerLayer(
                                  markers: <Marker>[
                                    Marker(
                                      point: LatLng(lat, lng),
                                      width: 120,
                                      height: 120,
                                      alignment: Alignment.center,
                                      child: SeverityGlowMarker(
                                        severity01: sev,
                                        baseSize: 22,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final ActionPopupController popup =
                              ActionPopupController();
                          try {
                            popup.showBlockingProgress(
                              context,
                              message: 'Exporting…',
                            );
                            await _export.exportSingleCapturedPhotoZip(
                              widget.capturedPhotoId,
                            );
                            popup.close();
                            if (!context.mounted) return;
                            await ActionPopup.showSuccess(
                              context,
                              message: 'Export complete.',
                            );
                          } catch (e) {
                            popup.close();
                            if (!context.mounted) return;
                            await ActionPopup.showError(
                              context,
                              message: 'Export failed: $e',
                            );
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export this capture (ZIP)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textMedium,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<Detection> _parseDetections(String? raw) {
    if (raw == null || raw.isEmpty) return const <Detection>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <Detection>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => Detection(
                left: (m['left'] as num?)?.toDouble() ?? 0,
                top: (m['top'] as num?)?.toDouble() ?? 0,
                width: (m['width'] as num?)?.toDouble() ?? 0,
                height: (m['height'] as num?)?.toDouble() ?? 0,
                confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
                classIndex: (m['classIndex'] as num?)?.toInt() ?? 0,
                label: m['label'] as String?,
              ))
          .toList();
    } catch (_) {
      return const <Detection>[];
    }
  }
}

class _SavedDetectionImageViewer extends StatelessWidget {
  const _SavedDetectionImageViewer({
    required this.imageBytes,
    required this.detections,
  });

  final Uint8List imageBytes;
  final List<Detection> detections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Saved Detection Preview'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _SavedDetectionOverlayImage(
            imageBytes: imageBytes,
            detections: detections,
          ),
        ),
      ),
    );
  }
}

class _SavedDetectionOverlayImage extends StatelessWidget {
  const _SavedDetectionOverlayImage({
    required this.imageBytes,
    required this.detections,
  });

  final Uint8List imageBytes;
  final List<Detection> detections;

  Future<Size> _imageSize() async {
    final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Size>(
      future: _imageSize(),
      builder: (context, snapshot) {
        final Size imageSize = snapshot.data ?? const Size(1, 1);
        return LayoutBuilder(
          builder: (context, constraints) {
            final double scale = (constraints.maxWidth / imageSize.width)
                .clamp(0.0, constraints.maxHeight / imageSize.height);
            final double drawnW = imageSize.width * scale;
            final double drawnH = imageSize.height * scale;
            final double offsetX = (constraints.maxWidth - drawnW) / 2;
            final double offsetY = (constraints.maxHeight - drawnH) / 2;
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                  ),
                ),
                if (detections.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SavedDetectionLabelPainter(
                        detections: detections,
                        imageOffset: Offset(offsetX, offsetY),
                        imageScale: scale,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SavedDetectionLabelPainter extends CustomPainter {
  _SavedDetectionLabelPainter({
    required this.detections,
    required this.imageOffset,
    required this.imageScale,
  });

  final List<Detection> detections;
  final Offset imageOffset;
  final double imageScale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final double cx = imageOffset.dx + (d.left + d.width / 2) * imageScale;
      final double cy = imageOffset.dy + (d.top + d.height / 2) * imageScale;

      final Paint dot = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), 4.2, dot);

      final int pct = (d.confidence * 100).round().clamp(0, 100);
      final String text = '$pct%';
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const double padX = 6;
      const double padY = 4;
      final double w = tp.width + padX * 2;
      final double h = tp.height + padY * 2;
      double x = cx + 10;
      double y = cy - h - 10;
      if (x + w > size.width) x = size.width - w - 6;
      if (x < 6) x = 6;
      if (y < 6) y = cy + 10;
      if (y + h > size.height) y = size.height - h - 6;

      final RRect bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      tp.paint(canvas, Offset(x + padX, y + padY));
    }
  }

  @override
  bool shouldRepaint(covariant _SavedDetectionLabelPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale;
  }
}

