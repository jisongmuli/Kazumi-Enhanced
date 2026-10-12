import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

class BangumiMirrorPolicy {
  BangumiMirrorPolicy._();

  static bool get hasCredentials =>
      bangumiMirrorCredentials['id']!.trim().isNotEmpty &&
      bangumiMirrorCredentials['value']!.trim().isNotEmpty;

  static bool requiresSignature(Uri uri, String method) {
    if (!ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) return false;
    final path = uri.path;
    if (method == 'POST' && path == '/v0/search/subjects') return true;
    if (method != 'GET') return false;
    return path.startsWith('/p1/subjects/') && path.endsWith('/comments') ||
        path.startsWith('/p1/episodes/') && path.endsWith('/comments') ||
        path.startsWith('/p1/characters/') && path.endsWith('/comments');
  }
}
