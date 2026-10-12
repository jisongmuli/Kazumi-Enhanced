import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/portal/portal_catalog.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_header.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_page.dart';
import 'package:kazumi/pages/portal/portal_playback.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_parser.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/video_source/youtube_models.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';

BangumiItem anime(int id, [String name = '葬送的芙莉莲']) => BangumiItem.fromJson({
  'id': id,
  'name_cn': '$name $id',
  'name': '$name $id',
  'rating': {'score': 8.6},
  'images': {'large': 'https://example.com/$id.jpg'},
  'date': '2024-01-01',
  'summary': '跨越时间的旅程，在温柔的告别中寻找生命的意义。',
});
const cinemaSource = CinemaSource(
  id: 'libvio_cam',
  name: 'LIBVIO',
  url: 'https://example.com/',
);
PortalItem movie(int id) => PortalItem.fromFilm(
  CinemaFilm(
    source: cinemaSource,
    title: '电影 $id',
    poster: 'https://example.com/movie$id.jpg',
    url: 'https://example.com/detail/$id',
    badge: 'HD',
  ),
);
History history(int id) => History(
  anime(id),
  12,
  '测试片源',
  DateTime(2026, 10, 12),
  'https://example.com/series/$id',
  '第12集',
)..progresses[12] = Progress(12, 0, 120000, durationMs: 240000);

class FakeHistory extends Fake implements IHistoryRepository {
  List<History> entries = [];
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => updates.stream;
  @override
  List<History> getAllHistories() => entries;
}

class FakeCatalog implements PortalCatalog {
  final requests =
      <({PortalCategory category, String keyword, String? next})>[];
  final cancellations = <CancelToken>[];
  final delayed = <String, Completer<PortalListing>>{};
  final failing = <PortalCategory>{};
  @override
  Future<PortalListing> fetch(
    PortalCategory category, {
    String keyword = '',
    String? next,
    bool refresh = false,
    CancelToken? cancelToken,
  }) async {
    requests.add((category: category, keyword: keyword, next: next));
    if (cancelToken != null) cancellations.add(cancelToken);
    if (delayed[keyword] != null) return delayed[keyword]!.future;
    if (failing.contains(category)) throw StateError('片源暂时不可用');
    if (category == PortalCategory.youtube)
      return PortalListing([
        PortalItem.fromYoutube(
          const YoutubeCard(
            pageUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
            title: '真实 YouTube 条目',
            thumbnail: '',
            channel: '测试频道',
            duration: Duration(minutes: 10),
          ),
        ),
      ]);
    if (category == PortalCategory.cinema || category == PortalCategory.shorts)
      return PortalListing([movie(10), movie(11)]);
    if (next != null)
      return PortalListing([
        PortalItem.fromAnime(anime(1)),
        PortalItem.fromAnime(anime(30)),
      ]);
    return PortalListing(
      List.generate(
        10,
        (i) => PortalItem.fromAnime(
          anime(i + 1, keyword.isEmpty ? '葬送的芙莉莲' : keyword),
        ),
      ),
      next: '28',
    );
  }
}

class FakeCinema extends CinemaService {
  final visited = <String>[];
  @override
  Future<List<CinemaSource>> sources() async => [cinemaSource];
  @override
  Future<Map<String, String>> categoryLinks(
    CinemaSource source, {
    String? pageUrl,
    CancelToken? cancelToken,
  }) async => {
    '电影': 'https://example.com/type/1',
    '电视剧': 'https://example.com/type/2',
    '纪录片': 'https://example.com/type/3',
    '综艺': 'https://example.com/type/5',
    '大陆': 'https://example.com/area/cn',
    '香港': 'https://example.com/area/hk',
    '美国': 'https://example.com/area/us',
    '日本': 'https://example.com/area/jp',
    '国产剧': 'https://example.com/type/13',
    '欧美剧': 'https://example.com/type/16',
  };
  @override
  Future<CinemaListing> listing(
    CinemaSource source, {
    String keyword = '',
    String? pageUrl,
    CancelToken? cancelToken,
    bool refresh = false,
  }) async {
    visited.add(pageUrl ?? 'search:$keyword');
    return CinemaListing(
      films: [
        CinemaFilm(
          source: source,
          title: '影片',
          url: '${source.url}detail/${visited.length}',
          poster: '',
        ),
      ],
    );
  }
}

Widget testApp(
  PortalController controller,
  FakeHistory repository, {
  ValueChanged<PortalItem>? play,
  ValueChanged<PortalItem>? open,
  ValueChanged<History>? resume,
  VoidCallback? allHistory,
}) => MaterialApp(
  theme: PortalStyle.theme(ThemeData.light()),
  home: PortalPage(
    controller: controller,
    historyRepository: repository,
    artwork: (_, _, _) => const ColoredBox(color: Color(0xff8ca8c6)),
    onPlay: play ?? (_) {},
    onDetails: open ?? (_) {},
    onResume: resume ?? (_) {},
    onHistory: allHistory ?? () {},
  ),
);

