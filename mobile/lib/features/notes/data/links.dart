import 'package:characters/characters.dart';

/// An address a link may point at: http(s) or mailto only (never `javascript:`
/// and the like). Bare domains get https. Null when it is not usable.
String? safeUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty || url.length > 2000 || RegExp(r'''[\s<>"'`]''').hasMatch(url)) return null;
  final String candidate;
  if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(url)) {
    candidate = url;
  } else if (RegExp(r'^[^@/]+\.[a-z]{2,}(/|$|\?|#)', caseSensitive: false).hasMatch(url)) {
    candidate = 'https://$url';
  } else if (RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$', caseSensitive: false).hasMatch(url)) {
    candidate = 'mailto:$url';
  } else {
    return null;
  }
  final u = Uri.tryParse(candidate);
  if (u == null) return null;
  final scheme = u.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') return null;
  if (scheme != 'mailto' && u.host.isEmpty) return null;
  // parentheses would end a markdown link early
  return candidate.replaceAll('(', '%28').replaceAll(')', '%29');
}

bool _pictograph(int r) =>
    (r >= 0x1F300 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    (r >= 0x25A0 && r <= 0x25FF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    const {0xA9, 0xAE, 0x203C, 0x2049, 0x2122, 0x2139, 0x24C2, 0x2934, 0x2935, 0x3030, 0x303D, 0x3297, 0x3299}.contains(r);

bool _regional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

/// One emoji and nothing else: a single grapheme that is a pictograph or a flag
/// (or a keycap such as 1\uFE0F\u20E3). Never markup, never words.
bool isEmoji(String value) {
  if (value.isEmpty || value.length > 24) return false;
  final parts = value.characters;
  if (parts.length != 1) return false;
  final runes = parts.first.runes.toList();
  if (runes.length >= 2 && _regional(runes[0]) && _regional(runes[1])) return true;
  if (runes.length >= 2 && (runes[0] == 0x23 || runes[0] == 0x2A || (runes[0] >= 0x30 && runes[0] <= 0x39)) && runes.contains(0x20E3)) return true;
  return _pictograph(runes.first);
}
