#!/usr/bin/env python3
"""Draws hidnr's letterforms and writes every brand SVG from one source.

Run from the repo root:  python3 scripts/branding.py
Then:                    swift scripts/make-app-icon.swift   (PNG app icon sizes)

Coordinates are y-down with the baseline at y=720 and the x-height at y=280.
"""
from pathlib import Path

INK = "#12142b"
CREAM = "#f7f5ef"


class Letters:
    def __init__(self, stem=112, hair=22, ball=54):
        self.W, self.H, self.R = stem, hair, ball
        self.X, self.B = 280, 720

    def stem(self, x, top=None):
        top = self.X if top is None else top
        return f"M{x},{top} H{x + self.W} V{self.B} H{x} Z"

    def arch(self, x, leg=315):
        """Shoulder of h/n: hairline from the stem at x into a thick leg."""
        X, B, H = self.X, self.B, self.H
        s, l = x + self.W, x + leg
        r = l + self.W
        return (f"M{s},{X + 105} C{s + 30},{X + 30} {s + 85},{X - 10} {s + 145},{X - 10} "
                f"C{r - 45},{X - 10} {r},{X + 45} {r},{X + 150} V{B} H{l} V{X + 160} "
                f"C{l},{X + 70} {l - 30},{X - 10 + H} {s + 125},{X - 10 + H} "
                f"C{s + 80},{X - 10 + H} {s + 25},{X + 60} {s},{X + 175} Z")

    def swash_stem(self, x):
        """The h ascender, dropping below the baseline and sweeping left."""
        W, B = self.W, self.B
        t = (self.H - 22) * 0.9  # thicker hairline for small sizes
        return (f"M{x},0 H{x + W} V{B + 10} C{x + W},{B + 165} {x + 30},{B + 218} {x - 90},{B + 215} "
                f"C{x - 165},{B + 213} {x - 212},{B + 178} {x - 226},{B + 128} "
                f"L{x - 186 + t},{B + 132} C{x - 176 + t},{B + 166 - t} {x - 145},{B + 188 - t} {x - 95},{B + 188 - t} "
                f"C{x - 22},{B + 188 - t} {x},{B + 125} {x},{B + 45} Z")

    def swash_ball(self, x):
        return circle(x - 203, self.B + 108, self.R)

    def r_arm(self, x):
        X, H = self.X, self.H
        s = x + self.W
        return (f"M{s},{X + 110} C{s + 30},{X + 30} {s + 95},{X - 10} {s + 160},{X - 10} "
                f"C{s + 200},{X - 10} {s + 225},{X + 5} {s + 235},{X + 30} "
                f"C{s + 210},{X + 14} {s + 180},{X - 10 + H} {s + 150},{X - 10 + H} "
                f"C{s + 95},{X - 10 + H} {s + 30},{X + 75} {s},{X + 180} Z")

    def bowl(self, cx):
        return ellipse(cx, 502, 190, 232) + " " + ellipse(cx + 10, 502, 84, 232 - self.H)

    def monogram(self):
        """Just the h with its swash: (paths, evenodd paths, bbox)."""
        paths = [self.arch(0), self.swash_stem(0), self.swash_ball(0)]
        return paths, [], (-203 - self.R, 0, 315 + self.W, self.B + 215)

    def wordmark(self):
        W, X = self.W, self.X
        paths = [self.arch(0), self.swash_stem(0), self.swash_ball(0)]
        paths += [self.stem(500), circle(500 + W / 2, 172, 56)]          # i
        cx = 870
        evenodd = [self.bowl(cx)]                                         # d bowl
        d_stem = cx + 190 - W
        paths.append(self.stem(d_stem, top=0))                            # d stem
        n = d_stem + W + 45
        paths += [self.stem(n), self.arch(n)]                             # n
        r = n + 315                                                       # r shares n's leg
        paths += [self.r_arm(r), circle(r + W + 228, X + 75, self.R)]
        return paths, evenodd, (-203 - self.R, 0, r + W + 228 + self.R, self.B + 215)


def ellipse(cx, cy, rx, ry):
    return f"M{cx - rx},{cy} a{rx},{ry} 0 1,0 {2 * rx},0 a{rx},{ry} 0 1,0 {-2 * rx},0 Z"


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def group(paths, evenodd, fill):
    body = "".join(f'<path d="{d}"/>' for d in paths)
    body += "".join(f'<path fill-rule="evenodd" d="{d}"/>' for d in evenodd)
    return f'<g fill="{fill}">{body}</g>'


def tight_svg(shape, fill="#000", pad=0):
    """Transparent SVG cropped to the shape, for template images."""
    paths, evenodd, (x0, y0, x1, y1) = shape
    w, h = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0 - pad} {y0 - pad} {w} {h}" '
            f'width="{w / 50:.2f}" height="{h / 50:.2f}">{group(paths, evenodd, fill)}</svg>')


def logo_svg(shape):
    """The wordmark centred on a white square, like the lyffe logo sheet."""
    paths, evenodd, (x0, y0, x1, y1) = shape
    w = x1 - x0
    side = w * 1.75
    vx, vy = x0 - (side - w) / 2, (y0 + y1) / 2 - side / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vx} {vy} {side} {side}" width="1200" height="1200">'
            f'<rect x="{vx}" y="{vy}" width="{side}" height="{side}" fill="#fff"/>{group(paths, evenodd, INK)}</svg>')


def icon_svg(shape):
    """macOS app icon: cream monogram on an ink rounded square (Apple's 824/1024 grid)."""
    paths, evenodd, (x0, y0, x1, y1) = shape
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{INK}"/>'
            f'<g transform="translate(512,512) scale(0.62) translate({-cx},{-cy})">{group(paths, evenodd, CREAM)}</g></svg>')


def image_set(folder, filename, svg):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / filename).write_text(svg)
    (folder / "Contents.json").write_text(
        '{\n  "images" : [ { "filename" : "%s", "idiom" : "universal" } ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 },\n'
        '  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }\n}\n'
        % filename)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    display = Letters()
    # The menu bar glyph is ~18pt tall, so hairlines and stems are beefed up to stay visible.
    small = Letters(stem=150, hair=78, ball=78)

    (root / "branding/hidnr-logo.svg").write_text(logo_svg(display.wordmark()))
    (root / "branding/hidnr-icon.svg").write_text(icon_svg(display.monogram()))
    assets = root / "Resources/Assets.xcassets"
    image_set(assets / "BarGlyph.imageset", "bar-glyph.svg", tight_svg(small.monogram(), pad=10))
    image_set(assets / "Wordmark.imageset", "wordmark.svg", tight_svg(Letters(hair=34).wordmark(), pad=10))
    print("Wrote branding/*.svg and the BarGlyph / Wordmark image sets")
