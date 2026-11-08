// Page icons: a categorised list to pick from, and any single emoji typed or pasted.

export interface EmojiGroup {
  key: string
  label: string
  /** The emoji that stands for the group in the tab bar. */
  sign: string
  list: string[]
}

const split = (s: string) => [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(s)].map((x) => x.segment)

export const EMOJI_GROUPS: EmojiGroup[] = [
  { key: 'trabalho', label: 'Trabalho', sign: '📋', list: split('📋📝📓📔📒📕📗📘📙📚📖🗂️🗃️🗄️📁📂📅📆🗓️📇📌📍📎🖇️📏📐✂️🖊️🖋️✏️🖍️🔍🔎💼🏢🏛️🧾🧮💻🖥️⌨️🖨️📊📈📉📑🗒️📰📣📢') },
  { key: 'ideias', label: 'Ideias', sign: '💡', list: split('💡🎯🧠💭💬🗯️🔥✨⭐🌟💫⚡🚀🛠️🔧🔨⚙️🧰🧪🔬🔭🧩🎲♟️🏆🥇🎖️🔑🗝️🔒🔓🔔🧭⏳⌛⏰') },
  { key: 'rostos', label: 'Rostos', sign: '😀', list: split('😀😃😄😁😆😅😂🤣😊😇🙂😉😍🥰😘😋😎🤓🤔🤨😐😴🤯🥳😭😤😡🥶🥵😱🤗🫡🤝👍👎👏🙌🙏💪👀🧑‍💻👩‍💻👨‍💻') },
  { key: 'natureza', label: 'Natureza', sign: '🌱', list: split('🌱🌿☘️🍀🌳🌲🌴🌵🌸🌹🌻🌼🍁🍂🍄🐶🐱🐭🐰🦊🐻🐼🦁🐸🐵🐧🐦🦉🦋🐝🐢🐙🐬🐳🌍🌎🌏🌙☀️⛅🌈☔❄️🌊') },
  { key: 'comida', label: 'Comida', sign: '🍽️', list: split('🍎🍊🍋🍌🍉🍇🍓🍒🍑🥑🍅🥕🌽🥐🍞🧀🥚🍳🥞🍔🍕🌮🍣🍜🍝🍲🥗🍰🍪🍫🍩☕🍵🍷🍺🥤🧃🍽️🥘') },
  { key: 'lugares', label: 'Lugares', sign: '🏠', list: split('🏠🏡🏘️🏙️🏫🏥🏦🏪🏭⛪🕌🏰🗼🗽⛺🏖️🏝️⛰️🌋🗺️🧳✈️🚀🚗🚌🚲🛵🚂🚢⚓🛒🛍️🏁') },
  { key: 'objetos', label: 'Objetos', sign: '🎵', list: split('🎵🎶🎧🎤🎸🎹🎬🎮🕹️📷📹📺📻☎️📱🔋🔌💾💿📦🎁🎈🎉🧸👕👗👟👜👓⌚💍💎💰💳💵🧴🧼🪴🛏️🛋️🪑🚿🧹') },
  { key: 'simbolos', label: 'Símbolos', sign: '✅', list: split('✅❌⚠️❗❓💯🔴🟠🟡🟢🔵🟣⚫⚪🟥🟧🟨🟩🟦🟪⬛⬜❤️🧡💛💚💙💜🖤🤍💔➕➖➗✖️♻️🔁🔄▶️⏸️⏹️🔀🔗🏷️🚩🏳️🏴') },
]

export const ALL_EMOJI: string[] = EMOJI_GROUPS.flatMap((g) => g.list)

/** One emoji and nothing else: a single grapheme that is a pictograph or a flag. Never markup, never words. */
export function isEmoji(value: string): boolean {
  if (typeof value !== 'string' || value.length === 0 || value.length > 24) return false
  const parts = split(value)
  return parts.length === 1 && /^(\p{Extended_Pictographic}|\p{Regional_Indicator}{2})/u.test(parts[0])
}

/** The first emoji found in whatever was typed or pasted, so "ola 🎉 mundo" still gives 🎉. */
export function firstEmoji(text: string): string | null {
  for (const part of split(text.slice(0, 200))) if (isEmoji(part)) return part
  return null
}
