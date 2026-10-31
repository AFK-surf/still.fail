#!/usr/bin/env python3
"""The faces still.fail offers beside the system's (client/core-ts/src/fonts.ts, docs/fonts.md), made from where each is
published into what the apps take, under fonts/<id>/<version>/ in the releases bucket (served at /releases/fonts/…):

- for pages, font.css and its woff2 files: a Chinese face cut by unicode-range into the slices Google Fonts cuts Noto
  Sans SC into (a page fetches only the slices its characters are in), a Latin one whole;
- for the Android app, each source file gzipped (<name>.ttf.gz), fetched whole when the face is chosen, and a
  preview (preview-<hash>.ttf, some tens of KB): only the characters the fonts page shows (its words in the catalogs,
  the faces' names, ASCII), for each face to be shown in itself before it is fetched.

  python3 scripts/fonts.py [--put [--previews]]     (needs fontTools and brotli: pip install fonttools brotli)
  python3 scripts/fonts.py --share                  the share card's face, written into the app (below)

Prints the catalogue's files (sizes and hashes) to put in fonts.ts. --put puts what it made in the bucket with wrangler
(cloud/'s, logged in); --previews only the previews (the pages' words changed: each is named by its hash, the
rest stays). A face's files never change once put: a new version of it is a new <version>."""
import concurrent.futures
import gzip
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get("FONTS_WORK", "fonts-work")).resolve()
CACHE = WORK / "sources"
OUT = WORK / "out"
GF = "https://raw.githubusercontent.com/google/fonts/47d54ca1ebb14fd864695f1d39dc734f39017c33/ofl"

# id, version, the family name pages know it by, sliced (Chinese) or whole, and its sources: (weight or "var", url,
# the file in a zip at that url or None, sha256 of what is downloaded).
FACES = [
    ("inter", "4.001", "SF Inter", False, [("var", "google:inter/Inter%5Bopsz,wght%5D.ttf", None, "")]),
    ("noto-sans-sc", "2.004", "SF Noto Sans SC", True, [("var", "google:notosanssc/NotoSansSC%5Bwght%5D.ttf", None, "")]),
    ("noto-serif-sc", "2.003", "SF Noto Serif SC", True, [("var", "google:notoserifsc/NotoSerifSC%5Bwght%5D.ttf", None, "")]),
    ("lxgw-wenkai", "1.530", "SF LXGW WenKai", True, [
        (400, "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf", None, ""),
        (500, "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf", None, ""),
    ]),
    ("jetbrains-mono", "2.211", "SF JetBrains Mono", False, [("var", "google:jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf", None, "")]),
    ("fira-code", "5.002", "SF Fira Code", False, [("var", "google:firacode/FiraCode%5Bwght%5D.ttf", None, "")]),
    ("maple-mono", "7.9", "SF Maple Mono CN", True, [
        (400, "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-CN-unhinted.zip", "MapleMono-CN-Regular.ttf", ""),
        (600, "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-CN-unhinted.zip", "MapleMono-CN-SemiBold.ttf", ""),
    ]),
]

# Where Google Fonts' own CSS for Noto Sans SC says its slices are (asked as a browser that takes woff2).
SLICES_CSS = "https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400"
BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"


def url_of(source: str) -> str:
    return GF + "/" + source[len("google:"):] if source.startswith("google:") else source


def fetch(url: str) -> bytes:
    name = hashlib.sha256(url.encode()).hexdigest()[:16] + "-" + url.rsplit("/", 1)[-1].replace("%5B", "[").replace("%5D", "]")
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"fetching {url}", file=sys.stderr)
        req = urllib.request.Request(url, headers={"user-agent": BROWSER})
        with urllib.request.urlopen(req, timeout=600) as r:
            data = r.read()
        path.write_bytes(data)
    return path.read_bytes()


def source_bytes(url: str, member: str | None, sha: str) -> bytes:
    data = fetch(url_of(url))
    got = hashlib.sha256(data).hexdigest()
    if sha and got != sha:
        sys.exit(f"{url}: sha256 {got}, not {sha}")
    if member is None:
        return data
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        name = next(n for n in z.namelist() if n.rsplit("/", 1)[-1] == member)
        return z.read(name)


def slices() -> list[str]:
    css = fetch(SLICES_CSS).decode()
    return [m.strip() for m in re.findall(r"unicode-range:\s*([^;]+);", css)]


