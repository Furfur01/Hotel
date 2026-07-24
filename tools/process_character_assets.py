#!/usr/bin/env python3
"""Crop generated characters into deliberately low-resolution Nextbot sprites."""

from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "characters" / "generated_source"
OUTPUT_DIR = ROOT / "assets" / "characters" / "final"
CANVAS_SIZE = (96, 160)
SUBJECT_MAX = (88, 152)
FACE_SIZE = (96, 96)


def process_character(name: str) -> None:
    source = Image.open(SOURCE_DIR / f"{name}_alpha.png").convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None:
        raise RuntimeError(f"{name}: generated cutout has no visible subject")

    subject = source.crop(bbox)
    scale = min(SUBJECT_MAX[0] / subject.width, SUBJECT_MAX[1] / subject.height)
    target_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(target_size, Image.Resampling.LANCZOS)
    subject = ImageEnhance.Contrast(subject).enhance(1.08)
    subject = ImageEnhance.Color(subject).enhance(0.90)
    subject = subject.filter(ImageFilter.UnsharpMask(radius=0.8, percent=125, threshold=3))

    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    x = (CANVAS_SIZE[0] - subject.width) // 2
    y = CANVAS_SIZE[1] - subject.height - 5
    canvas.alpha_composite(subject, (x, y))
    canvas.save(OUTPUT_DIR / f"{name}.png", optimize=True)

    # A separate deliberately coarse face crop is used by the capture sting.
    # Crop from the high-resolution cutout first so each role keeps its hat,
    # hair and malformed facial silhouette, then quantize to Nextbot pixels.
    face_box = (
        round(source.width * 0.22),
        0,
        round(source.width * 0.78),
        round(source.height * 0.34),
    )
    face = source.crop(face_box)
    face.thumbnail((64, 64), Image.Resampling.LANCZOS)
    face_canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    face_canvas.alpha_composite(face, ((64 - face.width) // 2, (64 - face.height) // 2))
    face_canvas = face_canvas.resize(FACE_SIZE, Image.Resampling.NEAREST)
    face_canvas = ImageEnhance.Contrast(face_canvas).enhance(1.18)
    face_canvas.save(OUTPUT_DIR / f"{name}_face.png", optimize=True)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for character_name in ("guard", "cleaner", "tenant"):
        process_character(character_name)
        print(f"wrote assets/characters/final/{character_name}.png")


if __name__ == "__main__":
    main()
