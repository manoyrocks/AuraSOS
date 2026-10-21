#!/usr/bin/env bash
# Builds the offline PWA into build/web, stamps the service worker with the file list and a
# content-hash version, and verifies the result.
#
# Usage: tool/build_web.sh [--base-href /subpath/] [extra flutter build args]
#   Hosting at the domain root needs no flags. For a sub-path (GitHub Pages project sites) pass
#   --base-href /name/  (leading and trailing slash).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
export APP_VERSION
echo "Building AuraSOS $APP_VERSION for the web"

flutter build web --release --no-web-resources-cdn --no-wasm-dry-run \
  --dart-define=APP_VERSION="$APP_VERSION" "$@"

python3 - <<'PY'
import hashlib, json, os

root = "build/web"
files = []
for base, _, names in os.walk(root):
    for n in sorted(names):
        rel = os.path.relpath(os.path.join(base, n), root).replace(os.sep, "/")
        if n.startswith(".") or rel in ("aura_sw.js", "flutter_service_worker.js", "version.json", "_headers"):
            continue
        if rel.endswith((".symbols", ".map")) or n.startswith("skwasm"):
            continue  # the app ships the CanvasKit renderer only
        files.append(rel)
files.sort()

h = hashlib.sha256()
for rel in files:
    h.update(rel.encode())
    with open(os.path.join(root, rel), "rb") as f:
        h.update(hashlib.sha256(f.read()).digest())
version = h.hexdigest()[:12]

# Navigations to "/" must also resolve from the cache.
precache = ["./"] + files
sw_path = os.path.join(root, "aura_sw.js")
src = open(sw_path).read()
src = src.replace("__AURA_VERSION__", version).replace("__AURA_FILES__", json.dumps(precache, indent=1))
open(sw_path, "w").write(src)

size = sum(os.path.getsize(os.path.join(root, r)) for r in files)
print(f"service worker stamped: cache version {version}, {len(precache)} files, {size/1e6:.1f} MB precached")
PY

python3 tool/check_web_build.py build/web
echo "Ready to publish: build/web  (see docs/PUBLISHING.md)"
