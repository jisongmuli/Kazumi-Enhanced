import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/utils/async_session.dart';

class CinemaController extends ChangeNotifier implements Disposable {
  CinemaController({CinemaService? service})
    : service = service ?? CinemaService.instance;
  final CinemaService service;
  List<CinemaSource> sources = [];
  final Map<String, CinemaListing> listings = {};
  final Map<String, String> errors = {};
  final Set<String> pending = {};
  String selectedSource = '';
  String keyword = '';
  bool loading = false;
  bool loadingMore = false;
  bool initialized = false;
  double scrollOffset = 0;
  final _sessions = AsyncSessionOwner();
  CancelToken? _cancel;

  List<CinemaFilm> get films {
    if (selectedSource.isNotEmpty) return listings[selectedSource]?.films ?? [];
    final buckets = [
      for (final source in sources)
        listings[source.id]?.films ?? <CinemaFilm>[],
    ];
    return [
      for (var i = 0; i < 30; i++)
        for (final films in buckets)
          if (i < films.length) films[i],
    ];
  }

  bool get hasNext =>
      selectedSource.isNotEmpty && listings[selectedSource]?.nextUrl != null;

  Future<void> load({
    String? sourceId,
    String? search,
    bool refresh = false,
  }) async {
    final session = _sessions.begin();
    _cancel?.cancel();
    final cancellation = CancelToken();
    _cancel = cancellation;
    if (sourceId != null) selectedSource = sourceId;
    if (search != null) keyword = search.trim();
    loading = true;
    loadingMore = false;
    listings.clear();
    errors.clear();
    pending.clear();
    notifyListeners();
    try {
      sources = await service.sources();
      if (session.isStale) return;
      final targets = sources
          .where(
            (source) => selectedSource.isEmpty || source.id == selectedSource,
          )
          .toList();
      pending.addAll(targets.map((source) => source.id));
      notifyListeners();
      var nextIndex = 0;
      Future<void> worker() async {
        while (session.isActive && nextIndex < targets.length) {
          final source = targets[nextIndex++];
          try {
            final result = await service.listing(
              source,
              keyword: keyword,
              refresh: refresh,
              cancelToken: cancellation,
            );
            if (session.isStale) return;
            listings[source.id] = result;
          } catch (error) {
            if (session.isStale) return;
            errors[source.id] = error is StateError
                ? error.message.toString()
                : error is DioException && error.response?.statusCode != null
                ? '网站返回 HTTP ${error.response!.statusCode}，可重试或打开原站'
                : error is DioException && error.error is HandshakeException
                ? '网站 TLS 连接或证书校验失败，请检查原站证书后重试'
                : '连接失败或超时，请检查网络后重试';
          }
          if (session.isStale) return;
          pending.remove(source.id);
          notifyListeners();
        }
      }

      await Future.wait(
        List.generate(targets.length < 4 ? targets.length : 4, (_) => worker()),
      );
    } catch (error) {
      if (session.isActive) errors['catalog'] = '片源目录读取失败：$error';
    } finally {
      if (session.isActive) {
        loading = false;
        initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (!hasNext || loading || loadingMore) return;
    final cancellation = _cancel;
    final sourceId = selectedSource;
    final previous = listings[sourceId]!;
    final source = sources.firstWhere((source) => source.id == sourceId);
    loadingMore = true;
    notifyListeners();
    try {
      final page = await service.listing(
        source,
        keyword: keyword,
        pageUrl: previous.nextUrl,
        cancelToken: cancellation,
      );
      if (_sessions.isClosed || cancellation?.isCancelled == true) return;
      final films = {
        for (final film in [...previous.films, ...page.films]) film.key: film,
      };
      listings[sourceId] = CinemaListing(
        films: films.values.toList(),
        nextUrl: page.nextUrl,
      );
    } catch (error) {
      if (!_sessions.isClosed && cancellation?.isCancelled != true) {
        errors[sourceId] = '加载下一页失败，请重试';
      }
    } finally {
      if (!_sessions.isClosed && cancellation?.isCancelled != true) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _sessions.close();
    _cancel?.cancel();
    super.dispose();
  }
}
