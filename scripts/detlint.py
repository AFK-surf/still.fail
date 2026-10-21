#!/usr/bin/env python3
"""detlint: what a run's determinism must not rest on: a guessed time, a wait for the app to "settle", a frame the app
asks for itself, the machine's own clock. mbui runs it on itself; still.fail's apps/mbui runs the one of the mbui it
pins ($MBUI_DIR/scripts/detlint.py apps/mbui) with its own apps/mbui/detlint.json.

    python3 scripts/detlint.py [ROOT]            check ROOT (default: this script's module) against ROOT/detlint.json
    python3 scripts/detlint.py ROOT --update     write the counts found as the new bar (never above the old one;
                                                 --update=raise to raise it, said why in the commit)
    python3 scripts/detlint.py ROOT --list RULE  every finding of RULE, file:line

The bar (a ratchet): detlint.json keeps each rule's count of findings, file by file, and each file is held to its own:
one more in any file fails (a finding moved to another file too), naming it and its lines; fewer fails too, until
--update lowers the bar (the migration's own commit: what was moved off stays off). A rule whose bar is 0 is simply
forbidden.

The rules (see RULES below for each one's words):

    frame-request  anything but the scheduler itself (mbt.frame_core: the frame loop, the dispatch, the host's
                   bridge) asks for a frame (Ctx::request_frame, @host.request_frame, @ui.request_frame): components
                   and motion included; the framework knows when a frame is due (an input, an event, an animation's
                   declared end, a layout read)
    settle         anything waits for, or asks whether, the app is "settled" (Tester::settle / settled, Ctx::settled /
                   stable): stability is an assertion at the end (assert_idle), never a condition
    flow-wait      an end-to-end flow (*.drive) waits a fixed time (wait N, linger N)
    script-wait    a test or screenshot script waits a fixed time or a fixed frame count (sleep N, MBUI_SHOT_AT=N,
                   setTimeout(…, N), waitForTimeout(N), time.sleep(N))
    page-settle    a script waits on a web page until the app is settled (__mbhost.settled(), unsettled())
    frame-wait     a fiber waits for the next frame (@effect.next_frame()) outside the runtime itself: an animation
                   waits until the moment its run ends, a step until its time or its event, never a frame (how many
                   frames come is the display's)
    at-rest-wait   anything goes on until the app is at rest (settled by another name): at_rest() read anywhere but in
                   an assertion's arguments (assert_true(t.at_rest())), a drive's `rest` step (a flow's, a script's,
                   a test's drive text), a picture taken at the app's rest (MBUI_SHOT_MS=rest, shot_at=rest,
                   SHOT_AT=rest), a target waited on until it holds still from one frame to the next (held_still,
                   holds_still, hold_still, steady, still_at), a loop that runs the clock on while something still
                   moves or is still to come (rest_of, moving, next_wake read in it: an end's "on to what moves' end,
                   draw, again"): a step waits for its own named thing and acts where this frame has its target, an end
                   runs a declared time and asserts idle, a picture is of a declared moment
    frame-count    a test runs a fixed number of frames (for _ in 0..<N { t.frame() })
    literal-time   a time given as a bare number (run_for(347), wake_in(500.0), advance(16.0), frame(ms=33.0),
                   wake_at(c.now() + 500.0)): a time names what it is (an animation's, a timer's declared length)
    app-clock      the app reads the clock (c.now(), @ui.now(), @host.now()) to work out where an animation is or
                   whether a time has passed: motion / wake_at do that from what they declared
    engine-math    a sine, an exponential, a power… from @math (sin, cos, tan, asin, acos, atan, atan2, exp, expm1, ln,
                   ln_1p, log2, log10, pow, Double's pow): on js the engine's Math.*, its last bits the machine's (an
                   arm64 Mac's V8 and an x86 Linux's differ); @dmath's are worked out in MoonBit, the same everywhere
    wall-clock     the machine's own clock or randomness (Date.now, performance.now, Math.random, an unseeded
                   @random, a random id: uuid() / random_id() called with nothing, the system's uuid or random
                   bytes) outside the host that provides them; the time of day through @ui.wall_ms, for what is
                   shown of it, only as a source's `now` (now: fn() { @ui.wall_ms() })
    poll           a frame or a wake asked for under a condition that reads the host or the layout (a frame each
                   until it says yes): the host's answer, or the layout, is an event
    builtin-hash   a value made from MoonBit's own hash (x.hash(), Hash::hash, an `impl Hash` of one's own): it is seeded
                   anew in each process and differs between js and native; @ui.stable_hash (FNV-1a) is the same
                   everywhere. A Map's own keys are not this: only a hash taken out as data
    hash-order     a @hashmap / @hashset: gone through, its order is its hash's, the process's; a Map (in the order
                   put) or a sorted list
    host-read      the app reads where it runs from @host (now, wake_after, platform, system_dark, window_inset, env),
                   not through @ui, which a Tester answers
    globals        a mutable global (a top-level let of a Ref, Map, Array or struct) that its package's reset (reset,
                   reset_globals, or what on_reset is given) does not put back, nor says `// kept across runs: why`
    build-effect   a view (a function given the Ctx: what a frame's build runs) tells outside of it while it builds: a
                   call to its core ((src.call)(…), what detlint.json's build_effect.fields names), a host's effect
                   (@host.share, @ui.keep… : build_effect.calls), a native view's own (its reload, set_scale, seek,
                   close…: build_effect.methods, by name), or a function of the app's that does one, other than
                   in Ctx::after_build or Ctx::tell, in a callback (fn(…) { … }: an answer, an event's handler) or under an input
                   the frame takes (a click, a tap, a key, a drag let go, a menu's choice: taken by the frame's first
                   build only). A frame is built again while what it read changes, and what a build let go of told
                   outside is told all the same

An exception is written on the line itself or on the line above it, with its reason:

    c.request_frame() // det-ok(frame-request): the bench mode draws every frame on purpose
    # det-ok(script-wait): the emulator's boot has no event to wait for

They are printed with their reasons, and counted (detlint.json's `excused`, by rule and file), and only go down:
marking a finding det-ok does not make it go away. app-clock alone (SWAPPABLE: a time shown is right) lets an
exception take the place of a finding there was (found and excused together never above their bar).

What it reads: MoonBit through a lexer of its own (comments, strings with their interpolations, #| lines, chars,
numbers), a call being NAME ( … ) with what is before it (a receiver `.`, a package `@pkg.`, a type `T::`) and its
arguments split at the top level, the enclosing top-level item (a `test` block, a `fn`) and blocks with their
headers (if / while / match / guards). It does not know types: `x.request_frame()` is the Ctx's for any x. Where that
is wrong, see "Limits" in docs/detlint.md.
"""
import fnmatch
import json
import os
import re
import sys

# ---------------------------------------------------------------------------------------------------------------------
# MoonBit lexer

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(
    r"0[xX][0-9A-Fa-f_]+(?:[UL]+|N)?|0[oO][0-7_]+(?:[UL]+|N)?|0[bB][01_]+(?:[UL]+|N)?"
    r"|[0-9][0-9_]*(?:\.(?!\.)[0-9_]*)?(?:[eE][+-]?[0-9]+)?(?:UL|L|U|N|F)?"
)
OPS = ["..<", "..=", "...", "::", "=>", "->", "==", "!=", "<=", ">=", "&&", "||", "|>", "+=", "-=", "*=", "/=", "%=",
       "<<", ">>", ".."]


class Tok:
    __slots__ = ("kind", "text", "line", "col", "end")

    def __init__(self, kind, text, line, col):
        self.kind, self.text, self.line, self.col = kind, text, line, col
        self.end = None  # for an opening bracket: the index of its closing one

    def __repr__(self):
        return f"{self.kind}:{self.text}@{self.line}"


def lex(src):
    """Tokens (ident, num, str, op, at: @pkg) and the comments by line ({line: text})."""
    toks, comments = [], {}
    i, n, line, lstart = 0, len(src), 1, 0

    def col():
        return i - lstart + 1

    while i < n:
        ch = src[i]
        if ch == "\n":
            line += 1
            i += 1
            lstart = i
            continue
        if ch in " \t\r":
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            comments[line] = comments.get(line, "") + src[i:j]
            i = j
            continue
        if src.startswith("/*", i):  # not MoonBit's, but harmless
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            line += src.count("\n", i, j)
            i = j
            continue
        if (ch in "#$") and i + 1 < n and src[i + 1] == "|":
            j = src.find("\n", i)
            j = n if j < 0 else j
            toks.append(Tok("str", src[i + 2:j], line, col()))
            i = j
            continue
        if ch == '"':
            start_line, c0 = line, col()
            j, depth, buf = i + 1, 0, []
            while j < n:
                c = src[j]
                if c == "\\" and j + 1 < n:
                    if src[j + 1] == "{":
                        depth += 1
                        j += 2
                        continue
                    j += 2
                    continue
                if depth and c == "}":
                    depth -= 1
                elif depth and c == "{":
                    depth += 1
                elif not depth and c == '"':
                    break
                elif c == "\n":
                    line += 1
                    lstart = j + 1
                buf.append(c)
                j += 1
            toks.append(Tok("str", "".join(buf), start_line, c0))
            i = j + 1
            continue
        if ch == "'":
            m = re.match(r"'(?:\\u\{[0-9A-Fa-f]+\}|\\x[0-9A-Fa-f]{2}|\\.|[^'\\\n])'", src[i:])
            if m:
                toks.append(Tok("str", m.group(0), line, col()))
                i += len(m.group(0))
                continue
        if ch == "@" and i + 1 < n and (src[i + 1].isalpha() or src[i + 1] == "_"):
            m = IDENT.match(src, i + 1)
            toks.append(Tok("at", "@" + m.group(0), line, col()))
            i = m.end()
            continue
        if ch.isalpha() or ch == "_":
            m = IDENT.match(src, i)
            toks.append(Tok("ident", m.group(0), line, col()))
            i = m.end()
            continue
        if ch.isdigit():
            m = NUMBER.match(src, i)
            toks.append(Tok("num", m.group(0), line, col()))
            i = m.end()
            continue
        for op in OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, line, col()))
                i += len(op)
                break
        else:
            toks.append(Tok("op", ch, line, col()))
            i += 1
    # brackets
    stack = []
    for k, t in enumerate(toks):
        if t.kind != "op":
            continue
        if t.text in "([{":
            stack.append(k)
        elif t.text in ")]}" and stack:
            toks[stack.pop()].end = k
    return toks, comments


