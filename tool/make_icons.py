#!/usr/bin/env python3
"""Generates the app icons (needs Pillow). The results are committed, CI does not run this."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 2048  # supersampled canvas; coordinates below are in a 1024 space
K = SS / 1024
DY = -15   # centre the glyph vertically


def pt(x, y):
    return (x * K, (y + DY) * K)


def box(x0, y0, x1, y1):
    return [x0 * K, (y0 + DY) * K, x1 * K, (y1 + DY) * K]


def glyph_mask():
    """White glyph (controller + upload arrow) with the buttons cut out, as an 'L' mask."""
    m = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(m)
    # controller body and grips
    d.rounded_rectangle(box(192, 470, 832, 790), radius=160 * K, fill=255)
    d.ellipse(box(175, 635, 425, 885), fill=255)
    d.ellipse(box(599, 635, 849, 885), fill=255)
    # upload arrow
    d.polygon([pt(512, 170), pt(612, 290), pt(412, 290)], fill=255)
    d.rectangle(box(482, 290, 542, 400), fill=255)
    # cut-outs: d-pad and four buttons
    d.rectangle(box(270, 590, 390, 630), fill=0)
    d.rectangle(box(310, 550, 350, 670), fill=0)
    for cx, cy in [(646, 610), (742, 610), (694, 562), (694, 658)]:
        d.ellipse(box(cx - 26, cy - 26, cx + 26, cy + 26), fill=0)
    return m


def gradient(size):
    """Diagonal blue gradient."""
    import numpy as np
    y, x = np.mgrid[0:size, 0:size]
    t = (x + y) / (2.0 * (size - 1))
    c0 = np.array([42, 99, 255], dtype=float)
    c1 = np.array([11, 31, 107], dtype=float)
    arr = (c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]).astype("uint8")
    return Image.fromarray(arr, "RGB")


def full_icon(mask, size, rounded):
    bg = gradient(SS).convert("RGBA")
    white = Image.new("RGBA", (SS, SS), (255, 255, 255, 255))
    bg.paste(white, (0, 0), mask)
    if rounded:
        r = Image.new("L", (SS, SS), 0)
        ImageDraw.Draw(r).rounded_rectangle([0, 0, SS - 1, SS - 1], radius=int(SS * 0.22), fill=255)
        bg.putalpha(r)
    return bg.resize((size, size), Image.LANCZOS)


def foreground(mask, size):
    """Adaptive-icon foreground: glyph inside the safe zone on a transparent canvas."""
    bbox = mask.getbbox()
    g = mask.crop(bbox)
    target = int(size * 0.60)
    scale = target / max(g.size)
    g = g.resize((max(1, int(g.width * scale)), max(1, int(g.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    white = Image.new("RGBA", g.size, (255, 255, 255, 255))
    out.paste(white, ((size - g.width) // 2, (size - g.height) // 2), g)
    return out


def main():
    mask = glyph_mask()
    res = os.path.join(ROOT, "native", "res")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    fg = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for d, s in legacy.items():
        p = os.path.join(res, f"mipmap-{d}")
        os.makedirs(p, exist_ok=True)
        full_icon(mask, s, rounded=True).save(os.path.join(p, "ic_launcher.png"))
        foreground(mask, fg[d]).save(os.path.join(p, "ic_launcher_foreground.png"))
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    os.makedirs(os.path.join(res, "values"), exist_ok=True)
    with open(os.path.join(res, "values", "ic_launcher_background.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#1B3FD8</color>\n'
                '</resources>\n')
    # iOS: 1024 px, opaque, square (iOS applies its own mask)
    ios = full_icon(mask, 1024, rounded=False).convert("RGB")
    ios.save(os.path.join(ROOT, "native", "ios_icon", "icon-1024.png"))
    # repository icon (AltStore/SideStore source)
    full_icon(mask, 512, rounded=True).save(os.path.join(ROOT, "assets", "icon", "icon.png"))
    print("icons written")


if __name__ == "__main__":
    main()
