import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/portal/portal_models.dart';

/// Bounded, disposable catalog data. No account, history or playback tokens.
class PortalAnimeDiskCache {
  PortalAnimeDiskCache({Future<Directory> Function()? directory})
    : _directory =
          directory ??
          (() async => Directory(
            '${(await getApplicationSupportDirectory()).path}/portal_anime_cache_v1',
          ));
  final Future<Directory> Function() _directory;
  Future<void> _writes = Future.value();

  String _name(String key) =>
      'catalog_${sha256.convert(utf8.encode(key))}.json';

  Future<PortalListing?> read(String key) async {
    try {
      final file = File('${(await _directory()).path}/${_name(key)}');
      if (!await file.exists() || await file.length() > 1024 * 1024)
        return null;
      final data = jsonDecode(await file.readAsString()) as Map;
      final time = DateTime.parse(data['time'] as String);
      final age = DateTime.now().difference(time);
      if (age.isNegative || age.inDays >= 7 || data['key'] != key) return null;
      final items = (data['items'] as List)
          .map(
            (row) => PortalItem.fromAnime(
              BangumiItem.fromJson(Map<String, dynamic>.from(row)),
            ),
          )
          .toList();
      if (items.isEmpty) return null;
      return PortalListing(
        items,
        next: data['next'] as String?,
        cachedAt: time,
      );
    } catch (_) {
      // Damaged or evicted cache files must never stop live loading.
      return null;
    }
  }

  Future<void> write(String key, PortalListing page) {
    final operation = _writes.then((_) async {
      try {
        if (page.items.isEmpty || page.items.any((item) => item.anime == null))
          return;
        final directory = await _directory();
        await directory.create(recursive: true);
        final file = File('${directory.path}/${_name(key)}');
        final text = jsonEncode({
          'key': key,
          'time': DateTime.now().toIso8601String(),
          'next': page.next,
          'items': [for (final item in page.items) _encode(item.anime!)],
        });
        if (utf8.encode(text).length > 1024 * 1024) return;
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(text, flush: true);
        await temporary.rename(file.path);
        final files = await directory
            .list()
            .where(
              (f) =>
                  f is File &&
                  RegExp(r'catalog_[a-f0-9]{64}\.json$').hasMatch(f.path),
            )
            .cast<File>()
            .toList();
        final dated = [
          for (final f in files) (file: f, time: await f.lastModified()),
        ];
        dated.sort((a, b) => b.time.compareTo(a.time));
        for (final old in dated.skip(24)) {
          await old.file.delete();
        }
      } catch (_) {
        /* Storage failures don't turn a good network result into an error. */
      }
    });
    _writes = operation;
    return operation;
  }

  static Map<String, dynamic> _encode(BangumiItem item) => {
    'id': item.id,
    'type': item.type,
    'name': item.name,
    'name_cn': item.nameCn,
    'summary': item.summary,
    'date': item.airDate,
    'images': item.images,
    'info': item.info,
    'metaTags': item.metaTags,
    'tags': [for (final tag in item.tags) tag.toJson()],
    'infobox': [
      {'key': '别名', 'value': item.alias},
    ],
    'rating': {
      'rank': item.rank,
      'score': item.ratingScore,
      'total': item.votes,
      'count': item.votesCount,
    },
  };
}
