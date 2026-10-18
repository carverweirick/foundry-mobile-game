#!/usr/bin/env python3
"""Builds assets/fonts/vt323_hd.ttf, the "HD" text font (Settings > Text).

VT323 (SIL OFL 1.1, no Reserved Font Name - see assets/fonts/VT323-OFL.txt) has roughly
twice m5x7's vertical pixel detail, but at the same nominal size it's 1.167x
wider, which would overflow every menu's width budget (CLAUDE.md UI rule 2).
Rather than rescale every font size in the game, this raises the font's
unitsPerEm by that ratio: at any nominal size it then renders exactly as
wide as m5x7 does, so every existing size constant and layout stays valid.
Nothing else in the font changes (metrics are all relative to the em).

Run from the project root:  python3 tools/make_text_font.py
Standard library only.
"""
import os
import struct

SRC = os.path.join("tools", "font_src", "VT323-Regular.ttf")  # .gdignore'd: not shipped
OUT = os.path.join("assets", "fonts", "vt323_hd.ttf")
# Measured: the same UI sample string is 363px in VT323 vs 311px in m5x7 at 14px.
WIDTH_RATIO = 363.0 / 311.0


def main():
    data = bytearray(open(SRC, "rb").read())
    num_tables = struct.unpack(">H", data[4:6])[0]
    head = None
    for i in range(num_tables):
        tag, _, offset, length = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        if tag == b"head":
            head = (offset, length, 12 + 16 * i)
    offset, length, record = head
    units = struct.unpack(">H", data[offset + 18:offset + 20])[0]
    new_units = round(units * WIDTH_RATIO)
    struct.pack_into(">H", data, offset + 18, new_units)
    # Keep the file's checksums honest: head's own table checksum (computed
    # with checkSumAdjustment zeroed), then the whole-file adjustment.
    struct.pack_into(">I", data, offset + 8, 0)

    def checksum(chunk):
        chunk = bytes(chunk) + b"\0" * (-len(chunk) % 4)
        return sum(struct.unpack(">%dI" % (len(chunk) // 4), chunk)) & 0xFFFFFFFF

    struct.pack_into(">I", data, record + 4, checksum(data[offset:offset + length]))
    struct.pack_into(">I", data, offset + 8, (0xB1B0AFBA - checksum(data)) & 0xFFFFFFFF)
    open(OUT, "wb").write(data)
    print("unitsPerEm %d -> %d, wrote %s" % (units, new_units, OUT))


if __name__ == "__main__":
    main()
