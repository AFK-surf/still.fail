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
