import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Manages the bundled SQLite database lifecycle.
/// Always copies from assets to ensure latest data.
class LocalDatabase {
  Database? _db;

  static const _assetPath = 'assets/data/career_path.db';
  static const _dbFileName = 'career_path.db';

  Future<void> init() async {
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbFileName);

    // Always copy from assets to ensure latest DB
    await Directory(dbDir).create(recursive: true);
    final data = await rootBundle.load(_assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await File(dbPath).writeAsBytes(bytes, flush: true);

    _db = await openDatabase(dbPath, readOnly: true);
  }

  Database get db {
    if (_db == null) throw StateError('LocalDatabase not initialized');
    return _db!;
  }

  // ── Streams ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStreams() async {
    final streams = await db.rawQuery(
      'SELECT id, slug, name, intro FROM streams ORDER BY id',
    );
    final roots = await db.rawQuery(
      'SELECT id, stream_id FROM career_nodes WHERE parent_id IS NULL ORDER BY id',
    );
    // Group root node IDs by stream
    final rootsByStream = <int, List<int>>{};
    for (final r in roots) {
      final sid = r['stream_id'] as int;
      (rootsByStream[sid] ??= []).add(r['id'] as int);
    }
    return streams.map((s) {
      final sid = s['id'] as int;
      return {
        'id': sid,
        'slug': s['slug'],
        'name': s['name'],
        'intro': s['intro'],
        'root_node_ids': rootsByStream[sid] ?? [],
      };
    }).toList();
  }

  // ── Root Nodes ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStreamRootNodes(int streamId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes '
      'WHERE stream_id = ? AND parent_id IS NULL ORDER BY id',
      [streamId],
    );
    final nodeIds = rows.map((r) => r['id'] as int).toList();
    final childMap = await _buildChildMap(nodeIds);
    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': streamId,
        'parent_id': null,
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Children ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNodeChildren(int nodeId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id FROM career_nodes '
      'WHERE parent_id = ? ORDER BY id',
      [nodeId],
    );
    final nodeIds = rows.map((r) => r['id'] as int).toList();
    final childMap = await _buildChildMap(nodeIds);
    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': r['stream_id'],
        'parent_id': nodeId,
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Leaf Details ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getNodeDetails(int nodeId) async {
    final nodes = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes WHERE id = ?',
      [nodeId],
    );
    if (nodes.isEmpty) throw Exception('Node $nodeId not found');
    final node = nodes.first;

    // Run all 3 resource queries in parallel
    final results = await Future.wait([
      db.rawQuery(
        'SELECT b.id, b.title, b.author, b.url, b.description '
        'FROM books b JOIN node_books nb ON nb.book_id = b.id '
        'WHERE nb.node_id = ? ORDER BY b.title',
        [nodeId],
      ),
      db.rawQuery(
        'SELECT i.id, i.name, i.city, i.website, i.description '
        'FROM institutes i JOIN node_institutes ni ON ni.institute_id = i.id '
        'WHERE ni.node_id = ? ORDER BY i.name',
        [nodeId],
      ),
      db.rawQuery(
        'SELECT js.id, js.name, js.description '
        'FROM job_sectors js JOIN node_job_sectors njs ON njs.job_sector_id = js.id '
        'WHERE njs.node_id = ? ORDER BY js.name',
        [nodeId],
      ),
    ]);

    return {
      'id': node['id'],
      'slug': node['slug'],
      'name': node['name'],
      'intro': node['intro'],
      'books': results[0].map((b) => Map<String, dynamic>.from(b)).toList(),
      'institutes': results[1].map((i) => Map<String, dynamic>.from(i)).toList(),
      'job_sectors': results[2].map((j) => Map<String, dynamic>.from(j)).toList(),
    };
  }

  // ── All Nodes (for eager-load) — 2 queries total ───────────────────────

  Future<List<Map<String, dynamic>>> getAllNodes() async {
    // Query 1: all nodes
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id, parent_id '
      'FROM career_nodes ORDER BY id',
    );
    // Query 2: all parent→child relationships in one shot
    final allChildren = await db.rawQuery(
      'SELECT parent_id, id FROM career_nodes '
      'WHERE parent_id IS NOT NULL ORDER BY parent_id, id',
    );
    final childMap = <int, List<int>>{};
    for (final c in allChildren) {
      final pid = c['parent_id'] as int;
      (childMap[pid] ??= []).add(c['id'] as int);
    }

    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': r['stream_id'],
        'parent_id': r['parent_id'],
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Helper: batch child lookup ──────────────────────────────────────────

  Future<Map<int, List<int>>> _buildChildMap(List<int> parentIds) async {
    if (parentIds.isEmpty) return {};
    final placeholders = List.filled(parentIds.length, '?').join(',');
    final children = await db.rawQuery(
      'SELECT parent_id, id FROM career_nodes '
      'WHERE parent_id IN ($placeholders) ORDER BY parent_id, id',
      parentIds,
    );
    final map = <int, List<int>>{};
    for (final c in children) {
      final pid = c['parent_id'] as int;
      (map[pid] ??= []).add(c['id'] as int);
    }
    return map;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
