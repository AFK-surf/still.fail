#!/usr/bin/env python3
# The native tests on Linux (CI's check-mbui native, on GitHub's free Linux runners): the tests run against mbui's fake
# host (no window), so the hosts' own code (Objective-C on Apple, C++ on Windows) is only linked, not run. In a
# checkout made for that alone (it rewrites moon.pkg files), each package whose native stubs are Apple's or Windows'
# gets one C file instead (linux_stub.c): each of its externs answering nothing (zero, an empty string or bytes), but
# those mbui's linux_host.c does for real (what a test calls through the fake host: a text's decoding).
#   python3 scripts/linux_host.py DIR…   DIR: a src/ of packages (mbui's, the app's)
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.join(HERE, "..", "mbui", "src", "host", "linux_host.c")
real_src = open(REAL).read()
real = set(re.findall(r'^\w[\w\s\*]*?\b(mb_\w+)\s*\(', real_src, re.M))

head = re.compile(r'extern\s+"C"\s+fn\s+\w+\s*\(')
tail = re.compile(r'\s*(?:->\s*(.*?))?\s*=\s*"(\w+)"', re.S)


def externs(src):
    for m in head.finditer(src):
        i, depth = m.end(), 1
        while depth:
            depth += {"(": 1, ")": -1}.get(src[i], 0)
            i += 1
        t = tail.match(src, i)
        if t:
            yield src[m.end():i - 1], t.group(1), t.group(2)


def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        if ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out if x.strip()]


def ctype(t):
    t = (t or "Unit").strip()
    if t == "Unit":
        return "void"
    if t in ("Int", "Bool", "Char", "UInt", "Int16", "UInt16"):
        return "int32_t"
    if t in ("Int64", "UInt64"):
        return "int64_t"
    if t == "Double":
        return "double"
    if t == "Float":
        return "float"
    if t == "Byte":
        return "uint8_t"
    return "void*"


def answer(ret):
    r, t = ctype(ret), (ret or "").strip()
    if r == "void":
        return ""
    if t == "String":
        return " return moonbit_make_string(0, 0);"
    if t == "Bytes":
        return " return moonbit_make_bytes(0, 0);"
    return " return 0;"


seen = set(real)
for root in sys.argv[1:]:
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        pkg = os.path.join(p, "moon.pkg")
        if not os.path.isfile(pkg):
            continue
        txt = open(pkg).read()
        m = re.search(r'"native-stub"\s*:\s*\[([^\]]*)\]', txt)
        if not m:
            continue
        stubs = re.findall(r'"([^"]+)"', m.group(1))
        if not any(s.endswith((".m", ".mm", ".cpp")) for s in stubs):
            continue
        keep = [s for s in stubs if s.endswith(".c") and not s.startswith(("win_", "android_", "apple_", "mac_"))]
        lines = ["#include <stdint.h>", "#include <stddef.h>", '#include "moonbit.h"']
        for f in sorted(os.listdir(p)):
            if not f.endswith(".mbt") or f.endswith(("_js.mbt", "_test.mbt", "_wbtest.mbt")):
                continue
            for args, ret, sym in externs(open(os.path.join(p, f)).read()):
                if sym in seen:
                    continue
                seen.add(sym)
                params = []
                for i, a in enumerate(split_top(args)):
                    params.append(f'{ctype(a.split(":", 1)[1] if ":" in a else a)} a{i}')
                lines.append(f'{ctype(ret)} {sym}({", ".join(params) or "void"}) {{{answer(ret)} }}')
        if d == "host" and os.path.abspath(p) == os.path.abspath(os.path.dirname(REAL)):
            keep.append("linux_host.c")
            # (what the hosts give C beside MoonBit, post_api.h: the app's core posts through it)
            lines += ["void mb_post(const char *c, const char *j, size_t n, const uint8_t *b, size_t bn) { }",
                      "void mb_post_drop(const char *c) { }"]
        open(os.path.join(p, "linux_stub.c"), "w").write("\n".join(lines) + "\n")
        new = ", ".join(f'"{s}"' for s in keep + ["linux_stub.c"])
        txt = txt[:m.start(1)] + " " + new + " " + txt[m.end(1):]
        txt = txt.replace("-fobjc-arc", "")
        txt = re.sub(r'"cc-link-flags"\s*:\s*"[^"]*-framework[^"]*"', '"cc-link-flags": ""', txt)
        open(pkg, "w").write(txt)
        print(f"{p}: {len(lines) - 3} stubs, with {keep}")

# (a package's own C that posts through the host, post_api.h, the app's core: those functions in a file of its own
# too, weak: Linux's link takes a static library's objects in the order given, the host's before the one needing them)
POST = ('#include <stddef.h>\n#include <stdint.h>\n'
        '__attribute__((weak)) void mb_post(const char *c, const char *j, size_t n, const uint8_t *b, size_t bn) { }\n'
        '__attribute__((weak)) void mb_post_drop(const char *c) { }\n')
for root in sys.argv[1:]:
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        pkg = os.path.join(p, "moon.pkg")
        if not os.path.isfile(pkg) or d == "host":
            continue
        cs = [f for f in os.listdir(p) if f.endswith(".c") and f not in ("linux_stub.c", "linux_post.c")]
        if not any("mb_post" in open(os.path.join(p, f), errors="ignore").read() for f in cs):
            continue
        txt = open(pkg).read()
        if '"native-stub"' not in txt:
            continue
        open(os.path.join(p, "linux_post.c"), "w").write(POST)
        txt = re.sub(r'("native-stub"\s*:\s*\[)', r'\1 "linux_post.c",', txt, count=1)
        open(pkg, "w").write(txt)
        print(f"{p}: linux_post.c")
