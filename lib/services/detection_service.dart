/// Saves detection results and images to Supabase (Storage + Postgres).
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

class DetectionService {
  DetectionService({SupabaseClient? client})
      : _client = client ?? SupabaseClientProvider.instance.client;

  final SupabaseClient _client;

  /// Saves a detection: uploads image to Storage, writes metadata to `detections`.
  Future<Map<String, dynamic>> saveDetection({
    required File imageFile,
    required Map<String, dynamic> detectionResult,
    String? fieldId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final String? uid = _client.auth.currentUser?.id;
      if (uid == null) {
        return <String, dynamic>{
          'success': false,
          'message': 'User not authenticated',
        };
      }
      final String? effectiveFieldId = fieldId?.trim();

      final String path =
          '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _client.storage.from('detections').upload(
            path,
            imageFile,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      final String imageUrl =
          _client.storage.from('detections').getPublicUrl(path);

      final int count = (detectionResult['count'] as num?)?.toInt() ?? 0;
      final bool hasMealybugs = count > 0;

      final Map<String, dynamic> row = <String, dynamic>{
        'user_id': uid,
        'image_url': imageUrl,
        'confidence': detectionResult['confidence'],
        'count': count,
        'has_mealybugs': hasMealybugs,
      };
      if (effectiveFieldId != null && effectiveFieldId.isNotEmpty) {
        row['field_id'] = effectiveFieldId;
      }
      if (latitude != null && longitude != null) {
        row['latitude'] = latitude;
        row['longitude'] = longitude;
      }

      final Map<String, dynamic> inserted = await _client
          .from('detections')
          .insert(row)
          .select('id, image_url')
          .single();

      if (effectiveFieldId != null && effectiveFieldId.isNotEmpty) {
        await _client.from('fields').update(<String, dynamic>{
          'image_count': await _incrementFieldImageCount(effectiveFieldId),
          'last_detection': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', effectiveFieldId);
      }

      return <String, dynamic>{
        'success': true,
        'message': effectiveFieldId != null && effectiveFieldId.isNotEmpty
            ? 'Detection saved successfully'
            : 'Detection saved (not linked to a field)',
        'detection_id': inserted['id']?.toString(),
        'image_url': inserted['image_url']?.toString() ?? imageUrl,
      };
    } on StorageException catch (e) {
      return <String, dynamic>{
        'success': false,
        'message': 'Storage error: ${e.message}',
      };
    } on PostgrestException catch (e) {
      return <String, dynamic>{
        'success': false,
        'message': 'Database error: ${e.message}',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'message': 'Error saving detection: $e',
      };
    }
  }

  /// Updates which field a saved detection is linked to (RLS: own rows only).
  Future<void> updateDetectionFieldAssignment({
    required String detectionId,
    String? fieldId,
  }) async {
    await _client.from('detections').update(<String, dynamic>{
      'field_id': fieldId,
    }).eq('id', detectionId);
  }

  Future<int> _incrementFieldImageCount(String fieldId) async {
    final Map<String, dynamic>? row = await _client
        .from('fields')
        .select('image_count')
        .eq('id', fieldId)
        .maybeSingle();
    final int cur = (row?['image_count'] as num?)?.toInt() ?? 0;
    return cur + 1;
  }

  /// Stream of detection rows for a field, newest first (by `created_at`).
  Stream<List<Map<String, dynamic>>> getDetectionsForField(String fieldId) {
    return _client
        .from('detections')
        .stream(primaryKey: const <String>['id'])
        .eq('field_id', fieldId)
        .order('created_at', ascending: false);
  }
}
