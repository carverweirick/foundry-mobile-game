#!/usr/bin/env python3
"""Generates the 32x32 UI icons in assets/icons/ (UiIcons draws them in a
16x16 logical box, so every icon gets twice the pixel detail of the old
hand-typed 16x16 grids - user request 2026-10-17, "more detail... for the
icons").

Each icon is a few shapes in a 0..32 coordinate space, supersampled 4x4 per
pixel and snapped to the grid (>= half covered = filled), so curves come out
as clean pixel-art steps with no anti-aliasing. Shapes are drawn in named
materials; a shading pass then lights every material region from the top
left (a light first row, a dark last row) and an outline pass puts a 1px
dark rim around the whole silhouette. Small details (text lines, a check
mark) are painted on top unshaded.

Run from the project root:  python3 tools/gen_ui_icons.py [preview.png]
Writes assets/icons/<name>.png; with a path argument also writes a 4x
preview sheet there (keep it outside the project, or Godot imports it).
Standard library only.
"""
import math
import os
import struct
import sys
import zlib

SIZE = 32
SUB = 4  # supersamples per axis
OUT_DIR = os.path.join("assets", "icons")
OUTLINE = (20, 18, 16, 255)

# Material ramps: (shadow, base, light). Base matches the old icon palette.
MATERIALS = {
    "paper": ((196, 188, 170), (242, 236, 220), (255, 252, 242)),
    "gold": ((178, 118, 28), (234, 178, 52), (255, 222, 120)),
    "ember": ((168, 70, 20), (228, 108, 38), (255, 158, 84)),
    "steel": ((112, 118, 130), (158, 166, 178), (204, 210, 220)),
    "dark": ((34, 38, 46), (56, 62, 72), (82, 90, 102)),
    "gem": ((48, 128, 196), (112, 196, 245), (196, 238, 255)),
    "green": ((38, 128, 52), (84, 196, 92), (150, 232, 150)),
    "red": ((150, 34, 30), (218, 66, 56), (250, 120, 104)),
    "yellow": ((206, 158, 30), (255, 214, 82), (255, 240, 170)),
    "cyan": ((40, 150, 180), (110, 218, 240), (190, 244, 255)),
    "skin": ((196, 150, 112), (236, 196, 156), (250, 224, 196)),
    "brown": ((96, 58, 28), (138, 88, 46), (184, 128, 74)),
    "blue": ((44, 92, 170), (86, 150, 230), (156, 200, 255)),
    "white": ((200, 204, 212), (238, 240, 244), (255, 255, 255)),
    "screen": ((14, 28, 44), (24, 44, 66), (40, 70, 100)),
    "purple": ((96, 46, 170), (150, 92, 224), (204, 160, 255)),
    "wood": ((120, 74, 36), (168, 108, 56), (206, 150, 92)),
}
INK = (30, 26, 22, 255)


# --- shapes (functions of a point in 0..32 space) ---------------------------

def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def rect(x0, y0, x1, y1):
    return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1


def round_rect(x0, y0, x1, y1, r):
    def f(x, y):
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return False
        cx = min(max(x, x0 + r), x1 - r)
        cy = min(max(y, y0 + r), y1 - r)
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    return f


def polygon(points):
    def f(x, y):
        inside = False
        n = len(points)
        for i in range(n):
            x0, y0 = points[i]
            x1, y1 = points[(i + 1) % n]
            if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
                inside = not inside
        return inside
    return f


def segment(x0, y0, x1, y1, width):
    def f(x, y):
        dx, dy = x1 - x0, y1 - y0
        t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)))
        px, py = x0 + t * dx, y0 + t * dy
        return (x - px) ** 2 + (y - py) ** 2 <= (width / 2) ** 2
    return f


def ring(cx, cy, r_out, r_in):
    return lambda x, y: r_in * r_in <= (x - cx) ** 2 + (y - cy) ** 2 <= r_out * r_out


def arc(cx, cy, r_out, r_in, a0, a1):
    """Ring sector between angles a0..a1 in degrees (0 = right, clockwise, y down)."""
    def f(x, y):
        d = (x - cx) ** 2 + (y - cy) ** 2
        if not (r_in * r_in <= d <= r_out * r_out):
            return False
        a = math.degrees(math.atan2(y - cy, x - cx)) % 360
        lo, hi = a0 % 360, a1 % 360
        return lo <= a <= hi if lo <= hi else a >= lo or a <= hi
    return f


