// Location picker focused on South Cotabato with municipality chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_logger.dart';
import '../core/map_tiles.dart';
import '../core/theme.dart';
import 'land_map_screen.dart';
import '../widgets/online_required_dialog.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

enum _MapStyle { street, satellite, dark, terrain }

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  _MapStyle _mapStyle = _MapStyle.satellite;
  final TextEditingController _searchController = TextEditingController();

  static const LatLng polomolokCenter = LatLng(6.2167, 125.0667);
  static final LatLngBounds polomolokBounds = LatLngBounds(
    const LatLng(6.06, 124.90),
    const LatLng(6.44, 125.24),
  );

  final List<Map<String, dynamic>> polomolokLocations =
      <Map<String, dynamic>>[
    <String, dynamic>{'name': 'Polomolok', 'lat': 6.2167, 'lng': 125.0667},
    <String, dynamic>{'name': 'Poblacion', 'lat': 6.2158, 'lng': 125.0635},
    <String, dynamic>{'name': 'Cannery Site', 'lat': 6.2408, 'lng': 125.0613},
    <String, dynamic>{'name': 'Landan', 'lat': 6.1787, 'lng': 125.0873},
    <String, dynamic>{'name': 'Lumakil', 'lat': 6.2152, 'lng': 125.1138},
  ];

  @override
  void initState() {
    super.initState();
    _selectedLocation = polomolokCenter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(polomolokCenter, 11.6);
    });
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      AppLogger.error('Location error', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location - Polomolok'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        actions: <Widget>[
          PopupMenuButton<_MapStyle>(
            icon: const Icon(Icons.layers),
            tooltip: 'Map style',
            onSelected: (_MapStyle style) {
              setState(() => _mapStyle = style);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<_MapStyle>>[
              const PopupMenuItem<_MapStyle>(
                value: _MapStyle.street,
                child: ListTile(
                  leading: Icon(Icons.map),
                  title: Text('Street'),
                ),
              ),
              const PopupMenuItem<_MapStyle>(
                value: _MapStyle.satellite,
                child: ListTile(
                  leading: Icon(Icons.satellite),
                  title: Text('Satellite'),
                ),
              ),
              const PopupMenuItem<_MapStyle>(
                value: _MapStyle.dark,
                child: ListTile(
                  leading: Icon(Icons.dark_mode),
                  title: Text('Dark'),
                ),
              ),
              const PopupMenuItem<_MapStyle>(
                value: _MapStyle.terrain,
                child: ListTile(
                  leading: Icon(Icons.terrain),
                  title: Text('Terrain'),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Polomolok locations...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: polomolokLocations.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> loc =
                        polomolokLocations[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(loc['name'] as String),
                        onSelected: (bool selected) {
                          final LatLng point = LatLng(
                            (loc['lat'] as num).toDouble(),
                            (loc['lng'] as num).toDouble(),
                          );
                          setState(() {
                            _selectedLocation = point;
                          });
                          _mapController.move(point, 14);
                        },
                        avatar: const Icon(Icons.location_on, size: 16),
                        selected: false,
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation ?? polomolokCenter,
                    initialZoom: 11.6,
                    minZoom: 10.8,
                    maxZoom: 18,
                    cameraConstraint:
                        CameraConstraint.contain(bounds: polomolokBounds),
                    onTap: (TapPosition tapPosition, LatLng point) {
                      setState(() => _selectedLocation = point);
                    },
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: _mapStyle == _MapStyle.satellite
                          ? MapTiles.esriWorldImagery
                          : _mapStyle == _MapStyle.dark
                              ? 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png'
                              : _mapStyle == _MapStyle.terrain
                                  ? MapTiles.esriTerrain
                                  : MapTiles.openStreetMap,
                      userAgentPackageName: 'com.pine.pine',
                      maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                      maxNativeZoom: MapTiles.maxZoomSatellite,
                    ),
                    if (_selectedLocation != null)
                      MarkerLayer(
                        markers: <Marker>[
                          Marker(
                            point: _selectedLocation!,
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: Colors.red.shade700,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    if (_currentLocation != null)
                      MarkerLayer(
                        markers: <Marker>[
                          Marker(
                            point: _currentLocation!,
                            width: 32,
                            height: 32,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_selectedLocation != null)
                      Text(
                        '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                        '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _selectedLocation != null
                            ? () => Navigator.pop(context, _selectedLocation)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirm Location'),
                      ),
                    ),
                    if (_selectedLocation != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (!await ensureOnline(context)) return;
                            if (!context.mounted) return;
                            final ScaffoldMessengerState messenger =
                                ScaffoldMessenger.of(context);
                            final bool? saved = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute<bool>(
                                builder: (_) => LandMapScreen(
                                  initialCenter: _selectedLocation,
                                ),
                              ),
                            );
                            if (saved == true && context.mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Boundary saved. You can confirm location or pick another.'),
                                  backgroundColor: AppTheme.primaryGreen,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.fence),
                          label: const Text('Draw field boundary'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryGreen,
                            side: const BorderSide(color: AppTheme.primaryGreen),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
