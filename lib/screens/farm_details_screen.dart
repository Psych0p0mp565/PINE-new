// Add/edit farm information with field name and location.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/supabase_client.dart';
import '../core/theme.dart';
import 'location_picker_screen.dart';
import '../widgets/online_required_dialog.dart';

class FarmDetailsScreen extends StatefulWidget {
  const FarmDetailsScreen({super.key});

  @override
  State<FarmDetailsScreen> createState() => _FarmDetailsScreenState();
}

class _FarmDetailsScreenState extends State<FarmDetailsScreen> {
  final TextEditingController _fieldNameController = TextEditingController();
  String _selectedLocation = '';
  static const String _otherLocationValue = 'Other';
  bool _otherSelected = false;
  final TextEditingController _customLocationController =
      TextEditingController();
  double? _pickedLat;
  double? _pickedLng;
  String? _previewImagePath;
  final ImagePicker _picker = ImagePicker();

  static const List<String> _polomolokBarangays = <String>[
    'Poblacion (Polomolok)',
    'Cannery Site',
    'Magsaysay',
    'Bentung',
    'Crossing Palkan',
    'Glamang',
    'Kinilis',
    'Klinan 6',
    'Koronadal Proper',
    'Lam Caliaf',
    'Landan',
    'Lapu',
    'Lumakil',
    'Maligo',
    'Pagalungang',
    'Pakan',
    'Fulo',
    'Rubber',
    'Silway 7',
    'Silway 8',
    'Sulit',
    'Sumbakil',
    'Upper Klinan',
  ];

  @override
  void dispose() {
    _fieldNameController.dispose();
    _customLocationController.dispose();
    super.dispose();
  }

  Future<void> _capturePreview() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() => _previewImagePath = photo.path);
  }

  Future<void> _openMapPicker() async {
    if (!await ensureOnline(context)) return;
    if (!mounted) return;
    final dynamic result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute<Object?>(
        builder: (_) => const LocationPickerScreen(),
      ),
    );
    if (result != null && result is LatLng) {
      setState(() {
        _pickedLat = result.latitude;
        _pickedLng = result.longitude;
      });
    }
  }

  Future<void> _submit() async {
    final name = _fieldNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter field name or number')),
      );
      return;
    }
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to add a field')),
      );
      return;
    }
    if (!await ensureOnline(context)) return;
    if (!mounted) return;
    try {
      final String typedOther = _customLocationController.text.trim();
      // If user chose "Other" but didn't type anything, fall back to pinned GPS.
      final String effectiveLocation =
          _otherSelected ? typedOther : _selectedLocation;

      await SupabaseClientProvider.instance.client.from('fields').insert(
            <String, dynamic>{
              'user_id': uid,
              'name': name,
              'address': effectiveLocation.isNotEmpty
                  ? effectiveLocation
                  : (_pickedLat != null && _pickedLng != null)
                      ? '${_pickedLat!.toStringAsFixed(4)}, ${_pickedLng!.toStringAsFixed(4)}'
                      : '',
              'preview_image_path': _previewImagePath,
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Field saved'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(fil ? 'Mga Detalye ng Bukid' : 'Farm Details'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco,
                  size: 36,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              fil ? 'Pangalan/Bilang ng Bukid' : 'Field Name/Number',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _fieldNameController,
              decoration: InputDecoration(
                hintText: 'Enter field name or number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              fil ? 'Preview ng Bukid' : 'Field Preview',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _capturePreview,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      fil ? 'Kunan ang preview ng bukid' : 'Capture field preview',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryGreen,
                      side: const BorderSide(color: AppTheme.primaryGreen),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            if (_previewImagePath != null) ...[
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
            ],
            const SizedBox(height: 20),
            Text(
              fil ? 'Lokasyon (Barangay)' : 'Input Location',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue:
                  _selectedLocation.isEmpty ? null : _selectedLocation,
              hint: Text(fil ? 'Pumili ng barangay' : 'Select location'),
              items: _polomolokBarangays
                  .map((String location) => DropdownMenuItem<String>(
                        value: location,
                        child: Text(location),
                      ))
                  .followedBy(<DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: _otherLocationValue,
                      child: Text(fil ? 'Iba (type)' : 'Other (type)'),
                    ),
                  ])
                  .toList(),
              onChanged: (String? value) {
                final String v = value ?? '';
                setState(() {
                  if (v == _otherLocationValue) {
                    _otherSelected = true;
                    _selectedLocation = _otherLocationValue;
                    _customLocationController.clear();
                  } else {
                    _otherSelected = false;
                    _selectedLocation = v;
                    _customLocationController.clear();
                  }
                });
              },
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
            if (_otherSelected) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customLocationController,
                decoration: InputDecoration(
                  hintText: fil
                      ? 'I-type ang barangay / lokasyon'
                      : 'Type your barangay / location',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onChanged: (String value) {
                  // Keep dropdown selection as "Other"; we only store typed text on submit.
                },
              ),
            ],
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map),
                label: Text(fil ? 'o i-pin sa mapa' : 'or pin in the map'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryGreen,
                ),
              ),
            ),
            if (_pickedLat != null && _pickedLng != null) ...[
              const SizedBox(height: 8),
              Text(
                fil
                    ? 'Naka-pin: ${_pickedLat!.toStringAsFixed(4)}, ${_pickedLng!.toStringAsFixed(4)}'
                    : 'Pinned: ${_pickedLat!.toStringAsFixed(4)}, ${_pickedLng!.toStringAsFixed(4)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMedium,
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  fil ? 'I-save' : 'Submit',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