def star(cx, cy, r_out, r_in, points=5, rotation=-90):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rotation + i * 180 / points)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return polygon(pts)


def gear(cx, cy, r_out, r_root, teeth, hole=0.0, tooth_frac=0.5):
    def f(x, y):
        d = math.hypot(x - cx, y - cy)
        if d < hole:
            return False
        if d <= r_root:
            return True
        if d > r_out:
            return False
        a = (math.atan2(y - cy, x - cx) / (2 * math.pi) * teeth) % 1.0
        return abs(a - 0.5) < tooth_frac / 2
    return f


def union(*shapes):
    return lambda x, y: any(s(x, y) for s in shapes)


def minus(a, *b):
    return lambda x, y: a(x, y) and not any(s(x, y) for s in b)


# --- the canvas ---------------------------------------------------------------

class Icon:
    def __init__(self):
        self.mat = [[None] * SIZE for _ in range(SIZE)]   # material per pixel
        self.ink = [[None] * SIZE for _ in range(SIZE)]   # unshaded overpaint
        self.cut = [[False] * SIZE for _ in range(SIZE)]

    def fill(self, shape, material):
        for py in range(SIZE):
            for px in range(SIZE):
                hits = 0
                for sy in range(SUB):
                    for sx in range(SUB):
                        if shape(px + (sx + 0.5) / SUB, py + (sy + 0.5) / SUB):
                            hits += 1
                if hits * 2 >= SUB * SUB:
                    self.mat[py][px] = material
                    self.ink[py][px] = None
        return self

    def erase(self, shape):
        """Punch a hole (transparent, and the outline pass rims it)."""
        for py in range(SIZE):
            for px in range(SIZE):
                hits = sum(1 for sy in range(SUB) for sx in range(SUB)
                           if shape(px + (sx + 0.5) / SUB, py + (sy + 0.5) / SUB))
                if hits * 2 >= SUB * SUB:
                    self.mat[py][px] = None
                    self.ink[py][px] = None
        return self

    def paint(self, shape, color):
        """Flat overpaint (details), only where something is already drawn
        unless the color is opaque detail meant to stand alone."""
        c = color if len(color) == 4 else tuple(color) + (255,)
        for py in range(SIZE):
            for px in range(SIZE):
                hits = sum(1 for sy in range(SUB) for sx in range(SUB)
                           if shape(px + (sx + 0.5) / SUB, py + (sy + 0.5) / SUB))
                if hits * 2 >= SUB * SUB:
                    self.ink[py][px] = c
        return self

    def dot(self, x, y, color):
        self.ink[y][x] = color if len(color) == 4 else tuple(color) + (255,)
        return self

    def render(self, outline=True):
        img = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
        for y in range(SIZE):
            for x in range(SIZE):
                m = self.mat[y][x]
                if m is None:
                    continue
                shadow, base, light = MATERIALS[m]
                up = self.mat[y - 1][x] if y > 0 else None
                left = self.mat[y][x - 1] if x > 0 else None
                down = self.mat[y + 1][x] if y < SIZE - 1 else None
                right = self.mat[y][x + 1] if x < SIZE - 1 else None
                color = base
                if up != m or left != m:
                    color = light
                if down != m or right != m:
                    color = shadow if (down != m or up == m) else color
                img[y][x] = color + (255,)
        for y in range(SIZE):
            for x in range(SIZE):
                if self.ink[y][x] is not None:
                    img[y][x] = self.ink[y][x]
        if outline:
            out = [row[:] for row in img]
            for y in range(SIZE):
                for x in range(SIZE):
                    if img[y][x][3]:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < SIZE and 0 <= yy < SIZE and img[yy][xx][3]:
                            out[y][x] = OUTLINE
                            break
            img = out
        return img


ICONS = {}


def icon(name):
    def register(fn):
        ICONS[name] = fn
        return fn
    return register


# --- the icons ----------------------------------------------------------------
# Kept in the same order and meaning as the old ASCII grids in ui_icons.gd.

