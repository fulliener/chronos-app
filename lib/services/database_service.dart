import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/goal.dart';
import '../models/task_session.dart';

class DatabaseService {
  static const String _dbName = 'time_tracker.db';
  static const int _dbVersion = 2;
  static const String _tableName = 'task_sessions';
  static const String _goalsTable = 'goals';

  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._internal();

  factory DatabaseService() {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
        'База данных SQLite недоступна в браузере. '
        'Запустите приложение на эмуляторе Android/iOS или десктопной платформе.',
      );
    }
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        task_name       TEXT    NOT NULL,
        category        TEXT    NOT NULL,
        start_time      TEXT    NOT NULL,
        end_time        TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createGoalsTable(db);
  }

  Future<void> _createGoalsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_goalsTable (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        category_name   TEXT    NOT NULL UNIQUE,
        daily_minutes   INTEGER NOT NULL DEFAULT 0,
        weekly_minutes  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createGoalsTable(db);
    }
  }

  // ─── CREATE ────────────────────────────────────────────────────────────────

  Future<TaskSession> insertSession(TaskSession session) async {
    final db = await database;
    final id = await db.insert(
      _tableName,
      session.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return session.copyWith(id: id);
  }

  // ─── READ ──────────────────────────────────────────────────────────────────

  Future<List<TaskSession>> getAllSessions() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      orderBy: 'start_time DESC',
    );
    return maps.map(TaskSession.fromMap).toList();
  }

  Future<TaskSession?> getSessionById(int id) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TaskSession.fromMap(maps.first);
  }

  Future<List<TaskSession>> getSessionsByCategory(String category) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'start_time DESC',
    );
    return maps.map(TaskSession.fromMap).toList();
  }

  Future<List<TaskSession>> getSessionsByDateRange(
    DateTime from,
    DateTime to,
  ) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'start_time BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'start_time DESC',
    );
    return maps.map(TaskSession.fromMap).toList();
  }

  Future<List<String>> getDistinctCategories() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT category FROM $_tableName ORDER BY category',
    );
    return result.map((row) => row['category'] as String).toList();
  }

  Future<int> getTotalDurationByCategory(String category) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(duration_seconds) as total FROM $_tableName WHERE category = ?',
      [category],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // ─── UPDATE ────────────────────────────────────────────────────────────────

  Future<int> updateSession(TaskSession session) async {
    final db = await database;
    return db.update(
      _tableName,
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  // ─── DELETE ────────────────────────────────────────────────────────────────

  Future<int> deleteSession(int id) async {
    final db = await database;
    return db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllSessions() async {
    final db = await database;
    return db.delete(_tableName);
  }

  // ─── GOALS ─────────────────────────────────────────────────────────────────

  Future<Goal> upsertGoal(Goal goal) async {
    final db = await database;
    final id = await db.insert(
      _goalsTable,
      goal.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return goal.copyWith(id: id);
  }

  Future<List<Goal>> getAllGoals() async {
    final db = await database;
    final maps = await db.query(_goalsTable, orderBy: 'category_name ASC');
    return maps.map(Goal.fromMap).toList();
  }

  Future<Goal?> getGoalByCategory(String categoryName) async {
    final db = await database;
    final maps = await db.query(
      _goalsTable,
      where: 'category_name = ?',
      whereArgs: [categoryName],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Goal.fromMap(maps.first);
  }

  Future<int> deleteGoal(int id) async {
    final db = await database;
    return db.delete(_goalsTable, where: 'id = ?', whereArgs: [id]);
  }

  // ─── GOAL PROGRESS ─────────────────────────────────────────────────────────

  /// Сумма секунд для категории за сегодня (00:00 — текущий момент).
  Future<int> getTodayDurationByCategory(String category) async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final result = await db.rawQuery(
      '''
      SELECT SUM(duration_seconds) AS total
      FROM $_tableName
      WHERE category = ?
        AND start_time >= ?
      ''',
      [category, todayStart.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Сумма секунд для категории за последние 7 дней (от начала текущей недели).
  Future<int> getWeekDurationByCategory(String category) async {
    final db = await database;
    final now = DateTime.now();
    // Начало недели — понедельник текущей недели
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final result = await db.rawQuery(
      '''
      SELECT SUM(duration_seconds) AS total
      FROM $_tableName
      WHERE category = ?
        AND start_time >= ?
      ''',
      [category, weekStart.toIso8601String()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // ─── UTILITY ───────────────────────────────────────────────────────────────

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
