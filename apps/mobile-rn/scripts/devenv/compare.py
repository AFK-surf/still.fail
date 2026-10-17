#!/usr/bin/env python3
"""The Android app's screenshots (ref/) beside the React Native app's (a shots.sh output), each pair one picture:
the Android app's on the left, the React Native app's on the right, half size, named as the screen.

  compare.py <ref dir> <shots dir> <out dir>
"""
import os
import sys

from PIL import Image, ImageDraw

ref, shots, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
for name in sorted(os.listdir(ref)):
    if not name.endswith(".png"):
        continue
    a = Image.open(os.path.join(ref, name)).convert("RGB")
    b_path = os.path.join(shots, name)
    b = Image.open(b_path).convert("RGB") if os.path.exists(b_path) else Image.new("RGB", a.size, (230, 230, 230))
    w, h = a.size[0] // 2, a.size[1] // 2
    a, b = a.resize((w, h)), b.resize((w, h))
    gap = 24
    pair = Image.new("RGB", (w * 2 + gap, h + 40), (255, 255, 255))
    pair.paste(a, (0, 40))
    pair.paste(b, (w + gap, 40))
    d = ImageDraw.Draw(pair)
    d.text((8, 12), "Android (Kotlin)", fill=(0, 0, 0))
    d.text((w + gap + 8, 12), "React Native" if os.path.exists(b_path) else "React Native: missing", fill=(0, 0, 0))
    pair.save(os.path.join(out, name))
    print("pair", name)
