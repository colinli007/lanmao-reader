import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:rule_engine/rule_engine.dart';

/// 一条书源日志。[sourceUrl] 为 null 时是存储层的落盘错误。
typedef SourceLogEntry = ({DateTime time, String? sourceUrl, String? field, String message});

/// 书源 JS 的调试日志和落盘错误（设计 D11）：只在内存里，最多 [capacity] 条，新的在前。
final class SourceLogBuffer extends ChangeNotifier {
  SourceLogBuffer({this.capacity = 500});

  final int capacity;
  final ListQueue<SourceLogEntry> _entries = ListQueue();

  /// 新的在前。
  List<SourceLogEntry> get entries => _entries.toList(growable: false);

  void addSourceLog(SourceLog log) => _add((time: DateTime.now(), sourceUrl: log.sourceUrl, field: log.field, message: log.message));

  void addStorageError(Object error) => _add((time: DateTime.now(), sourceUrl: null, field: null, message: '落盘失败：$error'));

  void _add(SourceLogEntry entry) {
    _entries.addFirst(entry);
    if (_entries.length > capacity) _entries.removeLast();
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
