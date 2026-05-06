import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../models/analytics_report.dart';
import 'database_service.dart';

/// Calculates smart productivity insights from the local SQLite database.
class AnalyticsService {
  final _db = DatabaseService();

  Future<AnalyticsReport> generateReport() async {
    final now = DateTime.now();
    final results = await Future.wait([
      _computeTrend(now),
      _computeGoalForecast(now),
      _computeBurnout(now),
      _computePeakProductivity(now),
    ]);
    return AnalyticsReport(
      trendInsight: results[0],
      goalForecast: results[1],
      burnoutWarning: results[2],
      peakProductivity: results[3],
    );
  }

  // ─── 1. Trend Analysis ────────────────────────────────────────────────────

  Future<InsightItem?> _computeTrend(DateTime now) async {
    final db = await _db.database;
    final thisMonday = _monday(now);
    final prevMonday = thisMonday.subtract(const Duration(days: 7));

    final cur = await _sumSeconds(db, thisMonday, now);
    final prev = await _sumSeconds(db, prevMonday, thisMonday);

    if (prev == 0 && cur == 0) return null;

    if (prev == 0) {
      return const InsightItem(
        icon: Icons.trending_up_rounded,
        title: 'Тренд продуктивности',
        message: 'На этой неделе вы активно начали работать — продолжайте в том же духе!',
        type: InsightType.positive,
      );
    }

    final pct = ((cur - prev) / prev * 100).round();
    if (pct >= 5) {
      return InsightItem(
        icon: Icons.trending_up_rounded,
        title: 'Тренд продуктивности',
        message: 'На этой неделе вы на $pct% продуктивнее, чем на прошлой.',
        type: InsightType.positive,
      );
    }
    if (pct <= -5) {
      return InsightItem(
        icon: Icons.trending_down_rounded,
        title: 'Тренд продуктивности',
        message: 'На этой неделе вы на ${pct.abs()}% менее продуктивны, чем на прошлой.',
        type: InsightType.neutral,
      );
    }
    return const InsightItem(
      icon: Icons.trending_flat_rounded,
      title: 'Тренд продуктивности',
      message: 'Ваша продуктивность на уровне прошлой недели.',
      type: InsightType.neutral,
    );
  }

  // ─── 2. Goal Forecast ─────────────────────────────────────────────────────

  Future<InsightItem?> _computeGoalForecast(DateTime now) async {
    final goals = await _db.getAllGoals();
    final weeklyGoals = goals.where((g) => g.weeklyMinutes > 0).toList();
    if (weeklyGoals.isEmpty) return null;

    final db = await _db.database;
    final thisMonday = _monday(now);
    final elapsedSec = now.difference(thisMonday).inSeconds;
    if (elapsedSec < 3600) return null; // too early in the week to forecast

    for (final goal in weeklyGoals) {
      final currentSec =
          await _sumSecondsByCategory(db, goal.categoryName, thisMonday, now);
      final goalSec = goal.weeklyMinutes * 60;

      if (currentSec >= goalSec) {
        return InsightItem(
          icon: Icons.check_circle_outline_rounded,
          title: 'Цель «${goal.categoryName}» достигнута!',
          message:
              'Вы уже выполнили недельную цель по категории «${goal.categoryName}». Отличная работа!',
          type: InsightType.positive,
        );
      }

      if (currentSec == 0) continue;

      // rate: seconds of tracked work per real elapsed second
      final rate = currentSec / elapsedSec;
      final remainingSec = goalSec - currentSec;
      final remainingRealSec = (remainingSec / rate).round();
      final forecastDt = now.add(Duration(seconds: remainingRealSec));

      final thisSunday = thisMonday.add(const Duration(days: 7));
      if (forecastDt.isAfter(thisSunday)) {
        return InsightItem(
          icon: Icons.flag_outlined,
          title: 'Прогноз цели «${goal.categoryName}»',
          message:
              'При текущем темпе недельная цель не будет достигнута. Нужно больше активности!',
          type: InsightType.warning,
        );
      }

      final day = _dayName(forecastDt.weekday);
      final h = forecastDt.hour.toString().padLeft(2, '0');
      final m = forecastDt.minute.toString().padLeft(2, '0');
      return InsightItem(
        icon: Icons.flag_rounded,
        title: 'Прогноз цели «${goal.categoryName}»',
        message: 'С текущим темпом цель будет достигнута $day к $h:$m.',
        type: InsightType.info,
      );
    }
    return null;
  }

