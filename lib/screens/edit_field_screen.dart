// Edit an existing field (name / preview image).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../core/theme.dart';
import '../widgets/online_required_dialog.dart';

class EditFieldScreen extends StatefulWidget {
  const EditFieldScreen({super.key, required this.fieldId});

  final String fieldId;

  @override
  State<EditFieldScreen> createState() => _EditFieldScreenState();
}

class _EditFieldScreenState extends State<EditFieldScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _address;
  String? _previewImagePath;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final Map<String, dynamic>? data = await SupabaseClientProvider
          .instance.client
          .from('fields')
          .select()
          .eq('id', widget.fieldId)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Field not found';
          _loading = false;
        });
        return;
      }

      if ((data['user_id'] as String?) != uid) {
        setState(() {
          _error = 'You do not have access to edit this field';
          _loading = false;
        });
        return;
      }

      setState(() {
        _nameController.text = (data['name'] as String?) ?? '';
        _address = data['address'] as String?;
        _previewImagePath = data['preview_image_path'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load field: $e';
        _loading = false;
      });
    }
  }

  Future<void> _capturePreview() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() => _previewImagePath = photo.path);
  }

  Future<void> _pickGalleryPreview() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() => _previewImagePath = photo.path);
  }

  Future<void> _save() async {
    if (_saving) return;
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter field name/number')),
      );
      return;
    }

    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    if (!await ensureOnline(context)) return;
    if (!mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await SupabaseClientProvider.instance.client
          .from('fields')
          .update(<String, dynamic>{
        'name': name,
        'address': _address ?? '',
        'preview_image_path': _previewImagePath,
        'user_id': uid,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.fieldId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Field updated'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to save field: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to save field: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Edit Field'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Field Name/Number',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter field name or number',
                            border: OutlineInputBorder(),
                            filled: true,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Field Preview',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _capturePreview,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Capture field preview'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryGreen,
                                  side: const BorderSide(
                                      color: AppTheme.primaryGreen),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickGalleryPreview,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text(
                                  'Pick from gallery',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryGreen,
                                  side: const BorderSide(
                                      color: AppTheme.primaryGreen),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_previewImagePath != null &&
                            File(_previewImagePath!).existsSync()) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_previewImagePath!),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ] else if (_previewImagePath != null) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'No preview image saved yet on this device.',
                            style: TextStyle(color: AppTheme.textMedium),
                          ),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _saving ? 'Saving...' : 'Save Changes',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
