import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/blocks.dart';
import '../../data/highlight.dart';
import 'ui.dart';

/// A text field that stays in step with a value kept elsewhere. The value
/// changes under it on a split, a conversion or an undo; typing flows the
/// other way through [onChanged].
class SyncedField extends StatefulWidget {
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.style,
    this.hint,
    this.multiline = true,
    this.focusNode,
    this.readOnly = false,
    this.onBackspaceEmpty,
    this.maxLength = maxText,
    this.align = TextAlign.start,
    this.decoration,
    this.codeLang,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextStyle? style;
  final String? hint;
  final bool multiline;
  final FocusNode? focusNode;
  final bool readOnly;
  final VoidCallback? onBackspaceEmpty;
  final int maxLength;
  final TextAlign align;
  final InputDecoration? decoration;

  /// When set the text is drawn with code colours for this language.
  final String? codeLang;

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = widget.codeLang == null ? TextEditingController(text: widget.value) : CodeController(widget.value, widget.codeLang!, widget.style);

  @override
  void didUpdateWidget(SyncedField old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (c is CodeController && widget.codeLang != null) c.lang = widget.codeLang!;
    if (widget.value != _c.text) {
      final at = _c.selection.baseOffset.clamp(0, widget.value.length);
      _c.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: _c.selection.isValid ? at : widget.value.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      style: widget.style,
      textAlign: widget.align,
      maxLines: widget.multiline ? null : 1,
      keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
      cursorColor: AppColors.accentBorder,
      decoration: widget.decoration ??
          InputDecoration(
            hintText: widget.hint,
            hintStyle: (widget.style ?? const TextStyle()).copyWith(color: AppColors.textMuted.withValues(alpha: 0.6)),
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
      onChanged: widget.onChanged,
    );
    final ringed = FocusRing(always: true, child: field);
    if (widget.onBackspaceEmpty == null) return ringed;
    // a hardware keyboard's Backspace on an empty field (a soft keyboard sends no key at all)
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.backspace && _c.text.isEmpty) {
          widget.onBackspaceEmpty!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ringed,
    );
  }
}

const _tokenColors = {
  TokenKind.comment: Color(0xFF9A968E),
  TokenKind.string: Color(0xFF6BB3A8),
  TokenKind.keyword: Color(0xFFD98A6C),
  TokenKind.number: Color(0xFFD1AD5A),
  TokenKind.text: AppColors.text,
};

/// A text controller that paints code with the same few colours the web uses (comments, strings, keywords, numbers).
class CodeController extends TextEditingController {
  CodeController(String text, this.lang, this.base) : super(text: text);
  String lang;
  final TextStyle? base;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final root = style ?? base ?? const TextStyle();
    if (value.composing.isValid && withComposing) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    return TextSpan(style: root, children: [
      for (final t in highlight(text, lang))
        TextSpan(text: t.text, style: TextStyle(color: _tokenColors[t.kind], fontStyle: t.kind == TokenKind.comment ? FontStyle.italic : null)),
    ]);
  }
}