# ---------------------------------------------------------------------------------------------------------------------
# A MoonBit file: its items, its calls, its blocks

ITEM_KW = {"fn", "test", "let", "impl", "struct", "enum", "type", "trait", "extern", "typealias", "const", "suberror",
           "traitalias", "enumview"}


class Call:
    __slots__ = ("name", "kind", "qual", "at", "args", "item", "is_def")

    def __init__(self, name, kind, qual, at, args, item, is_def):
        # kind: "method" (x.name), "pkg" (@pkg.name), "type" (T::name), "bare" (name)
        self.name, self.kind, self.qual, self.at, self.args, self.item, self.is_def = (
            name, kind, qual, at, args, item, is_def)


class Item:
    __slots__ = ("kind", "name", "start", "end", "line")

    def __init__(self, kind, name, start, end, line):
        self.kind, self.name, self.start, self.end, self.line = kind, name, start, end, line


class MbtFile:
    def __init__(self, path, rel, src):
        self.path, self.rel, self.src = path, rel, src
        self.lines = src.split("\n")
        self.toks, self.comments = lex(src)
        base = os.path.basename(rel)
        self.test_file = base.endswith("_test.mbt") or base.endswith("_wbtest.mbt")
        self.items = self._items()
        self.item_of = [None] * len(self.toks)
        for it in self.items:
            for k in range(it.start, min(it.end + 1, len(self.toks))):
                self.item_of[k] = it
        self.calls = self._calls()
        self._assert_args = None

    def assert_args(self):
        """The token indices inside each assertion's arguments (assert_true(…), …): sets, one an assertion."""
        if self._assert_args is None:
            self._assert_args = [set(i for _, a in c.args for i in a) for c in self.calls
                                 if c.name in ASSERTS and not c.is_def]
        return self._assert_args

    def _items(self):
        """Top-level items: each from a keyword at the start of a line, outside any bracket (after pub, priv, async,
        declare), to the token before the next one."""
        toks, starts, depth = self.toks, [], 0
        for k, t in enumerate(toks):
            if depth == 0 and t.col == 1 and t.kind == "ident" and (t.text in ITEM_KW or t.text in (
                    "pub", "priv", "async", "declare")):
                starts.append(k)
            if t.kind == "op" and t.text in "([{":
                depth += 1
            elif t.kind == "op" and t.text in ")]}":
                depth = max(0, depth - 1)
        items = []
        for n, k in enumerate(starts):
            e = (starts[n + 1] - 1) if n + 1 < len(starts) else len(toks) - 1
            j = k
            while j < e and toks[j].line == toks[k].line and not (toks[j].kind == "ident" and toks[j].text in ITEM_KW):
                j += 1  # pub(all), async, declare
            kw = toks[j].text if toks[j].kind == "ident" else ""
            name = ""
            nt = toks[j + 1] if j + 1 <= e else None
            if nt is not None:
                if kw == "test":
                    name = nt.text if nt.kind == "str" else ""
                elif kw == "fn" and nt.kind == "op" and nt.text == "[" and nt.end is not None:
                    name = self._fn_name(nt.end + 1)
                elif kw in ("fn", "extern"):
                    name = self._fn_name(j + 1)
                elif nt.kind == "ident":
                    name = nt.text
            items.append(Item(kw, name, k, e, toks[k].line))
        return items

    def _fn_name(self, k):
        toks = self.toks
        if k >= len(toks):
            return ""
        if toks[k].kind == "str":  # extern "C" fn
            k += 1
            if k < len(toks) and toks[k].text == "fn":
                k += 1
        if k + 2 < len(toks) and toks[k + 1].text == "::":
            return toks[k].text + "::" + toks[k + 2].text
        return toks[k].text if k < len(toks) else ""

    def _calls(self):
        toks, out = self.toks, []
        for k in range(len(toks) - 1):
            t = toks[k]
            if t.kind != "ident":
                continue
            nx = toks[k + 1]
            if not (nx.kind == "op" and nx.text == "(" and nx.end is not None):
                # a method named and given a label (x.f~) is not called; `x.f` passed as a function is not either
                continue
            prev = toks[k - 1] if k else None
            prev2 = toks[k - 2] if k > 1 else None
            kind, qual = "bare", ""
            if prev is not None and prev.kind == "op" and prev.text == ".":
                if prev2 is not None and prev2.kind == "at":
                    kind, qual = "pkg", prev2.text
                else:
                    kind = "method"
            elif prev is not None and prev.kind == "op" and prev.text == "::":
                kind = "type"
                qual = prev2.text if prev2 is not None else ""
            is_def = False
            j = k - 1
            if kind == "type":
                j = k - 3
                if j >= 0 and toks[j].kind == "at":
                    j -= 2
            if j >= 0 and toks[j].kind == "op" and toks[j].text == "]":  # fn[T] Name::f
                pass
            if j >= 0 and toks[j].kind == "ident" and toks[j].text == "fn":
                is_def = True
            if j >= 0 and toks[j].kind == "op" and toks[j].text == "]":
                o = self._open_of(j)
                if o is not None and o > 0 and toks[o - 1].text == "fn":
                    is_def = True
            args = self._args(k + 1)
            out.append(Call(t.text, kind, qual, k, args, self.item_of[k], is_def))
        return out

    def _open_of(self, close):
        for o in range(close, -1, -1):
            if self.toks[o].end == close:
                return o
        return None

    def _args(self, open_):
        """The arguments of the call whose ( is at open_: [(label or None, [token indices])]."""
        toks, close = self.toks, self.toks[open_].end
        args, cur, k = [], [], open_ + 1
        while k < close:
            t = toks[k]
            if t.kind == "op" and t.text == ",":
                args.append(cur)
                cur = []
                k += 1
                continue
            if t.kind == "op" and t.text in "([{" and t.end is not None:
                cur.extend(range(k, t.end + 1))
                k = t.end + 1
                continue
            cur.append(k)
            k += 1
        if cur:
            args.append(cur)
        out = []
        for a in args:
            label = None
            if len(a) >= 2 and toks[a[0]].kind == "ident" and toks[a[1]].kind == "op" and toks[a[1]].text in ("=", "~"):
                label = toks[a[0]].text
                a = a[2:] if toks[a[1]].text == "=" else []
            out.append((label, a))
        return out

    def recv_type(self, k, returns):
        """The type of the receiver of the method called at k (x.name(…)): its last name (Tester, Ctx…), or None
        when it cannot be told. From: self in a `fn T::…`; a parameter or let annotated `x : T`; `let x = T::f(…)`,
        `let x = f(…)` with f declared `-> T` (returns: name -> type, across the files); `f(…).name(…)`."""
        toks = self.toks
        d = k - 1  # the "."
        r = d - 1
        if r < 0:
            return None
        rt = toks[r]
        if rt.kind == "op" and rt.text == ")":
            o = self._open_of(r)
            if o is not None and o > 0 and toks[o - 1].kind == "ident":
                if o > 1 and toks[o - 2].text == "::":
                    return toks[o - 3].text if o > 2 else None  # T::new(…).name
                if o > 1 and toks[o - 2].text == ".":
                    return None
                return returns.get(toks[o - 1].text)
            return None
        if rt.kind != "ident" or (r > 0 and toks[r - 1].text == "."):
            return None
        name = rt.text
        it = self.item_of[k]
        if name == "self":
            if it is not None and "::" in it.name:
                return it.name.split("::")[0]
            return None
        lo = it.start if it is not None else 0
        for j in range(r - 1, lo - 1, -1):
            t = toks[j]
            if t.kind != "ident" or t.text != name:
                continue
            nx = toks[j + 1] if j + 1 < len(toks) else None
            pv = toks[j - 1] if j > 0 else None
            if nx is not None and nx.text == ":" and not (pv is not None and pv.text == "."):
                ty = self._type_at(j + 2)
                if ty:
                    return ty
            if pv is not None and pv.text in ("let", "mut") and nx is not None and nx.text == "=":
                v = j + 2
                if v < len(toks) and toks[v].kind == "at":
                    v += 2
                if v + 2 < len(toks) and toks[v].kind == "ident" and toks[v + 1].text == "::":
                    return toks[v].text
                if v + 1 < len(toks) and toks[v].kind == "ident" and toks[v + 1].text == "(":
                    return returns.get(toks[v].text)
                return None
        return None

    def _type_at(self, j):
        toks = self.toks
        if j < len(toks) and toks[j].kind == "at":
            j += 2
        if j < len(toks) and toks[j].kind == "ident" and toks[j].text[:1].isupper():
            return toks[j].text
        return None

    def returns(self):
        """fn name(…) -> T: {name: T} for this file's functions."""
        out = {}
        for it in self.items:
            if it.kind != "fn" or not it.name:
                continue
            j = it.start
            while j < it.end:
                t = self.toks[j]
                if t.kind == "op" and t.text in "([" and t.end is not None:
                    j = t.end + 1
                    continue
                j += 1
                if t.kind == "op" and t.text == "{":
                    break
                if t.kind == "op" and t.text == "->":
                    j -= 1
                    ty = self._type_at(j + 1)
                    if ty:
                        out[it.name.split("::")[-1]] = ty
                    break
        return out

    def in_test(self, k):
        it = self.item_of[k]
        return self.test_file or (it is not None and it.kind == "test")

    def enclosing_conditions(self, k):
        """The tokens of each condition k runs under, innermost first: an if's or while's condition (an else's: the
        if's it is the other branch of), a match's scrutinee, an arm's pattern and guard."""
        toks, out = self.toks, []
        # the arm k is in, if any, within its block: `pattern (if guard)? => expr`
        opens = [o for o in range(k - 1, -1, -1) if toks[o].kind == "op" and toks[o].text in "({["
                 and toks[o].end is not None and toks[o].end > k]
        level_start = opens[0] + 1 if opens else 0
        out.extend(self._arm_before(level_start, k))
        for o in opens:
            if toks[o].text != "{":
                continue
            out.extend(self._header(o))
        return out

    def _arm_before(self, start, k):
        """In a block from start to k: the pattern and guard of the arm k's statement is in, if it has one."""
        toks = self.toks
        b = k - 1
        while b >= start:
            t = toks[b]
            if t.kind == "op" and t.text in (";",):
                break
            if t.kind == "op" and t.text in ")]}":
                o = self._open_of(b)
                b = (o if o is not None else b) - 1
                continue
            if t.kind == "op" and t.text == "=>":
                # the arm's head: back to the line where it starts (a pattern starts a line)
                h = b - 1
                while h >= start and toks[h].line == toks[b].line:
                    h -= 1
                return [list(range(h + 1, b))]
            if toks[b].line != toks[k].line and not (toks[b].kind == "op" and toks[b].text in ("(", ",")):
                # a statement on an earlier line: k's statement starts after it
                prev_line_tok = toks[b]
                if prev_line_tok.kind == "op" and prev_line_tok.text in ("{",):
                    break
            b -= 1
        return []

    def _header(self, o):
        """What a block opened at o is under: if/while/match head, else (the if's condition), an arm's head."""
        toks = self.toks
        # back from o to the start of its header: the nearest if/while/match/else/=>/for at this level
        b, head = o - 1, []
        while b >= 0:
            t = toks[b]
            if t.kind == "op" and t.text in ")]}":
                ob = self._open_of(b)
                if t.text == "}":
                    # `} else {`: the if's condition before the previous block
                    if head == [] and b + 1 < o and toks[b + 1].text == "else":
                        return self._header(ob) if ob is not None else []
                    break
                head = list(range(ob if ob is not None else b, b + 1)) + head
                b = (ob if ob is not None else b) - 1
                continue
            if t.kind == "op" and t.text in ("{", ";", ","):
                break
            if t.kind == "op" and t.text == "=>":
                # a block as an arm's body: the arm's head
                return self._arm_before(self._block_start(b), b + 1) + []
            if t.kind == "ident" and t.text in ("if", "while", "match", "guard"):
                return [head]
            if t.kind == "ident" and t.text in ("fn", "test", "for", "loop", "let"):
                return []
            head.insert(0, b)
            b -= 1
        return []

    def _block_start(self, k):
        toks = self.toks
        for o in range(k - 1, -1, -1):
            if toks[o].kind == "op" and toks[o].text == "{" and toks[o].end is not None and toks[o].end > k:
                return o + 1
        return 0

    def text_of(self, idx):
        return " ".join(self.toks[i].text for i in idx)


