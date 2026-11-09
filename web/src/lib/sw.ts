import { canServiceWorker } from './capabilities'

/**
 * Registers the service worker that lets the page open without the server (see sw.template.js). Only in a production
 * build, only on a page that may have one (HTTPS or localhost), and after the page has loaded so it never competes with
 * the first paint. The memory measurements run a build in loadtest mode, which leaves it out.
 */
export function registerServiceWorker(): void {
  if (!import.meta.env.PROD || import.meta.env.MODE === 'loadtest' || !canServiceWorker()) return
  const register = () => void navigator.serviceWorker.register('/sw.js').catch(() => {})
  if (document.readyState === 'complete') register()
  else window.addEventListener('load', register, { once: true })
}
