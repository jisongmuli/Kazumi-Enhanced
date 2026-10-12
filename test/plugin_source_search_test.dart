import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:logger/logger.dart';

class TestCollect extends Fake implements CollectController {}

class TestPlugin extends Fake implements Plugin {
  TestPlugin(this.name, this.type);
  @override
  final String name;
  @override
  final String type;
  final calls = <String>[];
  final tokens = <RuleCancelToken>[];
  final completions = <Completer<PluginSearchResponse>>[];
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) {
    calls.add(keyword);
    tokens.add(cancelToken!);
    final completion = Completer<PluginSearchResponse>();
    completions.add(completion);
    return completion.future;
  }

  void complete(int index, [String? title]) => completions[index].complete(
    PluginSearchResponse(
      pluginName: name,
      data: [
        SearchItem(
          name: title ?? calls[index],
          src: 'https://example.com/$name/$index',
        ),
      ],
    ),
  );
}

void main() {
  setUp(() => Logger.level = Level.off);
  test(
    'all source types are queried progressively with bounded concurrency',
    () async {
      final plugins = [
        TestPlugin('动漫', 'anime'),
        TestPlugin('影视', 'cinema'),
        TestPlugin('短剧', 'cinema'),
        TestPlugin('YouTube', 'youtube'),
      ];
      final controller = PluginsController()..pluginList.addAll(plugins);
      final info = InfoController(TestCollect());
      final search = PluginSearchService(
        infoController: info,
        pluginsController: controller,
        maxConcurrent: 2,
      );
      final finished = search.queryAllSource('深海');
      expect(info.pluginSearchStatus.length, 4);
      expect(plugins.map((p) => p.calls.length), [1, 1, 0, 0]);
      plugins[1].complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(info.pluginSearchResponseList.single.pluginName, '影视');
      expect(plugins.map((p) => p.calls.length), [1, 1, 1, 0]);
      plugins[0].complete(0);
      await Future<void>.delayed(Duration.zero);
      plugins[2].complete(0);
      plugins[3].complete(0);
      await finished;
      expect(
        info.pluginSearchStatus.values.every(
          (s) => s == PluginSearchStatus.success,
        ),
        isTrue,
      );
      expect(info.pluginSearchResponseList.length, 4);
      search.cancel();
    },
  );
  test('a manual search supersedes a queued bulk search', () async {
    final first = TestPlugin('first', 'anime');
    final queued = TestPlugin('queued', 'cinema');
    final info = InfoController(TestCollect());
    final search = PluginSearchService(
      infoController: info,
      pluginsController: PluginsController()
        ..pluginList.addAll([first, queued]),
      maxConcurrent: 1,
    );
    final bulk = search.queryAllSource('旧词');
    final manual = search.querySource('新词', queued.name);
    queued.complete(0);
    await manual;
    first.complete(0);
    await bulk;
    expect(queued.calls, ['新词']);
    expect(info.pluginSearchResponseList.first.data.single.name, '新词');
    search.cancel();
  });
  test(
    'closing the sheet cancels requests and leaves queued sources unstarted',
    () async {
      final first = TestPlugin('first', 'cinema');
      final queued = TestPlugin('queued', 'anime');
      final info = InfoController(TestCollect());
      final search = PluginSearchService(
        infoController: info,
        pluginsController: PluginsController()
          ..pluginList.addAll([first, queued]),
        maxConcurrent: 1,
      );
      final finished = search.queryAllSource('深海');
      search.cancel();
      expect(first.tokens.single.isCancelled, isTrue);
      first.complete(0);
      await finished;
      expect(queued.calls, isEmpty);
      expect(info.pluginSearchResponseList, isEmpty);
    },
  );
  test('timeout is a visible failure rather than no results', () async {
    final plugin = TestPlugin('slow', 'cinema');
    final info = InfoController(TestCollect());
    final search = PluginSearchService(
      infoController: info,
      pluginsController: PluginsController()..pluginList.add(plugin),
      queryTimeout: const Duration(milliseconds: 10),
    );
    await search.queryAllSource('深海');
    expect(info.pluginSearchStatus[plugin.name], PluginSearchStatus.error);
    expect(info.pluginSearchErrors[plugin.name], contains('超时'));
    expect(plugin.tokens.single.isCancelled, isTrue);
    plugin.complete(0);
    search.cancel();
  });
  testWidgets(
    '62 sources remain visible and cinema filtering opens actual results',
    (tester) async {
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final groups = [
        for (var i = 0; i < 16; i++)
          SourceSearchGroup(
            name: '动漫$i',
            keyword: '深海',
            status: PluginSearchStatus.noResult,
            results: [],
          ),
        for (var i = 0; i < 45; i++)
          SourceSearchGroup(
            name: '影视$i',
            type: 'cinema',
            keyword: '深海',
            status: i == 0
                ? PluginSearchStatus.success
                : PluginSearchStatus.error,
            error: '网站返回 HTTP 403',
            results: i == 0
                ? [SearchItem(name: '深海 正片', src: 'https://example.com/film')]
                : [],
          ),
        const SourceSearchGroup(
          name: 'YouTube',
          type: 'youtube',
          keyword: '深海',
          status: PluginSearchStatus.captcha,
          results: [],
        ),
      ];
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSheetView(
            keyword: '深海',
            groups: groups,
            firstResultSource: '影视0',
            onSourceSearch: (_) {},
            onSourceAliasSearch: (_) {},
            onRetry: (_) {},
            onVerify: (_) {},
            onOpenBrowser: (_) {},
            onClose: () {},
            onPlay: (source, item) => opened.add('$source:${item.src}'),
          ),
        ),
      );
      expect(find.text('62 个来源 · 1 个有结果 · 1 个结果'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-filter:cinema')));
      await tester.pumpAndSettle();
      expect(find.text('深海 正片'), findsOneWidget);
      await tester.tap(find.text('深海 正片'));
      expect(opened, ['影视0:https://example.com/film']);
      await tester.tap(find.text('影视1'));
      await tester.pumpAndSettle();
      expect(find.text('网站返回 HTTP 403'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-filter:results')));
      await tester.pumpAndSettle();
      expect(find.text('影视1'), findsNothing);
      expect(find.text('深海 正片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
