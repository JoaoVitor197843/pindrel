import 'dart:async';

import 'package:flutter/widgets.dart' show ChangeNotifier;

import 'blocks.dart';
import 'cover_spec.dart';
import 'links.dart';
import 'note_page.dart';
import 'workspace.dart';

/// Edits one page. Every change goes straight into the workspace (and so to the
/// database), and [saving] follows it.
class PageEditor extends ChangeNotifier {
  PageEditor(this.ws, this.id, {this.saveDelay = const Duration(milliseconds: 600)}) {
    ws.contentOf(id);
  }

  final Workspace ws;
  final String id;
  final Duration saveDelay;
  Timer? _timer;
  bool saving = false;

  /// Spoilers and secure blocks that are open right now (not stored: they close with the page).
  final Set<String> revealed = {};

  /// Told which files this page stopped using (nothing else uses them), or uses again.
  void Function(String fileId, bool unused) fileUsage = (_, _) {};

  NotePage? get page => ws.page(id);
  List<Block> get blocks => page?.content ?? const [];
  bool get readOnly => page?.trashed ?? true;
  ({int done, int total}) get progress => checklistProgress(blocks);
  List<OutlineItem> get outlineItems => outline(blocks);
  PageStats get stats => pageStats(blocks);
  List<NotePage> get related => ws.related(id);

  @override
  void dispose() {
    _timer?.cancel();
    // the body is written when the page closes
    ws.release(id);
    super.dispose();
  }

  void _changed() {
    ws.touch(id);
    saving = true;
    _timer?.cancel();
    _timer = Timer(saveDelay, () {
      saving = false;
      notifyListeners();
    });
    notifyListeners();
  }

  bool get _can => page != null && !readOnly;

  int _index(String blockId) => blocks.indexWhere((b) => b.id == blockId);

  Block? _find(String blockId, [BlockType? type]) {
    final b = blocks.where((x) => x.id == blockId).firstOrNull;
    return b != null && (type == null || b.type == type) ? b : null;
  }

  void setTitle(String title) {
    final p = page;
    if (p == null || !_can) return;
    final t = title.replaceAll(RegExp(r'\s+'), ' ');
    p.title = t.length > maxTitle ? t.substring(0, maxTitle) : t;
    _changed();
  }

  /// Inserts a new block after [afterId] (or at the end). Null at the block limit.
  Block? insert(BlockType type, {String? afterId, int? level, bool toggle = false}) {
    final p = page;
    if (p?.content == null || !_can || p!.content!.length >= maxBlocks) return null;
    final block = makeBlock(type, level: level, toggle: toggle);
    final found = afterId == null ? -1 : _index(afterId);
    final at = found < 0 ? p.content!.length : found + 1;
    p.content!.insert(at, block);
    _changed();
    return block;
  }

  void remove(String blockId) {
    final p = page;
    final i = _index(blockId);
    if (p?.content == null || i < 0 || !_can) return;
    final gone = p!.content!.removeAt(i);
    revealed.remove(blockId);
    _changed();
    _release(fileIdsOf([gone]));
  }

  bool _inUse(String fileId) {
    if (blocks.any((b) => b.fileId == fileId)) return true;
    return false;
  }

  void _release(List<String> ids) {
    for (final f in ids) {
      if (!_inUse(f)) fileUsage(f, true);
    }
  }

  void move(int from, int at) {
    final p = page;
    if (p?.content == null || !_can) return;
    if (moveItem(p!.content!, from, at)) _changed();
  }

  /// Menu move: one place up (-1) or down (+1).
  void moveBy(String blockId, int delta) {
    final i = _index(blockId);
    if (i < 0) return;
    final target = i + delta;
    if (target < 0 || target >= blocks.length) return;
    move(i, delta > 0 ? i + 2 : i - 1);
  }

  void setText(String blockId, String text) {
    final b = _find(blockId);
    if (b == null || b.text == null || !_can) return;
    b.text = text.length > maxText ? text.substring(0, maxText) : text;
    _changed();
  }

