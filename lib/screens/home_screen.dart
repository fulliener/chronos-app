// ignore_for_file: unnecessary_brace_in_string_interps
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_session.dart';
import '../screens/all_history_screen.dart';
import '../services/app_settings.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/category_selector.dart';
import '../widgets/manual_entry_dialog.dart';
import '../widgets/stopwatch_display.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _taskController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseService();

  // ─── Timer state ────────────────────────────────────────────────────────────
  String _selectedCategory = 'Работа';
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  DateTime? _startTime;
  Timer? _timer;

  // ─── History state ───────────────────────────────────────────────────────────
  late Future<List<TaskSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _taskController.dispose();
    super.dispose();
  }

  // ─── Sessions ────────────────────────────────────────────────────────────────

  void _loadSessions() {
    setState(() {
      _sessionsFuture = _db.getAllSessions();
    });
  }

  Future<void> _deleteSession(int id) async {
    await _db.deleteSession(id);
    if (mounted) _loadSessions();
  }

  // ─── Timer logic ─────────────────────────────────────────────────────────────

  void _startTimer() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isRunning = true;
      _startTime = DateTime.now();
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });
    // Schedule break reminder 60 minutes from now
    NotificationService.instance.scheduleBreakReminder();
  }

  Future<void> _stopTimer() async {
    _timer?.cancel();
    setState(() => _isRunning = false);
    // Cancel break reminder — timer is no longer running
    NotificationService.instance.cancelBreakReminder();

    final endTime = DateTime.now();
    final startTime = _startTime;
    if (startTime == null) {
      _reset();
      return;
    }

    final session = TaskSession(
      taskName: _taskController.text.trim(),
      category: _selectedCategory,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: _elapsedSeconds,
    );

    try {
      await _db.insertSession(session);
      // Check if any goal was reached (fire-and-forget)
      NotificationService.instance.checkAndNotifyGoals();
      if (!mounted) return;
      _showSavedSnackBar(session);
      _loadSessions(); // ← обновляем список после сохранения
    } catch (e) {
      debugPrint('_stopTimer error: $e');
      if (!mounted) return;
      final msg = kIsWeb
          ? 'SQLite недоступна в браузере. Используйте эмулятор.'
          : 'Ошибка сохранения: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) _reset();
    }
  }

  void _reset() {
    setState(() {
      _isRunning = false;
      _elapsedSeconds = 0;
      _startTime = null;
      _taskController.clear();
      _selectedCategory = 'Работа';
    });
  }

  Future<void> _openAllHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AllHistoryScreen()),
    );
    if (mounted) _loadSessions();
  }

  Future<void> _openManualEntry() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManualEntryDialog(db: _db),
    );
    if (saved == true && mounted) {
      // Check if any goal was reached (fire-and-forget)
      NotificationService.instance.checkAndNotifyGoals();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Запись добавлена'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      _loadSessions(); // ← обновляем список после ручного ввода
    }
  }

  void _showSavedSnackBar(TaskSession session) {
    final h = session.durationSeconds ~/ 3600;
    final m = (session.durationSeconds % 3600) ~/ 60;
    final s = session.durationSeconds % 60;
    final dur =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '«${session.taskName}» сохранено — $dur',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── Build helpers ────────────────────────────────────────────────────────────

  Widget _buildTimerSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TaskNameField(
          controller: _taskController,
          enabled: !_isRunning,
        ),
        const SizedBox(height: 20),
        _SectionLabel(label: 'Категория'),
        const SizedBox(height: 10),
        CategorySelector(
          selected: _selectedCategory,
          enabled: !_isRunning,
          onChanged: (v) => setState(() => _selectedCategory = v),
        ),
        const SizedBox(height: 28),
        Center(
          child: StopwatchDisplay(
            elapsedSeconds: _elapsedSeconds,
            isRunning: _isRunning,
          ),
        ),
        const SizedBox(height: 28),
        _StartStopButton(
          isRunning: _isRunning,
          onStart: _startTimer,
          onStop: _stopTimer,
        ),
        if (_isRunning) ...[
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () {
                _timer?.cancel();
                _reset();
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Сбросить'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Chronos',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: _isRunning
          ? null
          : FloatingActionButton.extended(
              heroTag: 'home_fab',
              onPressed: _openManualEntry,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить вручную'),
            ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: FutureBuilder<List<TaskSession>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? [];
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting &&
                      sessions.isEmpty;

              return CustomScrollView(
                slivers: [
                  // ── Timer form ──────────────────────────────────────────────
                  SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: _buildTimerSection(),
                    ),
                  ),

                  // ── History header ──────────────────────────────────────────
                  SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Text(
                            'Последние записи',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 10),
                          if (sessions.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${sessions.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          if (isLoading) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Sessions list / empty state ─────────────────────────────
                  if (!isLoading && sessions.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history_toggle_off_outlined,
                              size: 56,
                              color: colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Записей пока нет',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Show at most 5 most-recent sessions
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final s = sessions[i];
                            return _SessionTile(
                              key: ValueKey(s.id),
                              session: s,
                              onDelete: () => _deleteSession(s.id!),
                            );
                          },
                          childCount: sessions.length.clamp(0, 5),
                        ),
                      ),
                    ),
                    // "Show all" button + bottom padding for FAB
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        child: sessions.length > 5
                            ? TextButton.icon(
                                onPressed: _openAllHistory,
                                icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18),
                                label: Text(
                                  'Показать всё · ${sessions.length} записей',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      colorScheme.onSurfaceVariant,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
    );
  }
}

class _TaskNameField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const _TaskNameField(
      {required this.controller, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Название задачи',
        hintText: 'Например: Написание диплома',
        prefixIcon: const Icon(Icons.edit_note_rounded),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: enabled
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Введите название задачи';
        }
        return null;
      },
    );
  }
}

class _StartStopButton extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onStart;
  final Future<void> Function() onStop;

  const _StartStopButton({
    required this.isRunning,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: SizedBox(
        key: ValueKey(isRunning),
        height: 60,
        child: FilledButton.icon(
          onPressed: isRunning ? onStop : onStart,
          icon: Icon(
            isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: 28,
          ),
          label: Text(
            isRunning ? 'Стоп' : 'Старт',
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                isRunning ? colorScheme.error : colorScheme.primary,
            foregroundColor:
                isRunning ? colorScheme.onError : colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Session tile ─────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final TaskSession session;
  final VoidCallback onDelete;

  const _SessionTile(
      {super.key, required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr =
        DateFormat('dd.MM.yyyy  HH:mm').format(session.startTime);
    final durStr = _fmtDuration(session.durationSeconds);

    return Dismissible(
      key: ValueKey('dismissible_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_sweep_rounded,
            color: colorScheme.onErrorContainer, size: 26),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: colorScheme.secondaryContainer,
            child: Icon(
              _categoryIcon(session.category),
              color: colorScheme.onSecondaryContainer,
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
                Icon(Icons.label_outline_rounded,
                    size: 12, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  session.category,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 10),
                Icon(Icons.timer_outlined,
                    size: 12, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  durStr,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dateStr,
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: colorScheme.error, size: 20),
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
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

// ─── File-level helpers ───────────────────────────────────────────────────────

String _fmtDuration(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0 && m > 0) return '${h}ч ${m}мин';
  if (h > 0) return '${h}ч';
  if (m > 0) return '${m}мин';
  return '${s}сек';
}

IconData _categoryIcon(String category) =>
    AppSettings.instance.iconDataFor(category);
