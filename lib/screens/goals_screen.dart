import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/goal.dart';
import '../services/database_service.dart';
import '../services/app_settings.dart';
import '../widgets/category_selector.dart';

class GoalsScreen extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;

  const GoalsScreen({super.key, required this.refreshNotifier});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _db = DatabaseService();

  List<_GoalWithProgress> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final goals = await _db.getAllGoals();
      final items = await Future.wait(goals.map((g) async {
        final todaySec = await _db.getTodayDurationByCategory(g.categoryName);
        final weekSec = await _db.getWeekDurationByCategory(g.categoryName);
        return _GoalWithProgress(
          goal: g,
          todaySeconds: todaySec,
          weekSeconds: weekSec,
        );
      }));
      if (mounted) setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openGoalDialog({Goal? existing}) async {
    final result = await showDialog<Goal>(
      context: context,
      builder: (_) => _GoalDialog(existing: existing),
    );
    if (result != null) {
      await _db.upsertGoal(result);
      _load();
    }
  }

  Future<void> _deleteGoal(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить цель?'),
        content: Text('Цель для категории «${goal.categoryName}» будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && goal.id != null) {
      await _db.deleteGoal(goal.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Цели'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goals_fab',
        onPressed: () => _openGoalDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Установить цель'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyState(onAdd: () => _openGoalDialog())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _GoalCard(
                      item: _items[index],
                      onEdit: () => _openGoalDialog(existing: _items[index].goal),
                      onDelete: () => _deleteGoal(_items[index].goal),
                    ),
                  ),
                ),
    );
  }
}

// ─── Goal Card ───────────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final _GoalWithProgress item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final categoryIcon = _iconForCategory(item.goal.categoryName);

    final dailyProgress = item.goal.dailyMinutes > 0
        ? (item.todaySeconds / (item.goal.dailyMinutes * 60)).clamp(0.0, 1.0)
        : 0.0;
    final weeklyProgress = item.goal.weeklyMinutes > 0
        ? (item.weekSeconds / (item.goal.weeklyMinutes * 60)).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: cs.onPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.goal.categoryName,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Изменить'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Удалить'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                  child: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Daily progress
            _ProgressRow(
              label: 'Сегодня',
              icon: Icons.today_outlined,
              actual: item.todaySeconds,
              targetMinutes: item.goal.dailyMinutes,
              progress: dailyProgress,
            ),
            const SizedBox(height: 14),
            // Weekly progress
            _ProgressRow(
              label: 'На этой неделе',
              icon: Icons.date_range_outlined,
              actual: item.weekSeconds,
              targetMinutes: item.goal.weeklyMinutes,
              progress: weeklyProgress,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress Row ─────────────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int actual; // seconds
  final int targetMinutes;
  final double progress; // 0.0 — 1.0

  const _ProgressRow({
    required this.label,
    required this.icon,
    required this.actual,
    required this.targetMinutes,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isAchieved = progress >= 1.0;
    // Achieved: soft botanical green; in-progress: deep charcoal
    const achievedColor = Color(0xFF3A7D44);
    const achievedBg = Color(0xFFDEF2E1);
    const progressColor = Color(0xFF2D2D2D);
    const progressBg = Color(0xFFE8E8E8);

    final barColor = isAchieved ? achievedColor : progressColor;
    final bgColor = isAchieved ? achievedBg : progressBg;

    final actualStr = _formatSeconds(actual);
    final targetStr = _formatMinutes(targetMinutes);
    final pct = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            if (isAchieved)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: Color(0xFF3A7D44)),
                  const SizedBox(width: 4),
                  Text(
                    'Цель достигнута!',
                    style: tt.labelSmall?.copyWith(
                      color: const Color(0xFF3A7D44),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              Text(
                '$pct%',
                style: tt.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: bgColor,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$actualStr / $targetStr',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 72, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Цели не установлены',
              style: tt.titleLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Установите плановые показатели, чтобы отслеживать свой прогресс.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Установить цель'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Goal Dialog ─────────────────────────────────────────────────────────────

class _GoalDialog extends StatefulWidget {
  final Goal? existing;

  const _GoalDialog({this.existing});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late String _category;
  final _dailyController = TextEditingController();
  final _weeklyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _category = widget.existing!.categoryName;
      _dailyController.text = widget.existing!.dailyMinutes.toString();
      _weeklyController.text = widget.existing!.weeklyMinutes.toString();
    } else {
      _category = AppSettings.instance.categories.first;
    }
  }

  @override
  void dispose() {
    _dailyController.dispose();
    _weeklyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final goal = Goal(
      id: widget.existing?.id,
      categoryName: _category,
      dailyMinutes: int.parse(_dailyController.text),
      weeklyMinutes: int.parse(_weeklyController.text),
    );
    Navigator.pop(context, goal);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Изменить цель' : 'Установить цель'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Категория',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              CategorySelector(
                selected: _category,
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 20),
              _MinutesField(
                controller: _dailyController,
                label: 'Цель на день',
                hint: 'например, 60 (=1 ч)',
              ),
              const SizedBox(height: 12),
              _MinutesField(
                controller: _weeklyController,
                label: 'Цель на неделю',
                hint: 'например, 300 (=5 ч)',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Сохранить' : 'Установить'),
        ),
      ],
    );
  }
}

class _MinutesField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _MinutesField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: 'мин',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Введите значение';
        final n = int.tryParse(v.trim());
        if (n == null || n <= 0) return 'Должно быть больше 0';
        return null;
      },
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatSeconds(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) {
    return m > 0 ? '$h ч $m мин' : '$h ч';
  }
  return '$m мин';
}

String _formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0) {
    return m > 0 ? '$h ч $m мин' : '$h ч';
  }
  return '$m мин';
}

IconData _iconForCategory(String category) =>
    AppSettings.instance.iconDataFor(category);

// ─── Data class ──────────────────────────────────────────────────────────────

class _GoalWithProgress {
  final Goal goal;
  final int todaySeconds;
  final int weekSeconds;

  const _GoalWithProgress({
    required this.goal,
    required this.todaySeconds,
    required this.weekSeconds,
  });
}