# ---------------------------------------------------------------------------------------------------------------------
# The rules

RULES = {
    "frame-request": "the app asks for a frame itself: the framework knows when one is due (an input, an event, an "
                     "animation's deadline, a layout read)",
    "settle": "waits for, or asks whether, the app is settled: stability is an end-of-test assertion (assert_idle), "
              "never what a step waits for",
    "flow-wait": "an end-to-end flow waits a fixed time: wait for the named thing (until, answered, ready, decoded)",
    "script-wait": "a test or screenshot script waits a fixed time or frame count: wait for the event, or take the "
                   "picture at a time the animations declare",
    "page-settle": "a script waits on a web page until the app is settled (__mbhost.settled): take it at a declared "
                   "time, or wait for the named thing",
    "frame-wait": "a fiber waits for the next frame: wait until the moment (an animation's declared end, a timer) or the "
                  "event, not a frame: how many frames come is the display's",
    "at-rest-wait": "goes on until the app is at rest (settled by another name): at_rest is asserted (assert_true("
                    "t.at_rest())), never waited on, nor run on in a loop while something moves or is still to come; a "
                    "step waits for its own named thing, an end runs a declared time and asserts idle, a picture is of "
                    "a declared moment",
    "frame-count": "a test runs a fixed number of frames: give the inputs and run_for a declared time",
    "literal-time": "a time given as a bare number: name what it is (an animation's or a timer's declared length)",
    "stable-mode": "the app draws otherwise when it is screenshotted (Ctx::stable): the picture is taken at a time "
                   "its animations declare, of the app as it runs",
    "retired-api": "an interface given up (an animation is data, declared once with its start and end): "
                   "frames_until, animating, animating_until, run_animations; motion_end run to, or read by the app",
    "app-clock": "the app reads the clock to work out an animation or a time passed: motion / wake_at do it from what "
                 "they declared",
    "wall-clock": "the machine's own clock or randomness, outside the host that provides them",
    "engine-math": "a sine, an exponential, a power from @math: on js the engine's Math.*, whose last bits are the "
                   "machine's; @dmath's (mbui/dmath) are the same on every machine",
    "poll": "a frame or a wake asked for under a condition that reads the host or the layout: that answer is an event",
    "host-read": "the app reads where it runs from @host: through @ui, which a Tester answers",
    "builtin-hash": "a value made from MoonBit's own hash (seeded anew in each process, not the same on js and "
                    "native): @ui.stable_hash",
    "hash-order": "a @hashmap / @hashset, its order the process's hash's: a Map (in the order put), or sort it",
    "globals": "a mutable global its package's reset does not put back, nor says `// kept across runs: why`",
    "style-literal": "a number where a style is said (a box's or words' look, @ui.style…), or an Exact(…) outside "
                     "the token files: name it with a token (docs/style.md)",
    "box-loose": "a box or words said by their loose look (pad=, bg=, size=…): say it as a named style (style=)",
    "style-exact": "a value off the theme's scale (Exact(…)), in a token file too: only goes down",
    "build-effect": "a view tells outside while it builds (a core's call, a host's effect): a frame is built again "
                    "while what it read changes, and a build let go of tells all the same; say it in Ctx::after_build "
                    "(once the frame's builds are over, as the last says it), or in the event's own handler",
    "unsettled-ok": "a test leaves out its end's idle check (unsettled_ok=…: what still moves or asks, until it says "
                    "its end): counted so the ones left only go",
}

# what @math works out by the engine on js (implementation-approximated in ECMAScript): @dmath's in their place
ENGINE_MATH = {"sin", "cos", "tan", "asin", "acos", "atan", "atan2", "exp", "expm1", "ln", "ln_1p", "log2", "log10",
               "pow", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "cbrt", "hypot"}
FRAME_ASK = {"request_frame", "wake_in", "wake_after", "wake_at", "wake_at_time", "frames_until"}
RETIRED = {"frames_until", "animating", "animating_until", "run_animations"}
# kept inside the framework, given up for tests and apps: run_for(motion_end() - time()) is run_animations again
RETIRED_OUTSIDE = {"motion_end"}
SETTLE = {"settle", "settled"}
# a target's place waited on until it holds still from frame to frame (a tap's, a drag's): settling by another name
# (by its names: `still` is not one, Ctx::still is the reduced motion's)
HOLD_STILL = {"held_still", "holds_still", "hold_still", "steady", "still_at"}
# what still moves or is still to come, read (where a motion ends, what moves, the next timer): in a loop that runs the
# clock on, a run "until it stops" (an end's "while something moves, on to its end, draw, again"): settling by another
# name. A step runs to one declared end (run_to(@ui.nav_rest())), an end a declared time, then assert_idle.
MOVE_READS = {"rest_of", "moving", "moving_now", "next_wake", "motion_end", "rest_why", "list_moving"}
CLOCK_RUNS = {"run_for", "run_to", "run_to_rest", "frame", "frame_at", "draw", "draw_owed", "advance"}
# what may hold at_rest(): an assertion's arguments (a test's end), nothing that goes on until it is
ASSERTS = {"assert_true", "assert_false", "assert_eq", "assert_not_eq", "inspect", "debug_inspect"}
SETTLE_TYPES = {"Tester", "Ctx", "Runtime"}
SETTLE_DEFS = {"settle", "settled", "unsettled", "stable", "assert_idle"}
TIME_FNS = {"run_for": 0, "wake_in": 0, "wake_after": 0, "wake_at": 0, "advance": 0, "frames_until": 0,
            "wake_at_time": 0}
CLOCK_READ = {"now"}
HOST_READS = {"now", "wake_after", "platform", "system_dark", "window_inset", "env"}
QUERY_DEFAULT = ["pressed", "list_row_height", "list_place", "rect_of", "row_height", "image_info", "view_info", "view_site_state",
                 "update_state", "shared_in", "made", "grabbed", "photos", "kept", "files"]
