/// Case- and accent-insensitive text for searching (the web's `fold`).
///
/// Dart's core library has no Unicode normalisation, so the Latin letters a
/// Portuguese note can hold are mapped by hand; anything else is only lowered.
const _groups = <String, String>{
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľł',
  'n': 'ñńņň',
  'o': 'òóôõöøōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţťŧ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'ss': 'ß',
  'ae': 'æ',
  'oe': 'œ',
};

final Map<int, String> _map = {
  for (final e in _groups.entries)
    for (final r in e.value.runes) r: e.key,
};

String fold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    // combining marks (input that is already decomposed) are dropped
    if (r >= 0x300 && r <= 0x36F) continue;
    b.write(_map[r] ?? String.fromCharCode(r));
  }
  return b.toString();
}

/// Like [fold] but one character in, one character out (so a match position in
/// the folded text is the same position in the original). Letters that fold to
/// two characters (ß, æ, œ) keep their lowercase form.
String foldKeepingLength(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final m = _map[r];
    b.write(m != null && m.length == 1 ? m : String.fromCharCode(r));
  }
  return b.toString();
}
