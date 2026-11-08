import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'blocks.dart';
import 'note_page.dart';

/// The notes on the device, in SQLite (on disk, so the bodies never have to sit
/// in memory together). Lists read only the metadata; a body is read when the
/// page is opened.
class NotesDb {
  NotesDb(this._db) {
    _migrate();
  }

  factory NotesDb.inMemory() => NotesDb(sqlite3.openInMemory());
  factory NotesDb.open(String path) => NotesDb(sqlite3.open(path));

  final Database _db;

  static const _version = 1;

  void _migrate() {
    final v = _db.select('PRAGMA user_version').first.values.first as int;
    if (v >= _version) return;
    _db.execute('BEGIN');
    try {
      _db.execute('''
        CREATE TABLE tags(id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, pos INTEGER NOT NULL);
        CREATE TABLE pages(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, excerpt TEXT NOT NULL, tags TEXT NOT NULL,
          updated INTEGER NOT NULL, created INTEGER NOT NULL, blocks INTEGER NOT NULL, content TEXT,
          locked INTEGER NOT NULL, trashed INTEGER NOT NULL, pinned INTEGER NOT NULL, icon TEXT NOT NULL, cover TEXT NOT NULL
        );
        CREATE INDEX pages_updated ON pages(updated DESC);
        CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
      ''');
      _db.execute('PRAGMA user_version = $_version');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void dispose() => _db.close();

  // pages

  /// Every page without its body.
  List<NotePage> pages() => [
        for (final r in _db.select('SELECT id,title,excerpt,tags,updated,created,blocks,locked,trashed,pinned,icon,cover FROM pages ORDER BY updated DESC'))
          NotePage(
            id: r['id'] as String,
            title: r['title'] as String,
            excerpt: r['excerpt'] as String,
            tags: _tagList(r['tags'] as String),
            updated: r['updated'] as int,
            created: r['created'] as int,
            blocks: r['blocks'] as int,
            locked: r['locked'] == 1,
            trashed: r['trashed'] == 1,
            pinned: r['pinned'] == 1,
            icon: r['icon'] as String,
            cover: r['cover'] as String,
          ),
      ];

  static List<String> _tagList(String json) {
    try {
      final d = jsonDecode(json);
      return d is List ? [for (final t in d) if (t is String) t] : [];
    } catch (_) {
      return [];
    }
  }

  /// Writes the metadata (and the body too when the page has one open).
  void savePage(NotePage p, {bool content = false}) {
    _db.execute(
      '''INSERT INTO pages(id,title,excerpt,tags,updated,created,blocks,content,locked,trashed,pinned,icon,cover)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(id) DO UPDATE SET title=excluded.title, excerpt=excluded.excerpt, tags=excluded.tags, updated=excluded.updated,
           created=excluded.created, blocks=excluded.blocks, ${content ? 'content=excluded.content,' : ''} locked=excluded.locked,
           trashed=excluded.trashed, pinned=excluded.pinned, icon=excluded.icon, cover=excluded.cover''',
      [
        p.id, p.title, p.excerpt, jsonEncode(p.tags), p.updated, p.created, p.blocks,
        content && p.content != null ? jsonEncode([for (final b in p.content!) b.toJson()]) : null,
        p.locked ? 1 : 0, p.trashed ? 1 : 0, p.pinned ? 1 : 0, p.icon, p.cover,
      ],
    );
  }

  /// The body of a page; null when the page has none stored yet.
  List<Block>? content(String id) {
    final rows = _db.select('SELECT content FROM pages WHERE id=?', [id]);
    if (rows.isEmpty) return null;
    final raw = rows.first['content'];
    if (raw is! String) return null;
    try {
      final d = jsonDecode(raw);
      if (d is! List) return null;
      return [
        for (final j in d.take(maxBlocks))
          ?Block.fromJson(j),
      ];
    } catch (_) {
      return null;
    }
  }

  void deletePages(Iterable<String> ids) {
    _db.execute('BEGIN');
    try {
      for (final id in ids) {
        _db.execute('DELETE FROM pages WHERE id=?', [id]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Bodies of every page, one at a time (search through blocks, file clean-up).
  Iterable<(String, List<Block>)> bodies() sync* {
    for (final r in _db.select('SELECT id FROM pages WHERE content IS NOT NULL')) {
      final id = r['id'] as String;
      final c = content(id);
      if (c != null) yield (id, c);
    }
  }

  // tags

  List<Tag> tags() => [
        for (final r in _db.select('SELECT id,name,color FROM tags ORDER BY pos'))
          Tag(r['id'] as String, r['name'] as String, TagColor.values.where((c) => c.name == r['color']).firstOrNull ?? TagColor.accent),
      ];

  void saveTag(Tag t, int pos) => _db.execute(
        'INSERT INTO tags(id,name,color,pos) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,color=excluded.color,pos=excluded.pos',
        [t.id, t.name, t.color.name, pos],
      );

  // settings

  Settings settings() {
    final m = {for (final r in _db.select('SELECT key,value FROM settings')) r['key'] as String: r['value'] as String};
    return Settings(useTrash: m['useTrash'] != 'false', retention: (int.tryParse(m['retention'] ?? '') ?? 30).clamp(7, 90));
  }

  void saveSettings(Settings s) {
    _db.execute('BEGIN');
    try {
      _db.execute("INSERT INTO settings(key,value) VALUES('useTrash',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", ['${s.useTrash}']);
      _db.execute("INSERT INTO settings(key,value) VALUES('retention',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", ['${s.retention}']);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
