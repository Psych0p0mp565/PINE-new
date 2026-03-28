library;

import 'package:flutter/material.dart';
import '../core/supabase_client.dart';
import '../core/theme.dart';
import '../services/captured_photos_remote_sync.dart';
import '../services/database_service.dart';
import '../services/detection_service.dart';
import '../services/export_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/capture_thumbnail.dart';
import 'captured_photo_detail_screen.dart';
import '../widgets/online_required_dialog.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';

class CapturedPhotosScreen extends StatefulWidget {
  const CapturedPhotosScreen({super.key});

  @override
  State<CapturedPhotosScreen> createState() => _CapturedPhotosScreenState();
}

class _CapturedPhotosScreenState extends State<CapturedPhotosScreen> {
  late final DatabaseService _db;
  late final ImageStorageService _images;
  late final ExportService _export;
  late Future<List<Map<String, dynamic>>> _photosFuture;

  @override
  void initState() {
    super.initState();
    _db = DatabaseService();
    _images = ImageStorageService();
    _export = ExportService(databaseService: _db, imageStorageService: _images);
    _photosFuture = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await CapturedPhotosRemoteSync(databaseService: _db)
          .pullIntoLocalIfSignedIn();
      if (!mounted) return;
      setState(() {
        _photosFuture = _load();
      });
    });
  }

  Future<List<Map<String, dynamic>>> _load() async {
    await _db.initialize();
    final String? userId =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (userId == null) return const <Map<String, dynamic>>[];
    return _db.getCapturedPhotos(limit: 500, userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Captured Pictures'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await _export.exportCapturedPhotosZipNewOnly();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            },
            icon: const Icon(Icons.upload, color: Colors.white),
            label: const Text(
              'Export New',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              try {
                await _export.exportCapturedPhotosZipAll();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Export failed: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            },
            icon: const Icon(Icons.all_inbox, color: Colors.white),
            label: const Text(
              'Export All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _photosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(
              child: Text('No captured pictures yet.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final row = items[i];
              final int id = (row['id'] as num).toInt();
              final String fieldName = (row['field_name'] as String?) ?? 'Field';
              final String fieldLabel = fieldName;
              final int confidence = (row['confidence'] as num?)?.toInt() ?? 0;
              final int count = (row['count'] as num?)?.toInt() ?? 0;
              final String localPath = row['local_image_path'] as String;
              final String? remoteUrl = row['remote_image_url'] as String?;
              final String? remoteId = row['remote_id'] as String?;

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final bool? assign = await showModalBottomSheet<bool>(
                    context: context,
                    showDragHandle: true,
                    builder: (BuildContext sheetContext) {
                      return SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.visibility),
                                title: const Text('View details'),
                                onTap: () => Navigator.pop(sheetContext, false),
                              ),
                              ListTile(
                                leading: const Icon(Icons.map),
                                title: const Text('Assign to a field'),
                                subtitle: const Text(
                                  'Tag this capture to one of your fields',
                                ),
                                onTap: () => Navigator.pop(sheetContext, true),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  if (!context.mounted) return;
                  if (assign == true) {
                    if (!await ensureOnline(context)) return;
                    if (!context.mounted) return;
                    final Map<String, String>? picked =
                        await _pickField(context);
                    if (picked == null) return;
                    await _db.initialize();
                    await _db.updateCapturedPhotoField(
                      id: id,
                      fieldId: picked['id'],
                      fieldName: picked['name'] ?? 'Field',
                    );
                    if (remoteId != null && remoteId.isNotEmpty) {
                      await DetectionService().updateDetectionFieldAssignment(
                        detectionId: remoteId,
                        fieldId: picked['id'],
                      );
                    }
                    if (!context.mounted) return;
                    context.read<AppState>().bumpCapturedPhotos();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Assigned to field'),
                        backgroundColor: AppTheme.primaryGreen,
                      ),
                    );
                    return;
                  }

                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CapturedPhotoDetailScreen(
                        capturedPhotoId: id,
                      ),
                    ),
                  );
                },
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: captureThumbnail(
                              localImagePath: localPath,
                              remoteImageUrl: remoteUrl,
                              images: _images,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fieldLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Mealybug Count: $count',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Confidence: $confidence%',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<Map<String, String>?> _pickField(BuildContext context) async {
  final String? uid =
      SupabaseClientProvider.instance.client.auth.currentUser?.id;
  if (uid == null) return null;
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: SupabaseClientProvider.instance.client
              .from('fields')
              .stream(primaryKey: const <String>['id'])
              .eq('user_id', uid),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (rows.isEmpty) {
              return const SizedBox(
                height: 240,
                child: Center(child: Text('No fields yet.')),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = rows[i];
                final String id = (r['id'] as String?) ?? '';
                final String name = (r['name'] as String?) ?? 'Field';
                return ListTile(
                  leading: const Icon(Icons.landscape),
                  title: Text(name),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    <String, String>{'id': id, 'name': name},
                  ),
                );
              },
            );
          },
        ),
      );
    },
  );
}

