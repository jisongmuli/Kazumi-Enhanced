import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/danmaku/bilibili_danmaku_service.dart';

void main() {
  testWidgets(
    'mobile built-in danmaku finds an anime, real episodes and playable timed comments without credentials',
    (tester) async {
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        final dio =
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)))
              ..httpClientAdapter = const NetworkConfig(
                enableLog: false,
              ).createAdapter();
        final service = BilibiliDanmakuService(dio: () => dio);
        final report = <Map<String, dynamic>>[];
        try {
          for (final title in ['凡人修仙传', '葬送的芙莉莲']) {
            final search = DanmakuSearchResponse.fromJson(
              await service.search(title),
            );
            expect(search.animes, isNotEmpty);
            final season = search.animes.first;
            final episodes = DanmakuEpisodeResponse.fromJson(
              await service.get(
                Uri.parse(
                  'https://api.dandanplay.net/api/v2/bangumi/${season.animeId}',
                ),
              ),
            );
            expect(episodes.episodes.length, greaterThan(1));
            final selected = episodes.episodes[episodes.episodes.length - 2];
            final raw = await service.get(
              Uri.parse(
                'https://api.dandanplay.net/api/v2/comment/${selected.episodeId}',
              ),
            );
            final comments = (raw['comments'] as List)
                .map(
                  (row) =>
                      DanmakuEntry.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList();
            expect(comments, isNotEmpty);
            expect(
              comments.every((c) => c.time >= 0 && c.source == '[BiliBili]'),
              isTrue,
            );
            report.add({
              'query': title,
              'sources': search.animes.length,
              'episodes': episodes.episodes.length,
              'episode': selected.episodeNumber,
              'comments': comments.length,
              'firstSecond': comments.first.time,
              'lastSecond': comments.last.time,
            });
          }
        } finally {
          dio.close(force: true);
          final out = Platform.environment['KAZUMI_VERIFY_DIR'];
          if (out != null)
            await File(
              '$out/mobile-danmaku-results.json',
            ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          print(jsonEncode(report));
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
