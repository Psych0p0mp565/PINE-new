// Terms of Use screen for Pine-Sight / PINE app.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, this.showAcceptButton = true});

  final bool showAcceptButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Terms of Use'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Terms of Use',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'By accessing or using this website/application, you agree to be bound by the following terms and conditions (\'Terms of Use\'). If you do not agree to these Terms of Use, please do not use this site or application.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    '1. Acceptance of Terms',
                    'By accessing or using Pine-Sight (the Service), you agree to comply with and be bound by these Terms of Use. If you do not agree with any part of these terms, you must not use the Service.',
                  ),
                  _buildSection(
                    '2. Use of Service',
                    'You agree to use the Service only for lawful purposes and in accordance with these Terms of Use. You are responsible for your content and use of the Service.',
                  ),
                  _buildSection(
                    '3. Account Registration',
                    'You may be required to create an account. You agree to provide accurate information and maintain confidentiality of your credentials.',
                  ),
                  _buildSection(
                    '4. Prohibited Activities',
                    'You agree not to: use the Service for illegal or unauthorized purposes; attempt to interfere with the proper working of the Service; or upload, post, or transmit harmful, offensive, or inappropriate content.',
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: showAcceptButton
                        ? ElevatedButton(
                            onPressed: () async {
                              final SharedPreferences prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('terms_accepted', true);
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Accept & Continue'),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
