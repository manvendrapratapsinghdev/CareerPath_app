import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService extends ChangeNotifier {
  final SharedPreferences _prefs;

  static const _key = 'locale_code';

  static const supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('bn'),
    Locale('te'),
    Locale('mr'),
    Locale('ta'),
    Locale('gu'),
    Locale('kn'),
    Locale('ml'),
    Locale('or'),
    Locale('pa'),
  ];

  static const localeNames = {
    'en': 'English',
    'hi': 'हिन्दी',
    'bn': 'বাংলা',
    'te': 'తెలుగు',
    'mr': 'मराठी',
    'ta': 'தமிழ்',
    'gu': 'ગુજરાતી',
    'kn': 'ಕನ್ನಡ',
    'ml': 'മലയാളം',
    'or': 'ଓଡ଼ିଆ',
    'pa': 'ਪੰਜਾਬੀ',
  };

  LocaleService(this._prefs);

  Locale get locale {
    final code = _prefs.getString(_key);
    if (code != null) {
      return Locale(code);
    }
    return const Locale('en');
  }

  Future<void> setLocale(Locale locale) async {
    await _prefs.setString(_key, locale.languageCode);
    notifyListeners();
  }
}
