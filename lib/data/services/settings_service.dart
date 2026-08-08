import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

class SettingsService {
  Future<bool?> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(AppConstants.prefsDarkMode)) return null;
    return prefs.getBool(AppConstants.prefsDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefsDarkMode, value);
  }
}
