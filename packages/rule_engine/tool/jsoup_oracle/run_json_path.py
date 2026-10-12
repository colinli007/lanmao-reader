"""用 Jayway json-path 3.0.0 生成 JSONPath 对照用例的期望值。

用法：python3 -I run_json_path.py <cases.py> <输出 json>
cases.py 里定义 CASES = [(JSON 文档, 路径, 说明), ...]
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
    for doc, path, _ in cases:
        f.write(b64(doc) + '\t' + b64(path) + '\n')
jars = ['json-path-3.0.0.jar', 'json-smart-2.6.0.jar', 'accessors-smart-2.6.0.jar', 'asm-9.7.1.jar', 'slf4j-api-2.0.17.jar']
cp = ':'.join([here] + [os.path.join(here, j) for j in jars])
subprocess.run(['java', '-cp', cp, 'JsonPathOracle', tsv, outp], check=True, stderr=subprocess.DEVNULL)
fixtures = []
for (doc, path, note), line in zip(cases, open(outp).read().split('\n')):
    definite, string, items, count = base64.b64decode(line).decode('utf-8').split('\u0003')
    fixtures.append({
        'note': note,
        'doc': doc,
        'path': path,
        'definite': None if definite == 'ERR' else definite == 'true',
        'string': string,
        'list': items.split('\u0001') if int(count) > 0 else [],
    })
with open(sys.argv[2], 'w') as f:
    json.dump({'generator': 'Jayway json-path 3.0.0（tool/jsoup_oracle/JsonPathOracle.java）', 'cases': fixtures}, f, ensure_ascii=False, indent=1)
print(len(fixtures), 'cases')
