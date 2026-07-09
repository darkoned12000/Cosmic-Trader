import 'package:flutter/material.dart';

enum LogType {
  info,
  success,
  warning,
  error,
  combat,
  trade,
  movement,
  system,
}

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogType type;

  LogEntry({
    required this.timestamp,
    required this.message,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        'type': type.name,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        message: json['message'] as String,
        type: LogType.values.byName(json['type'] as String),
      );
}

class ActionLogProvider extends ChangeNotifier {
  static ActionLogProvider get global => _instance ??= ActionLogProvider._();
  static ActionLogProvider? _instance;

  ActionLogProvider._();

  static const int _maxEntries = 200;

  final List<LogEntry> _entries = [];
  final Set<LogType> _visibleTypes = LogType.values.toSet();

  List<LogEntry> get entries =>
      _entries.where((e) => _visibleTypes.contains(e.type)).toList();

  int get rawCount => _entries.length;

  Set<LogType> get visibleTypes => _visibleTypes;

  bool isVisible(LogType type) => _visibleTypes.contains(type);

  void showAllTypes() {
    _visibleTypes.addAll(LogType.values);
    notifyListeners();
  }

  void hideAllTypes() {
    _visibleTypes.clear();
    notifyListeners();
  }

  void toggleType(LogType type) {
    if (_visibleTypes.contains(type)) {
      _visibleTypes.remove(type);
    } else {
      _visibleTypes.add(type);
    }
    notifyListeners();
  }

  void add(String message, LogType type) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      type: type,
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }

  // Convenience methods
  void info(String message) => add(message, LogType.info);
  void success(String message) => add(message, LogType.success);
  void warning(String message) => add(message, LogType.warning);
  void error(String message) => add(message, LogType.error);
  void combat(String message) => add(message, LogType.combat);
  void trade(String message) => add(message, LogType.trade);
  void movement(String message) => add(message, LogType.movement);
  void system(String message) => add(message, LogType.system);
}
