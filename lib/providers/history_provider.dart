import 'package:flutter/material.dart';
import '../data/models/history_item.dart';
import '../data/services/history_service.dart';

class HistoryProvider extends ChangeNotifier {
  HistoryProvider(this._service) {
    refresh();
  }

  final HistoryService _service;

  List<HistoryItem> _items = [];
  bool _loading = true;

  List<HistoryItem> get items => _items;
  bool get isLoading => _loading;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    _items = await _service.getAll();
    _loading = false;
    notifyListeners();
  }

  Future<void> add(HistoryItem item) async {
    await _service.add(item);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _service.delete(id);
    await refresh();
  }
}
