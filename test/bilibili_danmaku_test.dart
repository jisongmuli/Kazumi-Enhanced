import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/core/danmaku_backend_policy.dart';
import 'package:kazumi/services/danmaku/bilibili_danmaku_service.dart';
import 'package:kazumi/services/danmaku/bilibili_danmaku_proto.dart';

class _BiliFixture implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool denySearch = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    dynamic body;
    switch (options.uri.path) {
      case '/x/web-interface/nav':
        body = {
          'code': -101,
          'data': {
            'wbi_img': {
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          },
        };
      case '/x/frontend/finger/spi':
        body = {
          'code': 0,
          'data': {'b_3': 'public-anonymous', 'b_4': 'public-anonymous-4'},
        };
      case '/x/web-interface/wbi/search/type':
        body = denySearch
            ? {'code': -412}
            : {
                'code': 0,
                'data': {
                  'numPages': 1,
                  'result': [
                    {
                      'title': '<em>凡人</em> &amp; 修仙传',
                      'season_id': 28747,
                      'ep_size': 196,
                    },
                    {'title': '重复', 'season_id': null},
                  ],
                },
              };
      case '/pgc/view/web/season':
        body = {
          'code': 0,
          'result': {
            'episodes': [
              {'title': 'PV', 'cid': 100},
              {'title': '195', 'cid': 42361818541, 'badge': '预告'},
              {'title': '196', 'long_title': '慕兰之战20', 'cid': 42628875761},
              {'title': '195', 'long_title': '慕兰之战19', 'cid': 42628875313},
              {'title': '195', 'cid': 999},
              {'title': '花絮', 'cid': 101},
            ],
          },
        };
      default:
        return ResponseBody.fromString(
          '<?xml version="1.0"?><i><d p="2.5,1,25,16777215,0,0,user,42">你好 &amp; 世界</d></i>',
          200,
        );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'mobile defaults use the built-in source; user-selected endpoints and credentials remain authoritative',
    () {
      bool policy({
        bool windows = false,
        String endpoint = '',
        String id = '',
        String secret = '',
      }) => DanmakuBackendPolicy.usesBuiltIn(
        isWindows: windows,
        endpoint: endpoint,
        appId: id,
        appSecret: secret,
      );
      expect(policy(), isTrue);
      expect(policy(endpoint: '  '), isTrue);
      expect(policy(windows: true), isFalse);
      expect(policy(endpoint: 'https://example.test'), isFalse);
      expect(policy(id: 'official'), isFalse);
      expect(policy(secret: 'secret'), isFalse);
    },
  );
  test(
    'public search, large CID episode selection and XML comments form a complete credential-free chain',
    () async {
      final adapter = _BiliFixture();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final service = BilibiliDanmakuService(dio: () => dio);
      final search = DanmakuSearchResponse.fromJson(
        await service.get(
          Uri.parse('https://api.dandanplay.net/api/v2/search/episodes'),
          queryParameters: {'anime': '凡人修仙传'},
        ),
      );
      expect(search.animes.single.animeId, -28747);
      expect(search.animes.single.animeTitle, '凡人 & 修仙传');
      final episodes = DanmakuEpisodeResponse.fromJson(
        await service.get(
          Uri.parse('https://api.dandanplay.net/api/v2/bangumi/-28747'),
        ),
      );
      expect(episodes.episodes.map((e) => e.episodeNumber), [195, 196]);
      expect(episodes.episodes.first.episodeId, -42628875313);
      final data = await service.get(
        Uri.parse(
          'https://api.dandanplay.net/api/v2/comment/${episodes.episodes.first.episodeId}',
        ),
      );
      final entry = DanmakuEntry.fromJson(data['comments'].single);
      expect(entry.message, '你好 & 世界');
      expect(entry.time, 2.5);
      expect(entry.source, '[BiliBili]');
      await service.search('葬送的芙莉莲');
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/nav')).length,
        1,
      );
      final signed = adapter.requests.firstWhere(
        (r) => r.uri.path.contains('/wbi/'),
      );
      expect(signed.queryParameters['keyword'], '凡人修仙传');
      expect(
        signed.queryParameters['w_rid'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );
      expect(signed.headers['cookie'], contains('public-anonymous'));
      expect(
        adapter.requests.every((r) => r.uri.host.endsWith('bilibili.com')),
        isTrue,
      );
      expect(
        adapter.requests.every(
          (r) => !r.headers.keys.any(
            (k) =>
                k.toLowerCase().startsWith('x-app') ||
                k.toLowerCase() == 'authorization',
          ),
        ),
        isTrue,
      );
    },
  );
  test(
    'XML parsing keeps timing, colors and modes while dropping malformed/special/duplicate comments',
    () {
      final parsed = BilibiliDanmakuService.parseComments('''<i>
      <d p="5,4,25,255,0,0,u,1">底部</d><d p="2,5,25,16711680,0,0,u,2">顶部</d>
      <d p="1.5,2,25,65280,0,0,u,3">滚动 &lt;3</d><d p="1.5,2,25,65280,0,0,u,3">重复</d>
      <d p="NaN,1,25,1">坏时间</d><d p="2,7,25,1">高级</d>
      <d p="2,1,25,999999999">坏颜色</d><d p="-1,1,25,1">负时间</d><d p="2,1,25,1"></d>
    </i>''').map(DanmakuEntry.fromJson).toList();
      expect(parsed.map((e) => e.time), [1.5, 2, 5]);
      expect(parsed.map((e) => e.type), [1, 5, 4]);
      expect(parsed.first.message, '滚动 <3');
      expect(parsed.first.color.g, 1);
    },
  );
  test(
    'unsupported IDs and cancellation cannot fall through to the official API',
    () async {
      final adapter = _BiliFixture();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final service = BilibiliDanmakuService(dio: () => dio);
      await expectLater(
        service.get(Uri.parse('https://api.dandanplay.net/api/v2/comment/123')),
        throwsStateError,
      );
      final token = CancelToken()..cancel();
      await expectLater(
        service.get(
          Uri.parse('https://api.dandanplay.net/api/v2/search/episodes'),
          queryParameters: {'anime': '凡人'},
          cancelToken: token,
        ),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'HTTP deflate XML is decoded with zlib and raw deflate without corrupting Chinese text',
    () {
      const xml = '<?xml version="1.0"?><i><d p="1,1,25,16777215">你好</d></i>';
      for (final raw in [false, true]) {
        final encoded = ZLibCodec(raw: raw).encode(utf8.encode(xml));
        expect(BilibiliDanmakuService.decodeXml(encoded, 'deflate'), xml);
      }
      expect(BilibiliDanmakuService.decodeXml(utf8.encode(xml), null), xml);
    },
  );
  test(
    'source restrictions show an error and permit a later retry instead of pretending there are no matches',
    () async {
      final adapter = _BiliFixture()..denySearch = true;
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final service = BilibiliDanmakuService(dio: () => dio);
      await expectLater(service.search('凡人'), throwsStateError);
      adapter.denySearch = false;
      expect((await service.search('凡人'))['animes'], isNotEmpty);
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/nav')).length,
        2,
      );
    },
  );
  test(
    'protobuf segments preserve millisecond timing and safely reject truncated data',
    () {
      List<int> varint(int number) {
        final result = <int>[];
        while (number >= 128) {
          result.add((number & 127) | 128);
          number >>= 7;
        }
        return [...result, number];
      }

      final text = utf8.encode('分段弹幕');
      final element = [
        16,
        ...varint(1234567),
        24,
        5,
        40,
        ...varint(0xff0000),
        58,
        ...varint(text.length),
        ...text,
      ];
      final reply = [10, ...varint(element.length), ...element];
      final entry = DanmakuEntry.fromJson(
        BilibiliDanmakuProto.parse(reply).single,
      );
      expect(entry.time, 1234.567);
      expect(entry.message, '分段弹幕');
      expect(entry.type, 5);
      expect(
        () => BilibiliDanmakuProto.parse(reply.sublist(0, reply.length - 1)),
        throwsFormatException,
      );
    },
  );
}
