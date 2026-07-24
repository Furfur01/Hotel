#!/usr/bin/env python3
"""Prepare generated hotel art for the HUD and high-resolution world cards."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
GENERATED_ICONS = ROOT / "assets" / "icons" / "generated"
FINAL_ICONS = ROOT / "assets" / "icons" / "final"
WORLD_ICONS = ROOT / "assets" / "icons" / "world"
PAINTINGS = ROOT / "assets" / "paintings"
FINAL_PAINTINGS = PAINTINGS / "final"

ICON_ORDER = [
    "staff_card",
    "inspection_mirror",
    "instant_camera",
    "lockpick",
    "pry_bar",
    "alarm_clock",
    "electrician_kit",
    "ratchet_strap",
    "industrial_cleaner",
    "folding_trap",
    "suitcase",
]


def cyan_key(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    rgb = rgba.convert("RGB")
    pixels = rgb.load()
    mask = Image.new("L", rgb.size, 255)
    alpha = mask.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = pixels[x, y]
            distance_sq = r * r + (g - 255) * (g - 255) + (b - 255) * (b - 255)
            if distance_sq < 105 * 105 or (r < 85 and g > 175 and b > 175 and abs(g - b) < 55):
                alpha[x, y] = 0
    mask = mask.filter(ImageFilter.GaussianBlur(0.75))
    rgba.putalpha(mask)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("chroma key removed the complete icon")
    return rgba.crop(bbox)


def fit_icon(source: Image.Image) -> Image.Image:
    target_extent = 29
    scale = min(target_extent / source.width, target_extent / source.height)
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    reduced = source.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    offset = ((32 - reduced.width) // 2, (32 - reduced.height) // 2)
    canvas.alpha_composite(reduced, offset)
    quantized = canvas.quantize(colors=48, method=Image.Quantize.FASTOCTREE).convert("RGBA")
    # Ensure invisible pixels contain no cyan fringe when sampled by the engine.
    transparent = Image.new("RGBA", quantized.size, (0, 0, 0, 0))
    transparent.alpha_composite(quantized)
    return transparent


def remove_edge_key_spill(source: Image.Image) -> Image.Image:
    """Replace cyan matte pixels only when they touch the transparent edge."""
    result = source.copy()
    read = source.load()
    write = result.load()

    def is_spill(pixel: tuple[int, int, int, int]) -> bool:
        r, g, b, a = pixel
        return a > 0 and g > 4 and b > 4 and abs(g - b) < 34 and g > max(1, r) * 1.25 and b > max(1, r) * 1.25

    for y in range(source.height):
        for x in range(source.width):
            pixel = read[x, y]
            if not is_spill(pixel):
                continue
            touches_alpha = False
            for ny in range(max(0, y - 2), min(source.height, y + 3)):
                for nx in range(max(0, x - 2), min(source.width, x + 3)):
                    if read[nx, ny][3] == 0:
                        touches_alpha = True
                        break
                if touches_alpha:
                    break
            if not touches_alpha:
                continue
            replacement = None
            for radius in range(1, 7):
                candidates = []
                for ny in range(max(0, y - radius), min(source.height, y + radius + 1)):
                    for nx in range(max(0, x - radius), min(source.width, x + radius + 1)):
                        candidate = read[nx, ny]
                        if candidate[3] > 48 and not is_spill(candidate):
                            candidates.append((abs(nx - x) + abs(ny - y), -candidate[3], candidate))
                if candidates:
                    candidates.sort(key=lambda entry: (entry[0], entry[1]))
                    replacement = candidates[0][2]
                    break
            if replacement is not None:
                write[x, y] = (*replacement[:3], pixel[3])
    return result


def fit_world_icon(source: Image.Image) -> Image.Image:
    """Use the same 32 logical pixels in-world, stored at a stable 64 px size."""
    pixel_icon = fit_icon(source)
    return pixel_icon.resize((64, 64), Image.Resampling.NEAREST)


def process_icons() -> dict[str, dict[str, int]]:
    FINAL_ICONS.mkdir(parents=True, exist_ok=True)
    WORLD_ICONS.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
    regions: dict[str, dict[str, int]] = {}
    for index, item_id in enumerate(ICON_ORDER):
        source_path = GENERATED_ICONS / f"{item_id}.png"
        keyed_source = cyan_key(Image.open(source_path))
        icon = fit_icon(keyed_source)
        icon.save(FINAL_ICONS / f"{item_id}.png", optimize=True)
        fit_world_icon(keyed_source).save(WORLD_ICONS / f"{item_id}.png", optimize=True)
        column = index % 4
        row = index // 4
        x, y = column * 32, row * 32
        atlas.alpha_composite(icon, (x, y))
        regions[item_id] = {"x": x, "y": y, "w": 32, "h": 32}
    atlas.save(FINAL_ICONS / "item_icons_atlas.png", optimize=True)
    (FINAL_ICONS / "item_icons_atlas.json").write_text(
        json.dumps({"size": [128, 96], "regions": regions}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return regions


def process_paintings() -> None:
    FINAL_PAINTINGS.mkdir(parents=True, exist_ok=True)
    for index in range(1, 9):
        source = Image.open(PAINTINGS / f"portrait_{index:02d}.png").convert("RGB")
        source.thumbnail((256, 384), Image.Resampling.LANCZOS)
        source.quantize(colors=192, method=Image.Quantize.MEDIANCUT).convert("RGB").save(
            FINAL_PAINTINGS / f"portrait_{index:02d}.png", optimize=True
        )


def main() -> None:
    regions = process_icons()
    process_paintings()
    print(f"Prepared {len(regions)} HUD icons, {len(regions)} world icons and 8 portraits.")


if __name__ == "__main__":
    main()
