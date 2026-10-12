import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:logger/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh installations include sixteen anime rules without replacing existing sources',
    () async {
      Logger.level = Level.off;
      final existing = Plugin.fromTemplate()
        ..name = 'MXdm'
        ..baseUrl = 'https://my-source.example/';
      final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..newPluginDirectory = Directory('unused-rule-directory')
        ..pluginList.add(existing);
      for (final source in await CinemaService.instance.sources()) {
        controller.pluginList.add(CinemaService.plugin(source));
      }
      await controller.copyPluginsToExternalDirectory();
      expect(controller.pluginList.where((p) => p.type == 'anime').length, 16);
      expect(controller.pluginList.where((p) => p.isCinema).length, 45);
      expect(
        controller.pluginList.firstWhere((p) => p.name == 'MXdm'),
        same(existing),
      );
      expect(existing.baseUrl, 'https://my-source.example/');
      final count = controller.pluginList.length;
      await controller.copyPluginsToExternalDirectory();
      expect(controller.pluginList.length, count);
      expect(
        controller.pluginList.map((p) => p.name.toLowerCase()).toSet().length,
        count,
      );
    },
  );
}
