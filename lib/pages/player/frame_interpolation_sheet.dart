import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/player/interpolation_runtime.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/player/frame_interpolation.dart';
import 'package:kazumi/services/player/video_enhancement_runtime.dart';

Future<FrameInterpolation?> showFrameInterpolationDialog(
  BuildContext context,
  FrameInterpolation initial, {
  ValueListenable<InterpolationStatus>? status,
}) => KazumiDialog.show<FrameInterpolation>(
  context: context,
  builder: (_) => _InterpolationDialog(initial: initial, status: status),
);

class _InterpolationDialog extends StatefulWidget {
  const _InterpolationDialog({required this.initial, this.status});
  final FrameInterpolation initial;
  final ValueListenable<InterpolationStatus>? status;
  @override
  State<_InterpolationDialog> createState() => _InterpolationDialogState();
}

class _InterpolationDialogState extends State<_InterpolationDialog> {
  late FrameInterpolation value = widget.initial.copyWith(
    gpu: widget.initial.gpu >= 0 && widget.initial.gpu < 2
        ? widget.initial.gpu
        : 0,
  );
  late final multiplier = TextEditingController(
    text: value.multiplier.toString(),
  );
  final formKey = GlobalKey<FormState>();
  @override
  void dispose() {
    multiplier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('视频插帧'),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.status != null)
                ValueListenableBuilder<InterpolationStatus>(
                  valueListenable: widget.status!,
                  builder: (context, status, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(status.summary),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用插帧'),
                value: value.engine != InterpolationEngine.off,
                onChanged: (enabled) => setState(
                  () => value = value.copyWith(
                    engine: enabled
                        ? InterpolationEngine.rifeFast
                        : InterpolationEngine.off,
                  ),
                ),
              ),
              DropdownButtonFormField<InterpolationEngine>(
                isExpanded: true,
                initialValue: value.engine,
                decoration: const InputDecoration(labelText: '插帧算法'),
                items: [
                  for (final engine in InterpolationEngine.values)
                    DropdownMenuItem(
                      value: engine,
                      enabled:
                          !engine.isAi || VideoEnhancementRuntime.available,
                      child: Text(engine.label),
                    ),
                ],
                onChanged: (engine) {
                  if (engine != null)
                    setState(() => value = value.copyWith(engine: engine));
                },
              ),
              const SizedBox(height: 12),
              Text(value.engine.description),
              if (value.engine != InterpolationEngine.off) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final factor in [2.0, 3.0, 4.0, 8.0])
                      ChoiceChip(
                        label: Text('${factor.toInt()}×'),
                        selected: double.tryParse(multiplier.text) == factor,
                        onSelected: (_) =>
                            setState(() => multiplier.text = '$factor'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: multiplier,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '自定义倍数',
                    helperText: '1.01–8，支持小数，例如 2.4×：25 → 60 FPS',
                  ),
                  validator: (text) {
                    final number = double.tryParse(text?.trim() ?? '');
                    return number != null &&
                            FrameInterpolation.validMultiplier(number)
                        ? null
                        : '请输入 1.01–8 之间的有限数值';
                  },
                  onChanged: (_) => setState(() {}),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('场景切换保护'),
                  subtitle: const Text('切镜头时避免生成跨场景过渡帧'),
                  value: value.sceneDetection,
                  onChanged: (enabled) => setState(
                    () => value = value.copyWith(sceneDetection: enabled),
                  ),
                ),
                ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: value.processingHeight,
                    decoration: const InputDecoration(labelText: '插帧处理分辨率'),
                    items: const [
                      DropdownMenuItem(value: 540, child: Text('540p（优先流畅）')),
                      DropdownMenuItem(value: 720, child: Text('720p（默认）')),
                      DropdownMenuItem(value: 1080, child: Text('1080p（更多细节）')),
                      DropdownMenuItem(value: 0, child: Text('原始分辨率（最高开销）')),
                    ],
                    onChanged: (height) {
                      if (height != null)
                        setState(
                          () =>
                              value = value.copyWith(processingHeight: height),
                        );
                    },
                  ),
                  const Text('较低处理分辨率会减少细节，再恢复到原视频尺寸输出。'),
                  const SizedBox(height: 12),
                  if (value.engine.isAi)
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: value.gpu,
                      decoration: const InputDecoration(labelText: 'Vulkan 显卡'),
                      items: [
                        for (var gpu = 0; gpu < 2; gpu++)
                          DropdownMenuItem(
                            value: gpu,
                            child: Text(gpu == 0 ? 'GPU 0（默认）' : 'GPU $gpu'),
                          ),
                      ],
                      onChanged: (gpu) {
                        if (gpu != null)
                          setState(() => value = value.copyWith(gpu: gpu));
                      },
                    ),
                ],
                const SizedBox(height: 12),
                const Text('插帧会增加显卡或 CPU 占用。卡顿时先降低倍数或切换 Lite；流畅度还受显示器刷新率影响。'),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => KazumiDialog.dismiss(
          context: context,
          popWith: value.copyWith(engine: InterpolationEngine.off),
        ),
        child: const Text('关闭插帧'),
      ),
      TextButton(
        onPressed: () => KazumiDialog.dismiss(context: context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          final factor = value.engine == InterpolationEngine.off
              ? value.multiplier
              : double.parse(multiplier.text.trim());
          KazumiDialog.dismiss(
            context: context,
            popWith: value.copyWith(multiplier: factor),
          );
        },
        child: const Text('应用'),
      ),
    ],
  );
}
