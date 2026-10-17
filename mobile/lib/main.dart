import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/storage.dart';
import 'state/audio_handler.dart';
import 'state/library_controller.dart';
import 'state/player_controller.dart';
import 'state/settings_controller.dart';
import 'ui/widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final storage = await Storage.open();
  final settings = SettingsController(storage);
  final library = LibraryController(storage);
  await library.load();

  // Ducking, interruptions (calls, other apps) and headphone unplug are handled by the music profile.
  await (await AudioSession.instance).configure(const AudioSessionConfiguration.music());

  final handler = await AudioService.init(
    builder: AdiAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'org.nationdex.adi_music.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationIcon: 'drawable/ic_notification',
      // Keeps the service in the foreground while paused, so Android 12+ can resume it from the notification.
      androidStopForegroundOnPause: false,
    ),
  );

  final player = PlayerController(library: library, settings: settings, handler: handler);
  final glass = await detectGlassTier();

  runApp(AdiMusicApp(settings: settings, library: library, player: player, glassTier: glass));
}
