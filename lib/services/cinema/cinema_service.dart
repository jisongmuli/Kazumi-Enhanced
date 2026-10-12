import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_parser.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

class CinemaService {
  CinemaService({Dio? dio}) : _dioOverride = dio;
  final Dio? _dioOverride;
  Dio get _dio => _dioOverride ?? DioFactory.pluginDio;
  static final instance = CinemaService();
  List<CinemaSource>? _sources;
  final Map<String, ({String markup, String url})> _home = {};

  Future<List<CinemaSource>> sources() async => _sources ??= List.unmodifiable(
    (jsonDecode(
              await rootBundle.loadString('assets/cinema_sources.json'),
            )['sources']
            as List)
        .map((json) => CinemaSource.fromJson(Map<String, dynamic>.from(json))),
  );

  static Plugin plugin(CinemaSource source) => Plugin.fromTemplate()
    ..type = 'cinema'
    ..name = '影视 · ${source.name}'
    ..version = '1.0'
    ..baseUrl = source.url
    ..referer = source.url
    ..useWebview = true;

  Future<({String markup, String url})> _get(
    String url, {
    CancelToken? cancelToken,
    String method = 'GET',
    Map<String, String>? fields,
  }) async {
    final response = await _dio.request<String>(
      url,
      cancelToken: cancelToken,
      queryParameters: method == 'POST' ? null : fields,
      data: method == 'POST' ? fields : null,
      options: Options(
        method: method,
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 10),
        contentType: method == 'POST'
            ? Headers.formUrlEncodedContentType
            : null,
        headers: {'user-agent': getRandomUA(), 'referer': url},
      ),
    );
    final markup = response.data ?? '';
    if (RegExp(
      r'浏览器安全验证|请输入验证码|请先完成验证|Protected by cdndefend|Just a moment|Checking your browser',
    ).hasMatch(markup)) {
      throw StateError('该片源需要浏览器验证，请打开原站完成验证');
    }
    return (markup: markup, url: response.realUri.toString());
  }

  Future<CinemaListing> listing(
    CinemaSource source, {
    String keyword = '',
    String? pageUrl,
    CancelToken? cancelToken,
    bool refresh = false,
  }) async {
    final ({String markup, String url}) page;
    if (pageUrl != null) {
      page = await _get(pageUrl, cancelToken: cancelToken);
    } else {
      var home = refresh ? null : _home[source.id];
      home ??= await _get(source.url, cancelToken: cancelToken);
      _home[source.id] = home;
      if (keyword.trim().isEmpty) {
        page = home;
      } else if (source.searchUrl(keyword) case final String url) {
        page = await _get(url, cancelToken: cancelToken);
      } else {
        final form = CinemaParser.searchForm(home.markup, home.url);
        if (form == null) throw StateError('暂未识别该片源的搜索接口，可在原站搜索');
        page = await _get(
          form.url,
          method: form.method,
          fields: {...form.fields, form.keywordKey: keyword.trim()},
          cancelToken: cancelToken,
        );
      }
    }
    final listing = CinemaParser.listing(page.markup, source, page.url);
    if (listing.films.isEmpty && keyword.trim().isEmpty) {
      throw StateError('该站为动态页面或地址发布页，暂时无法直接读取封面，可打开原站');
    }
    return listing;
  }

  Future<CinemaDetail> detail(
    CinemaFilm film, {
    CancelToken? cancelToken,
  }) async {
    final page = await _get(film.url, cancelToken: cancelToken);
    return CinemaParser.detail(page.markup, film, page.url);
  }

  /// Read the public category links advertised by the site itself.
  Future<Map<String, String>> categoryLinks(
    CinemaSource source, {
    String? pageUrl,
    CancelToken? cancelToken,
  }) async {
    final page = await _get(pageUrl ?? source.url, cancelToken: cancelToken);
    return CinemaParser.categoryLinks(page.markup, page.url);
  }

  Future<VideoSource?> resolveEpisode(
    String url, {
    int offset = 0,
    CancelToken? cancelToken,
  }) async {
    final page = await _get(url, cancelToken: cancelToken);
    final media = CinemaParser.directMediaUrl(page.markup, page.url);
    return media == null
        ? null
        : VideoSource(
            url: media,
            offset: offset,
            type: VideoSourceType.online,
            httpHeaders: {'Referer': page.url, 'User-Agent': getRandomUA()},
          );
  }

  Future<CinemaDetail> detailFromPlugin(
    Plugin plugin,
    String url, {
    CancelToken? cancelToken,
  }) => detail(
    CinemaFilm(
      source: CinemaSource(
        id: plugin.name,
        name: plugin.name.replaceFirst('影视 · ', ''),
        url: plugin.baseUrl,
      ),
      title: '',
      url: url,
      poster: '',
    ),
    cancelToken: cancelToken,
  );
}
