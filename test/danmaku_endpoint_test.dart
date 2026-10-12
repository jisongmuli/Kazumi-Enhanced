import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/danmaku_endpoint.dart';

void main() {
  test('compatibility endpoints preserve base path and original query', () {
    final base = DanmakuEndpoint.parse('http://127.0.0.1:9321/token/');
    final routed = DanmakuEndpoint.route(
      Uri.parse('https://api.dandanplay.net/api/v2/search/episodes?v2=true'),
      base,
    );
    expect(
      routed.toString(),
      'http://127.0.0.1:9321/token/api/v2/search/episodes?v2=true',
    );
  });
  test('credentials never leave HTTPS official host', () {
    for (final url in [
      'https://example.com/api/v2/search/episodes',
      'http://api.dandanplay.net/api/v2/search/episodes',
      'https://api.dandanplay.net:8443/api/v2/search/episodes',
      'https://api.dandanplay.net.evil.example/api/v2/search/episodes',
    ]) {
      expect(
        DanmakuEndpoint.signatureHeaders(Uri.parse(url), 'id', 'secret', 123),
        isEmpty,
      );
    }
  });
  test(
    'official missing credentials produce actionable error instead of 403 request',
    () {
      expect(
        () => DanmakuEndpoint.signatureHeaders(
          Uri.parse('https://api.dandanplay.net/api/v2/search/episodes'),
          '',
          '',
          123,
        ),
        throwsStateError,
      );
    },
  );
  test('signature uses configured credentials and excludes query', () {
    final headers = DanmakuEndpoint.signatureHeaders(
      Uri.parse('https://api.dandanplay.net/api/v2/search/episodes?anime=x'),
      'id',
      'secret',
      123,
    );
    expect(
      headers['X-Signature'],
      base64Encode(
        sha256.convert(utf8.encode('id123/api/v2/search/episodessecret')).bytes,
      ),
    );
  });
  test('invalid endpoint roots are rejected', () {
    for (final value in [
      'file:///E:/x',
      'https://example.com?q=x',
      'https://example.com#x',
      'https://user:password@example.com',
      '',
    ]) {
      expect(() => DanmakuEndpoint.parse(value), throwsArgumentError);
    }
  });
}
