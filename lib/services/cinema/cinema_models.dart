import 'package:kazumi/modules/roads/road_module.dart';

class CinemaSource {
  const CinemaSource({
    required this.id,
    required this.name,
    required this.url,
    this.aliases = const [],
    this.searchTemplate,
    this.discoveredFrom,
  });
  final String id;
  final String name;
  final String url;
  final List<String> aliases;
  final String? searchTemplate;
  final String? discoveredFrom;
  String? searchUrl(String keyword) => searchTemplate == null
      ? null
      : Uri.parse(url)
            .resolve(
              searchTemplate!.replaceAll(
                '{keyword}',
                Uri.encodeComponent(keyword.trim()),
              ),
            )
            .toString();
  String get displayName => [name, ...aliases].join(' / ');
  factory CinemaSource.fromJson(Map<String, dynamic> json) => CinemaSource(
    id: json['id'],
    name: json['name'],
    url: json['url'],
    aliases: (json['aliases'] as List? ?? []).cast<String>(),
    searchTemplate: json['searchTemplate'],
    discoveredFrom: json['discoveredFrom'],
  );
}

class CinemaFilm {
  const CinemaFilm({
    required this.source,
    required this.title,
    required this.url,
    required this.poster,
    this.badge = '',
    this.summary = '',
    this.rating = 0,
  });
  final CinemaSource source;
  final String title;
  final String url;
  final String poster;
  final String badge;
  final String summary;

  /// The source's own score, when present. Zero means unknown.
  final double rating;
  String get key => '${source.id}:$url';

  // Keep movie history outside the positive Bangumi subject ID namespace.
  // Dart String.hashCode isn't stable between launches; use a stable FNV hash.
  int get historyId {
    var hash = 2166136261;
    for (final code in key.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0x7fffffff;
    }
    return -(hash + 1);
  }
}

class CinemaListing {
  const CinemaListing({required this.films, this.nextUrl});
  final List<CinemaFilm> films;
  final String? nextUrl;
}

class CinemaDetail {
  const CinemaDetail({
    required this.film,
    required this.roads,
    this.notice = '',
  });
  final CinemaFilm film;
  final List<Road> roads;
  final String notice;
}
