#!/usr/bin/env bash
# Compile src/*.ts and copy the static files alongside. See docs/building.md.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="out/extension"
rm -rf "$OUT"
npx tsc
mkdir -p "$OUT"
cp src/manifest.json "$OUT/manifest.json"
cp -R src/icons "$OUT/icons"

version="$(python3 -c "import json;print(json.load(open('$OUT/manifest.json'))['version'])")"
package_version="$(python3 -c "import json;print(json.load(open('package.json'))['version'])")"
if [ "$version" != "$package_version" ]; then
  printf 'REFUSING: src/manifest.json is v%s and package.json is v%s.\n' \
    "$version" "$package_version" >&2
  printf 'They have to agree -- install.sh labels the build from the manifest alone.\n' >&2
  exit 1
fi

printf 'built %s (v%s)\n' "$OUT" "$version"
ls "$OUT"
