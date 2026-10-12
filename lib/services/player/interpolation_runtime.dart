import 'package:kazumi/services/player/frame_interpolation.dart';

enum InterpolationPhase {
  off,
  starting,
  waiting,
  active,
  limited,
  failed,
  stopping,
}

class InterpolationStatus {
  const InterpolationStatus({
    this.phase = InterpolationPhase.off,
    this.sourceFps = 0,
    this.outputFps = 0,
    this.droppedFrames = 0,
    this.message = '',
  });
  final InterpolationPhase phase;
  final double sourceFps;
  final double outputFps;
  final int droppedFrames;
  final String message;
  String get summary => switch (phase) {
    InterpolationPhase.off => '插帧已关闭，使用原始帧率',
    InterpolationPhase.starting => '正在启用插帧…',
    InterpolationPhase.stopping => '正在关闭插帧…',
    InterpolationPhase.waiting => '滤镜已加载，播放后检测实际帧率',
    InterpolationPhase.failed => '插帧未生效：$message',
    InterpolationPhase.active || InterpolationPhase.limited =>
      '${sourceFps.toStringAsFixed(1)} → ${outputFps.toStringAsFixed(1)} FPS'
          '${phase == InterpolationPhase.limited ? ' · 输出速度不足，建议降低分辨率或倍数' : ''}'
          ' · 累计丢帧 $droppedFrames',
  };
}

typedef InterpolationProperty = Future<String> Function(String name);

/// Shared by the application and the live native-player probe. A filter label
/// alone is insufficient: mpv can keep a failed filter in the option list.
class InterpolationRuntime {
  static const label = 'kazumi-interpolation';
  static double _fps(String value) {
    final result = double.tryParse(value) ?? 0;
    return result.isFinite && result > 0 ? result : 0;
  }

  static bool reachesTarget(double source, double output, double multiplier) =>
      source > 0 &&
      output > source * 1.005 &&
      (output - source * multiplier).abs() <= source * multiplier * .05;

  static Future<void> remove({
    required InterpolationProperty get,
    required Future<void> Function(List<String>) command,
  }) async {
    if ((await get('vf')).contains(label)) {
      await command(['vf', 'remove', '@$label']);
    }
    if ((await get('vf')).contains(label)) {
      throw StateError('插帧滤镜未能移除，请重新打开视频');
    }
  }

  static Future<InterpolationStatus?> apply({
    required FrameInterpolation settings,
    required String scriptPath,
    required InterpolationProperty get,
    required Future<void> Function(String, String) set,
    required Future<void> Function(List<String>) command,
    required bool Function() isCurrent,
    required bool hardwareEnabled,
  }) async {
    await remove(get: get, command: command);
    if (!isCurrent()) return null;
    double sourceFps = 0;
    for (var i = 0; i < 32 && isCurrent(); i++) {
      sourceFps = _fps(await get('container-fps'));
      if (sourceFps <= 0) sourceFps = _fps(await get('estimated-vf-fps'));
      if (sourceFps > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!isCurrent()) return null;
    if (sourceFps <= 0) throw StateError('尚未解码到视频画面，请播放后重试');
    final width = int.tryParse(await get('video-params/w'));
    final height = int.tryParse(await get('video-params/h'));
    await set('hwdec', hardwareEnabled ? 'auto-copy' : 'no');
    if (!isCurrent()) return null;
    await command([
      'vf',
      'add',
      settings.filter(
        scriptPath,
        sourceFps: sourceFps,
        sourceWidth: width,
        sourceHeight: height,
      ),
    ]);
    for (var i = 0; i < 40 && isCurrent(); i++) {
      if (!(await get('vf')).contains(label)) throw StateError('播放器未加载插帧滤镜');
      final output = _fps(await get('estimated-vf-fps'));
      final drops = int.tryParse(await get('frame-drop-count')) ?? 0;
      if (reachesTarget(sourceFps, output, settings.multiplier)) {
        return InterpolationStatus(
          phase: InterpolationPhase.active,
          sourceFps: sourceFps,
          outputFps: output,
          droppedFrames: drops,
        );
      }
      if (await get('pause') == 'yes' || await get('core-idle') == 'yes') {
        return InterpolationStatus(
          phase: InterpolationPhase.waiting,
          sourceFps: sourceFps,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!isCurrent()) return null;
    throw StateError(
      '实际输出帧率没有达到 ${sourceFps * settings.multiplier} FPS；请降低处理分辨率或更换快速模型',
    );
  }
}
