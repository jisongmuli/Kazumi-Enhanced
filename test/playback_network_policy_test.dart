import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/playback_network_policy.dart';

void main() {
  test('HTTP playback applies resilience before segment lookahead', () async {
    final writes = <Object>[];
    await PlaybackNetworkPolicy.apply(
      url: 'https://example.com/index.m3u8?key=signed-value',
      isLocalPlayback: false,
      bufferSize: 32 * 1024 * 1024,
      isCurrent: () => true,
      setProperty: (name, value) async => writes.add([name, value]),
      command: (args) async => writes.add(args),
    );
    expect(writes.first, ['network-timeout', '20']);
    expect(writes[1], ['cache-pause-wait', '6']);
    expect(writes[2], ['cache-pause-initial', 'yes']);
    final retries = writes
        .skip(3)
        .take(writes.length - 4)
        .map((write) => (write as List<String>).last)
        .join(',');
    for (final write in writes.skip(3).take(writes.length - 4)) {
      expect((write as List<String>).last, isNot(contains(',')));
    }
    expect(retries, contains('reconnect_on_network_error=1'));
    expect(retries, contains('reconnect_max_retries=3'));
    expect(retries, contains('reconnect_delay_total_max=15'));
    expect(retries, isNot(contains('reconnect_at_eof')));
    expect(retries, isNot(contains('4xx')));
    expect(writes.last, [
      'change-list',
      'demuxer-lavf-o',
      'append',
      'http_multiple=1',
    ]);
  });

  test('local files and non-HTTP transports retain their defaults', () async {
    for (final (url, local) in [
      ('E:/Downloads/episode.mp4', true),
      ('http://localhost/offline.m3u8', true),
      ('rtsp://example.com/live', false),
    ]) {
      await PlaybackNetworkPolicy.apply(
        url: url,
        isLocalPlayback: local,
        bufferSize: 32 * 1024 * 1024,
        isCurrent: () => true,
        setProperty: (_, _) async => fail('Unexpected network change'),
        command: (_) async => fail('Unexpected network change'),
      );
    }
  });

  test('disposing a player interrupts pending network configuration', () async {
    var current = true;
    await PlaybackNetworkPolicy.apply(
      url: 'https://example.com/index.m3u8',
      isLocalPlayback: false,
      bufferSize: 32 * 1024 * 1024,
      isCurrent: () => current,
      setProperty: (_, _) async => current = false,
      command: (_) async => fail('Configured a disposed player'),
    );
  });

  test('small buffers retain a short buffering target', () async {
    final properties = <String, String>{};
    await PlaybackNetworkPolicy.apply(
      url: 'https://example.com/index.m3u8',
      isLocalPlayback: false,
      bufferSize: 2 * 1024 * 1024,
      isCurrent: () => true,
      setProperty: (key, value) async => properties[key] = value,
      command: (_) async {},
    );
    expect(properties['cache-pause-wait'], '1');
    expect(properties['cache-pause-initial'], 'no');
  });
}
