import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/cinema/cinema_controller.dart';
import 'package:kazumi/pages/cinema/cinema_page.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_parser.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';

const source = CinemaSource(
  id: 'one',
  name: '测试影院',
  url: 'https://example.com/',
);
const other = CinemaSource(
  id: 'two',
  name: '另一影院',
  url: 'https://two.example/',
);
const film = CinemaFilm(
  source: source,
  title: '一部很长片名的影片',
  url: 'https://example.com/voddetail/1.html',
  poster: 'https://example.com/cover.jpg',
);

class FakeCinemaService extends CinemaService {
  final List<String> keywords = [];
  Completer<CinemaListing>? delayed;
  @override
  Future<List<CinemaSource>> sources() async => [source, other];
  @override
  Future<CinemaListing> listing(
    CinemaSource source, {
    String keyword = '',
    String? pageUrl,
    CancelToken? cancelToken,
    bool refresh = false,
  }) async {
    keywords.add(keyword);
    if (keyword == '旧搜索') return delayed!.future;
    if (source.id == other.id) throw StateError('该片源需要浏览器验证');
    return CinemaListing(
      films: List.generate(
        18,
        (i) => CinemaFilm(
          source: source,
          title: '$keyword影片 $i',
          url: '${source.url}voddetail/$i.html',
          poster: film.poster,
        ),
      ),
    );
  }
}

