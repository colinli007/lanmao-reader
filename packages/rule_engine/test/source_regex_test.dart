import 'package:rule_engine/src/regex/java_replace.dart';
import 'package:rule_engine/src/regex/source_regex.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

void main() {
  late FakeEnvironment env;

  setUp(() => env = FakeEnvironment());
  tearDown(() => env.dispose());

  String replace(String input, String pattern, String replacement, {bool firstOnly = false}) =>
      replaceByRule(env, input, pattern, replacement, firstOnly: firstOnly);

  group('Java 正则转换', () {
    test(r'\h 在字符类内外', () {
      expect(translateJavaRegex(r'a\hb').$1, r'a[ \t  ᠎ -   　]b');
      expect(translateJavaRegex(r'[、\h]').$1, r'[、 \t  ᠎ -   　]');
      expect(replace('第1章　标题', r'\h', '-'), '第1章-标题');
      expect(replace('a b\tc', r'\H', ''), ' \t');
    });

    test('占有量词降为贪婪量词', () {
      expect(translateJavaRegex('(^|[。！？]++”?+)').$1, '(^|[。！？]+”?)');
      expect(translateJavaRegex(r'a*+b{2,3}+c?+').$1, r'a*b{2,3}c?');
      // 懒惰量词、转义的加号、字符类里的加号都不动
      expect(translateJavaRegex(r'a+?\++[+]+').$1, r'a+?\++[+]+');
    });

    test('开头的内联标志转成标志', () {
      final (source, flags) = translateJavaRegex('(?i)(?s)abc');
      expect(source, 'abc');
      expect(flags, (ignoreCase: true, multiLine: false, dotAll: true));
      expect(translateJavaRegex('(?im)x').$2, (ignoreCase: true, multiLine: true, dotAll: false));
      expect(replace('ABC\nabc', '(?i)b', '-'), 'A-C\na-c');
      expect(replace('a\nb', '(?s)a.b', 'x'), 'x');
    });

    test('\\d、\\w 按 Android（ICU）的 Unicode 语义', () {
      expect(replace('第１２章', r'\d+', 'N'), '第N章');
      expect(replace('三体 abc_1', r'\w+', 'W'), 'W W');
      expect(replace('a１b', r'\D', '-'), '-１-');
      expect(replace('三体,x', r'\W', '|'), '三体|x');
      expect(replace('a1三', r'[\d]', '#'), 'a#三');
    });

    test('整串匹配不受多行标志影响', () {
      final regex = SourceRegex.tryCompile(r'(?m)https://a\.com/book/\d+\.html')!;
      expect(regex.matchesEntire(env, 'https://a.com/book/1.html'), isTrue);
      expect(regex.matchesEntire(env, 'https://a.com/book/1.html?x'), isFalse);
      expect(regex.matchesEntire(env, 'x\nhttps://a.com/book/1.html'), isFalse);
      expect(SourceRegex.tryCompile('a|ab')!.matchesEntire(env, 'ab'), isTrue);
    });
  });

  group('替换串按 Java 语法展开', () {
    test(r'$n 和 ${name}', () {
      expect(replace('12-34', r'(\d+)-(\d+)', r'$2-$1'), '34-12');
      expect(replace('ab', r'(?<x>a)(b)', r'${x}$2${x}'), 'aba');
    });

    test(r'$n 不超过分组数，多出的数字是字面量', () {
      expect(replace('a', '(a)', r'$12'), 'a2');
    });

    test(r'\ 转义', () {
      expect(replace('a', 'a', r'\$1\\'), r'$1\');
    });

    test('未参与匹配的组替换为空', () {
      expect(replace('a', '(a)|(b)', r'[$2]'), '[]');
    });

    test('替换串不合法时退化为字面量替换', () {
      expect(replace('a(a)', '(a)', r'$x'), r'a$x');
      expect(replace('a', 'a', r'b\'), r'b\');
      expect(replace('a', 'a', r'$2'), r'$2');
      // 没有匹配时 Java 不检查替换串
      expect(replace('a', 'z', r'$9'), 'a');
    });

    test('正则编译不了时退化为字面量替换', () {
      expect(replace('a[未闭合b', '[未闭合', ''), 'ab');
    });
  });

  group('只取第一个匹配', () {
    test('结果是第一个匹配替换后的文本', () {
      expect(replace(r'共 12章 / 34章', r'(\d+)章', r'第$1章', firstOnly: true), '第12章');
    });

    test('没有匹配时为空', () {
      expect(replace('abc', r'\d', 'x', firstOnly: true), '');
    });

    test('正则或替换串不合法时结果是替换串', () {
      expect(replace('abc', '[', 'x', firstOnly: true), 'x');
      expect(replace('abc', 'a', r'$5', firstOnly: true), r'$5');
    });
  });

  // 摘自 aoaostar/legado 的 A 类书源，括号里是规则所在的字段
  group('真实净化规则', () {
    test('删除书名后的推广（ruleToc.chapterName）', () {
      expect(replace('第一章 开始（求月票）', r'[\(（【].*?[求更票谢乐发订合补加Kk].*?[】）\)]', ''), '第一章 开始');
    });

    test('从详情地址拼封面（ruleSearch.coverUrl）', () {
      expect(
        replace('/book/12345/', r'/book/(\d+)(\d{3})/', r'/files/article/image/$1/$1$2/$1$2s.jpg'),
        '/files/article/image/12/12345/12345s.jpg',
      );
    });

    test('嵌套分组拼封面并只取第一个匹配（ruleSearch.coverUrl）', () {
      expect(
        replace(
          'https://m.x.net/12345/',
          r'.+\D((\d+)\d{3})\D',
          r'https://images.shoujixs.net/$2/$1/$1s.jpg',
          firstOnly: true,
        ),
        'https://images.shoujixs.net/12/12345/12345s.jpg',
      );
    });

    test('取字数（ruleBookInfo.wordCount）', () {
      expect(replace('<p>字数：12万</p>', r'字数.([^<]+)', r'$1', firstOnly: true), '12万');
    });

    test('多个前缀去掉（ruleSearch.lastChapter）', () {
      expect(replace('免费章节 第十章 正文 尾声', '免费章节 |正文卷 |正文 |VIP章节 ', ''), '第十章 尾声');
    });

    test('句末换行（ruleBookInfo.intro）', () {
      expect(replace('他说：“走！”然后。好', r'(^|[。！？]+[”」）】]?)', r'$1<br>'), '<br>他说：“走！”<br>然后。<br>好');
    });

    test('占有量词的句末换行（ruleBookInfo.intro）', () {
      expect(replace('走！！”好。', '(^|[。！？]++”?+)', r'$1<br>'), '<br>走！！”<br>好。<br>');
    });

    test('删除广告行（ruleContent.content）', () {
      expect(replace('正文\n一秒记住本站\n', '一秒记住.*|www.*', ''), '正文\n\n');
    });

    test('作者前缀和分隔（ruleSearch.author）', () {
      expect(replace('作者：张三<br>', '作者：([^<]+)<', r'$1', firstOnly: true), '张三');
    });

    test('水平空白（ruleSearch.name）', () {
      expect(replace('三体 作者：刘慈欣\n', r'.+\h作者：\S{1,5}\n', 'x'), 'x');
    });
  });

  test('灾难性回溯可以被取消', () {
    env.cancel();
    expect(() => replace('a' * 30, r'(a+)+b', ''), throwsA(isA<CancelledForTest>()));
  });
}
