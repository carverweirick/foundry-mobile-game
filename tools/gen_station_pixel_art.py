#!/usr/bin/env python3
"""Generates the hand-built 8-bit station sprites in assets/sprites/stations_pixel/.

Each station is drawn on a 48x48 canvas with a few primitives (3/4-view boxes,
ellipses, lines), then given a 1px dark outline. Modelled on the AI-generated
set in assets/sprites/stations_ai/ (same machines, same colors) so the two art
styles the Settings menu switches between describe the same shop floor.

Run from the project root:  python3 tools/gen_station_pixel_art.py
No dependencies beyond the standard library (writes PNGs with zlib).
"""
import os
import struct
import zlib

W = H = 48
OUT_DIR = os.path.join("assets", "sprites", "stations_pixel")

# --- palette ---------------------------------------------------------------
OUT = (22, 22, 28)
S0 = (46, 50, 58)      # darkest steel
S1 = (74, 80, 90)
S2 = (104, 111, 122)
S3 = (140, 147, 158)
S4 = (182, 188, 197)
S5 = (214, 218, 224)   # highlight
HAZ = (236, 186, 46)
HAZD = (44, 38, 30)
ORG = (255, 128, 32)
ORG2 = (255, 196, 84)
ORG3 = (255, 236, 170)
RED = (214, 58, 48)
RED2 = (150, 36, 30)
PUR = (128, 58, 214)
PUR2 = (196, 128, 255)
PUR3 = (240, 210, 255)
BLU = (46, 120, 220)
BLU2 = (120, 190, 255)
BLU3 = (200, 236, 255)
CYN = (70, 210, 236)
SCR = (18, 36, 56)
CRM = (234, 224, 196)
CRM2 = (196, 182, 150)
COP = (206, 112, 56)
COP2 = (150, 72, 34)
WAX = (88, 168, 92)
WAX2 = (52, 112, 60)
BOX = (204, 156, 92)
BOX2 = (160, 116, 62)
WHT = (240, 242, 244)
SMK = (176, 176, 182)
SMK2 = (130, 130, 138)
GRN = (80, 200, 96)


