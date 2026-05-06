import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Настройки',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── Appearance ────────────────────────────────────────────
              _SectionHeader(label: 'Внешний вид'),
              _Card(
                child: SwitchListTile(
                  secondary: Icon(
                    AppSettings.instance.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: cs.primary,
                  ),
                  title: const Text('Тёмная тема'),
                  subtitle: Text(
                    AppSettings.instance.isDark ? 'Включена' : 'Выключена',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: AppSettings.instance.isDark,
                  onChanged: (v) => AppSettings.instance.setDarkMode(v),
                  activeThumbColor: cs.primary,
                ),
              ),

              const SizedBox(height: 24),

              // ── Notifications ─────────────────────────────────────────
              _SectionHeader(label: 'Уведомления'),
              _Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        Icons.notifications_outlined,
                        color: cs.primary,
                      ),
                      title: const Text('Напоминания о работе'),
                      subtitle: Text(
                        'Ежедневное напоминание в 10:00',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: AppSettings.instance.notifyWork,
                      onChanged: (v) async {
                        await AppSettings.instance.setNotifyWork(v);
                        if (v) {
                          await NotificationService.instance
                              .scheduleWorkReminder();
                        } else {
                          await NotificationService.instance
                              .cancelWorkReminder();
                        }
                      },
                      activeThumbColor: cs.primary,
                    ),
                    Divider(
                      height: 1,
                      indent: 56,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.coffee_outlined,
                        color: cs.primary,
                      ),
                      title: const Text('Напоминания о перерывах'),
                      subtitle: Text(
                        'Пуш через 60 мин непрерывной работы',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: AppSettings.instance.notifyBreaks,
                      onChanged: (v) =>
                          AppSettings.instance.setNotifyBreaks(v),
                      activeThumbColor: cs.primary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Categories ────────────────────────────────────────────
              _SectionHeader(label: 'Категории'),
              _Card(
                child: Column(
                  children: [
                    ...AppSettings.instance.categories.asMap().entries.map((e) {
                      final idx = e.key;
                      final cat = e.value;
                      final isLast =
                          idx == AppSettings.instance.categories.length - 1;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            leading: Icon(
                              AppSettings.instance.iconDataFor(cat),
                              color: cs.onSurfaceVariant,
                            ),
                            title: Text(cat,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            trailing: AppSettings.instance.categories.length > 1
                                ? IconButton(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        color: cs.error, size: 20),
                                    tooltip: 'Удалить категорию',
                                    onPressed: () =>
                                        _confirmDelete(context, cat),
                                  )
                                : Tooltip(
                                    message:
                                        'Должна оставаться хоть одна категория',
                                    child: Icon(Icons.lock_outline_rounded,
                                        size: 18, color: cs.outlineVariant),
                                  ),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _AddCategoryTile(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String category) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить категорию?'),
        content: Text(
          '«$category» будет удалена из списка.\n'
          'Существующие записи с этой категорией сохранятся.',
        ),
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
    if (ok == true) await AppSettings.instance.removeCategory(category);
  }
}

// ─── Add category tile ────────────────────────────────────────────────────────

class _AddCategoryTile extends StatefulWidget {
  @override
  State<_AddCategoryTile> createState() => _AddCategoryTileState();
}

class _AddCategoryTileState extends State<_AddCategoryTile> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _expanded = false;
  int? _selectedIconCodePoint; // null = use default

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await AppSettings.instance.addCategory(
      text,
      iconCodePoint: _selectedIconCodePoint,
    );
    _controller.clear();
    setState(() {
      _expanded = false;
      _selectedIconCodePoint = null;
    });
    _focusNode.unfocus();
  }

  void _toggleIcon(IconData icon) {
    setState(() {
      final cp = icon.codePoint;
      _selectedIconCodePoint =
          _selectedIconCodePoint == cp ? null : cp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _Card(
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 220),
        crossFadeState: _expanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: ListTile(
          leading: Icon(Icons.add_circle_outline_rounded, color: cs.primary),
          title: const Text('Добавить категорию'),
          onTap: () {
            setState(() => _expanded = true);
            Future.delayed(
              const Duration(milliseconds: 50),
              () => _focusNode.requestFocus(),
            );
          },
        ),
        secondChild: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name field ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Название категории',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _expanded = false;
                        _selectedIconCodePoint = null;
                      });
                      _focusNode.unfocus();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Icon picker ───────────────────────────────────
              Text(
                'Иконка',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              _IconPicker(
                icons: AppSettings.selectableIcons,
                selectedCodePoint: _selectedIconCodePoint,
                onTap: _toggleIcon,
              ),

              const SizedBox(height: 16),

              // ── Submit button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Добавить категорию'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Icon picker grid ─────────────────────────────────────────────────────────

class _IconPicker extends StatelessWidget {
  final List<IconData> icons;
  final int? selectedCodePoint;
  final ValueChanged<IconData> onTap;

  const _IconPicker({
    required this.icons,
    required this.selectedCodePoint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: icons.map((icon) {
        final isSelected = selectedCodePoint == icon.codePoint;
        return GestureDetector(
          onTap: () => onTap(icon),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? null
                  : Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}
