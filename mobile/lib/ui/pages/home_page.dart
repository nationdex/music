/// Library overview: recently played, playlists, albums. Ported from site/components/home.html.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../chrome.dart';
import '../file_picking.dart';
import '../navigation.dart';
import '../tabs.dart';
import '../widgets/common.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget section(String title, String subtitle, {VoidCallback? onViewAll}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (onViewAll != null) TextButton(onPressed: onViewAll, child: const Text('View all')),
        ],
      ),
    );

    final recent = lib.history.take(5).toList();
    final playlists = lib.playlists.take(5).toList();
    final albums = lib.albums.take(6).toList();

    return Scaffold(
      backgroundColor: showBack ? null : Colors.transparent,
      appBar: showBack ? AppBar(title: const Text('Library')) : null,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: listPadding(context),
          children: [
            if (!showBack)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Library', style: text.headlineLarge),
                          Text('Your offline music, all in one place.', style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(context)),
                  ],
                ),
              ),
            if (lib.tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'Your library is empty',
                  message: 'Import some music or save tracks from Discovery and they will appear here.',
                  actions: [
                    FilledButton(onPressed: () => importTracksFlow(context, pickAudioFiles), child: const Text('Import tracks')),
                    OutlinedButton.icon(icon: const Icon(Icons.explore_outlined, size: 20), label: const Text('Discovery'), onPressed: () => TabSelector.of(context)(AppTab.discovery)),
                  ],
                ),
              )
            else ...[
              section('Recently Played', 'Pick up where you left off'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: recent.isEmpty
                      ? Padding(padding: const EdgeInsets.all(24), child: Text('Nothing played yet.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)))
                      : Column(
                          children: [
                            for (var i = 0; i < recent.length; i++)
                              ListTile(
                                minTileHeight: 64,
                                leading: Artwork(track: recent[i], size: 40),
                                title: Text(recent[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(recent[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Text(formatTime(recent[i].duration), style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                                onTap: () => player.playFromList(lib.history, i),
                              ),
                          ],
                        ),
                ),
              ),
              section('Playlists', 'Your saved collections', onViewAll: () => TabSelector.of(context)(AppTab.playlists)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (final pl in playlists)
                          ListTile(
                            minTileHeight: 56,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            leading: CircleAvatar(backgroundColor: scheme.surfaceContainerHighest, child: Icon(pl.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded, color: scheme.onSurfaceVariant)),
                            title: Text(pl.name),
                            subtitle: Text(pl.meta),
                            onTap: () => openCollection(context, CollectionKind.playlists, pl.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (albums.isNotEmpty) ...[
                section('Albums', 'From your library', onViewAll: () => TabSelector.of(context)(AppTab.albums)),
                _AlbumGrid(albums: albums),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums});

  final List<Collection> albums;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 170).floor().clamp(2, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.8),
          itemCount: albums.length,
          itemBuilder: (_, i) {
            final a = albums[i];
            return Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openCollection(context, CollectionKind.albums, a.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: LayoutBuilder(builder: (_, box) => Artwork(track: a.artworkTrack, size: box.biggest.shortestSide, radius: 0, icon: Icons.album_rounded))),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                          Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
