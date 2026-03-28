// Fields dashboard with field-level infestation stats.
library;

import 'package:flutter/material.dart';

import '../models/field_plot_models.dart';
import 'farm_details_screen.dart';
import 'field_selection_screen.dart';

class FieldsDashboardScreen extends StatefulWidget {
  const FieldsDashboardScreen({super.key});

  @override
  State<FieldsDashboardScreen> createState() => _FieldsDashboardScreenState();
}

class _FieldsDashboardScreenState extends State<FieldsDashboardScreen> {
  final List<FieldData> _fields = const <FieldData>[
    FieldData(name: 'Field 001', infestationPercentage: 52, imageCount: 145),
    FieldData(name: 'Field 002', infestationPercentage: 28, imageCount: 89),
  ];

  String _selectedField = 'Field 001';

  FieldData? _getSelectedField() {
    try {
      return _fields.firstWhere((FieldData f) => f.name == _selectedField);
    } catch (_) {
      return null;
    }
  }

  static Color _progressColor(double percentage) {
    if (percentage < 30) return Colors.green;
    if (percentage < 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final FieldData? selected = _getSelectedField();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Dashboard'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Take photo',
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const FieldSelectionScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const FarmDetailsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Text(
                  'Field:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedField,
                    isExpanded: true,
                    items: _fields
                        .map((FieldData field) => DropdownMenuItem<String>(
                              value: field.name,
                              child: Text(field.name),
                            ))
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() => _selectedField = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: selected == null
                ? const Center(child: Text('No field selected'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildFieldCard(selected),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard(FieldData field) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  field.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _progressColor(field.infestationPercentage),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${field.infestationPercentage.toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.image, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${field.imageCount} images taken',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: field.infestationPercentage / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(field.infestationPercentage),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mealybug infestation (field average)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