  // ─── 3. Burnout Detector ──────────────────────────────────────────────────

  Future<InsightItem?> _computeBurnout(DateTime now) async {
    final db = await _db.database;
    const thresholdSec = 9 * 3600; // 9 hours

    for (int i = 1; i <= 3; i++) {
      final dayStart = DateTime(now.year, now.month, now.day - i);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final total = await _sumSeconds(db, dayStart, dayEnd);
      if (total > thresholdSec) {
        return const InsightItem(
          icon: Icons.warning_amber_rounded,
          title: 'Риск выгорания',
          message:
              'Ваша продуктивность падает — высокий риск выгорания. Рекомендуется отдых.',
          type: InsightType.warning,
        );
      }
    }
    return null;
  }

  // ─── 4. Peak Productivity ─────────────────────────────────────────────────

  Future<InsightItem?> _computePeakProductivity(DateTime now) async {
    final db = await _db.database;
    final from = now.subtract(const Duration(days: 30));

    final rows = await db.rawQuery(
      'SELECT start_time, end_time FROM task_sessions '
      'WHERE start_time >= ? AND end_time IS NOT NULL',
      [from.toIso8601String()],
    );
    if (rows.isEmpty) return null;

    final buckets = List<double>.filled(24, 0);
    for (final row in rows) {
      final start = DateTime.parse(row['start_time'] as String);
      final end = DateTime.parse(row['end_time'] as String);
      if (!end.isAfter(start)) continue;
      var cur = start;
      while (cur.isBefore(end)) {
        final nextHour =
            DateTime(cur.year, cur.month, cur.day, cur.hour + 1);
        final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
        buckets[cur.hour] += sliceEnd.difference(cur).inSeconds / 60.0;
        cur = nextHour;
      }
    }

    double bestSum = 0;
    int bestHour = -1;
    for (int h = 0; h < 23; h++) {
      final sum = buckets[h] + buckets[h + 1];
      if (sum > bestSum) {
        bestSum = sum;
        bestHour = h;
      }
    }
    if (bestHour == -1 || bestSum < 1) return null;

    final endH = bestHour + 2;
    final s = '${bestHour.toString().padLeft(2, '0')}:00';
    final e = '${endH.toString().padLeft(2, '0')}:00';
    return InsightItem(
      icon: Icons.bolt_rounded,
      title: 'Золотой час',
      message:
          'Ваш пик продуктивности за 30 дней — $s — $e. Планируйте важные задачи на этот интервал.',
      type: InsightType.info,
    );
  }

  // ─── SQL helpers ──────────────────────────────────────────────────────────

  Future<int> _sumSeconds(Database db, DateTime from, DateTime to) async {
    final result = await db.rawQuery(
      'SELECT SUM(duration_seconds) AS total FROM task_sessions '
      'WHERE start_time >= ? AND start_time < ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> _sumSecondsByCategory(
    Database db,
    String category,
    DateTime from,
    DateTime to,
  ) async {
    final result = await db.rawQuery(
      'SELECT SUM(duration_seconds) AS total FROM task_sessions '
      'WHERE category = ? AND start_time >= ? AND start_time < ?',
      [category, from.toIso8601String(), to.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // ─── Date helpers ─────────────────────────────────────────────────────────

  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day)
          .subtract(Duration(days: d.weekday - 1));

  static String _dayName(int weekday) => switch (weekday) {
        1 => 'в понедельник',
        2 => 'во вторник',
        3 => 'в среду',
        4 => 'в четверг',
        5 => 'в пятницу',
        6 => 'в субботу',
        7 => 'в воскресенье',
        _ => '',
      };
}
