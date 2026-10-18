#!/usr/bin/env python3
"""Generates src/text/tables.mbt and the conformance tests from the UCD.

    python3 scripts/gen_unicode.py            # latest UCD
    UCD_VERSION=17.0.0 python3 scripts/gen_unicode.py

The data files are downloaded into out/ucd/<version>/ (ignored by git).

Tables are sorted range lists covering U+0000..U+10FFFF: for each range, the
distance from the previous range start and a property value, both written as
base-32 varints in printable ASCII inside a string literal, and decoded once
at startup into two FixedArray[Int] for binary search.
"""
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = os.environ.get("UCD_VERSION", "latest")
BASE = (
    "https://www.unicode.org/Public/UCD/latest/ucd"
    if VERSION == "latest"
    else "https://www.unicode.org/Public/%s/ucd" % VERSION
)
CACHE = os.path.join(ROOT, "out", "ucd", VERSION)
FILES = {
    "GraphemeBreakProperty.txt": "auxiliary/GraphemeBreakProperty.txt",
    "GraphemeBreakTest.txt": "auxiliary/GraphemeBreakTest.txt",
    "LineBreakTest.txt": "auxiliary/LineBreakTest.txt",
    "emoji-data.txt": "emoji/emoji-data.txt",
    "DerivedCoreProperties.txt": "DerivedCoreProperties.txt",
    "LineBreak.txt": "LineBreak.txt",
    "EastAsianWidth.txt": "EastAsianWidth.txt",
    "DerivedGeneralCategory.txt": "extracted/DerivedGeneralCategory.txt",
}
N = 0x110000


def fetch(name):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = BASE + "/" + FILES[name]
        print("downloading", url)
        with urllib.request.urlopen(url) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8") as f:
        return f.read()


def version_of(text):
    m = re.search(r"-(\d+\.\d+\.\d+)\.txt", text.splitlines()[0])
    return m.group(1) if m else "?"


def parse(text, default, field=1):
    """Code point -> value of field `field` (1-based after the code points)."""
    vals = [default] * N
    for line in text.splitlines():
        m = re.match(r"#\s*@missing:\s*([0-9A-F]+)\.\.([0-9A-F]+)\s*;\s*(.*)", line)
        if m:
            parts = [p.strip() for p in m.group(3).split(";")]
            if len(parts) >= field:
                a, b = int(m.group(1), 16), int(m.group(2), 16)
                for c in range(a, b + 1):
                    vals[c] = parts[field - 1]
            continue
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(";")]
        r = parts[0]
        if len(parts) <= field:
            continue
        v = parts[field]
        if ".." in r:
            a, b = (int(x, 16) for x in r.split(".."))
        else:
            a = b = int(r, 16)
        for c in range(a, b + 1):
            vals[c] = v
    return vals


def parse_prop(text, prop):
    """Set of code points with a binary property (e.g. Extended_Pictographic)."""
    out = bytearray(N)
    for line in text.splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(";")]
        if parts[1] != prop:
            continue
        r = parts[0]
        if ".." in r:
            a, b = (int(x, 16) for x in r.split(".."))
        else:
            a = b = int(r, 16)
        for c in range(a, b + 1):
            out[c] = 1
    return out


def parse_incb(text):
    vals = ["None"] * N
    for line in text.splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(";")]
        if len(parts) < 3 or parts[1] != "InCB":
            continue
        r = parts[0]
        if ".." in r:
            a, b = (int(x, 16) for x in r.split(".."))
        else:
            a = b = int(r, 16)
        for c in range(a, b + 1):
            vals[c] = parts[2]
    return vals


DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"  # value digits; +32 marks "more"
MORE = "abcdefghijklmnopqrstuvwxyz!$%&*+"  # 32 continuation digits


def varint(n):
    assert n >= 0
    out = []
    while True:
        d = n & 31
        n >>= 5
        if n:
            out.append(MORE[d])
        else:
            out.append(DIGITS[d])
            return "".join(out)


def ranges(vals):
    out = []
    prev = None
    for c in range(N):
        if vals[c] != prev:
            out.append((c, vals[c]))
            prev = vals[c]
    return out


def encode(rs):
    s = []
    last = 0
    for start, v in rs:
        s.append(varint(start - last))
        s.append(varint(v))
        last = start
    return "".join(s)


def literal(name, enc, comment):
    lines = ["///|", "/// " + comment, "let %s : String =" % name]
    lines.append("  (")
    for i in range(0, len(enc), 96):
        lines.append("    #|" + enc[i : i + 96])
    lines.append("  )")
    return "\n".join(lines) + "\n"


GCB = [
    "Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator",
    "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT",
]
INCB = ["None", "Linker", "Consonant", "Extend"]

