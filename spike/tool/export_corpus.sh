#!/bin/sh
# 排版验证用的真实网文：从 macOS 上真实书源走查留下的数据库里导出几章，写到 assets/corpus.txt。
# 正文有版权，导出结果不进仓库（见 .gitignore）。每章以「=== 章节名」开头，之后一行一段。
set -e
db="$HOME/Library/Containers/dev.novelreader.app/Data/Library/Caches/walkthrough.sqlite"
out="$(dirname "$0")/../assets/corpus.txt"
sqlite3 -newline '' "$db" "
  select '=== ' || title || char(10) || content || char(10) from contents
  where (book_url like '%biduju%') or (book_url like '%duokan%')
  order by book_url, title" > "$out"
wc -m "$out"
