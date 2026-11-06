"""用已下载的 jsoup 1.16.2 JAR 生成实体解码边界期望值。

用法：python3 -I run_entities.py ../../test/fixtures/jsoup_entities_cases.json [--all-entities]
--all-entities 额外对照 Dart 当前 html 依赖的全部实体与后缀组合，不把这批大样本写入 fixture。
"""
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile

texts = [
    '<b>&amp; &lt;i&gt; &quot; &apos;</b>\r\n\t\x00',
    '&nbsp; &copy; &lang; &rang; &NotEqualTilde; &fjlig; &Afr;',
    '&AMP; &Amp; &unknown; &; &&amp; &amp;amp;',
    '&copy &not &notin &notin; &apos &apos;',
    '&notit; &ampx &amp1; &frac12x &frac12三 &amp三 &amp𝒜',
    '&amp=1 &amp-1 &amp_1 &amp! &amp;=1 &amp;-1 &amp;_1',
    '&#65; &#65 &#x41; &#X41 &#x1F600; &#0; &#xD800; &#x110000;',
    '&#; &#x; &#-1; &#x-1; &#999999999999999999999; &#00000000000000000000065;',
    '&#xFFFFFFFFFFFFFFFF; &#x8000000000000000; &#x00000000000000000041;',
    '&#１２; &#١٢; &#12３; &frac12３ &amp１２;',
    ''.join(f'&#{n};' for n in range(128, 160)),
    '&#13;\r\n&#xFFFF; &#x10FFFF; &#xFFFE; &#1; &#11; &#127;',
    '甲乙\r\n原文 <script>x < 2 && a > 1;</script>',
]
cases = [{'input': text, 'inAttribute': attribute} for text in texts for attribute in (False, True)]
boundary_count = len(cases)
here = Path(__file__).resolve().parent
b64 = lambda text: base64.b64encode(text.encode()).decode()
with tempfile.TemporaryDirectory(prefix='jsoup-entities-') as tmp:
    tmp = Path(tmp)
    if '--all-entities' in sys.argv[2:]:
        dart = tmp / 'all_entities.dart'
        dart.write_text('''
import 'dart:convert';
import 'dart:io';
import 'package:html/src/constants.dart' show entities;
import 'package:rule_engine/src/html/jsoup_entities.dart';
void main() {
  final cases = [
    for (final name in entities.keys)
      for (final suffix in ['', '=', '-', '_', 'x', '三', '𝒜'])
        for (final attr in [false, true])
          {'input': '&$name$suffix', 'inAttribute': attr,
           'actual': unescapeJsoupEntities('&$name$suffix', attr)}
  ];
  stdout.write(jsonEncode(cases));
}
''')
        config = here.parent.parent / '.dart_tool/package_config.json'
        result = subprocess.run(['dart', f'--packages={config}', str(dart)], capture_output=True, text=True, check=True)
        cases.extend(json.loads(result.stdout))
    subprocess.run(['javac', '-cp', str(here / 'jsoup-1.16.2.jar'), '-d', str(tmp), str(here / 'EntitiesOracle.java')], check=True)
    (tmp / 'in.tsv').write_text(''.join(f'{str(c["inAttribute"]).lower()}\t{b64(c["input"])}\n' for c in cases))
    subprocess.run(['java', '-cp', f'{tmp}:{here / "jsoup-1.16.2.jar"}', 'EntitiesOracle', str(tmp / 'in.tsv'), str(tmp / 'out.txt')], check=True)
    for case, result in zip(cases, (tmp / 'out.txt').read_text().splitlines(), strict=True):
        case['expected'] = base64.b64decode(result).decode()
        if 'actual' in case and case['actual'] != case['expected']:
            raise AssertionError(case)
Path(sys.argv[1]).write_text(json.dumps({'generator': 'jsoup 1.16.2 EntitiesOracle.java', 'cases': cases[:boundary_count]}, ensure_ascii=False, indent=2) + '\n')
print(f'{boundary_count} boundary cases; {len(cases) - boundary_count} entity combinations verified')
