import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/youtube_models.dart';
import 'package:path/path.dart' as path;

class YoutubeSourceService {
  YoutubeSourceService({String? engineDirectory, String Function()? proxy})
    : engineDirectory =
          engineDirectory ??
          path.join(
            path.dirname(Platform.resolvedExecutable),
            'youtube_engine',
          ),
      _proxy = proxy ?? _configuredProxy;

  static final instance = YoutubeSourceService();
  final String engineDirectory;
  final String Function() _proxy;
  final Map<String, String> _titles = {};

  bool get available =>
      Platform.isWindows &&
      File(path.join(engineDirectory, 'yt-dlp.exe')).existsSync() &&
      File(path.join(engineDirectory, 'node.exe')).existsSync();

  static String _configuredProxy() {
    if (GStorage.getSetting(SettingsKeys.proxyEnable)) {
      return ProxyUtils.getFormattedProxyUrl(
            GStorage.getSetting(SettingsKeys.proxyUrl),
          ) ??
          '';
    }
    final proxy = SystemProxyService.findProxy(
      Uri.parse('https://www.youtube.com'),
    );
    return proxy.startsWith('PROXY ') ? 'http://${proxy.substring(6)}' : '';
  }

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _playlistId = RegExp(r'^[A-Za-z0-9_-]{10,150}$');

