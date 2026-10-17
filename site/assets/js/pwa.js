// PWA glue: service worker registration and the install prompt.
// Loaded by the landing page directly and by app.js, so one module instance serves both.

const listeners = new Set();
let deferredPrompt = null;

const notify = () => listeners.forEach((fn) => fn());

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch((e) => console.warn('Service worker not registered:', e));
  });
}

// Chromium (Android, Windows, macOS, Linux, ChromeOS) fires this once the app is installable.
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredPrompt = e;
  notify();
});

window.addEventListener('appinstalled', () => {
  deferredPrompt = null;
  notify();
});

const ua = navigator.userAgent;
const isIos = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isSafari = /^((?!chrome|android|crios|fxios|edgios).)*safari/i.test(ua);

export const pwa = {
  get standalone() {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: window-controls-overlay)').matches ||
      navigator.standalone === true
    );
  },
  get canPrompt() {
    return deferredPrompt !== null;
  },
  // Guidance for browsers that never fire beforeinstallprompt.
  get hint() {
    if (this.standalone) return '';
    if (isIos)
      return isSafari ? 'Tap the Share button, then Add to Home Screen.' : 'Open this page in Safari, tap Share, then Add to Home Screen.';
    if (isSafari) return 'In Safari, choose File, then Add to Dock.';
    if (/firefox/i.test(ua) && !/android/i.test(ua)) return 'Firefox on desktop cannot install web apps. Use Chrome, Edge or Safari.';
    if (/firefox/i.test(ua)) return 'Open the Firefox menu and tap Install.';
    return "Use your browser's menu and choose Install app or Add to Home screen.";
  },
  async install() {
    if (!deferredPrompt) return null;
    const prompt = deferredPrompt;
    deferredPrompt = null;
    prompt.prompt();
    const { outcome } = await prompt.userChoice;
    notify();
    return outcome;
  },
  onChange(fn) {
    listeners.add(fn);
    window.matchMedia('(display-mode: standalone)').addEventListener('change', fn);
  }
};
