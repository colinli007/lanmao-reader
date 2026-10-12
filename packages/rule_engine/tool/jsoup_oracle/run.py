"""用 jsoup 1.16.2 生成对照用例的期望值。

用法：python3 -I run.py <cases.py> <输出 json>
cases.py 里定义 CASES = [(op, ctx, arg, html, 说明), ...]
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
    for op, ctx, arg, html, _ in cases:
        f.write('\t'.join([op, b64(ctx), b64(arg), b64(html)]) + '\n')
subprocess.run(['java', '-cp', f'{here}:{here}/jsoup-1.16.2.jar', 'Oracle', tsv, outp], check=True)
results = open(outp).read().split('\n')
fixtures = []
for (op, ctx, arg, html, note), line in zip(cases, results):
    if line.startswith('ERR '):
        expected = {'error': line[4:]}
    else:
        count, text = base64.b64decode(line).decode('utf-8').split('\u0003', 1)
        expected = {'items': text.split('\u0001') if int(count) > 0 else []}
    fixtures.append({'note': note, 'op': op, 'ctx': ctx, 'arg': arg, 'html': html, **expected})
with open(sys.argv[2], 'w') as f:
    json.dump({'generator': 'jsoup 1.16.2（scratchpad 里的 Oracle.java）', 'cases': fixtures}, f, ensure_ascii=False, indent=1)
print(len(fixtures), 'cases')
