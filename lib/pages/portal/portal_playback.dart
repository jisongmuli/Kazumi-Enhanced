import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/video_source/youtube_models.dart';

OnlineVideoPlaybackArgs portalCinemaArgs(CinemaDetail detail) {
  if (detail.roads.isEmpty) throw StateError('此站暂未返回播放列表，请在详情页打开原站');
  final film = detail.film;
  return OnlineVideoPlaybackArgs(
    bangumiItem: portalFilmItem(film),
    plugin: CinemaService.plugin(film.source),
    title: film.title,
    src: film.url,
    roads: detail.roads,
  );
}

BangumiItem portalFilmItem(CinemaFilm film) => BangumiItem.fromJson({
  'id': film.historyId,
  'type': 6,
  'name': film.title,
  'name_cn': film.title,
  'summary': film.summary,
  'images': {'large': film.poster},
  'rating': {},
  'info': '影视片源：${film.source.name}',
});

OnlineVideoPlaybackArgs portalYoutubeArgs(YoutubeCard video) {
  final film = CinemaFilm(
    source: const CinemaSource(
      id: 'youtube',
      name: 'YouTube',
      url: 'https://www.youtube.com/',
    ),
    title: video.title,
    url: video.pageUrl,
    poster: video.thumbnail,
  );
  final plugin = Plugin.fromTemplate()
    ..type = 'youtube'
    ..name = 'YouTube'
    ..baseUrl = 'https://www.youtube.com/'
    ..referer = 'https://www.youtube.com/';
  return OnlineVideoPlaybackArgs(
    bangumiItem: portalFilmItem(film),
    plugin: plugin,
    title: video.title,
    src: video.pageUrl,
    roads: [
      Road(name: 'YouTube', data: [video.pageUrl], identifier: [video.title]),
    ],
  );
}
