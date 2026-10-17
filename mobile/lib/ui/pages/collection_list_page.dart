/// Albums, artists and playlists lists. Ported from the list column of
/// site/components/collection.html. On wide screens the detail opens in a
/// second pane (the web build's two-column layout); on phones it is pushed.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../chrome.dart';
import '../file_picking.dart';
import '../navigation.dart';
import '../tabs.dart';
import '../widgets/action_menu.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/library_search_bar.dart';
import 'collection_detail_page.dart';

class CollectionListPage extends StatefulWidget {
  const CollectionListPage({super.key, required this.kind});

  final CollectionKind kind;

  @override
  State<CollectionListPage> createState() => _CollectionListPageState();
}

class _CollectionListPageState extends State<CollectionListPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _noun => switch (widget.kind) {
    CollectionKind.albums => 'albums',
    CollectionKind.artists => 'artists',
    CollectionKind.playlists => 'playlists',
  };

  List<Collection> _items(LibraryController lib) => switch (widget.kind) {
    CollectionKind.albums => lib.albumsMatching(_query),
    CollectionKind.artists => lib.artistsMatching(_query),
    CollectionKind.playlists => lib.playlistsMatching(_query),
  };

  void _open(Collection c, bool twoPane) {
    if (twoPane) {
      setState(() => _selectedId = c.id);
    } else {
      openCollection(context, widget.kind, c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final items = _items(lib);
    final twoPane = MediaQuery.sizeOf(context).width >= wideBreakpoint + 120;

    final list = Column(
      children: [
        LibrarySearchBar(
          controller: _search,
          hint: 'Search $_noun',
          onChanged: (v) => setState(() => _query = v),
          actions: [
            IconButton(
              tooltip: lib.sortAsc ? 'Sort descending' : 'Sort ascending',
              icon: AnimatedRotation(turns: lib.sortAsc ? 0 : 0.5, duration: const Duration(milliseconds: 200), child: const Icon(Icons.arrow_upward_rounded)),
              onPressed: lib.toggleSortDirection,
            ),
            ActionMenuButton(
              actionsBuilder: (ctx) => libraryMenuActions(
                ctx,
                onImport: () => importTracksFlow(context, pickAudioFiles),
                onDiscover: () => TabSelector.of(context)(AppTab.discovery),
              ),
            ),
          ],
        ),
        if (widget.kind == CollectionKind.playlists)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(icon: const Icon(Icons.add_rounded), label: const Text('New playlist'), onPressed: () => createPlaylistFlow(context)),
            ),
          ),
        Expanded(child: _body(lib, items, twoPane)),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: twoPane
            ? Row(
                children: [
                  SizedBox(width: 400, child: list),
                  VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  Expanded(
                    child: _selectedId == null
                        ? const EmptyState(title: 'Nothing selected', message: 'Select something from the list to be shown here', icon: Icons.touch_app_outlined)
                        : CollectionDetailView(kind: widget.kind, id: _selectedId!, embedded: true, onClose: () => setState(() => _selectedId = null)),
                  ),
                ],
              )
            : list,
      ),
    );
  }

  Widget _body(LibraryController lib, List<Collection> items, bool twoPane) {
    if (items.isEmpty && widget.kind != CollectionKind.playlists) {
      return EmptyState(title: 'No $_noun yet', message: 'Add music to your library to see it here');
    }
    return switch (widget.kind) {
      CollectionKind.albums || CollectionKind.artists => _grid(items, twoPane),
      CollectionKind.playlists => _playlists(items, twoPane),
    };
  }

  Widget _grid(List<Collection> items, bool twoPane) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final artists = widget.kind == CollectionKind.artists;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 170).floor().clamp(2, 6);
        return GridView.builder(
          padding: listPadding(context).copyWith(left: 16, right: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: artists ? 0.86 : 0.8),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final selected = twoPane && item.id == _selectedId;
            return Material(
              color: selected ? scheme.surfaceContainerHigh : (artists ? Colors.transparent : scheme.surfaceContainerHigh),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(item, twoPane),
                child: Column(
                  crossAxisAlignment: artists ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: artists ? const EdgeInsets.all(8) : EdgeInsets.zero,
                        child: LayoutBuilder(
                          builder: (_, box) => Center(
                            child: Artwork(
                              track: item.artworkTrack,
                              size: box.biggest.shortestSide,
                              radius: 0,
                              circle: artists,
                              icon: artists ? Icons.person_rounded : Icons.album_rounded,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: artists ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                        children: [
                          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                          if (!artists) Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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

  Widget _playlists(List<Collection> items, bool twoPane) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: listPadding(context),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final pl = items[i];
        final selected = twoPane && pl.id == _selectedId;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: pl.artworkTrack != null
                  ? Artwork(track: pl.artworkTrack, size: 44, circle: true)
                  : CircleAvatar(backgroundColor: scheme.surfaceContainerHighest, child: Icon(pl.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded)),
              title: Text(pl.name),
              subtitle: Text(pl.meta),
              textColor: selected ? scheme.onSecondaryContainer : null,
              onTap: () => _open(pl, twoPane),
            ),
          ),
        );
      },
    );
  }
}
