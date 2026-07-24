#!/usr/bin/env python3
"""Split Imagegen notebook marks and pictograms into small transparent assets."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "ui" / "generated_source"
MARKS = ROOT / "assets" / "ui" / "notebook_marks"
HEADERS = ROOT / "assets" / "ui" / "notebook_headers"


def fit_region(source: Image.Image, x0: int, x1: int, extent: int = 96) -> Image.Image:
    region = source.crop((x0, 0, x1, source.height))
    alpha_box = region.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError(f"empty generated region: {x0}..{x1}")
    region = region.crop(alpha_box)
    inner = extent - 12
    scale = min(inner / region.width, inner / region.height)
    size = (max(1, round(region.width * scale)), max(1, round(region.height * scale)))
    region = region.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (extent, extent), (0, 0, 0, 0))
    canvas.alpha_composite(region, ((extent - size[0]) // 2, (extent - size[1]) // 2))
    return canvas


def recolor_ink(source: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    ink = Image.new("RGBA", source.size, (*color, 255))
    ink.putalpha(source.getchannel("A"))
    return ink


def main() -> None:
    MARKS.mkdir(parents=True, exist_ok=True)
    HEADERS.mkdir(parents=True, exist_ok=True)

    marks = Image.open(SOURCE / "evidence_marks_alpha.png").convert("RGBA")
    for name, bounds in {
        "vacant_check": (150, 720),
        "rented_cross": (990, 1530),
    }.items():
        fit_region(marks, *bounds).save(MARKS / f"{name}.png", optimize=True)

    headers = Image.open(SOURCE / "evidence_headers_alpha.png").convert("RGBA")
    for name, bounds in {
        "registration": (80, 470),
        "doorstep": (490, 860),
        "listen": (900, 1140),
        "knock": (1170, 1490),
        "interior": (1540, 1920),
    }.items():
        recolor_ink(fit_region(headers, *bounds), (57, 42, 30)).save(
            HEADERS / f"{name}.png", optimize=True
        )

    print("Prepared 2 Imagegen marks and 5 Imagegen notebook headers at 96x96 RGBA.")


if __name__ == "__main__":
    main()
