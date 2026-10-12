import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

/// Configures only this process; never changes the user's Python or PATH.
class VideoEnhancementRuntime {
  static Directory get directory => Directory(
    path.join(path.dirname(Platform.resolvedExecutable), 'video_engine'),
  );

  static bool get available =>
      Platform.isWindows &&
      File(path.join(directory.path, 'libmpv-2.dll')).existsSync() &&
      File(path.join(directory.path, 'plugins', 'librife.dll')).existsSync();

  static String? initialize({Directory? runtimeDirectory}) {
    if (runtimeDirectory == null && !available) return null;
    final runtime = runtimeDirectory ?? directory;
    if (!Platform.isWindows ||
        !File(path.join(runtime.path, 'libmpv-2.dll')).existsSync())
      return null;
    final python = path.join(runtime.path, 'python');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final setEnvironment = kernel
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('SetEnvironmentVariableW');
    void set(String name, String value) {
      final key = name.toNativeUtf16();
      final data = value.toNativeUtf16();
      try {
        if (setEnvironment(key, data) == 0) {
          throw StateError('无法配置视频增强运行环境：$name');
        }
      } finally {
        calloc.free(key);
        calloc.free(data);
      }
    }

    set('PYTHONHOME', python);
    set('PATH', '$python;${Platform.environment['PATH'] ?? ''}');
    set(
      'VSSCRIPT_PATH',
      path.join(python, 'Lib', 'site-packages', 'vapoursynth', 'vsscript.dll'),
    );
    return path.join(runtime.path, 'libmpv-2.dll');
  }
}
