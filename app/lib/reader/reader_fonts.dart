import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final readerFontsProvider = ChangeNotifierProvider<ReaderFonts>((ref) => ReaderFonts());

final class ReaderFont {
  const ReaderFont(this.id, this.file);

  final String id;
  final File file;
  String get name => p.basenameWithoutExtension(file.path);
  String get family => 'reader-$id';
}

/// 每个字体在应用支持目录内有独立目录，目录名是稳定 ID，文件名用于显示。
/// 只加载当前使用的字体，避免启动时把所有中文字体都放进内存。
final class ReaderFonts extends ChangeNotifier {
  ReaderFonts({Directory? directory}) : _providedDirectory = directory;

  final Directory? _providedDirectory;
  Future<Directory>? _directoryFuture;
  List<ReaderFont> _entries = [];
  final Set<String> _loaded = {};
  String? warning;

  List<ReaderFont> get entries => List.unmodifiable(_entries);
  ReaderFont? find(String id) => _entries.where((font) => font.id == id).firstOrNull;
  String? familyFor(String id) => _loaded.contains(id) ? find(id)?.family : null;

  Future<Directory> _directory() =>
      _directoryFuture ??= (() async =>
          _providedDirectory ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'reader_fonts')))();

  /// 在首屏之前恢复，确保首次排版用到的就是真正选中的字体。
  Future<void> restore(String selected) async {
    try {
      final directory = await _directory();
      _entries = [];
      if (await directory.exists()) {
        await for (final item in directory.list(followLinks: false)) {
          if (item is! Directory || !p.basename(item.path).startsWith('font-')) continue;
          final files = await item.list(followLinks: false).where((file) => file is File && _supported(file.path)).cast<File>().toList();
          if (files.length == 1) _entries.add(ReaderFont(p.basename(item.path), files.single));
        }
        _entries.sort((a, b) => a.name.compareTo(b.name));
      }
      if (selected.isNotEmpty) await load(selected);
    } on Exception {
      warning = '已选字体无法读取，已使用系统字体。请重新导入或选择其他字体。';
    }
  }

  Future<void> load(String id) async {
    if (_loaded.contains(id)) return;
    final font = find(id);
    if (font == null) throw const FormatException('字体文件不存在，请重新导入');
    await _load(font, await font.file.readAsBytes());
  }

  Future<void> _load(ReaderFont font, Uint8List bytes) async {
    _validate(bytes);
    final loader = FontLoader(font.family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(font.id);
  }

  /// 先验证和载入，再公布新字体；原文件删除或移动不会影响应用内副本。
  Future<ReaderFont> import(String name, Uint8List bytes) async {
    if (!_supported(name)) throw const FormatException('请选择 TTF 或 OTF 字体文件');
    _validate(bytes);
    for (final font in _entries) {
      if (await font.file.exists() && listEquals(await font.file.readAsBytes(), bytes)) {
        await load(font.id);
        return font;
      }
    }
    final root = await _directory();
    await root.create(recursive: true);
    final folder = await root.createTemp('font-');
    final font = ReaderFont(p.basename(folder.path), File(p.join(folder.path, p.basename(name))));
    try {
      await font.file.writeAsBytes(bytes, flush: true);
      await _load(font, bytes);
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
    _entries = [..._entries, font];
    warning = null;
    notifyListeners();
    return font;
  }

  Future<void> remove(String id) async {
    final font = find(id);
    if (font == null) return;
    if (await font.file.parent.exists()) await font.file.parent.delete(recursive: true);
    _entries = _entries.where((entry) => entry.id != id).toList();
    _loaded.remove(id);
    notifyListeners();
  }

  static bool _supported(String name) => const ['.ttf', '.otf'].contains(p.extension(name).toLowerCase());

  /// FontLoader 不保证为无效字节抛错；先检查 sfnt 签名、目录和表边界，拒绝改后缀的文件和截断字体。
  /// https://learn.microsoft.com/en-us/typography/opentype/spec/otff
  static void _validate(Uint8List bytes) {
    Never invalid() => throw const FormatException('字体文件无效或已损坏，请重新选择 TTF 或 OTF 文件');
    if (bytes.length < 12) invalid();
    final data = ByteData.sublistView(bytes);
    final signature = data.getUint32(0);
    if (signature != 0x00010000 && signature != 0x4f54544f && signature != 0x74727565) invalid();
    final count = data.getUint16(4);
    if (count == 0 || 12 + count * 16 > bytes.length) invalid();
    final tables = <String, ByteData>{};
    for (var i = 0; i < count; i++) {
      final record = 12 + i * 16;
      final offset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      if (offset < 12 + count * 16 || offset + length > bytes.length || tables.containsKey(tag)) invalid();
      tables[tag] = ByteData.sublistView(bytes, offset, offset + length);
    }
    ByteData table(String tag, int minimum) {
      final value = tables[tag];
      if (value == null || value.lengthInBytes < minimum) invalid();
      return value;
    }

    // 必需表存在并不代表可用：引擎遇到坏表可能静默回退，先拒绝空表和破损的关键字段。
    final head = table('head', 54);
    final units = head.getUint16(18);
    if (head.getUint16(0) != 1 || head.getUint32(12) != 0x5f0f3cf5 || units < 16 || units > 16384) invalid();
    final maxp = table('maxp', 6);
    final version = maxp.getUint32(0);
    if (version != 0x00005000 && version != 0x00010000) invalid();
    if (version == 0x00010000 && maxp.lengthInBytes < 32) invalid();
    final glyphs = maxp.getUint16(4);
    final hhea = table('hhea', 36);
    final metrics = hhea.getUint16(34);
    if (glyphs == 0 || hhea.getUint32(0) != 0x00010000 || metrics == 0 || metrics > glyphs) invalid();
    table('hmtx', metrics * 4 + (glyphs - metrics) * 2);
    if (signature == 0x4f54544f) {
      if (tables.containsKey('CFF ')) {
        table('CFF ', 4);
      } else {
        table('CFF2', 5);
      }
    } else {
      final format = head.getInt16(50);
      if (format != 0 && format != 1) invalid();
      final loca = table('loca', (glyphs + 1) * (format == 0 ? 2 : 4));
      final glyf = table('glyf', 0);
      var previous = 0;
      for (var i = 0; i <= glyphs; i++) {
        final offset = format == 0 ? loca.getUint16(i * 2) * 2 : loca.getUint32(i * 4);
        if (offset < previous || offset > glyf.lengthInBytes) invalid();
        previous = offset;
      }
    }

    final cmap = table('cmap', 4);
    final mappings = cmap.getUint16(2);
    final mappingEnd = 4 + mappings * 8;
    if (cmap.getUint16(0) != 0 || mappings == 0 || mappingEnd > cmap.lengthInBytes) invalid();
    for (var i = 0; i < mappings; i++) {
      final offset = cmap.getUint32(4 + i * 8 + 4);
      if (offset < mappingEnd || offset + 2 > cmap.lengthInBytes) invalid();
      final format = cmap.getUint16(offset);
      final minimum = switch (format) {
        0 => 262,
        2 => 518,
        4 => 16,
        6 => 10,
        8 => 8208,
        10 => 20,
        12 || 13 => 16,
        14 => 10,
        _ => 0,
      };
      if (minimum == 0 || offset + minimum > cmap.lengthInBytes) invalid();
      final length = format == 14
          ? cmap.getUint32(offset + 2)
          : format >= 8
          ? cmap.getUint32(offset + 4)
          : cmap.getUint16(offset + 2);
      if (length < minimum || offset + length > cmap.lengthInBytes) invalid();
    }

    final name = table('name', 6);
    final nameVersion = name.getUint16(0);
    final names = name.getUint16(2);
    final storage = name.getUint16(4);
    var recordsEnd = 6 + names * 12;
    if (nameVersion > 1 || recordsEnd > name.lengthInBytes) invalid();
    void checkString(int record) {
      final length = name.getUint16(record);
      final offset = name.getUint16(record + 2);
      if (storage + offset + length > name.lengthInBytes) invalid();
    }

    for (var i = 0; i < names; i++) {
      checkString(6 + i * 12 + 8);
    }
    if (nameVersion == 1) {
      if (recordsEnd + 2 > name.lengthInBytes) invalid();
      final languages = name.getUint16(recordsEnd);
      final languageStart = recordsEnd + 2;
      recordsEnd = languageStart + languages * 4;
      if (recordsEnd > name.lengthInBytes) invalid();
      for (var i = 0; i < languages; i++) {
        checkString(languageStart + i * 4);
      }
    }
    if (storage < recordsEnd || storage > name.lengthInBytes) invalid();
  }
}
