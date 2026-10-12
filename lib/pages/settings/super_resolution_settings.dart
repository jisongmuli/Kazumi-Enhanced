import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/player/frame_interpolation_sheet.dart';
import 'package:kazumi/services/player/frame_interpolation.dart';
import 'package:kazumi/bean/settings/settings_list.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late bool disableWarning;
  late SuperResolutionMode superResolutionMode;

  @override
  void initState() {
    super.initState();
    disableWarning = GStorage.getSetting<bool>(
      SettingsKeys.disableSuperResolutionWarning,
    );
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultSuperResolutionMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('超分辨率与插帧'),
      body: SettingsList(
        sections: [
          SettingsRadioSection<SuperResolutionMode>(
            title: Text('超分辨率需要启用硬件解码, 若启用硬件解码后仍然不生效, 尝试切换视频渲染器为 gpu'),
            groupValue: superResolutionMode,
            onChanged: (SuperResolutionMode? value) {
              if (value == null) return;
              GStorage.putSetting<int>(
                SettingsKeys.defaultSuperResolutionMode,
                value.storageValue,
              );
              setState(() {
                superResolutionMode = value;
              });
            },
            tiles: [
              for (final mode in SuperResolutionMode.values)
                SettingsTile<SuperResolutionMode>.radioTile(
                  title: Text(mode.label),
                  description: Text(mode.description),
                  radioValue: mode,
                ),
            ],
          ),
          SettingsSection(title: const Text('视频插帧'), tiles: [
            SettingsTile(leading: Icons.slow_motion_video_rounded, title: const Text('默认插帧'),
              description: Text(InterpolationEngine.fromIndex(GStorage.getSetting(SettingsKeys.interpolationEngine)).label),
              onPressed: (_) async {
                final value = await showFrameInterpolationDialog(context, FrameInterpolation(
                  engine: InterpolationEngine.fromIndex(GStorage.getSetting(SettingsKeys.interpolationEngine)),
                  multiplier: GStorage.getSetting(SettingsKeys.interpolationMultiplier),
                  sceneDetection: GStorage.getSetting(SettingsKeys.interpolationSceneDetection),
                  gpu: GStorage.getSetting(SettingsKeys.interpolationGpu),
                  processingHeight: GStorage.getSetting(SettingsKeys.interpolationHeight)));
                if (value == null) return;
                await GStorage.putSetting(SettingsKeys.interpolationEngine, value.engine.index);
                await GStorage.putSetting(SettingsKeys.interpolationMultiplier, value.multiplier);
                await GStorage.putSetting(SettingsKeys.interpolationSceneDetection, value.sceneDetection);
                await GStorage.putSetting(SettingsKeys.interpolationGpu, value.gpu);
                await GStorage.putSetting(SettingsKeys.interpolationHeight, value.processingHeight);
                if (mounted) setState(() {});
              }),
          ]),
          SettingsSection(
            title: Text('默认行为'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.notifications_off_rounded,
                title: Text('关闭提示'),
                description: Text('关闭每次启用超分辨率时的提示'),
                initialValue: disableWarning,
                onToggle: (value) async {
                  disableWarning = value ?? !disableWarning;
                  await GStorage.putSetting<bool>(
                    SettingsKeys.disableSuperResolutionWarning,
                    disableWarning,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
