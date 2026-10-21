#!/usr/bin/env bash
# Tests live at the CONFIG ROOT, not in tests/: Quickshell resolves relative
# imports from the importing file's own directory and will not traverse ".."
# out of the config subtree, so a test in tests/ cannot import "core".
set -euo pipefail
cd "$(dirname "$0")"
fail=0
for t in test-*.qml; do
  out=$(timeout 120 qs -p "$t" 2>&1 | grep -E "PASS|FAIL|=== " || true)
  printf '%s\n' "$out"
  printf '%s' "$out" | grep -q "FAIL" && fail=1
done
exit $fail
