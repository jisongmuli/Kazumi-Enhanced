import 'package:kazumi/utils/crypto.dart';

class DanmakuEndpoint {
  static const officialHost = 'api.dandanplay.net';

  static Uri parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('请输入 HTTP(S) 接口根地址，不含查询参数');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  static Uri route(Uri original, Uri endpoint) => endpoint.replace(
    path: '${endpoint.path}${original.path}',
    query: original.query,
  );

  static Map<String, String> signatureHeaders(
    Uri target,
    String id,
    String secret,
    int timestamp,
  ) {
    // Never send official credentials to a third-party compatibility endpoint.
    if (target.scheme != 'https' ||
        target.host != officialHost ||
        (target.hasPort && target.port != 443))
      return {};
    if (id.trim().isEmpty || secret.trim().isEmpty) {
      throw StateError('弹弹play未配置 AppId / AppSecret，请在弹幕设置中选择本机多源或配置凭据');
    }
    return {
      'X-Auth': '1',
      'X-AppId': id,
      'X-Timestamp': '$timestamp',
      'X-Signature': generateDandanSignature(
        target.path,
        timestamp,
        appId: id,
        appSecret: secret,
      ),
    };
  }
}
