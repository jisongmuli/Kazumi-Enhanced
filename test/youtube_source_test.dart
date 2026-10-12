import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/video_source/youtube_models.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';

void main() {
  Map<String, Object?> format(
    String id,
    int height, {
    String video = 'avc1',
    String audio = 'none',
    String protocol = 'https',
    int fps = 30,
    bool drm = false,
  }) => {
    'format_id': id,
    'height': height,
    'fps': fps,
    'vcodec': video,
    'acodec': audio,
    'protocol': protocol,
    'has_drm': drm,
    'url': 'https://media.example/$id',
  };

  test('normalizes supported links and rejects unrelated hosts or options', () {
    expect(
      YoutubeSourceService.normalizeUrl('https://youtu.be/aqz-KE-bpKQ?t=30'),
      'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    );
    expect(
      YoutubeSourceService.normalizeUrl(
        'https://www.youtube.com/shorts/aqz-KE-bpKQ',
      ),
      'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    );
    expect(
      YoutubeSourceService.normalizeUrl(
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ&list=PLabcdefghijk',
      ),
      'https://www.youtube.com/playlist?list=PLabcdefghijk',
    );
    for (final link in [
      '--exec=bad',
      'file:///bad',
      'https://youtube.com.evil/watch?v=aqz-KE-bpKQ',
      'https://user@youtube.com/watch?v=aqz-KE-bpKQ',
      'https://youtube.com/watch?v=bad',
    ]) {
      expect(YoutubeSourceService.normalizeUrl(link), isNull);
    }
  });

  test(
    'only real playable resolutions appear, with separate audio and headers',
    () {
      final video = YoutubeVideo.fromJson(
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
        {
          'http_headers': {'User-Agent': 'test-agent'},
          'formats': [
            format('audio', 0, video: 'none', audio: 'opus'),
            format('low', 360),
            format('hd', 1080),
            format('4k', 2160, fps: 60),
            format('drm', 4320, drm: true),
            format('storyboard', 90, video: 'none'),
          ],
        },
      );
      expect(video.qualities.map((item) => item.height), [2160, 1080, 360]);
      expect(video.preferred(1080).id, 'hd');
      expect(video.preferred(1440).id, 'hd');
      expect(video.preferred(144).id, 'low');
      expect(video.qualities.first.label, '2160p 60 FPS');
      expect(video.qualities.first.audioUrl, 'https://media.example/audio');
      expect(video.qualities.first.headers['User-Agent'], 'test-agent');
    },
  );

  test(
    'deduplicates a resolution, preferring high fps and compatible direct streams',
    () {
      final video = YoutubeVideo.fromJson('page', {
        'formats': [
          format('audio', 0, video: 'none', audio: 'opus'),
          format('hls', 1080, protocol: 'm3u8_native', fps: 60),
          format('av1', 1080, video: 'av01', fps: 60),
          format('h264', 1080, fps: 60),
          format('slow', 1080),
        ],
      });
      expect(video.qualities.single.id, 'h264');
    },
  );

  test(
    'progressive streams work without external audio; silent adaptive streams are omitted',
    () {
      final video = YoutubeVideo.fromJson('page', {
        'formats': [
          format('progressive', 720, audio: 'aac'),
          format('silent', 1080),
        ],
      });
      expect(video.qualities.single.height, 720);
      expect(video.qualities.single.audioUrl, isNull);
      expect(
        () => YoutubeVideo.fromJson('page', {
          'formats': [format('silent', 1080)],
        }),
        throwsStateError,
      );
    },
  );

  test(
    'built-in source survives plugin persistence without matching an arbitrary rule name',
    () {
      final plugin = Plugin.fromTemplate()
        ..type = 'youtube'
        ..name = 'YouTube'
        ..baseUrl = 'https://www.youtube.com/';
      expect(Plugin.fromJson(plugin.toJson()).isYoutube, isTrue);
      plugin.type = 'anime';
      expect(plugin.isYoutube, isFalse);
    },
  );
}