@icon("contracts")
def _contracts(i):
    i.fill(polygon([(6, 3), (21, 3), (26, 8), (26, 29), (6, 29)]), "paper")
    i.fill(polygon([(21, 3), (26, 8), (21, 8)]), "steel")
    for y in (11, 15, 19):
        i.paint(rect(9.5, y, 22.5, y + 1.2), (120, 112, 100))
    i.paint(rect(9.5, 23, 15, 24.2), (120, 112, 100))
    i.fill(circle(21, 23.5, 4.2), "gold")
    i.fill(polygon([(18.5, 26), (20.2, 26), (19.6, 30.5), (17.8, 29.5)]), "red")
    i.fill(polygon([(21.8, 26), (23.5, 26), (24.2, 29.5), (22.4, 30.5)]), "red")
    i.paint(circle(21, 23.5, 1.6), (255, 236, 160))


@icon("dashboard")
def _dashboard(i):
    i.fill(round_rect(2, 4, 30, 23, 1.5), "steel")
    i.fill(rect(4.5, 6.5, 27.5, 20.5), "screen")
    i.fill(rect(14, 23, 18, 27), "steel")
    i.fill(round_rect(8, 26, 24, 29, 1), "dark")
    for (x0, y0, x1, y1) in ((8, 13.5, 13, 18), (13, 18, 23.5, 9)):
        i.paint(segment(x0, y0, x1, y1, 2.4), (240, 184, 60))


@icon("overview")
def _overview(i):
    i.fill(rect(4, 18, 9, 27), "gold")
    i.fill(rect(12, 12, 17, 27), "gold")
    i.fill(rect(20, 5, 25, 27), "gold")
    i.fill(round_rect(2, 27, 30, 30, 0.8), "white")


@icon("staff")
def _staff(i):
    i.fill(round_rect(6, 21, 26, 30, 3), "steel")
    i.fill(rect(14, 21, 18, 30), "gold")
    i.fill(circle(16, 16, 6.5), "skin")
    i.fill(polygon([(8.5, 13.5), (10, 7), (16, 4.5), (22, 7), (23.5, 13.5)]), "yellow")
    i.fill(round_rect(5.5, 12.5, 26.5, 15, 1.2), "gold")
    i.paint(rect(12.5, 17, 14, 19), INK)
    i.paint(rect(18, 17, 19.5, 19), INK)


@icon("transfer")
def _transfer(i):
    i.fill(polygon([(3, 9), (21, 9), (21, 5), (29, 11.5), (21, 18), (21, 14), (3, 14)]), "gold")
    i.fill(polygon([(29, 18), (11, 18), (11, 14.5), (3, 21), (11, 27.5), (11, 23), (29, 23)]), "ember")


@icon("printers")
def _printers(i):
    i.fill(round_rect(4, 3, 28, 29, 2), "steel")
    i.fill(rect(7, 6, 25, 18), "screen")
    i.fill(rect(9, 8, 23, 16), "ember")
    i.fill(rect(14, 9, 18, 12), "dark")
    i.fill(rect(10, 14.5, 22, 16), "brown")
    i.fill(rect(7, 21, 16, 26), "screen")
    i.paint(rect(8.5, 22.5, 14.5, 24), (90, 200, 240))
    i.fill(circle(21.5, 23.5, 1.8), "green")


@icon("settings")
def _settings(i):
    i.fill(gear(16, 16, 14, 10.5, 8, hole=4.2, tooth_frac=0.42), "steel")
    i.paint(ring(16, 16, 6.6, 4.2), (110, 116, 128))


@icon("gold")
def _gold(i):
    i.fill(circle(16, 16, 13), "gold")
    i.paint(ring(16, 16, 10.2, 8.8), (178, 118, 28))
    i.fill(circle(16, 16, 7.6), "yellow")
    i.paint(star(16, 16, 5, 2, points=4), (255, 248, 210))
    i.paint(segment(8.5, 12, 11, 8.5, 1.6), (255, 244, 190))



