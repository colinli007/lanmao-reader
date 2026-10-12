"""用 java.net.URL 生成相对地址拼接的期望值。

用法：python3 -I run_url.py <cases.py> <输出 json>
cases.py 里定义 CASES = [(基准地址, 相对地址, 说明), ...]
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
    for base, rel, _ in cases:
        f.write(b64(base) + '\t' + b64(rel) + '\n')
subprocess.run(['java', '-cp', here, 'UrlOracle', tsv, outp], check=True)
fixtures = [
    {'note': note, 'base': base, 'relative': rel, 'expected': base64.b64decode(line).decode('utf-8')}
    for (base, rel, note), line in zip(cases, open(outp).read().split('\n'))
]
with open(sys.argv[2], 'w') as f:
    json.dump({'generator': 'java.net.URL（tool/jsoup_oracle/UrlOracle.java）', 'cases': fixtures}, f, ensure_ascii=False, indent=1)
print(len(fixtures), 'cases')
