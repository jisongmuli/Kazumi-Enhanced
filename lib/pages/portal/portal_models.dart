import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/video_source/youtube_models.dart';

enum PortalChannel { home, anime, cinema, shorts, youtube }

enum PortalCategory {
  recommend('推荐'),
  all('全部'),
  chineseAnime('国产动漫'),
  japaneseAnime('日本动漫'),
  animeFilm('动漫电影'),
  chineseFilm('华语电影'),
  foreignFilm('海外电影'),
  chineseSeries('国产剧集'),
  foreignSeries('海外剧集'),
  shorts('短剧'),
  youtube('YouTube'),
  documentary('纪录片'),
  variety('综艺'),
  animationShort('动画短片'),
  anime('动漫'),
  cinema('影视');

  const PortalCategory(this.label);
  final String label;

  static const browse = [
    recommend,
    all,
    chineseAnime,
    japaneseAnime,
    animeFilm,
    chineseFilm,
    foreignFilm,
    chineseSeries,
    foreignSeries,
    shorts,
    youtube,
    documentary,
    variety,
    animationShort,
  ];
  static const search = [all, anime, cinema, shorts, youtube];
}

class PortalItem {
  const PortalItem({
    required this.key,
    required this.title,
    required this.poster,
    required this.subtitle,
    this.badge = '',
    this.score = 0,
    this.summary = '',
    this.anime,
    this.film,
    this.youtube,
  });
  final String key;
  final String title;
  final String poster;
  final String subtitle;
  final String badge;
  final double score;
  final String summary;
  final BangumiItem? anime;
  final CinemaFilm? film;
  final YoutubeCard? youtube;

  factory PortalItem.fromAnime(BangumiItem item) => PortalItem(
    key: 'anime:${item.id}',
    title: item.nameCn.isEmpty ? item.name : item.nameCn,
    poster: item.images['large'] ?? item.images['common'] ?? '',
    subtitle: item.airDate.isEmpty ? '动漫 · Bangumi' : '${item.airDate} · 动漫',
    score: item.ratingScore,
    summary: item.summary,
    anime: item,
  );
  factory PortalItem.fromFilm(CinemaFilm item) => PortalItem(
    key: item.key,
    title: item.title,
    poster: item.poster,
    subtitle: item.source.name,
    badge: item.badge,
    score: item.rating,
    summary: item.summary,
    film: item,
  );
  factory PortalItem.fromYoutube(YoutubeCard item) => PortalItem(
    key: item.pageUrl,
    title: item.title,
    poster: item.thumbnail,
    subtitle: item.channel.isEmpty ? 'YouTube' : item.channel,
    badge: item.duration == null ? '' : portalTime(item.duration!),
    youtube: item,
  );
}

class PortalListing {
  const PortalListing(this.items, {this.next});
  final List<PortalItem> items;
  final String? next;
}

String portalTime(Duration time) {
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  if (time.inHours == 0) return '${time.inMinutes}:$seconds';
  return '${time.inHours}:${(time.inMinutes % 60).toString().padLeft(2, '0')}:$seconds';
}
