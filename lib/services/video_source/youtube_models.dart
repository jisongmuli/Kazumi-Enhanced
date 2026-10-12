class YoutubeCard {
  const YoutubeCard({
    required this.pageUrl,
    required this.title,
    required this.thumbnail,
    this.channel = '',
    this.duration,
  });
  final String pageUrl;
  final String title;
  final String thumbnail;
  final String channel;
  final Duration? duration;
}

class YoutubeQuality {
  const YoutubeQuality({
    required this.id,
    required this.height,
    required this.fps,
    required this.videoUrl,
    required this.audioUrl,
    required this.headers,
  });

  final String id;
  final int height;
  final double fps;
  final String videoUrl;
  final String? audioUrl;
  final Map<String, String> headers;

  String get label =>
      '$height'
      'p${fps > 30 ? ' ${fps.round()} FPS' : ''}';
}

class YoutubeVideo {
  const YoutubeVideo({required this.pageUrl, required this.qualities});
  final String pageUrl;
  final List<YoutubeQuality> qualities;

  // Start at 1080p to avoid unexpectedly buffering a 4K stream. The menu
  // still exposes every resolution actually returned by the extractor.
  YoutubeQuality preferred(int height) => qualities.firstWhere(
    (quality) => quality.height <= height,
    orElse: () => qualities.last,
  );

  factory YoutubeVideo.fromJson(String pageUrl, Map<String, dynamic> json) {
    final formats = (json['formats'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) =>
              item['has_drm'] != true &&
              Uri.tryParse(item['url']?.toString() ?? '')?.scheme == 'https',
        )
        .toList();
    final audio = formats
        .where(
          (item) =>
              item['vcodec'] == 'none' &&
              item['acodec'] != 'none' &&
              item['acodec'] != null,
        )
        .toList();
    audio.sort((a, b) => _audioScore(b).compareTo(_audioScore(a)));
    final byHeight = <int, Map<String, dynamic>>{};
    for (final item in formats) {
      final height = (item['height'] as num?)?.toInt() ?? 0;
      if (height <= 0 || item['vcodec'] == null || item['vcodec'] == 'none') {
        continue;
      }
      if ((item['acodec'] == null || item['acodec'] == 'none') &&
          audio.isEmpty) {
        continue;
      }
      final previous = byHeight[height];
      if (previous == null || _videoScore(item) > _videoScore(previous)) {
        byHeight[height] = item;
      }
    }
    final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
    if (heights.isEmpty) {
      throw StateError('YouTube 没有返回可播放的画质，视频可能需要登录或受地区限制');
    }
    return YoutubeVideo(
      pageUrl: pageUrl,
      qualities: List.unmodifiable(
        heights.map((height) {
          final item = byHeight[height]!;
          final needsAudio = item['acodec'] == null || item['acodec'] == 'none';
          return YoutubeQuality(
            id: item['format_id'].toString(),
            height: height,
            fps: (item['fps'] as num?)?.toDouble() ?? 0,
            videoUrl: item['url'].toString(),
            audioUrl: needsAudio ? audio.first['url'].toString() : null,
            headers: {
              ..._headers(json['http_headers']),
              ..._headers(item['http_headers']),
            },
          );
        }),
      ),
    );
  }

  static Map<String, String> _headers(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value.toString()))
      : {};

  static double _audioScore(Map<String, dynamic> format) =>
      (format['protocol'] == 'https' ? 10000 : 0) +
      (format['format_id'].toString().contains('drc') ? 0 : 1000) +
      ((format['abr'] as num?)?.toDouble() ?? 0);

  static double _videoScore(Map<String, dynamic> format) =>
      ((format['fps'] as num?)?.toDouble() ?? 0) * 100000 +
      (format['protocol'] == 'https' ? 10000 : 0) +
      (format['vcodec'].toString().startsWith('avc')
          ? 3000
          : format['vcodec'].toString().startsWith('vp')
          ? 2000
          : 1000) +
      ((format['tbr'] as num?)?.toDouble() ?? 0) / 1000;
}

class YoutubePlaybackState {
  const YoutubePlaybackState({this.video, this.selected, this.busy = false});
  final YoutubeVideo? video;
  final YoutubeQuality? selected;
  final bool busy;
}
