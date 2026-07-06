#!/usr/bin/env python3
"""Report color distribution and chroma outliers for UI capture PNGs."""

from __future__ import annotations

import argparse
import colorsys
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image


THEME_COLORS = {
    "background": "#0d0d10",
    "inset": "#060608",
    "border": "#62626c",
    "text": "#e8e8ec",
    "muted": "#9a9aa4",
    "transport-accent": "#00ccff",
    "warning": "#ff8738",
    "success": "#4deb85",
    "danger": "#ff5257",
}


@dataclass(frozen=True)
class RGB:
    r: int
    g: int
    b: int

    @property
    def hex(self) -> str:
        return f"#{self.r:02x}{self.g:02x}{self.b:02x}"

    @property
    def hsv(self) -> tuple[float, float, float]:
        return colorsys.rgb_to_hsv(self.r / 255, self.g / 255, self.b / 255)


def parse_hex(value: str) -> RGB:
    raw = value.strip().lower()
    if raw in THEME_COLORS:
        raw = THEME_COLORS[raw]
    raw = raw.removeprefix("#")
    if len(raw) != 6:
        raise argparse.ArgumentTypeError(f"expected #rrggbb or theme token, got {value!r}")
    try:
        return RGB(int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16))
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid color {value!r}") from exc


def srgb_distance(a: RGB, b: RGB) -> float:
    return math.sqrt((a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2)


def hue_distance(a: float, b: float) -> float:
    delta = abs(a - b)
    return min(delta, 1 - delta)


def quantize(value: int, step: int) -> int:
    if step <= 1:
        return value
    bucket = int(round(value / step) * step)
    return max(0, min(255, bucket))


def quantized(rgb: RGB, step: int) -> RGB:
    return RGB(quantize(rgb.r, step), quantize(rgb.g, step), quantize(rgb.b, step))


def iter_pngs(inputs: Iterable[str]) -> list[Path]:
    pngs: list[Path] = []
    for item in inputs:
        path = Path(item).expanduser()
        if path.is_dir():
            pngs.extend(sorted(path.glob("*.png")))
        elif path.suffix.lower() == ".png":
            pngs.append(path)
        else:
            raise SystemExit(f"capture-color-report: not a PNG or directory: {path}")
    seen: set[Path] = set()
    unique: list[Path] = []
    for path in pngs:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(path)
    return unique


def read_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def active_modal_signal(path: Path) -> str | None:
    signal_tokens = ("modal", "chooser")
    active_values = {"open", "true", "1", "yes"}
    for key, value in read_key_values(path.with_suffix(".command.env")).items():
        key_lower = key.lower()
        value_lower = value.lower()
        if value_lower in active_values and any(token in key_lower for token in signal_tokens):
            return key
    return None


def is_modal_surface_pixel(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    luminance = (r + g + b) / 3
    channel_delta = max(r, g, b) - min(r, g, b)
    return 4 <= luminance <= 45 and channel_delta <= 20


def close_mask(mask: bytearray, width: int, height: int, gap: int) -> None:
    for y in range(height):
        row = y * width
        x = 0
        while x < width:
            if mask[row + x]:
                x += 1
                continue
            start = x
            while x < width and not mask[row + x]:
                x += 1
            end = x
            if start > 0 and end < width and end - start <= gap:
                mask[row + start:row + end] = b"\x01" * (end - start)

    for x in range(width):
        y = 0
        while y < height:
            if mask[y * width + x]:
                y += 1
                continue
            start = y
            while y < height and not mask[y * width + x]:
                y += 1
            end = y
            if start > 0 and end < height and end - start <= gap:
                for fill_y in range(start, end):
                    mask[fill_y * width + x] = 1


def detect_modal_bbox(image: Image.Image, args: argparse.Namespace) -> tuple[int, int, int, int] | None:
    rgb_image = image.convert("RGB")
    width, height = rgb_image.size
    pixels = rgb_image.load()
    step = max(1, args.modal_crop_step)
    grid_width = (width + step - 1) // step
    grid_height = (height + step - 1) // step
    mask = bytearray(grid_width * grid_height)

    for grid_y in range(grid_height):
        y = min(height - 1, grid_y * step)
        for grid_x in range(grid_width):
            x = min(width - 1, grid_x * step)
            if is_modal_surface_pixel(pixels[x, y]):
                mask[grid_y * grid_width + grid_x] = 1

    close_mask(mask, grid_width, grid_height, max(1, args.modal_crop_gap // step))

    seen = bytearray(grid_width * grid_height)
    candidates: list[tuple[float, tuple[int, int, int, int]]] = []
    original_area = width * height
    min_area = original_area * (args.modal_crop_min_area_percent / 100)

    for index, value in enumerate(mask):
        if not value or seen[index]:
            continue
        stack = [index]
        seen[index] = 1
        area = 0
        min_x = max_x = index % grid_width
        min_y = max_y = index // grid_width

        while stack:
            current = stack.pop()
            area += 1
            y, x = divmod(current, grid_width)
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
            for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if next_x < 0 or next_x >= grid_width or next_y < 0 or next_y >= grid_height:
                    continue
                neighbor = next_y * grid_width + next_x
                if seen[neighbor] or not mask[neighbor]:
                    continue
                seen[neighbor] = 1
                stack.append(neighbor)

        x1 = min_x * step
        y1 = min_y * step
        x2 = min(width, (max_x + 1) * step)
        y2 = min(height, (max_y + 1) * step)
        bbox_width = x2 - x1
        bbox_height = y2 - y1
        bbox_area = bbox_width * bbox_height
        if bbox_area < min_area:
            continue
        if bbox_width < width * args.modal_crop_min_width_fraction:
            continue
        if bbox_height < height * args.modal_crop_min_height_fraction:
            continue

        center_x = (x1 + x2) / 2
        center_y = (y1 + y2) / 2
        centered = 1 - min(
            1,
            math.sqrt(
                ((center_x - width / 2) / (width / 2)) ** 2
                + ((center_y - height / 2) / (height / 2)) ** 2
            ),
        )
        if centered < args.modal_crop_min_centered_score:
            continue

        grid_bbox_area = (bbox_width / step) * (bbox_height / step)
        rectangularity = area / grid_bbox_area if grid_bbox_area else 0
        score = area * (0.4 + centered) * max(0.25, rectangularity)
        padding = args.modal_crop_padding
        candidates.append((
            score,
            (
                max(0, x1 - padding),
                max(0, y1 - padding),
                min(width, x2 + padding),
                min(height, y2 + padding),
            ),
        ))

    if not candidates:
        return None
    return max(candidates, key=lambda item: item[0])[1]


def crop_image(path: Path, args: argparse.Namespace) -> tuple[Image.Image, dict]:
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    crop = {
        "mode": "full",
        "bbox": [0, 0, width, height],
        "source": None,
        "original_size": [width, height],
        "original_pixels": width * height,
        "coverage_percent": 100.0,
    }
    if args.modal_crop == "off":
        return image, crop

    signal = active_modal_signal(path)
    if not signal:
        return image, crop

    bbox = detect_modal_bbox(image, args)
    if not bbox:
        raise SystemExit(
            f"capture-color-report: expected modal crop for {path.name} from {signal}, but no confident modal panel was found"
        )
    x1, y1, x2, y2 = bbox
    crop_width = x2 - x1
    crop_height = y2 - y1
    crop = {
        "mode": "modal-auto",
        "bbox": [x1, y1, x2, y2],
        "source": signal,
        "original_size": [width, height],
        "original_pixels": width * height,
        "coverage_percent": (crop_width * crop_height / (width * height) * 100) if width and height else 0,
    }
    return image.crop(bbox), crop


def pixel_counts(image: Image.Image) -> tuple[int, Counter[RGB]]:
    pixel_bytes = image.tobytes()
    total = image.width * image.height
    counts: Counter[RGB] = Counter()
    background = parse_hex(THEME_COLORS["background"])

    for index in range(0, len(pixel_bytes), 4):
        r, g, b, a = pixel_bytes[index:index + 4]
        if a < 255:
            alpha = a / 255
            r = round(r * alpha + background.r * (1 - alpha))
            g = round(g * alpha + background.g * (1 - alpha))
            b = round(b * alpha + background.b * (1 - alpha))
        counts[RGB(r, g, b)] += 1

    return total, counts


def classify_neutral(rgb: RGB, grey_saturation: float, grey_delta: int, dark_value: float) -> str | None:
    _, saturation, value = rgb.hsv
    channel_delta = max(rgb.r, rgb.g, rgb.b) - min(rgb.r, rgb.g, rgb.b)
    if saturation > grey_saturation and channel_delta > grey_delta:
        return None
    if value <= dark_value:
        return "dark-grey"
    if value < 0.55:
        return "mid-grey"
    return "light-grey"


def is_allowed_chroma(
    rgb: RGB,
    allowed_colors: list[RGB],
    allowed_hues: list[float],
    distance: float,
    hue_tolerance: float,
) -> bool:
    if any(srgb_distance(rgb, allowed) <= distance for allowed in allowed_colors):
        return True
    hue, _, _ = rgb.hsv
    return any(hue_distance(hue, allowed_hue) <= hue_tolerance for allowed_hue in allowed_hues)


def analyze(path: Path, args: argparse.Namespace) -> dict:
    image, crop = crop_image(path, args)
    total, counts = pixel_counts(image)
    exact_counts: Counter[RGB] = Counter()
    quantized_counts: Counter[RGB] = Counter()
    neutral_counts: Counter[str] = Counter()
    chroma_counts: Counter[RGB] = Counter()
    unexpected_chroma = 0
    chroma_total = 0

    allowed_colors = list(args.allowed_color)
    allowed_hues = [color.hsv[0] for color in allowed_colors]
    semantic_colors = [] if args.no_default_semantics else [
        parse_hex("warning"),
        parse_hex("danger"),
        parse_hex("success"),
    ]
    allowed_colors.extend(semantic_colors)
    allowed_hues.extend(color.hsv[0] for color in semantic_colors)

    for rgb, count in counts.items():
        if args.top_exact:
            exact_counts[rgb] += count
        q = quantized(rgb, args.bin_size)
        quantized_counts[q] += count
        neutral = classify_neutral(rgb, args.grey_saturation, args.grey_delta, args.dark_value)
        if neutral:
            neutral_counts[neutral] += count
            continue
        _, saturation, value = rgb.hsv
        if saturation >= args.chroma_saturation and value >= args.min_chroma_value:
            chroma_total += count
            chroma_counts[q] += count
            if not is_allowed_chroma(
                rgb,
                allowed_colors,
                allowed_hues,
                args.allowed_distance,
                args.hue_tolerance,
            ):
                unexpected_chroma += count

    def pct(count: int) -> float:
        return (count / total * 100) if total else 0

    top_colors = [
        {"hex": color.hex, "count": count, "percent": pct(count)}
        for color, count in quantized_counts.most_common(args.top)
    ]
    top_chroma = [
        {"hex": color.hex, "count": count, "percent": pct(count)}
        for color, count in chroma_counts.most_common(args.top_chroma)
    ]
    exact_top = [
        {"hex": color.hex, "count": count, "percent": pct(count)}
        for color, count in exact_counts.most_common(args.top_exact)
    ]
    neutral = {
        key: {"count": neutral_counts[key], "percent": pct(neutral_counts[key])}
        for key in ("dark-grey", "mid-grey", "light-grey")
    }

    return {
        "file": str(path),
        "pixels": total,
        "crop": crop,
        "neutral": neutral,
        "chroma": {
            "count": chroma_total,
            "percent": pct(chroma_total),
            "unexpected_count": unexpected_chroma,
            "unexpected_percent": pct(unexpected_chroma),
        },
        "top_colors": top_colors,
        "top_chroma": top_chroma,
        "top_exact": exact_top,
    }


def markdown_report(results: list[dict], args: argparse.Namespace) -> str:
    lines = [
        "# Capture Color Report",
        "",
        f"Quantized bin size: {args.bin_size}. Dark grey: saturation <= {args.grey_saturation:.2f}, value <= {args.dark_value:.2f}.",
        f"Unexpected chroma: saturation >= {args.chroma_saturation:.2f}, value >= {args.min_chroma_value:.2f}, outside allowed colors/hues.",
        f"Modal crop: {args.modal_crop}.",
        "",
        "| Capture | Crop | Dark grey | Mid grey | Light grey | Chroma | Unexpected chroma | Top chroma |",
        "|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for result in results:
        neutral = result["neutral"]
        chroma = result["chroma"]
        crop = result.get("crop", {})
        crop_label = "full"
        if crop.get("mode") == "modal-auto":
            crop_label = f"modal {crop.get('coverage_percent', 0):.1f}%"
        top_chroma = ", ".join(
            f"{entry['hex']} {entry['percent']:.2f}%"
            for entry in result["top_chroma"][:5]
        ) or "-"
        lines.append(
            "| {name} | {crop} | {dark:.2f}% | {mid:.2f}% | {light:.2f}% | {chroma:.2f}% | {unexpected:.2f}% | {top} |".format(
                name=Path(result["file"]).name,
                crop=crop_label,
                dark=neutral["dark-grey"]["percent"],
                mid=neutral["mid-grey"]["percent"],
                light=neutral["light-grey"]["percent"],
                chroma=chroma["percent"],
                unexpected=chroma["unexpected_percent"],
                top=top_chroma,
            )
        )

    lines.append("")
    lines.append("## Per-Capture Top Colors")
    for result in results:
        lines.append("")
        lines.append(f"### {Path(result['file']).name}")
        lines.append("")
        lines.append("| Color | Percent | Count |")
        lines.append("|---|---:|---:|")
        for entry in result["top_colors"]:
            lines.append(f"| `{entry['hex']}` | {entry['percent']:.3f}% | {entry['count']} |")
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze capture PNG color percentages, dark greys, and chroma outliers."
    )
    parser.add_argument("inputs", nargs="+", help="PNG file(s) or directories containing top-level PNG captures")
    parser.add_argument("--bin-size", type=int, default=8, help="RGB quantization step for reported color buckets")
    parser.add_argument("--top", type=int, default=12, help="top quantized colors per capture")
    parser.add_argument("--top-chroma", type=int, default=8, help="top chromatic buckets per capture")
    parser.add_argument("--top-exact", type=int, default=0, help="also include exact top colors in JSON")
    parser.add_argument("--grey-saturation", type=float, default=0.08, help="HSV saturation at/below this is treated as grey")
    parser.add_argument("--grey-delta", type=int, default=10, help="RGB max-min delta at/below this is treated as grey, useful for near-black UI colors")
    parser.add_argument("--dark-value", type=float, default=0.18, help="HSV value at/below this is dark grey")
    parser.add_argument("--chroma-saturation", type=float, default=0.18, help="HSV saturation threshold for chromatic pixels")
    parser.add_argument("--min-chroma-value", type=float, default=0.12, help="ignore very dark chromatic antialias pixels below this HSV value")
    parser.add_argument("--allowed-color", action="append", type=parse_hex, default=[parse_hex("transport-accent")], help="allowed chroma color or theme token; repeatable")
    parser.add_argument("--allowed-distance", type=float, default=48, help="RGB distance tolerated around allowed colors")
    parser.add_argument("--hue-tolerance", type=float, default=0.035, help="hue distance tolerated around allowed color hue families")
    parser.add_argument("--no-default-semantics", action="store_true", help="do not automatically allow warning/danger/success hues")
    parser.add_argument("--modal-crop", choices=("auto", "off"), default="auto", help="crop modal/sheet/chooser captures to the detected dialog panel")
    parser.add_argument("--modal-crop-step", type=int, default=2, help="pixel step for modal crop detection")
    parser.add_argument("--modal-crop-gap", type=int, default=24, help="maximum modal-mask gap to close, in pixels")
    parser.add_argument("--modal-crop-padding", type=int, default=6, help="padding to add around detected modal crop")
    parser.add_argument("--modal-crop-min-area-percent", type=float, default=5.0, help="minimum detected modal bbox size as percent of full capture")
    parser.add_argument("--modal-crop-min-width-fraction", type=float, default=0.25, help="minimum detected modal bbox width as fraction of capture width")
    parser.add_argument("--modal-crop-min-height-fraction", type=float, default=0.12, help="minimum detected modal bbox height as fraction of capture height")
    parser.add_argument("--modal-crop-min-centered-score", type=float, default=0.45, help="minimum centeredness score for detected modal bbox")
    parser.add_argument("--json", type=Path, help="write machine-readable report JSON")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    pngs = iter_pngs(args.inputs)
    if not pngs:
        print("capture-color-report: no PNG captures found", file=sys.stderr)
        return 1
    results = [analyze(path, args) for path in pngs]
    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(markdown_report(results, args))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
