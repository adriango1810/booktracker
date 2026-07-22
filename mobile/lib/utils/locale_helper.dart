import 'dart:ui';

class LocaleHelper {
  static String deviceLocale() {
    final locale = PlatformDispatcher.instance.locale;
    final language = locale.languageCode;
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) {
      return '$language-$country';
    }
    return language;
  }
}
