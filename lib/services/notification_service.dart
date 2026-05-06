import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';
import 'database_service.dart';

/// Singleton that manages all local push notifications.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  // ─── Notification IDs ────────────────────────────────────────────────────

  static const _workReminderId = 1;
  static const _breakReminderId = 2;
  static const _goalBaseId = 100; // 100 + goal index

  // ─── Channel IDs ─────────────────────────────────────────────────────────

  static const _channelWork = 'tt_work_reminders';
  static const _channelBreak = 'tt_break_reminders';
  static const _channelGoals = 'tt_goal_achievements';

  static const _icon = 'ic_notification';

  bool _initialized = false;

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    // Set up timezone using Dart-native UTC offset — no platform plugin needed.
    // All scheduling is done in UTC; local time is derived from the offset.
    try {
      tz.initializeTimeZones();
      _initLocalTimezone();
    } catch (e) {
      debugPrint('[NotificationService] Timezone init failed: $e');
    }

    const androidInit = AndroidInitializationSettings(_icon);
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;

    // Re-schedule work reminder if enabled
    if (AppSettings.instance.notifyWork) {
      await scheduleWorkReminder();
    }
  }

  // ─── Work reminder ────────────────────────────────────────────────────────
  // Fires every day at 10:00 (local time) during the work window.

  Future<void> scheduleWorkReminder() async {
    if (kIsWeb || !_initialized) return;

    await cancelWorkReminder();
    if (!AppSettings.instance.notifyWork) return;

    try {
      await _plugin.zonedSchedule(
        _workReminderId,
        'Пора продуктивно поработать! 🚀',
        'Запусти таймер и начни продуктивный день.',
        _nextDailyOccurrence(hour: 10, minute: 0),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelWork,
            'Напоминания о работе',
            channelDescription:
                'Ежедневное напоминание о начале рабочего дня',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: _icon,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleWorkReminder error: $e');
    }
  }

  Future<void> cancelWorkReminder() async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(_workReminderId);
  }

  // ─── Break reminder ───────────────────────────────────────────────────────
  // Scheduled 60 min after timer starts; cancelled when timer stops.

  Future<void> scheduleBreakReminder() async {
    if (kIsWeb || !_initialized || !AppSettings.instance.notifyBreaks) return;

    try {
      final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 60));
      await _plugin.zonedSchedule(
        _breakReminderId,
        'Ты отлично потрудился! ☕',
        'Уже 60 минут без остановки — время для 5-минутного перерыва.',
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelBreak,
            'Напоминания о перерывах',
            channelDescription:
                'Напоминания сделать перерыв после длительной работы',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: _icon,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleBreakReminder error: $e');
    }
  }

  Future<void> cancelBreakReminder() async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(_breakReminderId);
  }

  // ─── Goal achievement ─────────────────────────────────────────────────────
  // Call after any session save. Notifies once per goal per day.

  Future<void> checkAndNotifyGoals() async {
    if (kIsWeb || !_initialized) return;

    try {
      final db = DatabaseService();
      final goals = await db.getAllGoals();
      if (goals.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();

      for (int i = 0; i < goals.length; i++) {
        final goal = goals[i];

        // Skip if already notified today for this category
        final key = 'goal_notified_${goal.categoryName}_$today';
        if (prefs.getBool(key) == true) continue;

        final todaySec =
            await db.getTodayDurationByCategory(goal.categoryName);
        final todayMin = todaySec / 60;

        if (goal.dailyMinutes > 0 && todayMin >= goal.dailyMinutes) {
          await _plugin.show(
            _goalBaseId + i,
            'Цель достигнута! 🎉',
            'Дневная цель «${goal.categoryName}» выполнена. Так держать!',
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channelGoals,
                'Достижение целей',
                channelDescription: 'Поздравления при выполнении дневной цели',
                importance: Importance.high,
                priority: Priority.high,
                icon: _icon,
              ),
            ),
          );
          await prefs.setBool(key, true);
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] checkAndNotifyGoals error: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Finds and sets the local timezone by matching the current UTC offset
  /// against the timezone database. Falls back to UTC on failure.
  void _initLocalTimezone() {
    final localOffset = DateTime.now().timeZoneOffset;
    final localAbbrev = DateTime.now().timeZoneName;

    tz.Location? best;
    for (final name in tz.timeZoneDatabase.locations.keys) {
      try {
        final loc = tz.getLocation(name);
        final tzNow = tz.TZDateTime.now(loc);
        if (tzNow.timeZoneOffset == localOffset) {
          best = loc;
          // Prefer an exact abbreviation match when available.
          if (tzNow.timeZoneName == localAbbrev) break;
        }
      } catch (_) {}
    }
    if (best != null) tz.setLocalLocation(best);
  }

  /// Returns the next occurrence of [hour]:[minute] in local time.
  /// If today's occurrence is already in the past, returns tomorrow's.
  tz.TZDateTime _nextDailyOccurrence({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);
}
