import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/reader_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late Directory directory;
  late ReaderFonts fonts;
  late Uint8List validFont;

  setUpAll(() async {
    // 使用仓库已有且带许可证的字体，测试不依赖系统字体或网络。
    validFont = await File('assets/fonts/lucide.ttf').readAsBytes();
  });

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('reader-fonts-test-');
    directory = Directory('${temporary.path}/library');
    fonts = ReaderFonts(directory: directory);
  });

  tearDown(() async {
    fonts.dispose();
    await temporary.delete(recursive: true);
  });

  test('导入保存应用内副本，原文件删除后仍可恢复字体', () async {
    final original = File('${temporary.path}/我的字体.TTF');
    await original.writeAsBytes(validFont);
    final imported = await fonts.import(
      '我的字体.TTF',
      await original.readAsBytes(),
    );
    expect(imported.name, '我的字体');
    expect(imported.file.path, startsWith('${directory.path}/'));
    expect(await imported.file.readAsBytes(), orderedEquals(validFont));
    expect(fonts.familyFor(imported.id), imported.family);
    await original.delete();

    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore(imported.id);
    expect(reopened.entries.single.id, imported.id);
    expect(reopened.entries.single.name, '我的字体');
    expect(reopened.familyFor(imported.id), imported.family);
    expect(reopened.warning, isNull);
  });

  test('相同字体改名重复导入不新增文件，也不改变原 ID', () async {
    final first = await fonts.import('初次.ttf', validFont);
    final repeated = await fonts.import(
      '另一个名字.ttf',
      Uint8List.fromList(validFont),
    );
    expect(repeated.id, first.id);
    expect(fonts.entries, hasLength(1));
    expect(await directory.list().length, 1);

    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore('');
    expect(reopened.familyFor(first.id), isNull);
    final importedAgain = await reopened.import('再次导入.ttf', validFont);
    expect(importedAgain.id, first.id);
    expect(reopened.familyFor(first.id), first.family);
    expect(await directory.list().length, 1);
  });

  test('同名不同字节的合法字体分别保存，不覆盖旧字体', () async {
    final first = await fonts.import('同名.ttf', validFont);
    // sfnt 表有自己的偏移和长度，追加零填充不修改已有表，仍是合法字体。
    final padded = Uint8List.fromList([...validFont, 0, 0, 0, 0]);
    final second = await fonts.import('同名.ttf', padded);
    expect(second.id, isNot(first.id));
    expect(second.file.path, isNot(first.file.path));
    expect(fonts.entries, hasLength(2));
    expect(await first.file.readAsBytes(), orderedEquals(validFont));
    expect(await second.file.readAsBytes(), orderedEquals(padded));

    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore(second.id);
    expect(reopened.entries, hasLength(2));
    expect(reopened.familyFor(second.id), second.family);
    // 启动只载入选中的字体；另一个选中时才载入。
    expect(reopened.familyFor(first.id), isNull);
    await reopened.load(first.id);
    expect(reopened.familyFor(first.id), first.family);
  });

  test('删除字体移除副本和列表，重启不会重新出现', () async {
    final imported = await fonts.import('删除.ttf', validFont);
    final original = File('${temporary.path}/保留.ttf');
    await original.writeAsBytes(validFont);
    await fonts.remove(imported.id);
    expect(fonts.entries, isEmpty);
    expect(fonts.find(imported.id), isNull);
    expect(fonts.familyFor(imported.id), isNull);
    expect(await imported.file.parent.exists(), isFalse);
    expect(await original.exists(), isTrue);
    await fonts.remove(imported.id);

    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore('');
    expect(reopened.entries, isEmpty);
    expect(reopened.warning, isNull);
  });

  test('第一次启动使用系统字体，不创建字体目录', () async {
    await fonts.restore('');
    expect(fonts.entries, isEmpty);
    expect(fonts.familyFor(''), isNull);
    expect(fonts.warning, isNull);
    expect(await directory.exists(), isFalse);
  });

  test('已选字体文件丢失，启动回落到系统字体并给出提示', () async {
    final imported = await fonts.import('丢失.ttf', validFont);
    await imported.file.delete();
    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore(imported.id);
    expect(reopened.familyFor(imported.id), isNull);
    expect(reopened.warning, contains('系统字体'));
    expect(reopened.entries, isEmpty);
  });

  test('已选字体文件损坏，启动不中断且不把它标为可用字体', () async {
    final imported = await fonts.import('损坏.ttf', validFont);
    await imported.file.writeAsBytes([0, 1, 2]);
    final reopened = ReaderFonts(directory: directory);
    addTearDown(reopened.dispose);
    await reopened.restore(imported.id);
    expect(reopened.familyFor(imported.id), isNull);
    expect(reopened.warning, contains('系统字体'));
    // 保留列表项，用户仍能识别并删除损坏字体。
    expect(reopened.find(imported.id), isNotNull);
    await reopened.remove(imported.id);
    expect(reopened.entries, isEmpty);
  });

  test('非法后缀、改后缀文本、空文件、截断字体均拒绝且不残留文件', () async {
    final invalid = <(String, Uint8List)>[
      ('不是字体.txt', validFont),
      ('伪装.ttf', Uint8List.fromList('this is not a font'.codeUnits)),
      ('空文件.otf', Uint8List(0)),
      ('截断目录.ttf', Uint8List.fromList(validFont.take(16).toList())),
      (
        '截断表.ttf',
        Uint8List.fromList(validFont.take(validFont.length ~/ 2).toList()),
      ),
    ];
    for (final (name, bytes) in invalid) {
      await expectLater(
        fonts.import(name, bytes),
        throwsFormatException,
        reason: name,
      );
      expect(fonts.entries, isEmpty, reason: name);
    }
    expect(await directory.exists(), isFalse);

    final imported = await fonts.import('已有.ttf', validFont);
    await expectLater(
      fonts.import('坏字体.ttf', Uint8List(8)),
      throwsFormatException,
    );
    expect(fonts.entries.single.id, imported.id);
    expect(await directory.list().length, 1);
    expect(fonts.familyFor(imported.id), imported.family);
  });
}
