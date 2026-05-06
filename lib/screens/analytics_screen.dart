// ignore_for_file: unnecessary_brace_in_string_interps
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/analytics_report.dart';
import '../models/task_session.dart';
import '../services/analytics_service.dart';
import '../services/category_color_service.dart';
import '../services/database_service.dart';

enum AnalyticsPeriod { day, week, month, all }

class _CategoryStat {
  final String category;
  final int totalSeconds;
  final Color color;
  final double percentage;

  const _CategoryStat({
    required this.category,
    required this.totalSeconds,
    required this.color,
    required this.percentage,
  });
}

class AnalyticsScreen extends StatefulWidget {
  /// Инкрементируется из MainShell при каждом переходе на эту вкладку.
  /// Позволяет перезагружать данные без пересоздания виджета (IndexedStack).
  final ValueNotifier<int>? refreshNotifier;

  const AnalyticsScreen({super.key, this.refreshNotifier});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseService();
  final _analyticsService = AnalyticsService();

  late Future<List<TaskSession>> _sessionsFuture;
  late Future<AnalyticsReport> _reportFuture;

  AnalyticsPeriod _period = AnalyticsPeriod.week;
  int _touchedIndex = -1;

  /// Delegates to [CategoryColorService] — automatically handles both themes.
  Color _colorFor(String category, int index, {required bool isDark}) =>
      CategoryColorService.colorFor(category, index, isDark: isDark);

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_loadSessions);
    _loadSessions();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadSessions);
    super.dispose();
  }

  void _loadSessions() {
    setState(() {
      _sessionsFuture = _db.getAllSessions();
      _reportFuture = _analyticsService.generateReport();
    });
  }

  List<TaskSession> _filter(List<TaskSession> sessions) {
    if (_period == AnalyticsPeriod.all) return List.of(sessions);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (_period) {
      AnalyticsPeriod.day => today,
      AnalyticsPeriod.week =>
        today.subtract(const Duration(days: 6)),
      AnalyticsPeriod.month =>
        DateTime(now.year, now.month - 1, now.day),
      AnalyticsPeriod.all => today,
    };
    return sessions.where((s) => !s.startTime.isBefore(from)).toList();
  }

  List<_CategoryStat> _buildStats(
    List<TaskSession> sessions, {
    required bool isDark,
  }) {
    final map = <String, int>{};
    for (final s in sessions) {
      map[s.category] = (map[s.category] ?? 0) + s.durationSeconds;
    }
    final total = map.values.fold(0, (a, b) => a + b);
    if (total == 0) return [];

    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.asMap().entries.map((e) {
      return _CategoryStat(
        category: e.value.key,
        totalSeconds: e.value.value,
        color: _colorFor(e.value.key, e.key, isDark: isDark),
        percentage: e.value.value * 100 / total,
      );
    }).toList();
  }

  /// Distributes session durations across 24 hourly buckets (in minutes).
  /// Each session is split proportionally across the hours it spans.
  static List<double> buildHourlyMinutes(List<TaskSession> sessions) {
    final buckets = List<double>.filled(24, 0);
    for (final s in sessions) {
      final start = s.startTime;
      final end = s.endTime ?? start.add(Duration(seconds: s.durationSeconds));
      if (!end.isAfter(start)) continue;

      var cur = start;
      while (cur.isBefore(end)) {
        final nextHour = DateTime(cur.year, cur.month, cur.day, cur.hour + 1);
        final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
        buckets[cur.hour] += sliceEnd.difference(cur).inSeconds / 60.0;
        cur = nextHour;
      }
    }
    return buckets;
  }

  static String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}ч ${m}мин';
    if (h > 0) return '${h}ч';
    if (m > 0) return '${m}мин';
    return '${totalSeconds}сек';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Аналитика',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: _loadSessions,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: kIsWeb
          ? _WebPlaceholder(colorScheme: colorScheme)
          : FutureBuilder<List<TaskSession>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Ошибка: ${snapshot.error}'),
                  );
                }

                final allSessions = snapshot.data ?? [];
                final filtered = _filter(allSessions);
                final isDark =
                    colorScheme.brightness == Brightness.dark;
                final stats = _buildStats(filtered, isDark: isDark);
                final total = filtered.fold<int>(
                    0, (sum, s) => sum + s.durationSeconds);
                final hourlyMinutes =
                    _AnalyticsScreenState.buildHourlyMinutes(filtered);

                return Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: _PeriodSelector(
                        selected: _period,
                        onChanged: (p) => setState(() {
                          _period = p;
                          _touchedIndex = -1;
                        }),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? _EmptyState(period: _period)
                          : RefreshIndicator(
                              onRefresh: () async => _loadSessions(),
                              child: SingleChildScrollView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FutureBuilder<AnalyticsReport>(
                                      future: _reportFuture,
                                      builder: (context, snap) {
                                        if (snap.hasData &&
                                            !snap.data!.isEmpty) {
                                          return Column(
                                            children: [
                                              _SmartInsightsCard(
                                                  report: snap.data!),
                                              const SizedBox(height: 16),
                                            ],
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                    _TotalCard(
                                      totalSeconds: total,
                                      sessionCount: filtered.length,
                                    ),
                                    const SizedBox(height: 16),
                                    _ChartCard(
                                      stats: stats,
                                      touchedIndex: _touchedIndex,
                                      onTouch: (i) => setState(
                                          () => _touchedIndex = i),
                                    ),
                                    const SizedBox(height: 16),
                                    _LegendCard(
                                      stats: stats,
                                      total: total,
                                    ),
                                    const SizedBox(height: 16),
                                    _HourlyBarChartCard(
                                      hourlyMinutes: hourlyMinutes,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

// ─── Period selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final AnalyticsPeriod selected;
  final ValueChanged<AnalyticsPeriod> onChanged;

  const _PeriodSelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AnalyticsPeriod>(
      segments: const [
        ButtonSegment(
          value: AnalyticsPeriod.day,
          label: Text('День'),
        ),
        ButtonSegment(
          value: AnalyticsPeriod.week,
          label: Text('Неделя'),
        ),
        ButtonSegment(
          value: AnalyticsPeriod.month,
          label: Text('Месяц'),
        ),
        ButtonSegment(
          value: AnalyticsPeriod.all,
          label: Text('Всё время'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (set) => onChanged(set.first),
      showSelectedIcon: false,
    );
  }
}

// ─── Total card ───────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final int totalSeconds;
  final int sessionCount;

  const _TotalCard(
      {required this.totalSeconds, required this.sessionCount});

  String _sessionWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'сессия';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'сессии';
    }
    return 'сессий';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: cs.inverseSurface,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Итого за период',
                    style: textTheme.labelLarge?.copyWith(
                      color: cs.onInverseSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _AnalyticsScreenState.formatDuration(totalSeconds),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onInverseSurface,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  color: cs.onInverseSurface.withValues(alpha: 0.7),
                  size: 36,
                ),
                const SizedBox(height: 4),
                Text(
                  '$sessionCount ${_sessionWord(sessionCount)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onInverseSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chart card ───────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final List<_CategoryStat> stats;
  final int touchedIndex;
  final ValueChanged<int> onTouch;

  const _ChartCard({
    required this.stats,
    required this.touchedIndex,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Card background: explicit theme value; used to fill the donut hole so the
    // center circle matches the card surface exactly.
    final cardBg = Theme.of(context).cardTheme.color ?? colorScheme.surface;
    final touched = (touchedIndex >= 0 && touchedIndex < stats.length)
        ? stats[touchedIndex]
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Распределение по категориям',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 272,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: stats.asMap().entries.map((e) {
                          final stat = e.value;
                          final showPct = stat.percentage >= 8;
                          return PieChartSectionData(
                            value: stat.totalSeconds.toDouble(),
                            color: stat.color,
                            // Fixed radius for all segments — guarantees
                            // a perfectly round donut at all times.
                            radius: 84,
                            title: showPct
                                ? '${stat.percentage.toStringAsFixed(0)}%'
                                : '',
                            showTitle: showPct,
                            titleStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              // White at 0.85 opacity — readable on all
                              // Deep Industrial colors regardless of theme.
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          );
                        }).toList(),
                        pieTouchData: PieTouchData(
                          touchCallback:
                              (FlTouchEvent event, PieTouchResponse? resp) {
                            final idx = (!event.isInterestedForInteractions ||
                                    resp?.touchedSection == null)
                                ? -1
                                : resp!.touchedSection!.touchedSectionIndex;
                            // Only rebuild if index actually changed —
                            // prevents flood of setState during scroll events.
                            if (idx != touchedIndex) onTouch(idx);
                          },
                        ),
                        centerSpaceRadius: 58,
                        centerSpaceColor: cardBg,
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                      ),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    // Center overlay.
                    // No explicit keys on children — AnimatedSwitcher
                    // distinguishes by widget type (_CenterHint vs _CenterInfo),
                    // which avoids duplicate-key crashes when the same section
                    // is touched again while the previous animation is still
                    // running.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: touched != null
                          ? _CenterInfo(stat: touched)
                          : const _CenterHint(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterHint extends StatelessWidget {
  const _CenterHint();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.touch_app_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          'Нажмите\nна секцию',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _CenterInfo extends StatelessWidget {
  final _CategoryStat stat;

  const _CenterInfo({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.category,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: stat.color,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          _AnalyticsScreenState.formatDuration(stat.totalSeconds),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          '${stat.percentage.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ─── Legend card ──────────────────────────────────────────────────────────────

class _LegendCard extends StatelessWidget {
  final List<_CategoryStat> stats;
  final int total;

  const _LegendCard({required this.stats, required this.total});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'По категориям',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            ...stats.map(
              (stat) => _LegendRow(stat: stat, total: total),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final _CategoryStat stat;
  final int total;

  const _LegendRow({required this.stat, required this.total});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: stat.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stat.category,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                _AnalyticsScreenState.formatDuration(stat.totalSeconds),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${stat.percentage.toStringAsFixed(0)}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? stat.totalSeconds / total : 0,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(stat.color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hourly bar chart card ────────────────────────────────────────────────────

class _HourlyBarChartCard extends StatelessWidget {
  final List<double> hourlyMinutes;

  const _HourlyBarChartCard({required this.hourlyMinutes});

  double _niceMaxY(double rawMax) {
    if (rawMax <= 0) return 10;
    // Round up to a nice ceiling
    const steps = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300];
    for (final s in steps) {
      if (rawMax <= s) return s.toDouble();
    }
    return (rawMax * 1.25).ceilToDouble();
  }

  double _yInterval(double maxY) {
    if (maxY <= 10) return 5;
    if (maxY <= 30) return 10;
    if (maxY <= 60) return 15;
    if (maxY <= 120) return 30;
    return 60;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final rawMax = hourlyMinutes.reduce(math.max);
    final maxY = _niceMaxY(rawMax);
    final interval = _yInterval(maxY);

    // Highlight the 2 peak hours with a lighter bar color
    double bestSum = 0;
    int peakStart = -1;
    for (int h = 0; h < 23; h++) {
      final s = hourlyMinutes[h] + hourlyMinutes[h + 1];
      if (s > bestSum) {
        bestSum = s;
        peakStart = h;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Активность по часам',
              textAlign: TextAlign.center,
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'суммарно за выбранный период, мин',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 168,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: 0,
                  groupsSpace: 3,
                  barGroups: List.generate(24, (h) {
                    final isPeak = peakStart != -1 &&
                        (h == peakStart || h == peakStart + 1);
                    final barColor = isPeak
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.28);
                    return BarChartGroupData(
                      x: h,
                      barRods: [
                        BarChartRodData(
                          toY: hourlyMinutes[h],
                          color: barColor,
                          width: 9,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
                    );
                  }),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value == meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              value.toInt().toString(),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 9,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 18,
                        getTitlesWidget: (value, meta) {
                          final h = value.toInt();
                          if (h % 6 != 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              h.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF2D2D2D),
                      getTooltipItem: (group, _, rod, __) {
                        final mins = rod.toY;
                        if (mins < 0.5) return null;
                        final label =
                            '${group.x.toString().padLeft(2, '0')}:00'
                            '\n${mins.round()} мин';
                        return BarTooltipItem(
                          label,
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final AnalyticsPeriod period;

  const _EmptyState({required this.period});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final periodLabel = switch (period) {
      AnalyticsPeriod.day => 'сегодня',
      AnalyticsPeriod.week => 'эту неделю',
      AnalyticsPeriod.month => 'этот месяц',
      AnalyticsPeriod.all => 'всё время',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pie_chart_outline_rounded,
              size: 80,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'За этот период данных пока нет',
              style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Нет записей за $periodLabel.\nЗапустите таймер или добавьте запись вручную.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Smart Insights card ──────────────────────────────────────────────────────

class _SmartInsightsCard extends StatelessWidget {
  final AnalyticsReport report;

  const _SmartInsightsCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Умные советы',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...report.items.asMap().entries.map((entry) {
              return Column(
                children: [
                  if (entry.key > 0)
                    Divider(
                      height: 24,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  _InsightRow(item: entry.value),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final InsightItem item;

  const _InsightRow({required this.item});

  Color _iconColor(ColorScheme cs) => switch (item.type) {
        InsightType.warning => cs.error,
        InsightType.positive => cs.onInverseSurface,
        InsightType.info => cs.onSurfaceVariant,
        InsightType.neutral => cs.onSurfaceVariant,
      };

  Color _iconBg(ColorScheme cs) => switch (item.type) {
        InsightType.warning => cs.errorContainer.withValues(alpha: 0.45),
        InsightType.positive => cs.inverseSurface,
        InsightType.info => cs.surfaceContainerHigh,
        InsightType.neutral => cs.surfaceContainerHigh,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _iconBg(cs),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.icon, size: 20, color: _iconColor(cs)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                item.message,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Web placeholder ──────────────────────────────────────────────────────────

class _WebPlaceholder extends StatelessWidget {
  final ColorScheme colorScheme;

  const _WebPlaceholder({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded,
              size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'SQLite недоступен в браузере',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
