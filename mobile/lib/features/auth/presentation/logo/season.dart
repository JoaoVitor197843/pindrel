/// Which scene the logo plays, by the device's LOCAL date (never UTC).
enum LogoTheme {
  normal,
  halloween,
  d24,
  d25,
  d31,
  d1,
  carnaval,
  pascoa,
  namorados,
  junino,
  dev,
}

/// Forces a theme in any build: `--dart-define=LOGO_THEME=halloween` (otherwise each only shows once a year).
const _forcedTheme = String.fromEnvironment('LOGO_THEME');

/// Easter Sunday (Meeus/Jones/Butcher, Gregorian calendar), at local midnight.
DateTime easter(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 1-based day of the year, counted on calendar days (a DST change cannot shift it).
int _dayOfYear(DateTime d) =>
    DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(d.year, 1, 1)).inDays +
    1;

/// A region's own dates: the theme of that day, or null to fall through to the global table.
typedef RegionalRule = LogoTheme? Function(DateTime d);

/// Rules by region (ISO 3166-1 alpha-2, upper case, e.g. 'BR'). Empty for now: add a region here and it is
/// consulted before the global table, so a regional date wins over a global one on the same day.
final Map<String, List<RegionalRule>> regionalRules = {};

/// Theme of the logo for a local date (and an optional region); the first match wins.
LogoTheme seasonalTheme(
  DateTime d, {
  String? region,
  Map<String, List<RegionalRule>>? rules,
}) {
  for (final rule
      in (rules ?? regionalRules)[region?.toUpperCase()] ??
          const <RegionalRule>[]) {
    final theme = rule(d);
    if (theme != null) return theme;
  }
  final m = d.month;
  final day = d.day;
  if (m == 10 && day == 31) return LogoTheme.halloween;
  if (m == 12 && day == 24) return LogoTheme.d24;
  if (m == 12 && day == 25) return LogoTheme.d25;
  if (m == 12 && day == 31) return LogoTheme.d31;
  if (m == 1 && day == 1) return LogoTheme.d1;
  if (m == 6 && day == 12) return LogoTheme.namorados;
  if (m == 6 && day == 24) return LogoTheme.junino;
  if (_dayOfYear(d) == 256) return LogoTheme.dev;
  final e = easter(d.year);
  for (var k = -2; k <= 0; k++) {
    if (_sameDay(d, DateTime(e.year, e.month, e.day + k))) {
      return LogoTheme.pascoa;
    }
  }
  for (var k = -50; k <= -47; k++) {
    if (_sameDay(d, DateTime(e.year, e.month, e.day + k))) {
      return LogoTheme.carnaval;
    }
  }
  return LogoTheme.normal;
}

/// The theme to play now: the forced one (debug) or the one of today.
LogoTheme currentLogoTheme(
  DateTime now, {
  String forced = _forcedTheme,
  String? region,
}) {
  for (final t in LogoTheme.values) {
    if (t.name == forced) return t;
  }
  return seasonalTheme(now, region: region);
}
