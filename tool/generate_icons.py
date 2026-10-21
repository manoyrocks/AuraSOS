"""Generates every AuraSOS app icon from one design (heart with calming ripples on a dark gradient).

  python3 tool/generate_icons.py

Writes: web/ (PWA icons + favicon), ios/Runner/Assets.xcassets/AppIcon.appiconset (every size in
Contents.json, opaque as the App Store requires) and android/app/src/main/res (legacy launcher
icons, adaptive-icon foreground and the monochrome layer for themed icons).
Pure Python + macOS `sips` for resizing; no other dependencies.
"""
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BG_TOP = (0x14, 0x1E, 0x38)
BG_BOT = (0x0B, 0x12, 0x20)
G1 = (0xF4, 0x86, 0x7D)
G2 = (0xC9, 0x4A, 0x5A)


def heart(x, y):
    return (x * x + y * y - 1) ** 3 - x * x * y ** 3


def render(size, hs, rings, mode, rounded=False, ss=3):
    """Returns RGBA rows. mode: 'full' opaque design, 'fg' transparent foreground, 'mono' alpha-only."""
    rows = []
    corner = size * 0.22
    for py in range(size):
        row = bytearray()
        for px in range(size):
            a_mask = 1.0
            if rounded:
                cx = min(px + 0.5, size - px - 0.5)
                cy = min(py + 0.5, size - py - 0.5)
                if cx < corner and cy < corner:
                    d = math.hypot(corner - cx, corner - cy)
                    a_mask = max(0.0, min(1.0, corner - d + 0.5))
            h_cov = 0
            r_cov = [0] * len(rings)
            for sy in range(ss):
                for sx in range(ss):
                    u = ((px + (sx + 0.5) / ss) / size - 0.5) * 2
                    v = ((py + (sy + 0.5) / ss) / size - 0.5) * 2
                    if heart(u / hs, -(v / hs) + 0.12) <= 0:
                        h_cov += 1
                    dist = math.hypot(u, v - 0.02)
                    for k, (rad, w, _) in enumerate(rings):
                        if abs(dist - rad) <= w / 2:
                            r_cov[k] += 1
            n = ss * ss
            h = h_cov / n
            gt = min(1.0, max(0.0, (py / size - 0.2) / 0.6))
            heart_rgb = [G1[i] * (1 - gt) + G2[i] * gt for i in range(3)]
            ring_a = [r_cov[k] / n * rings[k][2] for k in range(len(rings))]

            if mode == "full":
                t = py / size
                col = [BG_TOP[i] * (1 - t) + BG_BOT[i] * t for i in range(3)]
                for ra in ring_a:
                    col = [col[i] * (1 - ra) + 255 * ra for i in range(3)]
                col = [col[i] * (1 - h) + heart_rgb[i] * h for i in range(3)]
                row += bytes(round(c) for c in col) + bytes([round(255 * a_mask)])
            elif mode == "fg":
                ra = 1.0
                for r in ring_a:
                    ra *= 1 - r
                ring_alpha = 1 - ra
                out_a = h + ring_alpha * (1 - h)
                if out_a <= 0:
                    row += bytes([0, 0, 0, 0])
                else:
                    rgb = [(heart_rgb[i] * h + 255 * ring_alpha * (1 - h)) / out_a for i in range(3)]
                    row += bytes(round(c) for c in rgb) + bytes([round(255 * out_a)])
            else:  # mono: shape only, the system tints it
                ring_alpha = max(ring_a) if ring_a else 0
                alpha = max(h, ring_alpha * 0.9)
                row += bytes([255, 255, 255, round(255 * alpha)])
        rows.append(bytes(row))
    return rows


def write_png(path, size, rows, with_alpha=True):
    raw = bytearray()
    for r in rows:
        raw.append(0)
        if with_alpha:
            raw += r
        else:
            raw += b"".join(r[i:i + 3] for i in range(0, len(r), 4))
    ctype = 6 if with_alpha else 2

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, ctype, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def resize(src, dst, px):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["sips", "-s", "format", "png", "-z", str(px), str(px), src, "--out", dst],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    tmp = tempfile.mkdtemp(prefix="aura_icons_")
    p = lambda *a: os.path.join(ROOT, *a)

    any_rings = [(0.78, 0.028, 0.30), (0.92, 0.028, 0.14)]
    mask_rings = [(0.60, 0.024, 0.30), (0.72, 0.024, 0.14)]

    print("web icons")
    for size in (192, 512):
        write_png(p("web/icons", f"Icon-{size}.png"), size, render(size, 0.46, any_rings, "full", rounded=True))
        write_png(p("web/icons", f"Icon-maskable-{size}.png"), size, render(size, 0.34, mask_rings, "full"))
    write_png(p("web/favicon.png"), 64, render(64, 0.62, [], "full", rounded=True))
    png = open(p("web/favicon.png"), "rb").read()
    with open(p("web/favicon.ico"), "wb") as f:
        f.write(struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 64, 64, 0, 0, 1, 32, len(png), 22) + png)

    print("iOS app icon set (opaque, full-bleed: iOS applies its own rounding)")
    master = os.path.join(tmp, "ios_1024.png")
    write_png(master, 1024, render(1024, 0.46, any_rings, "full", ss=2), with_alpha=False)
    iconset = p("ios/Runner/Assets.xcassets/AppIcon.appiconset")
    contents = json.load(open(os.path.join(iconset, "Contents.json")))
    for img in contents["images"]:
        base = float(img["size"].split("x")[0])
        scale = int(img["scale"].rstrip("x"))
        px = round(base * scale)
        dst = os.path.join(iconset, img["filename"])
        if px == 1024:
            os.replace(master, dst)
            subprocess.run(["cp", dst, master], check=True)
        else:
            resize(master, dst, px)

    print("Android legacy launcher icons")
    legacy = os.path.join(tmp, "legacy_512.png")
    write_png(legacy, 512, render(512, 0.46, any_rings, "full", rounded=True))
    res = p("android/app/src/main/res")
    for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        resize(legacy, os.path.join(res, f"mipmap-{density}", "ic_launcher.png"), px)

    print("Android adaptive icon layers")
    fg_rings = [(0.50, 0.02, 0.30), (0.58, 0.02, 0.14)]
    fg = os.path.join(tmp, "fg_432.png")
    mono = os.path.join(tmp, "mono_432.png")
    write_png(fg, 432, render(432, 0.34, fg_rings, "fg"))
    write_png(mono, 432, render(432, 0.34, fg_rings, "mono"))
    for density, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)):
        d = os.path.join(res, f"drawable-{density}")
        if px == 432:
            os.makedirs(d, exist_ok=True)
            subprocess.run(["cp", fg, os.path.join(d, "ic_launcher_foreground.png")], check=True)
            subprocess.run(["cp", mono, os.path.join(d, "ic_launcher_monochrome.png")], check=True)
        else:
            resize(fg, os.path.join(d, "ic_launcher_foreground.png"), px)
            resize(mono, os.path.join(d, "ic_launcher_monochrome.png"), px)
    print("iOS launch image (the heart, centred on the dark launch screen)")
    launch = p("ios/Runner/Assets.xcassets/LaunchImage.imageset")
    for name, px in (("LaunchImage.png", 144), ("LaunchImage@2x.png", 288), ("LaunchImage@3x.png", 432)):
        resize(fg, os.path.join(launch, name), px)
    print("done")


if __name__ == "__main__":
    sys.exit(main())