  /// Enter in the middle of a text block: what follows the caret becomes a new
  /// paragraph (or list item) right after it.
  Block? split(String blockId, int caret) {
    final b = _find(blockId);
    if (b == null || b.text == null) return null;
    final at = caret.clamp(0, b.text!.length);
    return splitText(blockId, b.text!.substring(0, at), b.text!.substring(at));
  }

  Block? splitText(String blockId, String head, String tail) {
    final b = _find(blockId);
    const ok = {BlockType.paragraph, BlockType.heading, BlockType.quote, BlockType.callout, BlockType.toggle, BlockType.spoiler, BlockType.bullet, BlockType.numbered};
    if (b == null || !ok.contains(b.type) || b.text == null || !_can) return null;
    final isItem = b.type == BlockType.bullet || b.type == BlockType.numbered;
    final made = insert(isItem ? b.type : BlockType.paragraph, afterId: blockId);
    if (made == null) return null;
    if (isItem) made.indent = b.indent ?? 0;
    b.text = head.length > maxText ? head.substring(0, maxText) : head;
    made.text = tail.length > maxText ? tail.substring(0, maxText) : tail;
    _changed();
    return made;
  }

  void setBody(String blockId, String body) {
    final b = _find(blockId);
    if (b == null || !_can || !(b.type == BlockType.toggle || (b.type == BlockType.heading && b.toggle))) return;
    b.body = body.length > maxText ? body.substring(0, maxText) : body;
    _changed();
  }

  /// A copy of a block right after it. A picked image of this session stays
  /// single (its temporary address belongs to the original).
  Block? duplicateBlock(String blockId) {
    final p = page;
    final i = _index(blockId);
    if (p?.content == null || i < 0 || !_can || p!.content!.length >= maxBlocks) return null;
    final src = p.content![i];
    if (src.type == BlockType.image && (src.fileId == null || src.fileId!.isEmpty)) return null;
    final copy = src.copy(id: newId());
    if (copy.type == BlockType.checklist) {
      copy.items = [for (final it in copy.items!) ChecklistItem(id: newId('i'), text: it.text, done: it.done)];
    }
    p.content!.insert(i + 1, copy);
    _changed();
    return copy;
  }

  /// Changes a text block into another kind, keeping the words. Secrets and
  /// spoilers never convert.
  bool turnInto(String blockId, BlockType type, {int level = 2, bool toggle = false}) {
    final p = page;
    final i = _index(blockId);
    if (p?.content == null || i < 0 || !_can) return false;
    final b = p!.content![i];
    if (!isTextType(b.type) && b.type != BlockType.toggle) return false;
    if (!isTextType(type) && type != BlockType.toggle) return false;
    final wantsToggle = type == BlockType.heading && toggle;
    if (b.type == type && (type != BlockType.heading || ((b.level ?? 2) == level && b.toggle == wantsToggle))) return false;
    final text = b.text ?? '';
    final next = Block(blockId, type, text: text);
    if (type == BlockType.toggle) next.body = '';
    if (type == BlockType.heading) {
      next.level = level == 2 ? null : level;
      if (wantsToggle) {
        next.toggle = true;
        next.body = b.type == BlockType.heading ? (b.body ?? '') : '';
      }
    }
    if (type == BlockType.bullet || type == BlockType.numbered) next.indent = 0;
    p.content![i] = next;
    _changed();
    return true;
  }

  /// Nests a list item one level deeper (+1) or brings it back (-1).
  bool indent(String blockId, int delta) {
    final b = _find(blockId);
    if (b == null || (b.type != BlockType.bullet && b.type != BlockType.numbered) || !_can) return false;
    final next = ((b.indent ?? 0) + delta).clamp(0, maxIndent);
    if (next == (b.indent ?? 0)) return false;
    b.indent = next;
    _changed();
    return true;
  }

