#!/usr/bin/env python3
"""The brand assets of design/mobile/assets as VectorDrawables.

Covers what those SVGs use: path, rect, circle, <g> with translate/scale,
inherited fill and stroke, CSS custom properties from an embedded <style>
(with a prefers-color-scheme: dark block, written out as `<name>_dark`), and
fill="currentColor" (drawn black, tinted where it is shown).

    python3 scripts/svg2vd.py ../../design/mobile/assets app/src/main/res/drawable
"""
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"
INHERITED = ("fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "fill-rule")

# Asset file → drawable name. The model makers' marks are `maker_*`; the buddy's states `buddy_*`.
NAMES = {
    "mark": "stillfail_mark", "lockup": "stillfail_lockup", "slack": "slack",
    "anthropic": "maker_anthropic", "openai": "maker_openai", "deepseek": "maker_deepseek", "zhipu": "maker_zhipu", "mistral": "maker_mistral", "xiaomi": "maker_xiaomi", "ant-ling": "maker_ant_ling", "openrouter": "maker_openrouter", "vercel": "maker_vercel", "cloudflare": "maker_cloudflare", "azure": "maker_azure", "groq": "maker_groq", "together": "maker_together", "fireworks": "maker_fireworks", "cerebras": "maker_cerebras", "huggingface": "maker_huggingface", "nvidia": "maker_nvidia", "baseten": "maker_baseten",
    "idle": "buddy_idle", "working": "buddy_working", "blocked": "buddy_blocked", "done": "buddy_done", "offline": "buddy_offline",
    "illus-sign-in": "illus_sign_in", "illus-new-chat": "illus_new_chat", "illus-station-offline": "illus_station_offline",
}


def css_vars(root):
    """Light and dark values of the custom properties, or two empty maps."""
    style = root.find(f"{NS}style")
    if style is None or not style.text:
        return {}, {}
    text = style.text
    dark_at = text.find("@media")
    parse = lambda s: dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", s))
    return parse(text[:dark_at] if dark_at >= 0 else text), parse(text[dark_at:]) if dark_at >= 0 else {}


def color(value, variables):
    if value is None or value == "none":
        return None
    m = re.fullmatch(r"var\((--[\w-]+)\)", value.strip())
    if m:
        value = variables[m.group(1)]
    if value == "currentColor":
        return "#FF000000"
    value = value.strip()
    if re.fullmatch(r"#[0-9a-fA-F]{3}", value):
        value = "#" + "".join(c * 2 for c in value[1:])
    return value.upper()


def num(s):
    return float(s) if s is not None else 0.0


def fmt(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ── path data: re-tokenised so that arc flags written together ("a1 1 0 00-.8 0") parse on Android ──

ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def normalize_path(d):
    out = []
    i, n = 0, len(d)
    cmd = None
    count = 0

    def skip():
        nonlocal i
        while i < n and d[i] in " ,\t\n\r":
            i += 1

    def number():
        nonlocal i
        m = re.compile(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?").match(d, i)
        if not m:
            raise ValueError(f"bad path at {i}: {d[i:i+20]!r}")
        i = m.end()
        return m.group(0)

    while True:
        skip()
        if i >= n:
            break
        if d[i].isalpha():
            cmd = d[i]
            i += 1
            out.append(cmd)
            count = 0
            if cmd.upper() == "Z":
                continue
        args = ARGS[cmd.upper()]
        vals = []
        for k in range(args):
            skip()
            if cmd.upper() == "A" and k in (3, 4):
                vals.append(d[i])  # a flag is one digit, whatever follows it
                i += 1
            else:
                vals.append(number())
        if count > 0:
            out.append(cmd)
        out.append(" ".join(vals))
        count += 1
    return " ".join(out)


def rect_path(e):
    x, y, w, h = num(e.get("x")), num(e.get("y")), num(e.get("width")), num(e.get("height"))
    rx = num(e.get("rx") or e.get("ry"))
    ry = num(e.get("ry") or e.get("rx"))
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    if not rx:
        return f"M{fmt(x)} {fmt(y)}h{fmt(w)}v{fmt(h)}h{fmt(-w)}Z"
    return (f"M{fmt(x + rx)} {fmt(y)}H{fmt(x + w - rx)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x + w)} {fmt(y + ry)}"
            f"V{fmt(y + h - ry)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x + w - rx)} {fmt(y + h)}"
            f"H{fmt(x + rx)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x)} {fmt(y + h - ry)}"
            f"V{fmt(y + ry)}A{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(x + rx)} {fmt(y)}Z")


def circle_path(e):
    cx, cy, r = num(e.get("cx")), num(e.get("cy")), num(e.get("r"))
    return f"M{fmt(cx - r)} {fmt(cy)}A{fmt(r)} {fmt(r)} 0 1 0 {fmt(cx + r)} {fmt(cy)}A{fmt(r)} {fmt(r)} 0 1 0 {fmt(cx - r)} {fmt(cy)}Z"


def transform(value):
    t = {"translateX": 0.0, "translateY": 0.0, "scaleX": 1.0, "scaleY": 1.0}
    for name, args in re.findall(r"(\w+)\(([^)]*)\)", value or ""):
        a = [float(v) for v in re.split(r"[\s,]+", args.strip())]
        if name == "translate":
            t["translateX"], t["translateY"] = a[0], a[1] if len(a) > 1 else 0.0
        elif name == "scale":
            t["scaleX"], t["scaleY"] = a[0], a[1] if len(a) > 1 else a[0]
        else:
            raise ValueError(f"unsupported transform {name}")
    return t


def emit(e, inherited, variables, lines, depth):
    pad = "    " * depth
    attrs = dict(inherited)
    for k in INHERITED:
        if e.get(k) is not None:
            attrs[k] = e.get(k)
    tag = e.tag.replace(NS, "")
    if tag == "g":
        t = transform(e.get("transform"))
        props = " ".join(f'android:{k}="{fmt(v)}"' for k, v in t.items() if v != (1.0 if k.startswith("scale") else 0.0))
        lines.append(f"{pad}<group {props}>".replace("<group >", "<group>"))
        for child in e:
            emit(child, attrs, variables, lines, depth + 1)
        lines.append(f"{pad}</group>")
        return
    if tag == "path":
        d = normalize_path(e.get("d"))
    elif tag == "rect":
        d = rect_path(e)
    elif tag == "circle":
        d = circle_path(e)
    else:
        return  # title, style
    fill = color(attrs.get("fill", "#000000"), variables)
    stroke = color(attrs.get("stroke"), variables)
    out = [f'android:pathData="{d}"']
    if fill:
        out.append(f'android:fillColor="{fill}"')
    if attrs.get("fill-rule") == "evenodd":
        out.append('android:fillType="evenOdd"')
    if stroke:
        out.append(f'android:strokeColor="{stroke}"')
        out.append(f'android:strokeWidth="{fmt(float(attrs.get("stroke-width", "1")))}"')
        if attrs.get("stroke-linecap"):
            out.append(f'android:strokeLineCap="{attrs["stroke-linecap"]}"')
        if attrs.get("stroke-linejoin"):
            out.append(f'android:strokeLineJoin="{attrs["stroke-linejoin"]}"')
    lines.append(f"{pad}<path " + f"\n{pad}    ".join(out) + " />")


def convert(path, variables):
    root = ET.parse(path).getroot()
    vb = [float(v) for v in root.get("viewBox").split()]
    w, h = vb[2], vb[3]
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        f"<!-- Generated by scripts/svg2vd.py from design/mobile/assets/{os.path.basename(path)}. -->",
        f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="{fmt(w)}dp" android:height="{fmt(h)}dp" '
        f'android:viewportWidth="{fmt(w)}" android:viewportHeight="{fmt(h)}">',
    ]
    inherited = {k: root.get(k) for k in INHERITED if root.get(k) is not None}
    body = []
    for child in root:
        emit(child, inherited, variables, body, 1)
    if vb[0] or vb[1]:
        body = [f'    <group android:translateX="{fmt(-vb[0])}" android:translateY="{fmt(-vb[1])}">'] + ["    " + l for l in body] + ["    </group>"]
    return "\n".join(lines + body + ["</vector>", ""])


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    for file in sorted(os.listdir(src)):
        if not file.endswith(".svg"):
            continue
        stem = file[:-4]
        dark = stem.endswith("-dark")
        base = stem[:-5] if dark else stem
        name = NAMES[base] + ("_dark" if dark else "")
        root = ET.parse(os.path.join(src, file)).getroot()
        light_vars, dark_vars = css_vars(root)
        with open(os.path.join(dst, name + ".xml"), "w") as f:
            f.write(convert(os.path.join(src, file), light_vars))
        if dark_vars:
            with open(os.path.join(dst, name + "_dark.xml"), "w") as f:
                f.write(convert(os.path.join(src, file), {**light_vars, **dark_vars}))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
