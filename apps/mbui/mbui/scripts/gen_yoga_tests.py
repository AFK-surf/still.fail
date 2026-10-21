#!/usr/bin/env python3
"""Turn Yoga's generated layout tests into MoonBit tests for src/flex.

Yoga's tests are generated from HTML fixtures laid out by Chrome
(gentest), so they record what a browser does. We take the JavaScript
flavour, keep the LTR expectations, and write one MoonBit test file per
Yoga file.

  python3 scripts/gen_yoga_tests.py [path/to/yoga]

Without a path the Yoga repository is cloned (shallow) into out/yoga at the
commit below.
"""
import os
import re
import subprocess
import sys

YOGA_COMMIT = "52f6d0bd3824296b8e852cb4fcdf3b9821ab2aa5"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "flex")


def yoga_dir():
    if len(sys.argv) > 1:
        return sys.argv[1]
    d = os.path.join(ROOT, "out", "yoga")
    if not os.path.isdir(d):
        subprocess.check_call(["git", "clone", "-q", "https://github.com/facebook/yoga", d])
        subprocess.check_call(["git", "-C", d, "checkout", "-q", YOGA_COMMIT])
    return d


def dim(v):
    v = v.strip()
    if v == '"auto"':
        return "Auto"
    m = re.fullmatch(r'"(-?[0-9.]+)%"', v)
    if m:
        return f"Pct({float(m.group(1))})"
    return f"Pt({float(v)})"


EDGES = {
    "Left": ["left"], "Right": ["right"], "Top": ["top"], "Bottom": ["bottom"],
    "Start": ["left"], "End": ["right"],
    "Horizontal": ["left", "right"], "Vertical": ["top", "bottom"],
    "All": ["left", "top", "right", "bottom"],
}
ENUMS = {
    "FlexDirection": {"Row": "Row", "Column": "Column", "RowReverse": "RowReverse", "ColumnReverse": "ColumnReverse"},
    "PositionType": {"Absolute": "Absolute", "Relative": "Relative", "Static": "Static"},
    "Wrap": {"Wrap": "Wrap", "NoWrap": "NoWrap", "WrapReverse": "WrapReverse"},
    "Align": {"Auto": "Auto", "FlexStart": "FlexStart", "Center": "Center", "FlexEnd": "FlexEnd",
              "Stretch": "Stretch", "Baseline": "Baseline", "SpaceBetween": "SpaceBetween",
              "SpaceAround": "SpaceAround", "SpaceEvenly": "SpaceEvenly"},
    "Justify": {"FlexStart": "FlexStart", "Center": "Center", "FlexEnd": "FlexEnd",
                "SpaceBetween": "SpaceBetween", "SpaceAround": "SpaceAround", "SpaceEvenly": "SpaceEvenly"},
    "Display": {"Flex": "Flex", "None": "DisplayNone", "Contents": "Contents"},
    "BoxSizing": {"BorderBox": "BorderBox", "ContentBox": "ContentBox"},
    "Overflow": {"Visible": "Visible", "Hidden": "Hidden", "Scroll": "Scroll"},
}


def enum(v):
    k, name = v.strip().split(".")
    return ENUMS[k][name]


def setter(node, prop, args):
    s = f"{node}.style"
    a = [x.strip() for x in split_args(args)]
    simple_dims = {"Width": "width", "Height": "height", "MinWidth": "min_width", "MinHeight": "min_height",
                   "MaxWidth": "max_width", "MaxHeight": "max_height", "FlexBasis": "basis"}
    if prop in simple_dims:
        return [f"{s}.set_{simple_dims[prop]}({dim(a[0])})"]
    if prop in ("Margin", "Padding", "Border", "Position"):
        field = {"Margin": "margin", "Padding": "padding", "Border": "border", "Position": "inset"}[prop]
        edge = a[0].split(".")[1]
        return [f"{s}.set_{field}_{e}({dim(a[1])})" for e in EDGES[edge]]
    if prop == "PositionAuto":
        edge = a[0].split(".")[1]
        return [f"{s}.set_inset_{e}(Auto)" for e in EDGES[edge]]
    if prop == "FlexDirection":
        return [f"{s}.direction = {enum(a[0])}"]
    if prop == "PositionType":
        return [f"{s}.position = {enum(a[0])}"]
    if prop == "FlexWrap":
        return [f"{s}.wrap = {enum(a[0])}"]
    if prop in ("AlignItems", "AlignSelf", "AlignContent", "JustifyContent"):
        f = {"AlignItems": "align_items", "AlignSelf": "align_self", "AlignContent": "align_content",
             "JustifyContent": "justify"}[prop]
        return [f"{s}.{f} = {enum(a[0])}"]
    if prop in ("FlexGrow", "FlexShrink", "AspectRatio"):
        f = {"FlexGrow": "grow", "FlexShrink": "shrink", "AspectRatio": "aspect"}[prop]
        return [f"{s}.{f} = {float(a[0])}"]
    if prop == "Gap":
        g = a[0].split(".")[1]
        fields = {"Column": ["gap_col"], "Row": ["gap_row"], "All": ["gap_col", "gap_row"]}[g]
        return [f"{s}.set_{f}({dim(a[1])})" for f in fields]
    if prop == "Display":
        return [f"{s}.display = {enum(a[0])}"]
    if prop == "BoxSizing":
        return [f"{s}.box_sizing = {enum(a[0])}"]
    if prop == "Overflow":
        return [f"{s}.overflow = {enum(a[0])}"]
    if prop == "MeasureFunc":
        m = re.fullmatch(r'intrinsicSizeMeasureFunc\.bind\(\{text: "(.*)", flexDirection: FlexDirection\.(\w+)\}\)', args.strip())
        if not m:
            raise ValueError(args)
        text = m.group(1).replace("\\", "\\\\").replace('"', '\\"')
        return [f'{node}.measure = Some(text_measure("{text}", row={str(m.group(2) == "Row").lower()}))']
    raise ValueError(f"unknown setter {prop}({args})")


