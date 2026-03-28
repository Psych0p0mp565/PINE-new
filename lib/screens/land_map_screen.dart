/// Land boundary editor: define polygons on map for geo-fencing.
///
/// Uses flutter_map. Drawing UX: satellite-first, filled polygon preview,
/// tap vertices, tap near the first vertex to close (or use actions).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/map_tiles.dart';
import '../core/theme.dart';
import '../models/land.dart';
import '../services/database_service.dart';

enum _LandMapStyle { satellite, street, terrain }

/// Screen for creating/editing land boundaries on a map.
class LandMapScreen extends StatefulWidget {
  const LandMapScreen({
    super.key,
    this.land,
    this.onSaved,
    this.initialCenter,
  });

  final Land? land;
  final VoidCallback? onSaved;
  /// When set, map centers here and user can start drawing the boundary.
  final LatLng? initialCenter;

  @override
  State<LandMapScreen> createState() => _LandMapScreenState();
}

class _LandMapScreenState extends State<LandMapScreen> {
  final _mapController = MapController();
  final _database = DatabaseService();
  final _nameController = TextEditingController();

  List<LatLng> _polygonPoints = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  _LandMapStyle _mapStyle = _LandMapStyle.satellite;
  /// After closing the ring (tap near first point), no more vertices.
  bool _isClosed = false;

  static const Distance _distance = Distance();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.land?.landName ?? '';
    _polygonPoints = widget.land?.polygonCoordinates
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList() ??
        [];
    if (_polygonPoints.length >= 3) {
      _isClosed = true;
    }
    _initialize();
  }

  Future<void> _initialize() async {
    await _database.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  bool _isNearFirstVertex(LatLng tap) {
    if (_polygonPoints.length < 3) return false;
    final double meters =
        _distance.as(LengthUnit.Meter, _polygonPoints.first, tap);
    return meters < 22;
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_isClosed) return;
    if (_polygonPoints.length >= 3 && _isNearFirstVertex(point)) {
      setState(() => _isClosed = true);
      return;
    }
    setState(() => _polygonPoints.add(point));
  }

  void _removeLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      setState(() {
        _polygonPoints.removeLast();
        _isClosed = false;
      });
    }
  }

  void _clearPoints() {
    setState(() {
      _polygonPoints.clear();
      _isClosed = false;
    });
  }

  Future<void> _saveLand() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter land name')),
      );
      return;
    }
    if (_polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least 3 points to form a polygon'),
        ),
      );
      return;
    }
    if (!_isClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Close the shape: tap near the first point, or keep adding corners'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final coords = _polygonPoints
          .map((p) => LatLngPoint(p.latitude, p.longitude))
          .toList();

      if (widget.land?.id != null) {
        await _database.updateLand(
          widget.land!.copyWith(
            landName: name,
            polygonCoordinates: coords,
          ),
        );
      } else {
        await _database.insertLand(Land(
          landName: name,
          polygonCoordinates: coords,
          createdAt: DateTime.now(),
        ));
      }

      widget.onSaved?.call();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _tileUrl() {
    switch (_mapStyle) {
      case _LandMapStyle.satellite:
        return MapTiles.esriWorldImagery;
      case _LandMapStyle.terrain:
        return MapTiles.esriTerrain;
      case _LandMapStyle.street:
        return MapTiles.openStreetMap;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<LatLng> ring = _polygonPoints.length >= 3
        ? <LatLng>[..._polygonPoints, _polygonPoints.first]
        : <LatLng>[];

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(
          widget.land != null ? 'Edit field boundary' : 'Draw field boundary',
        ),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: <Widget>[
          PopupMenuButton<_LandMapStyle>(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Map style',
            onSelected: (_LandMapStyle s) => setState(() => _mapStyle = s),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_LandMapStyle>>[
              const PopupMenuItem<_LandMapStyle>(
                value: _LandMapStyle.satellite,
                child: Text('Satellite'),
              ),
              const PopupMenuItem<_LandMapStyle>(
                value: _LandMapStyle.street,
                child: Text('Street'),
              ),
              const PopupMenuItem<_LandMapStyle>(
                value: _LandMapStyle.terrain,
                child: Text('Terrain'),
              ),
            ],
          ),
          if (_polygonPoints.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _isClosed ? null : _removeLastPoint,
              tooltip: 'Remove last point',
            ),
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearPoints,
              tooltip: 'Clear all points',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Field name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _polygonPoints.isNotEmpty
                        ? _polygonPoints.first
                        : widget.initialCenter ?? const LatLng(14.5995, 120.9842),
                    initialZoom: 16,
                    maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                    minZoom: 3,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl(),
                      userAgentPackageName: 'com.pine.pine',
                      maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                      maxNativeZoom: MapTiles.maxZoomSatellite,
                    ),
                    if (ring.length >= 4)
                      PolygonLayer(
                        polygons: <Polygon>[
                          Polygon(
                            points: ring,
                            color: AppTheme.primaryGreen.withValues(alpha: 0.22),
                            borderColor: AppTheme.primaryGreen,
                            borderStrokeWidth: 2.5,
                          ),
                        ],
                      )
                    else if (_polygonPoints.length >= 2)
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: _polygonPoints,
                            color: AppTheme.primaryGreen,
                            strokeWidth: 3,
                          ),
                        ],
                      ),
                    if (_polygonPoints.isNotEmpty)
                      MarkerLayer(
                        markers: _polygonPoints
                            .asMap()
                            .entries
                            .map((MapEntry<int, LatLng> e) {
                          final bool isFirst = e.key == 0;
                          return Marker(
                            point: e.value,
                            width: isFirst ? 22 : 16,
                            height: isFirst ? 22 : 16,
                            alignment: Alignment.center,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: AppTheme.primaryGreen,
                                  width: isFirst ? 3 : 2,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: isFirst ? 8 : 6,
                                  height: isFirst ? 8 : 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.94),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            _isClosed
                                ? Icons.check_circle_outline
                                : Icons.touch_app_outlined,
                            color: AppTheme.primaryGreen,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isClosed
                                  ? 'Boundary closed. Save when ready.'
                                  : _polygonPoints.length >= 3
                                      ? 'Tap the green ring (first point) to close, or add more corners.'
                                      : 'Tap the map to place corners along your field edge.',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.errorRed),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveLand,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save boundary'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
