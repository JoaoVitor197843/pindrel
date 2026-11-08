/** Case- and accent-insensitive text for searching. */
export const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