@icon("gems")
def _gems(i):
    i.fill(polygon([(9, 6), (23, 6), (29, 12.5), (16, 28), (3, 12.5)]), "gem")
    i.paint(polygon([(3.8, 12.5), (28.2, 12.5), (27.5, 13.6), (4.5, 13.6)]), (48, 128, 196))
    i.paint(polygon([(9.5, 7), (13, 7), (10.5, 12), (6, 12)]), (210, 244, 255))
    i.paint(polygon([(16, 14), (19, 14), (16, 25)]), (196, 238, 255))


@icon("reputation")
def _reputation(i):
    i.fill(star(16, 17, 14.5, 6.2), "gold")
    i.paint(polygon([(16, 5), (17.4, 10.5), (16, 12.5), (14.6, 10.5)]), (255, 238, 160))


@icon("attention")
def _attention(i):
    i.fill(circle(16, 16, 14), "ember")
    i.fill(round_rect(13.5, 6, 18.5, 19, 2), "white")
    i.fill(circle(16, 23.5, 2.8), "white")


def wrench(i, material, handle_width):
    i.fill(segment(7, 25, 19, 13, handle_width), material)
    head = circle(22, 10, 7)
    jaw = union(segment(22, 10, 30, 2, 5.2), circle(22, 10, 2.6))
    i.fill(minus(head, jaw), material)


@icon("admin")
def _admin(i):
    wrench(i, "steel", 5)



@icon("badge_ready")
def _badge_ready(i):
    i.fill(circle(16, 16, 14), "green")
    i.paint(segment(9, 16.5, 14, 21.5, 3.2), (250, 255, 245))
    i.paint(segment(14, 21.5, 23.5, 10.5, 3.2), (250, 255, 245))


@icon("badge_running")
def _badge_running(i):
    i.fill(gear(16, 16, 14.5, 10.5, 9, hole=3.8, tooth_frac=0.45), "gold")
    i.paint(ring(16, 16, 6.4, 3.8), (178, 118, 28))


@icon("room_print")
def _room_print(i):
    i.fill(round_rect(3, 8, 29, 26, 2), "steel")
    i.fill(rect(6, 3, 26, 9), "white")
    i.fill(rect(7, 12, 25, 18), "screen")
    i.paint(rect(8.5, 13.5, 18, 15), (90, 200, 240))
    i.fill(rect(7, 21, 25, 29), "white")
    for y in (23.5, 26):
        i.paint(rect(9.5, y, 22, y + 1), (150, 150, 160))
    i.fill(circle(23, 15, 1.5), "green")


@icon("room_shell")
def _room_shell(i):
    i.fill(polygon([(5, 10), (27, 10), (24.5, 29), (7.5, 29)]), "steel")
    i.fill(ellipse(16, 10, 11, 3.6), "white")
    i.fill(ellipse(16, 10, 8.5, 2.2), "paper")
    for y in (16, 21.5):
        i.paint(polygon([(5.8, y), (26.2, y), (26, y + 1.3), (6, y + 1.3)]), (112, 118, 130))
    i.fill(segment(16, 9, 22, 2, 2.4), "wood")


@icon("room_furnace")
def _room_furnace(i):
    i.fill(polygon([(16, 2), (21, 9), (24, 6), (27, 15), (26.5, 22), (22, 28.5), (10, 28.5), (5.5, 22), (5, 15), (9, 7), (11, 11)]), "ember")
    i.fill(polygon([(16, 11), (20, 17), (21, 22.5), (18.5, 27), (13.5, 27), (11, 22.5), (12, 17)]), "yellow")
    i.paint(ellipse(16, 23.5, 2.6, 3), (255, 250, 220))


@icon("room_vim")
def _room_vim(i):
    i.fill(polygon([(5, 8), (27, 8), (24, 27), (8, 27)]), "dark")
    i.fill(ellipse(16, 8, 11, 3.4), "steel")
    i.fill(ellipse(16, 8.4, 8.4, 2.2), "ember")
    i.paint(ellipse(16, 8.4, 5, 1.2), (255, 220, 120))
    for y in (13, 17, 21):
        i.paint(polygon([(6.6, y), (25.4, y), (25.1, y + 1.6), (6.9, y + 1.6)]), (228, 108, 38))
    i.fill(rect(3, 26, 29, 29.5), "steel")