WALL_WORDS = re.compile(r"\b(Date\.now|performance\.now|Math\.random|crypto\.getRandomValues|clock_gettime|"
                        r"gettimeofday|mach_absolute_time|CFAbsoluteTimeGetCurrent|arc4random|"
                        # the system's random ids and bytes (a uuid made new each run)
                        r"crypto\.randomUUID|randomUUID|NSUUID|uuid_generate|SecRandomCopyBytes|getrandom|"
                        r"BCryptGenRandom|SecureRandom|rand|srand|random)\b(?=\s*\()|"
                        r"\b(Date\.now|performance\.now|Math\.random|NSUUID|SecureRandom|randomUUID)\b|/dev/u?random")
# the time of day read as a source's `now`, the one place it may be (@ui.wall_ms)
WALL_AS_NOW = re.compile(r"\bnow\s*:\s*fn\s*\(\s*\)\s*\{\s*@ui\.wall_ms\(\s*\)\s*\}")
# a function that makes a random id when called with nothing (a uuid, a random id); given something, it only shapes
# what it is given (`uuid(hash)`: the same each run)
RANDOM_IDS = {"uuid", "uuid4", "uuid_v4", "new_uuid", "random_uuid", "random_id", "rand_id", "random_hex",
              "random_string", "random_bytes"}
PLAIN_TYPES = {"Int", "Int64", "UInt", "UInt64", "Int16", "UInt16", "Double", "Float", "String", "Bool", "Char", "Byte",
               "Bytes", "Json", "Unit"}

# what a host does that is seen outside the app (a sheet opened, a file kept, the system's state set), as the app calls
# it: @pkg.name
BUILD_EFFECT_CALLS = ["@host.share", "@host.open_url", "@host.notice_show", "@host.set_sideways", "@host.set_dark",
                      "@host.update_install", "@host.push_token", "@host.gallery_ask", "@host.exit", "@host.keep",
                      "@host.save_file", "@host.clipboard_set", "@ui.share", "@ui.open_url", "@ui.notice_show",
                      "@ui.notice_ask", "@ui.keep", "@ui.keep_bytes", "@ui.clipboard_set", "@ui.save_file",
                      "@ui.pick", "@ui.set_sideways", "@ui.exit", "@ui.clipboard_set_png", "@ui.clipboard_read",
                      "@ui.keep_awake", "@ui.haptic", "@host.clip_set_text", "@host.clip_set_png", "@host.clip_read",
                      "@host.keep_awake", "@host.haptic"]
# a native view's (a page, a site, a video), a PDF's and a keep's own that tell its host (NativeView::reload, …):
# by their names, whatever they are called on but the Ctx (an app's own of the same name, a player's seek, tells it on)
BUILD_EFFECT_METHODS = ["go_back", "go_forward", "reload", "load", "set_scale", "close", "play", "pause", "seek",
                        "rate", "grab_frame"]
# what a frame takes once, at its first build (frame_body clears them after it): under one of these an effect is the
# input's
# a closure given to one of these runs later than the build: a fiber, a timer, a host's answer, a page's leaving
LATER_CALLS = {"fork", "effect", "spawn", "after", "later", "video", "site", "subscribe", "each_later", "watch",
               "take_back"}
# (a stream's `shown` and `broken`: @ui.Stream's events, taken as a frame begins and after it is painted)
LATER_LABELS = {"done", "answer", "then", "leave", "serve", "read", "back", "cancel", "fail", "ok", "shown", "broken"}
# called with the Ctx in a condition, not a widget's use: a time, a hold, a layout's read
NOT_INPUT_CALLS = {"after", "held", "within", "mark", "list_info", "rect_of", "words_of", "is_wide", "presence",
                   "animate", "theme", "window_size", "list_place"}
# a widget whose answer is what the finger or the keys chose this frame (a choice, a code typed in)
INPUT_VALUE_CALLS = {"segmented", "code_field", "toggle", "switch", "slider", "stepper"}
INPUT_WORDS = {"clicked", "tapped", "take_end", "take_tap", "take_key", "key_pressed", "chosen", "dismissed", "acted",
               "submitted", "right_clicked", "shortcut", "take_move", "pasted", "took"}

EXC = re.compile(r"det-ok\(([a-z-]+(?:\s*,\s*[a-z-]+)*)\)\s*:?\s*(.*)")


class Finding:
    __slots__ = ("rule", "file", "line", "what", "excused")

    def __init__(self, rule, file, line, what):
        self.rule, self.file, self.line, self.what, self.excused = rule, file, line, what, None


def under(rel, prefixes):
    return any(rel == p or rel.startswith(p.rstrip("/") + "/") for p in prefixes)


def matches(rel, globs):
    return any(fnmatch.fnmatch(rel, g) for g in globs)


class Config:
    def __init__(self, d):
        self.mbt_roots = d.get("mbt", {}).get("roots", ["src"])
        self.framework = d.get("mbt", {}).get("framework", [])
        # the scheduler itself (the frame loop, the dispatch of inputs and events, the host's bridge): the only place
        # a frame is asked for
        self.frame_core = d.get("mbt", {}).get("frame_core", [])
        self.clock_sources = d.get("mbt", {}).get("clock_sources", [])
        self.queries = set(d.get("mbt", {}).get("queries", QUERY_DEFAULT))
        self.globals_roots = d.get("globals", {}).get("roots", [])
        self.flows = d.get("flows", [])
        self.scripts = d.get("scripts", [])
        self.skip = d.get("skip", [])
        self.counts = d.get("counts", {})
        # the token files: where a style's numbers are said (style-literal does not count them there)
        self.style_tokens = d.get("style", {}).get("tokens", [])
        # what tells outside of a frame: field calls ((src.call)(…): their field's name) and package functions
        be = d.get("build_effect", {})
        self.effect_fields = set(be.get("fields", ["call", "subscribe"]))
        self.effect_calls = set(be.get("calls", BUILD_EFFECT_CALLS))
        self.effect_methods = set(be.get("methods", BUILD_EFFECT_METHODS))


