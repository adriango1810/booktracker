import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const _autoOpenKey = 'auto_open_goodreads';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> create() async {
    return PreferencesService(await SharedPreferences.getInstance());
  }

  bool getAutoOpenGoodreads({required bool defaultValue}) {
    return _prefs.getBool(_autoOpenKey) ?? defaultValue;
  }

  Future<void> setAutoOpenGoodreads(bool value) async {
    await _prefs.setBool(_autoOpenKey, value);
  }
}
