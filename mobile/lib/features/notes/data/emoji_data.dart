import 'package:characters/characters.dart';

// Page icons: a categorised list to pick from (the web's list), and any single emoji typed or pasted.

class EmojiGroup {
  const EmojiGroup(this.key, this.label, this.sign, this.list);
  final String key, label, sign;
  final List<String> list;
}

List<String> _split(String s) => s.characters.toList();

final emojiGroups = <EmojiGroup>[
  EmojiGroup('trabalho', 'Trabalho', '📋', _split('📋📝📓📔📒📕📗📘📙📚📖🗂️🗃️🗄️📁📂📅📆🗓️📇📌📍📎🖇️📏📐✂️🖊️🖋️✏️🖍️🔍🔎💼🏢🏛️🧾🧮💻🖥️⌨️🖨️📊📈📉📑🗒️📰📣📢')),
  EmojiGroup('ideias', 'Ideias', '💡', _split('💡🎯🧠💭💬🗯️🔥✨⭐🌟💫⚡🚀🛠️🔧🔨⚙️🧰🧪🔬🔭🧩🎲♟️🏆🥇🎖️🔑🗝️🔒🔓🔔🧭⏳⌛⏰')),
  EmojiGroup('rostos', 'Rostos', '😀', _split('😀😃😄😁😆😅😂🤣😊😇🙂😉😍🥰😘😋😎🤓🤔🤨😐😴🤯🥳😭😤😡🥶🥵😱🤗🫡🤝👍👎👏🙌🙏💪👀🧑‍💻👩‍💻👨‍💻')),
  EmojiGroup('natureza', 'Natureza', '🌱', _split('🌱🌿☘️🍀🌳🌲🌴🌵🌸🌹🌻🌼🍁🍂🍄🐶🐱🐭🐰🦊🐻🐼🦁🐸🐵🐧🐦🦉🦋🐝🐢🐙🐬🐳🌍🌎🌏🌙☀️⛅🌈☔❄️🌊')),
  EmojiGroup('comida', 'Comida', '🍽️', _split('🍎🍊🍋🍌🍉🍇🍓🍒🍑🥑🍅🥕🌽🥐🍞🧀🥚🍳🥞🍔🍕🌮🍣🍜🍝🍲🥗🍰🍪🍫🍩☕🍵🍷🍺🥤🧃🍽️🥘')),
  EmojiGroup('lugares', 'Lugares', '🏠', _split('🏠🏡🏘️🏙️🏫🏥🏦🏪🏭⛪🕌🏰🗼🗽⛺🏖️🏝️⛰️🌋🗺️🧳✈️🚀🚗🚌🚲🛵🚂🚢⚓🛒🛍️🏁')),
  EmojiGroup('objetos', 'Objetos', '🎵', _split('🎵🎶🎧🎤🎸🎹🎬🎮🕹️📷📹📺📻☎️📱🔋🔌💾💿📦🎁🎈🎉🧸👕👗👟👜👓⌚💍💎💰💳💵🧴🧼🪴🛏️🛋️🪑🚿🧹')),
  EmojiGroup('simbolos', 'Símbolos', '✅', _split('✅❌⚠️❗❓💯🔴🟠🟡🟢🔵🟣⚫⚪🟥🟧🟨🟩🟦🟪⬛⬜❤️🧡💛💚💙💜🖤🤍💔➕➖➗✖️♻️🔁🔄▶️⏸️⏹️🔀🔗🏷️🚩🏳️🏴')),
];

/// The first emoji found in whatever was typed or pasted, so "ola 🎉 mundo" still gives 🎉.
String? firstEmoji(String text, bool Function(String) isEmoji) {
  final head = text.length > 200 ? text.substring(0, 200) : text;
  for (final part in head.characters) {
    if (isEmoji(part)) return part;
  }
  return null;
}
