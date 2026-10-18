import 'dart:math';

/// 书源 JS 里的时间和文本函数，语义照 MD3（legado-with-MD3 d1b488b）的 `JsExtensions`。

/// `java.timeFormat(毫秒)`：设备本地时区，`yyyy/MM/dd HH:mm`。
String timeFormat(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${_pad(time.year, 4)}/${_pad(time.month, 2)}/${_pad(time.day, 2)} ${_pad(time.hour, 2)}:${_pad(time.minute, 2)}';
}

/// `java.timeFormatUTC(毫秒, 格式, 偏移)`：以偏移（毫秒）为时区，按 Java `SimpleDateFormat` 的格式输出，
/// 文字部分（月份名、星期、上午下午）用简体中文（中文设备的默认 Locale）。
///
/// 支持的字母：`y M d H h k K m s S E a Z D u`，单引号转义同 Java；其它字母以 [FormatException] 结束。
String timeFormatUtc(int milliseconds, String pattern, int offsetMilliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds + offsetMilliseconds, isUtc: true);
  final out = StringBuffer();
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == "'") {
      // '' 是一个单引号；'…' 里的内容原样输出，其中的 '' 也是一个单引号
      if (i + 1 < pattern.length && pattern[i + 1] == "'") {
        out.write("'");
        i += 2;
        continue;
      }
      i++;
      while (true) {
        if (i >= pattern.length) throw FormatException('Unterminated quote', pattern);
        if (pattern[i] == "'") {
          if (i + 1 < pattern.length && pattern[i + 1] == "'") {
            out.write("'");
            i += 2;
            continue;
          }
          i++;
          break;
        }
        out.write(pattern[i++]);
      }
      continue;
    }
    if (!_isAsciiLetter(c.codeUnitAt(0))) {
      out.write(c);
      i++;
      continue;
    }
    var count = 1;
    while (i + count < pattern.length && pattern[i + count] == c) {
      count++;
    }
    out.write(_field(time, c, count, offsetMilliseconds, pattern));
    i += count;
  }
  return out.toString();
}

String _field(DateTime time, String letter, int count, int offset, String pattern) => switch (letter) {
  'y' => count == 2 ? _pad(time.year % 100, 2) : _pad(time.year, count),
  'M' => count >= 4 ? _monthNames[time.month - 1] : (count == 3 ? '${time.month}月' : _pad(time.month, count)),
  'd' => _pad(time.day, count),
  'H' => _pad(time.hour, count),
  'h' => _pad(time.hour % 12 == 0 ? 12 : time.hour % 12, count),
  'k' => _pad(time.hour == 0 ? 24 : time.hour, count),
  'K' => _pad(time.hour % 12, count),
  'm' => _pad(time.minute, count),
  's' => _pad(time.second, count),
  'S' => _pad(time.millisecond, count),
  'E' => (count >= 4 ? '星期' : '周') + _weekdayNames[time.weekday - 1],
  'a' => time.hour < 12 ? '上午' : '下午',
  'Z' => _zone(offset),
  'D' => _pad(time.difference(DateTime.utc(time.year)).inDays + 1, count),
  'u' => _pad(time.weekday, count),
  _ => throw FormatException('不支持的格式字母：$letter', pattern),
};

const List<String> _monthNames = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// RFC 822 时区：`+0800`。
String _zone(int offsetMilliseconds) {
  final minutes = offsetMilliseconds ~/ 60000;
  final sign = minutes < 0 ? '-' : '+';
  return '$sign${_pad(minutes.abs() ~/ 60, 2)}${_pad(minutes.abs() % 60, 2)}';
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');

bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// `java.toNumChapter(文本)`：找第一个「第…章」，把中间部分转成整数，只返回 `第N章`（前后文字丢掉）；
/// 没有「第…章」时原样返回。中间部分先全角转半角、去掉空白，能按整数解析就用它，
/// 否则按中文数字计算，含有不认识的字符时为 -1。
String toNumChapter(String text) {
  final match = _chapterPattern.firstMatch(text);
  if (match == null) return text;
  return '第${_parseChapterNumber(match.group(1)!)}章';
}

// Java 的 `.` 不匹配 \n \r \u0085    
final RegExp _chapterPattern = RegExp('第([^\n\r\u0085  ]+?)章');

int _parseChapterNumber(String text) {
  final number = _fullToHalf(text).replaceAll(_javaWhitespace, '');
  return _parseJavaInt(number) ?? _chineseNumber(number);
}

final RegExp _javaWhitespace = RegExp('[ \t\n\u000B\f\r]+');

/// 全角空格转半角空格，U+FF01–U+FF5E 转成对应的 ASCII。
String _fullToHalf(String text) => String.fromCharCodes([
  for (final c in text.codeUnits) c == 0x3000 ? 0x20 : (c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : c),
]);

/// Java `Integer.parseInt`：可以带正负号，超出 32 位范围时失败。
int? _parseJavaInt(String text) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(text)) return null;
  final value = int.tryParse(text);
  return value != null && value >= -0x80000000 && value <= 0x7FFFFFFF ? value : null;
}

/// 中文数字的值：零到九（含大写和「两」）、十百千（含大写）、万、亿。
const Map<String, int> _chineseDigits = {
  '零': 0, '〇': 0, '一': 1, '壹': 1, '二': 2, '贰': 2, '两': 2, '三': 3, '叁': 3, '四': 4, '肆': 4,
  '五': 5, '伍': 5, '六': 6, '陆': 6, '七': 7, '柒': 7, '八': 8, '捌': 8, '九': 9, '玖': 9,
  '十': 10, '拾': 10, '百': 100, '佰': 100, '千': 1000, '仟': 1000, '万': 10000, '亿': 100000000,
};

/// 从左到右累加：数字先记在 [pending]；遇到十百千时乘上去并计入 [section]；遇到万时整段乘一万；
/// 遇到亿时整段乘一亿后计入 [billions]。末位数字紧跟在大于十的单位后面时按省略写法算（「一千二」是 1200）。
/// 运算按 32 位整数回绕（与 Kotlin 的 Int 一致）。有不认识的字符时返回 -1。
int _chineseNumber(String text) {
  final values = <int>[];
  for (final c in text.split('')) {
    final value = _chineseDigits[c];
    if (value == null) return -1;
    values.add(value);
  }
  var section = 0;
  var pending = 0;
  var billions = 0;
  for (var i = 0; i < values.length; i++) {
    final value = values[i];
    if (value == 100000000) {
      section = ((section + pending) * value).toSigned(32);
      billions = (billions * value + section).toSigned(32);
      section = 0;
      pending = 0;
    } else if (value == 10000) {
      section = ((section + pending) * value).toSigned(32);
      pending = 0;
    } else if (value >= 10) {
      section = (section + value * (pending == 0 ? 1 : pending)).toSigned(32);
      pending = 0;
    } else if (i >= 2 && i == values.length - 1 && values[i - 1] > 10) {
      pending = value * values[i - 1] ~/ 10;
    } else {
      pending = (pending * 10 + value).toSigned(32);
    }
  }
  return (section + pending + billions).toSigned(32);
}

/// `java.randomUUID()`：小写带连字符的 v4 UUID。
String randomUuid() {
  final bytes = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final Random _random = Random.secure();