def lint_mbt(f, cfg, out, returns, readers):
    app = not under(f.rel, cfg.framework)
    toks = f.toks

    def add(rule, k, what):
        out.append(Finding(rule, f.rel, toks[k].line, what))

    for c in f.calls:
        # the interfaces given up: neither defined nor called, anywhere
        if c.name in RETIRED and (c.is_def or c.kind in ("method", "pkg", "bare", "type")):
            add("retired-api", c.at, f.lines[toks[c.at].line - 1].strip())
        # the same, as the framework keeps it for itself: not called by the app, nor run to by a test (its own
        # tests may read it)
        if c.name in RETIRED_OUTSIDE and not c.is_def and app and not f.in_test(c.at):
            add("retired-api", c.at, f.lines[toks[c.at].line - 1].strip())
        if c.name in TIME_FNS or c.name == "frame":
            if any(toks[i].kind == "ident" and toks[i].text in RETIRED_OUTSIDE for _, a in c.args for i in a):
                add("retired-api", c.at, f.lines[toks[c.at].line - 1].strip())
        if c.is_def:
            continue
        test = f.in_test(c.at)
        item = c.item
        line_text = f.lines[toks[c.at].line - 1].strip()
        # 1. the app asks for a frame
        # (bare: the framework's own, in its package: h_request_frame, hostread's request_frame)
        if c.name in ("request_frame", "h_request_frame") and not under(f.rel, cfg.frame_core) and not test:
            add("frame-request", c.at, line_text)
        # 2. settle / settled / stable, but in their own definitions
        if c.name in SETTLE and c.kind in ("method", "pkg"):
            own = item is not None and item.kind == "fn" and item.name.split("::")[-1] in SETTLE_DEFS
            ty = f.recv_type(c.at, returns) if c.kind == "method" else c.qual
            if not own and (ty is None or ty in SETTLE_TYPES or c.kind == "pkg"):
                add("settle", c.at, line_text + ("   (receiver's type not known: counted)" if ty is None else ""))
        # a fiber waiting for a frame, but the runtime's own (src/effect: its definition, its scheduler; src/effecttest:
        # its tests)
        if c.name == "next_frame" and c.kind in ("pkg", "bare") and not under(f.rel, ["src/effect", "src/effecttest"]):
            add("frame-wait", c.at, line_text)
        # 3. at rest, read but in an assertion (the framework's own reading of it as a frame ends: frame_core)
        if c.name == "at_rest" and c.kind in ("method", "pkg", "bare") and not under(f.rel, cfg.frame_core):
            if not any(c.at in held for held in f.assert_args()):
                add("at-rest-wait", c.at, line_text)
        # the engine's own sine, exponential, power (and a Double's pow, which is @math's)
        if (c.kind == "pkg" and c.qual == "@math" and c.name in ENGINE_MATH) or (
                c.kind == "method" and c.name == "pow" and f.recv_type(c.at, returns) in ("Double", None)):
            add("engine-math", c.at, line_text)
        # a target waited on until it holds still
        if c.name in HOLD_STILL and c.kind in ("method", "bare"):
            add("at-rest-wait", c.at, line_text)
        # the app as it is screenshotted is not the app
        if c.name == "stable" and c.kind == "method" and not test and not c.args and f.recv_type(
                c.at, returns) in ("Ctx", None):
            add("stable-mode", c.at, line_text)
        # 4. a bare number as a time
        if c.name in TIME_FNS or (c.name == "frame" and c.kind == "method"):
            for label, a in c.args:
                if c.name == "frame" and label != "ms":
                    continue
                if c.name != "frame" and label is not None:
                    continue
                if literal_time(f, a):
                    add("literal-time", c.at, line_text)
                    break
        # 5. the app reads the clock
        if c.name in CLOCK_READ and app and not test and c.kind in ("method", "pkg") and not c.args:
            add("app-clock", c.at, line_text)
        # wall clock through a provider's function outside it; @ui.wall_ms, the time of day for what is shown of it,
        # only as a source's `now` (now: fn() { @ui.wall_ms() }): never what a wait or a motion is timed by
        if c.name in ("wall_ms", "ffi_wall_ms") and not under(f.rel, cfg.clock_sources) and not test and \
                not (c.qual == "@ui" and WALL_AS_NOW.search(line_text)):
            add("wall-clock", c.at, line_text)
        # a random id made new each run (uuid(), random_id()): an id the app needs is drawn from what the run gives
        # it (a seed, a counter, the frames' clock), so the same run makes the same one
        if c.name in RANDOM_IDS and not c.args and not under(f.rel, cfg.clock_sources) and not test:
            add("wall-clock", c.at, line_text)
        # 6. a frame asked under a condition that reads the host or the layout
        if c.name in FRAME_ASK and c.kind in ("method", "pkg") and not test and not under(f.rel, cfg.host_dirs()):
            timed = c.name != "request_frame" and not any(literal_time(f, a) for lb, a in c.args if lb is None)
            for cond in f.enclosing_conditions(c.at):
                q = reads_query(f, cond, cfg, readers)
                # a wake at a deadline while a finger is down (a long press) is the deadline, not a poll
                if q and not (timed and q.split(" ")[-1] == "pressed"):
                    add("poll", c.at, f"{line_text}   (under: {q})")
                    break
        # 8. MoonBit's own hash taken out as a value (x.hash(), Hash::hash(x)): seeded per process
        if c.name == "hash" and not test and ((c.kind == "method" and not c.args) or (c.kind == "type" and
                                                                                     c.qual == "Hash")):
            add("builtin-hash", c.at, line_text)
        # 7a. @host's reads in the app
        if c.kind == "pkg" and c.qual == "@host" and c.name in HOST_READS and app and not test:
            add("host-read", c.at, line_text)
    # wall clock and randomness in externs' bodies and anywhere else
    if not under(f.rel, cfg.clock_sources):
        for k, t in enumerate(toks):
            if t.kind == "str" and WALL_WORDS.search(t.text) and not f.in_test(k):
                add("wall-clock", k, f.lines[t.line - 1].strip())
            if t.kind == "at" and t.text == "@random" and k + 2 < len(toks):
                # @random.Rand::new() without a seed
                j = k + 1
                while j < len(toks) and j < k + 8 and not (toks[j].kind == "op" and toks[j].text == "("):
                    j += 1
                if j < len(toks) and toks[j].text == "(" and toks[j].end == j + 1:
                    add("wall-clock", k, f.lines[t.line - 1].strip())
    # an `impl Hash for T` of one's own (its hash a value of the process's seed), and the hashed collections (their
    # order the process's)
    for k, t in enumerate(toks):
        if f.in_test(k):
            continue
        if t.kind == "ident" and t.text == "impl" and k + 2 < len(toks) and toks[k + 1].text == "Hash" and \
                toks[k + 2].text == "for":
            add("builtin-hash", k, f.lines[t.line - 1].strip())
        if t.kind == "at" and t.text in ("@hashmap", "@hashset"):
            add("hash-order", k, f.lines[t.line - 1].strip())
    # a loop that runs the clock on while something still moves or is still to come: run until it stops
    if not under(f.rel, cfg.frame_core):
        for k, line in run_until_still(f):
            add("at-rest-wait", k, line)
    # 3. a fixed count of frames in a test
    for k, t in enumerate(toks):
        if t.kind == "ident" and t.text == "for" and f.in_test(k):
            # for _ in 0..<N { … .frame( … }
            j, rng = k + 1, []
            while j < len(toks) and not (toks[j].kind == "op" and toks[j].text == "{"):
                rng.append(j)
                j += 1
            if j >= len(toks) or toks[j].end is None:
                continue
            body = range(j, toks[j].end)
            has_range = any(toks[r].text in ("..<", "..=") for r in rng)
            bound_lit = has_range and all(toks[r].kind != "ident" or toks[r].text in ("in", "_") or
                                          toks[r] is toks[k + 1] for r in rng) and any(
                toks[r].kind == "num" and toks[r].text not in ("0", "1") for r in rng)
            if bound_lit and any(toks[b].kind == "ident" and toks[b].text == "frame" and
                                 toks[b - 1].text == "." for b in body):
                add("frame-count", k, f.lines[t.line - 1].strip())


def run_until_still(f):
    """The loops (while, loop, a `for` that is not over what it is given) that run the clock on (CLOCK_RUNS called in them) and read what still moves or is
    still to come (MOVE_READS) outside a loop within them so counted: each such loop once, where it begins."""
    toks = f.toks
    loops = []
    for k, t in enumerate(toks):
        if t.kind == "ident" and t.text in ("while", "loop", "for"):
            j = k + 1
            while j < len(toks) and not (toks[j].kind == "op" and toks[j].text == "{"):
                j += 1
            # (a `for … in` goes over what it is given, the steps of a test: not on until something stops)
            over = t.text == "for" and any(toks[i].kind == "ident" and toks[i].text == "in" for i in range(k + 1, j))
            if j < len(toks) and toks[j].end is not None and not over:
                loops.append((k, toks[j].end))

    def called(i, names):
        return toks[i].kind == "ident" and toks[i].text in names and i + 1 < len(toks) and \
            toks[i + 1].text == "(" and i > 0 and toks[i - 1].text in (".", "::")

    def inside(i, lp):
        return lp[0] < i < lp[1]

    runs = [lp for lp in loops if any(called(i, CLOCK_RUNS) for i in range(lp[0] + 1, lp[1]))]
    out = []
    for lp in runs:
        inner = [o for o in runs if o != lp and inside(o[0], lp)]
        if any(called(i, MOVE_READS) and not any(inside(i, o) for o in inner) for i in range(lp[0] + 1, lp[1])):
            out.append((lp[0], f.lines[toks[lp[0]].line - 1].strip()))
    return out


# what a box and words look like said loosely (Ctx::box, row, column, layer, text, rich): box-loose; a number in them,
# or anywhere in a style's constructors (style.mbt), style-literal
BOX_LOOK = {"dir", "w", "h", "pad", "padx", "pady", "pl", "pr", "pt", "pb", "gap", "align", "justify", "bg", "radius",
            "border", "border_color", "shadow", "shadow_color", "shadow_y", "min_w", "max_w", "min_h", "max_h", "clip",
            "opacity"}
TEXT_LOOK = {"size", "weight", "color", "wrap", "w", "line", "center", "tracking", "max_lines"}
# a count, not a look's value: no style-literal
COUNTS = {"max_lines"}
LOOSE_CALLS = {"box": BOX_LOOK, "row": BOX_LOOK, "column": BOX_LOOK, "layer": BOX_LOOK, "text": TEXT_LOOK,
               "rich": TEXT_LOOK}
STYLE_MAKERS = {"style", "patch", "text_style", "text_patch"}


def lint_style(f, cfg, out):
    """style-literal, box-loose, style-exact (docs/style.md): tests are not counted."""
    toks = f.toks
    tokens_file = matches(f.rel, cfg.style_tokens)
    counted = set()

    def add(rule, k, what):
        out.append(Finding(rule, f.rel, toks[k].line, what))

    def exact_at(k):
        """An Exact(…) made (not the enum's own declaration, nor a match arm's pattern)."""
        if not (toks[k].kind == "ident" and toks[k].text == "Exact" and k + 1 < len(toks) and toks[k + 1].text == "("):
            return False
        it = f.item_of[k]
        if it is not None and it.kind == "enum":
            return False
        end = toks[k + 1].end
        return not (end is not None and end + 1 < len(toks) and toks[end + 1].text in ("=>", "|"))

    for k in range(len(toks)):
        if exact_at(k) and not f.in_test(k):
            add("style-exact", k, f.lines[toks[k].line - 1].strip())
            if not tokens_file:
                add("style-literal", k, f.lines[toks[k].line - 1].strip())
                end = toks[k + 1].end or k + 1
                counted.update(range(k, end + 1))
    if tokens_file:
        return
    for c in f.calls:
        if c.is_def or f.in_test(c.at):
            continue
        line_text = f.lines[toks[c.at].line - 1].strip()
        look = None
        if c.kind == "method" and c.name in LOOSE_CALLS:
            look = LOOSE_CALLS[c.name]
            if any(label in look for label, _ in c.args):
                add("box-loose", c.at, line_text)
        maker = c.name in STYLE_MAKERS and (c.kind == "pkg" and c.qual == "@ui" or c.kind == "bare")
        for label, a in c.args:
            if not maker and (look is None or label not in look) or label in COUNTS:
                continue
            for i in a:
                if toks[i].kind == "num" and i not in counted:
                    counted.add(i)
                    add("style-literal", i, line_text)


def cfg_host_dirs(self):
    return [p for p in self.framework if p.rstrip("/").endswith("/host")]


Config.host_dirs = cfg_host_dirs


def literal_time(f, idx):
    """Whether a time argument is a bare number: its tokens, the clock's reads taken out (c.now(), now(), t.time()),
    are numbers and operators only, with a number among them."""
    toks = f.toks
    skip = set()
    for i in idx:
        t = toks[i]
        if t.kind == "ident" and t.text in ("now", "time") and i + 1 < len(toks) and toks[i + 1].text == "(":
            skip.update(range(i, (toks[i + 1].end or i + 1) + 1))
            j = i - 1
            while j >= 0 and toks[j].text == "." and j - 1 >= 0 and toks[j - 1].kind in ("ident", "at"):
                skip.update((j, j - 1))
                j -= 2
    rest = [toks[i] for i in idx if i not in skip]
    if not rest or all(t.kind != "num" or float(re.sub(r"[_A-Za-z]+$", "", t.text.replace("_", "")) or 0) == 0
                       for t in rest if t.kind == "num") and not skip:
        return False  # no time at all (frame(ms=0.0)) is not a guess
    if any(t.kind in ("ident", "at", "str") for t in rest):
        return False
    return any(t.kind == "num" for t in rest)


