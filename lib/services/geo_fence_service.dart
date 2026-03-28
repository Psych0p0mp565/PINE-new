/// Geo-fencing service: point-in-polygon for land boundary matching.
///
/// All computation on-device. No cloud. Determines whether a
/// detection (lat, lng) falls inside any defined land polygon.
library;

import '../models/land.dart';

/// Result of geo-fence lookup.
class GeoFenceResult {
  const GeoFenceResult({
    this.land,
    this.landId,
    this.isInside = false,
  });

  final Land? land;
  final int? landId;
  final bool isInside;
}

/// Service for point-in-polygon geo-fencing.
class GeoFenceService {
  /// Finds which land (if any) contains the given point.
  ///
  /// Returns [GeoFenceResult] with land when inside a boundary,
  /// or isInside=false when outside all boundaries.
  GeoFenceResult findLandForPoint(
    double latitude,
    double longitude,
    List<Land> lands,
  ) {
    for (final land in lands) {
      if (_pointInPolygon(latitude, longitude, land.polygonCoordinates)) {
        return GeoFenceResult(
          land: land,
          landId: land.id,
          isInside: true,
        );
      }
    }
    return const GeoFenceResult(isInside: false);
  }

  /// Ray-casting point-in-polygon algorithm.
  /// Returns true if (lat, lng) is inside the polygon.
  bool _pointInPolygon(
    double lat,
    double lng,
    List<LatLngPoint> polygon,
  ) {
    if (polygon.length < 3) return false;

    var inside = false;
    final n = polygon.length;
    var j = n - 1;

    for (var i = 0; i < n; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      if (((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }
}
