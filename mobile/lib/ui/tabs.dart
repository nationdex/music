/// The app's top-level destinations and a way for pages to switch between them.
library;

import 'package:flutter/material.dart';

enum AppTab {
  home('Library', Icons.library_music_outlined, Icons.library_music_rounded),
  tracks('Tracks', Icons.music_note_outlined, Icons.music_note_rounded),
  albums('Albums', Icons.album_outlined, Icons.album_rounded),
  artists('Artists', Icons.person_outline_rounded, Icons.person_rounded),
  playlists('Playlists', Icons.queue_music_outlined, Icons.queue_music_rounded),
  discovery('Discovery', Icons.explore_outlined, Icons.explore_rounded);

  const AppTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Provided by the shell; pages call `TabSelector.of(context)(AppTab.discovery)`.
class TabSelector extends InheritedWidget {
  const TabSelector({super.key, required this.select, required super.child});

  final ValueChanged<AppTab> select;

  static ValueChanged<AppTab> of(BuildContext context) => context.getInheritedWidgetOfExactType<TabSelector>()?.select ?? (_) {};

  @override
  bool updateShouldNotify(TabSelector old) => false;
}
