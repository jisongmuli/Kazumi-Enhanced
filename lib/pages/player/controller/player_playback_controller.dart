import 'dart:async';
// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/player/interpolation_runtime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/player/frame_interpolation.dart';
import 'package:kazumi/services/player/video_enhancement_runtime.dart';
import 'dart:typed_data';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';
import 'package:kazumi/services/player/playback_network_policy.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';

part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player);

  final Player player;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'PlayerPlaybackController: failed to dispose media player',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await player.stop();
      } catch (_) {}
    }
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
    required this.isLocalPlayback,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;
  final bool Function() isLocalPlayback;
  late final PlaybackCachePolicy cachePolicy = PlaybackCachePolicy(
    isLocalPlayback: isLocalPlayback,
    currentPlayer: () => mediaPlayer,
  );

  _OwnedPlayer? _ownedPlayer;
  Player? get mediaPlayer => _ownedPlayer?.player;
  VideoController? videoController;

  final AsyncSerialQueue _prefetchWrites = AsyncSerialQueue();
  bool _prefetchSuspendWanted = false;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool autoPlay = true;
  bool playerDebugMode = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  /// 历史记录传入的 offset
  int startOffset = 0;

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;
  @observable
  FrameInterpolation interpolation = const FrameInterpolation();
  @observable
  bool interpolationBusy = false;
  final AsyncSerialQueue _interpolationQueue = AsyncSerialQueue();
  File? _interpolationScript;
  StreamSubscription<PlayerLog>? _interpolationErrors;
  final interpolationStatus = ValueNotifier(const InterpolationStatus());
  Timer? _interpolationMonitor;
  int _interpolationRequest = 0;
  int _lastInterpolationDrops = 0;
  bool _checkingInterpolation = false;

  FrameInterpolation _storedInterpolation() => FrameInterpolation(
    engine: InterpolationEngine.fromIndex(
      GStorage.getSetting(SettingsKeys.interpolationEngine),
    ),
    multiplier: GStorage.getSetting(SettingsKeys.interpolationMultiplier),
    sceneDetection: GStorage.getSetting(
      SettingsKeys.interpolationSceneDetection,
    ),
    gpu: GStorage.getSetting(SettingsKeys.interpolationGpu),
    processingHeight: GStorage.getSetting(SettingsKeys.interpolationHeight),
  );

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {}
  }

  @action
  void resetForInit() {
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    startOffset = 0;
  }

  /// 本次会话是否从距结尾 [nearEndWatchedThreshold] 以内的位置起播。
  /// 这样的"播放完成"并非真正看完，应从头重播而非切下一集
  bool get resumedNearEnd {
    if (startOffset <= 0 || duration <= Duration.zero) {
      return false;
    }
    return Duration(seconds: startOffset) >= duration - nearEndWatchedThreshold;
  }

  /// 从头重播当前视频。[startOffset] 在重播落地后才归零，
  /// 避免自动连播在此期间抢先触发
  Future<void> restartFromBeginning() async {
    final player = mediaPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (!isCurrentPlayer(player)) {
        return;
      }
      await player.play();
      startOffset = 0;
    } catch (e) {
      KazumiLogger().w(
        'PlayerController: failed to restart from beginning',
        error: e,
      );
    }
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  /// Android blocks network access for backgrounded apps; a prefetching
  /// demuxer then burns through ffmpeg's reconnect/segment retries and marks
  /// the stream EOF, leaving playback permanently stuck once foregrounded.
  /// Suspending zeroes the readahead window so no new requests are issued
  /// while buffered data stays available; restore values are mpv defaults,
  /// which media_kit leaves untouched. Writes are serialized and apply the
  /// latest requested state, so rapid lifecycle flips cannot reorder.
  Future<void> setPrefetchSuspended(bool suspended) async {
    if (!Platform.isAndroid) {
      return;
    }
    _prefetchSuspendWanted = suspended;
    await _prefetchWrites.run(() async {
      final wanted = _prefetchSuspendWanted;
      final player = mediaPlayer;
      if (player == null) {
        return;
      }
      try {
        final pp = player.platform as NativePlayer;
        await pp.setProperty('cache-secs', wanted ? '0' : '36000');
        if (!isCurrentPlayer(player)) {
          return;
        }
        await pp.setProperty('demuxer-readahead-secs', wanted ? '0' : '1');
      } catch (e) {
        KazumiLogger().w(
          'PlayerController: failed to ${wanted ? 'suspend' : 'resume'} demuxer prefetch',
          error: e,
        );
      }
    });
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders,
    bool adBlockerEnabled, {
    required bool Function() canInstall,
    int offset = 0,
    VideoSourceFormat videoSourceFormat = VideoSourceFormat.auto,
    String? externalAudioUrl,
    bool? autoPlayOverride,
  }) async {
    startOffset = offset;
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    interpolation = const FrameInterpolation();
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES = GStorage.getSetting(
      SettingsKeys.androidEnableOpenSLES,
    );
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = autoPlayOverride ?? GStorage.getSetting(SettingsKeys.autoPlay);
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: cachePolicy.bufferSize,
          osc: false,
          logLevel: MPVLogLevel.values[debug.playerLogLevel],
          adBlocker: adBlockerEnabled,
        ),
      ),
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;
    cachePolicy.startWatching();

    try {
      await _interpolationErrors?.cancel();
      _interpolationErrors = player.stream.log.listen((event) {
        if (isCurrentPlayer(player) &&
            event.text.contains('Disabling filter') &&
            (event.text.contains('kazumi-interpolation') ||
                event.text.contains('vapoursynth') ||
                event.text.contains('lavfi'))) {
          unawaited(
            disableInterpolation(reason: event.text.trim())
                .then((_) {
                  KazumiDialog.showToast(
                    message: '插帧运行失败，已关闭。请查看插帧状态或降低处理分辨率。',
                  );
                })
                .catchError((Object error) {
                  KazumiLogger().w(
                    'Failed to disable interpolation after filter error',
                    error: error,
                  );
                }),
          );
        }
      });
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      var pp = player.platform as NativePlayer;
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await cachePolicy.apply();
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (VideoEnhancementRuntime.available) {
        await pp.command([
          'change-list',
          'demuxer-lavf-o',
          'remove',
          'hls_ad_filter=${adBlockerEnabled ? 1 : 0}',
        ]);
      }
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles");
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      await PlaybackNetworkPolicy.apply(
        url: videoUrl(),
        isLocalPlayback: isLocalPlayback(),
        bufferSize: cachePolicy.bufferSize,
        isCurrent: () => isCurrentPlayer(player),
        setProperty: (name, value) => pp.setProperty(name, value),
        command: (args) => pp.command(args),
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
      if (proxyEnable) {
        final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
        final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
        if (formattedProxy != null) {
          await pp.setProperty("http-proxy", formattedProxy);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
        }
      } else if (SystemProxyService.isActive) {
        final uri = Uri.tryParse(videoUrl());
        final proxy = uri == null
            ? 'DIRECT'
            : SystemProxyService.findProxy(uri);
        if (proxy.startsWith('PROXY ')) {
          final proxyUrl = 'http://${proxy.substring(6)}';
          await pp.setProperty("http-proxy", proxyUrl);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: 跟随系统代理 $proxyUrl');
        }
      }

      await player.setAudioTrack(AudioTrack.auto());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer = GStorage.getSetting(
          SettingsKeys.androidVideoRenderer,
        );

        if (androidVideoRenderer == 'auto') {
          // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
          // GPU-NEXT 需要 Vulkan 1.2 支持
          // 避免 Android 13 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
          final int androidSdkVersion =
              await PlatformEnvironmentService.getAndroidSdkVersion();
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          if (androidSdkVersion >= 34) {
            videoRenderer = 'gpu-next';
          } else {
            videoRenderer = 'gpu';
          }
        } else {
          videoRenderer = androidVideoRenderer;
        }
      }

      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          enableAndroidSurfaceProducer: false,
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      player.setPlaylistMode(PlaylistMode.none);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      bool showPlayerError = GStorage.getSetting(SettingsKeys.showPlayerError);
      player.stream.error.listen((event) {
        if (isCurrentPlayer(player)) {
          final actionableMessage = PlayerErrorMapper.toActionableMessage(
            event,
            isBuffering: playerBuffering,
          );
          if (actionableMessage != null) {
            KazumiDialog.showToast(
              message: actionableMessage,
              showActionButton: true,
            );
          } else if (showPlayerError) {
            KazumiDialog.showToast(
              message: '播放器内部错误 ${event.toString()} ${videoUrl()}',
              duration: const Duration(seconds: 5),
              showActionButton: true,
            );
          }
        }
        KazumiLogger().e(
          'PlayerController: Player intent error ${videoUrl()}',
          error: event,
        );
      });

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      if (videoSourceFormat == VideoSourceFormat.hls) {
        await pp.setProperty('demuxer-lavf-format', 'hls');
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      await pp.command(['change-list', 'audio-files', 'clr', '']);
      if (externalAudioUrl != null) {
        await pp.command([
          'change-list',
          'audio-files',
          'append',
          externalAudioUrl,
        ]);
      }
      if (!isCurrentPlayer(player))
        return await _discardIfNotCurrent(candidate);
      await player.open(
        Media(
          videoUrl(),
          start: Duration(seconds: offset),
          httpHeaders: httpHeaders,
        ),
        play: autoPlay,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      final wantedInterpolation = _storedInterpolation();
      if (wantedInterpolation.engine != InterpolationEngine.off) {
        try {
          await setInterpolation(
            wantedInterpolation,
            player: player,
            persist: false,
          );
        } catch (error) {
          KazumiDialog.showToast(message: '插帧未启用：$error');
        }
      }
      if (cachePolicy.networkAutomatic) {
        KazumiDialog.showToast(message: '移动数据下已自动开启低内存模式，可在播放设置中改为始终关闭');
      }

      return player;
    } catch (error, stackTrace) {
      if (identical(_ownedPlayer, candidate)) {
        cachePolicy.stopWatching();
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      var pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      switch (mode) {
        case SuperResolutionMode.efficiency:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShadersLite,
            ),
          ]);
          break;
        case SuperResolutionMode.quality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShaders,
            ),
          ]);
          break;
        case SuperResolutionMode.artCnnFast:
        case SuperResolutionMode.artCnnQuality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(shaderAssetService.shadersDirectory.path, [
              mode == SuperResolutionMode.artCnnFast
                  ? 'ArtCNN_C4F16.glsl'
                  : 'ArtCNN_C4F32.glsl',
            ]),
          ]);
          break;
        case SuperResolutionMode.off:
          await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
          break;
      }
      superResolutionMode = mode;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to set shader', error: e);
    }
  }

  Future<void> disableInterpolation({String? reason}) async {
    await setInterpolation(
      interpolation.copyWith(engine: InterpolationEngine.off),
    );
    if (reason != null) {
      interpolationStatus.value = InterpolationStatus(
        phase: InterpolationPhase.failed,
        message: reason,
      );
      KazumiLogger().w('Interpolation disabled: $reason');
    }
  }

  Future<void> setInterpolation(
    FrameInterpolation settings, {
    Player? player,
    bool persist = true,
  }) async {
    final request = ++_interpolationRequest;
    _interpolationMonitor?.cancel();
    interpolationStatus.value = InterpolationStatus(
      phase: settings.engine == InterpolationEngine.off
          ? InterpolationPhase.stopping
          : InterpolationPhase.starting,
    );
    // Persist an explicit stop before any pending activation can finish.
    if (persist && settings.engine == InterpolationEngine.off) {
      await GStorage.putSetting(
        SettingsKeys.interpolationEngine,
        InterpolationEngine.off.index,
      );
    }
    await _interpolationQueue.run(() async {
      final current = player ?? mediaPlayer;
      bool valid() =>
          request == _interpolationRequest &&
          current != null &&
          isCurrentPlayer(current);
      if (!valid()) return;
      final pp = current!.platform as NativePlayer;
      interpolationBusy = true;
      File? script;
      try {
        await pp.waitForPlayerInitialization;
        await pp.waitForVideoControllerInitializationIfAttached;
        if (!valid()) return;
        if (settings.engine == InterpolationEngine.off) {
          await InterpolationRuntime.remove(
            get: pp.getProperty,
            command: pp.command,
          );
          await pp.setProperty('hwdec', hAenable ? hardwareDecoder : 'no');
          interpolationStatus.value = const InterpolationStatus();
        } else {
          if (settings.engine.isAi && !VideoEnhancementRuntime.available) {
            throw StateError('RIFE 运行组件不完整，请检查程序旁的 video_engine 目录');
          }
          if (settings.engine.isAi) {
            final temporary = await getTemporaryDirectory();
            script = File(
              path.join(
                temporary.path,
                'kazumi-rife-${DateTime.now().microsecondsSinceEpoch}.vpy',
              ),
            );
            await script.writeAsString(
              settings.script(
                path.join(
                  VideoEnhancementRuntime.directory.path,
                  'plugins',
                  'librife.dll',
                ),
              ),
            );
          }
          final status = await InterpolationRuntime.apply(
            settings: settings,
            scriptPath: script?.path ?? '',
            get: pp.getProperty,
            set: pp.setProperty,
            command: pp.command,
            isCurrent: valid,
            hardwareEnabled: hAenable,
          );
          if (!valid() || status == null) return;
          interpolationStatus.value = status;
          _lastInterpolationDrops = status.droppedFrames;
        }
        if (!valid()) return;
        final oldScript = _interpolationScript;
        _interpolationScript = script;
        script = null;
        if (oldScript != null && await oldScript.exists())
          await oldScript.delete();
        interpolation = settings;
        if (persist) {
          await GStorage.putSetting(
            SettingsKeys.interpolationEngine,
            settings.engine.index,
          );
          await GStorage.putSetting(
            SettingsKeys.interpolationMultiplier,
            settings.multiplier,
          );
          await GStorage.putSetting(
            SettingsKeys.interpolationSceneDetection,
            settings.sceneDetection,
          );
          await GStorage.putSetting(
            SettingsKeys.interpolationGpu,
            settings.gpu,
          );
          await GStorage.putSetting(
            SettingsKeys.interpolationHeight,
            settings.processingHeight,
          );
        }
        if (settings.engine != InterpolationEngine.off) {
          _interpolationMonitor = Timer.periodic(const Duration(seconds: 1), (
            _,
          ) {
            unawaited(_checkInterpolation(current, request));
          });
        }
        KazumiLogger().i(
          'Interpolation ${settings.engine.name}: ${interpolationStatus.value.summary}',
          forceLog: true,
        );
      } catch (error) {
        if (valid()) {
          await InterpolationRuntime.remove(
            get: pp.getProperty,
            command: pp.command,
          );
          await pp.setProperty('hwdec', hAenable ? hardwareDecoder : 'no');
          interpolation = settings.copyWith(engine: InterpolationEngine.off);
          interpolationStatus.value = InterpolationStatus(
            phase: InterpolationPhase.failed,
            message: error.toString(),
          );
          await GStorage.putSetting(
            SettingsKeys.interpolationEngine,
            InterpolationEngine.off.index,
          );
          KazumiLogger().w('Interpolation activation failed', error: error);
          rethrow;
        }
      } finally {
        if (script != null && await script.exists()) await script.delete();
        interpolationBusy = false;
      }
    });
  }

  Future<void> _checkInterpolation(Player player, int request) async {
    if (_checkingInterpolation ||
        !isCurrentPlayer(player) ||
        request != _interpolationRequest)
      return;
    _checkingInterpolation = true;
    try {
      final pp = player.platform as NativePlayer;
      if (!(await pp.getProperty('vf')).contains(InterpolationRuntime.label)) {
        await disableInterpolation(reason: '播放器已卸载插帧滤镜');
        return;
      }
      final previous = interpolationStatus.value;
      final source =
          double.tryParse(await pp.getProperty('container-fps')) ??
          previous.sourceFps;
      final output =
          double.tryParse(await pp.getProperty('estimated-vf-fps')) ?? 0;
      final drops = int.tryParse(await pp.getProperty('frame-drop-count')) ?? 0;
      final paused = await pp.getProperty('pause') == 'yes';
      if (!isCurrentPlayer(player) || request != _interpolationRequest) return;
      final limited =
          drops - _lastInterpolationDrops >
          source * interpolation.multiplier * .1;
      _lastInterpolationDrops = drops;
      interpolationStatus.value = InterpolationStatus(
        phase: paused
            ? InterpolationPhase.waiting
            : limited ||
                  !InterpolationRuntime.reachesTarget(
                    source,
                    output,
                    interpolation.multiplier,
                  )
            ? InterpolationPhase.limited
            : InterpolationPhase.active,
        sourceFps: source,
        outputFps: output,
        droppedFrames: drops,
      );
    } catch (error) {
      KazumiLogger().w('Interpolation status read failed', error: error);
    } finally {
      _checkingInterpolation = false;
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      KazumiLogger().e(
        'PlayerController: failed to set playback speed',
        error: e,
      );
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {}
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    if (currentPosition != state.position) {
      currentPosition = state.position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    if (completed != state.completed) {
      completed = state.completed;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    ++_interpolationRequest;
    _interpolationMonitor?.cancel();
    _interpolationMonitor = null;
    interpolationStatus.value = const InterpolationStatus();
    interpolation = interpolation.copyWith(engine: InterpolationEngine.off);
    cachePolicy.stopWatching();
    await _interpolationErrors?.cancel();
    _interpolationErrors = null;
    final script = _interpolationScript;
    _interpolationScript = null;
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    await Future.wait([
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]);
    if (script != null && await script.exists()) await script.delete();
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    // Encode the captured frame natively; PlayerState dimensions may be stale.
    return player.safeScreenshot(format: 'image/png');
  }
}
