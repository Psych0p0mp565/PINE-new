// Camera, GPS, Gallery permission UIs; photo source picker; result; camera modes; albums.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/supabase_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/config.dart';
import '../core/app_state.dart';
import '../core/app_logger.dart';
import '../core/network_reachability.dart';
import '../core/theme.dart';
import '../models/detection_result.dart';
import '../services/cloud_sync_service.dart';
import '../services/image_storage_service.dart';
import '../services/database_service.dart';
import '../services/inference_service.dart';
import '../services/geo_fence_service.dart';
import '../models/land.dart';
import 'captured_photos_screen.dart';
import 'location_picker_screen.dart';
import '../widgets/online_required_dialog.dart';
import '../widgets/action_popup.dart';
import '../utils/exif_gps_reader.dart';

/// Shown after picking from gallery: optional map pin for where the photo was taken.
enum _WherePhotoTakenChoice { chooseOnMap, continueWithout }

/// Best-effort device GPS at the moment a gallery photo was chosen (fallback vs EXIF).
Future<({double? lat, double? lng})> _deviceGpsWhenGalleryPhotoChosen() async {
  try {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return (lat: null, lng: null);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return (lat: null, lng: null);
    }
    final Position? last = await Geolocator.getLastKnownPosition();
    final Position pos = last ??
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 6));
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (_) {
    return (lat: null, lng: null);
  }
}

