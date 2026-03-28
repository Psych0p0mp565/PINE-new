// My Fields view (Compact 12): Fields | Reminders tabs, bottom nav.
library;

import 'package:flutter/material.dart';

import '../core/supabase_client.dart';
import '../core/theme.dart';
import 'main_dashboard_screen.dart';
import 'field_detail_screen.dart';
import 'permission_screens.dart';
import 'edit_field_screen.dart';

class FieldsListScreen extends StatelessWidget {
  const FieldsListScreen({super.key, this.initialField});

  final String? initialField;

  @override
  Widget build(BuildContext context) {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Fields'),
          backgroundColor: AppTheme.primaryGreen,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: <Tab>[
              Tab(text: 'Fields'),
              Tab(text: 'Reminders'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            uid == null
                ? _buildEmptyFields(context)
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: SupabaseClientProvider.instance.client
                        .from('fields')
                        .stream(primaryKey: const <String>['id'])
                        .eq('user_id', uid),
                    builder: (BuildContext context,
                        AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                      if (!snapshot.hasData || snapshot.hasError) {
                        return _buildEmptyFields(context);
                      }
                      final List<Map<String, dynamic>> docs = snapshot.data!;
                      if (docs.isEmpty) {
                        return _buildEmptyFields(context);
                      }
                      final List<Map<String, dynamic>> fields = docs
                          .map((Map<String, dynamic> data) {
                        return <String, dynamic>{
                          'fieldId': data['id'] as String,
                          'name': data['name'] as String? ?? 'Field',
                          'address': data['address'] as String? ?? '',
                        };
                      }).toList();
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: fields.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> field = fields[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Stack(
                              children: <Widget>[
                                ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  title: Text(
                                    field['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const SizedBox(height: 4),
                                      if ((field['address'] as String).isNotEmpty)
                                        Text(
                                          'Address: ${field['address']}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.push<void>(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => FieldDetailScreen(
                                          fieldId: field['fieldId'] as String,
                                          fieldName: field['name'] as String,
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
                                      final String? fieldId =
                                          field['fieldId'] as String?;
                                      return IconButton(
                                        icon: const Icon(Icons.edit),
                                        tooltip: 'Edit field',
                                        onPressed: () {
                                          if (fieldId == null) return;
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
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You Have No Reminders',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your first photo and carry out your daily survey routines.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const PhotoSourcePicker(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Add Photo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 2,
          onTap: (int index) {
            if (index == 0) {
              Navigator.pushAndRemoveUntil<void>(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const MainDashboardScreen()),
                (Route<dynamic> _) => false,
              );
            } else if (index == 1) {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const PhotoSourcePicker(),
                ),
              );
            } else if (index == 3) {
              Navigator.pushAndRemoveUntil<void>(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const MainDashboardScreen()),
                (Route<dynamic> _) => false,
              );
            }
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primaryGreen,
          unselectedItemColor: Colors.grey,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.bug_report), label: 'Diagnose'),
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'My Fields'),
            BottomNavigationBarItem(
                icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }

  static Widget _buildEmptyFields(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.landscape_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No fields yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a field from the location picker in More.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
