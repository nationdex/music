// Applies the saved theme to pages that do not load the player (the landing page).
(() => {
  let theme = 'auto';
  try {
    theme = JSON.parse(localStorage.getItem('adimusic:settings') || '{}').theme || 'auto';
  } catch {}
  const mq = matchMedia('(prefers-color-scheme: dark)');
  const apply = () => document.documentElement.classList.toggle('dark', theme === 'dark' || (theme !== 'light' && mq.matches));
  apply();
  mq.addEventListener('change', apply);
})();
