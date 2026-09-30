import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AlbumItem {
  final int? id;
  final String filename;
  final String filepath;
  final String type; // 'encoded', 'decoded', 'received'
  final String encryptionType; // 'passkey', 'biometric', 'both', 'password'
  final int timestamp;
  final String thumbnailPath;

  AlbumItem({
    this.id,
    required this.filename,
    required this.filepath,
    required this.type,
    required this.encryptionType,
    required this.timestamp,
    required this.thumbnailPath,
  });

  bool get isEncrypted => type == 'encoded' || type == 'received';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filename': filename,
      'filepath': filepath,
      'type': type,
      'encryption_type': encryptionType,
      'timestamp': timestamp,
      'thumbnail_path': thumbnailPath,
    };
  }

  factory AlbumItem.fromMap(Map<String, dynamic> map) {
    return AlbumItem(
      id: map['id'] as int?,
      filename: map['filename'] as String? ?? 'file',
      filepath: map['filepath'] as String? ?? '',
      type: map['type'] as String? ?? 'encoded',
      encryptionType: map['encryption_type'] as String? ?? 'passkey',
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
    );
  }
}

class AlbumDb {
  static final AlbumDb _instance = AlbumDb._internal();
  factory AlbumDb() => _instance;
  AlbumDb._internal();

  static const String _tableName = 'album';
  Database? _database;
  bool _useInMemoryFallback = false;
  final List<AlbumItem> _inMemoryItems = [];
  int _nextId = 1;

  final _dbChangeController = StreamController<void>.broadcast();
  Stream<void> get onDbChanged => _dbChangeController.stream;

  Future<Database?> get database async {
    if (_useInMemoryFallback) return null;
    if (_database != null) return _database!;
    try {
      _database = await _initDb();
      return _database;
    } catch (e) {
      if (kDebugMode) print('Sqflite init failed, using in-memory store: $e');
      _useInMemoryFallback = true;
      return null;
    }
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tricrypt_album.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            filepath TEXT NOT NULL,
            type TEXT NOT NULL,
            encryption_type TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            thumbnail_path TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertItem(AlbumItem item) async {
    try {
      final db = await database;
      if (db != null) {
        final id = await db.insert(
          _tableName,
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _dbChangeController.add(null);
        return id;
      }
    } catch (_) {}

    final id = _nextId++;
    final storedItem = AlbumItem(
      id: id,
      filename: item.filename,
      filepath: item.filepath,
      type: item.type,
      encryptionType: item.encryptionType,
      timestamp: item.timestamp,
      thumbnailPath: item.thumbnailPath,
    );
    _inMemoryItems.insert(0, storedItem);
    _dbChangeController.add(null);
    return id;
  }

  Future<List<AlbumItem>> getAllItems() async {
    try {
      final db = await database;
      if (db != null) {
        final List<Map<String, dynamic>> maps = await db.query(
          _tableName,
          orderBy: 'timestamp DESC',
        );
        return List.generate(maps.length, (i) => AlbumItem.fromMap(maps[i]));
      }
    } catch (_) {}
    return List.from(_inMemoryItems);
  }

  Future<List<AlbumItem>> getEncryptedItems() async {
    try {
      final db = await database;
      if (db != null) {
        final List<Map<String, dynamic>> maps = await db.query(
          _tableName,
          where: 'type = ? OR type = ?',
          whereArgs: ['encoded', 'received'],
          orderBy: 'timestamp DESC',
        );
        return List.generate(maps.length, (i) => AlbumItem.fromMap(maps[i]));
      }
    } catch (_) {}
    return _inMemoryItems
        .where((i) => i.type == 'encoded' || i.type == 'received')
        .toList();
  }

  Future<List<AlbumItem>> getDecodedItems() async {
    try {
      final db = await database;
      if (db != null) {
        final List<Map<String, dynamic>> maps = await db.query(
          _tableName,
          where: 'type = ?',
          whereArgs: ['decoded'],
          orderBy: 'timestamp DESC',
        );
        return List.generate(maps.length, (i) => AlbumItem.fromMap(maps[i]));
      }
    } catch (_) {}
    return _inMemoryItems.where((i) => i.type == 'decoded').toList();
  }

  Future<int> getEncryptedCount() async {
    try {
      final db = await database;
      if (db != null) {
        final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM $_tableName WHERE type = "encoded" OR type = "received"',
        ));
        return count ?? 0;
      }
    } catch (_) {}
    return _inMemoryItems
        .where((i) => i.type == 'encoded' || i.type == 'received')
        .length;
  }

  Future<AlbumItem?> getItemById(int id) async {
    try {
      final db = await database;
      if (db != null) {
        final maps = await db.query(
          _tableName,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (maps.isEmpty) return null;
        return AlbumItem.fromMap(maps.first);
      }
    } catch (_) {}
    try {
      return _inMemoryItems.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<int> deleteItem(int id) async {
    try {
      final db = await database;
      if (db != null) {
        final result = await db.delete(
          _tableName,
          where: 'id = ?',
          whereArgs: [id],
        );
        _dbChangeController.add(null);
        return result;
      }
    } catch (_) {}
    _inMemoryItems.removeWhere((i) => i.id == id);
    _dbChangeController.add(null);
    return 1;
  }

  Future<void> clearAll() async {
    try {
      final db = await database;
      if (db != null) {
        await db.delete(_tableName);
      }
    } catch (_) {}
    _inMemoryItems.clear();
    _dbChangeController.add(null);
  }
}
