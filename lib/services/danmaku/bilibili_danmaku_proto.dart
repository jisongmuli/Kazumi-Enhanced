import 'dart:convert';

/// Public DmSegMobileReply / DanmakuElem wire fields; unknown fields are skipped.
abstract final class BilibiliDanmakuProto {
  static List<Map<String, dynamic>> parse(List<int> bytes) {
    if (bytes.length > 8 * 1024 * 1024)
      throw const FormatException('Segment too large');
    final result = <Map<String, dynamic>>[];
    for (final row in _fields(bytes)) {
      if (row.number != 1 || row.value is! List<int>) continue;
      final fields = {
        for (final f in _fields(row.value as List<int>)) f.number: f.value,
      };
      final progress = fields[2] ?? 0;
      final mode = fields[3];
      final color = fields[5] ?? 0;
      final content = fields[7];
      if (progress is! int ||
          progress < 0 ||
          mode is! int ||
          !{1, 2, 3, 4, 5}.contains(mode) ||
          color is! int ||
          color < 0 ||
          color > 0xffffff ||
          content is! List<int>)
        continue;
      final text = utf8.decode(content, allowMalformed: false).trim();
      if (text.isEmpty) continue;
      result.add({
        'p': '${progress / 1000},${mode <= 3 ? 1 : mode},$color,[BiliBili]',
        'm': text,
      });
    }
    return result;
  }

  static Iterable<({int number, Object value})> _fields(List<int> bytes) sync* {
    var offset = 0;
    int varint() {
      var value = 0;
      for (var shift = 0; shift < 70; shift += 7) {
        if (offset >= bytes.length)
          throw const FormatException('Truncated protobuf');
        final byte = bytes[offset++];
        value |= (byte & 0x7f) << shift;
        if (byte < 128) return value;
      }
      throw const FormatException('Invalid protobuf integer');
    }

    while (offset < bytes.length) {
      final tag = varint();
      final number = tag >> 3;
      final wire = tag & 7;
      if (number == 0) throw const FormatException('Invalid protobuf field');
      if (wire == 0) {
        yield (number: number, value: varint());
      } else if (wire == 2) {
        final length = varint();
        if (length < 0 || offset + length > bytes.length)
          throw const FormatException('Truncated protobuf bytes');
        final data = bytes.sublist(offset, offset + length);
        offset += length;
        yield (number: number, value: data);
      } else if (wire == 1 || wire == 5) {
        offset += wire == 1 ? 8 : 4;
        if (offset > bytes.length)
          throw const FormatException('Truncated fixed field');
      } else {
        throw const FormatException('Unsupported protobuf wire type');
      }
    }
  }
}
