#!/usr/bin/env python3
"""Tests of scripts/detlint.py: each rule stops what it is for (a made-up file it fails on) and lets its right way by
(one it passes); exceptions, and the bar.

    python3 scripts/detlint_test.py
"""
import json
import os
import shutil
import sys
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import detlint  # noqa: E402

CONF = {
    "mbt": {"roots": ["src"], "framework": ["src/ui", "src/host"], "clock_sources": ["src/host"],
            "frame_core": ["src/ui/app.mbt", "src/host"]},
    "globals": {"roots": ["src/app"]},
    "flows": ["flows/*.drive"],
    "scripts": ["scripts/*.sh", "scripts/*.mjs"],
    "counts": {},
}


class Tree:
    """A module of made-up files in a temporary directory."""

    def __init__(self, files, conf=None):
        self.root = tempfile.mkdtemp(prefix="detlint-")
        for rel, text in files.items():
            p = os.path.join(self.root, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(textwrap.dedent(text))
        self.conf = dict(conf or CONF)
        self.write_conf()

    def write_conf(self):
        with open(os.path.join(self.root, "detlint.json"), "w", encoding="utf-8") as fh:
            json.dump(self.conf, fh)

    def findings(self, rule=None):
        fs = detlint.collect(self.root, detlint.Config(self.conf))
        return [f for f in fs if (rule is None or f.rule == rule) and f.excused is None]

    def excused(self):
        return [f for f in detlint.collect(self.root, detlint.Config(self.conf)) if f.excused is not None]

    def close(self):
        shutil.rmtree(self.root)


def found(test, files, rule, n):
    t = Tree(files)
    try:
        got = t.findings(rule)
        test.assertEqual(len(got), n, "\n".join(f"{f.file}:{f.line} {f.what}" for f in got))
        return got
    finally:
        t.close()


class Rules(unittest.TestCase):
    def test_style(self):
        conf = dict(CONF, style={"tokens": ["src/app/tokens.mbt"]})
        files = {
            "src/app/view.mbt": """
                let card : @ui.Style = @ui.style(px=S4, radius=Exact(22.0), gap=Fixed(14.0))
                fn view(c : @ui.Ctx) -> Unit {
                  c.box(style=card, pad=12.0, fn() {
                    c.text("a", size=13.0, color=0x24272BFFL) |> ignore
                    c.text("b", style=title) |> ignore
                  }) |> ignore
                  c.box(style=card, id=7, aspect=1.5, fn() {  }) |> ignore
                  c.text("c", style=title, max_lines=2, tracking=0.5) |> ignore
                }
                let clamp : @ui.TextStyle = @ui.text_style(max_lines=2, tracking=Tight)
                """,
            "src/app/tokens.mbt": """
                pub let title : @ui.TextStyle = @ui.text_style(size=Exact(15.0, 21.0))
                pub let column_max : @ui.Len = Fixed(420.0)
                """,
            "src/app/view_test.mbt": """
                test "x" {
                  c.box(pad=3.0, fn() {  }) |> ignore
                }
                """,
        }
        t = Tree(files, conf)
        try:
            lit = t.findings("style-literal")
            # Exact(22.0) once (its number not again), Fixed's 14.0, pad 12.0, size 13.0, the colour: not the token
            # file's, nor the test's, nor aspect (not a look) nor id
            # tracking's 0.5; not max_lines (a count, not a look's value) in either
            self.assertEqual(sorted(f.line for f in lit), [2, 2, 4, 5, 5, 9], "\n".join(f.what for f in lit))
            # the calls said loosely (pad=, size=, max_lines= and tracking=); a box with a style and behaviour alone
            # (id, aspect) is not
            self.assertEqual(sorted(f.line for f in t.findings("box-loose")), [4, 5, 9])
            # every Exact made, in the token file too
            self.assertEqual(sorted((f.file, f.line) for f in t.findings("style-exact")),
                             [("src/app/tokens.mbt", 2), ("src/app/view.mbt", 2)])
        finally:
            t.close()
        # the enum's declaration and a match's patterns are not values made
        decl = {"src/ui/style_tokens.mbt": """
            pub(all) enum Space {
              S4
              Exact(Double)
            }
            fn Space::px(self : Space) -> Double {
              match self {
                S4 => 16.0
                Exact(v) => v
              }
            }
            """}
        found(self, decl, "style-exact", 0)

    def test_frame_request(self):
        bad = {"src/app/view.mbt": """
            fn view(c : @ui.Ctx) -> Unit {
              if c.pressed(1) { c.request_frame() }
              @host.request_frame()
            }
            """}
        found(self, bad, "frame-request", 2)
        # the framework's own components and motion count too: an animation is declared once, not asked each frame
        found(self, {"src/ui/list.mbt": "fn fling(c : Ctx) -> Unit {\n  if moving { c.request_frame() }\n"
                                        "  h_request_frame()\n}\n"}, "frame-request", 2)
        good = {
            # the scheduler asks (its frame loop, its dispatch); a test may; a comment or a string naming it is not
            # a call
            "src/ui/app.mbt": "fn on_key(c : Ctx) -> Unit {\n  c.request_frame()\n}\n",
            "src/app/view_test.mbt": "test \"x\" {\n  c.request_frame()\n}\n",
            "src/app/view.mbt": "// c.request_frame() was here\nfn v(c : @ui.Ctx) -> Unit {\n  c.text(\"request_frame()\")\n}\n",
        }
        found(self, good, "frame-request", 0)

    def test_engine_math(self):
        bad = {
            "src/ui/line.mbt": "fn arc(a : Double) -> Double {\n  @math.cos(a) + @math.sin(a) + @math.pow(2.0, a) + @math.exp(a)\n}\n",
            "src/app/spring.mbt": "fn decay(t : Double) -> Double {\n  2.718281828459045.pow(-t)\n}\n",
        }
        found(self, bad, "engine-math", 5)
        good = {
            "src/ui/line.mbt": "fn arc(a : Double) -> Double {\n  @dmath.cos(a) + @dmath.sin(a) + @math.floor(a) + a.sqrt()\n}\n",
        }
        found(self, good, "engine-math", 0)

    def test_frame_wait(self):
        bad = {
            "src/motion/fx.mbt": """
                async fn play(v : Value) -> Unit {
                  while v.moving() {
                    @effect.next_frame()
                  }
                }
                """,
        }
        found(self, bad, "frame-wait", 1)
        good = {
            "src/motion/fx.mbt": """
                async fn play(v : Value, end : Int) -> Unit {
                  @effect.sleep(end - @effect.now().to_int())
                }
                """,
            "src/effect/runtime.mbt": "pub async fn next_frame() -> Unit {\n  wait()\n}\nfn loop() -> Unit {\n  next_frame()\n}\n",
        }
        found(self, good, "frame-wait", 0)

    def test_at_rest_wait(self):
        bad = {
            # waited on: a loop, a condition, an until; a drive's rest step, in a test's text and in a flow
            "src/app/view_test.mbt": """
                test "saves" {
                  let t = @ui.Tester::new(fn(c) { view(c) })
                  while !t.at_rest() {
                    t.frame()
                  }
                  if t.at_rest() { t.tap(1.0, 2.0) }
                  t.drive("tap save\\nrest\\nexit") |> ignore
                }
                """,
            # a tap's target waited on until it holds still from one frame to the next
            "src/ui/drive.mbt": """
                fn drive_tap(d : Driver, x : Double, y : Double) -> Unit {
                  if !d.held_still(x, y) {
                    return
                  }
                  press(x, y)
                }
                """,
            "flows/01-save.drive": "tap save\nrest\nexit\n",
            # a picture at the app's rest
            "scripts/shots.sh": "MBUI_SHOT_MS=rest ./app\nnode web-shot.mjs out.png && open 'http://x/?shot_at=rest'\n",
            # an end run on until nothing moves: to what moves' end, again; the frame left owed drawn, a timer's
            # time, again (each loop once)
            "src/app/flow.mbt": """
                fn Flow::end(self : Flow) -> Unit {
                  while true {
                    while self.t.rest_of("") > self.t.time() {
                      self.t.run_for(self.t.rest_of("") - self.t.time())
                    }
                    self.t.draw()
                    match self.t.next_wake() {
                      Some((at, _)) => self.t.run_for(at - self.t.time())
                      None => break
                    }
                  }
                  self.t.assert_idle()
                }
                """,
        }
        found(self, bad, "at-rest-wait", 9)
        good = {
            # asserted, with what keeps it from it said; a word "rest" that is no step; a declared moment
            "src/app/view_test.mbt": """
                test "saves" {
                  let t = @ui.Tester::new(fn(c) { view(c) })
                  t.run_for(@kit.dialog_in)
                  assert_true(t.at_rest(), msg=t.rest_why())
                  assert_false(t.at_rest())
                  t.drive("tap rest of the list\\nexit") |> ignore
                }
                """,
            "flows/01-save.drive": "tap the rest\nuntil saved\nexit\n",
            "scripts/shots.sh": "MBUI_SHOT_MS=1000 ./app\n",
            # the frame core's own reading of it as a frame ends
            "src/ui/app.mbt": "fn on_frame(c : Ctx) -> Unit {\n  c.frame_rest = c.at_rest()\n}\n",
            # one declared end run to; what moves read where nothing runs the clock; an end a declared time
            "src/app/flow.mbt": """
                fn Flow::end(self : Flow) -> Unit {
                  self.t.run_to(@ui.nav_rest())
                  for m in self.t.moving() {
                    self.said.push(m)
                  }
                  self.t.run_for(@kit.toast_ms)
                  self.t.assert_idle()
                }
                """,
        }
        found(self, good, "at-rest-wait", 0)

    def test_settle(self):
        bad = {
            "src/app/view_test.mbt": """
                test "opens" {
                  let t = @ui.Tester::new(fn(c) { view(c) })
                  t.tap(1.0, 2.0)
                  t.settle() |> ignore
                  assert_true(t.settled())
                }
                """,
            "src/ui/tester.mbt": """
                pub fn Tester::tap(self : Tester, x : Double, y : Double) -> Unit {
                  self.touch(0, x, y)
                  self.settle() |> ignore
                }
                """,
        }
        found(self, bad, "settle", 3)
        good = {
            "src/app/view_test.mbt": """
                test "opens" {
                  let t = @ui.Tester::new(fn(c) { view(c) })
                  t.tap(1.0, 2.0)
                  t.run_for(@kit.dialog_in)
                  t.assert_idle()
                }
                """,
            # settle's own definition, and another type's settle (a Nav's: its pages put in place)
            "src/ui/tester.mbt": """
                pub fn Tester::settle(self : Tester) -> Int {
                  while !self.settled() { self.frame() }
                  0
                }
                """,
            "src/ui/nav.mbt": """
                fn[P] Nav::push(self : Nav[P], page : P) -> Unit {
                  self.settle()
                }
                """,
        }
        found(self, good, "settle", 0)

    def test_flow_wait(self):
        found(self, {"flows/01.drive": "tap 发消息\nwait 1500\nlinger 20000\n"}, "flow-wait", 2)
        found(self, {"flows/01.drive": "# wait 1500 was here\ntap 发消息\nuntil 收到\ntimeout 60000\nhold 700 引用\n"},
              "flow-wait", 0)

    def test_unsettled_ok(self):
        found(self, {"src/app/view_test.mbt": "test \"x\" {\n  t.settle(unsettled_ok=true) |> ignore\n  f.end(unsettled_ok=\"a spinner\")\n}\n"},
              "unsettled-ok", 2)
        found(self, {"src/ui/tester.mbt": "pub fn Tester::settle(self : Tester, unsettled_ok? : Bool = false) -> Int {\n  0\n}\n"},
              "unsettled-ok", 0)

    def test_script_wait(self):
        bad = {
            "scripts/shots.sh": "MBUI_SCRIPT=shot MBUI_SHOT_AT=60 ./app\nsleep 3\n",
            "scripts/web.mjs": "await page.waitForTimeout(Number(process.env.WAIT || 800));\n"
                               "await new Promise((r) => setTimeout(r, 500));\n"
        }
        found(self, bad, "script-wait", 4)
        good = {
            "scripts/shots.sh": "# sleep 3 was here\nMBUI_SCRIPT=shot ./app\nwait $pid\n",
            "scripts/web.mjs": "await page.waitForFunction(() => window.__mb !== undefined);\n",
        }
        found(self, good, "script-wait", 0)

    def test_page_settle(self):
        bad = {"scripts/web.mjs": "await page.waitForFunction(() => __mbhost.settled(), null, { timeout: 30000 });\n"
                                  "console.log(await page.evaluate(() => __mbhost.unsettled()));\n"}
        found(self, bad, "page-settle", 2)
        good = {"scripts/web.mjs": "// __mbhost.settled() was here\nawait page.evaluate(() => __mbhost.run_for(t));\n"}
        found(self, good, "page-settle", 0)

    def test_frame_count(self):
        bad = {"src/app/view_test.mbt": "test \"x\" {\n  for _ in 0..<60 {\n    t.frame()\n  }\n}\n"}
        found(self, bad, "frame-count", 1)
        good = {"src/app/view_test.mbt": "test \"x\" {\n  for i in 0..<rows.length() {\n    t.frame()\n  }\n"
                                         "  for _ in 0..<3 {\n    t.tap(1.0, 1.0)\n  }\n}\n"}
        found(self, good, "frame-count", 0)

    def test_literal_time(self):
        bad = {
            "src/app/view_test.mbt": "test \"x\" {\n  t.run_for(347.0)\n  t.frame(ms=1000.0)\n  t.advance(16.0)\n}\n",
            "src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.wake_in(50.0)\n  c.wake_at(c.now() + 500.0)\n}\n",
        }
        found(self, bad, "literal-time", 5)
        good = {
            "src/app/view_test.mbt": "test \"x\" {\n  t.run_for(@kit.toast_life)\n  t.frame()\n  t.frame(ms=0.0)\n}\n",
            "src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.wake_in(hold_ms)\n  c.wake_at(at + toast_life)\n}\n",
        }
        found(self, good, "literal-time", 0)

    def test_stable_mode(self):
        found(self, {"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let p = if c.stable() { 1.0 } else { 0.5 }\n}\n"},
              "stable-mode", 1)
        # the framework's own code too: a screenshot's run draws and moves as any run
        found(self, {"src/ui/draw.mbt": "pub fn Ctx::still(self : Ctx) -> Bool {\n  self.stable()\n}\n"},
              "stable-mode", 1)
        # reduced motion is the person's: not stable-mode
        found(self, {"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let p = if c.still() { 1.0 } else { 0.5 }\n}\n"},
              "stable-mode", 0)

    def test_app_clock(self):
        bad = {"src/app/view.mbt": """
            fn v(c : @ui.Ctx) -> Unit {
              let p = (c.now() - at) / 180.0
              let t = @ui.now()
            }
            """}
        found(self, bad, "app-clock", 2)
        good = {
            "src/ui/ctx.mbt": "fn Ctx::frame_time(self : Ctx) -> Double {\n  self.now()\n}\n",
            "src/app/view_test.mbt": "test \"x\" {\n  let t0 = c.now()\n}\n",
            "src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let p = @motion.anim(c, \"open\", sheet_in)\n}\n",
        }
        found(self, good, "app-clock", 0)

    def test_wall_clock(self):
        bad = {
            "src/app/js.mbt": "extern \"js\" fn ms() -> Double =\n  #|() => Date.now()\n",
            "src/app/r.mbt": "fn r() -> Int {\n  let g = @random.Rand::new()\n  g.int()\n}\n",
            "src/app/w.mbt": "fn w() -> Double {\n  @core.wall_ms()\n}\n",
        }
        found(self, bad, "wall-clock", 3)
        good = {
            "src/host/host_js.mbt": "extern \"js\" fn now() -> Double =\n  #|() => performance.now()\n",
            "src/app/r.mbt": "fn r(seed : Int) -> Int {\n  let g = @random.Rand::new(seed~)\n  g.int()\n}\n",
        }
        found(self, good, "wall-clock", 0)

    def test_wall_clock_random_ids(self):
        bad = {
            "src/app/name.mbt": "fn name() -> String {\n  \"pasted-text-\" + uuid() + \".txt\"\n}\n",
            "src/app/id.mbt": "fn id() -> String {\n  @util.random_id()\n}\n",
            "src/app/js.mbt": "extern \"js\" fn u() -> String =\n  #|() => crypto.randomUUID()\n",
            "src/app/c.mbt": "extern \"c\" fn r() -> Int =\n  #|int r(void) { return rand(); }\n",
        }
        found(self, bad, "wall-clock", 4)
        good = {
            # shaping a hash it is given: the same each run
            "src/app/name.mbt": "fn name(h : String) -> String {\n  \"pasted-text-\" + uuid(h) + \".txt\"\n}\n",
            # a test may make one
            "src/app/id_test.mbt": "test \"x\" {\n  let id = random_id()\n}\n",
            # the host that provides randomness
            "src/host/host_js.mbt": "extern \"js\" fn u() -> String =\n  #|() => crypto.randomUUID()\n",
            # words that only look alike
            "src/app/w.mbt": "fn w() -> String {\n  let operand = 1\n  \"brand(new)\"\n}\n",
        }
        found(self, good, "wall-clock", 0)

    def test_poll(self):
        bad = {"src/app/view.mbt": """
            fn ready() -> Bool {
              @host.update_state() != ""
            }

            fn v(c : @ui.Ctx, j : Job) -> Unit {
              match j.made() {
                Some(img) => c.image(img)
                None => c.wake_in(poll_ms)
              }
              if c.list_row_height(l, 3) is None {
                c.request_frame()
              }
              if ready() {
                c.request_frame()
              }
              if c.pressed(stage) {
                c.request_frame()
              }
            }
            """}
        found(self, bad, "poll", 4)
        good = {"src/app/view.mbt": """
            fn v(c : @ui.Ctx) -> Unit {
              if c.pressed(stage) {
                c.wake_in(hold_ms - held)
              }
              if open {
                c.wake_at(at + toast_life)
              }
            }
            """}
        found(self, good, "poll", 0)

    def test_host_read(self):
        bad = {"src/app/view.mbt": "fn v() -> Unit {\n  let p = @host.platform()\n  let d = @host.system_dark()\n}\n"}
        found(self, bad, "host-read", 2)
        good = {
            "src/app/view.mbt": "fn v() -> Unit {\n  let p = @ui.platform()\n  @host.open_url(u)\n}\n",
            "src/ui/hostread.mbt": "pub fn platform() -> Int {\n  @host.platform()\n}\n",
        }
        found(self, good, "host-read", 0)

    def test_globals(self):
        bad = {"src/app/state.mbt": """
            ///|
            let open : Ref[Bool] = { val: false }

            ///|
            let seen : Map[String, Int] = {}

            ///|
            fn reset() -> Unit {
              open.val = false
            }
            """}
        got = found(self, bad, "globals", 1)
        self.assertIn("seen", got[0].what)
        good = {
            "src/app/state.mbt": """
                ///|
                let open : Ref[Bool] = { val: false }

                ///|
                // kept across runs: a table of constants, never written
                let names : Map[String, Int] = { "a": 1 }

                ///|
                let limit : Int = 3

                ///|
                let seen : Map[String, Int] = {}

                ///|
                fn reset() -> Unit {
                  open.val = false
                  forget()
                }

                ///|
                fn forget() -> Unit {
                  seen.clear()
                }
                """,
            "src/app/more.mbt": """
                ///|
                let later : Array[Int] = []

                ///|
                fn init {
                  @ui.on_reset(fn() { later.clear() })
                }
                """,
        }
        found(self, good, "globals", 0)


class BuildEffect(unittest.TestCase):
    def test_build_effect(self):
        files = {
            "src/app/view.mbt": """
                fn keep(src : Source, n : Int) -> Unit {
                  (src.call)("keep", Json::number(n.to_double()), fn(_) {  })
                }
                fn send(src : Source) -> Unit {
                  (src.call)("send", Json::null(), fn(_) {  })
                }
                fn view(c : @ui.Ctx, src : Source, n : @ui.NativeView) -> Unit {
                  (src.call)("seen", Json::null(), fn(_) {  })
                  keep(src, 1)
                  n.reload()
                  @host.set_dark(true)
                  c.after_build("seen", fn() { (src.call)("seen", Json::null(), fn(_) {  }); n.seek(1.0) })
                  if c.clicked(7) {
                    send(src)
                    n.play()
                  }
                  if button(c, "go") {
                    keep(src, 2)
                  }
                  c.take_back(fn() { n.close() })
                  c.box(fn() { keep(src, 3) }) |> ignore
                  c.box(on_tap=fn() { keep(src, 4) }, fn() {  }) |> ignore
                  (src.call)("ask", Json::null(), fn(r) { keep(src, 5) })
                  c.close()
                }
                """,
        }
        got = sorted(found(self, files, "build-effect", 6), key=lambda f: f.line)
        # the core's calls (the ask itself, not its answer), a helper doing one, the native view's reload, the host's
        # effect, and the box's children's (built as the frame builds): not what after_build, an input, a handler or
        # an answer does, nor the Ctx's own
        self.assertEqual([f.line for f in got], [9, 10, 11, 12, 22, 24], "\n".join(f.what for f in got))
        self.assertIn(".reload", got[2].what)


    def test_build_effect_inputs_it_knows_by_shape(self):
        files = {
            "src/app/view.mbt": """
                fn empty(c : @ui.Ctx, words : String, on_tap : () -> Unit) -> Unit {
                  if c.clicked(3) {
                    on_tap()
                  }
                }
                fn shown(c : @ui.Ctx, body : () -> Unit) -> Unit {
                  body()
                }
                fn view(c : @ui.Ctx, src : Source, p : Player, prefs : Prefs) -> Unit {
                  let k = @sf.segmented(c, "face", ["a", "b"], 0)
                  let want = if k == 0 { "a" } else { "b" }
                  if want != prefs.face {
                    (src.call)("face", Json::null(), fn(_) {  })
                  }
                  if k == 0 {
                    (src.call)("every", Json::null(), fn(_) {  })
                  }
                  let typed = c.code_field(4)
                  if typed is Some(code) {
                    (src.call)("code", Json::null(), fn(_) {  })
                  }
                  empty(c, "none", fn() { (src.call)("up", Json::null(), fn(_) {  }) })
                  shown(c, fn() { (src.call)("built", Json::null(), fn(_) {  }) })
                  match c.rect_of(5) {
                    Some((x, _, _, _)) if c.pressed(5) => p.scrub = x
                    _ =>
                      if p.scrub >= 0.0 {
                        p.seek(p.scrub)
                        p.scrub = -1.0
                      }
                  }
                  if p.ready {
                    p.seek(0.0)
                  }
                }
                """,
        }
        got = sorted(found(self, files, "build-effect", 3), key=lambda f: f.line)
        # a choice other than what is kept, a code typed in, a button's callback, a press let go: the input's; a
        # choice as it stands each frame, a closure built as it is given, a seek on what is not the finger's: not
        self.assertEqual([f.line for f in got], [17, 24, 34], "\n".join(f.what for f in got))

    def test_build_effect_a_streams_callbacks_are_its_events(self):
        files = {
            "src/app/view.mbt": """
                fn view(c : @ui.Ctx, src : Source, s : Ref[@ui.Stream?]) -> Unit {
                  if s.val is None {
                    s.val = Some(@ui.Stream::new(
                      shown=fn(ts) { (src.call)("screen.ack", Json::null(), fn(_) {  }) },
                      broken=fn() { (src.call)("screen.keyframe", Json::null(), fn(_) {  }) },
                    ))
                  }
                  c.box(fn() { (src.call)("screen.view", Json::null(), fn(_) {  }) }) |> ignore
                }
                """,
        }
        got = found(self, files, "build-effect", 1)
        # what a stream says shown or broken is told as its event comes, not as the frame builds; a box's children are
        self.assertEqual([f.line for f in got], [9], "\n".join(f.what for f in got))


class Exceptions(unittest.TestCase):
    def test_reason_on_the_line_or_over_it(self):
        t = Tree({"src/app/view.mbt": """
            fn v(c : @ui.Ctx) -> Unit {
              c.request_frame() // det-ok(frame-request): the bench draws every frame on purpose
              // det-ok(frame-request): the same, on the line over it
              c.request_frame()
              c.request_frame() // det-ok(frame-request)
            }
            """})
        try:
            self.assertEqual(len(t.excused()), 2)
            left = t.findings("frame-request")
            self.assertEqual(len(left), 1, "an exception without its reason is not taken")
        finally:
            t.close()

    def test_exceptions_have_a_bar_of_their_own(self):
        t = Tree({"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(frame-request): a\n}\n"})
        try:
            self.assertEqual(Bar.run_main(None, t, "--update")[0], 0)
            self.assertEqual(Bar.run_main(None, t)[0], 0)
            with open(os.path.join(t.root, "src/app/view.mbt"), "a", encoding="utf-8") as fh:
                fh.write("fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(frame-request): b\n}\n")
            code, out = Bar.run_main(None, t)
            self.assertEqual(code, 1, out)
            self.assertIn("exceptions only go down", out)
        finally:
            t.close()

    def test_an_exception_in_place_of_a_finding_is_taken_and_lowers_the_bar(self):
        t = Tree({"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let ago = c.now() - sent\n}\n"})
        try:
            Bar.run_main(None, t, "--update")
            with open(os.path.join(t.root, "src/app/view.mbt"), "w", encoding="utf-8") as fh:
                fh.write("fn v(c : @ui.Ctx) -> Unit {\n  let ago = c.now() - sent // det-ok(app-clock): shown as ago\n}\n")
            code, out = Bar.run_main(None, t)
            self.assertEqual(code, 1, out)
            self.assertIn("lower it", out)
            self.assertEqual(Bar.run_main(None, t, "--update")[0], 0)
            code, out = Bar.run_main(None, t)
            self.assertEqual(code, 0, out)
        finally:
            t.close()

    def test_marking_a_finding_is_not_a_way_out_but_for_app_clock(self):
        t = Tree({"flows/01.drive": "tap 发消息\nwait 800\n"})
        try:
            Bar.run_main(None, t, "--update")
            with open(os.path.join(t.root, "flows/01.drive"), "w", encoding="utf-8") as fh:
                fh.write("tap 发消息\n# det-ok(flow-wait): the list's animation\nwait 800\n")
            code, out = Bar.run_main(None, t)
            self.assertEqual(code, 1, out)
            self.assertIn("exceptions only go down", out)
            Bar.run_main(None, t, "--update")
            self.assertEqual(Bar.run_main(None, t)[0], 1, "--update does not take it either")
        finally:
            t.close()

    def test_another_rules_exception_does_not_excuse(self):
        t = Tree({"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(poll): why\n}\n"})
        try:
            self.assertEqual(len(t.findings("frame-request")), 1)
        finally:
            t.close()


class Retired(unittest.TestCase):
    def test_given_up_interfaces_are_forbidden(self):
        bad = {"src/ui/anim.mbt": "pub fn Ctx::frames_until(self : Ctx, t : Double) -> Unit {\n  ()\n}\n",
               "src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.animating_until(at + d)\n"
                                   "  if c.animating() { () }\n  @ui.run_animations(c)\n}\n"}
        found(self, bad, "retired-api", 4)
        # motion_end: the framework's own, not a test's nor the app's
        found(self, {"src/app/view_test.mbt": "test \"x\" {\n  t.run_for(t.motion_end() - t.time())\n}\n",
                     "src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let e = c.motion_end()\n}\n"},
              "retired-api", 2)
        found(self, {"src/ui/motion.mbt": "pub fn Ctx::motion_end(self : Ctx) -> Double {\n  self.ends.max()\n}\n",
                     "src/ui/motion_test.mbt": "test \"its end\" {\n  assert_eq(t.motion_end(), 180.0)\n}\n"},
              "retired-api", 0)
        good = {"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  let animating = true\n"
                                    "  c.text(\"frames_until\")\n}\n"}
        found(self, good, "retired-api", 0)


    def test_builtin_hash_taken_out_as_a_value(self):
        bad = {"src/app/upload.mbt": "fn upload_id(name : String) -> Int {\n  name.hash() + Hash::hash(name)\n}\n"
                                     "impl Hash for Seed with hash_combine(self, h) {\n  ()\n}\n"}
        found(self, bad, "builtin-hash", 3)
        # the stable one; a Map's keys; a test comparing two
        good = {"src/app/upload.mbt": "fn upload_id(name : String) -> Int64 {\n  @ui.stable_hash(name)\n}\n"
                                      "fn kept(m : Map[String, Int], k : String) -> Int? {\n  m.get(k)\n}\n",
                "src/app/upload_test.mbt": "test \"same\" {\n  assert_eq(a.hash(), a.hash())\n}\n"}
        found(self, good, "builtin-hash", 0)

    def test_hashed_collections_order_by_the_process(self):
        bad = {"src/app/rows.mbt": "fn rows() -> Unit {\n  let seen = @hashset.HashSet::new()\n"
                                   "  let by = @hashmap.HashMap::new()\n}\n"}
        found(self, bad, "hash-order", 2)
        good = {"src/app/rows.mbt": "fn rows() -> Unit {\n  let by : Map[String, Int] = {}\n}\n"}
        found(self, good, "hash-order", 0)


class Bar(unittest.TestCase):
    FILES = {"src/app/view.mbt": "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n  c.request_frame()\n}\n"}

    def run_main(self, t, *flags):
        import io
        import contextlib
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = detlint.main([t.root, *flags])
        return code, out.getvalue()

    def test_moved_to_another_file_fails(self):
        t = Tree(self.FILES)
        try:
            self.run_main(t, "--update")
            # the same two, one of them moved into another file: the total is the same, that file is over its bar
            with open(os.path.join(t.root, "src/app/view.mbt"), "w", encoding="utf-8") as fh:
                fh.write("fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
            with open(os.path.join(t.root, "src/app/other.mbt"), "w", encoding="utf-8") as fh:
                fh.write("fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
            code, out = self.run_main(t)
            self.assertEqual(code, 1, out)
            self.assertIn("src/app/other.mbt: 1 > 0", out)
        finally:
            t.close()

    def test_update_then_pass_then_more_fails_less_fails(self):
        t = Tree(self.FILES)
        try:
            self.assertEqual(self.run_main(t)[0], 1, "no bar yet")
            self.run_main(t, "--update")
            code, out = self.run_main(t)
            self.assertEqual(code, 0, out)
            # one more: fails, and says where
            with open(os.path.join(t.root, "src/app/view.mbt"), "a", encoding="utf-8") as fh:
                fh.write("fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
            code, out = self.run_main(t)
            self.assertEqual(code, 1)
            self.assertIn("src/app/view.mbt: 3 > 2", out)
            # --update does not raise it
            self.run_main(t, "--update")
            self.assertEqual(self.run_main(t)[0], 1)
            # two fewer than the bar: fails until it is lowered
            with open(os.path.join(t.root, "src/app/view.mbt"), "w", encoding="utf-8") as fh:
                fh.write("fn v(c : @ui.Ctx) -> Unit {\n  c.text(\"x\")\n}\n")
            code, out = self.run_main(t)
            self.assertEqual(code, 1)
            self.assertIn("lower it", out)
            self.run_main(t, "--update")
            code, out = self.run_main(t)
            self.assertEqual(code, 0, out)
            self.assertIn("forbidden", out)
        finally:
            t.close()


if __name__ == "__main__":
    unittest.main(verbosity=1)
