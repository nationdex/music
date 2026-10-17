# Adi Music for Android and iOS

A Flutter port of the Adi Music web app (`../site`). Same design (Material 3 tokens,
M PLUS Rounded 1c, the type scale), same features, native playback.

## Run

```bash
cd mobile
flutter pub get
flutter run                                   # a device or emulator
flutter test                                  # 73 tests
flutter analyze
flutter build apk                             # Android
flutter build ios                             # iOS (macOS with Xcode only)
```

YouTube search needs an Adi Music server (the nginx in `../deploy`), because the API key
must not ship inside an app. Set it in Settings > Discovery, or at build time:

```bash
flutter run --dart-define=ADI_SERVER_URL=https://music.example.com
```

Without a server, Discovery uses 30-second Apple previews. Lyrics providers and iTunes are
keyless, so the app calls them directly.

## Web to Flutter

| Web | Flutter |
| --- | --- |
| `site/assets/js/app.js` (Alpine component) | `lib/state/` controllers (`provider`) |
| `tags.js` (ID3, MP4, FLAC parsers) | `audio_metadata_reader` (also Ogg, Opus, WAV, AIFF) |
| IndexedDB + localStorage | files in app storage + `library.json` + `shared_preferences` |
| `<audio>` + Web Audio equalizer | `just_audio` + Android system equalizer |
| Media Session API | `audio_service` (notification, lock screen, headset, car) |
| YouTube IFrame API | `youtube_player_iframe` (WebView) |
| `lyrics.js`, `palette.js`, `sources.js` | `lib/services/`, `lib/core/palette.dart` (same algorithms, ported line by line) |
| Router + `components/*.html` | `lib/ui/` pages, a navigator per tab |
| `app.css` tokens, UnoCSS | `lib/core/theme.dart`, `palette.dart` |

## Liquid Glass

`lib/ui/widgets/glass.dart` picks a tier at startup:

- **iOS 26+**: real Liquid Glass (refraction, blur, specular edge) for the mini player,
  tab bar and player controls, through `liquid_glass_renderer`.
- **Older iOS**: frosted glass (backdrop blur over a tint).
- **Android**: solid Material 3 surfaces.

Settings > Appearance > Liquid Glass turns it off. The project does not set
`UIDesignRequiresCompatibility`, so iOS 26 system UI (alerts, keyboards, share sheet)
keeps the new design.

## Differences from the web app

- **Equalizer: Android only.** iOS does not let apps process the system player's audio.
  Android uses the device's equalizer bands, with the 10-band presets interpolated onto them.
- **Preserve pitch** can be turned off on Android only. iOS always preserves pitch.
- **YouTube tracks** play in YouTube's iframe, so they stop when the app is backgrounded
  on some devices and have no equalizer. Local files and previews play in the background.
- No PWA install card, keyboard shortcuts, drag and drop, or "Open with" (web-only ideas).
- Settings gains a server URL and the glass switch.

## Not verified here

Tests and the Android build run on Linux. Verified: 73 unit and widget tests, `flutter analyze`,
a debug APK that launches on an Android 16 emulator. **Not verified:** any iOS build or
run (needs macOS), Liquid Glass on a real iOS 26 device, YouTube playback, background
playback and the media notification on a device, and the equalizer on hardware.

`liquid_glass_renderer` is a pre-release package. Its shaders log a warning when
compiled for the Skia backend; they load on Impeller, which is the default on iOS.
