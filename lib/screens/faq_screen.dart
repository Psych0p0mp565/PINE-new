// Frequently asked questions with expandable answers.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const List<Map<String, String>> _faqs = <Map<String, String>>[
    <String, String>{
      'question': 'How do I create an account?',
      'answer':
          'To create an account, navigate to the Sign-Up page, provide your username, full name, email address, and password, and agree to the terms and conditions. Once submitted, your account will be created, giving you access to the app\'s features.',
    },
    <String, String>{
      'question': 'How can I diagnose plant diseases?',
      'answer':
          'Use the "Diagnose" feature on the app\'s main navigation bar. You can either take a photo of your plant or upload an existing one for analysis. The app will process the image and provide insights, specifically detecting Mealybug Wilt Disease in pineapples.',
    },
    <String, String>{
      'question': 'Can I track multiple fields?',
      'answer':
          'Yes, the "My Fields" feature allows you to manage multiple fields. You can add fields and track data like crop health and survey history for each field.',
    },
    <String, String>{
      'question': 'What sign-in methods are supported?',
      'answer':
          'PINE supports email and password sign-in only. Sign in on the Login page with your registered email and password.',
    },
    <String, String>{
      'question': 'What do I do if I forget my password?',
      'answer':
          'On the Login page, select the "Forgot Password?" option. Enter your registered email address, and a password reset link will be sent to you.',
    },
    <String, String>{
      'question': 'How do I change the language of the app?',
      'answer':
          'Go to the "Settings" page and select "Language." Choose your preferred language from the list, and the app will update accordingly.',
    },
    <String, String>{
      'question': 'What kind of diseases can this app detect?',
      'answer':
          'Currently, the app specializes in detecting only one disease: Mealybug Wilt Disease in pineapples. Additional disease detection may be introduced in future updates.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('FAQ - Frequently Asked Questions'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _faqs.length,
        itemBuilder: (BuildContext context, int index) {
          return _buildFaqItem(_faqs[index]);
        },
      ),
    );
  }

  Widget _buildFaqItem(Map<String, String> faq) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          faq['question']!,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              faq['answer']!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
