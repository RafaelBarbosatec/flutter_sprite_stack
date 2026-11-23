#!/usr/bin/env python3
"""Pack per-frame strips into the vertical atlas `flutter_sprite_stack` reads.

The package expects one PNG where frame `0` is the top row, frame `1` the next,
and so on. Every frame must have the exact same `(width, height)` — otherwise
the atlas cannot be split into equal cells and `SpriteStack.load` throws.

Usage:

    # f0.png … f5.png in order
    python3 make_atlas.py torch_atlas.png f0.png f1.png f2.png f3.png f4.png

    # or let the shell expand a zero-padded sequence
    python3 make_atlas.py torch_atlas.png frames/f00.png frames/f01.png

    # validate the result in the same run
    python3 make_atlas.py atlas.png frame_*.png --slices 14

The output is always written losslessly as 8-bit RGBA (no quantization), so the
demo assets stay byte-for-byte predictable between runs.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from png_rw import PngError, read_png, write_png  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stack frame PNGs vertically into a sprite-stack atlas.",
    )
    parser.add_argument("output", help="atlas PNG to write")
    parser.add_argument("frames", nargs="+", help="frame PNGs, first frame first")
    parser.add_argument(
        "--slices",
        type=int,
        help="also check that the atlas width splits into this many slices",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite the output if it already exists",
    )
    args = parser.parse_args()

    output = Path(args.output)
    if output.exists() and not args.force:
        print(f"ERROR: {output} exists; pass --force to overwrite", file=sys.stderr)
        return 1
    if len(args.frames) < 1:
        print("ERROR: at least one frame is required", file=sys.stderr)
        return 2

    decoded: list[tuple[int, int, bytearray]] = []
    for name in args.frames:
        try:
            decoded.append(read_png(name))
        except (OSError, PngError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

    width, height = decoded[0][0], decoded[0][1]
    mismatched = [
        f"{Path(name).name} is {w}x{h}"
        for name, (w, h, _) in zip(args.frames, decoded)
        if (w, h) != (width, height)
    ]
    if mismatched:
        print(
            f"ERROR: frames must share one size; expected {width}x{height}",
            file=sys.stderr,
        )
        for line in mismatched:
            print(f"  - {line}", file=sys.stderr)
        print(
            "  Fix the frames (same camera, same pivot, same canvas) instead of "
            "padding them: padding shifts the pivot.",
            file=sys.stderr,
        )
        return 1

    if args.slices is not None:
        if args.slices <= 0 or width % args.slices != 0:
            print(
                f"ERROR: width {width} does not split into {args.slices} slices",
                file=sys.stderr,
            )
            return 1

    atlas = bytearray()
    for _, _, rgba in decoded:
        atlas += rgba

    write_png(output, width, height * len(decoded), atlas)

    print(f"wrote {output}")
    print(f"  image      {width}x{height * len(decoded)}")
    print(f"  frames     {len(decoded)} (frame 0 on top)")
    print(f"  frame size {width}x{height}")
    if args.slices:
        print(f"  slices     {args.slices} x {width // args.slices} px")

    try:
        print(f"  bytes      {output.stat().st_size:,}")
    except OSError:
        pass

    print("\nNext: validate it")
    frames_arg = f" --frames {len(decoded)}" if len(decoded) > 1 else ""
    slices_arg = f"--slices {args.slices}" if args.slices else "--slice-width <px>"
    print(f"  python3 validate_atlas.py {output} {slices_arg}{frames_arg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
