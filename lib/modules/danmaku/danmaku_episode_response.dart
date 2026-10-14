class DanmakuEpisode {
  int episodeId;
  String episodeTitle;
  int? episodeNumber;

  DanmakuEpisode({
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber,
  });

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisode(
      episodeId: json['episodeId'],
      episodeTitle: json['episodeTitle'],
      // Compatible services (including the bundled Node backend) return text
      // numbers; the native source returns integers. Specials can omit a number.
      episodeNumber: int.tryParse('${json['episodeNumber'] ?? ''}'.trim()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
      if (episodeNumber != null) 'episodeNumber': episodeNumber,
    };
  }
}

class DanmakuEpisodeResponse {
  int bangumiId;
  List<DanmakuEpisode> episodes;
  int errorCode;
  bool success;
  String errorMessage;

  DanmakuEpisodeResponse({
    required this.bangumiId,
    required this.episodes,
    required this.errorCode,
    required this.success,
    required this.errorMessage,
  });

  factory DanmakuEpisodeResponse.fromJson(Map<String, dynamic> json) {
    var list = json['bangumi']['episodes'] as List;
    List<DanmakuEpisode> episodeList = list
        .map((i) => DanmakuEpisode.fromJson(i))
        .toList();

    return DanmakuEpisodeResponse(
      bangumiId: json['bangumi']['animeId'],
      episodes: episodeList,
      errorCode: json['errorCode'],
      success: json['success'],
      errorMessage: json['errorMessage'],
    );
  }

  factory DanmakuEpisodeResponse.fromTemplate() {
    return DanmakuEpisodeResponse(
      bangumiId: 0,
      episodes: [],
      errorCode: 0,
      success: false,
      errorMessage: '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bangumi': {
        'animeId': bangumiId,
        'episodes': episodes.map((episode) => episode.toJson()).toList(),
      },
      'errorCode': errorCode,
      'success': success,
      'errorMessage': errorMessage,
    };
  }
}
