import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/bangumi_transport.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';

void main() {
  late Dio dio;
  late _RecordingAdapter adapter;

  void configure(BangumiAcceleration mode, {bool credentials = false}) {
    dio.interceptors.add(
      BangumiAccelerationInterceptor(
        acceleration: mode,
        hasMirrorCredentials: credentials,
      ),
    );
  }

  setUp(() {
    dio = Dio();
    adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() => dio.close(force: true));

  test(
    'source build searches upstream with body, filters and pagination',
    () async {
      configure(BangumiAcceleration.mirror);
      final data = {
        'keyword': '葬送的芙莉莲',
        'sort': 'heat',
        'filter': {
          'type': [2],
          'tag': ['漫画改'],
          'rank': ['>=0', '<=99999'],
          'nsfw': false,
        },
      };
      final response = await dio.post(
        'https://api.bgm.tv/v0/search/subjects?limit=20',
        queryParameters: {'offset': 20},
        data: data,
      );
      expect(
        adapter.request.uri,
        Uri.parse('https://api.bgm.tv/v0/search/subjects?limit=20&offset=20'),
      );
      expect(jsonDecode(adapter.body), data);
      expect(adapter.request.extra['bangumiEch'], isTrue);
      expect(response.data['data'].single['name_cn'], '葬送的芙莉莲');
    },
  );

  test('configured release keeps protected search on the mirror', () async {
    configure(BangumiAcceleration.mirror, credentials: true);
    await dio.post('https://api.bgm.tv/v0/search/subjects?limit=20&offset=0');
    expect(
      adapter.request.uri,
      Uri.parse('https://api.kazumi.fyi/v0/search/subjects?limit=20&offset=0'),
    );
  });

  test('source build keeps unsigned metadata requests on the mirror', () async {
    configure(BangumiAcceleration.mirror);
    await dio.get('https://next.bgm.tv/p1/subjects/400602');
    expect(
      adapter.request.uri,
      Uri.parse('https://api.kazumi.fyi/p1/subjects/400602'),
    );
  });

  test(
    'source build also uses upstream for protected comment requests',
    () async {
      configure(BangumiAcceleration.mirror);
      for (final kind in ['subjects', 'episodes', 'characters']) {
        final url = 'https://next.bgm.tv/p1/$kind/400602/comments?limit=20';
        await dio.get(url);
        expect(adapter.request.uri, Uri.parse(url));
        expect(adapter.request.extra['bangumiEch'], isTrue);
      }
    },
  );

  test('direct and ECH searches retain their selected transport', () async {
    const url = 'https://api.bgm.tv/v0/search/subjects?limit=20&offset=0';
    for (final mode in [BangumiAcceleration.direct, BangumiAcceleration.ech]) {
      dio.interceptors.clear();
      configure(mode);
      await dio.post(url);
      expect(adapter.request.uri, Uri.parse(url));
      expect(
        adapter.request.extra['bangumiEch'],
        mode == BangumiAcceleration.ech ? isTrue : isNull,
      );
    }
  });

  test(
    'mirror selection leaves account API and other hosts unchanged',
    () async {
      configure(BangumiAcceleration.mirror);
      for (final url in [
        'https://api.bgmapi.com/v0/me',
        'https://example.com/v0/search/subjects',
      ]) {
        await dio.post(url);
        expect(adapter.request.uri, Uri.parse(url));
      }
    },
  );

  test(
    'metadata fallback only retries unsupported or unavailable public mirror GETs',
    () {
      final options = RequestOptions(
        path: 'https://api.kazumi.fyi/p1/subjects/400602',
      );
      DioException failure(DioExceptionType type, [int? status]) =>
          DioException(
            requestOptions: options,
            type: type,
            response: status == null
                ? null
                : Response(requestOptions: options, statusCode: status),
          );
      const original = 'https://next.bgm.tv/p1/subjects/400602';
      expect(
        BangumiClient.canRetryMirrorMetadata(
          original,
          failure(DioExceptionType.badResponse, 404),
        ),
        isTrue,
      );
      expect(
        BangumiClient.canRetryMirrorMetadata(
          original,
          failure(DioExceptionType.connectionTimeout),
        ),
        isTrue,
      );
      for (final status in [400, 401, 403, 429]) {
        expect(
          BangumiClient.canRetryMirrorMetadata(
            original,
            failure(DioExceptionType.badResponse, status),
          ),
          isFalse,
        );
      }
      expect(
        BangumiClient.canRetryMirrorMetadata(
          original,
          failure(DioExceptionType.cancel),
        ),
        isFalse,
      );
      expect(
        BangumiClient.canRetryMirrorMetadata(
          original,
          failure(DioExceptionType.badCertificate),
        ),
        isFalse,
      );
      expect(
        BangumiClient.canRetryMirrorMetadata(
          'https://api.bgmapi.com/v0/me',
          failure(DioExceptionType.connectionTimeout),
        ),
        isFalse,
      );
      options.method = 'POST';
      expect(
        BangumiClient.canRetryMirrorMetadata(
          original,
          failure(DioExceptionType.connectionTimeout),
        ),
        isFalse,
      );
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  late RequestOptions request;
  String body = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    body = requestStream == null
        ? ''
        : await utf8.decoder.bind(requestStream).join();
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {'id': 400602, 'name_cn': '葬送的芙莉莲'},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