def parse_range(r: str) -> set[int]:
    out: set[int] = set()
    for part in r.split(","):
        part = part.strip().upper().removeprefix("U+")
        if "-" in part:
            a, b = part.split("-")
            out.update(range(int(a, 16), int(b, 16) + 1))
        elif "?" in part:
            out.update(range(int(part.replace("?", "0"), 16), int(part.replace("?", "F"), 16) + 1))
        else:
            out.add(int(part, 16))
    return out


def as_range(points: set[int]) -> str:
    s = sorted(points)
    runs, start, prev = [], s[0], s[0]
    for p in s[1:] + [None]:
        if p is not None and p == prev + 1:
            prev = p
            continue
        runs.append(f"U+{start:X}" if start == prev else f"U+{start:X}-{prev:X}")
        if p is not None:
            start = prev = p
    return ",".join(runs)


def subset(ttf: Path, out: Path, unicodes: str | None) -> bool:
    args = [sys.executable, "-m", "fontTools.subset", str(ttf), f"--output-file={out}", "--flavor=woff2", "--layout-features=*", "--no-hinting", "--name-IDs=*"]
    args.append(f"--unicodes={unicodes}" if unicodes else "--unicodes=*")
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"subset {ttf.name} {unicodes and unicodes[:40]}: {r.stderr}")
    return out.exists()


def weight_axis(ttf: Path) -> str | None:
    from fontTools.ttLib import TTFont
    f = TTFont(str(ttf), lazy=True)
    if "fvar" not in f:
        return None
    for a in f["fvar"].axes:
        if a.axisTag == "wght":
            return f"{int(a.minValue)} {int(a.maxValue)}"
    return None


def font_version(ttf: Path) -> str:
    from fontTools.ttLib import TTFont
    return str(TTFont(str(ttf), lazy=True)["name"].getDebugName(5))


def cmap_of(ttf: Path) -> set[int]:
    from fontTools.ttLib import TTFont
    return set(TTFont(str(ttf), lazy=True).getBestCmap().keys())


# What the fonts pages draw in a face before it is fetched: ASCII, the faces' names and the pages' own words.
NAMES = "思源黑体思源宋体霞鹜文楷"


def preview_text() -> str:
    words = []
    for lang in ("zh", "en"):
        catalog = json.loads((ROOT / f"client/i18n/catalog/{lang}/web-pages.json").read_text())
        words += [v for k, v in catalog.items() if k.startswith("web-pages.appearance.fonts.")]
    return "".join(chr(c) for c in range(0x20, 0x7F)) + NAMES + "".join(words) + "，。：、·…“”‘’（）"


