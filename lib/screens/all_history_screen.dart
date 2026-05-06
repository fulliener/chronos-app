import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_session.dart';
import '../services/app_settings.dart';
import '../services/database_service.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class AllHistoryScreen extends StatefulWidget {
  const AllHistoryScreen({super.key});

  @override
  State<AllHistoryScreen> createState() => _AllHistoryScreenState();
}

class _AllHistoryScreenState extends State<AllHistoryScreen> {
  final _db = DatabaseService();
  late Future<List<TaskSession>> _sessionsFuture;

  /// null means "Все"
  String? _selectedCategory;

  // Categories come from AppSettings so they stay in sync with settings screen

  @override
  void initState() {
    super.initState();
    // Direct assignment — setState must NOT be called during initState
    // because the widget is still in the "created" lifecycle state.
    _sessionsFuture = _db.getAllSessions();
  }

  /// Reload after delete or pull-to-refresh. Safe to call setState here
  /// because the widget is already mounted and in the "ready" state.
  void _load() {
    final future = _db.getAllSessions();
    setState(() { _sessionsFuture = future; });
  }

  void _selectCategory(String? category) {
    setState(() { _selectedCategory = category; });
  }

  List<TaskSession> _applyFilter(List<TaskSession> all) {
    if (_selectedCategory == null) return all;
    return all.where((s) => s.category == _selectedCategory).toList();
  }

  Future<void> _delete(int id) async {
    await _db.deleteSession(id);
    if (mounted) _load();
  }

  // ─── Group sessions into flat item list ──────────────────────────────────

  List<_Item> _buildItems(List<TaskSession> sessions) {
    if (sessions.isEmpty) return [];

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final yesterdayDate = todayDate.subtract(const Duration(days: 1));

    final items = <_Item>[];
    String? lastHeader;

    for (final session in sessions) {
      final d = DateTime(
        session.startTime.year,
        session.startTime.month,
        session.startTime.day,
      );
      final header = _headerFor(d, todayDate, yesterdayDate, now.year);

      if (header != lastHeader) {
        items.add(_HeaderItem(header));
        lastHeader = header;
      }
      items.add(_SessionItem(session));
    }
    return items;
  }

  static String _headerFor(
    DateTime date,
    DateTime today,
    DateTime yesterday,
    int currentYear,
  ) {
    if (date == today) return 'Сегодня';
    if (date == yesterday) return 'Вчера';
    const m = [
      '',
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    if (date.year == currentYear) return '${date.day} ${m[date.month]}';
    return '${date.day} ${m[date.month]} ${date.year}';
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('История', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: kIsWeb
          ? _WebPlaceholder(cs: cs)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Category filter chips ─────────────────────────────────
                _CategoryFilterBar(
                  categories: AppSettings.instance.categories,
                  selected: _selectedCategory,
                  onSelected: _selectCategory,
                ),
                const Divider(height: 1, thickness: 1),
                // ── Sessions list ─────────────────────────────────────────
                Expanded(
                  child: FutureBuilder<List<TaskSession>>(
                    future: _sessionsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _ErrorState(
                            message: snapshot.error.toString(), cs: cs);
                      }

                      final all = snapshot.data ?? [];
                      final sessions = _applyFilter(all);

                      if (all.isEmpty) return _EmptyState(cs: cs);
                      if (sessions.isEmpty) {
                        return _EmptyFilterState(
                          category: _selectedCategory!,
                          cs: cs,
                          onClear: () => _selectCategory(null),
                        );
                      }

                      final items = _buildItems(sessions);

                      return RefreshIndicator(
                        onRefresh: () async => _load(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final item = items[i];
                            if (item is _HeaderItem) {
                              return _DateHeader(label: item.label);
                            }
                            final s = (item as _SessionItem).session;
                            return _HistoryCard(
                              key: ValueKey(s.id),
                              session: s,
                              onDelete: () => _delete(s.id!),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Flat item types ──────────────────────────────────────────────────────────

sealed class _Item {}

class _HeaderItem extends _Item {
  final String label;
  _HeaderItem(this.label);
}

class _SessionItem extends _Item {
  final TaskSession session;
  _SessionItem(this.session);
}

// ─── Date header ──────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final TaskSession session;
  final VoidCallback onDelete;

  const _HistoryCard({super.key, required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeStr = DateFormat('HH:mm').format(session.startTime);
    final durStr = _fmtDuration(session.durationSeconds);

    return Dismissible(
      key: ValueKey('d_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_sweep_rounded,
            color: cs.onErrorContainer, size: 26),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: cs.secondaryContainer,
            child: Icon(
              _iconFor(session.category),
              color: cs.onSecondaryContainer,
              size: 20,
            ),
          ),
          title: Text(
            session.taskName,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.label_outline_rounded, size: 12, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  session.category,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.primary,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 10),
                Icon(Icons.schedule_outlined,
                    size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 10),
                Icon(Icons.timer_outlined,
                    size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(durStr,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: cs.error, size: 20),
            onPressed: () async {
              final ok = await _confirmDelete(context);
              if (ok == true) onDelete();
            },
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить запись?'),
        content: Text('«${session.taskName}» будет удалена безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String category) =>
      AppSettings.instance.iconDataFor(category);

  static String _fmtDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0 && m > 0) return '$h ч $m мин';
    if (h > 0) return '$h ч';
    if (m > 0) return '$m мин';
    return '${s % 60} сек';
  }
}

// ─── Category filter bar ──────────────────────────────────────────────────────

class _CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryFilterBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  static const Map<String, IconData> _icons = {
    'Работа': Icons.work_outline_rounded,
    'Учёба': Icons.school_outlined,
    'Отдых': Icons.self_improvement_outlined,
    'Спорт': Icons.fitness_center_outlined,
    'Другое': Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // "Все" chip
          _buildChip(
            context: context,
            cs: cs,
            label: 'Все',
            icon: Icons.layers_outlined,
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...categories.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildChip(
                context: context,
                cs: cs,
                label: cat,
                icon: _icons[cat] ?? Icons.category_outlined,
                isSelected: selected == cat,
                onTap: () => onSelected(selected == cat ? null : cat),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required ColorScheme cs,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── State widgets ────────────────────────────────────────────────────────────

class _EmptyFilterState extends StatelessWidget {
  final String category;
  final ColorScheme cs;
  final VoidCallback onClear;

  const _EmptyFilterState({
    required this.category,
    required this.cs,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off_rounded,
              size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Нет записей в категории «$category»',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('Сбросить фильтр'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off_outlined,
              size: 72, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Записей пока нет',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final ColorScheme cs;
  const _ErrorState({required this.message, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
            const SizedBox(height: 12),
            Text('Ошибка загрузки',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _WebPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  const _WebPlaceholder({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('SQLite недоступен в браузере',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
