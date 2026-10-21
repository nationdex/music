/// App chrome: the tab shell, navigation bar or rail, and the mini player.
/// Ported from the layout in site/app.html (rail on wide screens, bottom bar on
/// narrow ones, mini player above it).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/format.dart';
import '../state/player_controller.dart';
import 'navigation.dart';
import 'tabs.dart';
import 'pages/collection_list_page.dart';
import 'pages/discovery_page.dart';
import 'pages/home_page.dart';
import 'pages/tracks_page.dart';
import 'widgets/common.dart';
import 'widgets/glass.dart';

/// Space the floating chrome takes at the bottom, so lists can scroll clear of it.
class ChromeInsets extends InheritedWidget {
  const ChromeInsets({super.key, required this.bottom, required super.child});

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ChromeInsets old) => old.bottom != bottom;
}

const _miniPlayerHeight = 64.0;
const _miniPlayerMargin = 8.0;
const _navBarHeight = 80.0;
const wideBreakpoint = 840.0;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.tracks;
  final _navigators = {
    for (final t in AppTab.values) t: GlobalKey<NavigatorState>(),
  };

  Widget _root(AppTab tab) => switch (tab) {
    AppTab.home => const HomePage(),
    AppTab.tracks => const TracksPage(),
    AppTab.albums => const CollectionListPage(kind: CollectionKind.albums),
    AppTab.artists => const CollectionListPage(kind: CollectionKind.artists),
    AppTab.playlists => const CollectionListPage(
      kind: CollectionKind.playlists,
    ),
    AppTab.discovery => const DiscoveryPage(),
  };

  void _select(AppTab tab) {
    if (tab == _tab) {
      _navigators[tab]!.currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = tab);
    }
  }

  void _handleBack() {
    final nav = _navigators[_tab]!.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_tab != AppTab.tracks) {
      setState(() => _tab = AppTab.tracks);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final wide = size.width >= wideBreakpoint;
    final phoneTabs = AppTab.values.where((t) => t != AppTab.home).toList();

    final stack = IndexedStack(
      index: _tab.index,
      children: [
        for (final tab in AppTab.values)
          Navigator(
            key: _navigators[tab],
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => _root(tab)),
          ),
      ],
    );

    final inset =
        _miniPlayerHeight +
        _miniPlayerMargin * 2 +
        (wide ? 0 : _navBarHeight) +
        safeBottom;

    final Widget content = TabSelector(
      select: _select,
      child: ChromeInsets(
        bottom: inset,
        child: Stack(
          children: [
            Positioned.fill(child: stack),
            Positioned(
              left: wide ? 12 : 0,
              right: wide ? 12 : 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      _miniPlayerMargin,
                      12,
                      _miniPlayerMargin,
                    ),
                    child: MiniPlayer(),
                  ),
                  if (!wide)
                    _BottomNavigation(
                      tabs: phoneTabs,
                      selected: _tab,
                      onSelected: _select,
                    ),
                  if (wide) SizedBox(height: safeBottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: _tab.index,
                      onDestinationSelected: (i) => _select(AppTab.values[i]),
                      destinations: [
                        for (final t in AppTab.values)
                          NavigationRailDestination(
                            icon: Icon(t.icon),
                            selectedIcon: Icon(t.selectedIcon),
                            label: Text(t.label),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<AppTab> tabs;
  final AppTab selected;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final index = tabs.indexOf(selected).clamp(0, tabs.length - 1);

    if (isIos) {
      // A floating pill, like the iOS 26 tab bar.
      final scheme = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.paddingOf(context).bottom + 8,
        ),
        child: SizedBox(
          height: _navBarHeight - 16,
          child: GlassSurface(
            borderRadius: 32,
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: tabs[i].label,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(tabs[i]),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: i == index
                                ? scheme.secondaryContainer.withValues(
                                    alpha: 0.85,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                i == index
                                    ? tabs[i].selectedIcon
                                    : tabs[i].icon,
                                size: 24,
                                color: i == index
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                              Text(
                                tabs[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: i == index
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return NavigationBar(
      height: _navBarHeight,
      selectedIndex: index,
      onDestinationSelected: (i) => onSelected(tabs[i]),
      destinations: [
        for (final t in tabs)
          NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.selectedIcon),
            label: t.label,
          ),
      ],
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final track = player.currentTrack;

    return SizedBox(
      height: _miniPlayerHeight,
      child: GlassSurface(
        borderRadius: 20,
        solidColor: scheme.secondaryContainer,
        child: Stack(
          children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => openPlayer(context),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(
                    children: [
                      Artwork(track: track, size: 44, radius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: track == null
                            ? Text(
                                'Nothing playing',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSecondaryContainer.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleSmall?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                    ),
                                  ),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSecondaryContainer
                                          .withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      IconButton(
                        tooltip: player.isPlaying ? 'Pause' : 'Play',
                        iconSize: 30,
                        icon: player.isLoading && track != null
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: scheme.onSecondaryContainer,
                                ),
                              )
                            : Icon(
                                player.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                        color: scheme.onSecondaryContainer,
                        onPressed: player.togglePlay,
                      ),
                      IconButton(
                        tooltip: 'Next',
                        icon: const Icon(Icons.skip_next_rounded),
                        color: scheme.onSecondaryContainer,
                        onPressed: player.currentTrack == null
                            ? null
                            : player.nextTrack,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<Duration>(
                valueListenable: player.position,
                builder: (_, position, _) => ValueListenableBuilder<Duration>(
                  valueListenable: player.duration,
                  builder: (_, duration, _) => LinearProgressIndicator(
                    minHeight: 3,
                    value: duration.inMilliseconds == 0
                        ? 0
                        : (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                    backgroundColor: scheme.onSecondaryContainer.withValues(
                      alpha: 0.12,
                    ),
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hosts the hidden YouTube player. It must stay mounted while a YouTube track plays.
class YoutubeHost extends StatelessWidget {
  const YoutubeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        child,
        ValueListenableBuilder<YoutubePlayerController?>(
          valueListenable: player.youtubeController,
          builder: (_, controller, _) => controller == null
              ? const SizedBox.shrink()
              : Positioned(
                  left: 0,
                  bottom: 0,
                  width: 2,
                  height: 2,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.01,
                      child: YoutubePlayer(
                        controller: controller,
                        aspectRatio: 1,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Listens for one-off messages from the player (errors) and shows them as snackbars.
class MessageListener extends StatefulWidget {
  const MessageListener({
    super.key,
    required this.child,
    required this.messengerKey,
  });

  final Widget child;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  @override
  State<MessageListener> createState() => _MessageListenerState();
}

class _MessageListenerState extends State<MessageListener> {
  PlayerController? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<PlayerController>();
    if (_player != next) {
      _player?.removeListener(_onChange);
      _player = next..addListener(_onChange);
    }
  }

  void _onChange() {
    final message = _player?.takeMessage();
    if (message != null) {
      widget.messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Convenience for pages: bottom padding that clears the floating chrome.
EdgeInsets listPadding(BuildContext context, {double top = 0}) =>
    EdgeInsets.only(top: top, bottom: ChromeInsets.bottomOf(context) + 12);

String trackCountLabel(int n) => plural(n, 'track');
