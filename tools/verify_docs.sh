#!/bin/sh
# 证明构建/测试不写入 docs/：构建前后对 docs/ 做 SHA-256 清单并比较。
set -eu
cd "$(dirname "$0")/.."
zig build docs-hash >/dev/null
cp docs.sha256.current docs.sha256.before
zig build
zig build test
zig build test-golden
zig build test-replay
zig build check-docs
zig build docs-hash >/dev/null
if cmp -s docs.sha256.before docs.sha256.current; then
  echo "verify-docs: docs/ 未变化（$(wc -l < docs.sha256.current) 个文件）"
  rm -f docs.sha256.before
  exit 0
else
  echo "verify-docs: docs/ 发生变化" >&2
  diff -u docs.sha256.before docs.sha256.current >&2 || true
  exit 1
fi
