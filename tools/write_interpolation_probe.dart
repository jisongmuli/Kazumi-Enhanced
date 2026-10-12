import 'dart:io';
import 'dart:convert';
import 'package:kazumi/services/player/frame_interpolation.dart';
void main() {
  final root = Directory(r'E:/KazumiTools/verification');
  for (final engine in [InterpolationEngine.rifeLite, InterpolationEngine.rife, InterpolationEngine.rifeLarge]) {
    final settings = FrameInterpolation(engine: engine, multiplier: 2.4);
    final script = File('${root.path}/${engine.name}-probe.vpy');
    script.writeAsStringSync(settings.script(r'E:/Kazumi/windows/video_engine/plugins/librife.dll'));
    File('${root.path}/${engine.name}-probe.json').writeAsStringSync(jsonEncode({'vf':settings.filter(script.path)}));
  }
}
