import 'package:flutter/material.dart';
import '../data/services/settings_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._settingsService) {
    _load();
  }

  final SettingsService _settingsService;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;
  bool get isDarkMode => _mode == ThemeMode.dark;

  Future<void> _load() async {
    final saved = await _settingsService.getDarkMode();
    if (saved != null) {
      _mode = saved ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    }
  }

  Future<void> setDarkMode(bool value) async {
    _mode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _settingsService.setDarkMode(value);
  }
}
