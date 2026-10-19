// 1.3 断行检查（开发机，测试字体）。模拟器上的同一检查见 integration_test/typeset_test.dart。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spike/typeset/line_breaks.dart';
import 'package:spike/typeset/two_pass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实网文和压力文本在五种宽度下都遵守避头尾', () async {
    final corpus = parseCorpus(await rootBundle.loadString('assets/corpus.txt'));
    final paragraphs = [for (final chapter in corpus) ...chapter.paragraphs, ...stressParagraphs()];
    final violations = [
      for (final width in checkWidths) ...checkLineBreaks(paragraphs, const TypesetStyle(), width),
    ];
    for (final v in violations) {
      // ignore: avoid_print
      print('${v.kind}  ${v.char}  ${v.width}  ${v.context}');
    }
    expect(violations, isEmpty);
  });

  test('比一整行还长的不可断字串会被强制拆开，这时标点可能落到行首', () {
    // 测试字体里每个字母都是一个字宽：「reader-1.5.10.zip；」排在第三行，18 个字宽，比 320.5 宽，中间又没有可断的位置。
    final violations = checkLineBreaks(
      ['甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉下载了 reader-1.5.10.zip；甲乙丙丁戊己庚辛'],
      const TypesetStyle(),
      320.5,
    );
    expect([for (final v in violations) v.context], ['10.zip|；甲乙丙丁戊']);
  });
}
