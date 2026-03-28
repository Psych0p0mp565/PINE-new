/// Maps exceptions to short, user-friendly messages for UI.
///
/// Avoids exposing raw exception text (e.g. stack traces) to users.
library;

/// Returns a user-friendly message for [error] when shown in the UI.
String userFacingMessage(Object? error) {
  if (error == null) return 'Something went wrong.';
  final String msg = error.toString().toLowerCase();
  if (msg.contains('camera') || msg.contains('cameraexception')) {
    return 'Camera error. Please check permissions and try again.';
  }
  if (msg.contains('permission') || msg.contains('denied')) {
    return 'Permission denied. Please enable in Settings.';
  }
  if (msg.contains('location') || msg.contains('gps') || msg.contains('geolocator')) {
    return 'Could not get location. Check GPS and permissions.';
  }
  if (msg.contains('model') || msg.contains('interpreter') || msg.contains('tflite')) {
    return 'Detection model failed to load. Try restarting the app.';
  }
  if (msg.contains('decode') || msg.contains('image')) {
    return 'Could not process image. Try another photo.';
  }
  if (msg.contains('network') || msg.contains('socket') || msg.contains('connection')) {
    return 'Network error. Check your connection.';
  }
  // Fallback: short generic message (avoid raw exception)
  return 'Something went wrong. Please try again.';
}
