import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/frame_interpolation.dart';
import 'package:kazumi/services/player/interpolation_runtime.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/pages/player/frame_interpolation_sheet.dart';

void main() {
  testWidgets(
    'closing remains available when the custom multiplier is invalid',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 846));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FrameInterpolation? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showFrameInterpolationDialog(
                    context,
                    const FrameInterpolation(
                      engine: InterpolationEngine.rife,
                      gpu: 7,
                      processingHeight: 540,
                    ),
                  );
                },
                child: const Text('插帧设置'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('插帧设置'));
      await tester.pumpAndSettle();
      expect(find.text('启用插帧'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'NaN');
      await tester.tap(find.text('关闭插帧'));
      await tester.pumpAndSettle();
      expect(result?.engine, InterpolationEngine.off);
      expect(find.text('视频插帧'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'closing interpolation preserves unrelated filters and verifies removal',
    () async {
      var filters = '@sub:sub,@kazumi-interpolation:vapoursynth=file=x';
      await InterpolationRuntime.remove(
        get: (_) async => filters,
        command: (args) async {
          expect(args, ['vf', 'remove', '@kazumi-interpolation']);
          filters = '@sub:sub';
        },
      );
      expect(filters, '@sub:sub');
      await expectLater(
        InterpolationRuntime.remove(
          get: (_) async => '@kazumi-interpolation:bad',
          command: (_) async {},
        ),
        throwsStateError,
      );
    },
  );

  test('a filter label with unchanged FPS is not reported as enabled', () {
    fakeAsync((time) {
      Object? failure;
      var filters = '';
      InterpolationRuntime.apply(
        settings: const FrameInterpolation(engine: InterpolationEngine.rife),
        scriptPath: 'x',
        get: (name) async => switch (name) {
          'container-fps' || 'estimated-vf-fps' => '25',
          'vf' => filters,
          _ => 'no',
        },
        set: (_, _) async {},
        command: (args) async {
          filters = args[1] == 'add' ? '@kazumi-interpolation:bad' : '';
        },
        isCurrent: () => true,
        hardwareEnabled: true,
      ).catchError((Object error) {
        failure = error;
        return null;
      });
      time.flushMicrotasks();
      expect(failure, isNull);
      time.elapse(const Duration(seconds: 11));
      time.flushMicrotasks();
      expect(failure, isA<StateError>());
    });
  });

  test(
    'optical flow uses selected processing resolution and restores output size',
    () {
      final graph = const FrameInterpolation(
        engine: InterpolationEngine.opticalFlow,
        processingHeight: 540,
      ).filter('', sourceFps: 25, sourceWidth: 1920, sourceHeight: 1080);
      expect(graph, contains('scale=960:540,minterpolate'));
      expect(graph, contains('scale=1920:1080'));
      expect(InterpolationRuntime.reachesTarget(25, 50, 2), isTrue);
      expect(InterpolationRuntime.reachesTarget(25, 25, 2), isFalse);
    },
  );

  test('cancelled activation does not attach a stale filter', () async {
    var current = true;
    final commands = <List<String>>[];
    final status = await InterpolationRuntime.apply(
      settings: const FrameInterpolation(engine: InterpolationEngine.rife),
      scriptPath: 'x',
      get: (name) async {
        if (name == 'container-fps') current = false;
        return name == 'vf' ? '' : '25';
      },
      set: (_, _) async {},
      command: (args) async => commands.add(args),
      isCurrent: () => current,
      hardwareEnabled: true,
    );
    expect(status, isNull);
    expect(commands, isEmpty);
  });
  test('custom multipliers reject NaN, infinity, and invalid limits', () {
    for (final value in [double.nan, double.infinity, -1.0, 0.0, 1.0, 8.01]) {
      expect(FrameInterpolation.validMultiplier(value), isFalse);
    }
    for (final value in [1.01, 2.0, 2.4, 8.0]) {
      expect(FrameInterpolation.validMultiplier(value), isTrue);
    }
  });
  test(
    'Windows drive colons, Unicode and filter punctuation are byte escaped',
    () {
      const file = r'E:\我的视频\test:filter,[].vpy';
      final value = const FrameInterpolation(engine: InterpolationEngine.rife);
      expect(
        value.filter(file),
        contains('file=%${utf8.encode(file).length}%$file:'),
      );
      expect(value.filter(file), startsWith('@kazumi-interpolation:'));
    },
  );
  test(
    'RIFE rational multiplier changes FPS without changing playback speed',
    () {
      final script = const FrameInterpolation(
        engine: InterpolationEngine.rifeLarge,
        multiplier: 2.4,
      ).script(r'E:\x\rife.dll');
      expect(script, contains('model=73, factor_num=2400, factor_den=1000'));
      expect(script, contains("f.props['_SceneChangeNext']"));
      expect(script, contains('sc=True'));
      expect(script, isNot(contains('AssumeFPS')));
    },
  );
  test('optical flow requires known FPS and bounds output to 240 FPS', () {
    const value = FrameInterpolation(
      engine: InterpolationEngine.opticalFlow,
      multiplier: 2.4,
    );
    expect(() => value.filter(''), throwsStateError);
    expect(value.filter('', sourceFps: 25), contains('fps=60.0'));
    expect(() => value.filter('', sourceFps: 120), throwsStateError);
  });
  test('unknown stored engine falls back to disabled', () {
    expect(InterpolationEngine.fromIndex(-1), InterpolationEngine.off);
    expect(InterpolationEngine.fromIndex(100), InterpolationEngine.off);
  });
}
