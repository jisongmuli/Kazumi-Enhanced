import 'dart:io';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/danmaku_endpoint.dart';
import 'package:kazumi/services/danmaku/local_danmaku_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';

class DanmakuClient {
  DanmakuClient._();
  static final instance = DanmakuClient._();
  final Dio _localDio =
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)))
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
        );
  String get appId =>
      GStorage.getSetting(SettingsKeys.dandanAppId).trim().isEmpty
      ? dandanCredentials['id']!
      : GStorage.getSetting(SettingsKeys.dandanAppId).trim();
  String get appSecret =>
      GStorage.getSetting(SettingsKeys.dandanAppSecret).trim().isEmpty
      ? dandanCredentials['value']!
      : GStorage.getSetting(SettingsKeys.dandanAppSecret).trim();
  Future<Uri> endpoint() async {
    final configured = GStorage.getSetting(SettingsKeys.danmakuEndpoint).trim();
    if (configured.isNotEmpty) return DanmakuEndpoint.parse(configured);
    if (appId.isNotEmpty || appSecret.isNotEmpty)
      return Uri.https(DanmakuEndpoint.officialHost);
    return LocalDanmakuService.instance.endpoint();
  }

  Future<bool> get usesOfficial async =>
      (await endpoint()).host == DanmakuEndpoint.officialHost;
  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final target = DanmakuEndpoint.route(Uri.parse(url), await endpoint());
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      ...DanmakuEndpoint.signatureHeaders(target, appId, appSecret, timestamp),
      ...headers,
    };
    try {
      final local =
          target.host == '127.0.0.1' ||
          target.host == '::1' ||
          target.host == 'localhost';
      final response = await (local ? _localDio : DioFactory.apiDio).get(
        target.toString(),
        queryParameters: queryParameters,
        options: Options(
          headers: requestHeaders,
          receiveTimeout: const Duration(seconds: 60),
        ),
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>)
        throw StateError('弹幕接口返回了无效数据，请检查接口地址');
      if (data['success'] == false)
        throw StateError('弹幕接口：${data['errorMessage'] ?? '请求失败'}');
      return data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw StateError('弹幕接口认证失败，请在弹幕设置中检查凭据或接口地址');
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
