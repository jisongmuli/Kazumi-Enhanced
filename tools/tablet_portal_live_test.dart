import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/portal/portal_catalog.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/bangumi_transport.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/utils/constants.dart';

// Explicit real-network check. Does not use the PC's proxy or signing secrets.
void main() {
  testWidgets('tablet anime browsing, filters and search without a PC proxy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      const config = NetworkConfig(enableLog: false);
      final dio = Dio(
        BaseOptions(
          headers: bangumiHTTPHeader,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      dio.httpClientAdapter = BangumiEchAdapter(
        fallback: config.createAdapter(),
        config: config,
      );
      dio.interceptors.add(
        BangumiAccelerationInterceptor(
          acceleration: BangumiAcceleration.mirror,
          hasMirrorCredentials: false,
        ),
      );
      BangumiSearchPage parse(dynamic data) {
        final rows = data['data'] as List;
        return BangumiSearchPage(
          items: rows
              .map((j) => BangumiItem.fromJson(Map<String, dynamic>.from(j)))
              .toList(),
          rawCount: rows.length,
        );
      }

      final catalog = LivePortalCatalog(
        animeBrowse: (offset, token) async => parse(
          (await dio.get(
            'https://api.kazumi.fyi${BangumiApi.buildBangumiMirrorPopularPath(limit: 20, offset: offset)}',
            cancelToken: token,
          )).data,
        ),
        animeQuery: (keyword, tags, offset, token) async {
          try {
            return parse(
              (await dio.post(
                'https://api.bgm.tv/v0/search/subjects?limit=20&offset=$offset',
                data: BangumiApi.buildBangumiSearchParams(keyword, tags: tags),
                cancelToken: token,
              )).data,
            );
          } catch (error) {
            print('Public search transport: $error');
            rethrow;
          }
        },
      );
      final report = <Map<String, dynamic>>[];
      try {
        for (final category in [
          PortalCategory.anime,
          PortalCategory.chineseAnime,
          PortalCategory.japaneseAnime,
          PortalCategory.animeFilm,
          PortalCategory.animationShort,
        ]) {
          final watch = Stopwatch()..start();
          try {
            final page = await catalog.fetch(category);
            report.add({
              'category': category.name,
              'count': page.items.length,
              'seconds': watch.elapsedMilliseconds / 1000,
              'next': page.next,
              'first': page.items.firstOrNull?.title,
            });
            expect(page.items, isNotEmpty, reason: category.name);
            if (category == PortalCategory.anime) {
              final more = await catalog.fetch(category, next: page.next);
              expect(more.items.first.key, isNot(page.items.first.key));
            }
          } catch (error) {
            report.add({'category': category.name, 'error': '$error'});
            rethrow;
          }
        }
        final search = await catalog.fetch(
          PortalCategory.anime,
          keyword: '凡人修仙传',
        );
        expect(search.items, isNotEmpty);
        report.add({'search': '凡人修仙传', 'count': search.items.length});
      } finally {
        dio.close(force: true);
        final output = Platform.environment['KAZUMI_VERIFY_DIR'];
        if (output != null)
          await File(
            '$output/tablet-direct-network.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        // Public titles and status only; no user tokens or signed playback URLs.
        print(jsonEncode(report));
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
