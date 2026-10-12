import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';

typedef PortalAnimeQuery =
    Future<BangumiSearchPage?> Function(
      String keyword,
      List<String> tags,
      int offset,
      CancelToken? cancelToken,
    );

abstract class PortalCatalog {
  Future<PortalListing> fetch(
    PortalCategory category, {
    String keyword = '',
    String? next,
    bool refresh = false,
    CancelToken? cancelToken,
  });
}

class LivePortalCatalog implements PortalCatalog {
  LivePortalCatalog({
    CinemaService? cinema,
    YoutubeSourceService? youtube,
    PortalAnimeQuery? animeQuery,
  }) : cinema = cinema ?? CinemaService.instance,
       youtube = youtube ?? YoutubeSourceService.instance,
       _animeQuery = animeQuery ?? _queryAnime;
  final CinemaService cinema;
  final YoutubeSourceService youtube;
  final PortalAnimeQuery _animeQuery;
  static Future<BangumiSearchPage?> _queryAnime(
    String keyword,
    List<String> tags,
    int offset,
    CancelToken? token,
  ) => BangumiApi.bangumiSearch(
    keyword,
    tags: tags,
    limit: 20,
    offset: offset,
    sort: 'heat',
    cancelToken: token,
  );
  final _cache = <String, ({DateTime time, PortalListing data})>{};

