import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/reader_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List valid;
  late Directory directory;
  late ReaderFonts fonts;

  setUpAll(() async => valid = await File('assets/fonts/lucide.ttf').readAsBytes());
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader-font-validation-');
    fonts = ReaderFonts(directory: directory);
  });
  tearDown(() async {
    fonts.dispose();
    await directory.delete(recursive: true);
  });

  int record(ByteData data, String tag) {
    for (var i = 0; i < data.getUint16(4); i++) {
      final offset = 12 + i * 16;
      if (String.fromCharCodes([for (var j = 0; j < 4; j++) data.getUint8(offset + j)]) == tag) return offset;
    }
    throw StateError('测试字体缺少 $tag');
  }

  ByteData table(ByteData data, String tag) {
    final entry = record(data, tag);
    return ByteData.view(data.buffer, data.offsetInBytes + data.getUint32(entry + 8), data.getUint32(entry + 12));
  }

  Future<void> rejects(void Function(ByteData) damage) async {
    final bytes = Uint8List.fromList(valid);
    damage(ByteData.sublistView(bytes));
    await expectLater(fonts.import('损坏.ttf', bytes), throwsFormatException);
    expect(fonts.entries, isEmpty);
    expect(await directory.list().toList(), isEmpty, reason: '校验失败不能保存字体副本');
  }

  test('正常的项目字体仍可导入和恢复', () async {
    final imported = await fonts.import('正常.ttf', valid);
    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore(imported.id);
    expect(reopened.warning, isNull);
    expect(reopened.familyFor(imported.id), imported.family);
  });

  test('sfnt 表名与偏移完整但所有表长度为零：拒绝而不是显示导入成功', () async {
    await rejects((data) {
      for (var i = 0; i < data.getUint16(4); i++) {
        final entry = 12 + i * 16;
        data.setUint32(entry + 8, data.lengthInBytes);
        data.setUint32(entry + 12, 0);
      }
    });
  });

  test('关键表被截短，但字体文件的总长度保持不变', () async {
    for (final tag in ['head', 'hhea', 'maxp', 'hmtx', 'loca', 'cmap', 'name']) {
      await rejects((data) => data.setUint32(record(data, tag) + 12, 1));
    }
  });

  test('head 魔数损坏或 unitsPerEm 不在合法范围内', () async {
    await rejects((data) => table(data, 'head').setUint32(12, 0));
    await rejects((data) => table(data, 'head').setUint16(18, 0));
    await rejects((data) => table(data, 'head').setUint16(18, 16385));
  });

  test('字形数和横向度量数不匹配，或横向度量数据不足', () async {
    await rejects((data) => table(data, 'maxp').setUint16(4, 0));
    await rejects((data) => table(data, 'hhea').setUint16(34, 0));
    await rejects((data) => table(data, 'hhea').setUint16(34, table(data, 'maxp').getUint16(4) + 1));
    await rejects((data) {
      final entry = record(data, 'hmtx');
      data.setUint32(entry + 12, data.getUint32(entry + 12) - 1);
    });
  });

  test('字形位置表使用未知格式、指向轮廓外或出现倒序位置', () async {
    await rejects((data) => table(data, 'head').setInt16(50, 2));
    await rejects((data) => table(data, 'loca').setUint32(0, 0xffffffff));
    await rejects((data) {
      // 仓库字体是 long loca，前两个位置都是 0；把第一个改大便不再单调。
      expect(table(data, 'head').getInt16(50), 1);
      table(data, 'loca').setUint32(0, 10);
    });
  });

  test('cmap 记录目录、子表偏移和子表声明长度越界', () async {
    await rejects((data) => table(data, 'cmap').setUint16(2, 0xffff));
    await rejects((data) => table(data, 'cmap').setUint32(8, 0xffffffff));
    await rejects((data) {
      final cmap = table(data, 'cmap');
      final subtable = cmap.getUint32(8);
      expect(cmap.getUint16(subtable), 4);
      cmap.setUint16(subtable + 2, 0xffff);
    });
  });

  test('name 记录目录和字符串存储范围越界', () async {
    await rejects((data) => table(data, 'name').setUint16(2, 0xffff));
    await rejects((data) => table(data, 'name').setUint16(4, 0));
    await rejects((data) => table(data, 'name').setUint16(4, 0xffff));
    await rejects((data) => table(data, 'name').setUint16(6 + 8, 0xffff));
    await rejects((data) => table(data, 'name').setUint16(6 + 10, 0xffff));
  });

  test('name version 1 语言记录目录越界', () async {
    await rejects((data) {
      final name = table(data, 'name');
      name.setUint16(0, 1);
      name.setUint16(6 + name.getUint16(2) * 12, 0xffff);
    });
  });
}