@icon("room_post")
def _room_post(i):
    i.fill(star(16, 16, 14, 3.6, points=4, rotation=-90), "yellow")
    i.fill(star(24.5, 7, 5, 1.6, points=4, rotation=-90), "white")
    i.fill(star(7, 25, 4, 1.3, points=4, rotation=-90), "white")


@icon("act_upgrade")
def _act_upgrade(i):
    i.fill(polygon([(16, 2.5), (28, 15), (21, 15), (21, 29), (11, 29), (11, 15), (4, 15)]), "yellow")


@icon("act_start")
def _act_start(i):
    i.fill(polygon([(7, 4), (27, 16), (7, 28)]), "white")


@icon("act_collect")
def _act_collect(i):
    i.fill(rect(3, 13, 29, 28), "wood")
    i.fill(polygon([(3, 13), (6, 6), (26, 6), (29, 13)]), "brown")
    i.fill(rect(3, 12, 29, 15), "gold")
    i.fill(rect(13.5, 12, 18.5, 19), "gold")
    i.paint(rect(15.2, 15.2, 16.8, 17.2), INK)
    i.paint(rect(3.5, 21, 28.5, 22), (96, 58, 28))


@icon("act_queue")
def _act_queue(i):
    for y in (6, 14, 22):
        i.fill(rect(3, y, 8, y + 4.5), "gold")
        i.fill(round_rect(11, y + 0.5, 29, y + 4, 1), "white")


@icon("act_rack")
def _act_rack(i):
    i.fill(round_rect(3, 3, 29, 29, 1.5), "steel")
    for (x, y) in ((6, 6), (17, 6), (6, 17), (17, 17)):
        i.fill(rect(x, y, x + 9, y + 9), "dark")
    i.fill(rect(7, 7.5, 13.5, 13.5), "gold")
    i.fill(rect(18, 18.5, 24.5, 24.5), "gold")


@icon("act_send")
def _act_send(i):
    i.fill(polygon([(3, 12), (17, 12), (17, 5), (29, 16), (17, 27), (17, 20), (3, 20)]), "white")


@icon("act_scrap")
def _act_scrap(i):
    i.fill(polygon([(7, 10), (25, 10), (23, 29), (9, 29)]), "steel")
    i.fill(round_rect(4, 6, 28, 10, 1), "steel")
    i.fill(round_rect(12, 3, 20, 7, 1), "steel")
    for x in (12, 16, 20):
        i.paint(rect(x - 0.6, 13, x + 0.6, 26), (112, 118, 130))


@icon("act_rework")
def _act_rework(i):
    # A hammer: handle up to the right, head across it.
    i.fill(segment(6, 27, 18.5, 14.5, 4.2), "wood")
    d = (0.7071, -0.7071)   # along the handle
    p = (0.7071, 0.7071)    # across it
    cx, cy = 20.5, 11.5
    corners = []
    for sp, sd in ((-8, -3.6), (8, -3.6), (8, 3.6), (-8, 3.6)):
        corners.append((cx + sp * p[0] + sd * d[0], cy + sp * p[1] + sd * d[1]))
    i.fill(polygon(corners), "steel")
    i.fill(polygon([corners[1], (cx + 10.5 * p[0], cy + 10.5 * p[1]), corners[2]]), "steel")



@icon("act_scan")
def _act_scan(i):
    i.fill(segment(19, 19, 28, 28, 5), "brown")
    i.fill(circle(13, 13, 10.5), "steel")
    i.fill(circle(13, 13, 7.5), "cyan")
    i.paint(segment(9, 10.5, 11.5, 8, 2), (240, 252, 255))


@icon("act_lock")
def _act_lock(i):
    i.fill(arc(16, 13, 9, 5.5, 180, 360), "steel")
    i.fill(rect(7, 12, 9.6, 15), "steel")
    i.fill(rect(22.4, 12, 25, 15), "steel")
    i.fill(round_rect(4, 14, 28, 29, 2), "gold")
    i.fill(circle(16, 20, 2.6), "dark")
    i.fill(rect(15, 21, 17, 25.5), "dark")