def split_args(s):
    out, depth, cur, q = [], 0, "", False
    for ch in s:
        if ch == '"':
            q = not q
        if not q and ch in "({":
            depth += 1
        if not q and ch in ")}":
            depth -= 1
        if ch == "," and depth == 0 and not q:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def convert(path):
    src = open(path).read()
    tests = re.findall(r"test\('([^']+)', \(\) => \{(.*?)\n\}\);", src, re.S)
    out = []
    for name, body in tests:
        lines = []
        expects = []
        phase = 0
        ok = True
        for raw in body.split("\n"):
            line = raw.strip()
            if not line or line.startswith("const config"):
                continue
            if phase == 2:
                break
            m = re.fullmatch(r"const (\w+) = Yoga\.Node\.create\(config\);", line)
            if m:
                lines.append(f"let {m.group(1)} = @flex.Node::new()")
                continue
            m = re.fullmatch(r"(\w+)\.set(\w+)\((.*)\);", line)
            if m:
                try:
                    lines += setter(m.group(1), m.group(2), m.group(3))
                except ValueError as e:
                    ok = False
                    lines.append(f"// unsupported: {e}")
                continue
            m = re.fullmatch(r"(\w+)\.insertChild\((\w+), (\d+)\);", line)
            if m:
                lines.append(f"{m.group(1)}.add({m.group(2)})")
                continue
            m = re.fullmatch(r"root\.calculateLayout\(undefined, undefined, Direction\.(\w+)\);", line)
            if m:
                phase += 1
                if phase == 1:
                    lines.append("@flex.compute(root)")
                continue
            m = re.fullmatch(r"expect\((\w+)\.getComputed(\w+)\(\)\)\.toBe\((-?[0-9.]+)\);", line)
            if m and phase == 1:
                expects.append((m.group(1), m.group(2), float(m.group(3))))
                continue
        if not ok:
            continue
        # group expectations per node: left, top, width, height
        nodes = {}
        order = []
        for n, k, v in expects:
            if n not in nodes:
                nodes[n] = {}
                order.append(n)
            nodes[n][k] = v
        for n in order:
            d = nodes[n]
            lines.append(f'check("{n}", {n}, {d["Left"]}, {d["Top"]}, {d["Width"]}, {d["Height"]})')
        body_txt = "\n".join("  " + l for l in lines)
        out.append(f'///|\ntest "{name}" {{\n{body_txt}\n}}\n')
    return out


def main():
    d = os.path.join(yoga_dir(), "javascript", "tests", "generated")
    total = 0
    for f in sorted(os.listdir(d)):
        if not f.endswith(".test.ts"):
            continue
        tests = convert(os.path.join(d, f))
        total += len(tests)
        base = re.sub(r"^YG|Test$|\.test\.ts$", "", f.replace(".test.ts", ""))
        base = re.sub(r"Test$", "", base)
        snake = re.sub(r"(?<!^)(?=[A-Z])", "_", base).lower()
        dst = os.path.join(OUT, f"yoga_{snake}_test.mbt")
        with open(dst, "w") as w:
            w.write(f"// Generated by scripts/gen_yoga_tests.py from Yoga {YOGA_COMMIT[:12]}\n")
            w.write(f"// javascript/tests/generated/{f} (fixtures laid out by Chrome). Do not edit.\n\n")
            w.write("\n".join(tests))
    print(f"{total} tests")


main()
