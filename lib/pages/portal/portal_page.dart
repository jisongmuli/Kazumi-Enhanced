import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/portal/portal_cards.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_playback.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/player/history_playback_service.dart';

class PortalPage extends StatefulWidget {
  const PortalPage({
    super.key,
    required this.controller,
    required this.historyRepository,
    this.artwork,
    this.onDetails,
    this.onPlay,
    this.onResume,
    this.onHistory,
    this.onLibrary,
    this.showScore = true,
  });
  final PortalController controller;
  final IHistoryRepository historyRepository;
  final PortalArtworkBuilder? artwork;
  final ValueChanged<PortalItem>? onDetails;
  final ValueChanged<PortalItem>? onPlay;
  final ValueChanged<History>? onResume;
  final VoidCallback? onHistory;
  final VoidCallback? onLibrary;
  final bool showScore;
  @override
  State<PortalPage> createState() => _PortalPageState();
}

class _PortalPageState extends State<PortalPage> with KazumiDialogOwner {
  PortalController get controller => widget.controller;
  late final scroll = ScrollController(
    initialScrollOffset: controller.scrollOffset,
  );
  StreamSubscription<void>? historyChanges;
  List<History> histories = [];
  int visible = 42;
  late int lastScrollReset = controller.scrollReset;

  @override
  void initState() {
    super.initState();
    _readHistory();
    historyChanges = widget.historyRepository.changes.listen((_) {
      if (mounted) setState(_readHistory);
    });
    if (!controller.initialized) unawaited(controller.load());
  }

  void _readHistory() {
    final seen = <int>{};
    histories = widget.historyRepository
        .getAllHistories()
        .where((entry) => seen.add(entry.bangumiItem.id))
        .take(4)
        .toList();
  }

  @override
  void dispose() {
    controller.scrollOffset = scroll.hasClients ? scroll.offset : 0;
    historyChanges?.cancel();
    scroll.dispose();
    super.dispose();
  }

  void _select(PortalCategory category, {bool keepQuery = false}) {
    visible = 42;
    if (scroll.hasClients) scroll.jumpTo(0);
    unawaited(
      controller.load(
        category: category,
        keyword: keepQuery ? controller.keyword : '',
      ),
    );
  }

  void _history() => widget.onHistory != null
      ? widget.onHistory!()
      : context.pushNamed('/settings/history/');
  void _library() => widget.onLibrary != null
      ? widget.onLibrary!()
      : context.navigate('/tab/cinema/library');

  void _details(PortalItem item) {
    if (widget.onDetails != null) {
      widget.onDetails!(item);
      return;
    }
    if (item.anime != null) {
      context.pushNamed('/info/', arguments: item.anime);
    } else if (item.film != null) {
      context.pushNamed('/cinema/detail', arguments: item.film);
    } else if (item.youtube != null) {
      _play(item);
    }
  }