  /// Enter on an empty list item: it comes out one level, and from the first
  /// level it stops being a list item.
  bool leaveList(String blockId) {
    final b = _find(blockId);
    if (b == null || (b.type != BlockType.bullet && b.type != BlockType.numbered)) return false;
    return (b.indent ?? 0) > 0 ? indent(blockId, -1) : turnInto(blockId, BlockType.paragraph);
  }

  void setTone(String blockId, CalloutTone tone) {
    final b = _find(blockId, BlockType.callout);
    if (b == null || !_can) return;
    b.tone = tone == CalloutTone.info ? null : tone;
    _changed();
  }

  /// Sets the address (and title) of a link card, a video, an audio or a PDF.
  /// An unsafe address is refused (false); media and PDFs take http(s) only.
  bool setUrl(String blockId, String url, [String title = '']) {
    final b = _find(blockId);
    final safe = safeUrl(url);
    if (b == null || !isUrlBlock(b) || !_can || safe == null) return false;
    if (b.type != BlockType.bookmark && !RegExp(r'^https?:', caseSensitive: false).hasMatch(safe)) return false;
    b.url = safe;
    final t = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    b.title = t.length > 200 ? t.substring(0, 200) : t;
    _changed();
    return true;
  }

  /// Points a page link at another page. Not itself, not one in the trash, not one in the vault.
  bool setPageLink(String blockId, String pageId) {
    final b = _find(blockId, BlockType.pagelink);
    final target = ws.page(pageId);
    if (b == null || !_can || target == null || target.id == id || target.trashed || target.locked) return false;
    b.pageId = target.id;
    b.title = target.title;
    _changed();
    return true;
  }

  /// Keeps the name a page link remembers in step with the page. A page that
  /// moved into the vault is forgotten by name.
  void syncPageLink(String blockId) {
    final b = _find(blockId, BlockType.pagelink);
    if (b == null || !_can) return;
    final target = ws.page(b.pageId ?? '');
    final name = target == null ? (b.title ?? '') : (target.locked ? '' : target.title);
    if (b.title != name) {
      b.title = name;
      _changed();
    }
  }

  void setIcon(String icon) {
    final p = page;
    if (p == null || !_can || (icon.isNotEmpty && !isEmoji(icon))) return;
    p.icon = icon;
    _changed();
  }

  void setCover(String key) {
    final p = page;
    if (p == null || !_can || !isCover(key)) return;
    p.cover = key;
    _changed();
  }

  void setLang(String blockId, String lang) {
    final b = _find(blockId, BlockType.code);
    if (b == null || !_can) return;
    b.lang = lang;
    _changed();
  }

  // checklist
  void toggleItem(String blockId, String itemId) {
    final item = _find(blockId, BlockType.checklist)?.items!.where((i) => i.id == itemId).firstOrNull;
    if (item == null || !_can) return;
    item.done = !item.done;
    _changed();
  }

  void setItemText(String blockId, String itemId, String text) {
    final item = _find(blockId, BlockType.checklist)?.items!.where((i) => i.id == itemId).firstOrNull;
    if (item == null || !_can) return;
    item.text = text.length > maxText ? text.substring(0, maxText) : text;
    _changed();
  }

  String? addItem(String blockId, [String? afterItemId]) {
    final b = _find(blockId, BlockType.checklist);
    if (b == null || !_can || b.items!.length >= maxItems) return null;
    final item = ChecklistItem(id: newId('i'));
    final at = afterItemId == null ? b.items!.length : b.items!.indexWhere((i) => i.id == afterItemId) + 1;
    b.items!.insert(at, item);
    _changed();
    return item.id;
  }

  /// Removes an item; the last one takes the whole checklist block with it.
  void removeItem(String blockId, String itemId) {
    final b = _find(blockId, BlockType.checklist);
    if (b == null || !_can) return;
    if (b.items!.length <= 1) return remove(blockId);
    b.items = [for (final i in b.items!) if (i.id != itemId) i];
    _changed();
  }

  // table
  TableColumn? _col(Block b, String colId) => b.cols!.where((c) => c.id == colId).firstOrNull;

