library;

import 'dart:async';
import 'dart:io';

import '../core/app_logger.dart';
import '../core/network_reachability.dart';
import '../core/supabase_client.dart';
import 'database_service.dart';
import 'detection_service.dart';
import 'image_storage_service.dart';

/// Background uploader for offline-saved detections.
///
/// - Always stores photos locally first.
/// - When online + authenticated, uploads image + writes Supabase (`detections` + Storage).
class CloudSyncService {
  CloudSyncService({
    DatabaseService? databaseService,
    ImageStorageService? imageStorageService,
    DetectionService? detectionService,
  })  : _db = databaseService ?? DatabaseService(),
        _images = imageStorageService ?? ImageStorageService(),
        _remote = detectionService ?? DetectionService();

  final DatabaseService _db;
  final ImageStorageService _images;
  final DetectionService _remote;

  bool _running = false;

  /// Attempts to upload pending items. Safe to call repeatedly.
  Future<void> syncPending({int limit = 10}) async {
    if (_running) return;
    _running = true;
    try {
      await _db.initialize();

      final String? uid =
          SupabaseClientProvider.instance.client.auth.currentUser?.id;
      if (uid == null) {
        return;
      }
      if (!await NetworkReachability.isOnline()) return;

      final pending = await _db.getPendingUploads(limit: limit);
      for (final row in pending) {
        final int id = row['id'] as int;
        final String localPath = row['local_image_path'] as String;
        final int confidence = (row['confidence'] as num).toInt();
        final int count = (row['count'] as num).toInt();
        final String? fieldId = row['field_id'] as String?;
        final double? lat =
            row['latitude'] == null ? null : (row['latitude'] as num).toDouble();
        final double? lng = row['longitude'] == null
            ? null
            : (row['longitude'] as num).toDouble();

        final File? file = await _images.getImageFile(localPath);
        if (file == null) {
          await _db.markUploadFailed(id, 'Local image missing: $localPath');
          continue;
        }

        try {
          final res = await _remote.saveDetection(
            imageFile: file,
            detectionResult: <String, dynamic>{
              'confidence': confidence,
              'count': count,
            },
            fieldId: fieldId,
            latitude: lat,
            longitude: lng,
          );
          final ok = res['success'] as bool? ?? false;
          if (ok) {
            final String? remoteId = res['detection_id']?.toString();
            final String? remoteUrl = res['image_url']?.toString();
            if (remoteId != null &&
                remoteId.isNotEmpty &&
                remoteUrl != null &&
                remoteUrl.isNotEmpty) {
              await _db.linkCapturedPhotoToRemoteUpload(
                userId: uid,
                localImagePath: localPath,
                remoteId: remoteId,
                remoteImageUrl: remoteUrl,
              );
            }
            await _db.markUploadSynced(id);
          } else {
            await _db.markUploadFailed(id, res['message']?.toString() ?? 'Error');
          }
        } catch (e) {
          AppLogger.error('CloudSyncService upload failed', e);
          await _db.markUploadFailed(id, e.toString());
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Convenience helper to run sync in background.
  void syncInBackground() {
    // ignore: discarded_futures
    unawaited(syncPending());
  }
}

