library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/map_tiles.dart';
import '../core/supabase_client.dart';
import '../core/theme.dart';
import '../screens/captured_photo_detail_screen.dart';
import '../utils/severity_score.dart';
import '../widgets/severity_glow_marker.dart';

class DetectionsMapScreen extends StatefulWidget {
  const DetectionsMapScreen({
    super.key,
    this.fieldId,
    this.fieldName,
  });

  final String? fieldId;
  final String? fieldName;

  @override
  State<DetectionsMapScreen> createState() => _DetectionsMapScreenState();
}

class _DetectionsMapScreenState extends State<DetectionsMapScreen> {
  bool _showGrid = true;
  double _cellSizeM = 25.0;

  static const double _earthRadiusM = 6378137.0;

  /// Convert meters north/south to delta-lat degrees.
  double _metersToLatDeg(double meters) =>
      (meters / _earthRadiusM) * (180.0 / 3.141592653589793);

  /// Convert meters east/west to delta-lng degrees at a given latitude.
  double _metersToLngDeg(double meters, double atLatDeg) {
    final double latRad = atLatDeg * (3.141592653589793 / 180.0);
    final double denom =
        _earthRadiusM * (math.cos(latRad)).clamp(0.000001, 1.0);
    return (meters / denom) * (180.0 / 3.141592653589793);
  }

  /// Equirectangular approximation: degrees -> meters around a reference lat.
  Offset _latLngToMeters({
    required double lat,
    required double lng,
    required double refLat,
    required double refLng,
  }) {
    final double dLat = (lat - refLat) * (3.141592653589793 / 180.0);
    final double dLng = (lng - refLng) * (3.141592653589793 / 180.0);
    final double refLatRad = refLat * (3.141592653589793 / 180.0);
    final double x = _earthRadiusM * dLng * math.cos(refLatRad);
    final double y = _earthRadiusM * dLat;
    return Offset(x, y);
  }

  Color _gridColor(double s01) {
    final double v = s01.clamp(0.0, 1.0);
    // Smooth green -> red. (We still keep the point glow palette elsewhere.)
    return Color.lerp(const Color(0xFF2ECC71), const Color(0xFFE74C3C), v)!;
  }

  void _setCellSize(double meters) {
    setState(() => _cellSizeM = meters);
  }

