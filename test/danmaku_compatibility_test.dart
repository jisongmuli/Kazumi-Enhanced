import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/danmaku_source_sheet.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Map<String, dynamic> _details() => {
  'errorCode': 0,
  'success': true,
  'errorMessage': '',
  'bangumi': {
    'animeId': 101,
    'episodes': [
      {
        'episodeId': 10301,
        'episodeTitle': '【bilibili1】 第194话',
        'episodeNumber': '194',
      },
      {
        'episodeId': 10302,
        'episodeTitle': '【bilibili1】 第195话',
        'episodeNumber': '195',
      },
      {'episodeId': 10303, 'episodeTitle': '花絮', 'episodeNumber': ''},
    ],
  },
};

class _SourceAdapter implements HttpClientAdapter {
  final requested = <String>[];
  bool rateLimited = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.path);
    final dynamic data;
    var status = 200;
    switch (options.uri.path) {
      case '/api/v2/search/episodes':
        data = {
          'success': true,
          'animes': [
            {
              'animeId': 101,
              'animeTitle': '凡人修仙传 from bilibili',
              'typeDescription': '动漫',
            },
          ],
        };
      case '/api/v2/bangumi/101':
        data = _details();
      default:
        status = rateLimited ? 429 : 200;
        data = rateLimited
            ? {'success': false, 'errorMessage': 'Too many requests'}
            : {
                'comments': [
                  {'p': '2.5,1,16777215,[bilibili1]', 'm': '测试弹幕'},
                  {'p': '30.0,5,16711680,[youku]', 'm': '顶部弹幕'},
                ],
              };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _UnusedDownloads extends Fake implements DownloadController {}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _SourceAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_danmaku_compat_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    await GStorage.putSetting(
      SettingsKeys.danmakuEndpoint,
      'https://danmaku.test',
    );
    // Keep Hive writes outside the widget test's simulated clock.
    await GStorage.putSetting(SettingsKeys.privateMode, true);
  });
  setUp(() {
    DioFactory.reset();
    adapter = _SourceAdapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_danmaku_compat_'),
    );
    await directory.delete(recursive: true);
  });

  test(
    'bundled desktop details support string numbers and round-trip the nested API contract',
    () {
      final response = DanmakuEpisodeResponse.fromJson(_details());
      expect(response.episodes.map((episode) => episode.episodeNumber), [
        194,
        195,
        null,
      ]);
      final restored = DanmakuEpisodeResponse.fromJson(response.toJson());
      expect(restored.bangumiId, 101);
      expect(restored.episodes.map((episode) => episode.episodeId), [
        10301,
        10302,
        10303,
      ]);
      expect(restored.episodes[1].episodeNumber, 195);
    },
  );

  test('native integer numbers and non-numeric specials remain compatible', () {
    for (final value in [195, ' 195 ']) {
      expect(
        DanmakuEpisode.fromJson({
          'episodeId': -42628875313,
          'episodeTitle': '第195集',
          'episodeNumber': value,
        }).episodeNumber,
        195,
      );
    }
    for (final value in [null, '', 'PV', '1.5']) {
      expect(
        DanmakuEpisode.fromJson({
          'episodeId': 10303,
          'episodeTitle': '花絮',
          'episodeNumber': value,
        }).episodeNumber,
        isNull,
      );
    }
  });

  test(
    'a failed source replacement retains current timed comments and releases loading state',
    () async {
      final controller = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: _UnusedDownloads(),
      );
      expect(await controller.getDanDanmakuByEpisodeID(10301), isTrue);
      controller.setDanmakuEnabled(true);
      adapter.rateLimited = true;
      await expectLater(
        controller.getDanDanmakuByEpisodeID(10302),
        throwsStateError,
      );
      expect(controller.danmakuOn, isTrue);
      expect(controller.danmakuLoading, isFalse);
      expect(
        controller
            .danmakusForPlaybackPosition(const Duration(seconds: 2))
            .single
            .message,
        '测试弹幕',
      );
    },
  );

  test(
    'compatibility Bilibili labels respect the same source filter as native comments',
    () {
      for (final source in ['[bilibili]', '[bilibili1]', '[BiliBili]']) {
        final entry = DanmakuEntry.fromJson({
          'p': '1.5,4,16711680,$source',
          'm': '测试',
        });
        expect(entry.source, '[BiliBili]');
        expect(entry.type, 4);
        expect(entry.time, 1.5);
      }
      expect(
        DanmakuEntry.fromJson({
          'p': '1,1,16777215,[bilibili1＆youku]',
          'm': '测试',
        }).source,
        '[BiliBili＆youku]',
      );
      expect(
        DanmakuEntry.fromJson({'p': '1,1,16777215,[youku]', 'm': '测试'}).source,
        '[youku]',
      );
    },
  );

  testWidgets(
    'desktop source sheet searches, lists real string-numbered episodes, selects one and enables timed comments',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: _UnusedDownloads(),
      );
      var applies = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          navigatorObservers: [KazumiDialog.observer],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDanmakuSourceSheet(
                  context,
                  bangumiId: 1,
                  initialKeyword: '凡人修仙传',
                  danmakuController: controller,
                  onBeforeApply: () => applies++,
                ),
                child: const Text('打开弹幕'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开弹幕'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('凡人修仙传 from bilibili'), findsOneWidget);
      await tester.tap(find.text('凡人修仙传 from bilibili'));
      await tester.pumpAndSettle();
      expect(find.text('选择分集'), findsOneWidget);
      expect(find.text('【bilibili1】 第195话'), findsOneWidget);
      expect(find.text('分集加载失败'), findsNothing);
      await tester.tap(find.text('【bilibili1】 第195话'));
      await tester.pumpAndSettle();
      expect(applies, 1);
      expect(controller.danmakuOn, isTrue);
      expect(
        controller
            .danmakusForPlaybackPosition(const Duration(seconds: 2))
            .single
            .message,
        '测试弹幕',
      );
      expect(
        controller
            .danmakusForPlaybackPosition(const Duration(seconds: 30))
            .single
            .type,
        5,
      );
      expect(adapter.requested, contains('/api/v2/comment/10302'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
