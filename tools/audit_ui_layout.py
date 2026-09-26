#!/usr/bin/env python3
"""Catches the one UI layout bug this project keeps shipping.

A Control inside an HBoxContainer with autowrap enabled has a minimum width of
roughly zero - it can always wrap harder - so the HBox hands it almost no width
and its text wraps one character per line, turning a short readout into a tall
vertical strip. See CLAUDE.md's "UI layout rules" section for the mechanism and
the three valid fixes.

Scene files are the blind spot: .gd-built rows set custom_minimum_size by hand,
but a Label added in the Godot editor silently inherits autowrap and nothing
catches it until it's on screen.

Usage:  python3 tools/audit_ui_layout.py
Exits 1 if anything is unprotected, so it can gate a commit if wanted.
"""

import glob
import os
import re
import sys

# Controls that render text and therefore can collapse this way.
TEXT_CONTROLS = {"Label", "Button", "CheckBox", "OptionButton", "RichTextLabel"}


def parse_scene(path):
    """Yields (full_node_path, type, parent_path, property_block) per node."""
    text = open(path, encoding="utf-8").read()
    for block in re.split(r"\n(?=\[node )", text):
        m = re.match(r'\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?', block)
        if not m:
            continue
        name, ntype, parent = m.group(1), m.group(2), m.group(3)
        if parent in (None, "."):
            full = name
        else:
            full = f"{parent}/{name}"
        yield full, ntype, parent, block


def audit(path):
    types_by_path = {}
    findings = []
    for full, ntype, parent, block in parse_scene(path):
        types_by_path[full] = ntype
        if ntype not in TEXT_CONTROLS:
            continue
        if "HBoxContainer" not in types_by_path.get(parent, ""):
            continue

        wraps = re.search(r"^autowrap_mode = [1-3]$", block, re.M)
        if not wraps:
            continue  # no autowrap -> minimum width is the real text width

        # The three valid defenses, any one of which is enough.
        has_min_width = re.search(r"^custom_minimum_size = Vector2\(\s*([1-9]\d*(\.\d+)?)", block, re.M)
        expands = re.search(r"^size_flags_horizontal = 3$", block, re.M)
        clips = re.search(r"^clip_text = true$", block, re.M)
        if has_min_width or expands or clips:
            continue

        findings.append(full)
    return findings


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    total = 0
    for path in sorted(glob.glob("scenes/**/*.tscn", recursive=True)):
        findings = audit(path)
        if not findings:
            continue
        print(f"{path}:")
        for node in findings:
            print(f"  {node}")
            print("    autowrap inside an HBoxContainer with no width floor -")
            print("    will collapse to one character per line. Give it")
            print("    custom_minimum_size.x, size_flags_horizontal = 3, or drop autowrap.")
        total += len(findings)

    if total:
        print(f"\n{total} unprotected control(s). See CLAUDE.md > UI layout rules.")
        return 1
    print("UI layout audit: no unprotected autowrap-in-HBox controls.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