  @override
  Widget build(BuildContext context) {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(widget.fieldName?.trim().isNotEmpty == true
            ? 'Detections Map • ${widget.fieldName}'
            : 'Detections Map'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Grid cell size',
            initialValue: _cellSizeM,
            onSelected: _setCellSize,
            itemBuilder: (_) => const <PopupMenuEntry<double>>[
              PopupMenuItem<double>(
                value: 10,
                child: Text('10m grid'),
              ),
              PopupMenuItem<double>(
                value: 25,
                child: Text('25m grid'),
              ),
              PopupMenuItem<double>(
                value: 50,
                child: Text('50m grid'),
              ),
            ],
            icon: const Icon(Icons.square_foot),
          ),
          IconButton(
            tooltip: _showGrid ? 'Hide grid' : 'Show grid',
            onPressed: () => setState(() => _showGrid = !_showGrid),
            icon: Icon(_showGrid ? Icons.grid_off : Icons.grid_on),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to view detections map.'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: () {
                final String? f = widget.fieldId?.trim();
                if (f != null && f.isNotEmpty) {
                  // Apply filters before ordering; the stream builder type only
                  // exposes filter methods before order() is called.
                  return SupabaseClientProvider.instance.client
                      .from('detections')
                      .stream(primaryKey: const <String>['id'])
                      .eq('field_id', f)
                      .order('created_at', ascending: false);
                }
                // RLS already scopes rows to the signed-in user, so we don't
                // need a user_id filter here.
                return SupabaseClientProvider.instance.client
                    .from('detections')
                    .stream(primaryKey: const <String>['id'])
                    .order('created_at', ascending: false);
              }(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load detections: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<Map<String, dynamic>> docs = snapshot.data!;
                final List<_DetectionPoint> pts = docs
                    .map((d) => _DetectionPoint.fromRow(d))
                    .whereType<_DetectionPoint>()
                    .where((p) => p.lat != null && p.lng != null)
                    .toList();

                if (pts.isEmpty) {
                  return const Center(
                    child: Text('No geo-tagged detections yet.'),
                  );
                }

                final LatLng center = LatLng(pts.first.lat!, pts.first.lng!);

                final List<Polygon> gridPolys = <Polygon>[];
                if (_showGrid) {
                  // Build a square grid in meters around a reference origin.
                  // Aggregate severity per cell (weighted average) to smooth
                  // the heatmap. Weight = bugCount × confidence.
                  final Map<math.Point<int>, double> cellSumW = {};
                  final Map<math.Point<int>, double> cellSumWS = {};
                  final double refLat = center.latitude;
                  final double refLng = center.longitude;

                  for (final p in pts) {
                    final int bugCount = p.count ?? 0;
                    final int confidencePct = p.confidencePct ?? 0;
                    final double sev =
                        severity01(bugCount: bugCount, confidencePct: confidencePct);
                    final double w = math.max(
                      0.0,
                      bugCount * (confidencePct.clamp(0, 100) / 100.0),
                    );
                    final Offset m = _latLngToMeters(
                      lat: p.lat!,
                      lng: p.lng!,
                      refLat: refLat,
                      refLng: refLng,
                    );
                    final int cx = (m.dx / _cellSizeM).floor();
                    final int cy = (m.dy / _cellSizeM).floor();
                    final key = math.Point<int>(cx, cy);
                    cellSumW[key] = (cellSumW[key] ?? 0.0) + w;
                    cellSumWS[key] = (cellSumWS[key] ?? 0.0) + (w * sev);
                  }

                  for (final entry in cellSumW.entries) {
                    final int cx = entry.key.x;
                    final int cy = entry.key.y;
                    final double sumW = entry.value;
                    final double sumWS = cellSumWS[entry.key] ?? 0.0;
                    final double sev = sumW <= 0 ? 0.0 : (sumWS / sumW);

                    final double x0 = cx * _cellSizeM;
                    final double y0 = cy * _cellSizeM;
                    final double x1 = x0 + _cellSizeM;
                    final double y1 = y0 + _cellSizeM;

                    final double lat0 = refLat + _metersToLatDeg(y0);
                    final double lat1 = refLat + _metersToLatDeg(y1);
                    final double lng0 = refLng + _metersToLngDeg(x0, refLat);
                    final double lng1 = refLng + _metersToLngDeg(x1, refLat);

                    final Color fill =
                        _gridColor(sev).withValues(alpha: 0.28);
                    final Color stroke =
                        _gridColor(sev).withValues(alpha: 0.55);

                    gridPolys.add(
                      Polygon(
                        points: <LatLng>[
                          LatLng(lat0, lng0),
                          LatLng(lat0, lng1),
                          LatLng(lat1, lng1),
                          LatLng(lat1, lng0),
                        ],
                        color: fill,
                        borderColor: stroke,
                        borderStrokeWidth: 1.0,
                      ),
                    );
                  }
                }

                return FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 16,
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
                    if (gridPolys.isNotEmpty)
                      PolygonLayer(polygons: gridPolys),
                    MarkerLayer(
                      markers: pts.map((p) {
                        final double sev = severity01(
                          bugCount: p.count ?? 0,
                          confidencePct: p.confidencePct ?? 0,
                        );
                        return Marker(
                          point: LatLng(p.lat!, p.lng!),
                          width: 120,
                          height: 120,
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: () {
                              final int? capturedPhotoId = p.capturedPhotoId;
                              if (capturedPhotoId == null) return;
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CapturedPhotoDetailScreen(
                                    capturedPhotoId: capturedPhotoId,
                                  ),
                                ),
                              );
                            },
                            child: SeverityGlowMarker(
                              severity01: sev,
                              baseSize: 22,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_showGrid)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _GridLegend(cellSizeM: _cellSizeM),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _GridLegend extends StatelessWidget {
  const _GridLegend({required this.cellSizeM});

  final double cellSizeM;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFF2ECC71),
                    Color(0xFFF1C40F),
                    Color(0xFFF39C12),
                    Color(0xFFE74C3C),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${cellSizeM.toStringAsFixed(0)}m cells',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionPoint {
  const _DetectionPoint({
    required this.lat,
    required this.lng,
    required this.count,
    required this.confidencePct,
    required this.capturedPhotoId,
  });

  final double? lat;
  final double? lng;
  final int? count;
  final int? confidencePct;
  final int? capturedPhotoId;

  static _DetectionPoint? fromRow(Map<String, dynamic> d) {
    final double? lat = d['latitude'] == null ? null : (d['latitude'] as num).toDouble();
    final double? lng = d['longitude'] == null ? null : (d['longitude'] as num).toDouble();
    final int? count = (d['count'] as num?)?.toInt();
    final num? rawConf = d['confidence'] as num?;
    // Backwards-compatible normalization:
    // - If stored as fraction (0..1), convert to percent.
    // - If stored as percent (0..100), keep as-is.
    final int? confidencePct = rawConf == null
        ? null
        : (() {
            final double v = rawConf.toDouble();
            final double pct = v <= 1.0 ? (v * 100.0) : v;
            return pct.round().clamp(0, 100);
          })();

    // Optional linkage if your DB stores it; otherwise tapping will do nothing.
    final int? capturedPhotoId = (d['captured_photo_id'] as num?)?.toInt();

    return _DetectionPoint(
      lat: lat,
      lng: lng,
      count: count,
      confidencePct: confidencePct,
      capturedPhotoId: capturedPhotoId,
    );
  }
}

