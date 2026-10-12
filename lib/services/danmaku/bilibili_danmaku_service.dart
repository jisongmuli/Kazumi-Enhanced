import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:kazumi/services/danmaku/bilibili_danmaku_proto.dart';

/// Public Bilibili metadata/XML adapter. Negative IDs identify this provider
/// and are stable across restarts; no Node service or developer secret needed.
class BilibiliDanmakuService {
  BilibiliDanmakuService({required Dio Function() dio}) : _dio = dio;
  final Dio Function() _dio;
  Future<({String cookie, String key})>? _session;
  DateTime? _sessionTime;
  final _durations = <int, int>{};
  static const _api = 'https://api.bilibili.com';
  static const _headers = {
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'referer': 'https://www.bilibili.com/',
  };
  static const _mixin = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  static bool ownsPath(String path) =>
      RegExp(r'^/api/v2/(?:bangumi|comment)/-\d+$').hasMatch(path);

  Future<Map<String, dynamic>> get(
    Uri original, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) throw StateError('请求已取消');
    final query = {...original.queryParameters, ...?queryParameters};
    if (original.path == '/api/v2/search/episodes' ||
        original.path == '/api/v2/search/anime') {
      return search(
        '${query['anime'] ?? query['keyword'] ?? ''}',
        cancelToken: cancelToken,
      );
    }
    final id = int.tryParse(original.pathSegments.last);
    if (id == null || id >= 0 || !ownsPath(original.path))
      throw StateError('内置弹幕源编号无效，请重新搜索');
    if (original.path.startsWith('/api/v2/bangumi/')) {
      return episodes(-id, cancelToken: cancelToken);
    }
    return comments(-id, cancelToken: cancelToken);
  }

  Future<dynamic> _json(
    String path, {
    Map<String, dynamic>? query,
    String cookie = '',
    CancelToken? token,
  }) async {
    final response = await _dio().get(
      '$_api$path',
      queryParameters: query,
      cancelToken: token,
      options: Options(
        headers: {..._headers, if (cookie.isNotEmpty) 'cookie': cookie},
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final json = response.data;
    if (json is! Map) throw StateError('哔哩哔哩返回了无效数据，请稍后重试');
    return json;
  }

  Future<({String cookie, String key})> _bootstrap(CancelToken? token) async {
    if (_sessionTime != null &&
        DateTime.now().difference(_sessionTime!).inMinutes >= 60)
      _session = null;
    return _session ??= (() async {
      try {
        final nav = await _json('/x/web-interface/nav', token: token);
        // Logged-out nav uses code -101 but still publishes the web signing key.
        final wbi = nav['data']?['wbi_img'];
        if (wbi is! Map) throw StateError('哔哩哔哩搜索暂时不可用，请稍后重试');
        String keyPart(String name) =>
            Uri.parse('${wbi[name]}').pathSegments.last.split('.').first;
        final raw = keyPart('img_url') + keyPart('sub_url');
        if (raw.length != 64) throw StateError('哔哩哔哩搜索参数无效，请稍后重试');
        final key = _mixin.map((i) => raw[i]).join().substring(0, 32);
        final fingerprint = await _json('/x/frontend/finger/spi', token: token);
        final data = fingerprint['data'];
        final b3 = data is Map ? '${data['b_3'] ?? ''}' : '';
        final b4 = data is Map ? '${data['b_4'] ?? ''}' : '';
        if (b3.isEmpty || RegExp(r'[;\r\n]').hasMatch(b3 + b4))
          throw StateError('哔哩哔哩匿名会话暂时不可用');
        _sessionTime = DateTime.now();
        return (cookie: 'buvid3=$b3; buvid4=$b4', key: key);
      } catch (_) {
        _session = null;
        rethrow;
      }
    })();
  }

  static Map<String, dynamic> signedParams(
    Map<String, dynamic> values,
    String key,
    int timestamp,
  ) {
    final params = {...values, 'wts': timestamp};
    final keys = params.keys.toList()..sort();
    final query = keys
        .map(
          (name) =>
              '${Uri.encodeComponent(name)}=${Uri.encodeComponent('${params[name]}'.replaceAll(RegExp(r"[!'()*]"), ''))}',
        )
        .join('&');
    return {
      ...params,
      'w_rid': md5.convert(utf8.encode(query + key)).toString(),
    };
  }

  Future<Map<String, dynamic>> search(
    String title, {
    CancelToken? cancelToken,
  }) async {
    final keyword = title.trim();
    if (keyword.isEmpty) throw StateError('请输入番剧名称');
    final session = await _bootstrap(cancelToken);
    final json = await _json(
      '/x/web-interface/wbi/search/type',
      query: signedParams(
        {'keyword': keyword, 'search_type': 'media_bangumi'},
        session.key,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      cookie: session.cookie,
      token: cancelToken,
    );
    if (json['code'] != 0) {
      _session = null;
      throw StateError('哔哩哔哩暂时限制搜索请求，请稍后重试或设置兼容弹幕接口');
    }
    final data = json['data'];
    final rows = data is Map ? data['result'] : null;
    if (rows is! List) throw StateError('弹幕搜索返回了无效结果');
    final results = <int, Map<String, dynamic>>{};
    for (final row in rows.whereType<Map>()) {
      final id = int.tryParse('${row['season_id']}');
      final name =
          html.parseFragment('${row['title'] ?? ''}').text?.trim() ?? '';
      if (id == null || id <= 0 || name.isEmpty) continue;
      results[-id] = {
        'animeId': -id,
        'animeTitle': name,
        'typeDescription': '哔哩哔哩 · ${row['ep_size'] ?? "未知"} 集',
      };
    }
    return {
      'success': true,
      'animes': results.values.toList(),
      'hasMore': (int.tryParse('${data['numPages']}') ?? 1) > 1,
    };
  }

  Future<Map<String, dynamic>> episodes(
    int season, {
    CancelToken? cancelToken,
  }) async {
    final json = await _json(
      '/pgc/view/web/season',
      query: {'season_id': season},
      token: cancelToken,
    );
    if (json['code'] != 0) throw StateError('此番剧的公开分集暂时不可用，请重试或切换弹幕源');
    final result = json['result'];
    final rows = result is Map ? result['episodes'] : null;
    if (rows is! List) throw StateError('弹幕分集返回了无效数据');
    if (_durations.length > 1000) _durations.clear();
    for (final row in rows.whereType<Map>()) {
      final cid = int.tryParse('${row['cid']}');
      final duration = int.tryParse('${row['duration']}');
      if (cid != null && cid > 0 && duration != null && duration > 0)
        _durations[cid] = duration;
    }
    return episodeResponse(season, rows);
  }

  static Map<String, dynamic> episodeResponse(int season, List<dynamic> rows) {
    final episodes = <int, Map<String, dynamic>>{};
    for (final row in rows.whereType<Map>()) {
      final number = int.tryParse('${row['title']}');
      final cid = int.tryParse('${row['cid']}');
      final badge = '${row['badge'] ?? ''}';
      // PVs and extras must not shift normal episode matching by list position.
      if (number == null ||
          number < 1 ||
          cid == null ||
          cid <= 0 ||
          RegExp(r'预告|花絮|PV', caseSensitive: false).hasMatch(badge))
        continue;
      episodes.putIfAbsent(
        number,
        () => {
          'episodeId': -cid,
          'episodeNumber': number,
          'episodeTitle':
              '第 $number 集${row['long_title'] == null || row['long_title'] == '' ? '' : ' · ${row['long_title']}'}',
        },
      );
    }
    final sorted = episodes.keys.toList()..sort();
    return {
      'success': true,
      'errorCode': 0,
      'errorMessage': '',
      'bangumi': {
        'animeId': -season,
        'episodes': [for (final n in sorted) episodes[n]],
      },
    };
  }

  Future<Map<String, dynamic>> comments(
    int cid, {
    CancelToken? cancelToken,
  }) async {
    final duration = _durations[cid];
    if (duration != null) {
      // Six-minute segments cover the episode; XML pools may be limited.
      final count = (duration / 360000).ceil().clamp(1, 40);
      var next = 1;
      final pages = <int, List<Map<String, dynamic>>>{};
      Future<void> worker() async {
        while (next <= count && cancelToken?.isCancelled != true) {
          final index = next++;
          final response = await _dio().get(
            '$_api/x/v2/dm/web/seg.so',
            queryParameters: {'type': 1, 'oid': cid, 'segment_index': index},
            cancelToken: cancelToken,
            options: Options(
              headers: _headers,
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          pages[index] = BilibiliDanmakuProto.parse(response.data as List<int>);
        }
      }

      await Future.wait(List.generate(count < 3 ? count : 3, (_) => worker()));
      if (cancelToken?.isCancelled == true) throw StateError('请求已取消');
      final result = [
        for (var i = 1; i <= count; i++) ...?pages[i],
      ].take(50000).toList();
      result.sort(
        (a, b) => double.parse(
          a['p'].split(',')[0],
        ).compareTo(double.parse(b['p'].split(',')[0])),
      );
      return {'success': true, 'comments': result};
    }
    final response = await _dio().get(
      'https://comment.bilibili.com/$cid.xml',
      cancelToken: cancelToken,
      options: Options(
        headers: _headers,
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final raw = response.data;
    if (raw is! List<int>) throw StateError('此集返回了无效的弹幕数据');
    final text = decodeXml(raw, response.headers.value('content-encoding'));
    if (text.length > 8 * 1024 * 1024 || !text.contains('<i>')) {
      throw StateError('此集暂时无法读取公开弹幕，请稍后重试');
    }
    return {'success': true, 'comments': parseComments(text)};
  }

  static String decodeXml(List<int> bytes, String? encoding) {
    if (bytes.length > 8 * 1024 * 1024) throw StateError('弹幕数据过大');
    var decoded = bytes;
    // dart:io automatically inflates gzip, but not HTTP deflate responses.
    if (encoding?.toLowerCase().contains('deflate') == true) {
      try {
        decoded = ZLibDecoder().convert(bytes);
      } on FormatException {
        decoded = ZLibDecoder(raw: true).convert(bytes);
      }
    }
    if (decoded.length > 8 * 1024 * 1024) throw StateError('弹幕数据过大');
    return utf8.decode(decoded, allowMalformed: false);
  }

  static List<Map<String, dynamic>> parseComments(String xml) {
    final document = html.parse(xml);
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in document.getElementsByTagName('d')) {
      final fields = (row.attributes['p'] ?? '').split(',');
      if (fields.length < 4) continue;
      final time = double.tryParse(fields[0]);
      final mode = int.tryParse(fields[1]);
      final color = int.tryParse(fields[3]);
      final text = row.text.trim();
      if (time == null ||
          !time.isFinite ||
          time < 0 ||
          mode == null ||
          !{1, 2, 3, 4, 5}.contains(mode) ||
          color == null ||
          color < 0 ||
          color > 0xffffff ||
          text.isEmpty)
        continue;
      final type = mode <= 3 ? 1 : mode;
      final id = fields.length >= 8 ? fields[7] : '$time:$type:$text';
      if (!seen.add(id)) continue;
      result.add({'p': '$time,$type,$color,[BiliBili]', 'm': text});
      if (result.length >= 20000) break;
    }
    result.sort(
      (a, b) => double.parse(
        a['p'].split(',')[0],
      ).compareTo(double.parse(b['p'].split(',')[0])),
    );
    return result;
  }
}
