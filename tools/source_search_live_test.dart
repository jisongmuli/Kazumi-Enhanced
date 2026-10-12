// Explicit network probe, separate from the offline test suite.
// Reads the selected plugin store without changing the user's installation.
import 'dart:convert';
import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/youtube_source_service.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class ProbePaths extends PathProviderPlatform {
  ProbePaths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class ProbeCollect extends Fake implements CollectController {}

class ProbeYoutube extends Fake implements Plugin {
  ProbeYoutube(this.service);
  final YoutubeSourceService service;
  @override
  String get name => 'YouTube';
  @override
  String get type => 'youtube';
  @override
  bool get isCinema => false;
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) => service.search(keyword, cancelToken: cancelToken);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all installed sources search the actual film and read episode lists',
    () async {
      HttpOverrides.global = null;
      Logger.level = Level.off;
      final output = Platform.environment['KAZUMI_VERIFY_DIR']!;
      final store = File(Platform.environment['KAZUMI_PLUGIN_STORE']!);
      final before = await store.readAsString();
      final temporary = await Directory.systemTemp.createTemp(
        'kazumi_sources_probe_',
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = ProbePaths(temporary.path);
      Hive.init(temporary.path);
      await GStorage.init();
      final proxy = Uri.parse(Platform.environment['HTTPS_PROXY']!);
      final dio = DioFactory.pluginDio;
      dio.interceptors.clear();
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () =>
            HttpClient()
              ..findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}',
      );
      final youtube = YoutubeSourceService(
        engineDirectory: Platform.environment['KAZUMI_YOUTUBE_ENGINE']!,
        proxy: () => proxy.toString(),
      );
      final plugins = (jsonDecode(before) as List)
          .map((json) {
            final plugin = Plugin.fromJson(Map<String, dynamic>.from(json));
            return plugin.isYoutube ? ProbeYoutube(youtube) : plugin;
          })
          .cast<Plugin>()
          .toList();
      final info = InfoController(ProbeCollect());
      final search = PluginSearchService(
        infoController: info,
        pluginsController: PluginsController()..pluginList.addAll(plugins),
      );
      addTearDown(() async {
        search.cancel();
        dio.close(force: true);
        await Hive.close();
        PathProviderPlatform.instance = originalPaths;
        expect(
          temporary.absolute.path.startsWith(
            Directory.systemTemp.absolute.path,
          ),
          isTrue,
        );
        expect(
          temporary.uri.pathSegments.where((part) => part.isNotEmpty).last,
          startsWith('kazumi_sources_probe_'),
        );
        await temporary.delete(recursive: true);
      });
      final started = DateTime.now();
      final keyword = Platform.environment['KAZUMI_SEARCH_KEYWORD'] ?? '深海';
      await search.queryAllSource(keyword);
      final reports = <Map<String, dynamic>>[];
      final mediaInputs = <Map<String, dynamic>>[];
      for (final plugin in plugins) {
        final result = info.pluginSearchResponseList
            .where((r) => r.pluginName == plugin.name)
            .firstOrNull;
        final matching = result?.data
            .where((r) => r.name.trim() == keyword)
            .firstOrNull;
        final report = <String, dynamic>{
          'name': plugin.name,
          'type': plugin.type,
          'status': info.pluginSearchStatus[plugin.name]?.name,
          'count': result?.data.length ?? 0,
          'titles': result?.data.take(10).map((r) => r.name).toList() ?? [],
          'exactMatch': matching != null,
          if (info.pluginSearchErrors[plugin.name] != null)
            'error': info.pluginSearchErrors[plugin.name],
        };
        if (matching != null && plugin.isCinema) {
          try {
            final roads = await plugin
                .queryChapterRoads(matching.src)
                .timeout(const Duration(seconds: 25));
            report['episodes'] = roads.fold<int>(
              0,
              (n, r) => n + r.data.length,
            );
            report['roads'] = roads.length;
            if (roads.isNotEmpty && mediaInputs.length < 6) {
              final media = await CinemaService.instance
                  .resolveEpisode(roads.first.data.first)
                  .timeout(const Duration(seconds: 20));
              report['directMedia'] = media != null;
              if (media != null) {
                mediaInputs.add({
                  'source': plugin.name,
                  'url': media.url,
                  'headers': media.httpHeaders,
                });
              }
            }
          } catch (error) {
            report['detailError'] = error.toString();
          }
        }
        reports.add(report);
        // ignore: avoid_print
        print(jsonEncode(report));
      }
      await File('$output/source-search-results.json').writeAsString(
        jsonEncode({
          'keyword': keyword,
          'total': plugins.length,
          'seconds': DateTime.now().difference(started).inSeconds,
          'sources': reports,
        }),
      );
      await File(
        '$output/source-search-media.json',
      ).writeAsString(jsonEncode(mediaInputs));
      expect(
        reports
            .where((r) => r['type'] == 'cinema' && r['exactMatch'] == true)
            .length,
        greaterThanOrEqualTo(4),
      );
      expect(
        reports.where((r) => (r['episodes'] as int? ?? 0) > 0).length,
        greaterThanOrEqualTo(4),
      );
      expect(await store.readAsString(), before);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
