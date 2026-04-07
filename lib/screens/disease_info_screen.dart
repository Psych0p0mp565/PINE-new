// Disease information and education (Compact 16).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import 'disease_detail_screen.dart';
import 'disease_by_category_screen.dart';
import 'educational_content_screen.dart';

class DiseaseInfoScreen extends StatelessWidget {
  const DiseaseInfoScreen({super.key});

  static const List<Map<String, dynamic>> _diseases = <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'Machete Disease',
      'description': 'Mealybug Wilt of Pineapple (MWOP)',
      'category': 'Common Diseases'
    },
    <String, dynamic>{
      'name': 'Heart Rot',
      'description': 'Phytophthora spp.',
      'category': 'Common Diseases'
    },
    <String, dynamic>{
      'name': 'Fusariosis',
      'description': 'Fusarium subglutinans f. sp. ananas',
      'category': 'Common Diseases'
    },
    <String, dynamic>{
      'name': 'Pineapple Soft Rot',
      'description': 'Erwinia chrysanthemi',
      'category': 'Common Diseases'
    },
    <String, dynamic>{
      'name': 'Pineapple Anthracnose',
      'description': 'Colletotrichum gloeosporioides',
      'category': 'Common Diseases'
    },
    <String, dynamic>{
      'name': 'Disease of the whole Plant',
      'description': '',
      'category': 'By Parts'
    },
    <String, dynamic>{
      'name': 'Disease by Fruit',
      'description': '',
      'category': 'By Parts'
    },
    <String, dynamic>{
      'name': 'Disease caused by Pests',
      'description': '',
      'category': 'By Parts'
    },
    <String, dynamic>{
      'name': 'Disease by Leaves',
      'description': '',
      'category': 'By Parts'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(fil ? 'Impormasyon sa Sakit' : 'Disease Information'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              fil ? 'Pangkalahatang Impormasyon' : 'General Info',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(
                      fil
                          ? 'Paano kilalanin ang pinya'
                          : 'How to identify pineapples',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EducationalContentScreen.identifyingPineapples(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: Text(
                      fil
                          ? 'Pagkakaiba ng mga uri ng pinya'
                          : 'Difference between species of pineapples',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EducationalContentScreen.speciesDifferences(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: Text(
                      fil
                          ? 'Bakit magkakaiba ang itsura ng pinya'
                          : 'Why pineapples look different',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EducationalContentScreen.whyDifferent(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              fil ? 'Karaniwang Sakit' : 'Common Diseases',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            ..._diseases
                .where((Map<String, dynamic> d) =>
                    d['category'] == 'Common Diseases')
                .map((Map<String, dynamic> disease) =>
                    _buildDiseaseCard(context, disease)),
            const SizedBox(height: 24),
            Text(
              fil
                  ? 'Tuklasin ang mga Sakit ayon sa Bahagi'
                  : 'Explore Diseases by parts',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _diseases
                  .where(
                      (Map<String, dynamic> d) => d['category'] == 'By Parts')
                  .map((Map<String, dynamic> disease) =>
                      _buildChip(context, disease['name'] as String))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiseaseCard(BuildContext context, Map<String, dynamic> disease) {
    final String name = disease['name'] as String;
    final String desc = disease['description'] as String;
    final Widget? detailScreen = _getDetailScreenForCommonDisease(name);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        subtitle: desc.isNotEmpty
            ? Text(
                desc,
                style: const TextStyle(
                  color: AppTheme.textMedium,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMedium),
        onTap: detailScreen != null
            ? () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => detailScreen),
                );
              }
            : null,
      ),
    );
  }

  Widget? _getDetailScreenForCommonDisease(String name) {
    if (name == 'Machete Disease') return DiseaseDetailScreen.machete();
    if (name == 'Heart Rot') return DiseaseDetailScreen.heartRot();
    if (name == 'Fusariosis') return DiseaseDetailScreen.fusariosis();
    if (name == 'Pineapple Soft Rot') return DiseaseDetailScreen.softRot();
    if (name == 'Pineapple Anthracnose') {
      return DiseaseDetailScreen.anthracnose();
    }
    return null;
  }

  Widget _buildChip(BuildContext context, String label) {
    final Widget? categoryScreen = _getCategoryScreenForPart(label);
    return FilterChip(
      label: Text(label, style: const TextStyle(color: AppTheme.textDark)),
      onSelected: categoryScreen != null
          ? (bool _) {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => categoryScreen),
              );
            }
          : (bool _) {},
      backgroundColor: AppTheme.surfaceWhite,
      selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
    );
  }

  Widget? _getCategoryScreenForPart(String label) {
    if (label == 'Disease of the whole Plant') {
      return DiseaseByCategoryScreen.wholePlant();
    }
    if (label == 'Disease by Fruit') return DiseaseByCategoryScreen.fruit();
    if (label == 'Disease caused by Pests') {
      return DiseaseByCategoryScreen.pests();
    }
    if (label == 'Disease by Leaves') return DiseaseByCategoryScreen.leaves();
    return null;
  }
}
