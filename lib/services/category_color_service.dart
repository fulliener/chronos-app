import 'package:flutter/material.dart';

/// Provides theme-aware colors in the "Deep Industrial" aesthetic:
/// muted, desaturated tones that look premium on both dark (#121212)
/// and light (#FFFFFF) backgrounds.
///
/// Palette cycling rules:
///   • 6 base presets (indices 0–5).
///   • Beyond 6: each extra "round" reduces HSV saturation and value slightly,
///     keeping the industrial/muted feel at any category count.
///   • Dark  theme: auto-lighten colors whose luminance < 0.15 so they are
///     clearly visible against near-black backgrounds.
///   • Light theme: auto-darken colors whose luminance > 0.72 so they contrast
///     against white.
class CategoryColorService {
  CategoryColorService._();

  // ─── Deep Industrial base palette (6 colors) ──────────────────────────────

  /// Ordered from darkest to lightest so adjacent categories get
  /// maximally distinct values.
  static const List<Color> _palette = [
    Color(0xFF4A4E69), // 0 — Muted Slate        (blue-violet)
    Color(0xFF555D50), // 1 — Olive Drab          (warm green)
    Color(0xFFA5A5A5), // 2 — Silver Leaf         (neutral accent)
    Color(0xFF3D3D3D), // 3 — Anthracite          (dark neutral)
    Color(0xFF6B705C), // 4 — Sage Grey           (khaki-green)
    Color(0xFF2C2C2E), // 5 — Dark Graphite       (near-black)
  ];

  // ─── Named overrides for built-in categories ──────────────────────────────

  static const Map<String, Color> _named = {
    'Работа': Color(0xFF4A4E69), // Muted Slate
    'Учёба':  Color(0xFF555D50), // Olive Drab
    'Отдых':  Color(0xFF6B705C), // Sage Grey
    'Спорт':  Color(0xFFA5A5A5), // Silver Leaf
    'Другое': Color(0xFF3D3D3D), // Anthracite
  };

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Returns a contrast-safe Deep Industrial color for [category] at [index].
  /// Pass [isDark] = `Theme.of(context).brightness == Brightness.dark`.
  static Color colorFor(
    String category,
    int index, {
    required bool isDark,
  }) {
    final base = _named[category] ?? _industrialAt(index);
    return isDark ? _ensureDarkVisible(base) : _ensureLightVisible(base);
  }

  // ─── Industrial palette generation for > 6 categories ────────────────────

  /// Cycles the 6 base colors while reducing HSV saturation and value
  /// each "round" — further categories become progressively more washed-out,
  /// maintaining the muted industrial vibe.
  static Color _industrialAt(int index) {
    final base = _palette[index % _palette.length];
    final round = index ~/ _palette.length; // 0 for first 6, 1 for next 6, …

    if (round == 0) return base;

    final hsv = HSVColor.fromColor(base);

    // Each round: -12 % saturation, -8 % value (clamped to safe minimums).
    final s = (hsv.saturation - round * 0.12).clamp(0.08, 1.0);
    final v = (hsv.value      - round * 0.08).clamp(0.25, 1.0);

    return HSVColor.fromAHSV(1.0, hsv.hue, s, v).toColor();
  }

  // ─── Theme contrast guards ────────────────────────────────────────────────

  /// Dark bg ≈ #121212 (lum 0.005).  Target: lum ≥ 0.15 → contrast ≥ 2.9.
  static Color _ensureDarkVisible(Color color) {
    const target = 0.15;
    if (color.computeLuminance() >= target) return color;
    Color c = color;
    for (int step = 1; step <= 12; step++) {
      c = Color.lerp(color, const Color(0xFFCCCCCC), step * 0.10)!;
      if (c.computeLuminance() >= target) break;
    }
    return c;
  }

  /// Light bg ≈ #FFFFFF (lum 1.0).  Target: lum ≤ 0.55 → contrast ≥ 2.3.
  static Color _ensureLightVisible(Color color) {
    const target = 0.55;
    if (color.computeLuminance() <= target) return color;
    Color c = color;
    for (int step = 1; step <= 10; step++) {
      c = Color.lerp(color, Colors.black, step * 0.10)!;
      if (c.computeLuminance() <= target) break;
    }
    return c;
  }
}