def preview(ttf: Path, base: Path) -> tuple[str, int]:
    """The face's preview file: its glyphs for preview_text() alone, as TTF (what Android loads)."""
    text = preview_text()
    tmp = ttf.with_suffix(".preview.ttf")
    r = subprocess.run([sys.executable, "-m", "fontTools.subset", str(ttf), f"--output-file={tmp}", "--layout-features=*", "--no-hinting",
                        "--name-IDs=*", f"--text={text}"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"preview {ttf}: {r.stderr}")
    data = tmp.read_bytes()
    name = f"preview-{hashlib.sha256(data).hexdigest()[:8]}.ttf"
    (base / name).write_bytes(data)
    return name, len(data)


def make(face) -> dict:
    fid, version, family, sliced, sources = face
    base = OUT / "fonts" / fid / version
    base.mkdir(parents=True, exist_ok=True)
    tmp = WORK / "ttf" / fid
    tmp.mkdir(parents=True, exist_ok=True)
    css, files = [], []
    ranges = slices() if sliced else []
    for weight, url, member, sha in sources:
        data = source_bytes(url, member, sha)
        name = "var" if weight == "var" else str(weight)
        ttf = tmp / f"{name}.ttf"
        ttf.write_bytes(data)
        # The Android app's: the file whole, gzipped (it is unzipped where it is kept).
        gz = base / f"{name}.ttf.gz"
        gz.write_bytes(gzip.compress(data, 9, mtime=0))
        axis = weight_axis(ttf)
        print(f"{fid} {name}: {font_version(ttf)}", file=sys.stderr)
        files.append({"weight": 0 if weight == "var" else weight, "file": f"{name}.ttf.gz", "bytes": gz.stat().st_size, "sha256": hashlib.sha256(data).hexdigest()})
        css_weight = axis or str(weight)
        face_css = lambda src, rng: "@font-face{font-family:\"%s\";font-style:normal;font-weight:%s;font-display:swap;src:url(%s) format(\"woff2\")%s}" % (
            family, css_weight, src, f";unicode-range:{rng}" if rng else "")
        if "--previews" in sys.argv:
            continue
        if not sliced:
            out = base / f"{name}.woff2"
            subset(ttf, out, None)
            css.append(face_css(out.name, None))
            continue
        has = cmap_of(ttf)
        covered: set[int] = set()
        jobs = []
        for i, r in enumerate(ranges):
            pts = parse_range(r) & has
            covered |= parse_range(r)
            if pts:
                jobs.append((f"{name}-{i}.woff2", as_range(pts)))
        rest = has - covered
        if rest:
            jobs.append((f"{name}-rest.woff2", as_range(rest)))
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            done = list(pool.map(lambda j: subset(ttf, base / j[0], j[1]), jobs))
        for (file, rng), ok in zip(jobs, done):
            if ok:
                css.append(face_css(file, rng))
    if css:
        (base / "font.css").write_text("\n".join(css) + "\n")
    # The preview of the regular (the first source).
    shown, size = preview(tmp / ("var.ttf" if sources[0][0] == "var" else f"{sources[0][0]}.ttf"), base)
    return {"id": fid, "version": version, "family": family, "files": files, "preview": shown, "previewBytes": size}


# The share card's face (apps/mbui/src/sfpages/stations_now.mbt night_look; 2026-10-31 用户 chose it from drawn
# versions: 霞鹜文楷 with EB Garamond): one file a weight, the app carrying it (apps/mbui/src/sfbase/share_face.mbt), so
# the card is the same on every device whatever face its app is set in. A host face is one font (no fallback of its
# own), so the two are made one: EB Garamond's Latin, grown by SHARE_GROW to stand as tall as 文楷's (its x-height
# is 400 of 1000, 文楷's 468), and 文楷's characters of the card's words alone (the catalogs' words the core says the
# card in, its numbers' units, the dates', CJK punctuation; a character outside them is in the system's face).
SHARE_FACE = [
    (400, "google:ebgaramond/EBGaramond%5Bwght%5D.ttf", "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf"),
    (600, "google:ebgaramond/EBGaramond%5Bwght%5D.ttf", "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf"),
]
SHARE_GROW = 1.14
SHARE_KEYS = ("core-logic.fleet.", "core-logic.format.", "core-views.profiles.group.", "core-views.usage.", "web-main.stations.share")
SHARE_MORE = "亿万千百十零〇一二三四五六七八九年月日周时分秒个台，。：；、（）「」『』“”‘’…—·！？～"
SHARE_LATIN = list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026,
                                                                    0x2030, 0x20AC, 0x2122, 0x2212, 0x2264, 0x2265]
SHARE_OUT = ROOT / "apps/mbui/src/sfbase/share_face.mbt"


def share_chars() -> str:
    words = SHARE_MORE
    for f in sorted((ROOT / "client/i18n/catalog/zh").glob("*.json")):
        words += "".join(v for k, v in json.loads(f.read_text()).items() if k.startswith(SHARE_KEYS))
    return "".join(sorted({c for c in words if ord(c) >= 0x2E80}))


