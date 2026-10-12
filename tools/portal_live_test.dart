import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/portal/portal_catalog.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_header.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_page.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';

class PreviewHistory extends Fake implements IHistoryRepository {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  List<History> getAllHistories() => [];
}

// Explicit network / rendering probe; excluded from the normal offline suite.
void main() {
  testWidgets(
    'real homepage catalog, category browsing, search and rendered layout',
    (tester) async {
      HttpOverrides.global = null;
      final proxy = Uri.parse(Platform.environment['HTTPS_PROXY']!);
      final output = Platform.environment['KAZUMI_VERIFY_DIR']!;
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () =>
            HttpClient()
              ..findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}',
      );
      final catalog = LivePortalCatalog(
        cinema: CinemaService(dio: dio),
        youtube: YoutubeSourceService(
          engineDirectory: Platform.environment['KAZUMI_YOUTUBE_ENGINE']!,
          proxy: () => Platform.environment['HTTPS_PROXY']!,
        ),
        animeQuery: (keyword, tags, offset, token) async {
          final response = await dio.post(
            'https://api.bgm.tv/v0/search/subjects',
            queryParameters: {'limit': 20, 'offset': offset},
            cancelToken: token,
            data: BangumiApi.buildBangumiSearchParams(keyword, tags: tags),
          );
          final data = response.data['data'] as List;
          return BangumiSearchPage(
            items: data
                .map((j) => BangumiItem.fromJson(Map<String, dynamic>.from(j)))
                .toList(),
            rawCount: data.length,
          );
        },
      );
      final controller = PortalController(
        channel: PortalChannel.home,
        catalog: catalog,
      );
      final report = <Map<String, dynamic>>[];
      final images = <String, Uint8List>{};
      await tester.runAsync(() async {
        await controller.load();
        for (final category in controller.targets) {
          final items = controller.groups[category]?.items ?? [];
          report.add({
            'category': category.name,
            'count': items.length,
            'error': controller.errors[category],
            'firstTitle': items.firstOrNull?.title,
          });
        }
        var next = 0;
        final targets = PortalCategory.browse
            .where(
              (c) => ![
                PortalCategory.recommend,
                PortalCategory.all,
                PortalCategory.youtube,
                PortalCategory.shorts,
              ].contains(c),
            )
            .toList();
        Future<void> worker() async {
          while (next < targets.length) {
            final category = targets[next++];
            try {
              final page = await catalog.fetch(category);
              report.add({
                'category': category.name,
                'count': page.items.length,
                'next': page.next != null,
                'firstTitle': page.items.firstOrNull?.title,
              });
            } catch (error) {
              report.add({
                'category': category.name,
                'error': '$error',
                'count': 0,
              });
            }
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        for (final category in [
          PortalCategory.anime,
          PortalCategory.cinema,
          PortalCategory.shorts,
          PortalCategory.youtube,
        ]) {
          try {
            final page = await catalog.fetch(category, keyword: '凡人');
            report.add({
              'category': 'search:${category.name}',
              'count': page.items.length,
            });
          } catch (error) {
            report.add({
              'category': 'search:${category.name}',
              'count': 0,
              'error': '$error',
            });
          }
        }
        final wanted = {
          for (final page in controller.groups.values)
            for (final item in page.items.take(7)) item.poster: item,
        };
        final urls = wanted.keys.where((u) => u.isNotEmpty).toList();
        var imageNext = 0;
        Future<void> imageWorker() async {
          while (imageNext < urls.length) {
            final url = urls[imageNext++];
            try {
              final bytes = await dio.get<List<int>>(
                url,
                options: Options(
                  responseType: ResponseType.bytes,
                  headers: wanted[url]?.film != null
                      ? {'Referer': wanted[url]!.film!.source.url}
                      : {},
                ),
              );
              if ((bytes.data?.length ?? 0) < 10000000)
                images[url] = Uint8List.fromList(bytes.data!);
            } catch (_) {
              /* Image failure placeholders are intentional UI states. */
            }
          }
        }

        await Future.wait(List.generate(4, (_) => imageWorker()));
        await File(
          '$output/portal-live-results.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        final font = FontLoader('MI_Sans_Regular')
          ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      expect(controller.groups[PortalCategory.anime]!.items, isNotEmpty);
      expect(controller.groups[PortalCategory.cinema]!.items, isNotEmpty);
      expect(controller.groups[PortalCategory.shorts]!.items, isNotEmpty);
      expect(controller.groups[PortalCategory.youtube]!.items, isNotEmpty);
      expect(
        report.where((r) => (r['count'] as int) == 0),
        isEmpty,
        reason: report.where((r) => (r['count'] as int) == 0).toString(),
      );
      final boundary = GlobalKey();
      for (final size in [const Size(1280, 860), const Size(390, 846)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: PortalStyle.theme(ThemeData(fontFamily: 'MI_Sans_Regular')),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: Column(
                  children: [
                    PortalHeader(
                      selectedIndex: 5,
                      onNavigate: (_) {},
                      onSearch: (_) {},
                      onHistory: () {},
                      onMore: (_) {},
                    ),
                    Expanded(
                      child: PortalPage(
                        controller: controller,
                        historyRepository: PreviewHistory(),
                        artwork: (_, url, headers) => images[url] == null
                            ? const ColoredBox(color: Color(0xffe3e9f3))
                            : Image.memory(images[url]!, fit: BoxFit.cover),
                        onPlay: (_) {},
                        onDetails: (_) {},
                        onResume: (_) {},
                        onHistory: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future.wait(
            images.values.map(
              (bytes) =>
                  precacheImage(MemoryImage(bytes), boundary.currentContext!),
            ),
          );
        });
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/portal-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      dio.close(force: true);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
