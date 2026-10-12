import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    if (!await _client.usesOfficial) {
      final subject = await BangumiApi.getBangumiInfoByID(bgmBangumiID);
      if (subject == null) return 0;
      final title = subject.nameCn.isNotEmpty ? subject.nameCn : subject.name;
      final results = await searchAnimes(title);
      // An ambiguous result should be selected explicitly instead of silently using another season.
      if (results.animes.length != 1) return 0;
      return results.animes.single.animeId;
    }
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    final endPoint =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    if (bangumiID < 0 || !await _client.usesOfficial) {
      final response = await getDanDanEpisodesByDanDanBangumiID(bangumiID);
      if (bangumiID < 0) {
        final match = response.episodes
            .where((e) => e.episodeNumber == episode)
            .firstOrNull;
        return match == null ? [] : getDanDanmakuByEpisodeID(match.episodeId);
      }
      if (episode < 1 || episode > response.episodes.length) return [];
      return getDanDanmakuByEpisodeID(response.episodes[episode - 1].episodeId);
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) =>
      _getComments(episodeID.toString());

  static Future<List<DanmakuEntry>> _getComments(String episodeID) async {
    final endPoint =
        '${ApiEndpoints.dandanAPIDomain}${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    KazumiLogger().i('Danmaku: final request URL $endPoint');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
  }
}