void main() {
  test(
    'new routes keep existing menu identities and recognize dedicated channels',
    () {
      expect(menu.getPath(4), '/cinema');
      expect(menu.indexForPath('/tab/home/'), 5);
      expect(menu.indexForPath('/tab/shorts/'), 6);
      expect(menu.indexForPath('/tab/youtube/'), 7);
      expect(menu.indexForPath('/tab/cinema/library'), 4);
    },
  );
  test(
    'late search results and errors cannot overwrite a newer request',
    () async {
      final service = FakeCatalog();
      service.delayed['旧搜索'] = Completer();
      final controller = PortalController(
        channel: PortalChannel.anime,
        catalog: service,
      );
      final old = controller.load(keyword: '旧搜索');
      await controller.load(keyword: '新搜索');
      service.delayed['旧搜索']!.completeError(StateError('旧错误'));
      await old;
      expect(controller.items.first.title, contains('新搜索'));
      expect(controller.errors, isEmpty);
      expect(service.cancellations.first.isCancelled, isTrue);
      controller.dispose();
    },
  );
  test(
    'each feed updates independently; one unavailable source does not blank others',
    () async {
      final service = FakeCatalog()..failing.add(PortalCategory.youtube);
      final controller = PortalController(
        channel: PortalChannel.home,
        catalog: service,
      );
      await controller.load();
      expect(controller.items.any((i) => i.anime != null), isTrue);
      expect(controller.items.any((i) => i.film != null), isTrue);
      expect(controller.errors.keys, [PortalCategory.youtube]);
      service.failing.clear();
      await controller.retry(PortalCategory.youtube);
      expect(controller.errors, isEmpty);
      expect(controller.items.any((i) => i.youtube != null), isTrue);
      controller.dispose();
    },
  );
  test(
    'pagination deduplicates and retains old entries; disposal cancels owned requests',
    () async {
      final service = FakeCatalog();
      final controller = PortalController(
        channel: PortalChannel.anime,
        catalog: service,
      );
      await controller.load();
      await controller.loadMore(PortalCategory.anime);
      expect(controller.items.length, 11);
      expect(controller.items.last.anime!.id, 30);
      expect(controller.groups[PortalCategory.anime]!.next, isNull);
      controller.dispose();
      expect(service.cancellations.last.isCancelled, isTrue);
    },
  );
  test(
    'live catalog uses published region/type links rather than invented title matching',
    () async {
      final cinema = FakeCinema();
      final catalog = LivePortalCatalog(cinema: cinema);
      await catalog.fetch(PortalCategory.chineseFilm);
      expect(
        cinema.visited,
        containsAll([
          'https://example.com/area/cn',
          'https://example.com/area/hk',
        ]),
      );
      cinema.visited.clear();
      await catalog.fetch(PortalCategory.foreignFilm);
      expect(
        cinema.visited,
        containsAll([
          'https://example.com/area/us',
          'https://example.com/area/jp',
        ]),
      );
      cinema.visited.clear();
      await catalog.fetch(PortalCategory.chineseSeries);
      expect(cinema.visited.single, 'https://example.com/type/13');
      cinema.visited.clear();
      await catalog.fetch(PortalCategory.documentary);
      expect(cinema.visited.single, 'https://example.com/type/3');
    },
  );
  test(
    'anime format and origin filters actually reach the API and preserve pagination offsets',
    () async {
      final calls = <({List<String> tags, int offset})>[];
      final catalog = LivePortalCatalog(
        animeQuery: (keyword, tags, offset, token) async {
          calls.add((tags: tags, offset: offset));
          return BangumiSearchPage(items: [anime(1)], rawCount: 28);
        },
      );
      await catalog.fetch(PortalCategory.chineseAnime);
      await catalog.fetch(PortalCategory.japaneseAnime);
      await catalog.fetch(PortalCategory.animeFilm, next: '28');
      await catalog.fetch(PortalCategory.animationShort);
      expect(calls.map((c) => c.tags.single), ['中国', '日本', '剧场版', '短片']);
      expect(calls[2].offset, 28);
    },
  );
  test(
    'category links and source scores are validated; missing scores stay unknown',
    () {
      final parsed = CinemaParser.categoryLinks(
        '<a href="/type/1">电影</a><a href="https://evil.test">电视剧</a>'
        '<a href="javascript:alert(1)">综艺</a>',
        cinemaSource.url,
      );
      expect(parsed, {'电影': 'https://example.com/type/1'});
      final listing = CinemaParser.listing(
        '<a href="/detail/1" title="真实电影" data-original="/1.jpg">'
        '<span class="pic-tag">9.2</span><span class="pic-text">HD</span></a>'
        '<a href="/detail/2" title="另一电影" data-original="/2.jpg"></a>',
        cinemaSource,
        cinemaSource.url,
      );
      expect(listing.films.first.rating, 9.2);
      expect(listing.films.last.rating, 0);
    },
  );
  test(
    'YouTube cards use real durations and covers; private entries and unsafe URLs are skipped',
    () {
      final cards = YoutubeSourceService.browseCards({
        'entries': [
          {
            'id': 'aqz-KE-bpKQ',
            'title': '公开视频',
            'duration': 90,
            'channel': '频道',
            'thumbnails': [
              {'url': 'https://i.ytimg.com/a.jpg', 'width': 120},
              {'url': 'https://i.ytimg.com/b.jpg', 'width': 640},
            ],
          },
          {'id': 'abcdefghijk', 'availability': 'private'},
          {'id': '--bad'},
        ],
      });
      expect(cards.single.duration, const Duration(seconds: 90));
      expect(cards.single.thumbnail, endsWith('/b.jpg'));
      final args = portalYoutubeArgs(cards.single);
      expect(args.plugin.isYoutube, isTrue);
      expect(args.roads.single.data.single, cards.single.pageUrl);
      expect(args.bangumiItem.id, lessThan(0));
    },
  );
  testWidgets(
    'header navigates all six tabs, submits Enter and exposes history/settings',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <int>[];
      final query = <String>[];
      final extras = <String>[];
      var historyCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: PortalStyle.theme(ThemeData.light()),
          home: Scaffold(
            body: PortalHeader(
              selectedIndex: 5,
              onNavigate: selected.add,
              onSearch: query.add,
              onHistory: () => historyCount++,
              onMore: extras.add,
            ),
          ),
        ),
      );
      for (final label in ['首页', '动漫', '影视', '短剧', 'YouTube', '我的']) {
        await tester.tap(find.text(label));
      }
      expect(selected, [5, 0, 4, 6, 7, 3]);
      await tester.enterText(
        find.byKey(const ValueKey('portal-global-search')),
        '凡人修仙传',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(query, ['凡人修仙传']);
      await tester.tap(find.text('观看记录'));
      expect(historyCount, 1);
      await tester.tap(find.byTooltip('更多功能'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(extras, ['settings']);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(1280, 860),
    const Size(840, 600),
    const Size(390, 846),
  ]) {
    testWidgets(
      'homepage actions and history progress work at $size without overflow',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeCatalog();
        final controller = PortalController(
          channel: PortalChannel.home,
          catalog: service,
        );
        final repo = FakeHistory()..entries = [history(42)];
        final played = <PortalItem>[];
        final resumed = <History>[];
        await controller.load();
        await tester.pumpWidget(
          testApp(controller, repo, play: played.add, resume: resumed.add),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('hero-play:anime:1')));
        expect(played.single.anime!.id, 1);
        await tester.ensureVisible(
          find.byKey(ValueKey('resume:${repo.entries.single.key}')),
        );
        await tester.tap(
          find.byKey(ValueKey('resume:${repo.entries.single.key}')),
        );
        expect(resumed.single.lastWatchEpisode, 12);
        final bars = tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .where((b) => b.value != null);
        expect(bars.any((b) => b.value == 0.5), isTrue);
        await tester.ensureVisible(
          find.byKey(const ValueKey('feature-shorts')),
        );
        await tester.tap(find.byKey(const ValueKey('feature-shorts')));
        await tester.pump();
        expect(service.requests.last.category, PortalCategory.shorts);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await repo.updates.close();
      },
    );
  }
  testWidgets('carousel indicators change the actual playback item', (
    tester,
  ) async {
    final controller = PortalController(
      channel: PortalChannel.home,
      catalog: FakeCatalog(),
    );
    final repo = FakeHistory();
    final played = <PortalItem>[];
    await controller.load();
    await tester.pumpWidget(testApp(controller, repo, play: played.add));
    await tester.tap(find.byKey(const ValueKey('hero-dot:1')));
      await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hero-play:anime:2')));
    expect(played.single.anime!.id, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await repo.updates.close();
  });
  testWidgets(
    'search scope and result poster buttons operate on returned items',
    (tester) async {
      final controller = PortalController(
        channel: PortalChannel.home,
        catalog: FakeCatalog(),
      );
      final repo = FakeHistory();
      await controller.load(category: PortalCategory.all, keyword: '搜索词');
      final opened = <PortalItem>[];
      await tester.pumpWidget(testApp(controller, repo, open: opened.add));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('category:anime')));
      await tester.pump();
      expect(controller.keyword, '搜索词');
      expect(controller.items.every((i) => i.anime != null), isTrue);
      await tester.tap(find.byKey(const ValueKey('poster:anime:1')));
      expect(opened.single.anime!.id, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repo.updates.close();
    },
  );
}
