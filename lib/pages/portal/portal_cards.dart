import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';

typedef PortalArtworkBuilder =
    Widget Function(
      BuildContext context,
      String url,
      Map<String, String> headers,
    );

class PortalArtwork extends StatelessWidget {
  const PortalArtwork({
    super.key,
    required this.url,
    this.headers = const {},
    this.builder,
  });
  final String url;
  final Map<String, String> headers;
  final PortalArtworkBuilder? builder;
  @override
  Widget build(BuildContext context) {
    if (builder != null) return builder!(context, url, headers);
    final fallback = Container(
      color: const Color(0xffe6ecf5),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Color(0xffb5bfd0), size: 40),
      ),
    );
    if (url.isEmpty) return fallback;
    return LayoutBuilder(
      builder: (context, box) => CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        fit: BoxFit.cover,
        memCacheWidth: box.maxWidth.isFinite
            ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1920)
            : null,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
        fadeInDuration: const Duration(milliseconds: 160),
      ),
    );
  }
}

Map<String, String> portalHeaders(PortalItem item) =>
    item.film == null ? const {} : {'Referer': item.film!.source.url};

class PortalPoster extends StatefulWidget {
  const PortalPoster({
    super.key,
    required this.item,
    required this.onTap,
    this.landscape = false,
    this.artwork,
    this.showScore = true,
  });
  final PortalItem item;
  final VoidCallback onTap;
  final bool landscape;
  final bool showScore;
  final PortalArtworkBuilder? artwork;
  @override
  State<PortalPoster> createState() => _PortalPosterState();
}

class _PortalPosterState extends State<PortalPoster> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        key: ValueKey('poster:${item.key}'),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PortalArtwork(
                      url: item.poster,
                      headers: portalHeaders(item),
                      builder: widget.artwork,
                    ),
                    if (item.badge.isNotEmpty ||
                        widget.showScore && item.score > 0)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x77000000)],
                          ),
                        ),
                      ),
                    if (item.badge.isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        right: item.score > 0 ? 42 : 8,
                        child: Text(
                          item.badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (widget.showScore && item.score > 0)
                      Positioned(
                        right: 7,
                        bottom: 6,
                        child: Tooltip(
                          message: item.anime != null
                              ? 'Bangumi 评分'
                              : '${item.film?.source.name ?? ''}站内评分',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xbf0e1728),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.score.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xffffd55d),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (hover)
                      Container(
                        color: const Color(0x20000000),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: hover ? PortalStyle.blue : PortalStyle.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PortalStyle.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class PortalHero extends StatefulWidget {
  const PortalHero({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onDetails,
    this.artwork,
  });
  final List<PortalItem> items;
  final ValueChanged<PortalItem> onPlay;
  final ValueChanged<PortalItem> onDetails;
  final PortalArtworkBuilder? artwork;
  @override
  State<PortalHero> createState() => _PortalHeroState();
}

class _PortalHeroState extends State<PortalHero> {
  final pages = PageController();
  Timer? timer;
  int current = 0;
  bool hover = false;
  bool covered = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          !hover &&
          !covered &&
          pages.hasClients &&
          widget.items.length > 1) {
        pages.animateToPage(
          (current + 1) % widget.items.length,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    covered = RouteVisibility.isCoveredOf(context);
  }

  @override
  void didUpdateWidget(covariant PortalHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (current >= widget.items.length) {
      current = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pages.hasClients) pages.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          PageView.builder(
            controller: pages,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => current = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  PortalArtwork(
                    url: item.poster,
                    headers: portalHeaders(item),
                    builder: widget.artwork,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xe0162230),
                          Color(0x85162230),
                          Color(0x00162230),
                        ],
                        stops: [0, 0.45, 0.85],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 30,
                    right: 24,
                    bottom: 54,
                    child: LayoutBuilder(
                      builder: (context, box) => SizedBox(
                        width: box.maxWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: box.maxWidth * 0.85,
                              child: InkWell(
                                onTap: () => widget.onDetails(item),
                                child: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: box.maxWidth < 450 ? 24 : 34,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: box.maxWidth * 0.72,
                              child: Text(
                                item.summary.isNotEmpty
                                    ? item.summary
                                    : item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xffe6e9ed),
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              key: ValueKey('hero-play:${item.key}'),
                              onPressed: () => widget.onPlay(item),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 23,
                              ),
                              label: const Text('立即播放'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            left: 26,
            bottom: 15,
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Tooltip(
                    message: widget.items[i].title,
                    child: InkWell(
                      key: ValueKey('hero-dot:$i'),
                      onTap: () => pages.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == current ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == current
                                ? Colors.white
                                : const Color(0x88ffffff),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hover && widget.items.length > 1)
            Positioned(
              right: 14,
              bottom: 10,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '上一张',
                    onPressed: () => pages.animateToPage(
                      (current - 1 + widget.items.length) % widget.items.length,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: '下一张',
                    onPressed: () => pages.animateToPage(
                      (current + 1) % widget.items.length,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    ),
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class PortalFeatureLink extends StatelessWidget {
  const PortalFeatureLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
    this.item,
    this.artwork,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final PortalItem? item;
  final PortalArtworkBuilder? artwork;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item != null)
            PortalArtwork(
              url: item!.poster,
              headers: portalHeaders(item!),
              builder: artwork,
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xc01e293b), Color(0x001e293b)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                const Icon(
                  Icons.arrow_circle_right_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class PortalHistoryTile extends StatelessWidget {
  const PortalHistoryTile({
    super.key,
    required this.history,
    required this.onTap,
    this.artwork,
  });
  final History history;
  final VoidCallback onTap;
  final PortalArtworkBuilder? artwork;
  @override
  Widget build(BuildContext context) {
    final progress = history.progresses[history.lastWatchEpisode];
    final position = progress?.progress ?? Duration.zero;
    final duration = progress?.durationMs ?? 0;
    final title = history.bangumiItem.nameCn.isEmpty
        ? history.bangumiItem.name
        : history.bangumiItem.nameCn;
    return InkWell(
      key: ValueKey('resume:${history.key}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 76,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: PortalArtwork(
                url: history.bangumiItem.images['large'] ?? '',
                builder: artwork,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  history.lastWatchEpisodeName.isEmpty
                      ? '第 ${history.lastWatchEpisode} 集'
                      : history.lastWatchEpisodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: PortalStyle.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  duration > 0
                      ? '${portalTime(position)} / ${portalTime(Duration(milliseconds: duration))}'
                      : '看到 ${portalTime(position)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: PortalStyle.muted,
                  ),
                ),
                const SizedBox(height: 5),
                if (duration > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: (position.inMilliseconds / duration).clamp(0, 1),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
