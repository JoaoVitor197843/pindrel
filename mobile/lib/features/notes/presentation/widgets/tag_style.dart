import 'package:flutter/painting.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/note_page.dart';

Color tagColor(TagColor c) => switch (c) {
      TagColor.accent => AppColors.accentBorder,
      TagColor.rust => AppColors.tagRust,
      TagColor.blue => AppColors.tagBlue,
      TagColor.gold => AppColors.tagGold,
      TagColor.plum => AppColors.tagPlum,
      TagColor.teal => AppColors.tagTeal,
    };

const tagColorNames = {
  TagColor.accent: 'Musgo',
  TagColor.rust: 'Ferrugem',
  TagColor.blue: 'Azul',
  TagColor.gold: 'Ouro',
  TagColor.plum: 'Ameixa',
  TagColor.teal: 'Verde-água',
};