@icon("act_refresh")
def _act_refresh(i):
    i.fill(arc(16, 16, 12.5, 8.5, 200, 340), "cyan")
    i.fill(arc(16, 16, 12.5, 8.5, 20, 160), "cyan")
    i.fill(polygon([(24, 4), (31, 11), (21.5, 13)]), "cyan")
    i.fill(polygon([(8, 28), (1, 21), (10.5, 19)]), "cyan")


@icon("act_hire")
def _act_hire(i):
    i.fill(round_rect(3, 19, 21, 30, 3), "blue")
    i.fill(circle(12, 12.5, 6), "skin")
    i.fill(polygon([(6, 11), (8, 5.5), (12, 4.5), (16.5, 5.5), (18, 11)]), "brown")
    i.fill(union(rect(19.5, 17, 29.5, 21), rect(22.5, 14, 26.5, 24)), "green")


@icon("st_warning")
def _st_warning(i):
    i.fill(polygon([(16, 2.5), (30.5, 28.5), (1.5, 28.5)]), "yellow")
    i.fill(round_rect(14.2, 10, 17.8, 20.5, 1.2), "dark")
    i.fill(circle(16, 24.2, 2), "dark")


@icon("st_hourglass")
def _st_hourglass(i):
    i.fill(round_rect(6, 2, 26, 5.5, 1), "wood")
    i.fill(round_rect(6, 26.5, 26, 30, 1), "wood")
    i.fill(polygon([(8, 5.5), (24, 5.5), (17.5, 16), (24, 26.5), (8, 26.5), (14.5, 16)]), "white")
    i.fill(polygon([(11.5, 8.5), (20.5, 8.5), (16, 14)]), "gold")
    i.fill(polygon([(16, 19), (21.5, 26.5), (10.5, 26.5)]), "gold")


@icon("st_clock")
def _st_clock(i):
    i.fill(circle(16, 16, 14), "paper")
    for a in range(0, 360, 90):
        x = 16 + 11 * math.cos(math.radians(a))
        y = 16 + 11 * math.sin(math.radians(a))
        i.paint(circle(x, y, 1.1), (90, 84, 76))
    i.paint(segment(16, 16, 16, 7.5, 2.2), INK)
    i.paint(segment(16, 16, 22, 19, 2.2), INK)
    i.paint(circle(16, 16, 1.6), (218, 66, 56))


@icon("st_info")
def _st_info(i):
    i.fill(circle(16, 16, 14), "blue")
    i.fill(circle(16, 9, 2.4), "white")
    i.fill(union(rect(14, 13, 18, 24), rect(12, 13, 18, 15.5), rect(12, 22, 20, 24.5)), "white")


@icon("st_check")
def _st_check(i):
    i.fill(union(segment(5, 16.5, 12.5, 24.5, 5), segment(12.5, 24.5, 27, 7.5, 5)), "green")


@icon("st_cross")
def _st_cross(i):
    i.fill(union(segment(7, 7, 25, 25, 5), segment(25, 7, 7, 25, 5)), "red")


@icon("role_technician")
def _role_technician(i):
    wrench(i, "steel", 4.2)
    i.fill(segment(5.5, 26.5, 10.5, 21.5, 5.4), "ember")



@icon("role_engineer")
def _role_engineer(i):
    i.fill(gear(16, 16, 14, 10.5, 8, hole=4.2, tooth_frac=0.42), "blue")
    i.paint(ring(16, 16, 6.6, 4.2), (44, 92, 170))


@icon("part_turbine")
def _part_turbine(i):
    i.fill(polygon([(7, 29), (12, 18), (17, 9), (24, 3), (28, 5), (24, 13), (18, 22), (11, 29)]), "steel")
    i.fill(rect(4, 26, 15, 30), "dark")
    i.paint(segment(13, 21, 23, 7, 1.2), (220, 226, 236))


@icon("part_valve")
def _part_valve(i):
    i.fill(rect(2, 13, 30, 22), "steel")
    i.fill(circle(16, 17.5, 8), "steel")
    i.fill(rect(14, 4, 18, 11), "dark")
    i.fill(round_rect(8, 2, 24, 6, 1.5), "red")
    i.fill(rect(1, 11, 4, 24), "dark")
    i.fill(rect(28, 11, 31, 24), "dark")


