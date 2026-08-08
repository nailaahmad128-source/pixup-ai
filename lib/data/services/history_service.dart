import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/history_item.dart';

/// Handles reading/writing the enhancement history to local storage.
class HistoryService {
  Future<List<HistoryItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.prefsHistory) ?? [];
    final items = raw
        .map((e) => HistoryItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> add(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.prefsHistory) ?? [];
    raw.add(jsonEncode(item.toJson()));
    await prefs.setStringList(AppConstants.prefsHistory, raw);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.prefsHistory) ?? [];
    raw.removeWhere((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return map['id'] == id;
    });
    await prefs.setStringList(AppConstants.prefsHistory, raw);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefsHistory);
  }
}
