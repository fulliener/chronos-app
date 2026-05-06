import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task_session.dart';
import '../services/app_settings.dart';
import '../services/database_service.dart';

class ManualEntryDialog extends StatefulWidget {
  final DatabaseService db;

  const ManualEntryDialog({super.key, required this.db});

  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _taskController = TextEditingController();
  final _hoursController = TextEditingController(text: '0');
  final _minutesController = TextEditingController(text: '0');

  String _selectedCategory = AppSettings.instance.categories.first;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _taskController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  // ─── Date picker ─────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ─── Time picker ─────────────────────────────────────────────────────────

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          timePickerTheme: TimePickerThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final hours = int.tryParse(_hoursController.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final totalSeconds = hours * 3600 + minutes * 60;

    // startTime = chosen date + chosen clock time; endTime = startTime + duration
    final startTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final endTime = startTime.add(Duration(seconds: totalSeconds));

    final session = TaskSession(
      taskName: _taskController.text.trim(),
      category: _selectedCategory,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: totalSeconds,
    );

    try {
      await widget.db.insertSession(session);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ошибка при сохранении'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      radius: 22,
                      child: Icon(Icons.edit_calendar_rounded,
                          color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ручной ввод',
                              style: textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Добавить прошедшую задачу',
                              style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Task name ──
                TextFormField(
                  controller: _taskController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Название задачи',
                    hintText: 'Например: Написание диплома',
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                ),

                const SizedBox(height: 18),

                // ── Category dropdown ──
                _SectionLabel(label: 'Категория'),
                const SizedBox(height: 8),
                _CategoryDropdown(
                  selected: _selectedCategory,
                  onChanged: (v) => setState(() => _selectedCategory = v),
                ),

                const SizedBox(height: 18),

                // ── Duration ──
                _SectionLabel(label: 'Длительность'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: _hoursController,
                        label: 'Часы',
                        max: 23,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(':',
                          style: textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w300)),
                    ),
                    Expanded(
                      child: _NumberField(
                        controller: _minutesController,
                        label: 'Минуты',
                        max: 59,
                        extraValidator: (h, m) =>
                            (h == 0 && m == 0) ? 'Введите время' : null,
                        otherController: _hoursController,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Date ──
                _SectionLabel(label: 'Дата'),
                const SizedBox(height: 8),
                _DatePickerField(
                  date: _selectedDate,
                  onTap: _pickDate,
                ),

                const SizedBox(height: 12),

                // ── Start time ──
                _SectionLabel(label: 'Время начала'),
                const SizedBox(height: 8),
                _TimePickerField(
                  time: _selectedTime,
                  onTap: _pickTime,
                ),

                const SizedBox(height: 28),

                // ── Actions ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label:
                            Text(_isSaving ? 'Сохранение...' : 'Сохранить'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Private sub-widgets ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _CategoryDropdown(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.category_outlined),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      child: ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) {
          final cats = AppSettings.instance.categories;
          // Guard: if the current selection was removed, fallback to first
          final safeSelected = cats.contains(selected) ? selected : cats.first;
          return DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeSelected,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              items: cats
                  .map((label) =>
                      DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          );
        },
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int max;

  /// Дополнительная кросс-валидация (передаётся значение this + otherController).
  final String? Function(int self, int other)? extraValidator;
  final TextEditingController? otherController;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.max,
    this.extraValidator,
    this.otherController,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null) return 'Число';
        if (n < 0 || n > max) return '0–$max';
        if (extraValidator != null) {
          final other =
              int.tryParse(otherController?.text.trim() ?? '') ?? 0;
          return extraValidator!(n, other);
        }
        return null;
      },
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimePickerField({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.schedule_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        child: Text('$h:$m',
            style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerField({required this.date, required this.onTap});

  String get _label {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Сегодня, ${date.day} ${_monthName(date.month)} ${date.year}';
    }
    return '${date.day} ${_monthName(date.month)} ${date.year}';
  }

  String _monthName(int month) {
    const names = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return names[month];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        child: Text(_label,
            style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
