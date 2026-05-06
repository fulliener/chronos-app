import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton ChangeNotifier that holds all user preferences.
/// Subscribe via ListenableBuilder anywhere in the widget tree.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // ─── Persistence keys ─────────────────────────────────────────────────────

  static const _kDarkMode = 'is_dark_mode';
  static const _kNotifyWork = 'notify_work';
  static const _kNotifyBreaks = 'notify_breaks';

  /// v2 format stores "name:codepoint" per entry (e.g. "Книги:59517").
  /// Empty codepoint ("name:") means "use default icon".
  static const _kCategoriesV2 = 'categories_v2';

  // ─── Predefined selectable icon palette ───────────────────────────────────

  /// Ordered list of icons users can pick when creating a category.
  static const List<IconData> selectableIcons = [
    Icons.work_outline_rounded,        // Работа
    Icons.school_outlined,             // Учёба
    Icons.self_improvement_outlined,   // Медитация / Отдых
    Icons.fitness_center_outlined,     // Спорт
    Icons.menu_book,                   // Книга
    Icons.rocket_launch,               // Ракета / Проекты
    Icons.lightbulb_outline,           // Лампа / Идеи
    Icons.local_cafe,                  // Чашка / Перерыв
    Icons.music_note,                  // Музыка
    Icons.flight_takeoff,              // Путешествия
    Icons.palette_outlined,            // Творчество
    Icons.category_outlined,           // Другое
  ];

  // ─── State ────────────────────────────────────────────────────────────────

  ThemeMode _themeMode = ThemeMode.light;
  bool _notifyWork = true;
  bool _notifyBreaks = true;
  List<String> _categories = List.of(_defaultCategories);

  /// Custom icon codepoints keyed by category name.
  /// If a category has no entry here, the default Material icon is used.
  Map<String, int> _iconCodePoints = {};

  static const List<String> defaultCategories = [
    'Работа',
    'Учёба',
    'Отдых',
    'Спорт',
    'Другое',
  ];

  static const List<String> _defaultCategories = defaultCategories;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get notifyWork => _notifyWork;
  bool get notifyBreaks => _notifyBreaks;

  /// Immutable view of the current category list.
  List<String> get categories => List.unmodifiable(_categories);

  // ─── Icon resolution ──────────────────────────────────────────────────────

  /// Returns the [IconData] to use for [category].
  /// Uses the user-selected custom icon when available, otherwise falls back
  /// to the built-in default.
  IconData iconDataFor(String category) {
    final cp = _iconCodePoints[category];
    if (cp != null) return IconData(cp, fontFamily: 'MaterialIcons');
    return _builtinIconFor(category);
  }

  /// Default icon based on well-known category names.
  static IconData _builtinIconFor(String category) => switch (category) {
        'Работа' => Icons.work_outline_rounded,
        'Учёба' => Icons.school_outlined,
        'Отдых' => Icons.self_improvement_outlined,
        'Спорт' => Icons.fitness_center_outlined,
        _ => Icons.category_outlined,
      };

  /// Kept for backwards compatibility with call sites that haven't migrated yet.
  static IconData iconForCategory(String category) =>
      _builtinIconFor(category);

  // ─── Persistence ─────────────────────────────────────────────────────────

  /// Must be called once in main() before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final dark = prefs.getBool(_kDarkMode) ?? false;
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    _notifyWork = prefs.getBool(_kNotifyWork) ?? true;
    _notifyBreaks = prefs.getBool(_kNotifyBreaks) ?? true;

    final v2 = prefs.getStringList(_kCategoriesV2);
    if (v2 != null && v2.isNotEmpty) {
      _categories = [];
      _iconCodePoints = {};
      for (final entry in v2) {
        final sep = entry.lastIndexOf(':');
        if (sep == -1) {
          _categories.add(entry);
        } else {
          final name = entry.substring(0, sep);
          final cpStr = entry.substring(sep + 1);
          _categories.add(name);
          if (cpStr.isNotEmpty) {
            final cp = int.tryParse(cpStr);
            if (cp != null) _iconCodePoints[name] = cp;
          }
        }
      }
    } else {
      // Migration from old format (plain list of names, no icons).
      final legacy = prefs.getStringList('custom_categories');
      if (legacy != null && legacy.isNotEmpty) {
        _categories = List.of(legacy);
      }
    }
    // No notifyListeners here — called before runApp, tree not built yet.
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkMode, isDark);
    await prefs.setBool(_kNotifyWork, _notifyWork);
    await prefs.setBool(_kNotifyBreaks, _notifyBreaks);

    final v2 = _categories.map((name) {
      final cp = _iconCodePoints[name];
      return cp != null ? '$name:$cp' : '$name:';
    }).toList();
    await prefs.setStringList(_kCategoriesV2, v2);
  }

  // ─── Theme ────────────────────────────────────────────────────────────────

  Future<void> setDarkMode(bool value) async {
    _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _persist();
  }

  // ─── Notification prefs ───────────────────────────────────────────────────

  Future<void> setNotifyWork(bool value) async {
    _notifyWork = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setNotifyBreaks(bool value) async {
    _notifyBreaks = value;
    notifyListeners();
    await _persist();
  }

  // ─── Categories ───────────────────────────────────────────────────────────

  /// Adds a category with an optional custom icon.
  /// [iconCodePoint] should be the codePoint of any [IconData] from
  /// [selectableIcons]; pass null to use the built-in default.
  Future<void> addCategory(String name, {int? iconCodePoint}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_categories.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    _categories = [..._categories, trimmed];
    if (iconCodePoint != null) _iconCodePoints[trimmed] = iconCodePoint;
    notifyListeners();
    await _persist();
  }

  /// Prevents removal of the last remaining category.
  Future<void> removeCategory(String name) async {
    if (_categories.length <= 1) return;
    _categories = _categories.where((c) => c != name).toList();
    _iconCodePoints.remove(name);
    notifyListeners();
    await _persist();
  }
}
