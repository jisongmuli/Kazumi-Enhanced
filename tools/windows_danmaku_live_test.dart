import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/danmaku/local_danmaku_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _ProbePaths extends PathProviderPlatform {
  _ProbePaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  testWidgets(
    'Windows default service completes search, episode parsing and four consecutive fresh comment loads',
    (tester) async {
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        Logger.level = Level.off;
        final directory = await Directory.systemTemp.createTemp(
          'kazumi_windows_danmaku_',
        );
        final paths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _ProbePaths(directory.path);
        Hive.init(directory.path);
        final service = LocalDanmakuService(
          runtimeDirectory:
              '${Directory.current.path}/build/windows/x64/runner/Release/danmaku_engine',
        );
        final results = <Map<String, dynamic>>[];
        try {
          await GStorage.init();
          final endpoint = await service.endpoint();
          await GStorage.putSetting(
            SettingsKeys.danmakuEndpoint,
            endpoint.toString(),
          );
          final search = await DanmakuApi.searchAnimes('凡人修仙传');
          final selected = search.animes.firstWhere(
            (anime) =>
                anime.animeTitle.contains('from bilibili') &&
                anime.animeTitle.contains('动漫'),
          );
          final details = await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(
            selected.animeId,
          );
          expect(details.episodes.length, greaterThan(4));
          expect(
            details.episodes.every((episode) => episode.episodeNumber != null),
            isTrue,
          );
          // Four different uncached episodes previously hit the local three-per-minute limit.
          for (final episode in details.episodes.reversed.skip(1).take(4)) {
            final comments = await DanmakuApi.getDanDanmakuByEpisodeID(
              episode.episodeId,
            );
            expect(comments, isNotEmpty);
            expect(
              comments.every((entry) => entry.source.contains('BiliBili')),
              isTrue,
            );
            expect(comments.every((entry) => entry.time >= 0), isTrue);
            results.add({
              'query': '凡人修仙传',
              'searchResults': search.animes.length,
              'episodes': details.episodes.length,
              'episode': episode.episodeNumber,
              'comments': comments.length,
              'firstSecond': comments.first.time,
              'lastSecond': comments.last.time,
            });
          }
        } finally {
          await service.shutdown();
          DioFactory.reset();
          await Hive.close();
          PathProviderPlatform.instance = paths;
          expect(
            directory.absolute.path.startsWith(
              Directory.systemTemp.absolute.path,
            ),
            isTrue,
          );
          expect(
            directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
            startsWith('kazumi_windows_danmaku_'),
          );
          await directory.delete(recursive: true);
          final out = Platform.environment['KAZUMI_VERIFY_DIR'];
          if (out != null) {
            await File('$out/windows-danmaku-results.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert(results),
            );
          }
          // Report only counts/metadata, never the local authorization token or comment text.
          print(jsonEncode(results));
        }
      });
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
