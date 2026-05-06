class TaskSession {
  final int? id;
  final String taskName;
  final String category;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;

  const TaskSession({
    this.id,
    required this.taskName,
    required this.category,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
  });

  bool get isCompleted => endTime != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_name': taskName,
      'category': category,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }

  factory TaskSession.fromMap(Map<String, dynamic> map) {
    return TaskSession(
      id: map['id'] as int?,
      taskName: map['task_name'] as String,
      category: map['category'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      durationSeconds: map['duration_seconds'] as int,
    );
  }

  TaskSession copyWith({
    int? id,
    String? taskName,
    String? category,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
  }) {
    return TaskSession(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      category: category ?? this.category,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  @override
  String toString() {
    return 'TaskSession(id: $id, taskName: $taskName, category: $category, '
        'startTime: $startTime, endTime: $endTime, '
        'durationSeconds: $durationSeconds)';
  }
}
