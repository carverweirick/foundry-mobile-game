#!/usr/bin/env python3
"""Builds the 128x128 "Pixel HD" station set in assets/sprites/stations_hd/.

The 48x48 hand-built set (gen_station_pixel_art.py) reads blocky on a phone:
the floor draws a station in an 80-world-px box, so at 1x zoom each 48px
texel lands on ~7 device pixels of an iPhone. At 128px it's ~2.8, which is
where the extra detail actually shows (user request, 2026-10-17: "more like
128x128... a little bit more detail in the sprites").

Rather than redraw 18 machines, this derives true pixel art from the user's
own AI-painted set (assets/sprites/stations_ai/, 384px): pad to a 384 square,
3x3 alpha-weighted box downsample to 128, snap every sprite to its own
48-color median-cut palette (flat color clusters instead of painterly
gradients), remove single-pixel speckle, and add a 1px dark outline so the
silhouette reads against the floor like the 8-bit set's does. Finally the
transparent margin is trimmed (one shared box for a station and its
"_running" variant, so it doesn't jump when the machine starts): the floor
fits a sprite's whole canvas into Station.ART_BOX, so padding would make a
machine draw smaller than its 8-bit counterpart.

Run from the project root:  python3 tools/gen_station_pixel_hd.py
No dependencies beyond the standard library (reads/writes PNGs with zlib).
"""
import os
import struct
import zlib

SRC_DIR = os.path.join("assets", "sprites", "stations_ai")
OUT_DIR = os.path.join("assets", "sprites", "stations_hd")
SOURCE_SIZE = 384
FACTOR = 3                   # 384 / 3 = 128
PALETTE_COLORS = 48
OUTLINE = (22, 22, 28, 255)  # same outline as the 8-bit set


# --- PNG I/O -----------------------------------------------------------------

def read_png(path):
    data = open(path, "rb").read()
    pos = 8
    idat = b""
    w = h = ctype = 0
    palette = trns = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0, path
        elif tag == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    bpp = {6: 4, 2: 3, 3: 1, 0: 1, 4: 2}[ctype]
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        kind = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        row = []
        for x in range(w):
            px = line[x * bpp:(x + 1) * bpp]
            if ctype == 6:
                row.append(tuple(px))
            elif ctype == 2:
                row.append((px[0], px[1], px[2], 255))
            elif ctype == 3:
                alpha = trns[px[0]] if trns and px[0] < len(trns) else 255
                row.append(palette[px[0]] + (alpha,))
            elif ctype == 0:
                row.append((px[0], px[0], px[0], 255))
            else:
                row.append((px[0], px[0], px[0], px[1]))
        rows.append(row)
        prev = line
    return rows


def write_png(path, rows):
    h = len(rows)
    w = len(rows[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# --- the conversion ----------------------------------------------------------

def to_square(rows):
    """Centered horizontally, bottom-aligned, so the machine's feet stay put."""
    h = len(rows)
    w = len(rows[0])
    ox = (SOURCE_SIZE - w) // 2
    oy = SOURCE_SIZE - h
    out = [[(0, 0, 0, 0)] * SOURCE_SIZE for _ in range(SOURCE_SIZE)]
    for y in range(h):
        out[y + oy][ox:ox + w] = rows[y]
    return out


def box_downsample(rows):
    """Alpha-weighted 3x3 average; a block at least half covered is opaque."""
    n = len(rows) // FACTOR
    out = []
    for by in range(n):
        row = []
        for bx in range(n):
            r = g = b = a = 0
            for y in range(by * FACTOR, by * FACTOR + FACTOR):
                for x in range(bx * FACTOR, bx * FACTOR + FACTOR):
                    pr, pg, pb, pa = rows[y][x]
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
            if a < 128 * FACTOR * FACTOR:
                row.append((0, 0, 0, 0))
            else:
                row.append((r // a, g // a, b // a, 255))
        out.append(row)
    return out


def _spread(box):
    return max(max(p[c] for p in box) - min(p[c] for p in box) for c in range(3))


def median_cut(pixels, count):
    boxes = [pixels]
    while len(boxes) < count:
        index = max(range(len(boxes)), key=lambda i: _spread(boxes[i]) * len(boxes[i]) ** 0.5 if len(boxes[i]) > 1 else -1)
        box = boxes[index]
        if len(box) < 2:
            break
        channel = max(range(3), key=lambda c: max(p[c] for p in box) - min(p[c] for p in box))
        box.sort(key=lambda p: p[channel])
        mid = len(box) // 2
        boxes[index:index + 1] = [box[:mid], box[mid:]]
    return [tuple(sum(p[c] for p in b) // len(b) for c in range(3)) for b in boxes if b]


def _distance(a, b):
    # Green-weighted RGB distance - cheap stand-in for perceptual.
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return 2 * dr * dr + 4 * dg * dg + 3 * db * db


def quantize(rows):
    palette = median_cut([p[:3] for row in rows for p in row if p[3]], PALETTE_COLORS)
    nearest = {}
    out = []
    for row in rows:
        new_row = []
        for p in row:
            if p[3]:
                if p[:3] not in nearest:
                    nearest[p[:3]] = min(palette, key=lambda c: _distance(c, p[:3]))
                p = nearest[p[:3]] + (255,)
            new_row.append(p)
        out.append(new_row)
    return out


def despeckle(rows):
    """A pixel unlike all four neighbors, three of which agree, joins them."""
    h = len(rows)
    w = len(rows[0])
    out = [row[:] for row in rows]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            p = rows[y][x]
            if not p[3]:
                continue
            neighbors = [rows[y - 1][x], rows[y + 1][x], rows[y][x - 1], rows[y][x + 1]]
            if p in neighbors:
                continue
            counts = {}
            for q in neighbors:
                if q[3]:
                    counts[q] = counts.get(q, 0) + 1
            if counts:
                q, n = max(counts.items(), key=lambda kv: kv[1])
                if n >= 3:
                    out[y][x] = q
    return out


def add_outline(rows):
    h = len(rows)
    w = len(rows[0])
    out = [row[:] for row in rows]
    for y in range(h):
        for x in range(w):
            if rows[y][x][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and rows[yy][xx][3]:
                    out[y][x] = OUTLINE
                    break
    return out


def convert(src_path):
    return add_outline(despeckle(quantize(box_downsample(to_square(read_png(src_path))))))


def content_box(rows):
    xs = [x for row in rows for x, p in enumerate(row) if p[3]]
    ys = [y for y, row in enumerate(rows) if any(p[3] for p in row)]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    converted = {}
    for name in sorted(os.listdir(SRC_DIR)):
        if name.endswith(".png"):
            converted[name[:-4]] = convert(os.path.join(SRC_DIR, name))
    for name, rows in converted.items():
        base = name[:-len("_running")] if name.endswith("_running") else name
        boxes = [content_box(converted[n]) for n in (base, base + "_running") if n in converted]
        x0 = min(b[0] for b in boxes)
        y0 = min(b[1] for b in boxes)
        x1 = max(b[2] for b in boxes)
        y1 = max(b[3] for b in boxes)
        path = os.path.join(OUT_DIR, name + ".png")
        write_png(path, [row[x0:x1] for row in rows[y0:y1]])
        print("wrote %s (%dx%d)" % (path, x1 - x0, y1 - y0))


if __name__ == "__main__":
    main()
