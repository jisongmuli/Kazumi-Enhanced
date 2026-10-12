import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';

// Explicit live check, excluded from the normal offline test suite.
void main() {
  test('YouTube live search, single video, and real quality extraction', () async {
    final engine = Platform.environment['KAZUMI_YOUTUBE_ENGINE']!;
    final output = Platform.environment['KAZUMI_VERIFY_DIR']!;
    final service = YoutubeSourceService(engineDirectory: engine,
      proxy: () => Platform.environment['HTTPS_PROXY'] ?? '');
    final search = await service.search('凡人修仙传');
    expect(search.data, isNotEmpty);
    final roads = await service.chapters(search.data.first.src);
    expect(roads.single.data.single, contains('youtube.com/watch?v='));
    final video = await service.resolve('https://www.youtube.com/watch?v=aqz-KE-bpKQ');
    expect(video.qualities.any((quality) => quality.height == 1080), isTrue);
    expect(video.qualities.any((quality) => quality.height == 2160), isTrue);
    await File('$output/youtube-native-input.json').writeAsString(jsonEncode({
      'qualities': [for (final quality in video.qualities) {
        'id': quality.id, 'height': quality.height, 'videoUrl': quality.videoUrl,
        'audioUrl': quality.audioUrl, 'headers': quality.headers,
      }],
    }));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
