/// The root widget: providers, theme, and the always-mounted helpers
/// (glass scope, hidden YouTube player, error snackbars).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/discovery_service.dart';
import 'state/library_controller.dart';
import 'state/player_controller.dart';
import 'state/settings_controller.dart';
import 'ui/chrome.dart';
import 'ui/widgets/glass.dart';

class AdiMusicApp extends StatefulWidget {
  const AdiMusicApp({super.key, required this.settings, required this.library, required this.player, required this.glassTier, this.discovery});

  final SettingsController settings;
  final LibraryController library;
  final PlayerController player;
  final GlassTier glassTier;
  final DiscoveryService? discovery;

  @override
  State<AdiMusicApp> createState() => _AdiMusicAppState();
}

class _AdiMusicAppState extends State<AdiMusicApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final DiscoveryService _discovery = widget.discovery ?? DiscoveryService();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: widget.settings),
        ChangeNotifierProvider<LibraryController>.value(value: widget.library),
        ChangeNotifierProvider<PlayerController>.value(value: widget.player),
        Provider<DiscoveryService>.value(value: _discovery),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          final accent = settings.effectiveAccent;
          return MaterialApp(
            title: 'Adi Music',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _messengerKey,
            theme: buildTheme(Brightness.light, accent: accent),
            darkTheme: buildTheme(Brightness.dark, accent: accent),
            themeMode: settings.themeMode,
            themeAnimationDuration: settings.settings.motion == 'reduced' ? Duration.zero : const Duration(milliseconds: 300),
            builder: (context, child) {
              final dark = Theme.of(context).brightness == Brightness.dark;
              final reduced = settings.reducedMotion(context);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                  statusBarBrightness: dark ? Brightness.dark : Brightness.light,
                  systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
                  child: GlassScope(
                    tier: widget.glassTier,
                    child: MessageListener(messengerKey: _messengerKey, child: YoutubeHost(child: child ?? const SizedBox.shrink())),
                  ),
                ),
              );
            },
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
