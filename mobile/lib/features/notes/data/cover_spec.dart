// A page cover is a short text spec, never a drawing: what is saved is always something this file knows how to draw
// (the same specs the web writes, so a page keeps its cover on every device).

class PaletteColor {
  const PaletteColor(this.id, this.label, this.hex);
  final String id, label;
  final int hex; // 0xRRGGBB
}

const palette = <PaletteColor>[
  PaletteColor('verde', 'Verde', 0x6b8e61),
  PaletteColor('lima', 'Lima', 0xa8c45a),
  PaletteColor('turquesa', 'Turquesa', 0x6bb3a8),
  PaletteColor('ceu', 'Céu', 0x6fb8e0),
  PaletteColor('azul', 'Azul', 0x8aa8c4),
  PaletteColor('violeta', 'Violeta', 0x9a86d4),
  PaletteColor('ameixa', 'Ameixa', 0xc196ad),
  PaletteColor('rosa', 'Rosa', 0xd9788f),
  PaletteColor('ferrugem', 'Ferrugem', 0xd98a6c),
  PaletteColor('ouro', 'Ouro', 0xd1ad5a),
  PaletteColor('areia', 'Areia', 0xcdbd9a),
  PaletteColor('ardosia', 'Ardósia', 0x7a8794),
  PaletteColor('grafite', 'Grafite', 0x4a4a44),
];

class Mix {
  const Mix(this.key, this.label, this.stops);
  final String key, label;
  final List<String> stops;
}

const mixes = <Mix>[
  Mix('arco-iris', 'Arco-íris', ['rosa', 'ferrugem', 'ouro', 'lima', 'turquesa', 'ceu', 'violeta']),
  Mix('por-do-sol', 'Pôr do sol', ['violeta', 'rosa', 'ferrugem', 'ouro']),
  Mix('aurora', 'Aurora', ['verde', 'turquesa', 'ceu', 'violeta']),
  Mix('mar', 'Mar', ['azul', 'ceu', 'turquesa']),
  Mix('floresta', 'Floresta', ['grafite', 'verde', 'lima']),
  Mix('brasa', 'Brasa', ['grafite', 'ferrugem', 'ouro']),
  Mix('algodao-doce', 'Algodão-doce', ['ceu', 'ameixa', 'rosa']),
  Mix('deserto', 'Deserto', ['areia', 'ouro', 'ferrugem']),
];

class Direction {
  const Direction(this.key, this.label, this.glyph, this.degrees);
  final String key, label, glyph;
  final int degrees;
}

const directions = <Direction>[
  Direction('r', 'Para a direita', '→', 90),
  Direction('dr', 'Na diagonal', '↘', 120),
  Direction('d', 'Para baixo', '↓', 180),
  Direction('dl', 'Na outra diagonal', '↙', 240),
];

/// The classic covers: two colours of the app's own palette, blended into the page background at a given strength.
class Classic {
  const Classic(this.key, this.label, this.a, this.pctA, this.b, this.pctB);
  final String key, label;
  final int a, b;
  final int pctA, pctB;
}

const classics = <Classic>[
  Classic('musgo', 'Musgo', 0x4a5d44, 80, 0x6bb3a8, 45),
  Classic('ferrugem', 'Ferrugem', 0xd98a6c, 60, 0xd1ad5a, 40),
  Classic('oceano', 'Oceano', 0x8aa8c4, 55, 0x6bb3a8, 40),
  Classic('ameixa', 'Ameixa', 0xc196ad, 60, 0x8aa8c4, 35),
  Classic('areia', 'Areia', 0xd1ad5a, 45, 0xf5f2eb, 25),
  Classic('noite', 'Noite', 0x1e1e1b, 100, 0x2e2e2a, 70),
];

String soloSpec(String id) => 'solid:$id';
String monoSpec(String id) => 'mono:$id';
String duoSpec(String a, String b, [String dir = 'dr']) => 'duo:$a:$b:$dir';
String mixSpec(String key) => 'mix:$key';

PaletteColor? _color(String? id) => palette.where((c) => c.id == id).firstOrNull;

/// What a cover is drawn with: a direction in degrees and colour stops (hex, with the strength they get against the page).
class CoverStops {
  const CoverStops(this.degrees, this.stops);
  final int degrees;
  final List<(int hex, int pct)> stops;
}

/// The stops of a cover spec, or null when it is not one (an unknown colour, a made-up kind, anything else).
CoverStops? coverStops(String spec) {
  final classic = classics.where((c) => c.key == spec).firstOrNull;
  if (classic != null) return CoverStops(120, [(classic.a, classic.pctA), (classic.b, classic.pctB)]);
  if (spec.length > 60) return null;
  final parts = spec.split(':');
  final kind = parts.first;
  String? at(int i) => i < parts.length ? parts[i] : null;
  switch (kind) {
    case 'solid':
      final c = _color(at(1));
      return c != null && at(2) == null ? CoverStops(120, [(c.hex, 78), (c.hex, 78)]) : null;
    case 'mono':
      final c = _color(at(1));
      return c != null && at(2) == null ? CoverStops(120, [(c.hex, 88), (c.hex, 32)]) : null;
    case 'duo':
      final from = _color(at(1)), to = _color(at(2));
      final d = directions.where((d) => d.key == at(3)).firstOrNull;
      if (from == null || to == null || d == null) return null;
      return CoverStops(d.degrees, [(from.hex, 78), (to.hex, 78)]);
    case 'mix':
      final m = mixes.where((m) => m.key == at(1)).firstOrNull;
      return m != null && at(2) == null ? CoverStops(120, [for (final id in m.stops) (_color(id)!.hex, 78)]) : null;
  }
  return null;
}

/// '' (no cover) or something [coverStops] can draw.
bool isCover(String spec) => spec.isEmpty || coverStops(spec) != null;

/// What a spec is made of, so the picker can show the current choice.
class CoverChoice {
  const CoverChoice(this.kind, {this.a, this.b, this.dir});
  final String kind; // none | preset | solid | mono | duo | mix
  final String? a, b, dir;
}

CoverChoice describeCover(String spec) {
  if (spec.isEmpty || coverStops(spec) == null) return const CoverChoice('none');
  if (classics.any((c) => c.key == spec)) return CoverChoice('preset', a: spec);
  final p = spec.split(':');
  if (p.first == 'duo') return CoverChoice('duo', a: p[1], b: p[2], dir: p[3]);
  return CoverChoice(p.first, a: p[1]);
}