  @override
  Future<PortalListing> fetch(
    PortalCategory category, {
    String keyword = '',
    String? next,
    bool refresh = false,
    CancelToken? cancelToken,
  }) async {
    final key = '${category.name}:$keyword:$next';
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.time).inMinutes < 15) {
      return cached.data;
    }
    final PortalListing result;
    if (category == PortalCategory.youtube) {
      // Flat metadata avoids resolving every signed media stream just to show covers.
      final items = await youtube.browse(
        keyword.isEmpty ? '旅行 风景 4K' : keyword,
        limit: next == null ? 15 : int.parse(next),
        cancelToken: cancelToken,
      );
      result = PortalListing(
        items.map(PortalItem.fromYoutube).toList(),
        next:
            items.length >= (next == null ? 15 : int.parse(next)) &&
                (next == null || int.parse(next) < 60)
            ? '${(next == null ? 15 : int.parse(next)) + 15}'
            : null,
      );
    } else if (_animeCategories.contains(category)) {
      final offset = int.tryParse(next ?? '') ?? 0;
      final tags = switch (category) {
        PortalCategory.chineseAnime => ['中国'],
        PortalCategory.japaneseAnime => ['日本'],
        PortalCategory.animeFilm => ['剧场版'],
        PortalCategory.animationShort => ['短片'],
        _ => <String>[],
      };
      final page = await _animeQuery(keyword, tags, offset, cancelToken);
      if (page == null) throw StateError('动漫目录暂时无法连接，请检查网络后重试');
      result = PortalListing(
        page.items.map(PortalItem.fromAnime).toList(),
        next: page.rawCount >= 20 ? '${offset + page.rawCount}' : null,
      );
    } else {
      result = await _films(category, keyword, next, refresh, cancelToken);
    }
    if (cancelToken?.isCancelled != true) {
      if (_cache.length > 100) _cache.clear();
      _cache[key] = (time: DateTime.now(), data: result);
    }
    return result;
  }

  static const _animeCategories = {
    PortalCategory.recommend,
    PortalCategory.anime,
    PortalCategory.chineseAnime,
    PortalCategory.japaneseAnime,
    PortalCategory.animeFilm,
    PortalCategory.animationShort,
  };

  Future<PortalListing> _films(
    PortalCategory category,
    String keyword,
    String? next,
    bool refresh,
    CancelToken? cancelToken,
  ) async {
    final sources = await cinema.sources();
    if (next != null) {
      final cursors = (jsonDecode(next) as List).cast<Map>();
      final pages = await Future.wait(
        cursors.map((cursor) async {
          final source = sources.firstWhere((s) => s.id == cursor['source']);
          final url = cursor['url'] as String;
          if (Uri.parse(url).host != Uri.parse(source.url).host) {
            throw StateError('分页地址无效');
          }
          return (
            source: source,
            listing: await cinema.listing(
              source,
              pageUrl: url,
              cancelToken: cancelToken,
            ),
          );
        }),
      );
      return _combine(pages);
    }
    if (category == PortalCategory.shorts) {
      final source = sources.firstWhere((s) => s.id == 'hongguo_official');
      return _combine([
        (
          source: source,
          listing: await cinema.listing(
            source,
            keyword: keyword,
            refresh: refresh,
            cancelToken: cancelToken,
          ),
        ),
      ]);
    }
    Object? lastError;
    for (final id in ['libvio_cam', 'fdz_com', 'libvio_lat', 'libvio_bid']) {
      if (cancelToken?.isCancelled == true) throw StateError('请求已取消');
      final source = sources.where((s) => s.id == id).firstOrNull;
      if (source == null) continue;
      try {
        if (keyword.isNotEmpty) {
          return _combine([
            (
              source: source,
              listing: await cinema.listing(
                source,
                keyword: keyword,
                cancelToken: cancelToken,
                refresh: refresh,
              ),
            ),
          ]);
        }
        final links = await cinema.categoryLinks(
          source,
          cancelToken: cancelToken,
        );
        final kind = switch (category) {
          PortalCategory.chineseSeries || PortalCategory.foreignSeries => '电视剧',
          PortalCategory.documentary => '纪录片',
          PortalCategory.variety => '综艺',
          _ => '电影',
        };
        final base = links[kind];
        if (base == null) throw StateError('此站尚未公布$kind分类');
        final List<String> urls;
        if (category == PortalCategory.chineseFilm ||
            category == PortalCategory.foreignFilm) {
          final areas = await cinema.categoryLinks(
            source,
            pageUrl: base,
            cancelToken: cancelToken,
          );
          final names = category == PortalCategory.chineseFilm
              ? ['大陆', '香港', '台湾']
              : ['美国', '英国', '日本', '韩国'];
          urls = names
              .map((name) => areas[name])
              .whereType<String>()
              .toSet()
              .toList();
          if (urls.isEmpty) throw StateError('此站尚未公布地区筛选入口');
        } else if (category == PortalCategory.chineseSeries) {
          final seriesLinks = await cinema.categoryLinks(
            source,
            pageUrl: base,
            cancelToken: cancelToken,
          );
          urls = [seriesLinks['国产剧'] ?? (throw StateError('此站未公布国产剧分类'))];
        } else if (category == PortalCategory.foreignSeries) {
          final seriesLinks = await cinema.categoryLinks(
            source,
            pageUrl: base,
            cancelToken: cancelToken,
          );
          urls = ['欧美剧', '日韩剧', '日本剧', '韩国剧']
              .map((name) => seriesLinks[name])
              .whereType<String>()
              .toSet()
              .toList();
          if (urls.isEmpty) throw StateError('此站未公布海外剧集分类');
        } else {
          urls = [base];
        }
        final pages = await Future.wait(
          urls.map(
            (url) async => (
              source: source,
              listing: await cinema.listing(
                source,
                pageUrl: url,
                cancelToken: cancelToken,
              ),
            ),
          ),
        );
        return _combine(pages);
      } catch (error) {
        if (cancelToken?.isCancelled == true) rethrow;
        lastError = error;
      }
    }
    throw StateError(
      '影视目录暂时无法读取，可重试或在“片源目录”选择其他站点。${lastError is StateError ? ' ${lastError.message}' : ''}',
    );
  }

  PortalListing _combine(
    List<({CinemaSource source, CinemaListing listing})> pages,
  ) {
    final unique = <String, PortalItem>{};
    // Mix region buckets, so "海外" doesn't become only US films on the first screen.
    final longest = pages.fold<int>(
      0,
      (n, p) => p.listing.films.length > n ? p.listing.films.length : n,
    );
    for (var i = 0; i < longest; i++) {
      for (final page in pages) {
        if (i < page.listing.films.length) {
          final item = PortalItem.fromFilm(page.listing.films[i]);
          unique.putIfAbsent(item.key, () => item);
        }
      }
    }
    final cursors = [
      for (final page in pages)
        if (page.listing.nextUrl != null)
          {'source': page.source.id, 'url': page.listing.nextUrl},
    ];
    return PortalListing(
      unique.values.toList(),
      next: cursors.isEmpty ? null : jsonEncode(cursors),
    );
  }
}
