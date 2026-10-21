# Third-party software

Vendored in `site/assets/vendor/` at pinned versions. No package manager is used.

| Component | Version | License | Source |
| --- | --- | --- | --- |
| Alpine.js | 3.14.9 | MIT | https://github.com/alpinejs/alpine |
| Alpine plugins: Persist, Anchor, Focus, Intersect | 3.14.9 | MIT | https://github.com/alpinejs/alpine (`packages/*`) |
| UnoCSS runtime (`core.global.js`) and `preset-wind4` | 66.10.5 | MIT | https://github.com/unocss/unocss |
| Tailwind CSS v4 preflight (reset, inlined in `app.css`) | 4.x | MIT | https://github.com/tailwindlabs/tailwindcss |

Fonts in `site/fonts/` are subsets of M PLUS Rounded 1c (SIL Open Font License 1.1).
The Material icon paths in `site/partials/icons.html` come from Material Design Icons (Apache 2.0).

## Mobile app (`mobile/`)

Dart packages are resolved by `flutter pub get` (see `mobile/pubspec.lock`): provider, just_audio,
audio_service, audio_session, audio_metadata_reader, file_picker, path_provider,
shared_preferences, http, youtube_player_iframe, image, share_plus, url_launcher,
liquid_glass_renderer, device_info_plus. All are BSD-3, MIT or similar permissive licenses.
`mobile/assets/fonts/` holds Latin subsets of M PLUS Rounded 1c (SIL Open Font License 1.1).