def share_one(weight: int, latin_url: str, cjk_url: str) -> bytes:
    from fontTools import subset as fsubset
    from fontTools.merge import Merger
    from fontTools.ttLib import TTFont
    from fontTools.ttLib.scaleUpem import scale_upem
    from fontTools.varLib import instancer

    tmp = WORK / "share"
    tmp.mkdir(parents=True, exist_ok=True)
    latin = instancer.instantiateVariableFont(TTFont(io.BytesIO(source_bytes(latin_url, None, ""))), {"wght": weight})
    opts = fsubset.Options()
    opts.layout_features = ["kern", "liga", "tnum", "lnum", "case", "locl", "ccmp", "mark", "mkmk"]
    opts.hinting = False
    opts.notdef_outline = True
    sub = fsubset.Subsetter(opts)
    sub.populate(unicodes=SHARE_LATIN)
    sub.subset(latin)
    # grown: its outlines and metrics scaled to an em of 1000 * SHARE_GROW, then said to be of 1000
    scale_upem(latin, round(1000 * SHARE_GROW))
    latin["head"].unitsPerEm = 1000
    cjk = TTFont(io.BytesIO(source_bytes(cjk_url, None, "")))
    opts = fsubset.Options()
    opts.layout_features = ["*"]
    opts.hinting = False
    opts.notdef_outline = True
    sub = fsubset.Subsetter(opts)
    sub.populate(text=share_chars())
    sub.subset(cjk)
    # (tables only one of them has: the merger takes neither)
    for font, tables in ((latin, ("STAT", "gasp")), (cjk, ("vhea", "vmtx", "gasp"))):
        for t in tables:
            if t in font:
                del font[t]
    a, b = tmp / f"latin-{weight}.ttf", tmp / f"cjk-{weight}.ttf"
    latin.save(a)
    cjk.save(b)
    merged = Merger().merge([str(a), str(b)])
    # lines as 文楷's (the taller of the two by its own metrics would set every line apart more)
    merged["hhea"].ascent, merged["hhea"].descent, merged["hhea"].lineGap = cjk["hhea"].ascent, cjk["hhea"].descent, cjk["hhea"].lineGap
    o, c = merged["OS/2"], cjk["OS/2"]
    o.sTypoAscender, o.sTypoDescender, o.sTypoLineGap, o.usWinAscent, o.usWinDescent = (
        c.sTypoAscender, c.sTypoDescender, c.sTypoLineGap, c.usWinAscent, c.usWinDescent)
    o.usWeightClass = weight
    style = "Regular" if weight == 400 else "SemiBold"
    name = merged["name"]
    for i in (1, 2, 4, 6, 16, 17):
        name.removeNames(nameID=i)
    for i, v in ((1, "SF Share"), (2, "Regular"), (4, f"SF Share {style}"), (6, f"SFShare-{style}"), (16, "SF Share"), (17, style)):
        name.setName(v, i, 3, 1, 0x409)
    out = io.BytesIO()
    merged.save(out)
    return out.getvalue()


def share() -> None:
    """Writes SHARE_OUT: each weight's file, gzipped, as a Bytes literal (as inter_face.mbt keeps Inter)."""
    lines = [
        "// The share card's face: EB Garamond's Latin (grown to stand as tall as 霞鹜文楷's) and 霞鹜文楷's characters of the",
        "// card's words, one file a weight (SIL Open Font License, both). Made by scripts/fonts.py --share (do not edit: make",
        "// it again when the card's words change; a character not here is drawn in the system's face).",
        "",
    ]
    for weight, latin_url, cjk_url in SHARE_FACE:
        data = share_one(weight, latin_url, cjk_url)
        gz = gzip.compress(data, 9, mtime=0)
        print(f"share {weight}: {len(data)} bytes, {len(gz)} gzipped, sha256 {hashlib.sha256(data).hexdigest()}", file=sys.stderr)
        lit = "".join(chr(b) if 0x20 <= b < 0x7F and b not in (0x22, 0x5C) else "\\x%02x" % b for b in gz)
        lines += ["///|", "// kept across runs: a file's bytes, never written", f'let share_{weight}_gz : Bytes = b"{lit}"', ""]
    SHARE_OUT.write_text("\n".join(lines))


def put() -> None:
    names = sorted(p.relative_to(OUT).as_posix() for p in OUT.rglob("*") if p.is_file())
    if "--previews" in sys.argv:
        names = [n for n in names if n.rsplit("/", 1)[-1].startswith("preview-")]
    types = {".css": "text/css; charset=utf-8", ".woff2": "font/woff2", ".gz": "application/gzip", ".ttf": "font/ttf"}

    def one(name: str) -> str:
        t = types[Path(name).suffix]
        for _ in range(3):
            r = subprocess.run(["pnpm", "exec", "wrangler", "r2", "object", "put", f"stillfail-releases/{name}", "--file", str(OUT / name), "--content-type", t, "--remote"],
                               cwd=ROOT / "cloud", capture_output=True, text=True)
            if r.returncode == 0:
                return name
        sys.exit(f"putting {name}: {r.stderr[-400:]}")

    with concurrent.futures.ThreadPoolExecutor(12) as pool:
        for i, name in enumerate(pool.map(one, names)):
            if i % 50 == 0:
                print(f"put {i + 1}/{len(names)} {name}", file=sys.stderr)
    print(f"put {len(names)} files", file=sys.stderr)


def main() -> None:
    if "--share" in sys.argv:
        share()
        return
    made = [make(f) for f in FACES]
    print(json.dumps(made, indent=1))
    if "--put" in sys.argv:
        put()


if __name__ == "__main__":
    main()