Future<latlong2.LatLng?> _promptOptionalWherePhotoTaken(
  BuildContext context,
) async {
  final bool fil = context.read<AppState>().isFilipino;
  final _WherePhotoTakenChoice? choice =
      await showModalBottomSheet<_WherePhotoTakenChoice>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                fil ? 'Saan kinunan ang larawan?' : 'Where was this photo taken?',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                fil
                    ? 'Opsyonal. Kung laktawan, gagamitin ang iyong lokasyon ngayon (o GPS sa larawan kung mayroon).'
                    : 'Optional. If you skip, we use your current location now (or GPS from the file if present).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(sheetContext, _WherePhotoTakenChoice.chooseOnMap),
                icon: const Icon(Icons.map),
                label: Text(fil ? 'Pumili sa mapa' : 'Choose on map'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(sheetContext, _WherePhotoTakenChoice.continueWithout),
                child: Text(fil ? 'Laktawan' : 'Skip'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return null;
  if (choice != _WherePhotoTakenChoice.chooseOnMap) return null;
  if (!await ensureOnline(context)) return null;
  if (!context.mounted) return null;
  final Object? r = await Navigator.push<Object?>(
    context,
    MaterialPageRoute<Object?>(
      builder: (_) => const LocationPickerScreen(),
    ),
  );
  if (r is latlong2.LatLng) return r;
  return null;
}

String _noDetectionsDetailMessage(
  BuildContext context,
  DetectionResult result,
) {
  final bool fil = context.read<AppState>().isFilipino;
  final double maxRaw = (result.maxRawConfidence ?? 0.0) * 100;
  final String sample = (result.outputSample ?? const <double>[])
      .take(6)
      .map((v) => v.toStringAsFixed(3))
      .join(', ');
  final String tech =
      'maxRaw=${maxRaw.toStringAsFixed(1)}% raw=${result.rawDetectionsCount ?? 0} '
      'thr=${AppConfig.balanced().detectionThreshold} sample=[$sample]';
  if (fil) {
    return 'Walang namataang mealybug sa scan na ito.\n\n$tech';
  }
  return 'No mealybugs detected in this scan.\n\n$tech';
}

// --- Camera Permission ---
class CameraPermissionScreen extends StatelessWidget {
  const CameraPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Permission'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.camera_alt,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pine-Sight would like to access your Camera',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only when using the app',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMedium),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Allow', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Deny',
                    style: TextStyle(fontSize: 16, color: AppTheme.textMedium),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- GPS Permission ---
class GpsPermissionScreen extends StatelessWidget {
  const GpsPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Permission'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.location_on,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Allow Pine-Sight to access this device\'s location',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only when using the app',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMedium),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Allow', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Deny',
                    style: TextStyle(fontSize: 16, color: AppTheme.textMedium),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Gallery Permission ---
class GalleryPermissionScreen extends StatelessWidget {
  const GalleryPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Permission'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.photo_library,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pine-Sight would like to access your Gallery',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only when using the app',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMedium),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Allow', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Deny',
                    style: TextStyle(fontSize: 16, color: AppTheme.textMedium),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Photo Source Picker (Camera / Gallery) ---
class PhotoSourcePicker extends StatefulWidget {
  const PhotoSourcePicker({
    super.key,
    this.fieldName = 'Field',
    this.fieldId,
  });

  final String fieldName;

  /// When set, Save uses these for Supabase sync (required for "Please select a field" when missing).
  final String? fieldId;

  @override
  State<PhotoSourcePicker> createState() => _PhotoSourcePickerState();
}

class _PhotoSourcePickerState extends State<PhotoSourcePicker> {
  final ImagePicker _picker = ImagePicker();
  late final InferenceService _inferenceService;
  bool _busy = false;
  bool _gpsPromptShown = false;

  @override
  void initState() {
    super.initState();
    _inferenceService = InferenceService(config: AppConfig.balanced());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _promptForGpsIfNeeded();
    });
  }

  Future<void> _promptForGpsIfNeeded() async {
    if (!mounted || _gpsPromptShown) return;
    _gpsPromptShown = true;

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final LocationPermission permission = await Geolocator.checkPermission();
    final bool needsPrompt = !serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;
    if (!needsPrompt || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Turn on GPS for better accuracy'),
          content: const Text(
            'For best tagging accuracy, please enable GPS/location before taking or selecting a photo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                if (!serviceEnabled) {
                  await Geolocator.openLocationSettings();
                } else {
                  await Geolocator.requestPermission();
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Enable GPS'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFromGalleryAndDetect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final String path = picked.path;
      final latlong2.LatLng? mapPick =
          await _promptOptionalWherePhotoTaken(context);
      if (!mounted) return;
      final ({double? lat, double? lng}) pickGps =
          await _deviceGpsWhenGalleryPhotoChosen();
      final double? chosenTakeLat = mapPick?.latitude;
      final double? chosenTakeLng = mapPick?.longitude;
      final double? pickMomentLat = pickGps.lat;
      final double? pickMomentLng = pickGps.lng;

      int confidence = 0;
      int count = 0;
      List<Detection> detections = const <Detection>[];
      int? originalImageWidth;
      int? originalImageHeight;
      Uint8List? imageBytes;
      final BuildContext rootContext = context;
      bool scanDialogShown = false;
      try {
        if (rootContext.mounted) {
          showDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: (_) => const _ScanningDialog(),
          );
          scanDialogShown = true;
        }
        imageBytes = Uint8List.fromList(await picked.readAsBytes());
        await _inferenceService.initialize();
        final DetectionResult result = await _inferenceService.runInference(imageBytes);
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        count = result.detections.length;
        detections = result.detections;
        originalImageWidth = result.originalWidth;
        originalImageHeight = result.originalHeight;
        confidence = result.detections.isEmpty
            ? 0
            : (result.detections
                        .map((d) => d.confidence)
                        .reduce((a, b) => a + b) /
                    result.detections.length *
                    100)
                .round()
                .clamp(0, 100);
        if (count == 0 && mounted) {
          await ActionPopup.showInfo(
            context,
            title: context.read<AppState>().isFilipino
                ? 'Walang deteksyon'
                : 'No detections',
            message: _noDetectionsDetailMessage(context, result),
          );
        }
      } catch (e) {
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        AppLogger.error('Inference ERROR (gallery direct)', e);
        if (mounted) {
          await ActionPopup.showError(
            context,
            message: 'Detection failed: $e',
          );
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PhotoResultScreen(
            fieldName: widget.fieldName,
            imagePath: path,
            imageBytes: imageBytes,
            confidence: confidence,
            count: count,
            detections: detections,
            originalImageWidth: originalImageWidth,
            originalImageHeight: originalImageHeight,
            fieldId: widget.fieldId,
            takeLocationChosenLat: chosenTakeLat,
            takeLocationChosenLng: chosenTakeLng,
            pickMomentLat: pickMomentLat,
            pickMomentLng: pickMomentLng,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Add Photo'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Captured pictures',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const CapturedPhotosScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhite,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'How would you like to upload the photo?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _buildOption(
                            context,
                            icon: Icons.camera_alt,
                            label: 'Camera',
                            onTap: () {
                              Navigator.pushReplacement<void, void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CameraModeSelector(
                                    fieldName: widget.fieldName,
                                    fieldId: widget.fieldId,
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildOption(
                            context,
                            icon: Icons.photo_library,
                            label: 'Gallery',
                            onTap: () {
                              _pickFromGalleryAndDetect();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: AppTheme.primaryGreen),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Photo Result (after detection) ---
class PhotoResultScreen extends StatefulWidget {
  const PhotoResultScreen({
    super.key,
    required this.fieldName,
    this.imagePath,
    this.imageBytes,
    this.confidence = 70,
    this.count = 100,
    this.detections = const <Detection>[],
    this.originalImageWidth,
    this.originalImageHeight,
    this.fieldId,
    this.takeLocationChosenLat,
    this.takeLocationChosenLng,
    this.pickMomentLat,
    this.pickMomentLng,
  });

  final String fieldName;

  /// Optional path to the image file. When set, Save will upload via Supabase.
  final String? imagePath;
  final Uint8List? imageBytes;
  final int confidence;
  final int count;
  final List<Detection> detections;
  final int? originalImageWidth;
  final int? originalImageHeight;

  /// When set, Save uses these for Supabase (`detections` + local queue).
  final String? fieldId;

  /// User-picked “where taken” from map after gallery pick (highest priority).
  final double? takeLocationChosenLat;
  final double? takeLocationChosenLng;

  /// Device GPS captured when the gallery photo was chosen (after optional sheet).
  final double? pickMomentLat;
  final double? pickMomentLng;

  @override
  State<PhotoResultScreen> createState() => _PhotoResultScreenState();
}

class _PhotoResultScreenState extends State<PhotoResultScreen>
    with SingleTickerProviderStateMixin {
  double? _taggedLat;
  double? _taggedLng;
  GeoFenceResult? _fence;
  bool _saving = false;
  bool _gettingGps = false;
  late final AnimationController _pulse;
  late final GeoFenceService _geoFence;
  late final DatabaseService _db;

  @override
  void initState() {
    super.initState();
    _geoFence = GeoFenceService();
    _db = DatabaseService();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    final double? cLat = widget.takeLocationChosenLat;
    final double? cLng = widget.takeLocationChosenLng;
    if (cLat != null && cLng != null) {
      _taggedLat = cLat;
      _taggedLng = cLng;
    }
    // ignore: discarded_futures
    _tagFromExifThenDevice();
  }

  /// Priority: user map pick → EXIF → GPS when gallery photo was chosen → live device.
  Future<void> _tagFromExifThenDevice() async {
    if (_taggedLat != null && _taggedLng != null) {
      await _updateGeoFence();
      return;
    }
    final ({double lat, double lng})? exifGps = await readGpsFromImage(
      bytes: widget.imageBytes,
      path: widget.imagePath,
    );
    if (!mounted) return;
    if (exifGps != null) {
      setState(() {
        _taggedLat = exifGps.lat;
        _taggedLng = exifGps.lng;
      });
      await _updateGeoFence();
      return;
    }
    final double? mLat = widget.pickMomentLat;
    final double? mLng = widget.pickMomentLng;
    if (mLat != null && mLng != null) {
      setState(() {
        _taggedLat = mLat;
        _taggedLng = mLng;
      });
      await _updateGeoFence();
      return;
    }
    await _autoTagCurrentLocation();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _autoTagCurrentLocation() async {
    if (_taggedLat != null) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // Prefer last-known first (more reliable offline) then try a fresh fix.
      final Position? last = await Geolocator.getLastKnownPosition();
      final Position pos = last ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _taggedLat = pos.latitude;
        _taggedLng = pos.longitude;
      });
      await _updateGeoFence();
    } catch (_) {
      // If location isn't available/permission denied, keep manual tagging only.
    }
  }

  Future<bool> _ensureTaggedLocation({
    required bool showUi,
  }) async {
    if (_taggedLat != null && _taggedLng != null) return true;
    if (_gettingGps) return false;
    _gettingGps = true;
    final ActionPopupController popup = ActionPopupController();
    try {
      final double? chosenLat = widget.takeLocationChosenLat;
      final double? chosenLng = widget.takeLocationChosenLng;
      if (chosenLat != null && chosenLng != null) {
        setState(() {
          _taggedLat = chosenLat;
          _taggedLng = chosenLng;
        });
        await _updateGeoFence();
        return true;
      }

      // User may save before initState EXIF read finishes; try EXIF next.
      final ({double lat, double lng})? exifGps = await readGpsFromImage(
        bytes: widget.imageBytes,
        path: widget.imagePath,
      );
      if (!mounted) return false;
      if (exifGps != null) {
        setState(() {
          _taggedLat = exifGps.lat;
          _taggedLng = exifGps.lng;
        });
        await _updateGeoFence();
        return true;
      }

      final double? pmLat = widget.pickMomentLat;
      final double? pmLng = widget.pickMomentLng;
      if (pmLat != null && pmLng != null) {
        setState(() {
          _taggedLat = pmLat;
          _taggedLng = pmLng;
        });
        await _updateGeoFence();
        return true;
      }

      if (showUi && mounted) {
        popup.showBlockingProgress(
          context,
          message: 'Getting GPS…',
        );
      }

      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final Position? last = await Geolocator.getLastKnownPosition();
      final Position pos = last ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 6));

      if (!mounted) return false;
      setState(() {
        _taggedLat = pos.latitude;
        _taggedLng = pos.longitude;
      });
      await _updateGeoFence();
      return true;
    } catch (_) {
      return false;
    } finally {
      popup.close();
      _gettingGps = false;
    }
  }

  Future<void> _updateGeoFence() async {
    final double? lat = _taggedLat;
    final double? lng = _taggedLng;
    if (lat == null || lng == null) return;
    final String? existingFieldId = widget.fieldId?.trim();
    if (existingFieldId != null && existingFieldId.isNotEmpty) return;
    try {
      await _db.initialize();
      final List<Land> lands = await _db.getAllLands();
      final GeoFenceResult res = _geoFence.findLandForPoint(lat, lng, lands);
      if (!mounted) return;
      setState(() => _fence = res);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    final List<Detection> sortedDetections = List<Detection>.from(widget.detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final double overallConfidence = sortedDetections.isEmpty
        ? (widget.confidence.clamp(0, 100) / 100.0)
        : (sortedDetections
                .map((d) => d.confidence)
                .reduce((a, b) => a + b) /
            sortedDetections.length);
    final int overallPct = (overallConfidence * 100).round().clamp(0, 100);
    final double topConfidence = sortedDetections.isEmpty
        ? (widget.confidence.clamp(0, 100) / 100.0)
        : sortedDetections.first.confidence;
    final int topPct = (topConfidence * 100).round().clamp(0, 100);
    final bool hasMealybugHits =
        sortedDetections.isNotEmpty || widget.count > 0;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(widget.fieldName),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.imagePath != null && widget.imagePath!.isNotEmpty) ...[
              InkWell(
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _DetectionImageViewerScreen(
                        imagePath: widget.imagePath!,
                        imageBytes: widget.imageBytes,
                        detections: widget.detections,
                        originalImageWidth: widget.originalImageWidth,
                        originalImageHeight: widget.originalImageHeight,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  height: 220,
                  child: _DetectionPreviewImage(
                    imagePath: widget.imagePath!,
                    imageBytes: widget.imageBytes,
                    detections: widget.detections,
                    originalImageWidth: widget.originalImageWidth,
                    originalImageHeight: widget.originalImageHeight,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppTheme.primaryGreen,
                    AppTheme.secondaryGreen,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    fil ? 'Ang Prutas ay' : 'The Fruit is',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$overallPct%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (sortedDetections.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      fil
                          ? 'Pinakamataas: $topPct%'
                          : 'Highest: $topPct%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  Text(
                    hasMealybugHits
                        ? (fil
                            ? 'May mealybug infestation'
                            : 'Infested with Mealybug')
                        : (fil
                            ? 'Walang nakitang mealybug'
                            : 'No mealybugs detected'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(Icons.bug_report, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          fil
                              ? 'Bilang ng Mealybug: ${widget.count}'
                              : 'Mealybug Count: ${widget.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (sortedDetections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        fil ? 'Mga Deteksyon' : 'Detections',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...List<Widget>.generate(sortedDetections.length, (int i) {
                        final Detection d = sortedDetections[i];
                        final int pct = (d.confidence * 100).round().clamp(0, 100);
                        final String label = d.label ?? (fil ? 'Mealybug' : 'Mealybug');
                        return Padding(
                          padding: EdgeInsets.only(bottom: i == sortedDetections.length - 1 ? 0 : 10),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      Text(
                        fil
                            ? 'Ang porsyento ay kumpiyansa ng AI sa bawat deteksyon.'
                            : 'Percent is the AI confidence for each detection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await ensureOnline(context)) return;
                if (!context.mounted) return;
                final dynamic result = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute<Object?>(
                    builder: (_) => const LocationPickerScreen(),
                  ),
                );
                if (result != null && result is latlong2.LatLng && context.mounted) {
                  final latlong2.LatLng point = result;
                  setState(() {
                    _taggedLat = point.latitude;
                    _taggedLng = point.longitude;
                  });
                  await _updateGeoFence();
                }
              },
              icon: Icon(
                _taggedLat != null ? Icons.location_on : Icons.add_location_alt,
                color: AppTheme.primaryGreen,
              ),
              label: Text(
                _taggedLat != null
                    ? (fil
                        ? 'Lokasyon: ${_taggedLat!.toStringAsFixed(4)}, ${_taggedLng!.toStringAsFixed(4)}'
                        : 'Location: ${_taggedLat!.toStringAsFixed(4)}, ${_taggedLng!.toStringAsFixed(4)}')
                    : (fil
                        ? 'I-tag ang lokasyon kung saan kinunan ang larawan'
                        : 'Tag location where photo was taken'),
                style: const TextStyle(color: AppTheme.primaryGreen),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primaryGreen),
              ),
            ),
            const SizedBox(height: 12),
            _LocationPreviewCard(
              pulse: _pulse,
              lat: _taggedLat,
              lng: _taggedLng,
              onTap: () async {
                if (!await ensureOnline(context)) return;
                if (!context.mounted) return;
                final dynamic result = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute<Object?>(
                    builder: (_) => const LocationPickerScreen(),
                  ),
                );
                if (result != null && result is latlong2.LatLng && context.mounted) {
                  final latlong2.LatLng point = result;
                  setState(() {
                    _taggedLat = point.latitude;
                    _taggedLng = point.longitude;
                  });
                  await _updateGeoFence();
                }
              },
            ),
            if ((widget.fieldId == null || widget.fieldId!.trim().isEmpty) &&
                (_fence?.isInside ?? false) &&
                (_fence?.land?.landName.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fence,
                      color: AppTheme.primaryGreen.withValues(alpha: 0.9),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fil
                            ? 'Nasa loob ng field: ${_fence!.land!.landName}'
                            : 'Inside field boundary: ${_fence!.land!.landName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _saveDetection(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        fil ? 'I-save' : 'Save',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        side: const BorderSide(color: AppTheme.primaryGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child:
                          Text(
                        fil ? 'Ulit' : 'Retake',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDetection(BuildContext context) async {
    if (_saving) return;
    setState(() => _saving = true);

    // Make sure we try to tag a location before saving (works offline via last-known).
    await _ensureTaggedLocation(showUi: true);

    if (widget.imagePath == null || widget.imagePath!.isEmpty) {
      if (context.mounted) {
        Navigator.popUntil(context, (Route<dynamic> route) => route.isFirst);
      }
      setState(() => _saving = false);
      return;
    }
    final File file = File(widget.imagePath!);
    if (!await file.exists()) {
      if (context.mounted) {
        await ActionPopup.showError(
          context,
          message: 'Image file not found.',
        );
      }
      setState(() => _saving = false);
      return;
    }
    // Always save locally first so the app works offline.
    final bytes = await file.readAsBytes();
    final String localPath =
        await ImageStorageService().saveDetectionImage(bytes);

    // Enqueue for cloud sync when online.
    final db = DatabaseService();
    await db.initialize();

    final String userId =
        SupabaseClientProvider.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) {
      if (context.mounted) {
        await ActionPopup.showError(
          context,
          message: 'You must be signed in to save a capture.',
        );
      }
      setState(() => _saving = false);
      return;
    }
    final String? existingFieldId = widget.fieldId?.trim();
    final String effectiveFieldName = (existingFieldId != null &&
            existingFieldId.isNotEmpty)
        ? widget.fieldName
        : ((_fence?.isInside ?? false) &&
                (_fence?.land?.landName.trim().isNotEmpty ?? false))
            ? _fence!.land!.landName
            : widget.fieldName;
    await db.insertCapturedPhoto(
      localImagePath: localPath,
      fieldName: effectiveFieldName,
      confidence: widget.confidence,
      count: widget.count,
      detectionsJson: jsonEncode(
        widget.detections
            .map((d) => <String, dynamic>{
                  'left': d.left,
                  'top': d.top,
                  'width': d.width,
                  'height': d.height,
                  'confidence': d.confidence,
                  'classIndex': d.classIndex,
                  'label': d.label,
                })
            .toList(),
      ),
      fieldId: widget.fieldId,
      userId: userId,
      latitude: _taggedLat,
      longitude: _taggedLng,
    );
    await db.enqueueUpload(
      localImagePath: localPath,
      confidence: widget.confidence,
      count: widget.count,
      fieldId: widget.fieldId,
      latitude: _taggedLat,
      longitude: _taggedLng,
    );

    if (context.mounted) {
      context.read<AppState>().bumpCapturedPhotos();
    }

    // Kick off background sync (will no-op if offline).
    CloudSyncService(databaseService: db).syncInBackground();

    if (!context.mounted) return;
    final bool fil = context.read<AppState>().isFilipino;
    final bool online = await NetworkReachability.isOnline();
    if (!context.mounted) return;
    final String message = online
        ? (fil ? 'Na-save ang larawan.' : 'Picture saved.')
        : (fil
            ? 'Na-save nang offline. Ia-upload kapag online.'
            : 'Saved offline. Will upload when online.');

    final bool noGps = _taggedLat == null || _taggedLng == null;
    final String fullMessage = noGps
        ? '$message\n\n${fil ? 'Paalala: Na-save nang walang GPS sa mapa.' : 'Note: Saved without a GPS location on the map.'}'
        : message;

    await ActionPopup.showSuccessAutoDismiss(
      context,
      title: fil ? 'Na-save' : 'Saved',
      message: fullMessage,
      readSeconds: 3,
      countdownLabel: (int r) =>
          fil ? 'Magpapatuloy sa $r…' : 'Continuing in $r…',
    );
    if (!context.mounted) return;
    Navigator.popUntil(context, (Route<dynamic> route) => route.isFirst);
    if (mounted) setState(() => _saving = false);
  }
}

class _LocationPreviewCard extends StatelessWidget {
  const _LocationPreviewCard({
    required this.pulse,
    required this.lat,
    required this.lng,
    required this.onTap,
  });

  final Animation<double> pulse;
  final double? lat;
  final double? lng;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    final has = lat != null && lng != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 118,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppTheme.primaryGreen.withValues(alpha: 0.10),
                Colors.white,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MiniMapPainter(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: pulse,
                      builder: (context, _) {
                        final t = pulse.value;
                        final radius = 10 + (t * 10);
                        final alpha = (1.0 - t).clamp(0.0, 1.0);
                        return SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (has)
                                Container(
                                  width: radius * 2,
                                  height: radius * 2,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.primaryGreen.withValues(
                                      alpha: 0.18 * alpha,
                                    ),
                                  ),
                                ),
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: has
                                      ? AppTheme.primaryGreen
                                      : Colors.grey.shade400,
                                ),
                              ),
                              Icon(
                                Icons.location_on,
                                size: 22,
                                color: has
                                    ? AppTheme.primaryGreen
                                    : Colors.grey.shade500,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            has
                                ? (fil ? 'Naka-tag na lokasyon' : 'Tagged location')
                                : (fil
                                    ? 'Awtomatikong pagta-tag ng lokasyon…'
                                    : 'Auto-tagging location…'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            has
                                ? '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                                : (fil ? 'Pindutin para pumili sa mapa' : 'Tap to choose on map'),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: has
                                  ? AppTheme.textDark
                                  : AppTheme.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.textMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Subtle "map grid" + a couple of curvy "roads".
    const grid = 18.0;
    for (double x = 0; x < size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final road = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final p1 = Path()
      ..moveTo(0, size.height * 0.65)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.50,
        size.width * 0.42,
        size.height * 0.82,
        size.width * 0.72,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.44,
        size.width,
        size.height * 0.50,
      );
    canvas.drawPath(p1, road);

    final p2 = Path()
      ..moveTo(size.width * 0.08, 0)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.22,
        size.width * 0.22,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.12,
        size.height * 0.66,
        size.width * 0.20,
        size.height,
      );
    canvas.drawPath(p2, road);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DetectionPreviewImage extends StatefulWidget {
  const _DetectionPreviewImage({
    required this.imagePath,
    this.imageBytes,
    required this.detections,
    this.originalImageWidth,
    this.originalImageHeight,
  });

  final String imagePath;
  final Uint8List? imageBytes;
  final List<Detection> detections;
  final int? originalImageWidth;
  final int? originalImageHeight;

  @override
  State<_DetectionPreviewImage> createState() => _DetectionPreviewImageState();
}

class _DetectionPreviewImageState extends State<_DetectionPreviewImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _markerPulse;

  @override
  void initState() {
    super.initState();
    _markerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _markerPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double containerW = constraints.maxWidth;
          final double containerH = constraints.maxHeight;
          final double imageW = (widget.originalImageWidth ?? 1).toDouble();
          final double imageH = (widget.originalImageHeight ?? 1).toDouble();
          final double scale = math.min(containerW / imageW, containerH / imageH);
          final double drawnW = imageW * scale;
          final double drawnH = imageH * scale;
          final double offsetX = (containerW - drawnW) / 2;
          final double offsetY = (containerH - drawnH) / 2;

          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.04),
                  child: widget.imageBytes != null
                      ? Image.memory(
                          widget.imageBytes!,
                          fit: BoxFit.contain,
                        )
                      : Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.contain,
                        ),
                ),
              ),
              if (widget.detections.isNotEmpty)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _markerPulse,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _DetectionMarkerPainter(
                          detections: widget.detections,
                          imageOffset: Offset(offsetX, offsetY),
                          imageScale: scale,
                          pulse: _markerPulse.value,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DetectionImageViewerScreen extends StatelessWidget {
  const _DetectionImageViewerScreen({
    required this.imagePath,
    required this.imageBytes,
    required this.detections,
    required this.originalImageWidth,
    required this.originalImageHeight,
  });

  final String imagePath;
  final Uint8List? imageBytes;
  final List<Detection> detections;
  final int? originalImageWidth;
  final int? originalImageHeight;

  @override
  Widget build(BuildContext context) {
    final double availableH = MediaQuery.sizeOf(context).height - 140;
    final double viewerH = availableH > 240 ? availableH : 240;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Detection Preview'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: viewerH,
              child: _DetectionPreviewImage(
                imagePath: imagePath,
                imageBytes: imageBytes,
                detections: detections,
                originalImageWidth: originalImageWidth,
                originalImageHeight: originalImageHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionMarkerPainter extends CustomPainter {
  _DetectionMarkerPainter({
    required this.detections,
    required this.imageOffset,
    required this.imageScale,
    required this.pulse,
  });

  final List<Detection> detections;
  final Offset imageOffset;
  final double imageScale;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final double cx = imageOffset.dx + (d.left + d.width / 2) * imageScale;
      final double cy = imageOffset.dy + (d.top + d.height / 2) * imageScale;
      final double ringRadius = 8 + pulse * 7;
      final double alpha = (1.0 - pulse).clamp(0.0, 1.0);

      final ring = Paint()
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.42 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(cx, cy), ringRadius, ring);

      final dot = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), 4.5, dot);

      _drawConfidenceLabel(canvas, size, d, cx, cy);
    }
  }

  void _drawConfidenceLabel(
    Canvas canvas,
    Size canvasSize,
    Detection d,
    double cx,
    double cy,
  ) {
    final int pct = (d.confidence * 100).round().clamp(0, 100);
    final String text = '$pct%';

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const double padX = 6;
    const double padY = 4;
    final double bubbleW = tp.width + padX * 2;
    final double bubbleH = tp.height + padY * 2;

    // Prefer top-right of marker, clamp inside canvas.
    double x = cx + 10;
    double y = cy - bubbleH - 10;
    if (x + bubbleW > canvasSize.width) x = canvasSize.width - bubbleW - 6;
    if (x < 6) x = 6;
    if (y < 6) y = cy + 10;
    if (y + bubbleH > canvasSize.height) y = canvasSize.height - bubbleH - 6;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, bubbleW, bubbleH),
      const Radius.circular(10),
    );
    final Paint bg = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bg);

    // Small accent border for legibility.
    final Paint stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, stroke);

    tp.paint(canvas, Offset(x + padX, y + padY));
  }

  @override
  bool shouldRepaint(covariant _DetectionMarkerPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale ||
        oldDelegate.pulse != pulse;
  }
}

// --- Camera Mode Selector ---
class CameraModeSelector extends StatefulWidget {
  const CameraModeSelector({
    super.key,
    required this.fieldName,
    this.fieldId,
  });

  final String fieldName;
  final String? fieldId;

  @override
  State<CameraModeSelector> createState() => _CameraModeSelectorState();
}

class _CameraModeSelectorState extends State<CameraModeSelector> {
  bool _isCapturing = false;
  final ImagePicker _picker = ImagePicker();
  late final InferenceService _inferenceService;

  @override
  void initState() {
    super.initState();
    _inferenceService = InferenceService(config: AppConfig.balanced());
  }

  Future<void> _captureAndDetect() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null || !mounted) {
        setState(() => _isCapturing = false);
        return;
      }
      final String path = photo.path;
      int confidence = 0;
      int count = 0;
      List<Detection> detections = const <Detection>[];
      int? originalImageWidth;
      int? originalImageHeight;
      Uint8List? imageBytes;
      final BuildContext rootContext = context;
      bool scanDialogShown = false;
      try {
        if (rootContext.mounted) {
          showDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: (_) => const _ScanningDialog(),
          );
          scanDialogShown = true;
        }
        final File file = File(path);
        final List<int> bytes = await file.readAsBytes();
        imageBytes = Uint8List.fromList(bytes);
        await _inferenceService.initialize();
        final DetectionResult result =
            await _inferenceService.runInference(imageBytes);
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        count = result.detections.length;
        detections = result.detections;
        originalImageWidth = result.originalWidth;
        originalImageHeight = result.originalHeight;
        confidence = result.detections.isEmpty
            ? 0
            : (result.detections
                        .map((d) => d.confidence)
                        .reduce((a, b) => a + b) /
                    result.detections.length *
                    100)
                .round()
                .clamp(0, 100);
        if (count == 0 && mounted) {
          await ActionPopup.showInfo(
            context,
            title: context.read<AppState>().isFilipino
                ? 'Walang deteksyon'
                : 'No detections',
            message: _noDetectionsDetailMessage(context, result),
          );
        }
      } catch (e) {
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        // Make inference failures visible instead of silently showing 0%.
        AppLogger.error('Inference ERROR (camera)', e);
        if (mounted) {
          await ActionPopup.showError(
            context,
            message: 'Detection failed: $e',
          );
        }
      }
      if (!mounted) return;
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PhotoResultScreen(
            fieldName: widget.fieldName,
            imagePath: path,
            imageBytes: imageBytes,
            confidence: confidence,
            count: count,
            detections: detections,
            originalImageWidth: originalImageWidth,
            originalImageHeight: originalImageHeight,
            fieldId: widget.fieldId,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        await ActionPopup.showError(
          context,
          message: 'Could not capture photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fieldName),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text(
                          'Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _isCapturing ? null : _captureAndDetect,
                          icon: _isCapturing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(
                              _isCapturing ? 'Processing...' : 'Take Photo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

// --- Albums Screen ---
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({
    super.key,
    required this.fieldName,
    this.fieldId,
  });

  final String fieldName;
  final String? fieldId;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  bool _isProcessing = false;
  bool _loadingAlbums = true;
  List<({String name, int count})> _albums = <({String name, int count})>[];
  String? _loadError;
  final ImagePicker _picker = ImagePicker();
  late final InferenceService _inferenceService;

  @override
  void initState() {
    super.initState();
    _inferenceService = InferenceService(config: AppConfig.balanced());
    _loadDeviceAlbums();
  }

  Future<void> _loadDeviceAlbums() async {
    try {
      final PermissionState state =
          await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      if (!state.isAuth) {
        setState(() {
          _loadingAlbums = false;
          _loadError = 'Gallery permission denied';
        });
        return;
      }
      final List<AssetPathEntity> paths =
          await PhotoManager.getAssetPathList(type: RequestType.image);
      final List<({String name, int count})> list =
          <({String name, int count})>[];
      for (final AssetPathEntity path in paths) {
        final int count = await path.assetCountAsync;
        if (!mounted) return;
        list.add((name: path.name, count: count));
      }
      if (!mounted) return;
      setState(() {
        _albums = list;
        _loadingAlbums = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAlbums = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _pickAndDetect() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) {
        setState(() => _isProcessing = false);
        return;
      }
      final String path = picked.path;
      final latlong2.LatLng? mapPick =
          await _promptOptionalWherePhotoTaken(context);
      if (!mounted) {
        setState(() => _isProcessing = false);
        return;
      }
      final ({double? lat, double? lng}) pickGps =
          await _deviceGpsWhenGalleryPhotoChosen();
      final double? chosenTakeLat = mapPick?.latitude;
      final double? chosenTakeLng = mapPick?.longitude;
      final double? pickMomentLat = pickGps.lat;
      final double? pickMomentLng = pickGps.lng;

      int confidence = 0;
      int count = 0;
      List<Detection> detections = const <Detection>[];
      int? originalImageWidth;
      int? originalImageHeight;
      Uint8List? imageBytes;
      final BuildContext rootContext = context;
      bool scanDialogShown = false;
      try {
        if (rootContext.mounted) {
          showDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: (_) => const _ScanningDialog(),
          );
          scanDialogShown = true;
        }
        final List<int> bytes = await picked.readAsBytes();
        imageBytes = Uint8List.fromList(bytes);
        await _inferenceService.initialize();
        final DetectionResult result =
            await _inferenceService.runInference(imageBytes);
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        count = result.detections.length;
        detections = result.detections;
        originalImageWidth = result.originalWidth;
        originalImageHeight = result.originalHeight;
        confidence = result.detections.isEmpty
            ? 0
            : (result.detections
                        .map((d) => d.confidence)
                        .reduce((a, b) => a + b) /
                    result.detections.length *
                    100)
                .round()
                .clamp(0, 100);
        if (count == 0 && mounted) {
          await ActionPopup.showInfo(
            context,
            title: context.read<AppState>().isFilipino
                ? 'Walang deteksyon'
                : 'No detections',
            message: _noDetectionsDetailMessage(context, result),
          );
        }
      } catch (e) {
        if (scanDialogShown && rootContext.mounted) {
          Navigator.of(rootContext, rootNavigator: true).pop();
          scanDialogShown = false;
        }
        AppLogger.error('Inference ERROR (gallery)', e);
        if (mounted) {
          await ActionPopup.showError(
            context,
            message: 'Detection failed: $e',
          );
        }
      }
      if (!mounted) return;
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PhotoResultScreen(
            fieldName: widget.fieldName,
            imagePath: path,
            imageBytes: imageBytes,
            confidence: confidence,
            count: count,
            detections: detections,
            originalImageWidth: originalImageWidth,
            originalImageHeight: originalImageHeight,
            fieldId: widget.fieldId,
            takeLocationChosenLat: chosenTakeLat,
            takeLocationChosenLng: chosenTakeLng,
            pickMomentLat: pickMomentLat,
            pickMomentLng: pickMomentLng,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        await ActionPopup.showError(
          context,
          message: 'Could not pick image.',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: AppTheme.backgroundLight,
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : _loadingAlbums
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    if (_loadError != null) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _loadError!,
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      _buildAlbumTile(context, 'Pick from gallery', 0),
                    ] else if (_albums.isEmpty) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No albums found'),
                        ),
                      ),
                      _buildAlbumTile(context, 'Pick from gallery', 0),
                    ] else ...[
                      const Text(
                        'My Albums',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      for (final album in _albums)
                        _buildAlbumTile(context, album.name, album.count),
                    ],
                  ],
                ),
    );
  }

  Widget _buildAlbumTile(BuildContext context, String name, int count) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.photo_album, color: AppTheme.primaryGreen),
      ),
      title: Text(name),
      trailing: count > 0
          ? Text(
              count.toString(),
              style: const TextStyle(color: Colors.grey),
            )
          : null,
      onTap: _pickAndDetect,
    );
  }
}

class _ScanningDialog extends StatefulWidget {
  const _ScanningDialog();

  @override
  State<_ScanningDialog> createState() => _ScanningDialogState();
}

class _ScanningDialogState extends State<_ScanningDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fil ? 'Ina-analisa ang larawan…' : 'Analyzing picture…',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.black.withValues(alpha: 0.06),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.45),
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final y = _controller.value * 108;
                          return Positioned(
                            left: 6,
                            right: 6,
                            top: y,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryGreen
                                        .withValues(alpha: 0.55),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                fil
                    ? 'Tinitingnan ang mealybugs, pakihintay…'
                    : 'Detecting mealybugs, please wait…',
                style: const TextStyle(color: AppTheme.textMedium, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
