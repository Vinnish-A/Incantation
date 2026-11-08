"""Check actual pixels and PDF text after validate-real-panels.R."""

import collections
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image
import pymupdf

root = Path(sys.argv[1])
receipt = json.loads((root / "real_panel_checks.json").read_text())
images = {
    name: np.asarray(Image.open(root / f"C_{name}.png").convert("RGBA"))
    for name in ("before", "micro", "restored", "replay")
}
changed = np.any(images["before"] != images["micro"], axis=2)
height, width = changed.shape
canvas_w, canvas_h = np.array(receipt["canvas_mm"]) * 72 / 25.4
box = receipt["target_outer_before_pt"]
dx = receipt["micro_dx_mm"] * 72 / 25.4
left = max(0, int(np.floor(box["left"] / canvas_w * width)) - 2)
right = min(width, int(np.ceil((box["right"] + dx) / canvas_w * width)) + 2)
top = max(0, int(np.floor((canvas_h - box["top"]) / canvas_h * height)) - 2)
bottom = min(height, int(np.ceil((canvas_h - box["bottom"]) / canvas_h * height)) + 2)
allowed = np.zeros(changed.shape, dtype=bool)
allowed[top:bottom, left:right] = True


def glyphs(path):
    with pymupdf.open(path) as document:
        return collections.Counter(
            (span["text"], span["font"], round(span["size"], 5), span["color"])
            for block in document[0].get_text("dict")["blocks"]
            if "lines" in block
            for line in block["lines"]
            for span in line["spans"]
        )


with pymupdf.open(root / "C_before.pdf") as document:
    fonts = sorted({font[3] for font in document[0].get_fonts()})
checks = {
    "changed_pixels": int(changed.sum()),
    "outside_target_pixels": int(np.count_nonzero(changed & ~allowed)),
    "restored_pixels_exact": bool(np.array_equal(images["before"], images["restored"])),
    "replay_pixels_exact": bool(np.array_equal(images["micro"], images["replay"])),
    "pdf_text_font_size_colour_preserved": glyphs(root / "C_before.pdf")
    == glyphs(root / "C_micro.pdf"),
    "pdf_fonts": fonts,
    "warnings": receipt["warnings"],
}
if len(sys.argv) > 2:
    native = np.asarray(Image.open(sys.argv[2]).convert("RGBA"))
    captured = np.asarray(Image.open(root / "C_ragg.png").convert("RGBA"))
    checks["native_ragg_pixels_exact"] = bool(np.array_equal(native, captured))
    assert checks["native_ragg_pixels_exact"], checks
assert checks["changed_pixels"] > 0 and checks["outside_target_pixels"] == 0, checks
assert checks["restored_pixels_exact"] and checks["replay_pixels_exact"], checks
assert checks["pdf_text_font_size_colour_preserved"], checks
assert fonts and all("Arial" in font for font in fonts), checks
assert not checks["warnings"], checks
for name in ("A", "C_before", "C_micro", "C_restored", "C_replay"):
    with pymupdf.open(root / f"{name}.pdf") as document:
        document[0].get_pixmap(matrix=pymupdf.Matrix(2, 2)).save(
            root / f"{name}_pdf_preview.png"
        )
(root / "pixel_and_pdf_checks.json").write_text(json.dumps(checks, indent=2) + "\n")
print(json.dumps(checks, indent=2))
