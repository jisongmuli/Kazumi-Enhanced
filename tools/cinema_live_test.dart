import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/cinema/cinema_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('parse actual source pages and fetch actual episode lists', () async {
    HttpOverrides.global = null;
    final proxy = Uri.parse(Platform.environment['HTTPS_PROXY']!);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()
            ..findProxy = (uri) => 'PROXY ${proxy.host}:${proxy.port}',
    );
    final service = CinemaService(dio: dio);
    final directory = Platform.environment['KAZUMI_VERIFY_DIR']!;
    final sources = await service.sources();
    expect(sources.length, greaterThanOrEqualTo(45));
    final reports = <Map<String, dynamic>>[];
    final mediaInputs = <Map<String, dynamic>>[];
    final selected = Platform.environment['KAZUMI_CINEMA_SOURCES']?.split(',');
    for (final source in sources) {
      if (selected != null && !selected.contains(source.id)) continue;
      final report = <String, dynamic>{
        'id': source.id,
        'name': source.name,
        'posters': 0,
      };
      try {
        final listing = await service.listing(source);
        report['posters'] = listing.films.length;
        if (listing.films.isEmpty) continue;
        final detail = await service.detail(listing.films.first);
        report['roads'] = detail.roads.length;
        report['episodes'] = detail.roads.fold<int>(
          0,
          (n, road) => n + road.data.length,
        );
        report['film'] = listing.films.first.title;
        report['url'] = listing.films.first.url;
        try {
          final search = await service.listing(source, keyword: '凡人');
          report['searchResults'] = search.films.length;
        } catch (error) {
          report['searchError'] = error.toString();
        }
        if (detail.roads.isNotEmpty) {
          try {
            final media = await service.resolveEpisode(
              detail.roads.first.data.first,
            );
            report['directMedia'] = media != null;
            if (media != null)
              mediaInputs.add({
                'source': source.name,
                'url': media.url,
                'headers': media.httpHeaders,
              });
          } catch (error) {
            report['mediaError'] = error.toString();
          }
        }
      } catch (error) {
        report['error'] = error.toString();
      }
      reports.add(report);
      // This developer probe is explicitly invoked, separate from offline CI.
      print(jsonEncode(report));
    }
    final suffix = selected == null ? '' : '-search';
    await File(
      '$directory/cinema-live$suffix-results.json',
    ).writeAsString(jsonEncode(reports));
    if (selected == null) {
      await File(
        '$directory/cinema-native-input.json',
      ).writeAsString(jsonEncode(mediaInputs));
    }
    final fdz = reports
        .where((report) => report['id'] == 'guozhi7')
        .firstOrNull;
    if (fdz != null) expect(fdz['searchResults'], greaterThan(0));
    expect(
      reports.where((report) => report['posters'] > 10).length,
      greaterThanOrEqualTo(selected == null ? 6 : selected.length),
    );
    expect(
      reports.where((report) => (report['roads'] as int? ?? 0) > 0).length,
      greaterThanOrEqualTo(selected == null ? 6 : selected.length),
    );
    dio.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
