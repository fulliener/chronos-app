import 'package:flutter/material.dart';

class StopwatchDisplay extends StatelessWidget {
  final int elapsedSeconds;
  final bool isRunning;

  const StopwatchDisplay({
    super.key,
    required this.elapsedSeconds,
    required this.isRunning,
  });

  String get _formatted {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: BoxDecoration(
        color: isRunning
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: (isRunning ? colorScheme.primary : Colors.grey)
                .withAlpha(isRunning ? 60 : 30),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w200,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isRunning
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            child: Text(_formatted),
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            opacity: isRunning ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Запись идёт...',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
