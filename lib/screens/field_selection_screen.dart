// Choose a field before taking photos or viewing field details.
library;

import 'package:flutter/material.dart';

import '../core/supabase_client.dart';
import '../core/theme.dart';
import 'field_detail_screen.dart';
import 'edit_field_screen.dart';

class FieldSelectionScreen extends StatelessWidget {
  const FieldSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Choose a field'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: uid == null
          ? _buildEmpty(context)
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseClientProvider.instance.client
                  .from('fields')
                  .stream(primaryKey: const <String>['id'])
                  .eq('user_id', uid),
              builder: (BuildContext context,
                  AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                if (!snapshot.hasData || snapshot.hasError) {
                  return _buildEmpty(context);
                }
                final List<Map<String, dynamic>> docs = snapshot.data!;
                if (docs.isEmpty) {
                  return _buildEmpty(context);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> data = docs[index];
                    final String fieldId = data['id'] as String;
                    final String name =
                        data['name'] as String? ?? 'Field ${index + 1}';
                    final String address = data['address'] as String? ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    child: Stack(
                      children: <Widget>[
                        ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const SizedBox(height: 4),
                              if (address.isNotEmpty)
                                Text(
                                  address,
                                  style: const TextStyle(
                                    color: AppTheme.textMedium,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppTheme.textMedium,
                          ),
                          onTap: () {
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => FieldDetailScreen(
                                  fieldId: fieldId,
                                  fieldName: name,
                                ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Builder(
                            builder: (BuildContext editContext) {
                              return IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Edit field',
                                onPressed: () {
                                  Navigator.push<void>(
                                    editContext,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          EditFieldScreen(fieldId: fieldId),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    );
                  },
                );
              },
            ),
    );
  }

  static Widget _buildEmpty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.landscape_outlined,
              size: 64,
              color: AppTheme.textMedium,
            ),
            SizedBox(height: 16),
            Text(
              'No fields yet',
              style: TextStyle(
                fontSize: 18,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add a field from the location picker in More.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
