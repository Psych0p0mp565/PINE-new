/// Shared map tile URLs for flutter_map.
///
/// [esriWorldImagery] — Esri World Imagery (RGB aerial / satellite). Tiles are
/// refreshed on Esri’s schedule; there is no single “live” public tile URL.
/// For provider-specific freshness, you’d need your own keyed service (Mapbox,
/// Google Maps Platform, etc.).
library;

abstract final class MapTiles {
  /// Global satellite / aerial imagery (no API key; suitable for field drawing).
  static const String esriWorldImagery =
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  static const String openStreetMap =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const String esriTerrain =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Physical_Map/MapServer/tile/{z}/{y}/{x}';

  /// Typical max zoom for Esri imagery in this app.
  static const int maxZoomSatellite = 19;
}
