import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:url_launcher/url_launcher.dart';

class CinemaDetailPage extends StatefulWidget {
  const CinemaDetailPage({super.key, required this.film});
  final CinemaFilm film;
  @override
  State<CinemaDetailPage> createState() => _CinemaDetailPageState();
}

class _CinemaDetailPageState extends State<CinemaDetailPage> {
  CancelToken cancellation = CancelToken();
  late Future<CinemaDetail> detail = CinemaService.instance.detail(
    widget.film,
    cancelToken: cancellation,
  );
  int road = 0;
  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  void _play(CinemaDetail detail, int episode) {
    final film = detail.film;
    final bangumi = BangumiItem.fromJson({
      'id': film.historyId,
      'type': 6,
      'name': film.title,
      'name_cn': film.title,
      'summary': film.summary,
      'images': {'large': film.poster},
      'rating': {},
      'info': '影视片源：${film.source.name}',
    });
    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: bangumi,
        plugin: CinemaService.plugin(film.source),
        title: film.title,
        src: film.url,
        roads: detail.roads,
        initialEpisode: episode,
        initialRoad: road,
        resumeHistory: false,
      ),
    );
  }

  Future<void> _openSite() async {
    try {
      await launchUrl(
        Uri.parse(widget.film.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      KazumiDialog.showToast(message: '无法打开原站，请检查系统浏览器');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.film.title),
      actions: [
        IconButton(
          onPressed: _openSite,
          tooltip: '在浏览器打开',
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: FutureBuilder<CinemaDetail>(
      future: detail,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final film = loaded?.film ?? widget.film;
        final image = SizedBox(
          width: 240,
          child: AspectRatio(
            aspectRatio: 0.65,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: film.poster,
                httpHeaders: {'Referer': film.source.url},
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    const Icon(Icons.movie_outlined, size: 64),
              ),
            ),
          ),
        );
        final introduction = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(film.title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('片源：${film.source.displayName}'),
            if (film.badge.isNotEmpty) Text(film.badge),
            const SizedBox(height: 16),
            Text(
              film.summary.isEmpty
                  ? (snapshot.connectionState == ConnectionState.done
                        ? '暂无影片简介'
                        : '正在读取影片详情…')
                  : film.summary,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openSite,
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开原站'),
            ),
          ],
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (MediaQuery.sizeOf(context).width > 700)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    image,
                    const SizedBox(width: 24),
                    Expanded(child: introduction),
                  ],
                )
              else ...[
                Center(child: image),
                const SizedBox(height: 20),
                introduction,
              ],
              const SizedBox(height: 24),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator(),
              if (snapshot.hasError) ...[
                Text('影片详情读取失败：${snapshot.error}'),
                TextButton(
                  onPressed: () {
                    cancellation.cancel();
                    cancellation = CancelToken();
                    setState(() {
                      detail = CinemaService.instance.detail(
                        widget.film,
                        cancelToken: cancellation,
                      );
                    });
                  },
                  child: const Text('重试'),
                ),
              ],
              if (loaded != null && loaded.roads.isEmpty)
                const Text('暂未识别此网站的播放列表，可通过“打开原站”观看。'),
              if (loaded != null && loaded.roads.isNotEmpty) ...[
                if (loaded.notice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(loaded.notice),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var index = 0; index < loaded.roads.length; index++)
                      ChoiceChip(
                        label: Text(loaded.roads[index].name),
                        selected: road == index,
                        onSelected: (_) => setState(() => road = index),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < loaded.roads[road].data.length;
                      index++
                    )
                      FilledButton.tonal(
                        onPressed: () => _play(loaded, index + 1),
                        child: Text(loaded.roads[road].identifier[index]),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