# Line break classes after LB1 resolution (AI, SG, XX -> AL; SA -> CM or AL;
# CJ -> NS), written out as constants at the end of tables.mbt.
LB = [
    "BK", "CR", "LF", "NL", "SP", "ZW", "ZWJ", "CM", "WJ", "GL", "CL", "CP",
    "EX", "SY", "OP", "QU", "IS", "NS", "B2", "BA", "BB", "HY", "HH", "CB",
    "IN", "AL", "HL", "NU", "PR", "PO", "ID", "EB", "EM", "JL", "JV", "JT",
    "H2", "H3", "RI", "AK", "AP", "AS", "VF", "VI",
]


def main():
    gbp = fetch("GraphemeBreakProperty.txt")
    ver = version_of(gbp)
    emoji = fetch("emoji-data.txt")
    dcp = fetch("DerivedCoreProperties.txt")
    lbt = fetch("LineBreak.txt")
    eaw = fetch("EastAsianWidth.txt")
    dgc = fetch("DerivedGeneralCategory.txt")

    gcb = parse(gbp, "Other")
    xp = parse_prop(emoji, "Extended_Pictographic")
    incb = parse_incb(dcp)
    lb = parse(lbt, "XX")
    ea = parse(eaw, "N")
    gc = parse(dgc, "Cn")

    # GB9c relies on InCB=Extend characters never starting a cluster.
    for c in range(N):
        if incb[c] == "Extend":
            assert gcb[c] in ("Extend", "ZWJ"), hex(c)

    gvals = [0] * N
    for c in range(N):
        gvals[c] = GCB.index(gcb[c]) | (xp[c] << 4) | (INCB.index(incb[c]) << 5)

    lvals = [0] * N
    for c in range(N):
        k = lb[c]
        g = gc[c]
        if k in ("AI", "SG", "XX"):
            k = "AL"
        elif k == "SA":
            k = "CM" if g in ("Mn", "Mc") else "AL"
        elif k == "CJ":
            k = "NS"
        v = LB.index(k)
        if ea[c] in ("F", "W", "H"):
            v |= 1 << 6
        if xp[c] and g == "Cn":
            v |= 1 << 7
        if k == "QU" and g == "Pi":
            v |= 1 << 8
        if k == "QU" and g == "Pf":
            v |= 1 << 9
        lvals[c] = v

    gr = ranges(gvals)
    lr = ranges(lvals)
    genc = encode(gr)
    lenc = encode(lr)
    out = []
    out.append(
        "// Generated by scripts/gen_unicode.py from the Unicode %s character\n"
        "// database. Do not edit.\n\n" % ver
    )
    out.append("///|\npub let unicode_version : String = \"%s\"\n\n" % ver)
    out.append(
        literal(
            "grapheme_data",
            genc,
            "%d ranges: Grapheme_Cluster_Break | Extended_Pictographic << 4 | InCB << 5"
            % len(gr),
        )
    )
    out.append("\n")
    out.append(
        literal(
            "line_data",
            lenc,
            "%d ranges: resolved Line_Break | East Asian (F/W/H) << 6 |"
            " (Extended_Pictographic & Cn) << 7 | (QU & Pi) << 8 | (QU & Pf) << 9"
            % len(lr),
        )
    )
    out.append("\n// Line_Break classes after LB1.\n")
    for i, k in enumerate(LB):
        out.append("\n///|\nconst %s = %d\n" % (k, i))
    with open(os.path.join(ROOT, "src", "text", "tables.mbt"), "w") as f:
        f.write("".join(out))
    print("Unicode %s: %d grapheme ranges (%d chars), %d line ranges (%d chars)"
          % (ver, len(gr), len(genc), len(lr), len(lenc)))

    write_test("GraphemeBreakTest.txt", "grapheme", "grapheme_conformance_test.mbt")
    write_test("LineBreakTest.txt", "linebreak", "linebreak_conformance_test.mbt")


def write_test(src, name, dst):
    text = fetch(src)
    ver = version_of(text)
    cases = []
    for line in text.splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        s = []
        for tok in line.split():
            if tok == "÷":
                s.append("/")
            elif tok == "×":
                s.append(".")
            else:
                s.append(tok.lstrip("0") or "0")
        cases.append("".join(s))
    out = [
        "// Generated by scripts/gen_unicode.py from %s (Unicode %s). Do not edit.\n"
        "// One case per line: code points in hex, each preceded by '/' (break)\n"
        "// or '.' (no break), and the text end's mark last.\n" % (src, ver)
    ]
    chunk = 2000
    names = []
    for k in range(0, len(cases), chunk):
        names.append("%s_cases_%d" % (name, len(names)))
        out.append("\n///|\nlet %s : String =\n  (\n" % names[-1])
        for c in cases[k : k + chunk]:
            out.append("    #|%s\n" % c)
        out.append("  )\n")
    out.append(
        "\n///|\ntest \"%s conformance (%s, Unicode %s)\" {\n"
        "  run_conformance(\"%s\", [%s])\n}\n"
        % (name, src, ver, name, ", ".join(names))
    )
    with open(os.path.join(ROOT, "src", "text", dst), "w") as f:
        f.write("".join(out))
    print("%s: %d cases" % (src, len(cases)))


if __name__ == "__main__":
    sys.exit(main())
