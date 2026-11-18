// Development switch for utility CSS.
//
// Pages ship /assets/utilities.css, a snapshot of what the UnoCSS runtime generates for every
// class used in the site (see tools/css-snapshot). That is faster than generating CSS in the
// browser: no 217 KB of runtime JS, no layout flash.
//
// While adding classes, load the runtime instead: open any page with ?uno=runtime (remembered
// in localStorage; ?uno=off turns it back off), then run tools/css-snapshot/snapshot.sh.
(() => {
  let mode = new URLSearchParams(location.search).get('uno');
  try {
    if (mode === 'off') localStorage.removeItem('adimusic:uno');
    else if (mode) localStorage.setItem('adimusic:uno', mode);
    else mode = localStorage.getItem('adimusic:uno');
  } catch {}
  if (mode !== 'runtime' && mode !== 'snapshot') return;

  // async=false keeps execution in this order: config, preset, runtime.
  for (const src of ['/assets/uno.config.js', '/assets/vendor/unocss-preset-wind4.js', '/assets/vendor/unocss-runtime-core.js']) {
    const s = document.createElement('script');
    s.src = src;
    s.async = false;
    document.head.append(s);
  }
  if (mode === 'snapshot') window.addEventListener('load', collect);

  // Feeds every page, fragment and script to the runtime, then publishes the CSS it generated.
  async function collect() {
    const rt = window.__unocss_runtime;
    const text = async (url) => (await fetch(url)).text();
    const shell = await text('/sw.js');
    const files = [...new Set([...shell.matchAll(/'(\/[^']+)'/g)].map((m) => m[1]))].filter((u) =>
      /^\/(components\/|assets\/js\/|app\.html$|$)/.test(u)
    );
    for (const file of ['/', '/app.html', '/privacy', ...files]) {
      try {
        await rt.extract(await text(file));
      } catch {}
    }
    await new Promise((r) => setTimeout(r, 300));
    const css = [...document.querySelectorAll('style[data-unocss-runtime-layer]')].map((s) => s.textContent).join('\n');
    const pre = document.createElement('pre');
    pre.id = 'uno-snapshot';
    pre.textContent = css;
    document.body.append(pre);
  }
})();