@icon("part_bracket")
def _part_bracket(i):
    i.fill(union(rect(4, 4, 11, 28), rect(4, 21, 28, 28)), "steel")
    i.erase(circle(7.5, 10, 1.8))
    i.erase(circle(22, 24.5, 1.8))


@icon("part_housing")
def _part_housing(i):
    i.fill(round_rect(3, 6, 29, 26, 3), "steel")
    i.erase(round_rect(8, 11, 24, 21, 2))
    for (x, y) in ((5.5, 8.5), (26.5, 8.5), (5.5, 23.5), (26.5, 23.5)):
        i.paint(circle(x, y, 1.2), (82, 90, 102))


@icon("part_ring")
def _part_ring(i):
    i.fill(ring(16, 16, 13.5, 7.5), "steel")
    i.paint(arc(16, 16, 12, 10.5, 200, 260), (220, 226, 236))


@icon("part_impeller")
def _part_impeller(i):
    blades = []
    for k in range(6):
        a = math.radians(k * 60)
        b = math.radians(k * 60 + 44)
        sweep = 0.42
        blades.append(polygon([
            (16 + 5 * math.cos(a), 16 + 5 * math.sin(a)),
            (16 + 14.5 * math.cos(a + sweep), 16 + 14.5 * math.sin(a + sweep)),
            (16 + 14 * math.cos(b + sweep * 0.6), 16 + 14 * math.sin(b + sweep * 0.6)),
            (16 + 5 * math.cos(b), 16 + 5 * math.sin(b)),
        ]))
    i.fill(union(*blades), "steel")
    i.fill(circle(16, 16, 6), "dark")
    i.fill(circle(16, 16, 2.6), "steel")



@icon("part_shaft")
def _part_shaft(i):
    i.fill(segment(5, 27, 27, 5, 5), "steel")
    i.fill(segment(4, 28, 8, 24, 7.5), "dark")
    i.fill(segment(24, 8, 28, 4, 7.5), "dark")
    i.paint(segment(10, 20.5, 21.5, 9, 1.1), (220, 226, 236))


@icon("part_pendant")
def _part_pendant(i):
    i.fill(ring(16, 6, 3.4, 1.6), "gold")
    i.fill(polygon([(16, 9), (25, 18), (16, 30), (7, 18)]), "gold")
    i.fill(polygon([(16, 13), (20.5, 18), (16, 24.5), (11.5, 18)]), "red")
    i.paint(polygon([(13.5, 16.5), (15.5, 14.5), (15.5, 17)]), (255, 190, 170))


@icon("factory")
def _factory(i):
    i.fill(polygon([(2, 29), (2, 14), (9, 18), (9, 14), (16, 18), (16, 14), (23, 18), (23, 6), (29, 6), (29, 29)]), "steel")
    i.fill(rect(24, 2, 28, 7), "ember")
    for x in (5, 12, 19):
        i.fill(rect(x, 21, x + 4, 25), "white")
    i.fill(rect(23.5, 22, 27.5, 29), "dark")


# --- output -------------------------------------------------------------------

def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rendered = {}
    for name, draw in ICONS.items():
        canvas = Icon()
        draw(canvas)
        rendered[name] = canvas.render()
        write_png(os.path.join(OUT_DIR, name + ".png"), rendered[name])
    # 4x preview sheet, 8 per row, on the dark panel color.
    cols, scale, pad = 8, 4, 8
    names = list(rendered)
    cell = SIZE * scale
    rows_n = (len(names) + cols - 1) // cols
    bg = (30, 31, 36, 255)
    sheet = [[bg] * (cols * (cell + pad) + pad) for _ in range(rows_n * (cell + pad) + pad)]
    for k, name in enumerate(names):
        ox = pad + (k % cols) * (cell + pad)
        oy = pad + (k // cols) * (cell + pad)
        for y in range(cell):
            for x in range(cell):
                p = rendered[name][y // scale][x // scale]
                if p[3]:
                    sheet[oy + y][ox + x] = p
    if len(sys.argv) > 1:
        write_png(sys.argv[1], sheet)
    print("wrote %d icons to %s" % (len(names), OUT_DIR))


if __name__ == "__main__":
    main()