def reads_query(f, cond, cfg, readers=None):
    toks = f.toks
    for i in cond:
        t = toks[i]
        if t.kind == "ident" and i + 1 < len(toks) and toks[i + 1].text == "(":
            prev = toks[i - 1] if i else None
            if readers and (prev is None or prev.text != ".") and (os.path.dirname(f.rel), t.text) in readers:
                return t.text + "() → " + readers[(os.path.dirname(f.rel), t.text)]
            if prev is not None and prev.text == "." and i >= 2 and toks[i - 2].kind == "at" and toks[i - 2].text == "@host":
                return "@host." + t.text
            if t.text in cfg.queries and prev is not None and prev.text == ".":
                return t.text
            if t.text.startswith("h_") and t.text[2:] in cfg.queries:
                return t.text
    return None


def host_readers(files, cfg):
    """The package's own functions that read the host or the layout, themselves or through another such function
    of their package: {(package dir, name): what they read}."""
    bodies = {}
    for f in files:
        if f.test_file:
            continue
        pkg = os.path.dirname(f.rel)
        for it in f.items:
            if it.kind == "fn" and it.name and "::" not in it.name:
                bodies[(pkg, it.name)] = (f, range(it.start, it.end + 1))
    readers = {}
    changed = True
    while changed:
        changed = False
        for key, (f, rng) in bodies.items():
            if key in readers:
                continue
            q = reads_query(f, rng, cfg, readers)
            if q:
                readers[key] = q
                changed = True
    return readers


def lint_globals(files, cfg, out):
    """7b: per package under globals.roots, every top-level let of a non-plain type is put back by the package's
    reset (reset, reset_globals, a function given to on_reset, and what those call) or says why not."""
    pkgs = {}
    for f in files:
        if f.test_file or not under(f.rel, cfg.globals_roots):
            continue
        pkgs.setdefault(os.path.dirname(f.rel), []).append(f)
    alias = {os.path.basename(p): p for p in pkgs}
    fns = {}  # (pkg, name) -> [token lists]
    roots = []
    lets = []
    for pkg, fs in pkgs.items():
        for f in fs:
            for it in f.items:
                body = f.toks[it.start:it.end + 1]
                if it.kind == "fn":
                    fns.setdefault((pkg, it.name.split("::")[-1] if "::" not in it.name else it.name), []).append(body)
                    if it.name in ("reset", "reset_globals"):
                        roots.append((pkg, it.name))
                elif it.kind == "let":
                    lets.append((pkg, f, it))
            for c in f.calls:
                if c.name == "on_reset" and c.args:
                    _, a = c.args[0]
                    toks = [f.toks[i] for i in a]
                    if len(toks) == 1 and toks[0].kind == "ident":
                        roots.append((pkg, toks[0].text))
                    else:
                        fns.setdefault((pkg, f"<on_reset {f.rel}:{f.toks[c.at].line}>"), []).append(toks)
                        roots.append((pkg, f"<on_reset {f.rel}:{f.toks[c.at].line}>"))
    said = {p: set() for p in pkgs}
    seen, todo = set(), list(roots)
    while todo:
        key = todo.pop()
        if key in seen or key not in fns:
            continue
        seen.add(key)
        pkg = key[0]
        for body in fns[key]:
            for i, t in enumerate(body):
                if t.kind == "ident":
                    if not (i and body[i - 1].text == "."):  # a field of the same name is not the global
                        said[pkg].add(t.text)
                    if i + 1 < len(body) and body[i + 1].text == "(":
                        q = body[i - 2].text if i >= 2 and body[i - 1].text == "." and body[i - 2].kind == "at" else None
                        p = alias.get(q[1:]) if q else pkg
                        if p is not None:
                            todo.append((p, t.text))
                    if i >= 2 and body[i - 1].text == "." and body[i - 2].kind == "at" and body[i - 2].text[1:] in alias:
                        said[alias[body[i - 2].text[1:]]].add(t.text)
    for pkg, f, it in lets:
        toks = f.toks[it.start:it.end + 1]
        # let NAME (: TYPE)? = VALUE
        k = 0
        while k < len(toks) and toks[k].text != "let":
            k += 1
        if k + 1 >= len(toks) or toks[k + 1].kind != "ident":
            continue
        name = toks[k + 1].text
        ty, j = [], k + 2
        if j < len(toks) and toks[j].text == ":":
            j += 1
            while j < len(toks) and toks[j].text != "=":
                ty.append(toks[j])
                j += 1
        value = toks[j + 1:] if j < len(toks) else []
        tynames = {t.text for t in ty if t.kind == "ident"}
        if ty and tynames <= PLAIN_TYPES:
            continue
        if ty and ty[0].text == "(" and ty[0].end is not None and any(t.text == "->" for t in ty) and not any(
                t.text in ("Ref", "Array", "Map", "Set", "FixedArray") for t in ty):
            continue  # a function: a top-level let cannot be set again
        if not ty and value and len(value) == 1 and value[0].kind in ("num", "str"):
            continue
        if not ty and value and all(t.kind in ("num", "str", "op") or t.text in ("true", "false") for t in value):
            continue
        # the comment over it
        above = it.line - 1
        while above >= 1 and f.lines[above - 1].strip() == "":
            above -= 1
        kept = above >= 1 and f.lines[above - 1].strip().startswith("// kept across runs:")
        # doc comments (///) between: look over them
        a2 = above
        while not kept and a2 >= 1 and f.lines[a2 - 1].strip().startswith("//"):
            if f.lines[a2 - 1].strip().startswith("// kept across runs:"):
                kept = True
            a2 -= 1
        if kept or name in said[pkg]:
            continue
        out.append(Finding("globals", f.rel, it.line, f"{name} : {' '.join(t.text for t in ty) or '(inferred)'}"))


# ---------------------------------------------------------------------------------------------------------------------
# Flows and scripts

DRIVE_WAIT = re.compile(r"^\s*(wait|linger)\s+[0-9]")
# a drive's `rest` step: a flow's line, or a line of drive text in a string (a test's, a script's)
DRIVE_REST = re.compile(r"^\s*rest\s*(#.*)?$")
DRIVE_REST_TEXT = re.compile(r"(\\n|^\s*#\||\"|')rest\s*(\\n|\"|'|$)")
# a picture at the app's rest
SHOT_REST = re.compile(r"\b(MBUI_SHOT_MS|shot_at|SHOT_AT)\s*=\s*[\"']?rest\b")
SCRIPT_WAITS = [
    re.compile(r"(?<![\w-])sleep\s+[\"'$0-9.]"),
    re.compile(r"\bMBUI_SHOT_AT=[\"'$0-9]"),
    re.compile(r"\bsetTimeout\(.*[^\w.][0-9]"),
    re.compile(r"\bwaitForTimeout\("),
    re.compile(r"\btime\.sleep\("),
]
PAGE_SETTLE = re.compile(r"\b__mb\w*\.(?:settled|unsettled)\b")
# a test's end without its idle check: Tester::settle's, a replay's Flow::end's (an argument, not a declaration)
UNSETTLED_OK = re.compile(r"\bunsettled_ok\s*=")


def lint_lines(rel, src, rule, pats, out, comment):
    for n, line in enumerate(src.split("\n"), 1):
        s = line.lstrip()
        if s.startswith(comment) and "det-ok(" not in s:
            continue
        for p in pats:
            m = p.search(line)
            if m:
                # in a comment after the code
                ci = line.find(" " + comment + " ")
                if ci >= 0 and ci < m.start():
                    continue
                out.append(Finding(rule, rel, n, line.strip()))
                break


# ---------------------------------------------------------------------------------------------------------------------
# Exceptions, the bar, the report

def excuse(findings, texts):
    for fd in findings:
        lines = texts.get(fd.file)
        if lines is None:
            continue
        for ln in (fd.line, fd.line - 1):
            if 1 <= ln <= len(lines):
                m = EXC.search(lines[ln - 1])
                if m and fd.rule in [r.strip() for r in m.group(1).split(",")]:
                    reason = m.group(2).strip()
                    fd.excused = reason or None
                    if not reason:
                        fd.what += "   (det-ok without a reason: not taken)"
                    break


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def collect(root, cfg):
    findings, texts, mbts = [], {}, []
    for dirpath, dirnames, names in os.walk(root):
        rd = os.path.relpath(dirpath, root).replace(os.sep, "/")
        rd = "" if rd == "." else rd
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d not in (
            "_build", "node_modules", "target", ".mooncakes", "out") and not matches(
            (rd + "/" + d).lstrip("/"), cfg.skip))
        for n in sorted(names):
            rel = (rd + "/" + n).lstrip("/")
            if matches(rel, cfg.skip):
                continue
            path = os.path.join(dirpath, n)
            if n.endswith(".mbt") and under(rel, cfg.mbt_roots):
                src = read(path)
                texts[rel] = src.split("\n")
                mbts.append(MbtFile(path, rel, src))
                lint_lines(rel, src, "unsettled-ok", [UNSETTLED_OK], findings, "//")
                lint_lines(rel, src, "at-rest-wait", [DRIVE_REST_TEXT, SHOT_REST], findings, "//")
            elif matches(rel, cfg.flows):
                src = read(path)
                texts[rel] = src.split("\n")
                lint_lines(rel, src, "flow-wait", [DRIVE_WAIT], findings, "#")
                lint_lines(rel, src, "at-rest-wait", [DRIVE_REST], findings, "#")
            elif matches(rel, cfg.scripts):
                src = read(path)
                texts[rel] = src.split("\n")
                comment = "//" if n.endswith((".mjs", ".js", ".ts")) else "#"
                lint_lines(rel, src, "script-wait", SCRIPT_WAITS, findings, comment)
                lint_lines(rel, src, "page-settle", [PAGE_SETTLE], findings, comment)
                lint_lines(rel, src, "at-rest-wait", [SHOT_REST, DRIVE_REST_TEXT], findings, comment)
    returns = {}
    for f in mbts:
        returns.update(f.returns())
    readers = host_readers(mbts, cfg)
    for f in mbts:
        lint_mbt(f, cfg, findings, returns, readers)
        lint_style(f, cfg, findings)
    lint_globals(mbts, cfg, findings)
    lint_build_effects(mbts, cfg, findings)
    excuse(findings, texts)
    return findings


