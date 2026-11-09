// What this page may use depends on how it was opened. Browsers hand out `crypto.subtle`, the clipboard, service workers
// and the storage manager only on a secure page (HTTPS or localhost); on plain HTTP at a LAN address they are simply
// missing (checked in Chrome at http://192.168.x.x: isSecureContext false, crypto.subtle undefined, no serviceWorker, no
// navigator.clipboard, no navigator.storage). A feature that needs one of them is left out there instead of failing
// when it is used. Anything that does not say it is insecure counts as secure, so tests (jsdom) keep every feature.
const secure = () => typeof window === 'undefined' || (window as { isSecureContext?: boolean }).isSecureContext !== false

/** The vault encrypts on the device with `crypto.subtle`, so it exists only on a secure page. */
export const canVault = () => secure()

/** "Copiar como Markdown" writes to the clipboard, which only a secure page may do. */
export const canCopy = () => secure() && typeof navigator !== 'undefined' && !!navigator.clipboard?.writeText

/** Offline support needs a service worker. */
export const canServiceWorker = () => secure() && typeof navigator !== 'undefined' && 'serviceWorker' in navigator
