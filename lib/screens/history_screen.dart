import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_session.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = DatabaseService();
  late Future<List<TaskSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  void _loadSessions() {
    _sessionsFuture = _db.getAllSessions();
  }

  Future<void> _deleteSession(int id) async {
    await _db.deleteSession(id);
    if (!mounted) return;
    setState(_loadSessions);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'История',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: kIsWeb
          ? _WebUnsupportedPlaceholder(colorScheme: colorScheme)
          : FutureBuilder<List<TaskSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final errorText = snapshot.error.toString();
            debugPrint('[HistoryScreen] Ошибка загрузки: $errorText');
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 56, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Ошибка загрузки',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final sessions = snapshot.data ?? [];

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_outlined,
                      size: 72, color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Записей пока нет',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Запустите таймер, чтобы создать первую',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outlineVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _SessionCard(
                session: session,
                onDelete: () => _deleteSession(session.id!),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Web placeholder ──────────────────────────────────────────────────────────

class _WebUnsupportedPlaceholder extends StatelessWidget {
  final ColorScheme colorScheme;
  const _WebUnsupportedPlaceholder({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_rounded,
                size: 72, color: colorScheme.outlineVariant),
            const SizedBox(height: 20),
            Text(
              'База данных SQLite недоступна в браузере',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Используйте эмулятор Android/iOS\nили десктопную платформу.',
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

// ─── Session card ─────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final TaskSession session;
  final VoidCallback onDelete;

  const _SessionCard({required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr =
        DateFormat('dd.MM.yyyy  HH:mm').format(session.startTime);
    final durStr = _formatDuration(session.durationSeconds);

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _showConfirmDialog(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_sweep_rounded,
          color: colorScheme.onErrorContainer,
          size: 28,
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: colorScheme.secondaryContainer,
            child: Icon(
              _categoryIcon(session.category),
              color: colorScheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          title: Text(
            session.taskName,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category
                Row(
                  children: [
                    Icon(_categoryIcon(session.category),
                        size: 13, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      session.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Duration
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      durStr,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: colorScheme.error,
            tooltip: 'Удалить',
            onPressed: () async {
              final confirmed = await _showConfirmDialog(context);
              if (confirmed == true) onDelete();
            },
          ),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить запись?'),
        content: Text(
          '«${session.taskName}» будет удалена безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Работа':
        return Icons.work_outline_rounded;
      case 'Учёба':
        return Icons.school_outlined;
      case 'Отдых':
        return Icons.self_improvement_outlined;
      case 'Спорт':
        return Icons.fitness_center_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;

    if (h > 0) return '$h ч $m мин';
    if (m > 0) return '$m мин $s сек';
    return '$s сек';
  }
}