def lint_build_effects(files, cfg, out):
    """build-effect: what a view tells outside while it builds (RULES): the effects (a field call (x.call)(…), a
    package's effect, a native view's own: its reload, its seek) and the app's functions that do one (found to a fixed
    point), called in a function given the Ctx, other than in Ctx::after_build, a callback (fn(…) { … }) or under an
    input the frame takes."""
    app = [f for f in files if not f.test_file and not under(f.rel, cfg.framework)]

    def header(f, it):
        toks, k = f.toks, it.start
        while k <= it.end and not (toks[k].kind == "op" and toks[k].text == "{"):
            if toks[k].kind == "op" and toks[k].text in "([" and toks[k].end is not None:
                k = toks[k].end
            k += 1
        return k

    def is_view(f, it):
        if it.kind != "fn":
            return False
        b = header(f, it)
        return any(f.toks[k].kind == "ident" and f.toks[k].text == "Ctx" for k in range(it.start, min(b, it.end)))

    # the app's functions by (package, name): where they are defined (their file and definition's call)
    defs = {}
    calls_at = {}
    for f in app:
        for c in f.calls:
            calls_at[(f.rel, c.at)] = c
            if c.is_def and c.kind == "bare":
                defs[(os.path.dirname(f.rel), c.name)] = (f, c)

    def positional(f, args):
        """The positional ones of a call's arguments or a definition's parameters (not `x=`, `x~`, `x? :`)."""
        return [a for lab, a in args if lab is None and a and not (len(a) > 1 and f.toks[a[1]].text == "?")]

    handlers, asking = {}, set()

    def handler_param(key, i):
        """Whether function key calls its i-th positional parameter only as an input is taken (a button's answer:
        dv_empty(c, …, fn() { … }) whose `on_tap()` is under its `clicked`)."""
        if (key, i) in handlers:
            return handlers[(key, i)]
        if key not in defs or (key, i) in asking:
            return False
        df, dc = defs[key]
        params = positional(df, dc.args)
        if i >= len(params) or df.toks[params[i][0]].kind != "ident":
            return False
        name = df.toks[params[i][0]].text
        asking.add((key, i))
        sites = [c.at for c in df.calls if c.item is dc.item and c.kind == "bare" and not c.is_def and c.name == name]
        got = bool(sites) and all(exempt(df, k) for k in sites)
        asking.discard((key, i))
        handlers[(key, i)] = got
        return got

    def later(f, o):
        """Whether the closure whose body opens at o runs later than the build (a callback: what an effect is answered
        with, an event's handler, a fiber's body), not as it builds (a box's children: c.box(fn() { … }))."""
        toks = f.toks
        # the call it is an argument of, and its label
        lab = None
        b = o - 1
        while b >= 0 and not (toks[b].kind == "op" and toks[b].text in ("(", ",")):
            if toks[b].kind == "op" and toks[b].text in ")]}":
                ob = f._open_of(b)
                b = (ob if ob is not None else b) - 1
                continue
            if toks[b].kind == "op" and toks[b].text in ("=", "~") and b > 0 and toks[b - 1].kind == "ident":
                lab = toks[b - 1].text
            b -= 1
        if lab is not None and (lab.startswith("on_") or lab in LATER_LABELS):
            return True
        # not given to a call (a field's value, a let's): what it is called by is not the build
        if b < 0 or toks[b].text not in ("(", ","):
            return True
        # back to the call's opening bracket
        p = b
        while p >= 0:
            t = toks[p]
            if t.kind == "op" and t.text == "(" and t.end is not None and t.end > o:
                break
            if t.kind == "op" and t.text in "[{" and t.end is not None and t.end > o:
                return True  # in an array or a struct: a value, not run as it builds
            p -= 1
        if p < 1:
            return False
        callee = toks[p - 1]
        # (src.call)(…, fn(res) { … }): an effect's answer
        if callee.kind == "op" and callee.text == ")" and p >= 4 and toks[p - 2].kind == "ident" and \
                toks[p - 2].text in cfg.effect_fields:
            return True
        if callee.kind == "ident" and callee.text in LATER_CALLS:
            return True
        # given to an app's function that calls it only under an input (a button's own callback)
        call = calls_at.get((f.rel, p - 1))
        if call is not None and call.kind == "bare":
            for i, a in enumerate(positional(f, call.args)):
                if a[0] <= o <= a[-1]:
                    return handler_param((os.path.dirname(f.rel), call.name), i)
        return False

    def built_by_ctx(f, o):
        """Whether the closure at o (its `fn`) is given to one of the Ctx's own (c.list(…, fn(i) { … }): its rows,
        built as the frame builds)."""
        toks = f.toks
        p = o - 1
        while p >= 0:
            t = toks[p]
            if t.kind == "op" and t.text == "(" and t.end is not None and t.end > o:
                break
            p -= 1
        return p >= 3 and toks[p - 1].kind == "ident" and toks[p - 2].text == "." and toks[p - 3].kind == "ident" and \
            toks[p - 3].text == "c"

    shapes = {}

    def item_shapes(f, it):
        """In function it: the lets that hold what a widget took (`let k = segmented(c, …)`, `let typed =
        c.code_field(…)`, and the lets worked out from them), and the fields a press sets (`p.scrub = …` under a
        `pressed`): a condition comparing the one (`!=`, `is`) or testing the other once let go is an input's."""
        key = (f.rel, it.start)
        if key in shapes:
            return shapes[key]
        toks, values, pressed_fields = f.toks, set(), set()
        for k in range(it.start, it.end - 2):
            t = toks[k]
            if t.kind == "ident" and t.text == "let" and toks[k + 1].kind == "ident" and toks[k + 2].text == "=":
                # the let's expression: to the end of its line, its brackets whole
                e, j = [], k + 3
                while j <= it.end and toks[j].line == toks[k].line:
                    if toks[j].kind == "op" and toks[j].text in "([{" and toks[j].end is not None:
                        e.extend(range(j, toks[j].end + 1))
                        j = toks[j].end + 1
                        continue
                    e.append(j)
                    j += 1
                took = False
                for i in e[:5]:
                    ti = toks[i]
                    if ti.kind == "ident" and i + 1 < len(toks) and toks[i + 1].text == "(":
                        # a widget whose answer is what it took (segmented(c, …), c.code_field(…))
                        took = ti.text in INPUT_VALUE_CALLS
                        break
                if took or any(toks[i].kind == "ident" and toks[i].text in values for i in e):
                    values.add(toks[k + 1].text)
            if t.kind == "op" and t.text == "." and toks[k + 1].kind == "ident" and toks[k + 2].kind == "op" and \
                    toks[k + 2].text == "=":
                if any(any(toks[i].kind == "ident" and toks[i].text == "pressed" for i in cond)
                       for cond in f.enclosing_conditions(k)):
                    pressed_fields.add(toks[k + 1].text)
        shapes[key] = (values, pressed_fields)
        return shapes[key]

    def exempt(f, k):
        toks = f.toks
        for o in range(k - 1, -1, -1):
            t = toks[o]
            if t.kind != "op" or t.text not in "({" or t.end is None or t.end < k:
                continue
            if t.text == "(" and o > 0 and toks[o - 1].kind == "ident" and toks[o - 1].text in ("after_build", "tell"):
                return True
            if t.text == "{":
                # a callback's body: fn(…) { … } or fn(…) -> T { … }
                j = o - 1
                if j >= 0 and toks[j].kind == "ident" and j > 0 and toks[j - 1].text == "->":
                    j -= 2
                    while j >= 0 and toks[j].kind == "op" and toks[j].text in (">", "]"):
                        j -= 1
                if j >= 0 and toks[j].kind == "op" and toks[j].text == ")":
                    ob = f._open_of(j)
                    if ob is not None and ob > 0 and toks[ob - 1].kind == "ident" and toks[ob - 1].text == "fn":
                        # given what happened (fn(d) { … }: a stepper's change, an answer): a handler; fn() { … }: a
                        # box's children, the build, unless what it is given to runs it later
                        if (ob > 1 and toks[ob - 2].text == "async") or later(f, ob - 1):
                            return True
                        if j > ob + 1 and not built_by_ctx(f, ob - 1):
                            return True
        it = f.item_of[k]
        values, pressed_fields = item_shapes(f, it) if it is not None else (set(), set())
        for cond in f.enclosing_conditions(k):
            if any(toks[i].kind == "ident" and toks[i].text in INPUT_WORDS for i in cond):
                return True
            names = {toks[i].text for i in cond if toks[i].kind == "ident"}
            # what a widget took, compared: its choice other than what is kept, a code typed in
            if names & values and ("is" in names or any(toks[i].text == "!=" for i in cond)):
                return True
            # what a press left, acted on once it is let go (a timeline's seek to where it was dragged)
            if "pressed" not in names and any(toks[i].text == "." and i + 1 < len(toks) and
                                              toks[i + 1].text in pressed_fields for i in cond):
                return True
            # a widget asked whether it was used (button(c, …), row(c, …): given the Ctx first), not a time or a
            # layout read (after(c, …), held(c, …))
            for i in cond:
                t = toks[i]
                if t.kind == "ident" and i + 2 < len(toks) and toks[i + 1].text == "(" and \
                        toks[i + 2].kind == "ident" and toks[i + 2].text == "c" and i + 3 < len(toks) and \
                        toks[i + 3].text in (",", ")") and t.text not in NOT_INPUT_CALLS:
                    return True
        return False

    def sites(f, it, helpers):
        """The effects in item it not exempt: (token index, what)."""
        toks, got = f.toks, []
        for k in range(it.start, it.end + 1):
            t = toks[k]
            # (x.call)(…)
            if t.kind == "ident" and t.text in cfg.effect_fields and k >= 3 and toks[k - 1].text == "." and \
                    toks[k - 3].kind == "op" and toks[k - 3].text == "(" and k + 2 < len(toks) and \
                    toks[k + 1].text == ")" and toks[k + 2].text == "(":
                if not exempt(f, k):
                    got.append((k, f"({toks[k - 2].text}.{t.text})"))
        for c in f.calls:
            if c.is_def or c.at < it.start or c.at > it.end:
                continue
            name = None
            if c.kind == "pkg" and f"{c.qual}.{c.name}" in cfg.effect_calls:
                name = f"{c.qual}.{c.name}"
            elif c.kind == "bare" and (os.path.dirname(f.rel), c.name) in helpers:
                name = c.name
            elif c.kind == "method" and c.name in cfg.effect_methods and c.at >= 2 and \
                    not (f.toks[c.at - 2].kind == "ident" and f.toks[c.at - 2].text == "c"):
                name = "." + c.name
            if name and not exempt(f, c.at):
                got.append((c.at, name))
        return got

    fns = [(f, it) for f in app for it in f.items if it.kind == "fn" and it.name]
    # what is done only on an input, an answer, after the build: a function every call of which is (an action: a
    # send, a pick's ask), its effects are the input's
    callers = {}
    for f in app:
        pkg = os.path.dirname(f.rel)
        for c in f.calls:
            if c.kind == "bare" and not c.is_def and c.item is not None and c.item.kind == "fn":
                callers.setdefault((pkg, c.name), []).append((f, c.item, c.at))
    actions = set()
    while True:
        grew = False
        for f, it in fns:
            key = (os.path.dirname(f.rel), it.name)
            if key in actions or key not in callers:
                continue
            if all(exempt(cf, k) or (os.path.dirname(cf.rel), ci.name) in actions for cf, ci, k in callers[key]):
                actions.add(key)
                grew = True
        if not grew:
            break
    views = {(f.rel, it.start) for f, it in fns if is_view(f, it) and (os.path.dirname(f.rel), it.name) not in actions}
    helpers = set()
    while True:
        # (a bare call is to its package's own function: by its directory and name)
        more = {(os.path.dirname(f.rel), it.name) for f, it in fns if (f.rel, it.start) not in views and
                "::" not in it.name and (os.path.dirname(f.rel), it.name) not in actions and sites(f, it, helpers)}
        if more <= helpers:
            break
        helpers |= more
    for f, it in fns:
        if (f.rel, it.start) not in views:
            continue
        for k, what in sites(f, it, helpers):
            out.append(Finding("build-effect", f.rel, f.toks[k].line, f"{f.lines[f.toks[k].line - 1].strip()}   "
                                                                     f"({what}, in {it.name})"))


