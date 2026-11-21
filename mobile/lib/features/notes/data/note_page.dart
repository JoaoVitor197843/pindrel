import '../../../core/performance/frame_pacer.dart';
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

/// The smallest and the largest the body text of the pages is made, as a factor of its size.
const minTextScale = 0.7, maxTextScale = 2.0, textScaleStep = 0.1;

class Settings {
  const Settings({this.useTrash = true, this.retention = 30, this.textScale = 1.0, this.power = PowerMode.auto});
  final bool useTrash;

  /// Days a trashed page is kept.
  final int retention;

  /// How much larger (or smaller) the text of the pages is than its normal size (Ctrl +, Ctrl -, the magnifier).
  final double textScale;

  /// Configurações > Energia: how many frames the app draws a second (see [PowerMode]).
  final PowerMode power;

  /// A scale brought to the range and to a step of a tenth, so that going up and down always lands on the same sizes.
  static double cleanScale(double v) => v.isNaN ? 1.0 : (v.clamp(minTextScale, maxTextScale) * 10).round() / 10; // tenths as integers: 7 / 10 is 0.7 exactly, 7 * 0.1 is not

  Settings copy({bool? useTrash, int? retention, double? textScale, PowerMode? power}) => Settings(
    useTrash: useTrash ?? this.useTrash,
    retention: (retention ?? this.retention).clamp(7, 90),
    textScale: cleanScale(textScale ?? this.textScale),
    power: power ?? this.power,
  );
}
