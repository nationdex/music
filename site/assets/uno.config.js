// UnoCSS runtime configuration (loaded before the runtime; see the <script> tags in each page).
// Utilities use the Tailwind v4 naming via preset-wind4. The Material 3 color tokens themselves
// live in app.css (:root, light-dark() pairs); the theme below only names them for utilities.
(() => {
  const tokens = [
    'primary',
    'onPrimary',
    'primaryContainer',
    'onPrimaryContainer',
    'secondary',
    'onSecondary',
    'secondaryContainer',
    'secondaryContainerVariant',
    'onSecondaryContainer',
    'tertiary',
    'onTertiary',
    'tertiaryContainer',
    'onTertiaryContainer',
    'error',
    'surface',
    'onSurface',
    'surfaceVariant',
    'onSurfaceVariant',
    'surfaceContainerHighest',
    'surfaceContainerHigh',
    'surfaceContainer',
    'surfaceContainerLow',
    'surfaceContainerLowest',
    'outline',
    'outlineVariant',
    'shadow',
    'scrim',
    'inverseSurface',
    'inverseOnSurface',
    'inversePrimary'
  ];
  const colors = Object.fromEntries(tokens.map((t) => [t, `var(--color-${t})`]));

  // Material 3 type scale: [font-size, line-height, letter-spacing, weight]
  const sp = (n) => `calc(var(--spacing) * ${n})`;
  const scale = {
    'body-lg': [sp(4), sp(6), '0.15px', 400],
    'body-md': [sp(3.5), sp(5), '0.25px', 400],
    'body-sm': [sp(3), sp(4), '0.4px', 400],
    'headline-lg': [sp(8), sp(10), '0', 700],
    'headline-md': [sp(7), sp(9), '0', 700],
    'headline-sm': [sp(6), sp(8), '0', 700],
    'label-lg': [sp(3.5), sp(5), '0.1px', 500],
    'label-md': ['12px', sp(4), '0.5px', 500],
    'label-sm': ['11px', sp(4), '0.5px', 500],
    'title-lg': [sp(5.5), sp(7), '0', 500],
    'title-md': [sp(4), sp(6), '0.15px', 500],
    'title-sm': [sp(3.5), sp(5), '0.1px', 500]
  };

  // Material 3 type scale as a preset. It is listed before Wind4, so its rules sort before Wind4's
  // utilities (font-semibold, leading-relaxed, ...) and those can still override it, while responsive
  // variants such as sm:text-title-lg keep sorting after the base utilities.
  const typeScale = {
    name: 'adi-type-scale',
    rules: [
      [
        /^text-(body|headline|label|title)-(lg|md|sm)$/,
        ([, kind, size]) => {
          const [fontSize, lineHeight, letterSpacing, fontWeight] = scale[`${kind}-${size}`];
          return { 'font-size': fontSize, 'line-height': lineHeight, 'letter-spacing': letterSpacing, 'font-weight': String(fontWeight) };
        }
      ]
    ]
  };

  window.__unocss = {
    presets: [
      typeScale,
      // The reset comes from unocss-reset.css (an exact copy of Tailwind v4's preflight).
      () => window.__unocss_runtime.presets.presetWind4({ preflights: { reset: false } })
    ],
    theme: {
      colors,
      breakpoint: { xss: '20rem', xs: '24rem', sm: '40rem', md: '48rem', lg: '64rem', xl: '80rem', '2xl': '96rem' },
      // The old design never defined text-base, so buttons inherit the 14px body size.
      text: { base: { fontSize: '0.875rem', lineHeight: '1.25rem' } }
    }
  };
})();
