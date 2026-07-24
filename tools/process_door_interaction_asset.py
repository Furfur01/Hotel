#!/usr/bin/env python3
"""Build the low-resolution FPS door-interaction sprite sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
HAND_SOURCE = ROOT / "assets" / "player" / "generated_source" / "door_interaction_magenta.png"
OUTPUT = ROOT / "assets" / "player" / "door_interaction_frames_v2.png"
FRAME_SIZE = (128, 160)
COLUMNS = 4
ROWS = 2


def _is_key_or_spill(red: int, green: int, blue: int, key: tuple[int, int, int]) -> bool:
    # The generated backdrop is nearly flat, so a hard key preserves the intended
    # chunky sprite edges.  The second clause removes the one-pixel magenta fringe
    # without desaturating the burgundy sleeve.
    if max(abs(red - key[0]), abs(green - key[1]), abs(blue - key[2])) <= 30:
        return True
    return red >= 105 and blue >= 82 and green <= 72 and blue >= green * 1.45


def _remove_hand_key(source: Image.Image) -> Image.Image:
    border_samples: list[tuple[int, int, int]] = []
    width, height = source.size
    for x in range(width):
        border_samples.append(source.getpixel((x, 0))[:3])
        border_samples.append(source.getpixel((x, height - 1))[:3])
    for y in range(height):
        border_samples.append(source.getpixel((0, y))[:3])
        border_samples.append(source.getpixel((width - 1, y))[:3])
    border_samples.sort()
    key = border_samples[len(border_samples) // 2]

    cleaned = Image.new("RGBA", source.size, (0, 0, 0, 0))
    clean_pixels = cleaned.load()
    source_pixels = source.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, _alpha = source_pixels[x, y]
            if not _is_key_or_spill(red, green, blue, key):
                clean_pixels[x, y] = (red, green, blue, 255)
    return cleaned


def _anchor_bottom_right(frame: Image.Image) -> Image.Image:
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return frame
    shift_x = frame.width - bbox[2]
    shift_y = frame.height - bbox[3]
    anchored = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    anchored.alpha_composite(frame, (shift_x, shift_y))
    return anchored


def _hand_frames() -> list[Image.Image]:
    source = _remove_hand_key(Image.open(HAND_SOURCE).convert("RGBA"))
    cell_width = source.width // 4
    cell_height = source.height // 2
    frames: list[Image.Image] = []
    for row in range(2):
        for column in range(4):
            frame = source.crop((
                column * cell_width,
                row * cell_height,
                (column + 1) * cell_width,
                (row + 1) * cell_height,
            ))
            frame = _anchor_bottom_right(frame)
            frames.append(frame.resize(FRAME_SIZE, Image.Resampling.NEAREST))
    return frames


def main() -> None:
    frames = _hand_frames()
    if len(frames) != COLUMNS * ROWS:
        raise RuntimeError(f"expected {COLUMNS * ROWS} frames, got {len(frames)}")
    sheet = Image.new(
        "RGBA",
        (FRAME_SIZE[0] * COLUMNS, FRAME_SIZE[1] * ROWS),
        (0, 0, 0, 0),
    )
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (
            (index % COLUMNS) * FRAME_SIZE[0],
            (index // COLUMNS) * FRAME_SIZE[1],
        ))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT, optimize=True)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
