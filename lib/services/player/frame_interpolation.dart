import 'dart:convert';

enum InterpolationEngine {
  off('关闭', '使用原始视频帧率'),
  rifeLite('RIFE 4.25 Lite', 'AI 插帧，优先实时速度'),
  rife('RIFE 4.26', 'AI 插帧，平衡运动细节和性能'),
  rifeLarge('RIFE 4.26 Large', 'AI 插帧，更高计算开销'),
  opticalFlow('普通光流', 'FFmpeg 运动补偿，使用 CPU'),
  rifeFast('RIFE 4.6 轻量', '较早的轻量模型，较低计算开销');

  const InterpolationEngine(this.label, this.description);
  final String label;
  final String description;
  bool get isAi => this != off && this != opticalFlow;
  int get model => switch (this) {
    rifeLite => 70,
    rife => 72,
    rifeLarge => 73,
    rifeFast => 23,
    _ => throw StateError('不是 RIFE 模型'),
  };
  static InterpolationEngine fromIndex(int index) =>
      index >= 0 && index < values.length ? values[index] : off;
}

class FrameInterpolation {
  const FrameInterpolation({
    this.engine = InterpolationEngine.off,
    this.multiplier = 2,
    this.sceneDetection = true,
    this.gpu = 0,
    this.processingHeight = 720,
  });

  final InterpolationEngine engine;
  final double multiplier;
  final bool sceneDetection;
  final int gpu;
  final int processingHeight;

  static bool validMultiplier(double value) =>
      value.isFinite && value >= 1.01 && value <= 8;

  FrameInterpolation copyWith({
    InterpolationEngine? engine,
    double? multiplier,
    bool? sceneDetection,
    int? gpu,
    int? processingHeight,
  }) => FrameInterpolation(
    engine: engine ?? this.engine,
    multiplier: multiplier ?? this.multiplier,
    sceneDetection: sceneDetection ?? this.sceneDetection,
    gpu: gpu ?? this.gpu,
    processingHeight: processingHeight ?? this.processingHeight,
  );

  String get label => engine == InterpolationEngine.off
      ? '插帧：关闭'
      : '插帧 ${multiplier.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')}×';

  static String quoteMpv(String value) =>
      '%${utf8.encode(value).length}%$value';

  String filter(
    String scriptPath, {
    double? sourceFps,
    int? sourceWidth,
    int? sourceHeight,
  }) {
    if (!validMultiplier(multiplier)) {
      throw ArgumentError('插帧倍数范围为 1.01–8');
    }
    if (engine.isAi) {
      return '@kazumi-interpolation:vapoursynth=file=${quoteMpv(scriptPath)}'
          ':buffered-frames=8:concurrent-frames=2';
    }
    if (engine == InterpolationEngine.opticalFlow) {
      if (sourceFps == null || !sourceFps.isFinite || sourceFps <= 0) {
        throw StateError('尚未取得原始帧率，请在视频开始播放后重试');
      }
      final fps = sourceFps * multiplier;
      if (fps > 240) throw StateError('目标帧率超过 240 FPS，请降低倍数');
      var before = '';
      var after = '';
      if (processingHeight > 0 &&
          sourceWidth != null &&
          sourceHeight != null &&
          sourceHeight > processingHeight) {
        final width =
            (sourceWidth * processingHeight / sourceHeight / 2).round() * 2;
        before = 'scale=$width:$processingHeight,';
        after = ',scale=$sourceWidth:$sourceHeight';
      }
      return '@kazumi-interpolation:lavfi=[${before}minterpolate=fps=$fps'
          ':mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1'
          ':scd=${sceneDetection ? 'fdiff' : 'none'}$after]';
    }
    throw StateError('关闭状态无需视频滤镜');
  }

  String script(String pluginPath) {
    if (!engine.isAi ||
        !validMultiplier(multiplier) ||
        gpu < 0 ||
        gpu > 7 ||
        ![0, 540, 720, 1080].contains(processingHeight)) {
      throw ArgumentError('无效的 RIFE 配置');
    }
    // JSON string literals also form safe Python literals for Windows paths.
    final plugin = jsonEncode(pluginPath);
    final numerator = (multiplier * 1000).round();
    return '''import vapoursynth as vs
from vapoursynth import core
core.std.LoadPlugin(path=$plugin)
clip = video_in
fmt = clip.format.id
matrix = 1 if clip.height > 576 else 6
# Preserve colour matrix metadata without requesting frames during script init.
def save_matrix(n, f):
    src = f[0] if isinstance(f, list) else f
    out = src.copy()
    out.props['_KazumiMatrix'] = src.props.get('_Matrix', matrix)
    return out
tagged = core.std.ModifyFrame(clip, clips=[clip], selector=save_matrix)
height = $processingHeight
height = min(height, clip.height) if height else clip.height
width = max(2, round(clip.width * height / clip.height / 2) * 2)
inputs = {m: core.resize.Bicubic(tagged, width=width, height=height,
                                format=vs.RGBS, matrix_in=m) for m in (1, 4, 5, 6, 7, 9, 10)}
def select_input(n, f):
    src = f[0] if isinstance(f, list) else f
    return inputs.get(src.props.get('_KazumiMatrix', matrix), inputs[matrix])
rgb = core.std.FrameEval(core.std.BlankClip(tagged, width=width, height=height, format=vs.RGBS),
                         eval=select_input, prop_src=[tagged])
${sceneDetection ? '''# Detect cuts using adjacent luma differences. RIFE respects these properties.
luma = core.std.ShufflePlanes(clip, planes=0, colorfamily=vs.GRAY)
stats = core.std.PlaneStats(luma, luma[1:] + luma[-1])
def mark_cut(n, f):
    frames = f
    f = frames[0].copy()
    f.props['_SceneChangeNext'] = int(frames[1].props['PlaneStatsDiff'] > 0.15)
    return f
rgb = core.std.ModifyFrame(rgb, clips=[rgb, stats], selector=mark_cut)
''' : ''}rgb = core.rife.RIFE(rgb, model=${engine.model}, factor_num=$numerator, factor_den=1000,
                     gpu_id=$gpu, gpu_thread=2, sc=${sceneDetection ? 'True' : 'False'})
conversions = {m: core.resize.Bicubic(rgb, width=clip.width, height=clip.height,
                                  format=fmt, matrix=m) for m in (1, 4, 5, 6, 7, 9, 10)}
def restore_matrix(n, f):
    src = f[0] if isinstance(f, list) else f
    return conversions.get(src.props.get('_KazumiMatrix', matrix), conversions[matrix])
output = core.std.FrameEval(core.std.BlankClip(rgb, width=clip.width, height=clip.height, format=fmt),
                           eval=restore_matrix, prop_src=[rgb])
output.set_output()
''';
  }
}
