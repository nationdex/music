/// All tracks, with search and sort. Ported from site/components/tracks.html.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../chrome.dart';
import '../tabs.dart';
import '../file_picking.dart';
import '../navigation.dart';
import '../widgets/action_menu.dart';
import '../widgets/common.dart';
import '../widgets/library_search_bar.dart';
import '../widgets/track_widgets.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _import() => importTracksFlow(context, pickAudioFiles);

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final player = context.read<PlayerController>();
    final tracks = lib.tracksMatching(_query);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LibrarySearchBar(
              controller: _search,
              hint: 'Search tracks',
              onChanged: (v) => setState(() => _query = v),
              actions: [
                ActionMenuButton(
                  icon: Icons.sort_rounded,
                  tooltip: 'Open sort menu',
                  actionsBuilder: (_) => [
                    for (final (key, label) in sortKeys)
                      MenuAction(
                        icon: lib.sortKey == key
                            ? Icons.check_rounded
                            : Icons.sort_rounded,
                        label: label,
                        onSelected: () => lib.setSortKey(key),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: lib.sortAsc ? 'Sort descending' : 'Sort ascending',
                  icon: AnimatedRotation(
                    turns: lib.sortAsc ? 0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.arrow_upward_rounded),
                  ),
                  onPressed: lib.toggleSortDirection,
                ),
                ActionMenuButton(
                  actionsBuilder: (ctx) => libraryMenuActions(
                    ctx,
                    onImport: _import,
                    onDiscover: () => TabSelector.of(context)(AppTab.discovery),
                  ),
                ),
              ],
            ),
            if (lib.importStatus != null)
              LinearProgressIndicator(minHeight: 2, color: scheme.primary),
            Expanded(
              child: lib.tracks.isEmpty
                  ? EmptyState(
                      title: 'Your library is empty',
                      message: 'Start by adding some music',
                      actions: [
                        FilledButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Import tracks'),
                          onPressed: _import,
                        ),
                      ],
                    )
                  : tracks.isEmpty
                  ? const EmptyState(
                      title: 'No tracks found',
                      message: 'Try a different search',
                    )
                  : ListView.builder(
                      padding: listPadding(context),
                      itemExtent: 72,
                      itemCount: tracks.length,
                      itemBuilder: (_, i) => TrackTile(
                        track: tracks[i],
                        showAlbum: wide,
                        onTap: () => player.playFromList(tracks, i),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
