import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/portal/portal_catalog.dart';
import 'package:kazumi/pages/portal/portal_cards.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_header.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_page.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/bangumi_ech_image_service.dart';
import 'package:kazumi/utils/constants.dart';

class _EmptyHistory extends Fake implements IHistoryRepository {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  List<History> getAllHistories() => [];
}

void main() {
  testWidgets(
    'render actual anime covers on landscape tablet and portrait phone',
    (tester) async {
      final output = Platform.environment['KAZUMI_VERIFY_DIR']!;
      final images = <String, Uint8List>{};
      final dio = Dio(BaseOptions(headers: bangumiHTTPHeader));
      dio.httpClientAdapter = const NetworkConfig(
        enableLog: false,
      ).createAdapter();
      final covers = BangumiEchImageService(proxyForUrl: (_) => null);
      final catalog = LivePortalCatalog(
        animeBrowse: (offset, token) async {
          final response = await dio.get(
            'https://api.kazumi.fyi${BangumiApi.buildBangumiMirrorPopularPath(limit: 20, offset: offset)}',
          );
          final rows = response.data['data'] as List;
          return BangumiSearchPage(
            items: rows
                .map(
                  (row) => BangumiItem.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(),
            rawCount: rows.length,
          );
        },
        animeQuery: (_, _, _, _) async => null,
      );
      final controller = PortalController(
        channel: PortalChannel.anime,
        catalog: catalog,
      );
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        await controller.load();
        expect(controller.items.length, 20);
        var next = 0;
        Future<void> worker() async {
          while (next < controller.items.length) {
            final item = controller.items[next++];
            final url = portalPosterUrl(item);
            final response = await covers.get(url);
            expect(response.statusCode, 200, reason: item.title);
            images[url] = Uint8List.fromList(
              await response.content.expand((chunk) => chunk).toList(),
            );
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        await (FontLoader(
          'MI_Sans_Regular',
        )..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final boundary = GlobalKey();
      for (final size in [
        const Size(1280, 800),
        const Size(840, 600),
        const Size(390, 846),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        controller.resetScroll();
        await tester.pumpWidget(
          MaterialApp(
            theme: PortalStyle.theme(ThemeData(fontFamily: 'MI_Sans_Regular')),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: Column(
                  children: [
                    PortalHeader(
                      selectedIndex: 0,
                      onNavigate: (_) {},
                      onSearch: (_) {},
                      onHistory: () {},
                      onMore: (_) {},
                    ),
                    Expanded(
                      child: PortalPage(
                        controller: controller,
                        historyRepository: _EmptyHistory(),
                        artwork: (_, url, _) => images[url] == null
                            ? const ColoredBox(color: Color(0xffe6ecf5))
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
        await tester.runAsync(() async {
          await Future.wait(
            images.values.map(
              (bytes) =>
                  precacheImage(MemoryImage(bytes), boundary.currentContext!),
            ),
          );
        });
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/tablet-anime-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      covers.close();
      dio.close(force: true);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
