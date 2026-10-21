/// Album, artist or playlist detail. Ported from the details pane of
/// site/components/collection.html.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../chrome.dart';
import '../navigation.dart';
import '../widgets/action_menu.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/track_widgets.dart';

class CollectionDetailPage extends StatelessWidget {
  const CollectionDetailPage({super.key, required this.kind, required this.id});

  final CollectionKind kind;
  final String id;

  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      CollectionKind.albums => 'Album',
      CollectionKind.artists => 'Artist',
      CollectionKind.playlists => 'Playlist',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: CollectionDetailView(
        kind: kind,
        id: id,
        onClose: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class CollectionDetailView extends StatelessWidget {
  const CollectionDetailView({
    super.key,
    required this.kind,
    required this.id,
    required this.onClose,
    this.embedded = false,
  });

  final CollectionKind kind;
  final String id;
  final VoidCallback onClose;

  /// Rendered inside a two-pane layout rather than as its own page.
  final bool embedded;

  Collection? _find(LibraryController lib) => switch (kind) {
    CollectionKind.albums => lib.album(id),
    CollectionKind.artists => lib.artist(id),
    CollectionKind.playlists => lib.playlist(id),
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = _find(lib);

    if (d == null) {
      return const EmptyState(
        title: 'Not found',
        message: 'This item is no longer in your library',
      );
    }

    final isPlaylist = kind == CollectionKind.playlists;
    final artists = kind == CollectionKind.artists;

    List<MenuAction> menu(BuildContext ctx) => [
      MenuAction(
        icon: Icons.play_arrow_rounded,
        label: 'Play next',
        onSelected: () {
          for (final t in d.tracks.reversed) {
            player.playNext(t);
          }
        },
      ),
      MenuAction(
        icon: Icons.queue_music_rounded,
        label: 'Add to queue',
        onSelected: () => d.tracks.forEach(player.addToQueue),
      ),
      if (isPlaylist && !d.isFavorites)
        MenuAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete playlist',
          destructive: true,
          onSelected: () async {
            final ok = await confirmDialog(
              context,
              title: 'Delete playlist?',
              body:
                  '“${d.name}” will be deleted. Your tracks stay in the library.',
              confirmLabel: 'Delete',
            );
            if (ok) {
              lib.deletePlaylist(d.id);
              onClose();
            }
          },
        ),
    ];

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Artwork(
            track: d.artworkTrack,
            size: 120,
            radius: 16,
            circle: artists,
            icon: artists
                ? Icons.person_rounded
                : (isPlaylist
                      ? Icons.queue_music_rounded
                      : Icons.album_rounded),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (d.isFavorites)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        d.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (d.artist.isNotEmpty)
                  Text(
                    d.artist,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  d.meta,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: d.tracks.isEmpty
                          ? null
                          : () => player.playFromList(d.tracks, 0),
                      child: const Text('Play'),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Shuffle'),
                      onPressed: d.tracks.isEmpty
                          ? null
                          : () => player.playShuffled(d.tracks),
                    ),
                    ActionMenuButton(actionsBuilder: menu),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return ListView.builder(
      padding: listPadding(context),
      itemCount: d.tracks.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return header;
        final track = d.tracks[i - 1];
        return SizedBox(
          height: 72,
          child: TrackTile(
            track: track,
            onTap: () => player.playFromList(d.tracks, i - 1),
          ),
        );
      },
    );
  }
}