def tally(findings, excused):
    counts = {r: {} for r in RULES}
    for fd in findings:
        if (fd.excused is not None) == excused:
            counts[fd.rule][fd.file] = counts[fd.rule].get(fd.file, 0) + 1
    return counts


def total(per_file):
    return sum(per_file.values())


# the rules where an exception may take the place of a finding there was (docs/detlint.md: a time shown is right);
# elsewhere an exception's count only goes down, apart from the findings'
SWAPPABLE = {"app-clock"}


def over(cur, bar, rule):
    """The files (of one rule) above their bar: (file, found, its bar, found and excused, their bar)."""
    out = []
    for p in sorted(set(cur["found"]) | set(cur["excused"])):
        f, e = cur["found"].get(p, 0), cur["excused"].get(p, 0)
        bf, be = bar["found"].get(p, 0), bar["excused"].get(p, 0)
        if f > bf or (f + e > bf + be if rule in SWAPPABLE else e > be):
            out.append((p, f, bf, f + e, bf + be))
    return out


def under_bar(cur, bar):
    """The files (of one rule) below their bar: found fewer, or found and excused fewer."""
    out = []
    for p in sorted(set(bar["found"]) | set(bar["excused"])):
        f, e = cur["found"].get(p, 0), cur["excused"].get(p, 0)
        bf, be = bar["found"].get(p, 0), bar["excused"].get(p, 0)
        if f < bf or f + e < bf + be:
            out.append(p)
    return out


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = [a for a in argv if a.startswith("--")]
    root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    conf_path = os.path.join(root, "detlint.json")
    if not os.path.exists(conf_path):
        print(f"detlint: no {conf_path}", file=sys.stderr)
        return 2
    conf = json.loads(read(conf_path))
    cfg = Config(conf)
    findings = collect(root, cfg)
    if "--list" in flags:
        want = args[1] if len(args) > 1 else None
        for fd in sorted(findings, key=lambda x: (x.rule, x.file, x.line)):
            if want is None or fd.rule == want:
                ex = f"   [det-ok: {fd.excused}]" if fd.excused else ""
                print(f"{fd.rule}\t{fd.file}:{fd.line}\t{fd.what}{ex}")
        return 0
    found, excused = tally(findings, False), tally(findings, True)
    have = {r: {"found": found[r], "excused": excused[r]} for r in RULES}
    bars = {r: {"found": conf.get("counts", {}).get(r), "excused": conf.get("excused", {}).get(r)} for r in RULES}
    update = next((a for a in flags if a.startswith("--update")), None)
    if update:
        counts, exc = {}, {}
        for r in RULES:
            cur, bar = have[r], bars[r]
            nf, ne = dict(cur["found"]), dict(cur["excused"])
            if bar["found"] is not None and update != "--update=raise":
                bar = {"found": bar["found"], "excused": bar["excused"] or {}}
                for p, f, bf, fe, bfe in over(cur, bar, r):
                    print(f"detlint: {r} in {p} is above its bar ({f} found, {fe} with det-ok; the bar {bf}, {bfe}): "
                          f"kept (--update=raise to raise it, and say why)", file=sys.stderr)
                    nf[p], ne[p] = bar["found"].get(p, 0), bar["excused"].get(p, 0)
            counts[r] = {p: n for p, n in sorted(nf.items()) if n}
            exc[r] = {p: n for p, n in sorted(ne.items()) if n}
        conf["counts"], conf["excused"] = counts, exc
        with open(conf_path, "w", encoding="utf-8") as fh:
            json.dump(conf, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("detlint: bars written: " + ", ".join(
            f"{r} {total(counts[r])}" + (f" (+{total(exc[r])} det-ok)" if exc[r] else "") for r in RULES))
        return 0
    bad = False
    print(f"detlint ({os.path.basename(root)}): rule, found / bar, "
          f"det-ok / bar (each file against its own)")
    for r in RULES:
        cur, bar = have[r], bars[r]
        notes = []
        line = f"  {r:14} {total(cur['found']):5} / "
        if bar["found"] is None:
            bad = True
            line += "-"
            notes.append(f"    {r}: no bar in detlint.json (scripts/detlint.py --update)")
        else:
            bar = {"found": bar["found"], "excused": bar["excused"] or {}}
            line += f"{total(bar['found']):<5} {total(cur['excused']):4} / {total(bar['excused']):<4}"
            if total(bar["found"]) == 0 and total(bar["excused"]) == 0:
                line += "  forbidden"
            for p, f, bf, fe, bfe in over(cur, bar, r):
                bad = True
                if f > bf:
                    notes.append(f"    {r}: {p}: {f} > {bf}: {RULES[r]}")
                else:
                    notes.append(f"    {r}: {p}: {fe - f} det-ok, the bar {bfe - bf}: " + (
                        "an exception may only take the place of a finding there was" if r in SWAPPABLE else
                        "this rule's exceptions only go down (a finding marked det-ok is still a finding)"))
                for fd in findings:
                    if fd.rule == r and fd.file == p:
                        notes.append(f"        {p}:{fd.line}  {fd.what}" + (
                            f"   [det-ok: {fd.excused}]" if fd.excused is not None else ""))
                if f > bf:
                    notes.append(f"      an exception says why on its line (`det-ok({r}): <why>`), in place of a "
                                 f"finding there was")
            lower = under_bar(cur, bar)
            if lower:
                bad = True
                notes.append(f"    {r}: fewer than the bar in {', '.join(lower)}: lower it to what is now "
                             f"(scripts/detlint.py --update), so it stays there")
        print(line)
        for fd in findings:
            if fd.rule == r and fd.excused is not None:
                print(f"      det-ok {fd.file}:{fd.line}: {fd.excused}")
        for x in notes:
            print(x)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
