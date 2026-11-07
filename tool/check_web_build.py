"""Verifies build/web is publishable. Run by tool/build_web.sh; exits non-zero on any problem.

Checks: every file the service worker precaches exists; every manifest icon / shortcut target is
there; the version was stamped; no text file references an external host; the CSP in index.html
matches web/_headers (minus frame-ancestors); no inline scripts; required files are present.
"""
import json
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "build/web"
problems = []


def fail(msg):
    problems.append(msg)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def exists(rel):
    return os.path.isfile(os.path.join(ROOT, rel))


for required in ("index.html", "manifest.json", "aura_sw.js", "flutter_bootstrap.js", "main.dart.js",
                 "pwa_init.js", "splash.css", "privacy.html", "robots.txt", "_headers",
                 "canvaskit/canvaskit.wasm", "canvaskit/chromium/canvaskit.wasm", "favicon.png",
                 "favicon.ico", "audio_worklet.js", "dsp_worklet.dart.js"):
    if not exists(required):
        fail(f"missing required file: {required}")

# Service worker: stamped, and every precached file is really there.
sw = read("aura_sw.js")
if "__AURA_" in sw:
    fail("aura_sw.js still has unstamped placeholders (build_web.sh stamps it)")
m = re.search(r"const FILES = (\[.*?\]);", sw, re.S)
if not m:
    fail("could not read the precache list from aura_sw.js")
else:
    files = json.loads(m.group(1))
    for f in files:
        rel = "index.html" if f == "./" else f
        if not exists(rel):
            fail(f"service worker precaches a file that does not exist: {f}")
    for must in ("./", "main.dart.js", "flutter_bootstrap.js", "manifest.json", "privacy.html",
                 "assets/AssetManifest.bin.json", "canvaskit/canvaskit.wasm",
                 "audio_worklet.js", "dsp_worklet.dart.js"):
        if must not in files:
            fail(f"service worker does not precache {must}")
    print(f"  service worker precaches {len(files)} files")

# Manifest.
manifest = json.loads(read("manifest.json"))
for icon in manifest.get("icons", []):
    if not exists(icon["src"]):
        fail(f"manifest icon missing: {icon['src']}")
sizes = {i["sizes"] for i in manifest.get("icons", [])}
if not {"192x192", "512x512"} <= sizes:
    fail("manifest needs 192x192 and 512x512 icons")
for sc in manifest.get("shortcuts", []):
    if not re.match(r"^\./\?mode=(sos|focus|calm|deep)$", sc["url"]):
        fail(f"shortcut has an unexpected url: {sc['url']}")

# index.html: no inline scripts, CSP present and consistent with _headers.
index = read("index.html")
if "$FLUTTER_BASE_HREF" in index:
    fail("index.html still contains the $FLUTTER_BASE_HREF placeholder")
for tag in re.findall(r"<script\b([^>]*)>", index):
    if "src=" not in tag:
        fail("index.html has an inline <script> (the CSP forbids it)")
meta = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', index)
hdr = re.search(r"Content-Security-Policy: (.+)", read("_headers"))
if not meta or not hdr:
    fail("CSP missing from index.html or _headers")
else:
    header_csp = hdr.group(1).replace("; frame-ancestors 'none'", "").strip()
    if meta.group(1).strip() != header_csp:
        fail("CSP in index.html differs from _headers")
    for bad in ("unsafe-eval", "http:", "https:", "*"):
        if bad in header_csp.replace("'wasm-unsafe-eval'", ""):
            fail(f"CSP contains {bad!r}")

# No external hosts in anything the browser loads as text.
for rel in ("index.html", "manifest.json", "aura_sw.js", "pwa_init.js", "splash.css", "privacy.html",
            "privacy.css"):
    if not exists(rel):
        continue
    for url in re.findall(r"https?://[^\s\"'<>)]+", read(rel)):
        fail(f"{rel} references an external URL: {url}")

# Version stamped into the Dart build.
main_js = open(os.path.join(ROOT, "main.dart.js"), encoding="utf-8", errors="ignore").read()
if os.environ.get("APP_VERSION") and os.environ["APP_VERSION"] not in main_js:
    fail(f"APP_VERSION {os.environ['APP_VERSION']} was not compiled into main.dart.js")

if problems:
    print("build/web is NOT publishable:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print("  build/web checks passed")
