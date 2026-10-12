"""用 JsoupXpath 2.5.5 生成 XPath 对照用例的期望值。

用法：python3 -I run_xpath.py <cases.py> <输出 json>
cases.py 里定义 CASES = [(上下文 CSS 选择器, XPath, HTML, 说明), ...]
"""
import base64
import importlib.util
import json
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('cases', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
cases = module.CASES

b64 = lambda s: base64.b64encode(s.encode('utf-8')).decode()
tsv = os.path.join(here, 'in.tsv')
outp = os.path.join(here, 'out.txt')
with open(tsv, 'w') as f:
    for ctx, xpath, html, _ in cases:
        f.write('\t'.join([b64(ctx), b64(xpath), b64(html)]) + '\n')
jars = ['JsoupXpath-2.5.5.jar', 'jsoup-1.16.2.jar', 'commons-lang3-3.12.0.jar', 'antlr4-runtime-4.7.2.jar', 'slf4j-api-2.0.17.jar']
cp = ':'.join([here] + [os.path.join(here, j) for j in jars])
subprocess.run(['java', '-cp', cp, 'XPathOracle', tsv, outp], check=True, stderr=subprocess.DEVNULL)
fixtures = []
for (ctx, xpath, html, note), line in zip(cases, open(outp).read().split('\n')):
    case = {'note': note, 'ctx': ctx, 'xpath': xpath, 'html': html}
    if line == 'ERR':
        case['error'] = True
    else:
        count, text = base64.b64decode(line).decode('utf-8').split('\u0003', 1)
        case['items'] = text.split('\u0001') if int(count) > 0 else []
    fixtures.append(case)
with open(sys.argv[2], 'w') as f:
    json.dump({'generator': 'JsoupXpath 2.5.5（tool/jsoup_oracle/XPathOracle.java）', 'cases': fixtures}, f, ensure_ascii=False, indent=1)
print(len(fixtures), 'cases')
