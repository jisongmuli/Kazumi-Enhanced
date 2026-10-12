import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/frame_interpolation.dart';
import 'package:kazumi/services/player/video_enhancement_runtime.dart';
import 'package:kazumi/services/player/interpolation_runtime.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('live media-kit runtime interpolation and removal', () async {
    final runtime = Directory(Platform.environment['KAZUMI_ENGINE_DIR']!);
    final verify = Directory(Platform.environment['KAZUMI_VERIFY_DIR']!);
    MediaKit.ensureInitialized(
      libmpv: VideoEnhancementRuntime.initialize(runtimeDirectory: runtime),
    );
    final reports = <Map<String, dynamic>>[];
    for (final engine in [
      InterpolationEngine.rifeFast,
      InterpolationEngine.rifeLite,
      InterpolationEngine.rife,
      InterpolationEngine.rifeLarge,
      InterpolationEngine.opticalFlow,
    ]) {
      final player = Player(
        configuration: const PlayerConfiguration(
          vo: 'null',
          osc: false,
          logLevel: MPVLogLevel.debug,
        ),
      );
      final native = player.platform as NativePlayer;
      await native.setProperty('ao', 'null');
      await native.setProperty('vid', 'auto');
      await native.setProperty('demuxer-cache-dir', verify.path);
      await native.setProperty('cache-on-disk', 'no');
      await native.setProperty('loop-file', 'inf');
      await native.setProperty('demuxer-lavf-o', '');
      final logs = <String>[];
      final sub = player.stream.log.listen((event) {
        if (event.level == 'error' || event.level == 'fatal')
          logs.add(event.toString());
      });
      final setting = FrameInterpolation(
        engine: engine,
        multiplier: 2,
        processingHeight: 540,
      );
      final script = File('${verify.path}/${engine.name}-dynamic.vpy');
      if (engine.isAi)
        await script.writeAsString(
          setting.script('${runtime.path}/plugins/librife.dll'),
        );
      try {
        await player.open(Media('${verify.path}/interpolation-1080p.mp4'));
        await Future<void>.delayed(const Duration(seconds: 1));
        await InterpolationRuntime.apply(
          settings: setting,
          scriptPath: script.path,
          get: native.getProperty,
          set: native.setProperty,
          command: native.command,
          isCurrent: () => true,
          hardwareEnabled: true,
        );
        await Future<void>.delayed(const Duration(seconds: 4));
        final report = <String, dynamic>{
          'engine': engine.name,
          'fps': await native.getProperty('estimated-vf-fps'),
          'sourceFps': await native.getProperty('container-fps'),
          'filter': await native.getProperty('vf'),
          'enabled': await native.getProperty('vf/0/enabled'),
          'drops': await native.getProperty('frame-drop-count'),
          'errors': logs.toList(),
        };
        await InterpolationRuntime.remove(
          get: native.getProperty,
          command: native.command,
        );
        await native.setProperty('hwdec', 'auto');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        report['afterOffFilter'] = await native.getProperty('vf');
        report['afterOffFps'] = await native.getProperty('estimated-vf-fps');
        reports.add(report);
        print(jsonEncode(report));
      } finally {
        await sub.cancel();
        await player.dispose();
        if (await script.exists()) await script.delete();
      }
    }
    await File(
      '${verify.path}/interpolation-dart-results.json',
    ).writeAsString(jsonEncode(reports));
    expect(
      reports.every(
        (r) => InterpolationRuntime.reachesTarget(
          25,
          double.tryParse(r['fps']) ?? 0,
          2,
        ),
      ),
      isTrue,
    );
    expect(
      reports.every(
        (r) =>
            !(r['afterOffFilter'] as String).contains('kazumi-interpolation'),
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
