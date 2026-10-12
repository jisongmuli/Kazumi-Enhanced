import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/cinema/cinema_controller.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart';

class CinemaPage extends StatefulWidget {
  const CinemaPage({super.key, required this.controller});
  final CinemaController controller;
  @override
  State<CinemaPage> createState() => _CinemaPageState();
}

class _CinemaPageState extends State<CinemaPage> {
  late final scroll = ScrollController(
    initialScrollOffset: widget.controller.scrollOffset,
  );
  late final search = TextEditingController(text: widget.controller.keyword);
  CinemaController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    if (!controller.initialized) controller.load();
  }

  @override
  void dispose() {
    controller.scrollOffset = scroll.hasClients ? scroll.offset : 0;
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _openSite(CinemaSource source) async {
    try {
      await launchUrl(
        Uri.parse(source.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      KazumiDialog.showToast(message: '无法打开原站，请检查系统浏览器');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final films = controller.films;
      return Scaffold(
        body: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              title: const DragToMoveArea(child: Text('热门影视')),
              actions: [
                IconButton(
                  tooltip: '片源状态',
                  onPressed: _showSources,
                  icon: const Icon(Icons.dns_outlined),
                ),
                IconButton(
                  tooltip: '刷新影视',
                  onPressed: () => controller.load(refresh: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(controller.selectedSource),
                            initialValue: controller.selectedSource,
                            decoration: const InputDecoration(
                              labelText: '影视片源',
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('全部片源'),
                              ),
                              for (final source in controller.sources)
                                DropdownMenuItem(
                                  value: source.id,
                                  child: Text(
                                    source.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                controller.load(sourceId: value);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: TextField(
                            controller: search,
                            decoration: InputDecoration(
                              labelText: '搜索电影、电视剧、综艺',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: '搜索影视',
                                icon: const Icon(Icons.search),
                                onPressed: () =>
                                    controller.load(search: search.text),
                              ),
                            ),
                            onSubmitted: (value) =>
                                controller.load(search: value),
                          ),
                        ),
                        if (controller.sources.any(
                          (source) => source.id == 'hongguo_official',
                        ))
                          ActionChip(
                            label: const Text('红果短剧'),
                            avatar: const Icon(Icons.local_movies_outlined),
                            onPressed: () {
                              search.clear();
                              controller.load(
                                sourceId: 'hongguo_official',
                                search: '',
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      controller.loading
                          ? '已读取 ${controller.listings.length} 个片源 · ${films.length} 部影片 · ${controller.pending.length} 个正在读取'
                          : '${films.length} 部影片 · ${controller.listings.length} 个可读取片源${controller.errors.isEmpty ? '' : ' · ${controller.errors.length} 个片源需重试或在浏览器打开'}',
                    ),
                    if (controller.selectedSource.isNotEmpty &&
                        controller.errors.containsKey(
                          controller.selectedSource,
                        ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          controller.errors[controller.selectedSource]!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (controller.loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (films.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    children: [
                      Icon(
                        controller.loading
                            ? Icons.movie_filter_outlined
                            : Icons.search_off,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        controller.loading
                            ? '正在读取影片封面…'
                            : '没有读取到影片，请换一个片源或检索关键词',
                      ),
                      if (!controller.loading)
                        TextButton(
                          onPressed: _showSources,
                          child: const Text('查看片源状态 / 打开原站'),
                        ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.54,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => CinemaPosterCard(
                    film: films[index],
                    onTap: () => context.pushNamed(
                      '/cinema/detail',
                      arguments: films[index],
                    ),
                  ),
                  childCount: films.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: controller.hasNext
                      ? FilledButton.tonal(
                          onPressed: controller.loadingMore
                              ? null
                              : controller.loadMore,
                          child: Text(controller.loadingMore ? '加载中…' : '加载更多'),
                        )
                      : Text(
                          controller.selectedSource.isEmpty
                              ? '切换到单个片源可查看更多影片'
                              : '已显示当前页面全部影片',
                        ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
          child: const Icon(Icons.arrow_upward),
        ),
      );
    },
  );

  void _showSources() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('影视片源与地址公告'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('在线看剧与看剧AI指向同一网站，已合并；影片封面来自各片源网站。'),
              ),
              for (final source in controller.sources)
                ListTile(
                  title: Text(source.displayName),
                  subtitle: Text(
                    controller.pending.contains(source.id)
                        ? '读取中…'
                        : controller.errors[source.id] ??
                              (controller.listings.containsKey(source.id)
                                      ? '${controller.listings[source.id]!.films.length} 部影片'
                                      : '未读取，切换到此片源加载') +
                                  (source.discoveredFrom == null
                                      ? ''
                                      : '\n发现依据：${source.discoveredFrom}'),
                  ),
                  leading: Icon(
                    controller.errors.containsKey(source.id)
                        ? Icons.public
                        : Icons.movie_outlined,
                  ),
                  trailing: IconButton(
                    tooltip: '打开原站',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openSite(source),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    controller.load(sourceId: source.id);
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class CinemaPosterCard extends StatelessWidget {
  const CinemaPosterCard({super.key, required this.film, required this.onTap});
  final CinemaFilm film;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 0.65,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: film.poster,
                  httpHeaders: {'Referer': film.source.url},
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      const Center(child: Icon(Icons.movie_outlined, size: 40)),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
                if (film.badge.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        film.badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      film.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    film.source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
