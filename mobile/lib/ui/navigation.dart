/// Route helpers. Settings and the full player cover the navigation bar (like
/// the web build, which hides it on those pages), so they push on the root navigator.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../state/library_controller.dart';
import 'pages/collection_detail_page.dart';
import 'pages/home_page.dart';
import 'pages/player_page.dart';
import 'pages/settings_page.dart';
import 'widgets/action_menu.dart';
import 'widgets/common.dart';

enum CollectionKind { albums, artists, playlists }

void openPlayer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const PlayerPage(),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved), child: child);
      },
    ),
  );
}

void openSettings(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
}

void openHome(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HomePage(showBack: true)));
}

void openCollection(BuildContext context, CollectionKind kind, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionDetailPage(kind: kind, id: id)));
}

/// Opens the system file picker and imports the chosen audio files.
Future<void> importTracksFlow(BuildContext context, Future<List<ImportSource>> Function() pick) async {
  final lib = context.read<LibraryController>();
  try {
    final files = await pick();
    if (files.isEmpty || !context.mounted) return;
    final added = await lib.importFiles(files);
    if (context.mounted) {
      showSnack(context, added.isEmpty ? 'Nothing new to add' : '${added.length} track${added.length == 1 ? '' : 's'} added');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Storage is full or unavailable');
  }
}

/// The menu behind the "more" button on library pages.
List<MenuAction> libraryMenuActions(BuildContext context, {required VoidCallback onImport, required VoidCallback onDiscover}) => [
  MenuAction(icon: Icons.add_rounded, label: 'Import tracks', onSelected: onImport),
  MenuAction(icon: Icons.explore_outlined, label: 'Discover music', onSelected: onDiscover),
  MenuAction(icon: Icons.library_music_outlined, label: 'Library overview', onSelected: () => openHome(context)),
  MenuAction(icon: Icons.settings_outlined, label: 'Settings', onSelected: () => openSettings(context)),
];

const sourceUrl = AppConfig.sourceUrl;