  /// Restrict direct links to YouTube, strip unrelated parameters, and never
  /// pass a user-controlled string as a command-line option or shell command.
  static String? normalizeUrl(String value, {bool allowPlaylist = true}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443 && uri.port != 80)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (![
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtu.be',
    ].contains(host))
      return null;
    final list = uri.queryParameters['list'];
    if (allowPlaylist && list != null && _playlistId.hasMatch(list)) {
      return 'https://www.youtube.com/playlist?list=$list';
    }
    final segments = uri.pathSegments;
    final id = host == 'youtu.be'
        ? segments.firstOrNull
        : uri.path == '/watch'
        ? uri.queryParameters['v']
        : segments.length >= 2 &&
              ['shorts', 'live', 'embed'].contains(segments.first)
        ? segments[1]
        : null;
    return id != null && _videoId.hasMatch(id)
        ? 'https://www.youtube.com/watch?v=$id'
        : null;
  }

  Future<PluginSearchResponse> search(
    String keyword, {
    RuleCancelToken? cancelToken,
  }) async {
    final direct = normalizeUrl(keyword);
    final json = await _run([
      '--flat-playlist',
      '--playlist-end',
      '15',
      '--',
      direct ?? 'ytsearch15:${keyword.trim()}',
    ], cancelToken: cancelToken);
    final entries = json['entries'] is List ? json['entries'] as List : [json];
    final items = <SearchItem>[];
    for (final item in entries.whereType<Map>()) {
      final url = item['_type'] == 'playlist'
          ? normalizeUrl(item['webpage_url']?.toString() ?? direct ?? '')
          : normalizeUrl(item['url']?.toString() ?? '') ??
                normalizeUrl('https://www.youtube.com/watch?v=${item['id']}');
      if (url == null) continue;
      final title = item['title']?.toString() ?? 'YouTube 视频';
      if (_titles.length > 300) _titles.clear();
      _titles[url] = title;
      final channel = item['channel']?.toString() ?? '';
      final seconds = (item['duration'] as num?)?.round();
      final duration = seconds == null
          ? ''
          : ' · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      items.add(
        SearchItem(
          name: '$title${channel.isEmpty ? '' : ' · $channel'}$duration',
          src: url,
        ),
      );
    }
    if (direct != null && direct.contains('/playlist?') && items.isNotEmpty) {
      return PluginSearchResponse(
        pluginName: 'YouTube',
        data: [
          SearchItem(
            name: json['title']?.toString() ?? 'YouTube 播放列表',
            src: direct,
          ),
        ],
      );
    }
    if (items.isEmpty) throw const NoResultException('YouTube');
    return PluginSearchResponse(pluginName: 'YouTube', data: items);
  }

  /// Public metadata for the homepage. No media is downloaded.
  Future<List<YoutubeCard>> browse(
    String keyword, {
    int limit = 15,
    RuleCancelToken? cancelToken,
  }) async {
    final direct = normalizeUrl(keyword);
    final json = await _run([
      '--flat-playlist',
      '--playlist-end',
      '$limit',
      '--',
      direct ?? 'ytsearch$limit:${keyword.trim()}',
    ], cancelToken: cancelToken);
    return browseCards(json);
  }

  static List<YoutubeCard> browseCards(Map<String, dynamic> json) {
    final entries = json['entries'] is List ? json['entries'] as List : [json];
    final cards = <String, YoutubeCard>{};
    for (final item in entries.whereType<Map>()) {
      if ([
        'private',
        'needs_auth',
        'subscriber_only',
      ].contains(item['availability']))
        continue;
      final url =
          normalizeUrl(
            item['webpage_url']?.toString() ?? item['url']?.toString() ?? '',
            allowPlaylist: false,
          ) ??
          normalizeUrl(
            'https://www.youtube.com/watch?v=${item['id']}',
            allowPlaylist: false,
          );
      if (url == null) continue;
      var thumbnail = item['thumbnail']?.toString() ?? '';
      final thumbs = (item['thumbnails'] as List? ?? [])
          .whereType<Map>()
          .toList();
      thumbs.sort(
        (a, b) =>
            ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0),
      );
      if (thumbs.isNotEmpty)
        thumbnail = thumbs.first['url']?.toString() ?? thumbnail;
      if (!['http', 'https'].contains(Uri.tryParse(thumbnail)?.scheme))
        thumbnail = '';
      final seconds = (item['duration'] as num?)?.toInt();
      cards[url] = YoutubeCard(
        pageUrl: url,
        title: item['title']?.toString() ?? 'YouTube 视频',
        thumbnail: thumbnail,
        channel:
            item['channel']?.toString() ?? item['uploader']?.toString() ?? '',
        duration: seconds != null && seconds > 0
            ? Duration(seconds: seconds)
            : null,
      );
    }
    return cards.values.toList();
  }

  Future<List<Road>> chapters(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    final url = normalizeUrl(source);
    if (url == null) throw ArgumentError('无效的 YouTube 链接');
    if (url.contains('/watch?')) {
      return [
        Road(
          name: 'YouTube',
          data: [url],
          identifier: [_titles[url] ?? '播放视频'],
        ),
      ];
    }
    final json = await _run([
      '--flat-playlist',
      '--playlist-end',
      '300',
      '--',
      url,
    ], cancelToken: cancelToken);
    final data = <String>[];
    final names = <String>[];
    for (final entry in (json['entries'] as List? ?? []).whereType<Map>()) {
      final target = normalizeUrl(
        'https://www.youtube.com/watch?v=${entry['id']}',
        allowPlaylist: false,
      );
      if (target == null ||
          [
            'private',
            'needs_auth',
            'subscriber_only',
          ].contains(entry['availability']))
        continue;
      data.add(target);
      names.add(entry['title']?.toString() ?? '第${data.length}个视频');
    }
    if (data.isEmpty) throw StateError('播放列表中没有公开可播放的视频');
    return [Road(name: 'YouTube 播放列表', data: data, identifier: names)];
  }

  Future<YoutubeVideo> resolve(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    final url = normalizeUrl(source, allowPlaylist: false);
    if (url == null) throw ArgumentError('无效的 YouTube 视频链接');
    return YoutubeVideo.fromJson(
      url,
      await _run(['--no-playlist', '--', url], cancelToken: cancelToken),
    );
  }

  Future<Map<String, dynamic>> _run(
    List<String> args, {
    RuleCancelToken? cancelToken,
  }) async {
    if (!available)
      throw StateError('YouTube 组件未安装，请运行 tools/setup_youtube.ps1 后重新编译');
    if (cancelToken?.isCancelled ?? false) throw StateError('YouTube 请求已取消');
    final process = await Process.start(
      path.join(engineDirectory, 'yt-dlp.exe'),
      [
        '--ignore-config',
        '--no-plugin-dirs',
        '--no-cache-dir',
        '--skip-download',
        '--dump-single-json',
        '--no-warnings',
        '--socket-timeout',
        '15',
        '--retries',
        '1',
        '--extractor-retries',
        '1',
        '--js-runtimes',
        'node:${path.join(engineDirectory, 'node.exe')}',
        '--proxy',
        _proxy(),
        ...args,
      ],
      environment: {
        'PYTHONHOME': '',
        'PYTHONPATH': '',
        'PYTHONIOENCODING': 'utf-8',
      },
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    var finished = false;
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 90), () {
      timedOut = true;
      process.kill();
    });
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!finished) process.kill();
      }),
    );
    try {
      final exit = await process.exitCode;
      final output = await stdoutFuture;
      final error = await stderrFuture;
      if (cancelToken?.isCancelled ?? false) throw StateError('YouTube 请求已取消');
      if (timedOut) throw TimeoutException('YouTube 解析超时，请检查代理或网络');
      if (exit != 0) {
        if (error.contains('Sign in') || error.contains('not a bot')) {
          throw StateError('YouTube 要求登录或验证；请在浏览器打开视频检查访问状态');
        }
        if (error.contains('country') || error.contains('region')) {
          throw StateError('此 YouTube 视频受到地区限制');
        }
        throw StateError('YouTube 解析失败，请检查代理、网络或视频是否公开');
      }
      final json = jsonDecode(output);
      if (json is! Map) throw const FormatException('YouTube 返回了无效数据');
      return Map<String, dynamic>.from(json);
    } finally {
      finished = true;
      timer.cancel();
    }
  }
}
