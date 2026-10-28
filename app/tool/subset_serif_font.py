"""裁出书名、标题用的衬线字体（redesign-cinema-ui 设计 D2）。

源文件是 Noto Serif SC Black（https://github.com/notofonts/noto-cjk 的 Serif/SubsetOTF/SC/NotoSerifSC-Black.otf），
只留 GB2312 里的字符（6763 个汉字和全角符号）、ASCII 和常用中文标点，其余的字由系统字体补上。

用法（需要 fonttools：pip install fonttools）：
    python3 tool/subset_serif_font.py <NotoSerifSC-Black.otf>
在 app/ 下运行，输出 assets/fonts/NotoSerifSC-Black-subset.otf。
"""

import subprocess
import sys
from pathlib import Path

OUTPUT = Path('assets/fonts/NotoSerifSC-Black-subset.otf')


def gb2312() -> str:
    """GB2312 的全部字符：符号区 A1–A9，汉字区 B0–F7。"""
    chars = []
    for high in [*range(0xA1, 0xAA), *range(0xB0, 0xF8)]:
        for low in range(0xA1, 0xFF):
            try:
                chars.append(bytes([high, low]).decode('gb2312'))
            except UnicodeDecodeError:
                pass
    return ''.join(chars)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ascii_chars = ''.join(chr(c) for c in range(0x20, 0x7F))
    punctuation = '，。、；：？！“”‘’（）《》〈〉【】「」『』—…·～　'
    text = ascii_chars + punctuation + gb2312()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            'pyftsubset',
            sys.argv[1],
            f'--text={text}',
            f'--output-file={OUTPUT}',
            '--layout-features=kern,palt,vpal',
            '--no-hinting',
        ],
        check=True,
    )
    print(f'{OUTPUT}：{OUTPUT.stat().st_size / 1000:.0f} KB，{len(set(text))} 个字符')


if __name__ == '__main__':
    main()
