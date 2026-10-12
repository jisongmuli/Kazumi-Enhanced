import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

class LocalDanmakuService {
  static final instance = LocalDanmakuService();
  Process? _process;
  Future<Uri>? _starting;
  Uri? _endpoint;

  Future<Uri> endpoint() async {
    if (_endpoint != null) return _endpoint!;
    return _starting ??= _start().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }

  Future<Uri> _start() async {
    final directory = path.join(
      path.dirname(Platform.resolvedExecutable),
      'danmaku_engine',
    );
    final node = File(path.join(directory, 'node.exe'));
    final launcher = File(path.join(directory, 'kazumi-launcher.mjs'));
    if (!Platform.isWindows || !node.existsSync() || !launcher.existsSync()) {
      throw StateError(
        Platform.isWindows
            ? '本机弹幕组件未安装，请在弹幕设置中配置兼容接口或弹弹play凭据'
            : '平板需要在线弹幕接口，请在设置中的“弹幕接口”配置兼容接口或官方凭据',
      );
    }
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final token = base64Url.encode(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final process = await Process.start(
      node.path,
      [launcher.path],
      workingDirectory: directory,
      environment: {
        'DANMU_API_PORT': '$port',
        'TOKEN': token,
        'ADMIN_TOKEN': token,
        'SOURCE_ORDER': 'bilibili,tencent,qiyi,youku',
        'PROXY_URL': '',
      },
    );
    _process = process;
    // Drain both streams, without logging endpoint tokens or fetched comments.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
        if (identical(_process, process)) {
          _process = null;
          _endpoint = null;
          _starting = null;
        }
      }),
    );
    try {
      for (var i = 0; i < 40; i++) {
        if (exited) throw StateError('本机弹幕服务启动失败');
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(milliseconds: 200),
          );
          socket.destroy();
          return _endpoint = Uri.parse('http://127.0.0.1:$port/$token');
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      throw StateError('本机弹幕服务启动超时');
    } catch (_) {
      process.kill();
      rethrow;
    }
  }
}
