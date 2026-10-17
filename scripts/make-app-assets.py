#!/usr/bin/env python3
"""Draw PIA.app's icon and write its notification sounds, from code, with no dependencies.

    make-app-assets.py <Resources folder>

- AppIcon.icns: the 16×16 owl (README's assets/pia-owl.svg), pixel-perfect at every size, on a soft
  lavender squircle so its dark outline reads on light and dark menus alike.
- owl-ready|done|stalled|permission.caf: the "Búho" family the human chose — soft sine notes, a
  quarter lower than written: ready rises in two (C5→E5), done rises in three (C5 E5 G5), stalled falls
  (G4→F4), permission taps twice (E5 E5).
"""
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zlib

OWL = [
    ".DD..........DD.",
    ".DBD........DBD.",
    ".DBBDDDDDDDDBBD.",
    ".DBBBBBBBBBBBBD.",
    "DBBEEEBBBBEEEBBD",
    "DBEEEEEBBEEEEEBD",
    "DBEEPPEBBEPPEEBD",
    "DBEEPPEBBEPPEEBD",
    "DBBEEEBKKBEEEBBD",
    "DBBBBBBKKBBBBBBD",
    "DBWLLLLLLLLLLWBD",
    "DBWLLDLLLLDLLWBD",
    "DBWLLLLLLLLLLWBD",
    ".DBWLLLLLLLLWBD.",
    "..DDBBBBBBBBDD..",
    "....KK....KK....",
]
PALETTE = {"D": "#1A1B3A", "B": "#3D3F9E", "E": "#FFD166", "P": "#1A1B3A", "K": "#FF8C42", "L": "#8D92F0", "W": "#2C2E78"}
BACKGROUND = "#ECEBFF"


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def png(path, size, pixels):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def icon(size):
    pixels = [[(0, 0, 0, 0)] * size for _ in range(size)]
    inset = round(size * 0.1)
    body = size - 2 * inset
    radius = body * 0.225
    bg = rgb(BACKGROUND)
    for y in range(size):
        for x in range(size):
            # Rounded rectangle with a little antialiasing on the corners.
            cx = min(max(x + 0.5, inset + radius), inset + body - radius)
            cy = min(max(y + 0.5, inset + radius), inset + body - radius)
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) - radius
            if x + 0.5 < inset or x + 0.5 > inset + body or y + 0.5 < inset or y + 0.5 > inset + body:
                continue
            alpha = 1.0 if d <= -0.5 else (0.0 if d >= 0.5 else 0.5 - d)
            if alpha > 0:
                pixels[y][x] = bg + (round(255 * alpha),)
    cell = max(1, int(body * 0.74 // 16))
    art = cell * 16
    ox = (size - art) // 2
    oy = (size - art) // 2 + max(0, cell // 3)
    for r, row in enumerate(OWL):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            color = rgb(PALETTE[ch]) + (255,)
            for y in range(oy + r * cell, oy + (r + 1) * cell):
                for x in range(ox + c * cell, ox + (c + 1) * cell):
                    pixels[y][x] = color
    return pixels


def make_icns(resources):
    work = tempfile.mkdtemp()
    iconset = os.path.join(work, "AppIcon.iconset")
    os.mkdir(iconset)
    for base in (16, 32, 128, 256, 512):
        png(os.path.join(iconset, f"icon_{base}x{base}.png"), base, icon(base))
        png(os.path.join(iconset, f"icon_{base}x{base}@2x.png"), base * 2, icon(base * 2))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(resources, "AppIcon.icns")], check=True)
    shutil.rmtree(work)


SEQ = {
    "ready": [(523.25, 0, 0.35), (659.25, 0.18, 0.5)],
    "done": [(523.25, 0, 0.22), (659.25, 0.14, 0.22), (783.99, 0.28, 0.6)],
    "stalled": [(392.0, 0, 0.3), (349.23, 0.32, 0.5)],
    "permission": [(659.25, 0, 0.16), (659.25, 0.22, 0.3)],
}
OCTAVE, ATTACK, VOLUME, LENGTH = 0.75, 0.06, 0.4, 1.3
RATE = 44100


def tone(kind):
    notes = SEQ[kind]
    total = max(at + dur * LENGTH for _, at, dur in notes) + 0.15
    samples = [0.0] * int(total * RATE)
    floor = 0.0001
    for freq, at, dur in notes:
        dur *= LENGTH
        start = int(at * RATE)
        n = int((dur + 0.05) * RATE)
        for i in range(n):
            t = i / RATE
            # Exponential attack to VOLUME, then exponential decay to silence, as WebAudio did.
            if t < ATTACK:
                g = floor * (VOLUME / floor) ** (t / ATTACK)
            elif t < dur:
                g = VOLUME * (floor / VOLUME) ** ((t - ATTACK) / max(dur - ATTACK, 1e-6))
            else:
                g = 0.0
            if start + i < len(samples):
                samples[start + i] += g * math.sin(2 * math.pi * freq * OCTAVE * t)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.89 / peak)
    return [int(max(-1, min(1, s * scale)) * 32767) for s in samples]


def make_sounds(resources):
    work = tempfile.mkdtemp()
    for kind in SEQ:
        wav = os.path.join(work, f"owl-{kind}.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", s) for s in tone(kind)))
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", wav, os.path.join(resources, f"owl-{kind}.caf")], check=True)
    shutil.rmtree(work)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    resources = sys.argv[1]
    os.makedirs(resources, exist_ok=True)
    make_icns(resources)
    make_sounds(resources)
    print(f"assets: icon and {len(SEQ)} sounds in {resources}")


if __name__ == "__main__":
    main()
