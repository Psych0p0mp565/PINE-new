/// SQLite database service for Land and Detection records.
///
/// All spatial data stored locally. No cloud sync.
library;

import 'dart:convert';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/detection_record.dart';
import '../models/land.dart';

/// Database service for offline storage of lands and detections.
class DatabaseService {
  static const _dbName = 'pine.db';
  static const _dbVersion = 8;

  Database? _db;

  /// Initializes the database. Call once at app startup.
  Future<void> initialize() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<bool> _columnExists(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final row in rows) {
      final name = row['name']?.toString();
      if (name == column) return true;
    }
    return false;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE land (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        land_name TEXT NOT NULL,
        polygon_coordinates TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE detection (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        land_id INTEGER,
        bug_count INTEGER NOT NULL,
        confidence_score REAL NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (land_id) REFERENCES land(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_detection_land_id ON detection(land_id)',
    );
    await db.execute(
      'CREATE INDEX idx_detection_timestamp ON detection(timestamp)',
    );

    await db.execute('''
      CREATE TABLE upload_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_image_path TEXT NOT NULL,
        confidence INTEGER NOT NULL,
        count INTEGER NOT NULL,
        field_id TEXT,
        latitude REAL,
        longitude REAL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_upload_queue_status_created ON upload_queue(status, created_at)',
    );

    await db.execute('''
      CREATE TABLE captured_photo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_image_path TEXT NOT NULL,
        field_name TEXT NOT NULL,
        field_id TEXT,
        confidence INTEGER NOT NULL,
        count INTEGER NOT NULL,
        detections_json TEXT,
        latitude REAL,
        longitude REAL,
        user_id TEXT,
        created_at TEXT NOT NULL,
        exported_at TEXT,
        remote_id TEXT,
        remote_image_url TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_captured_photo_created ON captured_photo(created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_captured_photo_user ON captured_photo(user_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_captured_photo_user_remote '
      'ON captured_photo(user_id, remote_id) WHERE remote_id IS NOT NULL '
      "AND remote_id != ''",
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE upload_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_image_path TEXT NOT NULL,
          confidence INTEGER NOT NULL,
          count INTEGER NOT NULL,
          field_id TEXT,
          plot_id TEXT,
          latitude REAL,
          longitude REAL,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_upload_queue_status_created ON upload_queue(status, created_at)',
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE captured_photo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_image_path TEXT NOT NULL,
          field_name TEXT NOT NULL,
          plot_name TEXT NOT NULL,
          field_id TEXT,
          plot_id TEXT,
          confidence INTEGER NOT NULL,
          count INTEGER NOT NULL,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_captured_photo_created ON captured_photo(created_at)',
      );
    }
    if (oldVersion < 4) {
      final hasExportedAt = await _columnExists(db, 'captured_photo', 'exported_at');
      if (!hasExportedAt) {
        await db.execute(
          'ALTER TABLE captured_photo ADD COLUMN exported_at TEXT',
        );
      }
    }

    if (oldVersion < 5) {
      final hasUserId = await _columnExists(db, 'captured_photo', 'user_id');
      if (!hasUserId) {
        await db.execute(
          'ALTER TABLE captured_photo ADD COLUMN user_id TEXT',
        );
      }
    }

    if (oldVersion < 6) {
      // Remove plot-related columns (SQLite 3.35+). Older engines: columns may remain unused.
      try {
        await db.execute('ALTER TABLE upload_queue DROP COLUMN plot_id');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE captured_photo DROP COLUMN plot_name');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE captured_photo DROP COLUMN plot_id');
      } catch (_) {}
    }

    if (oldVersion < 7) {
      final hasDetectionsJson =
          await _columnExists(db, 'captured_photo', 'detections_json');
      if (!hasDetectionsJson) {
        await db.execute(
          'ALTER TABLE captured_photo ADD COLUMN detections_json TEXT',
        );
      }
    }

    if (oldVersion < 8) {
      if (!await _columnExists(db, 'captured_photo', 'remote_id')) {
        await db.execute('ALTER TABLE captured_photo ADD COLUMN remote_id TEXT');
      }
      if (!await _columnExists(db, 'captured_photo', 'remote_image_url')) {
        await db.execute(
          'ALTER TABLE captured_photo ADD COLUMN remote_image_url TEXT',
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_captured_photo_user_remote '
        'ON captured_photo(user_id, remote_id) WHERE remote_id IS NOT NULL '
        "AND remote_id != ''",
      );
    }
  }

  // --- Land CRUD ---

  Future<int> insertLand(Land land) async {
    final db = _db!;
    final coordsJson = jsonEncode(
      land.polygonCoordinates.map((p) => p.toJson()).toList(),
    );
    return db.insert('land', {
      'land_name': land.landName,
      'polygon_coordinates': coordsJson,
      'created_at': (land.createdAt ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<List<Land>> getAllLands() async {
    final rows = await _db!.query('land', orderBy: 'created_at DESC');
    return rows.map(_landFromRow).toList();
  }

  Future<Land?> getLandById(int id) async {
    final rows = await _db!.query('land', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _landFromRow(rows.first);
  }

  Future<int> updateLand(Land land) async {
    if (land.id == null) return 0;
    final coordsJson = jsonEncode(
      land.polygonCoordinates.map((p) => p.toJson()).toList(),
    );
    return _db!.update(
      'land',
      {
        'land_name': land.landName,
        'polygon_coordinates': coordsJson,
      },
      where: 'id = ?',
      whereArgs: [land.id],
    );
  }

  Future<int> deleteLand(int id) async {
    await _db!.update(
      'detection',
      {'land_id': null},
      where: 'land_id = ?',
      whereArgs: [id],
    );
    return _db!.delete('land', where: 'id = ?', whereArgs: [id]);
  }

  Land _landFromRow(Map<String, dynamic> row) {
    final coordsList =
        jsonDecode(row['polygon_coordinates'] as String) as List<dynamic>;
    final coords = coordsList
        .map((e) => LatLngPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return Land(
      id: row['id'] as int,
      landName: row['land_name'] as String,
      polygonCoordinates: coords,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    );
  }

  // --- Detection CRUD ---

  Future<int> insertDetection(DetectionRecord record) async {
    return _db!.insert('detection', {
      'image_path': record.imagePath,
      'latitude': record.latitude,
      'longitude': record.longitude,
      'land_id': record.landId,
      'bug_count': record.bugCount,
      'confidence_score': record.confidenceScore,
      'timestamp': record.timestamp.toIso8601String(),
    });
  }

  Future<List<DetectionRecord>> getAllDetections() async {
    final rows = await _db!.query('detection', orderBy: 'timestamp DESC');
    return rows.map(_detectionFromRow).toList();
  }

  Future<List<DetectionRecord>> getDetectionsByLandId(int landId) async {
    final rows = await _db!.query(
      'detection',
      where: 'land_id = ?',
      whereArgs: [landId],
      orderBy: 'timestamp DESC',
    );
    return rows.map(_detectionFromRow).toList();
  }

  DetectionRecord _detectionFromRow(Map<String, dynamic> row) =>
      DetectionRecord(
        id: row['id'] as int,
        imagePath: row['image_path'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        landId: row['land_id'] as int?,
        bugCount: row['bug_count'] as int,
        confidenceScore: (row['confidence_score'] as num).toDouble(),
        timestamp: DateTime.parse(row['timestamp'] as String),
      );

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // --- Upload queue (offline sync) ---

  Future<int> enqueueUpload({
    required String localImagePath,
    required int confidence,
    required int count,
    String? fieldId,
    double? latitude,
    double? longitude,
  }) async {
    return _db!.insert('upload_queue', {
      'local_image_path': localImagePath,
      'confidence': confidence,
      'count': count,
      'field_id': fieldId,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'pending',
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingUploads({int limit = 20}) async {
    return _db!.query(
      'upload_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> markUploadSynced(int id) async {
    await _db!.update(
      'upload_queue',
      {
        'status': 'synced',
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markUploadFailed(int id, String error) async {
    await _db!.rawUpdate(
      '''
      UPDATE upload_queue
      SET status = ?,
          attempts = attempts + 1,
          last_error = ?
      WHERE id = ?
      ''',
      ['pending', error, id],
    );
  }

  // --- Captured photos (local gallery) ---

  Future<int> insertCapturedPhoto({
    required String localImagePath,
    required String userId,
    required String fieldName,
    required int confidence,
    required int count,
    String? detectionsJson,
    String? fieldId,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    String? remoteId,
    String? remoteImageUrl,
  }) async {
    return _db!.insert('captured_photo', {
      'local_image_path': localImagePath,
      'field_name': fieldName,
      'field_id': fieldId,
      'confidence': confidence,
      'count': count,
      'detections_json': detectionsJson,
      'latitude': latitude,
      'longitude': longitude,
      'user_id': userId,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'remote_id': remoteId,
      'remote_image_url': remoteImageUrl,
    });
  }

  /// Placeholder path for rows hydrated from Supabase (no local JPEG file).
  static const String remoteOnlyLocalPath = '_remote_';

  /// Inserts a gallery row backed by cloud storage (after reinstall / sync).
  Future<int> insertCapturedPhotoFromRemote({
    required String userId,
    required String remoteId,
    required String remoteImageUrl,
    required String fieldName,
    required int confidence,
    required int count,
    String? fieldId,
    double? latitude,
    double? longitude,
    required DateTime createdAt,
  }) async {
    return _db!.insert('captured_photo', {
      'local_image_path': remoteOnlyLocalPath,
      'field_name': fieldName,
      'field_id': fieldId,
      'confidence': confidence,
      'count': count,
      'latitude': latitude,
      'longitude': longitude,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'remote_id': remoteId,
      'remote_image_url': remoteImageUrl,
    });
  }

  Future<void> linkCapturedPhotoToRemoteUpload({
    required String userId,
    required String localImagePath,
    required String remoteId,
    required String remoteImageUrl,
  }) async {
    await _db!.update(
      'captured_photo',
      <String, Object?>{
        'remote_id': remoteId,
        'remote_image_url': remoteImageUrl,
      },
      where: 'user_id = ? AND local_image_path = ?',
      whereArgs: <Object?>[userId, localImagePath],
    );
  }

  Future<bool> hasCapturedPhotoForRemoteId(
    String userId,
    String remoteId,
  ) async {
    final List<Map<String, dynamic>> rows = await _db!.query(
      'captured_photo',
      columns: <String>['id'],
      where: 'user_id = ? AND remote_id = ?',
      whereArgs: <Object?>[userId, remoteId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasCapturedPhotoForRemoteImageUrl(
    String userId,
    String remoteImageUrl,
  ) async {
    final List<Map<String, dynamic>> rows = await _db!.query(
      'captured_photo',
      columns: <String>['id'],
      where: 'user_id = ? AND remote_image_url = ?',
      whereArgs: <Object?>[userId, remoteImageUrl],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getCapturedPhotos({
    int limit = 200,
    String? userId,
  }) async {
    return _db!.query(
      'captured_photo',
      where: userId == null ? null : 'user_id = ?',
      whereArgs: userId == null ? null : <Object?>[userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getUnexportedCapturedPhotos({
    int limit = 500,
    String? userId,
  }) async {
    final String where = userId == null
        ? 'exported_at IS NULL'
        : 'exported_at IS NULL AND user_id = ?';
    return _db!.query(
      'captured_photo',
      where: where,
      whereArgs: userId == null ? null : <Object?>[userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> markCapturedPhotosExported(List<int> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db!.update(
      'captured_photo',
      {'exported_at': now},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<Map<String, dynamic>?> getCapturedPhotoById(int id) async {
    final rows =
        await _db!.query('captured_photo', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> updateCapturedPhotoField({
    required int id,
    required String fieldName,
    String? fieldId,
  }) async {
    await _db!.update(
      'captured_photo',
      <String, Object?>{
        'field_name': fieldName,
        'field_id': fieldId,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
