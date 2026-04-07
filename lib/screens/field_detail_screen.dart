// Single-field hub: stats from Supabase detections and Take Photo.
library;

import 'package:flutter/material.dart';

import '../core/supabase_client.dart';
import '../core/theme.dart';
import 'detections_map_screen.dart';
import 'permission_screens.dart';

/// Detail view for one field.
class FieldDetailScreen extends StatelessWidget {
  const FieldDetailScreen({
    super.key,
    required this.fieldId,
    required this.fieldName,
  });

  final String fieldId;
  final String fieldName;

  static DateTime? _parseTs(Map<String, dynamic> d) {
    final dynamic v = d['created_at'] ?? d['timestamp'];
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(fieldName),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseClientProvider.instance.client
            .from('detections')
            .stream(primaryKey: const <String>['id'])
            .eq('field_id', fieldId)
            .order('created_at', ascending: false),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load detections: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<Map<String, dynamic>> docs = snapshot.data!;
          final int imageCount = docs.length;
          final Map<String, dynamic>? latest =
              docs.isNotEmpty ? docs.first : null;

          double infestationRate = 0;
          if (latest != null) {
            final int count = (latest['count'] as num?)?.toInt() ?? 0;
            final bool hasBugs = latest['has_mealybugs'] == true;
            infestationRate = hasBugs && count > 0
                ? (count * 7).clamp(0, 100).toDouble()
                : (hasBugs ? 25.0 : 0.0);
          }

          final DateTime? lastT =
              latest != null ? _parseTs(latest) : null;
          String lastUpdated = 'Never';
          if (lastT != null) {
            final DateTime t = lastT.toLocal();
            final DateTime now = DateTime.now();
            if (t.day == now.day &&
                t.month == now.month &&
                t.year == now.year) {
              lastUpdated = 'Today';
            } else {
              lastUpdated = '${t.month}/${t.day}/${t.year}';
            }
          }

          final bool isNewField = imageCount == 0;

          return _buildBody(
            context,
            imageCount: imageCount,
            infestationRate: infestationRate,
            lastUpdated: lastUpdated,
            isNewField: isNewField,
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required int imageCount,
    required double infestationRate,
    required String lastUpdated,
    required bool isNewField,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
            child: isNewField
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'No detections yet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Run your first scan to see mealybug activity for this field.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: <Widget>[
                      const Text(
                        'The fruit is',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${infestationRate.round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Infested with Mealybug',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _buildStatItem(
                    Icons.image,
                    'Images Taken',
                    '$imageCount',
                  ),
                  _buildStatItem(
                    Icons.calendar_today,
                    'Last Updated',
                    lastUpdated,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoSourcePicker(
                      fieldName: fieldName,
                      fieldId: fieldId,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.camera_alt, size: 20),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DetectionsMapScreen(
                      fieldId: fieldId,
                      fieldName: fieldName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map_outlined, size: 20),
              label: const Text('View detections map'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryGreen,
                side: const BorderSide(color: AppTheme.primaryGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: <Widget>[
        Icon(icon, color: AppTheme.primaryGreen, size: 28),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textMedium,
          ),
        ),
      ],
    );
  }
}