  Future<void> _resume(History entry) async {
    if (widget.onResume != null) {
      widget.onResume!(entry);
      return;
    }
    if (dialogs.isRunning) return;
    await dialogs.run((task) async {
      final token = CancelToken();
      final result = await task.loading(
        message: '正在恢复播放',
        onCancel: token.cancel,
        action: () =>
            inject<HistoryPlaybackService>().open(entry, cancelToken: token),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
            (context) => context.pushNamed('/video/', arguments: args),
          );
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请检查片源后重试');
  }

  Future<void> _play(PortalItem item) async {
    if (widget.onPlay != null) {
      widget.onPlay!(item);
      return;
    }
    if (dialogs.isRunning) return;
    final id =
        item.anime?.id ??
        item.film?.historyId ??
        (item.youtube != null
            ? portalYoutubeArgs(item.youtube!).bangumiItem.id
            : null);
    final previous = widget.historyRepository
        .getAllHistories()
        .where((entry) => entry.bangumiItem.id == id)
        .firstOrNull;
    if (previous != null) {
      await _resume(previous);
      return;
    }
    if (item.anime != null) {
      final info = InfoController(inject<CollectController>())
        ..bangumiItem = item.anime!;
      await showAdaptiveBottomSheet<void>(
        context: context,
        maxHeightFactor: 0.88,
        builder: (_) => SourceSheet(infoController: info),
      );
      return;
    }
    if (item.youtube != null) {
      context.pushNamed('/video/', arguments: portalYoutubeArgs(item.youtube!));
      return;
    }
    if (item.film != null) {
      await dialogs.run((task) async {
        final token = CancelToken();
        final detail = await task.loading(
          message: '正在读取播放列表',
          onCancel: token.cancel,
          action: () =>
              CinemaService.instance.detail(item.film!, cancelToken: token),
        );
        if (detail.roads.isEmpty) {
          task.withContext(
            (context) =>
                context.pushNamed('/cinema/detail', arguments: detail.film),
          );
        } else {
          task.withContext(
            (context) => context.pushNamed(
              '/video/',
              arguments: portalCinemaArgs(detail),
            ),
          );
        }
      }, errorMessage: '影片暂时无法播放，请重试或在详情页切换片源');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (lastScrollReset != controller.scrollReset) {
        lastScrollReset = controller.scrollReset;
        visible = 42;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) scroll.jumpTo(0);
        });
      }
      return Scaffold(
        backgroundColor: PortalStyle.background,
        body: LayoutBuilder(
          builder: (context, box) {
            final inset = box.maxWidth < 650 ? 12.0 : 20.0;
            final width = (box.maxWidth - inset * 2).clamp(0.0, 1720.0);
            return SingleChildScrollView(
              controller: scroll,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _categories(),
                      if (controller.loading)
                        const LinearProgressIndicator(minHeight: 2)
                      else
                        const SizedBox(height: 2),
                      const SizedBox(height: 10),
                      if (controller.isLanding) ...[
                        _featured(width),
                        const SizedBox(height: 16),
                        _continue(width),
                        const SizedBox(height: 16),
                        _shelf(
                          '热门推荐',
                          controller.items.take(7).toList(),
                          width,
                          onMore: () => _select(PortalCategory.all),
                          loading:
                              controller.loading && controller.items.isEmpty,
                        ),
                        const SizedBox(height: 16),
                        for (final category in controller.targets) ...[
                          _feedShelf(category, width),
                          const SizedBox(height: 16),
                        ],
                      ] else ...[
                        _resultsHeader(),
                        if (controller.channel == PortalChannel.youtube)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final query in [
                                  '旅行 风景 4K',
                                  '科技 数码',
                                  '动画 短片',
                                  '音乐 现场',
                                  '纪录片 中文',
                                ])
                                  ActionChip(
                                    label: Text(query),
                                    onPressed: () => controller.load(
                                      category: PortalCategory.youtube,
                                      keyword: query,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        _grid(controller.items.take(visible).toList(), width),
                        for (final category in controller.targets)
                          if (controller.errors[category] != null ||
                              controller.pending.contains(category))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _feedState(category),
                            ),
                        if (controller.items.isEmpty &&
                            !controller.loading &&
                            controller.errors.isEmpty)
                          _empty(
                            controller.keyword.isEmpty
                                ? '这个分类暂时没有内容'
                                : '没有找到相关内容，试试其他关键词',
                          ),
                        const SizedBox(height: 18),
                        if (controller.items.length > visible ||
                            controller.groups.values.any((p) => p.next != null))
                          Center(
                            child: OutlinedButton.icon(
                              key: const ValueKey('portal-load-more'),
                              onPressed: controller.loadingMore.isNotEmpty
                                  ? null
                                  : () {
                                      if (controller.items.length > visible) {
                                        setState(() => visible += 42);
                                      } else {
                                        visible += 42;
                                        for (final target
                                            in controller.targets) {
                                          unawaited(
                                            controller.loadMore(target),
                                          );
                                        }
                                      }
                                    },
                              icon: controller.loadingMore.isEmpty
                                  ? const Icon(Icons.expand_more)
                                  : const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                              label: Text(
                                controller.loadingMore.isEmpty
                                    ? '加载更多'
                                    : '正在加载',
                              ),
                            ),
                          ),
                        const SizedBox(height: 30),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _categories() {
    final categories = controller.keyword.isNotEmpty
        ? PortalCategory.search
        : switch (controller.channel) {
            PortalChannel.anime => [
              PortalCategory.anime,
              PortalCategory.chineseAnime,
              PortalCategory.japaneseAnime,
              PortalCategory.animeFilm,
              PortalCategory.animationShort,
            ],
            PortalChannel.cinema => [
              PortalCategory.cinema,
              PortalCategory.chineseFilm,
              PortalCategory.foreignFilm,
              PortalCategory.chineseSeries,
              PortalCategory.foreignSeries,
              PortalCategory.documentary,
              PortalCategory.variety,
            ],
            PortalChannel.shorts => [PortalCategory.shorts],
            PortalChannel.youtube => [PortalCategory.youtube],
            PortalChannel.home => PortalCategory.browse,
          };
    return SizedBox(
      height: 48,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TextButton(
                    key: ValueKey('category:${category.name}'),
                    onPressed: () => _select(
                      category,
                      keepQuery: controller.keyword.isNotEmpty,
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: controller.category == category
                          ? PortalStyle.blue
                          : const Color(0xfff0f3f9),
                      foregroundColor: controller.category == category
                          ? Colors.white
                          : PortalStyle.ink,
                      minimumSize: const Size(60, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                        side: BorderSide(
                          color: controller.category == category
                              ? PortalStyle.blue
                              : const Color(0xffe8edf6),
                        ),
                      ),
                    ),
                    child: Text(
                      controller.keyword.isEmpty &&
                              category == PortalCategory.anime
                          ? '全部动漫'
                          : controller.keyword.isEmpty &&
                                category == PortalCategory.cinema
                          ? '全部影视'
                          : category.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featured(double width) {
    final anime = controller.groups[PortalCategory.anime]?.items ?? [];
    final heroes = (anime.isNotEmpty ? anime : controller.items)
        .take(5)
        .toList();
    final height = width < 650 ? 270.0 : (width * 0.235).clamp(270.0, 360.0);
    final banner = heroes.isEmpty
        ? Container(
            decoration: BoxDecoration(
              color: const Color(0xffe7edf7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: controller.pending.contains(PortalCategory.anime)
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _feedState(PortalCategory.anime),
            ),
          )
        : PortalHero(
            items: heroes,
            onPlay: _play,
            onDetails: _details,
            artwork: widget.artwork,
          );
    final shorts = controller.groups[PortalCategory.shorts]?.items.firstOrNull;
    final youtube =
        controller.groups[PortalCategory.youtube]?.items.firstOrNull;
    final right = [
      PortalFeatureLink(
        key: const ValueKey('feature-shorts'),
        title: '热门短剧',
        subtitle: '红果官方 · 发现精彩故事',
        item: shorts,
        color: const Color(0xff7f625b),
        onTap: () => _select(PortalCategory.shorts),
        artwork: widget.artwork,
      ),
      PortalFeatureLink(
        key: const ValueKey('feature-youtube'),
        title: 'YouTube 精选',
        subtitle: '发现更大的世界\n记录真实而精彩的生活',
        item: youtube,
        color: const Color(0xff4381b0),
        onTap: () => _select(PortalCategory.youtube),
        artwork: widget.artwork,
      ),
    ];
    if (width >= 850) {
      return SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(flex: 68, child: banner),
            const SizedBox(width: 12),
            Expanded(
              flex: 32,
              child: Column(
                children: [
                  Expanded(child: right[0]),
                  const SizedBox(height: 10),
                  Expanded(child: right[1]),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(height: height, child: banner),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(child: right[0]),
              const SizedBox(width: 12),
              Expanded(child: right[1]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _continue(double width) => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('继续观看', _history),
        const SizedBox(height: 6),
        if (histories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.history, color: PortalStyle.muted, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '开始播放后，观看进度会自动出现在这里',
                    style: TextStyle(color: PortalStyle.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else if (width >= 1050)
          SizedBox(
            height: 76,
            child: Row(
              children: [
                for (var i = 0; i < histories.length; i++) ...[
                  if (i > 0) const SizedBox(width: 22),
                  Expanded(
                    child: PortalHistoryTile(
                      history: histories[i],
                      onTap: () => _resume(histories[i]),
                      artwork: widget.artwork,
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: histories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, i) => SizedBox(
                width: width < 500 ? 280 : 320,
                child: PortalHistoryTile(
                  history: histories[i],
                  onTap: () => _resume(histories[i]),
                  artwork: widget.artwork,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _feedShelf(PortalCategory category, double width) {
    final items = controller.groups[category]?.items ?? [];
    final title = switch (category) {
      PortalCategory.anime => '动漫热播',
      PortalCategory.cinema => '电影精选',
      PortalCategory.shorts => '短剧热播',
      PortalCategory.youtube => 'YouTube 精选',
      _ => category.label,
    };
    if (items.isEmpty) {
      return _surface(
        Column(
          children: [
            _sectionHeader(title, () => _select(category)),
            _feedState(category),
          ],
        ),
      );
    }
    return _shelf(
      title,
      items.take(category == PortalCategory.youtube ? 4 : 7).toList(),
      width,
      onMore: () => _select(category),
      landscape: category == PortalCategory.youtube,
    );
  }

  Widget _feedState(PortalCategory category) {
    final error = controller.errors[category];
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: PortalStyle.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${category.label}：$error',
                style: const TextStyle(fontSize: 12, color: PortalStyle.muted),
              ),
            ),
            TextButton(
              key: ValueKey('retry:${category.name}'),
              onPressed: () => controller.retry(category),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (controller.pending.contains(category)) {
      return const Padding(
        padding: EdgeInsets.all(22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '正在读取内容…',
              style: TextStyle(color: PortalStyle.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return _empty('这个分类暂时没有内容');
  }

  Widget _resultsHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          controller.keyword.isEmpty
              ? controller.category.label
              : '“${controller.keyword}” 的搜索结果',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        Text(
          '${controller.items.length} 项内容',
          style: const TextStyle(color: PortalStyle.muted, fontSize: 13),
        ),
        if (controller.keyword.isNotEmpty)
          TextButton.icon(
            key: const ValueKey('portal-clear-search'),
            onPressed: () => _select(switch (controller.channel) {
              PortalChannel.home => PortalCategory.recommend,
              PortalChannel.anime => PortalCategory.anime,
              PortalChannel.cinema => PortalCategory.cinema,
              PortalChannel.shorts => PortalCategory.shorts,
              PortalChannel.youtube => PortalCategory.youtube,
            }),
            icon: const Icon(Icons.close, size: 15),
            label: const Text('清除搜索'),
          ),
        TextButton.icon(
          onPressed: () => controller.load(refresh: true),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新'),
        ),
        if (controller.channel == PortalChannel.cinema ||
            controller.category == PortalCategory.cinema)
          TextButton.icon(
            onPressed: _library,
            icon: const Icon(Icons.dns_outlined, size: 18),
            label: const Text('片源目录'),
          ),
      ],
    ),
  );

  Widget _shelf(
    String title,
    List<PortalItem> items,
    double width, {
    required VoidCallback onMore,
    bool landscape = false,
    bool loading = false,
  }) => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title, onMore),
        const SizedBox(height: 10),
        if (loading)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          _empty('内容正在更新，请稍后刷新')
        else
          LayoutBuilder(
            builder: (context, box) {
              final columns = landscape ? 4 : 7;
              final cardWidth = (box.maxWidth - (columns - 1) * 18) / columns;
              final actualWidth = width < 850
                  ? (landscape ? 230.0 : 148.0)
                  : cardWidth;
              final height = landscape
                  ? actualWidth / (16 / 9) + 54
                  : actualWidth * 0.85 + 54;
              return SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (_, i) => SizedBox(
                    width: actualWidth,
                    child: PortalPoster(
                      item: items[i],
                      artwork: widget.artwork,
                      onTap: () => _details(items[i]),
                      landscape: landscape,
                      showScore: widget.showScore,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );

  Widget _grid(List<PortalItem> items, double width) {
    final landscape = controller.category == PortalCategory.youtube;
    final count = landscape
        ? (width > 1100
              ? 4
              : width > 680
              ? 3
              : width > 480
              ? 2
              : 1)
        : width > 1450
        ? 8
        : width > 1150
        ? 7
        : width > 950
        ? 6
        : width > 750
        ? 5
        : width > 550
        ? 4
        : width > 360
        ? 3
        : 2;
    final cardWidth = (width - (count - 1) * 16) / count;
    final height = landscape ? cardWidth * 9 / 16 + 60 : cardWidth * 1.38 + 60;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        mainAxisExtent: height,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
      ),
      itemBuilder: (_, index) => PortalPoster(
        item: items[index],
        onTap: () => _details(items[index]),
        artwork: widget.artwork,
        showScore: widget.showScore,
        landscape: landscape,
      ),
    );
  }

  Widget _sectionHeader(String title, VoidCallback onMore) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      TextButton(
        onPressed: onMore,
        style: TextButton.styleFrom(
          foregroundColor: PortalStyle.muted,
          minimumSize: const Size(40, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('查看全部', style: TextStyle(fontSize: 12)),
            SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    ],
  );
  Widget _surface(Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffedf1f8)),
    ),
    child: child,
  );
  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        message,
        style: const TextStyle(color: PortalStyle.muted, fontSize: 13),
      ),
    ),
  );
}
