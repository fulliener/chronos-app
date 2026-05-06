class Goal {
  final int? id;
  final String categoryName;
  final int dailyMinutes;
  final int weeklyMinutes;

  const Goal({
    this.id,
    required this.categoryName,
    required this.dailyMinutes,
    required this.weeklyMinutes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category_name': categoryName,
      'daily_minutes': dailyMinutes,
      'weekly_minutes': weeklyMinutes,
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'] as int?,
      categoryName: map['category_name'] as String,
      dailyMinutes: map['daily_minutes'] as int,
      weeklyMinutes: map['weekly_minutes'] as int,
    );
  }

  Goal copyWith({
    int? id,
    String? categoryName,
    int? dailyMinutes,
    int? weeklyMinutes,
  }) {
    return Goal(
      id: id ?? this.id,
      categoryName: categoryName ?? this.categoryName,
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
      weeklyMinutes: weeklyMinutes ?? this.weeklyMinutes,
    );
  }
}