  void setLabel(String blockId, String colId, String label) {
    final b = _find(blockId, BlockType.table);
    final col = b == null ? null : _col(b, colId);
    if (col == null || !_can) return;
    col.label = label.length > 80 ? label.substring(0, 80) : label;
    _changed();
  }

  void setCell(String blockId, int row, String colId, String text) {
    final b = _find(blockId, BlockType.table);
    if (b == null || !_can || row < 0 || row >= b.rows!.length || _col(b, colId) == null) return;
    b.rows![row][colId] = text.length > 2000 ? text.substring(0, 2000) : text;
    _changed();
  }

  String? addCol(String blockId) {
    final b = _find(blockId, BlockType.table);
    if (b == null || !_can || b.cols!.length >= maxCols) return null;
    final col = TableColumn(id: newId('c'), label: 'Coluna ${b.cols!.length + 1}');
    b.cols!.add(col);
    for (final r in b.rows!) {
      r[col.id] = '';
    }
    _changed();
    return col.id;
  }

  void addRow(String blockId) {
    final b = _find(blockId, BlockType.table);
    if (b == null || !_can || b.rows!.length >= maxRows) return;
    b.rows!.add({for (final c in b.cols!) c.id: ''});
    _changed();
  }

  /// A table keeps at least one column and one row.
  void removeCol(String blockId, String colId) {
    final b = _find(blockId, BlockType.table);
    if (b == null || !_can || b.cols!.length <= 1 || _col(b, colId) == null) return;
    b.cols = [for (final c in b.cols!) if (c.id != colId) c];
    for (final r in b.rows!) {
      r.remove(colId);
    }
    _changed();
  }

  void removeRow(String blockId, int row) {
    final b = _find(blockId, BlockType.table);
    if (b == null || !_can || b.rows!.length <= 1 || row < 0 || row >= b.rows!.length) return;
    b.rows!.removeAt(row);
    _changed();
  }

  void resizeCol(String blockId, String colId, num width) {
    final b = _find(blockId, BlockType.table);
    final col = b == null ? null : _col(b, colId);
    if (col == null || !_can || !width.isFinite) return;
    col.w = width.round().clamp(minColWidth, maxColWidth);
    _changed();
  }

  void moveCol(String blockId, int from, int at) {
    final b = _find(blockId, BlockType.table);
    if (b != null && _can && moveItem(b.cols!, from, at)) _changed();
  }

  void moveRow(String blockId, int from, int at) {
    final b = _find(blockId, BlockType.table);
    if (b != null && _can && moveItem(b.rows!, from, at)) _changed();
  }

  // image
  void setImage(String blockId, String? name, String? src) {
    final b = _find(blockId, BlockType.image);
    if (b == null || !_can) return;
    final had = b.fileId;
    b.name = name;
    b.src = src;
    b.fileId = null;
    _changed();
    if (had != null && had.isNotEmpty) _release([had]);
  }

  // spoiler / secure
  void reveal(String blockId, bool open) {
    open ? revealed.add(blockId) : revealed.remove(blockId);
    notifyListeners();
  }

  // tags
  bool addTag(String name, [TagColor color = TagColor.accent]) {
    final p = page;
    if (p == null || !_can) return false;
    final tag = ws.addTag(name.length > maxTagName ? name.substring(0, maxTagName) : name, color);
    if (tag == null || p.tags.contains(tag.id)) return false;
    p.tags.add(tag.id);
    _changed();
    return true;
  }

  void removeTag(String tagId) {
    final p = page;
    if (p == null || !_can || !p.tags.contains(tagId)) return;
    p.tags = [for (final t in p.tags) if (t != tagId) t];
    _changed();
  }

  void togglePin() {
    if (page != null && !readOnly) ws.togglePin(id);
  }

  /// Copying a page; null when it cannot be copied.
  ({String id, int images})? duplicate() {
    if (readOnly) return null;
    final made = ws.duplicate(id);
    return made == null ? null : (id: made.page.id, images: made.images);
  }
}