class Canvas:
    def __init__(self):
        self.px = [[None] * W for _ in range(H)]

    def set(self, x, y, c):
        if c is not None and 0 <= x < W and 0 <= y < H:
            self.px[y][x] = c

    def get(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            return self.px[y][x]
        return None

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def hline(self, x, y, w, c):
        self.rect(x, y, w, 1, c)

    def vline(self, x, y, h, c):
        self.rect(x, y, 1, h, c)

    def frame(self, x, y, w, h, c):
        self.hline(x, y, w, c)
        self.hline(x, y + h - 1, w, c)
        self.vline(x, y, h, c)
        self.vline(x + w - 1, y, h, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, c, outline=None):
        for yy in range(cy - ry, cy + ry + 1):
            for xx in range(cx - rx, cx + rx + 1):
                d = ((xx - cx) / (rx + 0.5)) ** 2 + ((yy - cy) / (ry + 0.5)) ** 2
                if d <= 1.0:
                    edge = ((xx - cx) / (rx - 0.5 if rx > 1 else 0.5)) ** 2 + ((yy - cy) / (ry - 0.5 if ry > 1 else 0.5)) ** 2 > 1.0
                    self.set(xx, yy, outline if (outline and edge) else c)

    def box(self, x, y, w, h, d, front, top=None, side=None):
        """3/4-view box: front face w x h at (x, y + d), top and right-side faces
        d px deep, receding up and to the right."""
        top = top or lighten(front, 0.35)
        side = side or darken(front, 0.35)
        self.rect(x, y + d, w, h, front)
        for k in range(1, d + 1):
            self.hline(x + k, y + d - k, w, top)
            self.vline(x + w - 1 + k, y + d - k, h, side)
        # crisp edges: lit top edge of the front face, shaded bottom
        self.hline(x, y + d, w, lighten(front, 0.18))
        self.hline(x, y + d + h - 1, w, darken(front, 0.2))

    def hazard(self, x, y, w, h):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, HAZ if ((xx + yy) // 2) % 2 == 0 else HAZD)

    def screen(self, x, y, w, h, glow=CYN):
        self.rect(x, y, w, h, SCR)
        self.frame(x - 1, y - 1, w + 2, h + 2, S0)
        self.hline(x + 1, y + 1, max(1, w - 3), glow)
        if h > 2:
            self.hline(x + 1, y + 3 if h > 4 else y + 2, max(1, w // 2), darken(glow, 0.3))

    def legs(self, x0, x1, y, h=2, c=S0):
        self.rect(x0, y, 3, h, c)
        self.rect(x1 - 2, y, 3, h, c)

    def outline(self, c=OUT):
        add = []
        for y in range(H):
            for x in range(W):
                if self.px[y][x] is None:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        n = self.get(x + dx, y + dy)
                        if n is not None and n != c:
                            add.append((x, y))
                            break
        for x, y in add:
            self.px[y][x] = c

    def save(self, path):
        raw = b""
        for row in self.px:
            raw += b"\x00" + b"".join(
                bytes((*c, 255)) if c is not None else b"\x00\x00\x00\x00" for c in row)
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def lighten(c, t):
    return tuple(min(255, int(v + (255 - v) * t)) for v in c)


def darken(c, t):
    return tuple(int(v * (1 - t)) for v in c)


# --- stations ----------------------------------------------------------------

def printing(cv, running=False):
    cv.box(12, 3, 22, 38, 5, S2)
    cv.legs(13, 33, 46)
    # amber resin window with build plate, lift screw and a part
    cv.rect(15, 11, 16, 20, (120, 52, 14))
    cv.rect(16, 12, 14, 18, ORG if not running else ORG2)
    cv.rect(16, 12, 14, 3, darken(ORG, 0.25))
    cv.vline(22, 12, 9, S1)
    cv.rect(18, 20, 10, 2, S3)
    cv.rect(21, 22, 4, 3, CRM)
    cv.rect(16, 27, 14, 3, (190, 80, 20))
    cv.vline(16, 12, 18, lighten(ORG, 0.5))
    # control panel
    cv.screen(16, 35, 7, 4)
    cv.rect(26, 35, 3, 2, ORG)
    cv.rect(26, 38, 3, 2, S0)
    cv.hazard(35, 22, 2, 14)


def clean(cv, running=False):
    # lid propped open behind the tank
    for k in range(9):
        cv.hline(11 + k // 3, 5 + k, 24, S1 if k else S3)
    cv.hline(16, 3, 12, S0)
    cv.rect(16, 3, 2, 3, S0)
    cv.rect(26, 3, 2, 3, S0)
    cv.box(6, 13, 32, 26, 6, S2)
    cv.legs(7, 37, 45)
    # fluid in the open top, basket mesh
    for k in range(1, 6):
        cv.hline(7 + k, 19 - k, 30, BLU if k % 2 else BLU2)
    cv.rect(7, 20, 30, 6, BLU)
    for xx in range(10, 34, 3):
        cv.vline(xx, 17, 8, S3)
    cv.hline(10, 17, 24, S3)
    cv.hline(10, 24, 24, S3)
    cv.set(12, 21, BLU3)
    cv.set(27, 19, BLU3)
    cv.set(20, 22, BLU3)
    cv.screen(15, 31, 9, 4)
    cv.rect(28, 31, 3, 2, ORG)
    cv.rect(28, 34, 3, 2, S0)
    cv.hazard(39, 21, 2, 15)


def uv_cure(cv, running=False):
    cv.box(18, 2, 12, 5, 3, S1)
    for xx in range(20, 29, 2):
        cv.vline(xx, 5, 3, S0)
    cv.box(7, 9, 30, 28, 5, S2)
    cv.legs(8, 36, 42)
    glow = PUR2 if running else PUR
    cv.rect(10, 17, 19, 19, S0)
    cv.rect(11, 18, 17, 17, glow)
    cv.rect(11, 18, 17, 2, PUR3 if running else PUR2)
    cv.hline(13, 21, 13, PUR3)
    cv.hline(13, 23, 13, PUR3 if running else PUR2)
    cv.ellipse(19, 31, 6, 2, darken(glow, 0.15) if not running else PUR2, PUR3)
    cv.vline(11, 18, 17, lighten(glow, 0.4))
    # control strip
    cv.rect(30, 17, 5, 19, (36, 44, 72))
    for i, c in enumerate((PUR2, SCR, S3, S3, ORG)):
        cv.rect(31, 18 + i * 3 + (1 if i else 0), 3, 2, c)
    if running:
        for x, y in ((8, 16), (36, 30), (21, 14), (6, 26)):
            cv.set(x, y, PUR3)


def scan(cv, running=False):
    cv.box(5, 31, 36, 11, 4, S2)
    cv.legs(6, 40, 46)
    cv.screen(10, 38, 8, 3)
    cv.rect(26, 38, 3, 2, ORG)
    # gantry
    cv.rect(7, 6, 4, 29, S1)
    cv.rect(35, 6, 4, 29, S1)
    cv.vline(7, 6, 29, S3)
    cv.vline(35, 6, 29, S3)
    cv.box(6, 3, 34, 3, 3, S2)
    cv.rect(19, 9, 8, 5, S1)
    cv.rect(20, 14, 6, 2, S0)
    cv.set(22, 15, BLU2)
    cv.set(23, 15, BLU3)
    # light cone onto the turntable
    for k in range(13):
        half = 1 + k // 2
        for xx in range(23 - half, 23 + half + 1):
            if cv.get(xx, 16 + k) is None:
                cv.set(xx, 16 + k, BLU2 if (xx + k) % 3 else BLU3)
    cv.ellipse(23, 31, 9, 2, S3, S1)
    cv.rect(20, 25, 6, 5, CRM)
    cv.rect(21, 23, 4, 2, CRM2)


def patching(cv, running=False):
    # pegboard with tools
    cv.rect(12, 4, 26, 14, S1)
    for yy in range(6, 17, 3):
        for xx in range(14, 37, 3):
            cv.set(xx, yy, S0)
    for i, c in enumerate((RED, BLU2, WHT, ORG, S4)):
        cv.rect(15 + i * 4, 7, 2, 7, c)
        cv.set(15 + i * 4, 6, S0)
    # lamp arm
    cv.line(9, 22, 9, 10, S0)
    cv.line(9, 10, 15, 6, S0)
    cv.rect(15, 5, 5, 3, S3)
    cv.set(17, 8, ORG2)
    cv.box(4, 18, 38, 3, 4, S3)
    cv.box(6, 25, 34, 17, 3, S1)
    cv.rect(9, 30, 14, 4, S2)
    cv.rect(9, 36, 14, 4, S2)
    cv.hline(13, 31, 6, S4)
    cv.hline(13, 37, 6, S4)
    cv.rect(26, 30, 12, 10, S2)
    cv.legs(7, 39, 45)
    # part being patched + putty
    cv.rect(18, 17, 9, 4, CRM)
    cv.rect(20, 15, 4, 2, CRM2)
    cv.rect(31, 18, 4, 2, (210, 120, 150))


def pour_cup_attach(cv, running=False):
    cv.box(3, 22, 40, 3, 4, S3)
    cv.box(5, 29, 36, 13, 3, S1)
    cv.legs(6, 40, 45)
    cv.rect(8, 33, 12, 7, S2)
    cv.rect(23, 33, 15, 7, (40, 70, 110))
    for xx in range(25, 37, 4):
        cv.rect(xx, 35, 3, 3, BOX)
    # wax trees with pour cups on top
    for x0, h in ((11, 17), (22, 21), (33, 14)):
        top = 22 - h
        cv.vline(x0, top + 3, h - 1, WAX2)
        cv.vline(x0 + 1, top + 3, h - 1, WAX)
        for yy in range(top + 6, 21, 4):
            cv.rect(x0 - 3, yy, 3, 2, WAX)
            cv.rect(x0 + 2, yy + 2, 3, 2, WAX)
        cv.rect(x0 - 2, top, 6, 2, CRM)
        cv.rect(x0 - 1, top + 2, 4, 1, CRM2)
        cv.rect(x0 - 2, 21, 6, 1, S0)


def shelling(cv, running=False):
    # slurry dip on the left
    cv.rect(4, 6, 2, 22, S1)
    cv.rect(19, 6, 2, 22, S1)
    cv.hline(4, 5, 17, S2)
    cv.vline(12, 6, 6, S0)
    cv.rect(9, 12, 7, 2, S3)
    for xx in range(10, 15, 2):
        cv.rect(xx, 14, 1, 4, CRM)
        cv.set(xx, 18, CRM2)
    cv.box(2, 24, 21, 16, 3, S2)
    cv.rect(4, 26, 17, 3, CRM)
    cv.legs(3, 22, 43)
    # sand (stucco) rainfall cabinet on the right
    cv.box(24, 12, 19, 28, 4, S2)
    cv.legs(25, 42, 44)
    cv.rect(26, 19, 15, 15, (110, 60, 20))
    cv.rect(27, 20, 13, 13, ORG2)
    for yy in range(20, 33, 2):
        for xx in range(28 + (yy % 4) // 2, 40, 3):
            cv.set(xx, yy, ORG)
    cv.rect(27, 30, 13, 3, (214, 160, 86))
    # hopper and duct
    cv.ellipse(36, 6, 4, 3, S3, S1)
    cv.vline(36, 9, 3, S1)
    cv.rect(41, 3, 3, 12, S1)
    cv.screen(27, 37, 6, 2)


def burnout(cv, running=False):
    # chimney and smoke
    cv.rect(20, 4, 6, 7, S1)
    cv.hline(19, 4, 8, S3)
    for x, y, r in ((23, 2, 3), (29, 0, 2)) if not running else ((22, 2, 3), (28, 0, 3), (33, 1, 2)):
        cv.ellipse(x, y, r, max(1, r - 1), SMK, SMK2)
    cv.box(6, 9, 32, 31, 6, S2)
    cv.legs(7, 37, 46)
    cv.rect(13, 8, 16, 4, S1)
    for xx in range(14, 28, 2):
        cv.vline(xx, 9, 2, S0)
    # firebox door
    cv.rect(9, 20, 22, 18, S0)
    cv.rect(11, 22, 18, 14, RED2)
    fire_hi = ORG3 if running else ORG2
    cv.rect(12, 23, 16, 12, ORG)
    cv.rect(14, 25, 12, 8, fire_hi)
    cv.rect(16, 27, 8, 4, ORG3 if running else ORG2)
    for xx in range(12, 28, 3):
        cv.vline(xx, 23, 12, darken(ORG, 0.35))
    cv.hline(11, 33, 18, (120, 40, 10))
    cv.rect(32, 20, 4, 5, S1)
    cv.set(33, 21, ORG)
    cv.set(33, 23, GRN if running else S0)
    cv.rect(30, 26, 2, 6, S3)
    if running:
        for x, y in ((8, 19), (31, 18), (20, 19)):
            cv.set(x, y, ORG2)


def pour(cv, running=False):
    # control cabinet
    cv.box(2, 12, 15, 30, 3, S4, S5, S3)
    cv.legs(3, 16, 45)
    cv.screen(4, 17, 9, 5, GRN)
    for yy in range(25, 34, 3):
        for xx in (4, 7, 10):
            cv.rect(xx, yy, 2, 2, (RED, ORG, S1)[(xx + yy) % 3])
    cv.rect(5, 36, 8, 2, S1)
    # induction vessel with coil
    cv.rect(31, 4, 3, 6, S1)
    cv.hline(29, 4, 7, S3)
    cv.ellipse(31, 12, 11, 4, S4, S2)
    cv.rect(20, 12, 23, 22, S3)
    cv.vline(20, 12, 22, S4)
    cv.vline(42, 12, 22, S1)
    cv.ellipse(31, 34, 11, 4, S2, S1)
    glow = ORG3 if running else ORG2
    cv.rect(27, 15, 9, 8, S0)
    cv.rect(28, 16, 7, 6, ORG)
    cv.rect(29, 17, 5, 4, glow)
    coil = ORG if running else COP
    for yy in range(25, 34, 2):
        cv.hline(20, yy, 23, coil)
        cv.hline(20, yy + 1, 23, COP2 if not running else (200, 70, 20))
    # gauge and pipe
    cv.ellipse(45, 30, 2, 2, WHT, S1)
    cv.line(43, 22, 45, 22, S1)
    cv.vline(45, 22, 6, S1)
    cv.rect(18, 38, 26, 4, S0)
    if running:
        for x, y in ((19, 24), (44, 26), (31, 7)):
            cv.set(x, y, ORG2)


def mold_prep(cv, running=False):
    # shelving with shells
    cv.rect(4, 3, 2, 22, S1)
    cv.rect(32, 3, 2, 22, S1)
    cv.hline(4, 12, 30, S3)
    cv.hline(4, 22, 30, S3)
    for xx in range(7, 31, 6):
        cv.rect(xx, 7, 4, 5, CRM)
        cv.rect(xx + 1, 5, 2, 2, CRM2)
        cv.rect(xx, 17, 4, 5, CRM if xx % 4 else CRM2)
    # torch on a hose
    cv.line(40, 24, 38, 6, COP2)
    cv.rect(36, 4, 4, 3, S2)
    cv.set(35, 3, BLU2)
    cv.set(34, 2, BLU3)
    cv.box(3, 24, 38, 3, 4, S3)
    cv.box(5, 31, 34, 11, 3, S1)
    cv.legs(6, 38, 45)
    cv.rect(9, 25, 10, 3, S2)
    cv.rect(10, 24, 8, 2, (200, 190, 170))
    cv.rect(23, 24, 6, 3, HAZ)
    cv.ellipse(19, 37, 5, 3, S2, S0)
    cv.rect(16, 35, 7, 2, CRM2)


def deshell(cv, running=False):
    cv.rect(6, 6, 4, 32, S1)
    cv.rect(35, 6, 4, 32, S1)
    cv.hazard(6, 26, 4, 10)
    cv.hazard(35, 26, 4, 10)
    cv.box(5, 2, 35, 4, 3, S2)
    # pneumatic hammer
    cv.rect(18, 9, 9, 8, S2)
    cv.vline(18, 9, 8, S4)
    cv.rect(21, 17, 3, 6, S4)
    cv.rect(20, 23, 5, 2, S0)
    cv.line(27, 10, 32, 6, COP)
    cv.line(27, 11, 32, 7, COP2)
    # shell fragments in the tray
    cv.box(9, 30, 27, 8, 3, S1)
    for x, y, w, h in ((12, 28, 5, 4), (18, 26, 6, 6), (25, 28, 5, 4), (14, 31, 4, 2), (29, 30, 4, 2)):
        cv.rect(x, y, w, h, CRM)
        cv.hline(x, y, w, WHT)
        cv.set(x + w - 1, y + h - 1, CRM2)
    cv.box(4, 41, 37, 3, 2, S2)
    cv.screen(42, 20, 3, 6)


def abrasive_blast(cv, running=False):
    cv.box(5, 6, 34, 26, 5, S2)
    cv.rect(18, 4, 10, 4, S1)
    # window with sparks and a part
    cv.rect(9, 13, 24, 9, S0)
    cv.rect(10, 14, 22, 7, (90, 52, 24))
    cv.rect(18, 16, 5, 4, CRM)
    for x, y in ((12, 15), (15, 18), (26, 16), (29, 19), (13, 19), (27, 15)):
        cv.set(x, y, ORG2)
    cv.line(32, 14, 24, 17, S4)
    # glove ports
    cv.ellipse(14, 28, 4, 3, S0, S1)
    cv.ellipse(28, 28, 4, 3, S0, S1)
    cv.ellipse(14, 28, 2, 1, (20, 20, 24))
    cv.ellipse(28, 28, 2, 1, (20, 20, 24))
    # hopper below
    for k in range(7):
        cv.hline(9 + k * 2, 36 + k, 26 - k * 4, S1 if k % 2 else S2)
    cv.rect(19, 42, 6, 3, S0)
    cv.legs(6, 38, 37, 9, S1)
    # dust collector hose
    cv.rect(42, 8, 4, 22, S1)
    cv.line(40, 10, 42, 10, S0)
    cv.ellipse(44, 31, 2, 1, S0)


def grinding(cv, running=False):
    # belt sander
    cv.rect(26, 4, 8, 25, S1)
    cv.rect(28, 5, 4, 23, RED)
    cv.vline(28, 5, 23, (240, 100, 90))
    cv.ellipse(30, 5, 3, 2, S3, S0)
    cv.ellipse(30, 27, 3, 2, S3, S0)
    # bench grinder wheel + guard
    cv.ellipse(13, 18, 7, 7, S3, S1)
    cv.ellipse(13, 18, 4, 4, S2, S0)
    cv.ellipse(13, 18, 1, 1, S4)
    cv.rect(17, 16, 8, 6, S1)
    # sparks
    for x, y in ((5, 23), (3, 26), (6, 27), (2, 22), (4, 29), (7, 25)):
        cv.set(x, y, ORG2 if (x + y) % 2 else HAZ)
    # lamp
    cv.line(39, 24, 41, 8, S0)
    cv.rect(38, 6, 5, 3, S3)
    cv.box(3, 26, 38, 3, 4, S3)
    cv.box(5, 33, 34, 9, 3, S1)
    cv.rect(8, 35, 13, 3, S2)
    cv.hline(12, 36, 5, S4)
    cv.legs(6, 38, 45)
    cv.rect(26, 24, 8, 3, CRM)
    # dust duct
    cv.rect(43, 10, 3, 24, S1)


def ship(cv, running=False):
    # shelf with stock
    cv.rect(26, 6, 2, 16, S1)
    cv.rect(42, 6, 2, 16, S1)
    cv.hline(26, 12, 18, S3)
    cv.rect(29, 7, 5, 5, BOX)
    cv.rect(35, 9, 5, 3, WHT)
    cv.rect(29, 14, 12, 3, BOX2)
    # lamp
    cv.line(6, 22, 8, 7, S0)
    cv.rect(7, 5, 6, 3, S3)
    cv.box(3, 22, 40, 3, 4, S3)
    cv.box(5, 29, 36, 13, 3, S1)
    cv.legs(6, 40, 45)
    cv.rect(8, 33, 13, 3, S2)
    cv.rect(8, 37, 13, 3, S2)
    # the shipping box
    cv.box(11, 11, 15, 10, 4, BOX, lighten(BOX, 0.25), BOX2)
    cv.vline(18, 15, 10, (232, 210, 160))
    for k in range(1, 5):
        cv.set(18 + k, 15 - k, (232, 210, 160))
    cv.rect(20, 18, 5, 3, WHT)
    cv.hline(21, 19, 3, S0)
    # label printer
    cv.box(30, 18, 9, 5, 2, S0)
    cv.rect(32, 19, 5, 2, WHT)


def nc_shelf(cv, running=False):
    cv.rect(4, 3, 3, 40, S1)
    cv.rect(40, 3, 3, 40, S1)
    cv.hazard(4, 3, 3, 40)
    cv.hazard(40, 3, 3, 40)
    for yy in (16, 30, 42):
        cv.box(5, yy - 2, 36, 2, 2, S3)
    # quarantined parts
    for x, y in ((9, 9), (16, 11), (24, 8), (31, 11)):
        cv.rect(x, y, 5, 5, CRM)
        cv.hline(x, y, 5, WHT)
        cv.rect(x + 1, y - 2, 3, 2, CRM2)
    cv.rect(9, 24, 12, 4, (60, 70, 90))
    cv.rect(23, 23, 6, 5, CRM)
    cv.rect(31, 24, 6, 4, CRM2)
    cv.rect(10, 36, 10, 4, (60, 70, 90))
    cv.rect(24, 35, 8, 5, CRM)
    # red QC HOLD tag
    cv.line(36, 13, 38, 17, S4)
    cv.rect(35, 17, 6, 9, RED)
    cv.rect(36, 18, 4, 1, WHT)
    cv.rect(37, 20, 2, 3, WHT)
    cv.set(37, 24, WHT)


STATIONS = {
    "printing": printing, "clean": clean, "uv_cure": uv_cure, "scan": scan,
    "patching": patching, "pour_cup_attach": pour_cup_attach, "shelling": shelling,
    "burnout": burnout, "pour": pour, "mold_prep": mold_prep, "deshell": deshell,
    "abrasive_blast": abrasive_blast, "grinding": grinding, "ship": ship,
    "nc_shelf": nc_shelf,
}
RUNNING_VARIANTS = ("uv_cure", "burnout", "pour")


def render(fn, running=False):
    cv = Canvas()
    fn(cv, running)
    cv.outline()
    return cv


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in STATIONS.items():
        render(fn).save(os.path.join(OUT_DIR, name + ".png"))
        if name in RUNNING_VARIANTS:
            render(fn, True).save(os.path.join(OUT_DIR, name + "_running.png"))
    print("wrote %d sprites to %s" % (len(STATIONS) + len(RUNNING_VARIANTS), OUT_DIR))


if __name__ == "__main__":
    main()
