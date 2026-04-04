import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages the bundled SQLite database lifecycle.
/// Copies from assets on first launch, opens read-only for queries.
class LocalDatabase {
  Database? _db;

  static const _assetPath = 'assets/data/career_path.db';
  static const _dbFileName = 'career_path.db';

  /// Copies the asset DB to the documents directory (if needed) and opens it.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbFileName);

    if (!File(dbPath).existsSync()) {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

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
    final result = <Map<String, dynamic>>[];
    for (final s in streams) {
      final roots = await db.rawQuery(
        'SELECT id FROM career_nodes WHERE stream_id = ? AND parent_id IS NULL ORDER BY id',
        [s['id']],
      );
      result.add({
        'id': s['id'],
        'slug': s['slug'],
        'name': s['name'],
        'intro': s['intro'],
        'root_node_ids': roots.map((r) => r['id']).toList(),
      });
    }
    return result;
  }

  // ── Root Nodes ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStreamRootNodes(int streamId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes '
      'WHERE stream_id = ? AND parent_id IS NULL ORDER BY id',
      [streamId],
    );
    return _enrichNodesWithChildren(rows, streamId: streamId);
  }

  // ── Children ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNodeChildren(int nodeId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id FROM career_nodes '
      'WHERE parent_id = ? ORDER BY id',
      [nodeId],
    );
    return _enrichNodesWithChildren(rows, parentId: nodeId);
  }

  // ── Leaf Details ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getNodeDetails(int nodeId) async {
    final nodes = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes WHERE id = ?',
      [nodeId],
    );
    if (nodes.isEmpty) {
      throw Exception('Node $nodeId not found');
    }
    final node = nodes.first;

    final books = await db.rawQuery(
      'SELECT b.id, b.title, b.author, b.url, b.description '
      'FROM books b JOIN node_books nb ON nb.book_id = b.id '
      'WHERE nb.node_id = ? ORDER BY b.title',
      [nodeId],
    );

    final institutes = await db.rawQuery(
      'SELECT i.id, i.name, i.city, i.website, i.description '
      'FROM institutes i JOIN node_institutes ni ON ni.institute_id = i.id '
      'WHERE ni.node_id = ? ORDER BY i.name',
      [nodeId],
    );

    final jobSectors = await db.rawQuery(
      'SELECT js.id, js.name, js.description '
      'FROM job_sectors js JOIN node_job_sectors njs ON njs.job_sector_id = js.id '
      'WHERE njs.node_id = ? ORDER BY js.name',
      [nodeId],
    );

    return {
      'id': node['id'],
      'slug': node['slug'],
      'name': node['name'],
      'intro': node['intro'],
      'books': books.map((b) => Map<String, dynamic>.from(b)).toList(),
      'institutes': institutes.map((i) => Map<String, dynamic>.from(i)).toList(),
      'job_sectors': jobSectors.map((j) => Map<String, dynamic>.from(j)).toList(),
    };
  }

  // ── All Nodes (for eager-load) ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllNodes() async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id, parent_id FROM career_nodes ORDER BY id',
    );
    return _enrichNodesWithChildren(rows);
  }

  // ── Helper ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _enrichNodesWithChildren(
    List<Map<String, dynamic>> rows, {
    int? streamId,
    int? parentId,
  }) async {
    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      final children = await db.rawQuery(
        'SELECT id FROM career_nodes WHERE parent_id = ? ORDER BY id',
        [r['id']],
      );
      final childIds = children.map((c) => c['id']).toList();
      result.add({
        'id': r['id'],
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': streamId ?? r['stream_id'],
        'parent_id': parentId ?? r['parent_id'],
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      });
    }
    return result;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
