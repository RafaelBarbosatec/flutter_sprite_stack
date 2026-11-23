#!/usr/bin/env python3
"""Tiny PNG reader/writer used by the sprite-stack asset scripts.

Standard library only: no Pillow, no numpy. That matters because these scripts
are meant to run inside an AI agent session where installing packages is slow or
impossible.

Supported input (enough for every sprite sheet and atlas we have seen):

* 8-bit channels, non-interlaced
* color types 0 (gray), 2 (RGB), 3 (palette), 4 (gray + alpha), 6 (RGBA)

Everything is normalized to RGBA8888 so callers never branch on color type.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIGNATURE = b"\x89PNG\r\n\x1a\n"

_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PngError(Exception):
    """Raised when a file is not a PNG we can decode."""


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytearray:
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0

    for y in range(height):
        if pos >= len(raw):
            raise PngError("truncated image data")
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        if len(line) != stride:
            raise PngError("truncated scanline")
        pos += stride

        if filter_type == 1:  # Sub
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif filter_type == 2:  # Up
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif filter_type == 3:  # Average
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif filter_type == 4:  # Paeth
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                up_left = prev[x - channels] if x >= channels else 0
                line[x] = (line[x] + _paeth(left, prev[x], up_left)) & 0xFF
        elif filter_type != 0:
            raise PngError(f"unknown filter type {filter_type}")

        out[y * stride:(y + 1) * stride] = line
        prev = line

    return out


def read_png(path: str | Path) -> tuple[int, int, bytearray]:
    """Decode *path* and return ``(width, height, rgba_bytes)``."""
    data = Path(path).read_bytes()
    if not data.startswith(SIGNATURE):
        raise PngError(f"{path}: not a PNG file")

    pos = len(SIGNATURE)
    width = height = 0
    depth = color_type = 0
    interlace = 0
    palette: bytes | None = None
    transparency: bytes | None = None
    idat = bytearray()

    while pos < len(data):
        if pos + 8 > len(data):
            raise PngError(f"{path}: truncated chunk header")
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length:
            raise PngError(f"{path}: truncated {tag!r} chunk")
        pos += 12 + length

        if tag == b"IHDR":
            width, height, depth, color_type, comp, filt, interlace = (
                struct.unpack(">IIBBBBB", body)
            )
            if comp != 0 or filt != 0:
                raise PngError(f"{path}: unsupported compression/filter method")
        elif tag == b"PLTE":
            palette = body
        elif tag == b"tRNS":
            transparency = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break

    if not width or not height:
        raise PngError(f"{path}: missing IHDR")
    if depth != 8:
        raise PngError(f"{path}: only 8-bit channels are supported (got {depth})")
    if interlace != 0:
        raise PngError(f"{path}: interlaced PNGs are not supported")
    if color_type not in _CHANNELS:
        raise PngError(f"{path}: unsupported color type {color_type}")

    channels = _CHANNELS[color_type]
    pixels = _unfilter(zlib.decompress(bytes(idat)), width, height, channels)

    rgba = bytearray(width * height * 4)

    if color_type == 6:
        rgba[:] = pixels
    elif color_type == 3:
        if palette is None:
            raise PngError(f"{path}: palette image without PLTE")
        for i, index in enumerate(pixels):
            base = index * 3
            if base + 2 >= len(palette):
                raise PngError(f"{path}: palette index {index} out of range")
            rgba[i * 4] = palette[base]
            rgba[i * 4 + 1] = palette[base + 1]
            rgba[i * 4 + 2] = palette[base + 2]
            rgba[i * 4 + 3] = (
                transparency[index]
                if transparency is not None and index < len(transparency)
                else 255
            )
    elif color_type in (0, 4):
        gray_alpha = color_type == 4
        for i in range(width * height):
            value = pixels[i * channels]
            rgba[i * 4] = value
            rgba[i * 4 + 1] = value
            rgba[i * 4 + 2] = value
            rgba[i * 4 + 3] = pixels[i * channels + 1] if gray_alpha else 255
    elif color_type == 2:
        for i in range(width * height):
            rgba[i * 4:i * 4 + 3] = pixels[i * 3:i * 3 + 3]
            rgba[i * 4 + 3] = 255

    return width, height, rgba


def write_png(
    path: str | Path,
    width: int,
    height: int,
    rgba: bytes | bytearray,
) -> None:
    """Write *rgba* as an 8-bit RGBA PNG."""
    expected = width * height * 4
    if len(rgba) != expected:
        raise PngError(f"expected {expected} bytes, got {len(rgba)}")

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: None keeps the writer trivial and lossless
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    Path(path).write_bytes(
        SIGNATURE
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
