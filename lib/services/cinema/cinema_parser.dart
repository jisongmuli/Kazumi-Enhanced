import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/cinema/cinema_models.dart';

class CinemaSearchForm {
  const CinemaSearchForm(this.url, this.method, this.fields, this.keywordKey);
  final String url;
  final String method;
  final Map<String, String> fields;
  final String keywordKey;
}

class CinemaParser {
  static bool isHongguo(String url) => [
    'hongguoduanju.com',
    'novelquickapp.com',
    'www.novelquickapp.com',
    'applink.novelquickapp.com',
  ].contains(Uri.parse(url).host);

  static Map<String, dynamic>? _hongguoRouteData(String markup) {
    for (final script in html.parse(markup).querySelectorAll('script')) {
      final text = script.text;
      final match = RegExp(r'_ROUTER_DATA\s*=\s*(\{)').firstMatch(text);
      if (match == null) continue;
      final start = match.end - 1;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var i = start; i < text.length; i++) {
        final char = text[i];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
        } else if (char == '"') {
          quoted = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}' && --depth == 0) {
          try {
            return jsonDecode(text.substring(start, i + 1))
                as Map<String, dynamic>;
          } catch (_) {
            break;
          }
        }
      }
    }
    return null;
  }

  // Read only the site's JSON player configuration; never execute its scripts.
  static String? directMediaUrl(String markup, String base) {
    if (isHongguo(base)) {
      final data = _hongguoRouteData(markup)?['loaderData'];
      if (data is Map) {
        for (final route in data.values.whereType<Map>()) {
          final player = route['video_player_info'];
          if (player is Map && player['main_url'] is String) {
            return absoluteUrl(base, player['main_url']);
          }
        }
      }
    }
    for (final match in RegExp(
      r'var\s+player_[\w]+\s*=\s*(\{.*?\})\s*;?\s*</script>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(markup)) {
      try {
        final config = jsonDecode(match[1]!) as Map<String, dynamic>;
        var value = config['url'] as String;
        switch (config['encrypt'].toString()) {
          case '0':
            break;
          case '1':
            value = Uri.decodeComponent(value);
          case '2':
            value = Uri.decodeComponent(utf8.decode(base64Decode(value)));
          default:
            continue;
        }
        final url = absoluteUrl(base, value);
        if (url != null &&
            RegExp(
              r'\.(m3u8|mp4|mpd)$',
              caseSensitive: false,
            ).hasMatch(Uri.parse(url).path)) {
          return url;
        }
      } catch (_) {
        // Unknown player formats continue through the existing WebView parser.
      }
    }
    return null;
  }

  static String? absoluteUrl(String base, String? value) {
    if (value == null || value.trim().isEmpty || value.startsWith('#')) {
      return null;
    }
    try {
      final uri = Uri.parse(base).resolve(value.trim());
      return ['https', 'http'].contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri.toString()
          : null;
    } catch (_) {
      return null;
    }
  }

  static String _text(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _titleText(Element? element) {
    if (element == null) return '';
    var title = element.text;
    for (final badge in element.querySelectorAll('.info_right, .tag, .badge')) {
      title = title.replaceFirst(badge.text, '');
    }
    return _text(title);
  }

  static String? _image(Element anchor) {
    for (final element in [anchor, ...anchor.querySelectorAll('img')]) {
      for (final key in [
        'data-original',
        'data-src',
        'data-lazy-src',
        'data-url',
        'src',
      ]) {
        final value = element.attributes[key];
        if (value != null &&
            value.isNotEmpty &&
            !RegExp(
              r'logo|loading|blank|icon|\.gif',
              caseSensitive: false,
            ).hasMatch(value)) {
          return value;
        }
      }
      final match = RegExp(
        "url\\(\\s*['\"]?(.+?)['\"]?\\s*\\)",
      ).firstMatch(element.attributes['style'] ?? '');
      if (match != null) return match[1];
    }
    return null;
  }

  static CinemaListing listing(
    String markup,
    CinemaSource source,
    String base,
  ) {
    final document = html.parse(markup);
    final films = <String, CinemaFilm>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final url = absoluteUrl(base, anchor.attributes['href']);
      final poster = absoluteUrl(base, _image(anchor));
      if (url == null ||
          poster == null ||
          Uri.parse(url).host != Uri.parse(base).host) {
        continue;
      }
      final path = Uri.parse(url).path;
      if (path == '/' ||
          path.contains('/index/home') ||
          RegExp(
            r'/(artdetail[-/]|article/|news/|blog/|post/|tag/)',
            caseSensitive: false,
          ).hasMatch(path) ||
          RegExp(
            r'/(adstat|advert|ads|download)(/|$)',
            caseSensitive: false,
          ).hasMatch(path) ||
          path.endsWith('.js') ||
          anchor.classes.any(
            (name) => name.contains('logo') || name.contains('banner'),
          )) {
        continue;
      }
      var title = _text(anchor.attributes['title']);
      if (title.isEmpty)
        title = _text(anchor.querySelector('img')?.attributes['alt']);
      if (title.isEmpty)
        title = _titleText(
          anchor.querySelector('.vodlist_title, .vodlist-title'),
        );
      var parent = anchor.parent;
      for (
        var i = 0;
        title.isEmpty && parent != null && i < 3;
        i++, parent = parent.parent
      ) {
        title = _titleText(
          parent.querySelector(
            'h3, h4, .title, .module-poster-item-title, .public-list-name, .movie-title, .vodlist_title, .vodlist-title',
          ),
        );
      }
      // Search highlighting is sometimes embedded in an escaped title/alt
      // attribute. Treat it as text, as the site's browser view does.
      title = _text(html.parseFragment(title).text);
      if (title.isEmpty || title == source.name || title.length > 180) continue;
      final badge = _text(
        anchor
            .querySelector(
              '.pic-text, .module-item-note, .public-list-prb, .module-item-text, .tag-box .tag',
            )
            ?.text,
      );
      films.putIfAbsent(
        url,
        () => CinemaFilm(
          source: source,
          title: title,
          url: url,
          poster: poster,
          badge: badge,
          summary: _text(anchor.querySelector('.info-intro')?.text),
          rating: _score(anchor.querySelector('.pic-tag, .score')?.text),
        ),
      );
    }
    String? next;
    for (final anchor in document.querySelectorAll('a[href]')) {
      if (anchor.attributes['rel'] == 'next' ||
          RegExp(r'下一页|下页|Next', caseSensitive: false).hasMatch(anchor.text)) {
        final target = absoluteUrl(base, anchor.attributes['href']);
        if (target != null &&
            target != base &&
            Uri.parse(target).host == Uri.parse(base).host) {
          next = target;
          break;
        }
      }
    }
    return CinemaListing(films: films.values.toList(), nextUrl: next);
  }

  static double _score(String? text) {
    final score = double.tryParse(_text(text)) ?? 0;
    return score > 0 && score <= 10 ? score : 0;
  }

  static Map<String, String> categoryLinks(String markup, String base) {
    const names = {
      '电影',
      '电视剧',
      '纪录片',
      '动漫',
      '综艺',
      '国产剧',
      '欧美剧',
      '日韩剧',
      '日本剧',
      '韩国剧',
      '大陆',
      '香港',
      '台湾',
      '美国',
      '英国',
      '日本',
      '韩国',
      '法国',
      '德国',
      '动画',
      '动画片',
      '短片',
    };
    final links = <String, String>{};
    for (final anchor in html.parse(markup).querySelectorAll('a[href]')) {
      final name = _text(anchor.text);
      final url = absoluteUrl(base, anchor.attributes['href']);
      if (names.contains(name) &&
          url != null &&
          Uri.parse(url).host == Uri.parse(base).host &&
          !Uri.parse(url).path.contains('/detail/')) {
        links.putIfAbsent(name, () => url);
      }
    }
    return links;
  }

  static CinemaSearchForm? searchForm(String markup, String base) {
    final document = html.parse(markup);
    for (final form in document.querySelectorAll('form')) {
      final input =
          form.querySelector(
            'input[name="wd"], input[name="searchword"], input[name="keyword"], input[name="q"]',
          ) ??
          (form.id.toLowerCase().contains('search') ||
                  (form.attributes['action'] ?? '').contains('search') ||
                  RegExp(
                    r'^/s(?:\.html)?$',
                  ).hasMatch(form.attributes['action'] ?? '')
              ? form.querySelector(
                  'input[name="name"], input[type="search"][name]',
                )
              : null);
      if (input == null) continue;
      final url = absoluteUrl(base, form.attributes['action'] ?? base);
      if (url == null || Uri.parse(url).host != Uri.parse(base).host) continue;
      final fields = <String, String>{};
      for (final field in form.querySelectorAll('input[type="hidden"][name]')) {
        fields[field.attributes['name']!] = field.attributes['value'] ?? '';
      }
      return CinemaSearchForm(
        url,
        (form.attributes['method'] ?? 'get').toUpperCase(),
        fields,
        input.attributes['name']!,
      );
    }
    return null;
  }

  static CinemaDetail detail(String markup, CinemaFilm film, String base) {
    final document = html.parse(markup);
    final summary = _text(
      document
              .querySelector(
                '.module-info-introduction, .stui-content__desc, .myui-content__desc, .vod_content, .content-desc, .detail-content',
              )
              ?.text ??
          document
              .querySelector(
                'meta[property="og:description"], meta[name="description"]',
              )
              ?.attributes['content'],
    );
    final roads = <Road>[];
    final seenGroups = <String>{};
    final labels = document.querySelectorAll(
      '.module-tab-item, .stui-pannel__head h3, .myui-panel__head h3, .ds-anthology-head a, .anthology-tab a, .player_name a',
    );
    final groups = document.querySelectorAll(
      '.module-play-list, .stui-content__playlist, .myui-content__list, .playlist, .play-list, .play_list, .anthology-list-play, .ds-anthology-list, .play-list-content, .lists-box[id^="playlist"], [class*="episode-grid-"]',
    );
    void addGroup(Iterable<Element> anchors, String name) {
      final episodes = <String, String>{};
      for (final anchor in anchors) {
        final url = absoluteUrl(base, anchor.attributes['href']);
        if (url == null ||
            Uri.parse(url).host != Uri.parse(base).host ||
            !_playLink(url)) {
          continue;
        }
        episodes[url] = _text(anchor.text).isEmpty ? '播放' : _text(anchor.text);
      }
      final signature = episodes.keys.join('|');
      if (episodes.isEmpty || !seenGroups.add(signature)) return;
      roads.add(
        Road(
          name: name.isEmpty ? '线路 ${roads.length + 1}' : name,
          data: episodes.keys.toList(),
          identifier: episodes.values.toList(),
        ),
      );
    }

    for (final group in groups) {
      if (group.querySelector(
            '.module-play-list, .stui-content__playlist, .myui-content__list, .playlist, .play-list, .play_list, .anthology-list-play, .ds-anthology-list, .play-list-content, .lists-box[id^="playlist"]',
          ) !=
          null) {
        continue;
      }
      final preceding = group.previousElementSibling;
      final heading =
          preceding?.querySelector('h3, h4') ??
          (preceding?.localName == 'h3' ? preceding : null);
      final name = isHongguo(base)
          ? '红果官方网页（网页开放集数）'
          : heading != null
          ? _text(heading.text)
          : roads.length < labels.length
          ? _text(labels[roads.length].text)
          : '';
      addGroup(group.querySelectorAll('a[href]'), name);
    }
    if (roads.isEmpty) addGroup(document.querySelectorAll('a[href]'), '播放线路');
    return CinemaDetail(
      notice: isHongguo(base) ? '仅列出官方网页开放的集数；更多剧集请通过原站提示在红果 App 观看。' : '',
      film: CinemaFilm(
        source: film.source,
        title: film.title,
        url: film.url,
        poster: film.poster,
        badge: film.badge,
        summary: summary,
        rating: film.rating,
      ),
      roads: roads,
    );
  }

  static bool _playLink(String url) => RegExp(
    r'/(vodplay|play|player|video|watch|bofang|v_play|bf)(/|-\d)|/play[^/]*\.html|/(tv|movie|anime|variety|dongman|zongyi|duanju)/[^/]+/\d+($|[?])|[?&](play|ep)=',
    caseSensitive: false,
  ).hasMatch(url);
}
