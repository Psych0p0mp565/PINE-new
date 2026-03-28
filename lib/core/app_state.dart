library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple global app state for auth-related flags.
///
/// This is intentionally minimal and can be extended to cover more flows
/// (e.g., dashboard filters, lands selection) as the app grows.
class AppState extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _languageCode = 'en';
  int _capturedPhotosRevision = 0;

  bool get isLoggedIn => _isLoggedIn;
  String get languageCode => _languageCode;
  bool get isFilipino => _languageCode == 'fil';
  int get capturedPhotosRevision => _capturedPhotosRevision;

  void bumpCapturedPhotos() {
    _capturedPhotosRevision++;
    notifyListeners();
  }

  void setLoggedIn(bool value) {
    if (_isLoggedIn == value) return;
    _isLoggedIn = value;
    notifyListeners();
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language_code') ?? 'en';
    if (_languageCode != code) {
      _languageCode = code;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
  }
}

