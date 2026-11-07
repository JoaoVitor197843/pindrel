import 'blocks.dart';

enum TagColor { accent, rust, blue, gold, plum, teal }

class Tag {
  const Tag(this.id, this.name, this.color);
  final String id, name;
  final TagColor color;
}

/// A page. [content] stays null until the page is opened: lists only need the
/// metadata and an excerpt, and the body of every page must not sit in memory.
class NotePage {
  NotePage({
    required this.id,
    this.title = 'Sem título',
    this.excerpt = '',
    List<String>? tags,
    required this.updated,
    required this.created,
    this.blocks = 0,
    this.content,
    this.locked = false,
    this.trashed = false,
    this.pinned = false,
    this.icon = '',
    this.cover = '',
  }) : tags = tags ?? [];

  final String id;
  String title, excerpt, icon, cover;
  List<String> tags;
  int updated, created, blocks;
  List<Block>? content;
  bool locked, trashed, pinned;
}

const maxTitle = 120;
const maxTagName = 24;

class Settings {
  const Settings({this.useTrash = true, this.retention = 30});
  final bool useTrash;

  /// Days a trashed page is kept.
  final int retention;

  Settings copy({bool? useTrash, int? retention}) => Settings(useTrash: useTrash ?? this.useTrash, retention: (retention ?? this.retention).clamp(7, 90));
}