void main() {
  test(
    'search highlight tags and category labels do not change film titles',
    () {
      final parsed = CinemaParser.listing(
        '''
      <a href="/voddetail/1" title="&lt;em&gt;深海&lt;/em&gt;"><img src="/a.jpg"></a>
      <div><a href="/voddetail/2" style="background-image:url(/b.jpg)"></a>
        <h3><a href="/voddetail/2"><span class="info_right">国漫</span>深海</a></h3></div>
    ''',
        source,
        source.url,
      );
      expect(parsed.films.map((f) => f.title), ['深海', '深海']);
    },
  );
  test(
    'published name-based search forms are accepted without matching login forms',
    () {
      final form = CinemaParser.searchForm('''
      <form action="/register"><input name="name"></form>
      <form id="searchForm" action="/s"><input name="name"></form>
    ''', source.url);
      expect(form!.url, 'https://example.com/s');
      expect(form.keywordKey, 'name');
    },
  );
  test(
    'stored cinema plugins recover the catalogued search template by address',
    () async {
      final service = CinemaService();
      final stored =
          CinemaService.plugin(
              (await service.sources()).firstWhere((s) => s.id == 'fdz_com'),
            )
            ..name = '我的饭搭子'
            ..searchURL = '';
      final recovered = await service.sourceForPlugin(stored);
      expect(
        recovered.searchUrl('深海'),
        contains('yu-%E6%B7%B1%E6%B5%B7-xianguan'),
      );
      expect(recovered.url, stored.baseUrl);
    },
  );
  test(
    'background poster titles are read while article thumbnails are excluded',
    () {
      final page = CinemaParser.listing(
        '<a href="/voddetail/1/" style="background-image:url(/cover.jpg)">'
        '<p class="vodlist_title">真实影片</p></a>'
        '<a href="/artdetail-123/"><img src="/article.jpg" alt="网站文章"></a>',
        source,
        source.url,
      );
      expect(page.films.single.title, '真实影片');
    },
  );
  test(
    'Hongguo public route JSON resolves media without executing website scripts',
    () {
      final data = jsonEncode({
        'loaderData': {
          'player/page': {
            'video_player_info': {
              'main_url': 'https://cdn.example/video/?token=test',
            },
          },
        },
      });
      expect(
        CinemaParser.directMediaUrl(
          '<script>_ROUTER_DATA = $data;</script>',
          'https://hongguoduanju.com/player/1',
        ),
        'https://cdn.example/video/?token=test',
      );
      expect(
        CinemaParser.directMediaUrl(
          '<script>_ROUTER_DATA = $data;</script>',
          'https://unrelated.example/',
        ),
        isNull,
      );
      const hg = CinemaSource(
        id: 'hg',
        name: '红果短剧',
        url: 'https://hongguoduanju.com/',
      );
      final detail = CinemaParser.detail(
        '<div class="pc-episode-grid-xx"><a href="/player/123">1</a>'
        '<a href="/player/123/456">2</a><button disabled>3</button></div>',
        const CinemaFilm(
          source: hg,
          title: '测试剧',
          url: 'https://hongguoduanju.com/detail?series_id=123',
          poster: '',
        ),
        hg.url,
      );
      expect(detail.roads.single.identifier, ['1', '2']);
      expect(detail.notice, contains('官方网页'));
    },
  );
  test(
    'a source search requiring verification is an error instead of zero results',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: options.path.contains('search')
                      ? '<h1>请输入验证码</h1>'
                      : '<form action="/search"><input name="wd"></form>',
                ),
              );
            },
          ),
        );
      addTearDown(() => dio.close(force: true));
      final service = CinemaService(dio: dio);
      await expectLater(
        service.listing(source, keyword: '凡人'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('验证'),
          ),
        ),
      );
    },
  );
  test('explicit search templates encode keywords inside the published path', () {
    const site = CinemaSource(
      id: 'fdz',
      name: '饭搭子',
      url: 'https://fdzys.net/',
      searchTemplate: '/yu-{keyword}-xianguan-de-yingpian-shippin-zhibo',
    );
    expect(
      site.searchUrl('凡人 /?'),
      'https://fdzys.net/yu-%E5%87%A1%E4%BA%BA%20%2F%3F-xianguan-de-yingpian-shippin-zhibo',
    );
  });
  test(
    'lazy posters deduplicate films and exclude advertisements and external links',
    () {
      final parsed = CinemaParser.listing(
        '''
      <a href="/voddetail/1.html" title="电影一"><img src="loading.gif" data-src="/cover.jpg"></a>
      <a href="/voddetail/1.html"><img src="/cover.jpg" alt="重复"></a>
      <a href="/movie/two" title="电影二" style="background-image:url('/two.webp')"></a>
      <a href="/index.php/adstat/go?slot=ad1"><img src="/ad.webp" alt="广告"></a>
      <a href="https://external.example/movie"><img src="/external.jpg" alt="外部广告"></a>
      <a href="javascript:alert(1)"><img src="/bad.jpg" alt="脚本"></a>
      <a rel="next" href="/list/2.html">下一页</a>
    ''',
        source,
        source.url,
      );
      expect(parsed.films.map((f) => f.title), ['电影一', '电影二']);
      expect(parsed.films.first.poster, 'https://example.com/cover.jpg');
      expect(parsed.nextUrl, 'https://example.com/list/2.html');
    },
  );

  test(
    'search preserves POST hidden fields and uses the actual keyword key',
    () {
      final form = CinemaParser.searchForm('''
      <form action="/search.html?mode=film" method="post">
      <input name="searchword"><input type="hidden" name="type" value="movie"></form>
    ''', source.url)!;
      expect(form.method, 'POST');
      expect(form.keywordKey, 'searchword');
      expect(form.fields, {'type': 'movie'});
      expect(form.url, 'https://example.com/search.html?mode=film');
      expect(
        CinemaParser.searchForm(
          '<form action="https://bad.example/"><input name="wd"></form>',
          source.url,
        ),
        isNull,
      );
    },
  );

  test(
    'nested containers keep separate episode roads without combined duplicates',
    () {
      final detail = CinemaParser.detail(
        '''
      <div class="anthology-tab"><a>线路甲</a><a>线路乙</a></div>
      <div class="play-list">
        <ul class="anthology-list-play"><li><a href="/vodplay/1-1-1.html">第1集</a></li>
          <li><a href="/vodplay/1-1-2.html">第2集</a></li></ul>
        <ul class="anthology-list-play"><li><a href="/vodplay/1-2-1.html">全集</a></li></ul>
      </div>
    ''',
        film,
        film.url,
      );
      expect(detail.roads.map((r) => r.name), ['线路甲', '线路乙']);
      expect(detail.roads.map((r) => r.data.length), [2, 1]);
    },
  );

  test('online home video URLs and numbered film episodes are recognized', () {
    final detail = CinemaParser.detail(
      '''
      <div class="player_name"><a href="#playlist1">天堂云</a></div>
      <div id="playlist1" class="lists-box"><a href="/tv/title/1">第01集</a>
      <a href="/tv/title/2?sid=2">第02集</a></div>
      <ul class="stui-content__playlist"><a href="/video/32-2-1.html">正片</a></ul>
    ''',
      film,
      film.url,
    );
    expect(detail.roads.length, 2);
    expect(detail.roads.first.identifier, ['第01集', '第02集']);
    expect(
      detail.roads.last.data.single,
      'https://example.com/video/32-2-1.html',
    );
  });

  test(
    'direct media supports public JSON encoding and rejects scripts and share pages',
    () {
      const media = 'https://cdn.example/index.m3u8?token=abc';
      for (final encoding in [0, 1, 2]) {
        final encoded = encoding == 0
            ? media
            : encoding == 1
            ? Uri.encodeComponent(media)
            : base64Encode(utf8.encode(Uri.encodeComponent(media)));
        final config = jsonEncode({
          'encrypt': encoding,
          'url': encoded,
          'vod_data': {'name': '电影'},
        });
        expect(
          CinemaParser.directMediaUrl(
            '<script>var player_aaaa=$config;</script>',
            source.url,
          ),
          media,
        );
      }
      for (final url in [
        'javascript:alert(1)',
        'https://pan.example/share/file',
      ]) {
        expect(
          CinemaParser.directMediaUrl(
            '<script>var player_aaaa=${jsonEncode({'encrypt': 0, 'url': url})}</script>',
            source.url,
          ),
          isNull,
        );
      }
    },
  );

  test('movie history IDs stay stable and separate from Bangumi subjects', () {
    expect(film.historyId, lessThan(0));
    expect(
      CinemaFilm(
        source: source,
        title: '改名',
        url: film.url,
        poster: '',
      ).historyId,
      film.historyId,
    );
    expect(
      CinemaFilm(
        source: other,
        title: film.title,
        url: film.url,
        poster: '',
      ).historyId,
      isNot(film.historyId),
    );
  });

  test('one failed source does not discard readable film posters', () async {
    final controller = CinemaController(service: FakeCinemaService());
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.films.length, 18);
    expect(controller.errors[other.id], contains('浏览器验证'));
    expect(controller.loading, isFalse);
    expect(controller.pending, isEmpty);
  });

  test('a superseded search cannot replace newer results', () async {
    final service = FakeCinemaService()..delayed = Completer<CinemaListing>();
    final controller = CinemaController(service: service);
    addTearDown(controller.dispose);
    final old = controller.load(sourceId: source.id, search: '旧搜索');
    await Future<void>.delayed(Duration.zero);
    await controller.load(sourceId: source.id, search: '新搜索');
    service.delayed!.complete(const CinemaListing(films: [film]));
    await old;
    expect(controller.films.first.title, '新搜索影片 0');
  });

  for (final width in [390.0, 1218.0]) {
    testWidgets(
      'poster grid at width $width fits and keeps search and source status usable',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 846));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = FakeCinemaService();
        final controller = CinemaController(service: service);
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: CinemaPage(controller: controller),
          ),
        );
        await tester.pump();
        expect(find.text('热门影视'), findsOneWidget);
        expect(find.byType(CinemaPosterCard), findsWidgets);
        expect(tester.takeException(), isNull);
        if (width > 1000) {
          final cards = tester
              .widgetList<CinemaPosterCard>(find.byType(CinemaPosterCard))
              .toList();
          final firstRow = cards
              .where(
                (card) =>
                    tester.getTopLeft(find.byWidget(card)).dy ==
                    tester.getTopLeft(find.byWidget(cards.first)).dy,
              )
              .length;
          expect(firstRow, 6);
        }
        await tester.enterText(find.byType(TextField), '凡人');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(service.keywords, contains('凡人'));
        await tester.tap(find.byTooltip('片源状态'));
        await tester.pumpAndSettle();
        expect(find.text('该片源需要浏览器验证'), findsOneWidget);
        expect(find.byTooltip('打开原站'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
