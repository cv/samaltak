#!/bin/sh
# Every project function (.pi/functions/**/*.ts) parses as TypeScript, as pi must to load it: gate.ts once shipped a
# shell ${a#OUT=} inside a JS template literal, and pi could not load any of them. Parses with bun's transpiler, else
# node's type stripping (node 22.13 or later, then a vm.Script of what is left); with neither it says so and passes,
# so a machine without them (CI) does not fail.
# usage: tests/tools/pi_functions_test.sh [DIR]   (default .pi/functions)
dir=${1:-.pi/functions}
files=$(find "$dir" -name '*.ts' -type f | sort)
[ -n "$files" ] || { echo "pi functions: no .ts files under $dir" >&2; exit 1; }
if command -v bun >/dev/null 2>&1; then
  tool=bun
  check() { bun -e 'const t = new Bun.Transpiler({ loader: "ts" }); t.transformSync(await Bun.file(process.argv[1]).text())' "$1"; }
elif command -v node >/dev/null 2>&1 && node -e 'process.exit(typeof require("node:module").stripTypeScriptTypes === "function" ? 0 : 1)' 2>/dev/null; then
  tool=node
  check() { node --no-warnings -e 'const fs = require("node:fs"), f = process.argv[1]; new (require("node:vm").Script)(require("node:module").stripTypeScriptTypes(fs.readFileSync(f, "utf8")), { filename: f })' "$1"; }
else
  echo "pi functions: skipped (neither bun nor node 22.13+ with type stripping to parse TypeScript)"
  exit 0
fi
n=0 bad=0
for f in $files; do
  n=$((n + 1))
  if ! out=$(check "$f" 2>&1); then
    bad=$((bad + 1))
    echo "pi functions: $f does not parse ($tool):" >&2
    printf '%s\n' "$out" | head -12 >&2
  fi
done
[ "$bad" -eq 0 ] || { echo "pi functions: FAILED: $bad of $n files do not parse" >&2; exit 1; }
echo "pi functions: $n files parse ($tool)"
