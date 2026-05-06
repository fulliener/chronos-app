import 'package:flutter/material.dart';

import '../services/app_settings.dart';

class CategorySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const CategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the category list changes in settings
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final labels = AppSettings.instance.categories;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: labels.map((label) {
            final isSelected = label == selected;
            return ChoiceChip(
              avatar: Icon(
                AppSettings.instance.iconDataFor(label),
                size: 18,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              label: Text(label),
              selected: isSelected,
              onSelected: enabled ? (_) => onChanged(label) : null,
              selectedColor: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? cs.onPrimary : cs.onSurface,
              ),
              side: BorderSide.none,
              showCheckmark: false,
            );
          }).toList(),
        );
      },
    );
  }
}
