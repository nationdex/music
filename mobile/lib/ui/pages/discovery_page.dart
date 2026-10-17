/// Discovery: search YouTube (full tracks) or Apple (30 s previews). Ported
/// from site/components/discovery.html and `discoveryView` in app.js.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../services/discovery_service.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../../state/settings_controller.dart';
import '../chrome.dart';
import '../widgets/action_menu.dart';
import '../widgets/common.dart';
import '../widgets/library_search_bar.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final _search = TextEditingController();
  bool _loading = false;
  String _error = '';
  List<DiscoveryItem> _results = const [];
  String _title = 'Top Hits';
  TrackSource _source = TrackSource.youtube;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch('Top Hits', initial: true));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String term, {bool initial = false}) async {
    term = term.trim();
    if (term.isEmpty) return;
    final token = ++_token;
    final settings = context.read<SettingsController>();
    final service = context.read<DiscoveryService>();
    setState(() {
      _loading = true;
      _error = '';
      _title = initial ? 'Top Hits' : 'Songs';
    });
    try {
      List<DiscoveryItem>? rows;
      if (settings.settings.discoverySource != 'itunes') {
        try {
          rows = await service.youtubeSearch(settings.serverUrl, term);
        } on YouTubeUnavailable {
          rows = null; // no server, no key, or quota spent: fall back to previews
        }
      }
      rows ??= await service.itunesSearch(term);
      if (!mounted || token != _token) return;
      setState(() {
        _source = rows!.isNotEmpty && rows.first.source == TrackSource.youtube ? TrackSource.youtube : TrackSource.remote;
        _results = rows;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _results = const [];
        _error = 'Failed to fetch';
      });
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  bool _isSaved(LibraryController lib, DiscoveryItem item) => lib.tracks.any(
    (t) => (item.videoId != null && t.videoId == item.videoId) || (!t.stored && t.name == item.name && t.artist == item.artist) || t.id == item.trackId,
  );

  Track _trackFor(LibraryController lib, DiscoveryItem item) {
    for (final t in lib.tracks) {
      if (t.id == item.trackId || (item.videoId != null && t.videoId == item.videoId) || (!t.stored && t.name == item.name && t.artist == item.artist)) return t;
    }
    return item.toTrack();
  }

  void _save(LibraryController lib, DiscoveryItem item) {
    final t = _trackFor(lib, item);
    if (lib.trackById(t.id) != null) return;
    lib.addRemoteTrack(t);
    showSnack(context, 'Added to your library');
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final settings = context.watch<SettingsController>();
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = context.select<PlayerController, Track?>((p) => p.currentTrack);
    final playing = context.select<PlayerController, bool>((p) => p.isPlaying);

    bool itemPlaying(DiscoveryItem i) =>
        current != null && playing && ((i.videoId != null && current.videoId == i.videoId) || (current.name == i.name && current.artist == i.artist));

    final youtubeWanted = settings.settings.discoverySource != 'itunes';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(alignment: Alignment.centerLeft, child: Text('Discovery', style: text.titleLarge)),
            ),
            LibrarySearchBar(
              controller: _search,
              hint: 'Search tracks, artists, albums',
              radius: 28,
              onChanged: (_) {},
              onSubmitted: _runSearch,
              actions: [
                IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => _runSearch(_search.text)),
                ActionMenuButton(
                  actionsBuilder: (_) => [
                    MenuAction(
                      icon: Icons.cached_rounded,
                      label: youtubeWanted ? 'Use Apple previews' : 'Use YouTube',
                      onSelected: () {
                        settings.update(settings.settings.copyWith(discoverySource: youtubeWanted ? 'itunes' : 'youtube'));
                        showSnack(context, 'Discovery source changed. Search again.');
                      },
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [CircularProgressIndicator(color: scheme.primary), const SizedBox(height: 16), Text('Searching catalog...', style: text.titleMedium)],
                      ),
                    )
                  : _error.isNotEmpty
                  ? EmptyState(title: _error, message: 'Check your connection and try again.', icon: Icons.cloud_off_rounded)
                  : _results.isEmpty
                  ? const EmptyState(title: 'No results found', icon: Icons.search_rounded)
                  : ListView.builder(
                      padding: listPadding(context),
                      itemCount: _results.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(_title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                                    Text('${_results.length} songs', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                                  ],
                                ),
                                Text(_source == TrackSource.youtube ? 'Full tracks from YouTube' : '30-second Apple previews', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          );
                        }
                        final item = _results[i - 1];
                        final saved = _isSaved(lib, item);
                        final isPlaying = itemPlaying(item);
                        return InkWell(
                          onTap: () => player.playFromList([for (final r in _results) _trackFor(lib, r)], i - 1),
                          child: SizedBox(
                            height: 72,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16, right: 8),
                              child: Row(
                                children: [
                                  Artwork(
                                    track: item.toTrack(),
                                    size: 48,
                                    overlay: isPlaying ? const NowPlayingOverlay(playing: true) : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: isPlaying ? scheme.primary : scheme.onSurface)),
                                        Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: saved ? 'In your library' : 'Add to library',
                                    icon: Icon(saved ? Icons.check_rounded : Icons.add_rounded),
                                    onPressed: saved ? null : () => _save(lib, item),
                                  ),
                                  SizedBox(width: 48, child: Text(formatTime(item.duration), textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
