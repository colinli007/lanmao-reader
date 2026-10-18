"""用 JDK、Hutool 5.8.22 和 AOSP 的 android.util.Base64 生成编码、摘要、加解密、日期格式的期望值。

用法：python3 -I run_codec.py <cases.py> <输出 json>
cases.py 里定义 CASES = [(操作名, [参数, ...], 说明), ...]，操作名和参数的含义见 CodecOracle.java。
输出里 expected 是结果文本（字节数组为小写十六进制）；抛出异常时没有 expected，error 是异常类名。
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

b64 = lambda s: base64.b64encode(str(s).encode('utf-8')).decode()
tsv = os.path.join(here, 'in.tsv')
outp = os.path.join(here, 'out.txt')
with open(tsv, 'w') as f:
    for op, args, _ in cases:
        f.write('\t'.join([op] + [b64(a) for a in args]) + '\n')
subprocess.run(['java', '-cp', os.pathsep.join([here, os.path.join(here, 'hutool-core-5.8.22.jar')]),
                'CodecOracle', tsv, outp], check=True)
fixtures = []
for (op, args, note), line in zip(cases, open(outp).read().split('\n')):
    case = {'note': note, 'op': op, 'args': [str(a) for a in args]}
    if line.startswith('!'):
        case['error'] = line[1:]
    else:
        case['expected'] = base64.b64decode(line).decode('utf-8')
    fixtures.append(case)
with open(sys.argv[2], 'w') as f:
    json.dump({'generator': 'JDK / Hutool 5.8.22 / AOSP android.util.Base64（tool/jsoup_oracle/CodecOracle.java）',
               'cases': fixtures}, f, ensure_ascii=False, indent=1)
print(len(fixtures), 'cases')
