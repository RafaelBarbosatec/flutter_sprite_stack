#!/usr/bin/env python3
"""Validate a sprites-stack strip or frame atlas before it reaches the renderer.

Catches the mistakes that are invisible in a PNG viewer and obvious in game:

* dimensions that do not split into whole slices/frames
* an opaque background (the renderer expects transparency)
* empty slices, which render as a gap between the prop's cross-sections
* slices whose content wanders sideways, which makes the prop wobble as it turns
* frame-to-frame pivot drift, which makes an animation jitter
* anti-aliased edges, which look like a halo around pixel art

Usage:

    python3 validate_atlas.py sprite.png --slices 24
    python3 validate_atlas.py atlas.png  --slices 14 --frames 5
    python3 validate_atlas.py atlas.png  --slice-width 32 --frames 5 --json

Exit code is 0 when the asset is usable (warnings allowed) and 1 on errors.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from png_rw import PngError, read_png  # noqa: E402

SEMI_ALPHA_WARN_RATIO = 0.02  # >2% of painted pixels being translucent is odd
DRIFT_WARN_RATIO = 0.35  # share of the slice width a well-pivoted prop may drift
DRIFT_WARN_MIN_PX = 2.0


class Stats:
    """Per-slice measurements for one frame."""

    __slots__ = (
        "index",
        "painted",
        "semi",
        "min_x",
        "max_x",
        "min_y",
        "max_y",
        "sum_x",
    )

    index: int
    painted: int
    semi: int
    min_x: int | None
    max_x: int | None
    min_y: int | None
    max_y: int | None
    sum_x: int

    def __init__(self, index: int) -> None:
        self.index = index
        self.painted = 0
        self.semi = 0
        self.min_x = None
        self.max_x = None
        self.min_y = None
        self.max_y = None
        self.sum_x = 0

    @property
    def empty(self) -> bool:
        return self.painted == 0

    @property
    def center_x(self) -> float:
        if not self.painted:
            return 0.0
        assert self.min_x is not None and self.max_x is not None
        return (self.min_x + self.max_x + 1) / 2.0

    @property
    def width(self) -> int:
        if not self.painted:
            return 0
        assert self.min_x is not None and self.max_x is not None
        return self.max_x - self.min_x + 1

    def as_dict(self) -> dict:
        return {
            "slice": self.index,
            "painted": self.painted,
            "empty": self.empty,
            "center_x": round(self.center_x, 2),
            "width": self.width,
        }


def analyze_frame(
    rgba: bytearray,
    width: int,
    slice_width: int,
    slice_height: int,
    frame_index: int,
    frame_count: int,
    slice_count: int,
) -> tuple[list[Stats], float]:
    stats = [Stats(i) for i in range(slice_count)]
    semi_total = 0
    painted_total = 0
    top_row = frame_index * slice_height

    for y in range(slice_height):
        row = (top_row + y) * width * 4
        for s in range(slice_count):
            st = stats[s]
            base = row + s * slice_width * 4
            for x in range(slice_width):
                offset = base + x * 4
                alpha = rgba[offset + 3]
                if alpha != 0:
                    st.painted += 1
                    painted_total += 1
                    st.sum_x += x
                    if st.min_x is None or x < st.min_x:
                        st.min_x = x
                    if st.max_x is None or x > st.max_x:
                        st.max_x = x
                    if st.min_y is None or y < st.min_y:
                        st.min_y = y
                    if st.max_y is None or y > st.max_y:
                        st.max_y = y
                    if alpha != 255:
                        st.semi += 1
                        semi_total += 1

    ratio = (semi_total / painted_total) if painted_total else 0.0
    return stats, ratio


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a sprite-stack strip or vertical frame atlas.",
    )
    parser.add_argument("image", help="PNG strip or atlas")
    parser.add_argument("--slices", type=int, help="number of slices per frame")
    parser.add_argument(
        "--slice-width",
        type=int,
        help="slice width in pixels (alternative to --slices)",
    )
    parser.add_argument("--frames", type=int, default=1, help="frames in the atlas")
    parser.add_argument(
        "--allow-empty-slices",
        action="store_true",
        help="do not report empty slices between painted ones",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="treat warnings as errors (use it in CI)",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--quiet", action="store_true", help="only print problems")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []

    try:
        width, height, rgba = read_png(args.image)
    except (OSError, PngError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.slices and args.slice_width:
        print("ERROR: pass --slices or --slice-width, not both", file=sys.stderr)
        return 2
    if not args.slices and not args.slice_width:
        print("ERROR: pass --slices or --slice-width", file=sys.stderr)
        return 2
    if args.frames < 1:
        print("ERROR: --frames must be >= 1", file=sys.stderr)
        return 2

    if args.slices:
        if width % args.slices != 0:
            errors.append(
                f"width {width} is not divisible by {args.slices} slices",
            )
            slice_count = args.slices
            slice_width = width // args.slices
        else:
            slice_count = args.slices
            slice_width = width // slice_count
    else:
        slice_width = args.slice_width
        if width % slice_width != 0:
            errors.append(
                f"width {width} is not divisible by slice width {slice_width}",
            )
        slice_count = width // slice_width

    if height % args.frames != 0:
        errors.append(
            f"height {height} is not divisible by {args.frames} frames",
        )
    slice_height = height // args.frames

    if all(rgba[i] == 255 for i in range(3, len(rgba), 4)):
        errors.append(
            "no transparent pixels at all: the background looks opaque; the "
            "renderer composites the whole slice cell",
        )

    if slice_width <= 0 or slice_height <= 0:
        errors.append("degenerate slice size")
        slice_count = max(slice_count, 0)

    frames: list[dict] = []
    padding: dict[tuple[int, ...], list[int]] = {}
    for frame in range(args.frames if slice_height > 0 else 0):
        stats, semi_ratio = analyze_frame(
            rgba,
            width,
            slice_width,
            slice_height,
            frame,
            args.frames,
            slice_count,
        )

        empty = [st.index for st in stats if st.empty]
        painted_slices = [st.index for st in stats if not st.empty]
        if not painted_slices:
            errors.append(f"frame {frame}: every slice is empty (blank frame)")
        else:
            first = min(painted_slices)
            last = max(painted_slices)

            # Index 0 is the ground cross-section and the highest index is the
            # top of the prop, so the three kinds of hole mean different things.
            below = [i for i in empty if i < first]
            above = [i for i in empty if i > last]
            internal = [i for i in empty if first < i < last]

            if below:
                errors.append(
                    f"frame {frame}: slices {_summarize(below)} below the first "
                    "painted slice are empty; the prop floats above its ground "
                    "point and its shadow",
                )
            if internal and not args.allow_empty_slices:
                warnings.append(
                    f"frame {frame}: slices {_summarize(internal)} between "
                    "painted slices are empty; the prop will show a gap there "
                    "(carving artifact or real hollow geometry)",
                )
            if above:
                padding.setdefault(tuple(above), []).append(frame)

        visible = [st for st in stats if not st.empty]
        drift = 0.0
        if len(visible) > 1:
            # Tiny fragments (a chimney's top voxels) have meaningless box
            # centres, so weight the check towards slices that carry mass.
            heaviest = max(st.painted for st in visible)
            measured = [
                st for st in visible if st.painted >= heaviest * 0.15
            ]
            offsets = [st.center_x - slice_width / 2.0 for st in measured]
            if len(offsets) > 1:
                median = sorted(offsets)[len(offsets) // 2]
                drift = max(abs(value - median) for value in offsets)
                limit = max(DRIFT_WARN_MIN_PX, slice_width * DRIFT_WARN_RATIO)
                if drift > limit:
                    warnings.append(
                        f"frame {frame}: slice content drifts {drift:.1f} px "
                        f"from the slice axis (limit {limit:.1f}); check the "
                        "pivot — a tool that crops every slice to its own "
                        "bounds makes the prop wobble while rotating",
                    )

        if semi_ratio > SEMI_ALPHA_WARN_RATIO:
            warnings.append(
                f"frame {frame}: {semi_ratio * 100:.1f}% of painted pixels are "
                "semi-transparent; pixel art usually wants hard alpha",
            )

        frames.append(
            {
                "frame": frame,
                "empty_slices": empty,
                "drift_px": round(drift, 2),
                "semi_alpha_ratio": round(semi_ratio, 4),
                "bbox_width": max((st.width for st in stats), default=0),
                "slices": [st.as_dict() for st in stats],
            }
        )

    for slices, frame_indices in sorted(padding.items(), key=lambda kv: kv[1][0]):
        warnings.append(
            f"frame(s) {_summarize(frame_indices)}: slices "
            f"{_summarize(list(slices))} at the top are empty padding; harmless "
            "but wasted memory (reduce sliceCount if no animation needs headroom)",
        )

    if args.strict and warnings:
        errors.extend(f"strict: {warning}" for warning in warnings)
        warnings = []

    if len(frames) > 1:
        widths = [f["bbox_width"] for f in frames]
        if widths and max(widths) - min(widths) > 1:
            warnings.append(
                "frames have different silhouette widths "
                f"({min(widths)}..{max(widths)} px); "
                "check that every frame shares the same pivot and camera",
            )

    report = {
        "file": str(args.image),
        "width": width,
        "height": height,
        "slices": slice_count,
        "frames": args.frames,
        "slice_width": slice_width,
        "slice_height": slice_height,
        "errors": errors,
        "warnings": warnings,
        "detail": frames,
        "ok": not errors,
    }

    if args.json:
        print(json.dumps(report, indent=2))
        return 1 if errors else 0

    if not args.quiet or errors or warnings:
        print(f"file        {args.image}")
        print(f"image       {width}x{height}")
        print(f"layout      {slice_count} slices x {args.frames} frames")
        print(f"slice size  {slice_width}x{slice_height}")
        print()

    if not args.quiet and frames:
        print(f"{'frame':>5} {'slices':>6} {'empty':>6} {'drift':>7} {'semi%':>6}")
        for frame in frames:
            print(
                f"{frame['frame']:>5} {slice_count:>6} "
                f"{len(frame['empty_slices']):>6} "
                f"{frame['drift_px']:>7.1f} "
                f"{frame['semi_alpha_ratio'] * 100:>5.1f}%"
            )
        print()

    for warning in warnings:
        print(f"WARN:  {warning}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)

    if errors:
        print(f"\nFAIL: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1

    print(f"OK: {slice_count * args.frames} slices checked, "
          f"{len(warnings)} warning(s)")
    return 0


def _summarize(indices: list[int], limit: int = 8) -> str:
    shown = ", ".join(str(i) for i in indices[:limit])
    if len(indices) > limit:
        return f"{shown}, … (+{len(indices) - limit})"
    return shown


if __name__ == "__main__":
    raise SystemExit(main())
