import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/logo/season.dart';

String iso(DateTime d) => '${d.year}-${d.month}-${d.day}';

void main() {
  test('easter bate com as datas conhecidas', () {
    expect(iso(easter(2025)), '2025-4-20');
    expect(iso(easter(2026)), '2026-4-5');
    expect(iso(easter(2027)), '2027-3-28');
    expect(iso(easter(2024)), '2024-3-31');
    expect(iso(easter(2038)), '2038-4-25');
  });

  group('datas fixas: o dia, o anterior e o seguinte', () {
    final cases = <String, (DateTime, LogoTheme)>{
      'halloween': (DateTime(2026, 10, 31), LogoTheme.halloween),
      '24/12': (DateTime(2026, 12, 24), LogoTheme.d24),
      '25/12': (DateTime(2026, 12, 25), LogoTheme.d25),
      '31/12': (DateTime(2026, 12, 31), LogoTheme.d31),
      '01/01': (DateTime(2026, 1, 1), LogoTheme.d1),
      'namorados': (DateTime(2026, 6, 12), LogoTheme.namorados),
      'junino': (DateTime(2026, 6, 24), LogoTheme.junino),
    };
    cases.forEach((name, c) {
      test(name, () {
        final (d, theme) = c;
        expect(seasonalTheme(d), theme);
        expect(
          seasonalTheme(DateTime(d.year, d.month, d.day - 1)),
          isNot(theme),
        );
        expect(
          seasonalTheme(DateTime(d.year, d.month, d.day + 1)),
          isNot(theme),
        );
      });
    });
  });

  test('um dia comum é normal', () {
    expect(seasonalTheme(DateTime(2026, 8, 15)), LogoTheme.normal);
    expect(seasonalTheme(DateTime(2026, 3, 3)), LogoTheme.normal);
  });

  test('dia do programador: 13/09, ou 12/09 em ano bissexto', () {
    expect(seasonalTheme(DateTime(2026, 9, 13)), LogoTheme.dev);
    expect(seasonalTheme(DateTime(2026, 9, 12)), LogoTheme.normal);
    expect(seasonalTheme(DateTime(2026, 9, 14)), LogoTheme.normal);
    expect(seasonalTheme(DateTime(2028, 9, 12)), LogoTheme.dev);
    expect(seasonalTheme(DateTime(2028, 9, 13)), LogoTheme.normal);
    expect(seasonalTheme(DateTime(2028, 9, 11)), LogoTheme.normal);
  });

  for (final year in [2025, 2026, 2027]) {
    test('páscoa e carnaval de $year', () {
      final e = easter(year);
      LogoTheme at(int n) => seasonalTheme(DateTime(year, e.month, e.day + n));
      expect([-3, -2, -1, 0, 1].map(at), [
        LogoTheme.normal,
        LogoTheme.pascoa,
        LogoTheme.pascoa,
        LogoTheme.pascoa,
        LogoTheme.normal,
      ]);
      expect([-51, -50, -49, -48, -47, -46].map(at), [
        LogoTheme.normal,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.normal,
      ]);
    });
  }

  test('Carnaval de 2025: sábado 1/3 a terça 4/3', () {
    expect(
      [
        DateTime(2025, 2, 28),
        DateTime(2025, 3, 1),
        DateTime(2025, 3, 2),
        DateTime(2025, 3, 3),
        DateTime(2025, 3, 4),
        DateTime(2025, 3, 5),
      ].map(seasonalTheme),
      [
        LogoTheme.normal,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.carnaval,
        LogoTheme.normal,
      ],
    );
  });

  test('usa a data local: a hora do dia não muda o tema', () {
    expect(seasonalTheme(DateTime(2026, 12, 31, 23, 30)), LogoTheme.d31);
    expect(seasonalTheme(DateTime(2027, 1, 1, 0, 30)), LogoTheme.d1);
  });

  test('currentLogoTheme: tema forçado vale; desconhecido é ignorado', () {
    final day = DateTime(2026, 8, 15);
    expect(currentLogoTheme(day, forced: 'halloween'), LogoTheme.halloween);
    expect(currentLogoTheme(day, forced: 'nada'), LogoTheme.normal);
    expect(currentLogoTheme(DateTime(2026, 12, 25), forced: ''), LogoTheme.d25);
  });

  group('regiões', () {
    final rules = <String, List<RegionalRule>>{
      'BR': [(d) => d.month == 8 && d.day == 15 ? LogoTheme.d1 : null],
    };

    test('sem regra para a região, vale a tabela global', () {
      final day = DateTime(2026, 8, 15);
      expect(seasonalTheme(day, region: 'PT', rules: rules), LogoTheme.normal);
      expect(seasonalTheme(day, rules: rules), LogoTheme.normal);
      expect(seasonalTheme(day), LogoTheme.normal);
    });

    test(
      'a regra da região vale (sem diferenciar maiúsculas) e null cai no global',
      () {
        expect(
          seasonalTheme(DateTime(2026, 8, 15), region: 'br', rules: rules),
          LogoTheme.d1,
        );
        expect(
          seasonalTheme(DateTime(2026, 8, 16), region: 'BR', rules: rules),
          LogoTheme.normal,
        );
      },
    );

    test('a data regional vence a global no mesmo dia', () {
      final clash = <String, List<RegionalRule>>{
        'BR': [(_) => LogoTheme.dev],
      };
      expect(
        seasonalTheme(DateTime(2026, 12, 25), region: 'BR', rules: clash),
        LogoTheme.dev,
      );
    });
  });
}
