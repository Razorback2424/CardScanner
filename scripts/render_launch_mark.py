#!/usr/bin/env python3
"""Render LaunchMark: AppOpeningView's first frame (front card + seeking guides).

Requires Pillow. Usage:
    scripts/render_launch_mark.py TradingCardScanner/Assets.xcassets/LaunchMark.imageset

Keep the geometry and colors in step with OpeningGeometry/OpeningPalette in
TradingCardScanner/Views/AppOpeningView.swift.
"""
import sys
from PIL import Image, ImageDraw, ImageChops

SS = 4  # supersampling
CARD_W, CARD_H, CARD_R, INSET = 132, 185, 12, 12
TOP = (0.33, 0.58, 1.00)
BOTTOM = (0.02, 0.30, 0.94)

def rgb(c): return tuple(round(v * 255) for v in c)

def rounded_mask(size, box, radius, scale):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([v * scale for v in box], radius=radius * scale, fill=255)
    return m

def render(pt_scale):
    s = pt_scale * SS
    W, H = (CARD_W + 2 * INSET), (CARD_H + 2 * INSET)
    size = (W * s, H * s)
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    card = (INSET, INSET, INSET + CARD_W, INSET + CARD_H)

    # Card fill: linear gradient topLeading -> bottomTrailing (SwiftUI projects onto (w, h)).
    cw, ch = CARD_W * s, CARD_H * s
    grad = Image.new('RGB', (cw, ch))
    px = grad.load()
    denom = cw * cw + ch * ch
    top, bottom = rgb(TOP), rgb(BOTTOM)
    hl = []
    for y in range(ch):
        for x in range(cw):
            t = (x * cw + y * ch) / denom
            base = [top[i] + (bottom[i] - top[i]) * t for i in range(3)]
            a = 0.22 * max(0.0, 1 - t / 0.5)  # glass highlight overlay
            px[x, y] = tuple(round(b + (255 - b) * a) for b in base)
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    layer.paste(grad, (INSET * s, INSET * s))
    layer.putalpha(rounded_mask(size, card, CARD_R, s))
    out = Image.alpha_composite(out, layer)

    def stroke_border(box, radius, width, alpha):
        outer = rounded_mask(size, box, radius, s)
        inner_box = (box[0] + width, box[1] + width, box[2] - width, box[3] - width)
        inner = rounded_mask(size, inner_box, max(radius - width, 0), s)
        ring = ImageChops.subtract(outer, inner).point(lambda v: round(v * alpha))
        white = Image.new('RGBA', size, (255, 255, 255, 0))
        white.putalpha(ring)
        return Image.alpha_composite(out, white)

    out = stroke_border((card[0] + 9, card[1] + 9, card[2] - 9, card[3] - 9), 6, 1, 0.45)
    out = stroke_border(card, CARD_R, 2, 0.9)

    # CornerGuides at the seeking inset, white 70%.
    guides = Image.new('L', size, 0)
    d = ImageDraw.Draw(guides)
    b = (1.5, 1.5, W - 1.5, H - 1.5)
    length, radius, lw = 22, 12, 3
    for (x, y, dx, dy) in [(b[0], b[1], 1, 1), (b[2], b[1], -1, 1), (b[2], b[3], -1, -1), (b[0], b[3], 1, -1)]:
        pts = [(x, y + dy * length), (x, y + dy * radius)]
        p0, c, p2 = (x, y + dy * radius), (x, y), (x + dx * radius, y)
        for i in range(1, 33):
            t = i / 32
            pts.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p2[0],
                        (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p2[1]))
        pts.append((x + dx * length, y))
        spts = [(px_ * s, py_ * s) for px_, py_ in pts]
        d.line(spts, fill=255, width=lw * s, joint='curve')
        r = lw * s / 2
        for ex, ey in (spts[0], spts[-1]):
            d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=255)
    white = Image.new('RGBA', size, (255, 255, 255, 0))
    white.putalpha(guides.point(lambda v: round(v * 0.7)))
    out = Image.alpha_composite(out, white)
    return out.resize((W * pt_scale, H * pt_scale), Image.LANCZOS)

if __name__ == '__main__':
    dest = sys.argv[1]
    for scale in (2, 3):
        render(scale).save(f'{dest}/launch@{scale}x.png', optimize=True)
