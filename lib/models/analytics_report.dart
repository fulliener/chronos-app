import 'package:flutter/material.dart';

enum InsightType { positive, warning, neutral, info }

class InsightItem {
  final IconData icon;
  final String title;
  final String message;
  final InsightType type;

  const InsightItem({
    required this.icon,
    required this.title,
    required this.message,
    required this.type,
  });
}

class AnalyticsReport {
  final InsightItem? trendInsight;
  final InsightItem? goalForecast;
  final InsightItem? burnoutWarning;
  final InsightItem? peakProductivity;

  const AnalyticsReport({
    this.trendInsight,
    this.goalForecast,
    this.burnoutWarning,
    this.peakProductivity,
  });

  /// Burnout always first, then trend, then goal, then peak.
  List<InsightItem> get items => [
        if (burnoutWarning != null) burnoutWarning!,
        if (trendInsight != null) trendInsight!,
        if (goalForecast != null) goalForecast!,
        if (peakProductivity != null) peakProductivity!,
      ];

  bool get isEmpty => items.isEmpty;
}
