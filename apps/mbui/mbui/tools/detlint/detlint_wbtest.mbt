// Each rule stops what it is for (a made-up file it fails on) and lets its right way by (one it passes); exceptions,
// and the bar.

///|
let conf_text : String =
  #|{"mbt": {"roots": ["src"], "framework": ["src/ui", "src/host"], "clock_sources": ["src/host"],
  #|         "frame_core": ["src/ui/app.mbt", "src/host"]},
  #| "globals": {"roots": ["src/app"]},
  #| "flows": ["flows/*.drive"],
  #| "scripts": ["scripts/*.sh", "scripts/*.mjs"],
  #| "hosts": ["android/*.java", "src/host/*.m", "src/host/*.c"],
  #| "counts": {}}

///|
fn conf_value() -> @rjson.Value {
  @rjson.parse(conf_text) catch {
    _ => panic()
  }
}

///|
fn test_cfg() -> Config {
  Config::new(conf_value())
}

///|
/// The findings not excused (of rule, or all)
fn lint_of(files : Array[(String, String)], rule? : String, cfg? : Config = test_cfg()) -> Array[Finding] {
  lint_sources(files, cfg).filter(fn(f) {
    (rule is None || rule == Some(f.rule)) && f.excused is None
  })
}

///|
fn found(
  files : Array[(String, String)],
  rule : String,
  n : Int,
  cfg? : Config = test_cfg(),
) -> Array[Finding] raise {
  let got = lint_of(files, rule~, cfg~)
  if got.length() != n {
    fail(
      "\{rule}: \{got.length()} found, not \{n}:\n" +
      got.map(fn(f) { "\{f.file}:\{f.line} \{f.what}" }).join("\n"),
    )
  }
  got
}

///|
fn lines(fs : Array[Finding]) -> Array[Int] {
  let a = fs.map(fn(f) { f.line })
  a.sort()
  a
}

///|
test "style outside" {
  // a look drawn to units of its own (an input method's keys, another product's, laid out to the window's width) is
  // not the theme's: no style rule counts it
  let conf = conf_value().set(
    "style",
    @rjson.Value::Obj([("outside", Arr([Str("src/keys/*.mbt")]))]),
  )
  let cfg = Config::new(conf)
  let view =
    #|
    #|fn view(c : @ui.Ctx, u : Double) -> Unit {
    #|  c.box(radius=16.0 * u, bg=0xFCFCFCFFL, fn() { c.text("Q", size=60.0 * u) |> ignore }) |> ignore
    #|}
    #|
  let files = [("src/keys/view.mbt", view), ("src/app/view.mbt", view)]
  for rule in ["style-literal", "box-loose", "style-exact"] {
    assert_eq(
      lint_of(files, rule~, cfg~).map(fn(f) { f.file }).filter(fn(f) { f == "src/keys/view.mbt" }),
      [],
    )
  }
  assert_eq(lines(lint_of(files, rule="box-loose", cfg~)), [3, 3])
}

///|
test "style" {
  let conf = conf_value().set(
    "style",
    @rjson.Value::Obj([("tokens", Arr([Str("src/app/tokens.mbt")]))]),
  )
  let cfg = Config::new(conf)
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|let card : @ui.Style = @ui.style(px=S4, radius=Exact(22.0), gap=Fixed(14.0))
        #|fn view(c : @ui.Ctx) -> Unit {
        #|  c.box(style=card, pad=12.0, fn() {
        #|    c.text("a", size=13.0, color=0x24272BFFL) |> ignore
        #|    c.text("b", style=title) |> ignore
        #|  }) |> ignore
        #|  c.box(style=card, id=7, aspect=1.5, fn() {  }) |> ignore
        #|  c.text("c", style=title, max_lines=2, tracking=0.5) |> ignore
        #|}
        #|let clamp : @ui.TextStyle = @ui.text_style(max_lines=2, tracking=Tight)
        #|let pill : @ui.Style = @ui.css("w=Grow(1.0) px=S1_25 bg=A(Fg,O35) radius=Exact(9.0)")
        #|
      ),
    ),
    (
      "src/app/tokens.mbt",
      (
        #|
        #|pub let title : @ui.TextStyle = @ui.text_style(size=Exact(15.0, 21.0))
        #|pub let column_max : @ui.Len = Fixed(420.0)
        #|pub let wide : @ui.Style = @ui.css("w=Fixed(420.0) radius=Exact(2.0)")
        #|
      ),
    ),
    (
      "src/app/view_test.mbt",
      (
        #|
        #|test "x" {
        #|  c.box(pad=3.0, fn() {  }) |> ignore
        #|}
        #|
      ),
    ),
  ]
  // Exact(22.0) once (its number not again), Fixed's 14.0, pad 12.0, size 13.0, the colour: not the token file's,
  // nor the test's, nor aspect (not a look) nor id; tracking's 0.5; not max_lines (a count, not a look's value) in
  // either; in a style's text Grow's 1.0 and the Exact (not S1_25's digits nor O35's), not the token file's
  assert_eq(lines(lint_of(files, rule="style-literal", cfg~)), [2, 2, 4, 5, 5, 9, 12, 12])
  // the calls said loosely (pad=, size=, max_lines= and tracking=); a box with a style and behaviour alone (id,
  // aspect) is not
  assert_eq(lines(lint_of(files, rule="box-loose", cfg~)), [4, 5, 9])
  // every Exact made, in the token file too
  let exact = lint_of(files, rule="style-exact", cfg~).map(fn(f) { "\{f.file}:\{f.line}" })
  exact.sort_by(@rjson.str_cmp)
  assert_eq(exact, [
    "src/app/tokens.mbt:2", "src/app/tokens.mbt:4", "src/app/view.mbt:12", "src/app/view.mbt:2",
  ])
  // the enum's declaration and a match's patterns are not values made
  let decl = [
    (
      "src/ui/style_tokens.mbt",
      (
        #|
        #|pub(all) enum Space {
        #|  S4
        #|  Exact(Double)
        #|}
        #|fn Space::px(self : Space) -> Double {
        #|  match self {
        #|    S4 => 16.0
        #|    Exact(v) => v
        #|  }
        #|}
        #|
      ),
    ),
  ]
  found(decl, "style-exact", 0) |> ignore
}

///|
test "style-text" {
  let files = [
    (
      "src/app/look.mbt",
      (
        #|
        #|let card : @ui.Style = @ui.style(row=true, h=S7, px=S2, radius=Lg, bg=A(Fg, O35), clip=false,
        #|  hovered=@ui.patch(bg=Hover), w=Grow(1.0), shadow=Cast(4.0, -1.0, 0x00000033L))
        #|let card_on : @ui.Style = card.then(@ui.style(bg=@ui.Accent, border_color=Color::Line))
        #|let pane : @ui.Style = @ui.css("w=Full px=S2")
        #|let grown : @ui.Style = @ui.style(w=@sf.grow, px=S2)
        #|let sided : @ui.Style = @ui.style(w=Fixed(side_w))
        #|let capped : @ui.Style = @ui.style(h=Fixed(ROW_H))
        #|let lifted : @ui.Style = card.then(@ui.style(shadow=@sf.floating.cast()))
        #|let pressing : @ui.Style = @ui.style(pressed=dim_patch)
        #|let twice : @ui.Style = @ui.style(w=Fixed(2.0 * 7.0))
        #|fn view(c : @ui.Ctx, wide : Bool) -> Unit {
        #|  c.box(style=@ui.style(px=S2), fn() {  }) |> ignore
        #|}
        #|test "t" {
        #|  let s = @ui.style(px=S2)
        #|}
        #|
      ),
    ),
    (
      "src/ui/kit_styles.mbt",
      (
        #|
        #|let no_style : Style = style()
        #|let row_style : Style = style(row=true, gap=S1)
        #|let words : TextStyle = text_style(size=Lg)
        #|let other = style(row=true)
        #|
      ),
    ),
    (
      "src/app/look_test.mbt",
      (
        #|
        #|let fixture : @ui.Style = @ui.style(px=S2)
        #|
      ),
    ),
  ]
  // a named style all tokens and numbers, a .then(…)'s; in mbui's own package the bare style( where its let says
  // Style. Not one naming a variable (@sf.grow, side_w, a constant ROW_H, a patch by name), a call, an operator, one
  // in a function or a test, nor already text
  let got = found(files, "style-text", 4)
  assert_eq(got.map(fn(f) { "\{f.file}:\{f.line}" }), [
    "src/app/look.mbt:2", "src/app/look.mbt:4", "src/ui/kit_styles.mbt:2", "src/ui/kit_styles.mbt:3",
  ])
  // what to write instead, printed
  assert_has(
    got[0].what,
    "write: @ui.css(\"row h=S7 px=S2 radius=Lg bg=A(Fg,O35) clip=false hovered{bg=Hover} w=Grow(1.0) shadow=Cast(4.0,-1.0,0x00000033)\")",
  )
  assert_has(got[1].what, "write: @ui.css(\"bg=Accent border_color=Line\")")
  assert_has(got[2].what, "write: css(\"\")")
  assert_has(got[3].what, "write: css(\"row gap=S1\")")
}

///|
test "frame-request" {
  found(
    [
      (
        "src/app/view.mbt",
        (
          #|
          #|fn view(c : @ui.Ctx) -> Unit {
          #|  if c.pressed(1) { c.request_frame() }
          #|  @hostapi.request_frame()
          #|}
          #|
        ),
      ),
    ],
    "frame-request",
    2,
  )
  |> ignore
  // the framework's own components and motion count too: an animation is declared once, not asked each frame
  found(
    [
      (
        "src/ui/list.mbt",
        "fn fling(c : Ctx) -> Unit {\n  if moving { c.request_frame() }\n  h_request_frame()\n}\n",
      ),
    ],
    "frame-request",
    2,
  )
  |> ignore
  // the scheduler asks (its frame loop, its dispatch); a test may; a comment or a string naming it is not a call
  found(
    [
      ("src/ui/app.mbt", "fn on_key(c : Ctx) -> Unit {\n  c.request_frame()\n}\n"),
      ("src/app/view_test.mbt", "test \"x\" {\n  c.request_frame()\n}\n"),
      (
        "src/app/view.mbt",
        "// c.request_frame() was here\nfn v(c : @ui.Ctx) -> Unit {\n  c.text(\"request_frame()\")\n}\n",
      ),
    ],
    "frame-request",
    0,
  )
  |> ignore
}

///|
test "engine-math" {
  found(
    [
      (
        "src/ui/line.mbt",
        "fn arc(a : Double) -> Double {\n  @math.cos(a) + @math.sin(a) + @math.pow(2.0, a) + @math.exp(a)\n}\n",
      ),
      (
        "src/app/spring.mbt",
        "fn decay(t : Double) -> Double {\n  2.718281828459045.pow(-t)\n}\n",
      ),
    ],
    "engine-math",
    5,
  )
  |> ignore
  found(
    [
      (
        "src/ui/line.mbt",
        "fn arc(a : Double) -> Double {\n  @dmath.cos(a) + @dmath.sin(a) + @math.floor(a) + a.sqrt()\n}\n",
      ),
    ],
    "engine-math",
    0,
  )
  |> ignore
}

///|
test "frame-wait" {
  found(
    [
      (
        "src/motion/fx.mbt",
        (
          #|
          #|async fn play(v : Value) -> Unit {
          #|  while v.moving() {
          #|    @effect.next_frame()
          #|  }
          #|}
          #|
        ),
      ),
    ],
    "frame-wait",
    1,
  )
  |> ignore
  found(
    [
      (
        "src/motion/fx.mbt",
        (
          #|
          #|async fn play(v : Value, end : Int) -> Unit {
          #|  @effect.sleep(end - @effect.now().to_int())
          #|}
          #|
        ),
      ),
      (
        "src/effect/runtime.mbt",
        "pub async fn next_frame() -> Unit {\n  wait()\n}\nfn loop() -> Unit {\n  next_frame()\n}\n",
      ),
    ],
    "frame-wait",
    0,
  )
  |> ignore
}

///|
test "at-rest-wait" {
  let bad = [
    // waited on: a loop, a condition, an until; a drive's rest step, in a test's text and in a flow
    (
      "src/app/view_test.mbt",
      (
        #|
        #|test "saves" {
        #|  let t = @ui.Tester::new(fn(c) { view(c) })
        #|  while !t.at_rest() {
        #|    t.frame()
        #|  }
        #|  if t.at_rest() { t.tap(1.0, 2.0) }
        #|  t.drive("tap save\nrest\nexit") |> ignore
        #|}
        #|
      ),
    ),
    // a tap's target waited on until it holds still from one frame to the next
    (
      "src/ui/drive.mbt",
      (
        #|
        #|fn drive_tap(d : Driver, x : Double, y : Double) -> Unit {
        #|  if !d.held_still(x, y) {
        #|    return
        #|  }
        #|  press(x, y)
        #|}
        #|
      ),
    ),
    ("flows/01-save.drive", "tap save\nrest\nexit\n"),
    // a picture at the app's rest
    (
      "scripts/shots.sh",
      "MBUI_SHOT_MS=rest ./app\nnode web-shot.mjs out.png && open 'http://x/?shot_at=rest'\n",
    ),
    // an end run on until nothing moves: to what moves' end, again; the frame left owed drawn, a timer's time, again
    // (each loop once)
    (
      "src/app/flow.mbt",
      (
        #|
        #|fn Flow::end(self : Flow) -> Unit {
        #|  while true {
        #|    while self.t.rest_of("") > self.t.time() {
        #|      self.t.run_for(self.t.rest_of("") - self.t.time())
        #|    }
        #|    self.t.draw()
        #|    match self.t.next_wake() {
        #|      Some((at, _)) => self.t.run_for(at - self.t.time())
        #|      None => break
        #|    }
        #|  }
        #|  self.t.assert_idle()
        #|}
        #|
      ),
    ),
  ]
  found(bad, "at-rest-wait", 9) |> ignore
  let good = [
    // asserted, with what keeps it from it said; a word "rest" that is no step; a declared moment
    (
      "src/app/view_test.mbt",
      (
        #|
        #|test "saves" {
        #|  let t = @ui.Tester::new(fn(c) { view(c) })
        #|  t.run_for(@kit.dialog_in)
        #|  assert_true(t.at_rest(), msg=t.rest_why())
        #|  assert_false(t.at_rest())
        #|  t.drive("tap rest of the list\nexit") |> ignore
        #|}
        #|
      ),
    ),
    ("flows/01-save.drive", "tap the rest\nuntil saved\nexit\n"),
    ("scripts/shots.sh", "MBUI_SHOT_MS=1000 ./app\n"),
    // the frame core's own reading of it as a frame ends
    ("src/ui/app.mbt", "fn on_frame(c : Ctx) -> Unit {\n  c.frame_rest = c.at_rest()\n}\n"),
    // one declared end run to; what moves read where nothing runs the clock; an end a declared time
    (
      "src/app/flow.mbt",
      (
        #|
        #|fn Flow::end(self : Flow) -> Unit {
        #|  self.t.run_to(@ui.nav_rest())
        #|  for m in self.t.moving() {
        #|    self.said.push(m)
        #|  }
        #|  self.t.run_for(@kit.toast_ms)
        #|  self.t.assert_idle()
        #|}
        #|
      ),
    ),
  ]
  found(good, "at-rest-wait", 0) |> ignore
}

///|
test "settle" {
  let bad = [
    (
      "src/app/view_test.mbt",
      (
        #|
        #|test "opens" {
        #|  let t = @ui.Tester::new(fn(c) { view(c) })
        #|  t.tap(1.0, 2.0)
        #|  t.settle() |> ignore
        #|  assert_true(t.settled())
        #|}
        #|
      ),
    ),
    (
      "src/ui/tester.mbt",
      (
        #|
        #|pub fn Tester::tap(self : Tester, x : Double, y : Double) -> Unit {
        #|  self.touch(0, x, y)
        #|  self.settle() |> ignore
        #|}
        #|
      ),
    ),
  ]
  found(bad, "settle", 3) |> ignore
  let good = [
    (
      "src/app/view_test.mbt",
      (
        #|
        #|test "opens" {
        #|  let t = @ui.Tester::new(fn(c) { view(c) })
        #|  t.tap(1.0, 2.0)
        #|  t.run_for(@kit.dialog_in)
        #|  t.assert_idle()
        #|}
        #|
      ),
    ),
    // settle's own definition, and another type's settle (a Nav's: its pages put in place)
    (
      "src/ui/tester.mbt",
      (
        #|
        #|pub fn Tester::settle(self : Tester) -> Int {
        #|  while !self.settled() { self.frame() }
        #|  0
        #|}
        #|
      ),
    ),
    (
      "src/ui/nav.mbt",
      (
        #|
        #|fn[P] Nav::push(self : Nav[P], page : P) -> Unit {
        #|  self.settle()
        #|}
        #|
      ),
    ),
  ]
  found(good, "settle", 0) |> ignore
}

///|
test "flow-wait" {
  found([("flows/01.drive", "tap 发消息\nwait 1500\nlinger 20000\n")], "flow-wait", 2) |> ignore
  found(
    [
      (
        "flows/01.drive",
        "# wait 1500 was here\ntap 发消息\nuntil 收到\ntimeout 60000\nhold 700 引用\n",
      ),
    ],
    "flow-wait",
    0,
  )
  |> ignore
}

///|
test "unsettled-ok" {
  found(
    [
      (
        "src/app/view_test.mbt",
        "test \"x\" {\n  t.settle(unsettled_ok=true) |> ignore\n  f.end(unsettled_ok=\"a spinner\")\n}\n",
      ),
    ],
    "unsettled-ok",
    2,
  )
  |> ignore
  found(
    [
      (
        "src/ui/tester.mbt",
        "pub fn Tester::settle(self : Tester, unsettled_ok? : Bool = false) -> Int {\n  0\n}\n",
      ),
    ],
    "unsettled-ok",
    0,
  )
  |> ignore
}

///|
test "script-wait" {
  found(
    [
      ("scripts/shots.sh", "MBUI_SCRIPT=shot MBUI_SHOT_AT=60 ./app\nsleep 3\n"),
      (
        "scripts/web.mjs",
        "await page.waitForTimeout(Number(process.env.WAIT || 800));\nawait new Promise((r) => setTimeout(r, 500));\n",
      ),
    ],
    "script-wait",
    4,
  )
  |> ignore
  found(
    [
      ("scripts/shots.sh", "# sleep 3 was here\nMBUI_SCRIPT=shot ./app\nwait $pid\n"),
      (
        "scripts/web.mjs",
        "await page.waitForFunction(() => window.__mb !== undefined);\n",
      ),
    ],
    "script-wait",
    0,
  )
  |> ignore
}

///|
test "device-shot" {
  found(
    [
      (
        "scripts/ref.sh",
        "\"SHOT \"*) $ADB exec-out screencap -p > $O/$n.png ;;\nxcrun simctl io \"$ID\" screenshot \"$O/$n.png\"\n",
      ),
    ],
    "device-shot",
    2,
  )
  |> ignore
  found(
    [
      (
        "scripts/ref.sh",
        "# adb's screencap was here\nbash scripts/render_android.sh run\nMBUI_SCRIPT=shot MBUI_SHOT_DIR=out ./app\n",
      ),
    ],
    "device-shot",
    0,
  )
  |> ignore
}

///|
test "host-import" {
  found(
    [("src/kit/moon.pkg", "import {\n  \"mbui/host\",\n  \"mbui/ui\",\n}\n")],
    "host-import",
    1,
  )
  |> ignore
  found(
    [
      ("src/kit/moon.pkg", "import {\n  \"mbui/hostapi\",\n  \"mbui/ui\",\n}\n"),
      (
        "src/demo/moon.pkg",
        "import {\n  \"mbui/host\",\n}\n\noptions(\n  \"is-main\": true,\n)\n",
      ),
    ],
    "host-import",
    0,
  )
  |> ignore
}

///|
test "library-import" {
  let cfg = Config::new(
    @rjson.parse(
      #|{"mbt": {"roots": ["src"]}, "library": {"roots": ["src/sf"], "imports": ["mbui/", "moonbitlang/", "app/sf", "app/kept"]}}
      ,
    ) catch {
      _ => panic()
    },
  )
  // the library importing the app's pages, its core
  assert_eq(
    lint_of(
      [("src/sf/moon.pkg", "import {\n  \"mbui/ui\",\n  \"app/pages\",\n  \"app/core\",\n}\n")],
      rule="library-import",
      cfg~,
    ).length(),
    2,
  )
  // the framework, the core library, what it is said to have; the app's pages may import anything
  assert_eq(
    lint_of(
      [
        ("src/sf/moon.pkg", "import {\n  \"mbui/ui\",\n  \"moonbitlang/core/json\",\n}\n\nimport { \"app/kept\" } for \"test\"\n"),
        ("src/pages/moon.pkg", "import {\n  \"app/core\",\n  \"app/sf\",\n}\n"),
      ],
      rule="library-import",
      cfg~,
    ).length(),
    0,
  )
}

///|
test "page-settle" {
  found(
    [
      (
        "scripts/web.mjs",
        "await page.waitForFunction(() => __mbhost.settled(), null, { timeout: 30000 });\nconsole.log(await page.evaluate(() => __mbhost.unsettled()));\n",
      ),
    ],
    "page-settle",
    2,
  )
  |> ignore
  found(
    [
      (
        "scripts/web.mjs",
        "// __mbhost.settled() was here\nawait page.evaluate(() => __mbhost.run_for(t));\n",
      ),
    ],
    "page-settle",
    0,
  )
  |> ignore
}

///|
test "frame-count" {
  found(
    [("src/app/view_test.mbt", "test \"x\" {\n  for _ in 0..<60 {\n    t.frame()\n  }\n}\n")],
    "frame-count",
    1,
  )
  |> ignore
  found(
    [
      (
        "src/app/view_test.mbt",
        "test \"x\" {\n  for i in 0..<rows.length() {\n    t.frame()\n  }\n  for _ in 0..<3 {\n    t.tap(1.0, 1.0)\n  }\n}\n",
      ),
    ],
    "frame-count",
    0,
  )
  |> ignore
}

///|
test "literal-time" {
  found(
    [
      (
        "src/app/view_test.mbt",
        "test \"x\" {\n  t.run_for(347.0)\n  t.frame(ms=1000.0)\n  t.advance(16.0)\n}\n",
      ),
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  c.wake_in(50.0)\n  c.wake_at(c.now() + 500.0)\n}\n",
      ),
    ],
    "literal-time",
    5,
  )
  |> ignore
  found(
    [
      (
        "src/app/view_test.mbt",
        "test \"x\" {\n  t.run_for(@kit.toast_life)\n  t.frame()\n  t.frame(ms=0.0)\n}\n",
      ),
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  c.wake_in(hold_ms)\n  c.wake_at(at + toast_life)\n}\n",
      ),
    ],
    "literal-time",
    0,
  )
  |> ignore
}

///|
test "stable-mode" {
  found(
    [
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  let p = if c.stable() { 1.0 } else { 0.5 }\n}\n",
      ),
    ],
    "stable-mode",
    1,
  )
  |> ignore
  // the framework's own code too: a screenshot's run draws and moves as any run
  found(
    [("src/ui/draw.mbt", "pub fn Ctx::still(self : Ctx) -> Bool {\n  self.stable()\n}\n")],
    "stable-mode",
    1,
  )
  |> ignore
  // reduced motion is the person's: not stable-mode
  found(
    [
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  let p = if c.still() { 1.0 } else { 0.5 }\n}\n",
      ),
    ],
    "stable-mode",
    0,
  )
  |> ignore
}

///|
test "app-clock" {
  found(
    [
      (
        "src/app/view.mbt",
        (
          #|
          #|fn v(c : @ui.Ctx) -> Unit {
          #|  let p = (c.now() - at) / 180.0
          #|  let t = @ui.now()
          #|}
          #|
        ),
      ),
    ],
    "app-clock",
    2,
  )
  |> ignore
  found(
    [
      ("src/ui/ctx.mbt", "fn Ctx::frame_time(self : Ctx) -> Double {\n  self.now()\n}\n"),
      ("src/app/view_test.mbt", "test \"x\" {\n  let t0 = c.now()\n}\n"),
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  let p = @motion.anim(c, \"open\", sheet_in)\n}\n",
      ),
    ],
    "app-clock",
    0,
  )
  |> ignore
}

///|
test "wall-clock" {
  found(
    [
      ("src/app/js.mbt", "extern \"js\" fn ms() -> Double =\n  #|() => Date.now()\n"),
      (
        "src/app/r.mbt",
        "fn r() -> Int {\n  let g = @random.Rand::new()\n  g.int()\n}\n",
      ),
      ("src/app/w.mbt", "fn w() -> Double {\n  @core.wall_ms()\n}\n"),
    ],
    "wall-clock",
    3,
  )
  |> ignore
  found(
    [
      (
        "src/host/host_js.mbt",
        "extern \"js\" fn now() -> Double =\n  #|() => performance.now()\n",
      ),
      (
        "src/app/r.mbt",
        "fn r(seed : Int) -> Int {\n  let g = @random.Rand::new(seed~)\n  g.int()\n}\n",
      ),
    ],
    "wall-clock",
    0,
  )
  |> ignore
}

///|
test "wall-clock random ids" {
  found(
    [
      (
        "src/app/name.mbt",
        "fn name() -> String {\n  \"pasted-text-\" + uuid() + \".txt\"\n}\n",
      ),
      ("src/app/id.mbt", "fn id() -> String {\n  @util.random_id()\n}\n"),
      (
        "src/app/js.mbt",
        "extern \"js\" fn u() -> String =\n  #|() => crypto.randomUUID()\n",
      ),
      (
        "src/app/c.mbt",
        "extern \"c\" fn r() -> Int =\n  #|int r(void) { return rand(); }\n",
      ),
    ],
    "wall-clock",
    4,
  )
  |> ignore
  found(
    [
      // shaping a hash it is given: the same each run
      (
        "src/app/name.mbt",
        "fn name(h : String) -> String {\n  \"pasted-text-\" + uuid(h) + \".txt\"\n}\n",
      ),
      // a test may make one
      ("src/app/id_test.mbt", "test \"x\" {\n  let id = random_id()\n}\n"),
      // the host that provides randomness
      (
        "src/host/host_js.mbt",
        "extern \"js\" fn u() -> String =\n  #|() => crypto.randomUUID()\n",
      ),
      // words that only look alike
      (
        "src/app/w.mbt",
        "fn w() -> String {\n  let operand = 1\n  \"brand(new)\"\n}\n",
      ),
    ],
    "wall-clock",
    0,
  )
  |> ignore
}

///|
test "poll" {
  found(
    [
      (
        "src/app/view.mbt",
        (
          #|
          #|fn ready() -> Bool {
          #|  @hostapi.update_state() != ""
          #|}
          #|
          #|fn v(c : @ui.Ctx, j : Job) -> Unit {
          #|  match j.made() {
          #|    Some(img) => c.image(img)
          #|    None => c.wake_in(poll_ms)
          #|  }
          #|  if c.list_row_height(l, 3) is None {
          #|    c.request_frame()
          #|  }
          #|  if ready() {
          #|    c.request_frame()
          #|  }
          #|  if c.pressed(stage) {
          #|    c.request_frame()
          #|  }
          #|}
          #|
        ),
      ),
    ],
    "poll",
    4,
  )
  |> ignore
  found(
    [
      (
        "src/app/view.mbt",
        (
          #|
          #|fn v(c : @ui.Ctx) -> Unit {
          #|  if c.pressed(stage) {
          #|    c.wake_in(hold_ms - held)
          #|  }
          #|  if open {
          #|    c.wake_at(at + toast_life)
          #|  }
          #|}
          #|
        ),
      ),
    ],
    "poll",
    0,
  )
  |> ignore
}

///|
test "host-read" {
  found(
    [
      (
        "src/app/view.mbt",
        "fn v() -> Unit {\n  let p = @hostapi.platform()\n  let d = @hostapi.system_dark()\n}\n",
      ),
    ],
    "host-read",
    2,
  )
  |> ignore
  found(
    [
      (
        "src/app/view.mbt",
        "fn v() -> Unit {\n  let p = @ui.platform()\n  @hostapi.open_url(u)\n}\n",
      ),
      ("src/ui/hostread.mbt", "pub fn platform() -> Int {\n  @hostapi.platform()\n}\n"),
    ],
    "host-read",
    0,
  )
  |> ignore
}

///|
test "globals" {
  let got = found(
    [
      (
        "src/app/state.mbt",
        (
          #|
          #|///|
          #|let open : Ref[Bool] = { val: false }
          #|
          #|///|
          #|let seen : Map[String, Int] = {}
          #|
          #|///|
          #|fn reset() -> Unit {
          #|  open.val = false
          #|}
          #|
        ),
      ),
    ],
    "globals",
    1,
  )
  assert_true(got[0].what.contains("seen"))
  found(
    [
      (
        "src/app/state.mbt",
        (
          #|
          #|///|
          #|let open : Ref[Bool] = { val: false }
          #|
          #|///|
          #|// kept across runs: a table of constants, never written
          #|let names : Map[String, Int] = { "a": 1 }
          #|
          #|///|
          #|let limit : Int = 3
          #|
          #|///|
          #|let seen : Map[String, Int] = {}
          #|
          #|///|
          #|fn reset() -> Unit {
          #|  open.val = false
          #|  forget()
          #|}
          #|
          #|///|
          #|fn forget() -> Unit {
          #|  seen.clear()
          #|}
          #|
        ),
      ),
      (
        "src/app/more.mbt",
        (
          #|
          #|///|
          #|let later : Array[Int] = []
          #|
          #|///|
          #|fn init {
          #|  @ui.on_reset(fn() { later.clear() })
          #|}
          #|
        ),
      ),
    ],
    "globals",
    0,
  )
  |> ignore
}

///|
test "reset-wire" {
  // a hook set by reset to what does the work (reset runs only as a Tester starts): one; put back as its let has it
  // (false, Ref(false), Ref::new(false)), none
  let got = found(
    [
      (
        "src/app/state.mbt",
        (
          #|
          #|///|
          #|let open : Ref[Bool] = { val: false }
          #|
          #|///|
          #|let asked : Ref[(String) -> Unit] = Ref(fn(_) {  })
          #|
          #|///|
          #|let shown : Ref[Int] = Ref::new(0)
          #|
          #|///|
          #|fn reset() -> Unit {
          #|  open.val = false
          #|  shown.val = 0
          #|  asked.val = pick_open
          #|}
          #|
          #|///|
          #|fn pick_open(key : String) -> Unit {
          #|  ignore(key)
          #|}
          #|
        ),
      ),
    ],
    "reset-wire",
    1,
  )
  assert_true(got[0].what.contains("asked"))
  found(
    [
      (
        "src/app/state.mbt",
        (
          #|
          #|///|
          #|let shown : Ref[Int] = Ref::new(0)
          #|
          #|///|
          #|let by_hand : Ref[Bool] = Ref(false)
          #|
          #|///|
          #|fn reset() -> Unit {
          #|  shown.val = 0
          #|  // (state it marks, not a wire; one a call makes)
          #|  by_hand.val = true
          #|  made.val = make(1)
          #|}
          #|
          #|///|
          #|let made : Ref[Int] = Ref(make(0))
          #|
          #|///|
          #|fn make(n : Int) -> Int {
          #|  n
          #|}
          #|
        ),
      ),
    ],
    "reset-wire",
    0,
  )
  |> ignore
}

///|
test "build-effect" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn keep(src : Source, n : Int) -> Unit {
        #|  (src.call)("keep", Json::number(n.to_double()), fn(_) {  })
        #|}
        #|fn send(src : Source) -> Unit {
        #|  (src.call)("send", Json::null(), fn(_) {  })
        #|}
        #|fn view(c : @ui.Ctx, src : Source, n : @ui.NativeView) -> Unit {
        #|  (src.call)("seen", Json::null(), fn(_) {  })
        #|  keep(src, 1)
        #|  n.reload()
        #|  @hostapi.set_dark(true)
        #|  c.after_build("seen", fn() { (src.call)("seen", Json::null(), fn(_) {  }); n.seek(1.0) })
        #|  if c.clicked(7) {
        #|    send(src)
        #|    n.play()
        #|  }
        #|  if button(c, "go") {
        #|    keep(src, 2)
        #|  }
        #|  c.take_back(fn() { n.close() })
        #|  c.box(fn() { keep(src, 3) }) |> ignore
        #|  c.box(on_tap=fn() { keep(src, 4) }, fn() {  }) |> ignore
        #|  (src.call)("ask", Json::null(), fn(r) { keep(src, 5) })
        #|  c.close()
        #|}
        #|
      ),
    ),
  ]
  let got = found(files, "build-effect", 6)
  got.sort_by(fn(a, b) { a.line.compare(b.line) })
  // the core's calls (the ask itself, not its answer), a helper doing one, the native view's reload, the host's
  // effect, and the box's children's (built as the frame builds): not what after_build, an input, a handler or an
  // answer does, nor the Ctx's own
  assert_eq(got.map(fn(f) { f.line }), [9, 10, 11, 12, 22, 24])
  assert_true(got[2].what.contains(".reload"))
}

///|
test "after-build-input: what an input took told by after_build, not what every build works out alike, nor by tell" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn view(c : @ui.Ctx, src : Source, on : Bool) -> Unit {
        #|  c.after_build("seen", fn() { (src.call)("seen", Json::null(), fn(_) {  }) })
        #|  if c.clicked(7) {
        #|    c.after_build("send", fn() { (src.call)("send", Json::null(), fn(_) {  }) })
        #|  }
        #|  if switch_row(c, "on", on) != on {
        #|    c.after_build("switch", fn() { (src.call)("switch", Json::null(), fn(_) {  }) })
        #|  }
        #|  if button(c, "go") {
        #|    c.tell("go", fn() { (src.call)("go", Json::null(), fn(_) {  }) })
        #|  }
        #|}
        #|
      ),
    ),
  ]
  let got = found(files, "after-build-input", 2)
  got.sort_by(fn(a, b) { a.line.compare(b.line) })
  // under the click and under the switch used; not what every build says, nor what tell tells
  assert_eq(got.map(fn(f) { f.line }), [5, 8])
}

///|
test "build-effect: inputs it knows by shape" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn empty(c : @ui.Ctx, words : String, on_tap : () -> Unit) -> Unit {
        #|  if c.clicked(3) {
        #|    on_tap()
        #|  }
        #|}
        #|fn shown(c : @ui.Ctx, body : () -> Unit) -> Unit {
        #|  body()
        #|}
        #|fn view(c : @ui.Ctx, src : Source, p : Player, prefs : Prefs) -> Unit {
        #|  let k = @sf.segmented(c, "face", ["a", "b"], 0)
        #|  let want = if k == 0 { "a" } else { "b" }
        #|  if want != prefs.face {
        #|    (src.call)("face", Json::null(), fn(_) {  })
        #|  }
        #|  if k == 0 {
        #|    (src.call)("every", Json::null(), fn(_) {  })
        #|  }
        #|  let typed = c.code_field(4)
        #|  if typed is Some(code) {
        #|    (src.call)("code", Json::null(), fn(_) {  })
        #|  }
        #|  empty(c, "none", fn() { (src.call)("up", Json::null(), fn(_) {  }) })
        #|  shown(c, fn() { (src.call)("built", Json::null(), fn(_) {  }) })
        #|  match c.rect_of(5) {
        #|    Some((x, _, _, _)) if c.pressed(5) => p.scrub = x
        #|    _ =>
        #|      if p.scrub >= 0.0 {
        #|        p.seek(p.scrub)
        #|        p.scrub = -1.0
        #|      }
        #|  }
        #|  if p.ready {
        #|    p.seek(0.0)
        #|  }
        #|}
        #|
      ),
    ),
  ]
  // a choice other than what is kept, a code typed in, a button's callback, a press let go: the input's; a choice
  // as it stands each frame, a closure built as it is given, a seek on what is not the finger's: not
  assert_eq(lines(found(files, "build-effect", 3)), [17, 24, 34])
}

///|
test "build-effect: what a presenter keeps runs later, and so does what is handed on to one" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn ask_first(title : String, run : () -> Unit) -> Unit {
        #|  @sf.confirm(title, "", "go", run)
        #|}
        #|fn view(c : @ui.Ctx, src : Source, n : Int) -> Unit {
        #|  if n > 0 {
        #|    @sf.confirm("go?", "", "go", fn() { (src.call)("go", Json::null(), fn(_) {  }) })
        #|    ask_first("go?", fn() { (src.call)("go", Json::null(), fn(_) {  }) })
        #|    @sf.toast(fn() { (src.call)("built", Json::null(), fn(_) {  }) })
        #|  }
        #|}
        #|
      ),
    ),
  ]
  let cfg = Config::new(@rjson.parse("{\"build_effect\": {\"later\": [\"@sf.confirm\"]}}"))
  // a presenter's action, and one handed on to it whole: told once it is said; given to what is not one: as it builds
  assert_eq(lines(found(files, "build-effect", 1, cfg~)), [9])
}

///|
test "build-effect: a stream's callbacks are its events" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn view(c : @ui.Ctx, src : Source, s : Ref[@ui.Stream?]) -> Unit {
        #|  if s.val is None {
        #|    s.val = Some(@ui.Stream::new(
        #|      shown=fn(ts) { (src.call)("screen.ack", Json::null(), fn(_) {  }) },
        #|      broken=fn() { (src.call)("screen.keyframe", Json::null(), fn(_) {  }) },
        #|    ))
        #|  }
        #|  c.box(fn() { (src.call)("screen.view", Json::null(), fn(_) {  }) }) |> ignore
        #|}
        #|
      ),
    ),
  ]
  // what a stream says shown or broken is told as its event comes, not as the frame builds; a box's children are
  assert_eq(lines(found(files, "build-effect", 1)), [9])
}

///|
test "an exception's reason on the line or over it" {
  let files = [
    (
      "src/app/view.mbt",
      (
        #|
        #|fn v(c : @ui.Ctx) -> Unit {
        #|  c.request_frame() // det-ok(frame-request): the bench draws every frame on purpose
        #|  // det-ok(frame-request): the same, on the line over it
        #|  c.request_frame()
        #|  c.request_frame() // det-ok(frame-request)
        #|}
        #|
      ),
    ),
  ]
  let all = lint_sources(files, test_cfg())
  assert_eq(all.filter(fn(f) { f.excused is Some(_) }).length(), 2)
  // an exception without its reason is not taken
  assert_eq(lint_of(files, rule="frame-request").length(), 1)
}

///|
test "another rule's exception does not excuse" {
  found(
    [
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(poll): why\n}\n",
      ),
    ],
    "frame-request",
    1,
  )
  |> ignore
}

///|
test "given-up interfaces are forbidden" {
  found(
    [
      (
        "src/ui/anim.mbt",
        "pub fn Ctx::frames_until(self : Ctx, t : Double) -> Unit {\n  ()\n}\n",
      ),
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  c.animating_until(at + d)\n  if c.animating() { () }\n  @ui.run_animations(c)\n}\n",
      ),
    ],
    "retired-api",
    4,
  )
  |> ignore
  // motion_end: the framework's own, not a test's nor the app's
  found(
    [
      (
        "src/app/view_test.mbt",
        "test \"x\" {\n  t.run_for(t.motion_end() - t.time())\n}\n",
      ),
      ("src/app/view.mbt", "fn v(c : @ui.Ctx) -> Unit {\n  let e = c.motion_end()\n}\n"),
    ],
    "retired-api",
    2,
  )
  |> ignore
  found(
    [
      (
        "src/ui/motion.mbt",
        "pub fn Ctx::motion_end(self : Ctx) -> Double {\n  self.ends.max()\n}\n",
      ),
      (
        "src/ui/motion_test.mbt",
        "test \"its end\" {\n  assert_eq(t.motion_end(), 180.0)\n}\n",
      ),
    ],
    "retired-api",
    0,
  )
  |> ignore
  found(
    [
      (
        "src/app/view.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n  let animating = true\n  c.text(\"frames_until\")\n}\n",
      ),
    ],
    "retired-api",
    0,
  )
  |> ignore
}

///|
test "builtin-hash taken out as a value" {
  found(
    [
      (
        "src/app/upload.mbt",
        "fn upload_id(name : String) -> Int {\n  name.hash() + Hash::hash(name)\n}\nimpl Hash for Seed with hash_combine(self, h) {\n  ()\n}\n",
      ),
    ],
    "builtin-hash",
    3,
  )
  |> ignore
  // the stable one; a Map's keys; a test comparing two
  found(
    [
      (
        "src/app/upload.mbt",
        "fn upload_id(name : String) -> Int64 {\n  @ui.stable_hash(name)\n}\nfn kept(m : Map[String, Int], k : String) -> Int? {\n  m.get(k)\n}\n",
      ),
      ("src/app/upload_test.mbt", "test \"same\" {\n  assert_eq(a.hash(), a.hash())\n}\n"),
    ],
    "builtin-hash",
    0,
  )
  |> ignore
}

///|
test "hashed collections order by the process" {
  found(
    [
      (
        "src/app/rows.mbt",
        "fn rows() -> Unit {\n  let seen = @hashset.HashSet::new()\n  let by = @hashmap.HashMap::new()\n}\n",
      ),
    ],
    "hash-order",
    2,
  )
  |> ignore
  found(
    [("src/app/rows.mbt", "fn rows() -> Unit {\n  let by : Map[String, Int] = {}\n}\n")],
    "hash-order",
    0,
  )
  |> ignore
}

// ---------------------------------------------------------------------------------------------------------------------
// The bar: run as the command is, on a module of made-up files in a directory of its own

///|
priv struct Tree {
  root : String
}

///|
let trees : Ref[Int] = { val: 0 }

///|
fn Tree::new(files : Array[(String, String)]) -> Tree {
  trees.val += 1
  let base = @sys.getenv("TMPDIR").unwrap_or("/tmp")
  let root = @sys.join(
    base,
    "detlint-test-\{@sys.basename(@sys.cwd())}-\{trees.val}",
  )
  let t = { root, }
  t.clear()
  @sys.makedirs(root)
  for f in files {
    t.write(f.0, f.1)
  }
  let _ = @sys.write_text(@sys.join(root, "detlint.json"), conf_text)
  t
}

///|
fn Tree::write(self : Tree, rel : String, text : String) -> Unit {
  let p = @sys.join(self.root, rel)
  @sys.makedirs(@sys.dirname(p))
  let _ = @sys.write_text(p, text)
}

///|
fn Tree::append(self : Tree, rel : String, text : String) -> Unit {
  let p = @sys.join(self.root, rel)
  let _ = @sys.write_text(p, @sys.read_text(p).unwrap_or("") + text)
}

///|
fn Tree::clear(self : Tree) -> Unit {
  fn rm(p : String) -> Unit {
    if @sys.is_dir(p) {
      for n in @sys.list_dir(p) {
        rm(@sys.join(p, n))
      }
    }
    let _ = @sys.remove(p)
  }

  if @sys.exists(self.root) {
    rm(self.root)
  }
}

///|
fn Tree::run(self : Tree, flags : Array[String]) -> (Int, String) {
  let out = []
  let err = []
  let code = run([self.root, ..flags], out, err)
  (code, (err + out).join("\n"))
}

///|
fn assert_has(text : String, part : String) -> Unit raise {
  if !text.contains(part) {
    fail("no \"\{part}\" in:\n\{text}")
  }
}

///|
let bar_files : Array[(String, String)] = [
  (
    "src/app/view.mbt",
    "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n  c.request_frame()\n}\n",
  ),
]

///|
test "exceptions have a bar of their own" {
  let t = Tree::new([
    (
      "src/app/view.mbt",
      "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(frame-request): a\n}\n",
    ),
  ])
  assert_eq(t.run(["--update"]).0, 0)
  assert_eq(t.run([]).0, 0)
  t.append(
    "src/app/view.mbt",
    "fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame() // det-ok(frame-request): b\n}\n",
  )
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "exceptions only go down")
  t.clear()
}

///|
test "an exception in place of a finding is taken and lowers the bar" {
  let t = Tree::new([
    ("src/app/view.mbt", "fn v(c : @ui.Ctx) -> Unit {\n  let ago = c.now() - sent\n}\n"),
  ])
  t.run(["--update"]) |> ignore
  t.write(
    "src/app/view.mbt",
    "fn v(c : @ui.Ctx) -> Unit {\n  let ago = c.now() - sent // det-ok(app-clock): shown as ago\n}\n",
  )
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "lower it")
  assert_eq(t.run(["--update"]).0, 0)
  let (code, out) = t.run([])
  if code != 0 {
    fail(out)
  }
  t.clear()
}

///|
test "marking a finding is not a way out but for app-clock" {
  let t = Tree::new([("flows/01.drive", "tap 发消息\nwait 800\n")])
  t.run(["--update"]) |> ignore
  t.write("flows/01.drive", "tap 发消息\n# det-ok(flow-wait): the list's animation\nwait 800\n")
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "exceptions only go down")
  t.run(["--update"]) |> ignore
  // --update does not take it either
  assert_eq(t.run([]).0, 1)
  t.clear()
}

///|
test "moved to another file fails" {
  let t = Tree::new(bar_files)
  t.run(["--update"]) |> ignore
  // the same two, one of them moved into another file: the total is the same, that file is over its bar
  t.write("src/app/view.mbt", "fn v(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
  t.write("src/app/other.mbt", "fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "src/app/other.mbt: 1 > 0")
  t.clear()
}

///|
test "update, then pass, then more fails, less fails" {
  let t = Tree::new(bar_files)
  // no bar yet
  assert_eq(t.run([]).0, 1)
  t.run(["--update"]) |> ignore
  let (code, out) = t.run([])
  if code != 0 {
    fail(out)
  }
  // one more: fails, and says where
  t.append("src/app/view.mbt", "fn w(c : @ui.Ctx) -> Unit {\n  c.request_frame()\n}\n")
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "src/app/view.mbt: 3 > 2")
  // --update does not raise it
  t.run(["--update"]) |> ignore
  assert_eq(t.run([]).0, 1)
  // two fewer than the bar: fails until it is lowered
  t.write("src/app/view.mbt", "fn v(c : @ui.Ctx) -> Unit {\n  c.text(\"x\")\n}\n")
  let (code, out) = t.run([])
  assert_eq(code, 1)
  assert_has(out, "lower it")
  t.run(["--update"]) |> ignore
  let (code, out) = t.run([])
  if code != 0 {
    fail(out)
  }
  assert_has(out, "forbidden")
  t.clear()
}

///|
test "host-delay" {
  found(
    [
      (
        "android/app/Views.java",
        "void ready(WebView w) {\n  Host.main.postDelayed(() -> tell(1), 1000);\n}\n",
      ),
      (
        "src/host/mac_views.m",
        "static void later(void) {\n  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500), q, ^{ go(); });\n}\n",
      ),
      (
        "src/host/linux_views.c",
        "static void later(void) {\n  g_timeout_add(500, go, NULL);\n}\n",
      ),
    ],
    "host-delay",
    3,
  )
  |> ignore
  // on the event it is for; a comment naming one; the app's own wake, said
  found(
    [
      (
        "android/app/Views.java",
        "void ready(WebView w) {\n  w.postVisualStateCallback(id, cb);\n  // postDelayed( was here\n  main.postDelayed(Host::requestFrame, ms); // det-ok(host-delay): the app's wake_after\n}\n",
      ),
    ],
    "host-delay",
    0,
  )
  |> ignore
}

///|
test "page-hand" {
  let cfg = Config::new(@rjson.parse("{\"pages\": {\"roots\": [\"src/pages\"]}}"))
  // a page reading the hand; the library's and a page's test's not counted
  found(
    [
      ("src/pages/row.mbt", "fn v() -> Unit {\n  let f = @ui.pointing() is Finger\n}\n"),
      ("src/lib/hand.mbt", "pub fn by_finger() -> Bool {\n  @ui.pointing() is Finger\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  assert_true(@ui.pointing() is Mouse)\n}\n"),
    ],
    "page-hand",
    1,
    cfg~,
  )
  |> ignore
}

///|
test "page-screen" {
  let cfg = Config::new(@rjson.parse("{\"pages\": {\"roots\": [\"src/pages\"]}}"))
  // a page reading the native input; the library's and a page's test's not counted
  found(
    [
      ("src/pages/row.mbt", "fn v() -> Unit {\n  let f = @sf.native_input()\n}\n"),
      ("src/sf/parts.mbt", "pub fn by_touch() -> Pointing {\n  @sf.native_input()\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  assert_true(@sf.native_input())\n}\n"),
    ],
    "page-screen",
    1,
    cfg~,
  )
  |> ignore
}

///|
test "tier-outside-shell" {
  let cfg = Config::new(
    @rjson.parse(
      "{\"pages\": {\"roots\": [\"src/pages\", \"src/shell\"]}, \"shell\": {\"files\": [\"src/shell/frame.mbt\"], \"reads\": [\"@sf.layout\", \"is_wide\"], \"state\": [\"wide\"]}}",
    ),
  )
  // a page reading the tier, asking the shell whether it is wide and reading its state; the shell's own, a page's test,
  // a field named so on something else and the native input's in the shell not counted
  found(
    [
      (
        "src/pages/row.mbt",
        "fn v(c : Ctx) -> Unit {\n  let l = @sf.layout(c.width)\n  if is_wide(c) && wide.tape {\n    ()\n  }\n  let x = s.wide.tape\n}\n",
      ),
      ("src/shell/frame.mbt", "fn f(c : Ctx) -> Unit {\n  let l = @sf.layout(c.width)\n  if wide.tape { @sf.native_input() |> ignore }\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  assert_true(is_wide(c))\n}\n"),
    ],
    "tier-outside-shell",
    3,
    cfg~,
  )
  |> ignore
}

///|
test "fixture-import" {
  let cfg = Config::new(
    @rjson.parse(
      "{\"pages\": {\"roots\": [\"src/app\"]}, \"library\": {\"roots\": [\"src/ui\"]}, \"fixture\": {\"package\": \"@fix\", \"openers\": [\"src/app/fixture_open.mbt\"]}}",
    ),
  )
  // a page's and the library's use of the made-up core; the opener's, a test's and a tool's not counted
  found(
    [
      ("src/app/page.mbt", "fn v() -> Unit {\n  let d = @fix.docs\n}\n"),
      ("src/ui/part.mbt", "fn p() -> Unit {\n  @fix.reset()\n}\n"),
      ("src/app/fixture_open.mbt", "fn o() -> Unit {\n  @fix.reset()\n}\n"),
      ("src/app/page_wbtest.mbt", "test \"t\" {\n  let s = @fix.core(\"home\")\n}\n"),
      ("src/tool/main.mbt", "fn main {\n  @fix.core(\"home\") |> ignore\n}\n"),
    ],
    "fixture-import",
    2,
    cfg~,
  )
  |> ignore
}

///|
test "page-old-part" {
  let cfg = Config::new(@rjson.parse("{\"pages\": {\"roots\": [\"src/pages\"], \"old_parts\": [\"button\"]}}"))
  // a page taking the settings' older button; another of their parts, the library's button and a test's not counted
  found(
    [
      ("src/pages/row.mbt", "fn v(c : Ctx) -> Unit {\n  @settings.button(c, \"k\", \"好\", true) |> ignore\n  @settings.field(c) |> ignore\n  @sf.button(c, \"好\") |> ignore\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  @settings.button(c, \"k\", \"好\", true) |> ignore\n}\n"),
    ],
    "page-old-part",
    1,
    cfg~,
  )
  |> ignore
}

///|
test "page-old-sheet" {
  let cfg = Config::new(@rjson.parse("{\"pages\": {\"roots\": [\"src/pages\"], \"old_sheets\": [\"open_sheet\"]}}"))
  // a page putting a sheet up in the old host; the host's own fn, the name not called and a test's not counted
  found(
    [
      ("src/pages/row.mbt", "fn open_sheet(h : Double) -> Unit {\n  ignore(h)\n}\nfn v() -> Unit {\n  open_sheet(0.5)\n  let f = open_sheet\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  open_sheet(0.5)\n}\n"),
    ],
    "page-old-sheet",
    1,
    cfg~,
  )
  |> ignore
}

///|
test "corners-each" {
  let cfg = Config::new(@rjson.parse("{\"pages\": {\"roots\": [\"src/pages\"]}, \"library\": {\"roots\": [\"src/lib\"]}}"))
  // corners said not alike in a page and in the library; one corner for all, a test's and another package's not counted
  found(
    [
      ("src/pages/col.mbt", "let a : Style = style(radius=Corners(12.0, 12.0, 0.0, 0.0))\nlet b : Style = style(radius=Exact(12.0))\n"),
      ("src/lib/panel.mbt", "fn f(k : CornerOf) -> Radius {\n  LinkedEach(k, k, Own(30.0), Own(30.0))\n}\n"),
      ("src/pages/col_wbtest.mbt", "test \"t\" {\n  let _ = Corners(1.0, 2.0, 3.0, 4.0)\n}\n"),
      ("src/other/x.mbt", "let c : Radius = Corners(1.0, 2.0, 3.0, 4.0)\n"),
    ],
    "corners-each",
    2,
    cfg~,
  )
  |> ignore
}

///|
test "cursor-hand" {
  // the hand said over something, as it is and in a branch; another shape and a test's not counted
  found(
    [
      ("src/pages/row.mbt", "fn v(c : Ctx, id : Int, f : Bool) -> Unit {\n  c.cursor(id, Hand)\n  c.cursor(id, ResizeX)\n  c.cursor(id, if f { @ui.Hand } else { Arrow })\n}\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  c.cursor(id, Hand)\n}\n"),
    ],
    "cursor-hand",
    2,
  )
  |> ignore
}

///|
test "page-look" {
  let cfg = Config::new(
    @rjson.parse(
      "{\"pages\": {\"roots\": [\"src/pages\"], \"frames\": [\"src/pages/frame.mbt\"], \"one_look\": [\"desk_card\", \"Narrow\"]}}",
    ),
  )
  // a page's own piece of one arrangement and its branch on one; the frame that names them, a page's test and other
  // names not counted
  found(
    [
      ("src/pages/row.mbt", "fn v(c : Ctx, l : Look) -> Unit {\n  if l == Narrow {\n    c.box(style=desk_card)\n  }\n  c.box(style=card)\n}\n"),
      ("src/pages/frame.mbt", "let desk_card : Style = @sf.desk_card\n"),
      ("src/pages/row_wbtest.mbt", "test \"t\" {\n  assert_true(look() == Narrow)\n}\n"),
    ],
    "page-look",
    2,
    cfg~,
  )
  |> ignore
}

///|
test "follow-layout" {
  // a follow of a measured size, through a name bound to one, an animate of the keyboard's; a follow of a state, a
  // layout told its cause and a test's, not counted
  let fs = found(
    [
      (
        "src/app/composer.mbt",
        "fn v(c : @ui.Ctx, a : @motion.Anim) -> Unit {\n" +
        "  a.follow(@motion.measured(c, \"box\").unwrap_or(0.0), @motion.tween(260.0))\n" +
        "  let h = c.laid_size(1).unwrap().1\n" +
        "  a.follow(h, @motion.tween(260.0))\n" +
        "  let lift = @motion.animate(c, \"lift\", c.ime_inset())\n" +
        "  let on = @motion.animate(c, \"on\", if open { 1.0 } else { 0.0 })\n" +
        "  a.follow(if open { 1.0 } else { 0.0 }, @motion.tween(140.0))\n" +
        "  @motion.layout(c, 3, \"box\", by=words)\n" +
        "}\n",
      ),
      (
        "src/app/composer_wbtest.mbt",
        "test \"t\" {\n  a.follow(@motion.measured(c, \"box\").unwrap_or(0.0), @motion.tween(260.0))\n}\n",
      ),
    ],
    "follow-layout",
    3,
  )
  assert_eq(lines(fs), [2, 4, 5])
}

///|
test "motion-spring" {
  // the app's own springs, by @motion's and a Ctx's; its presets, a test's and the framework's not counted
  let cfg = Config::new(@rjson.parse("{\"mbt\": {\"framework\": [\"src/motion\"]}}"))
  let fs = found(
    [
      (
        "src/app/sheet.mbt",
        "fn v(c : @ui.Ctx, a : @motion.Anim) -> Unit {\n" +
        "  a.animate(0.0, @motion.spring(ratio=1.0, stiffness=400.0))\n" +
        "  let k = c.spring(\"bars\", 1.0, stiffness=600.0, damping=50.0)\n" +
        "  a.animate(0.0, @motion.motion_spring(0.3, bounce=0.2))\n" +
        "  a.animate(0.0, @motion.sheet_spring)\n" +
        "}\n",
      ),
      ("src/app/sheet_wbtest.mbt", "test \"t\" {\n  a.animate(0.0, @motion.spring())\n}\n"),
      ("src/motion/spec.mbt", "pub let s : Spec = motion_spring(0.28)\n"),
    ],
    "motion-spring",
    3,
    cfg~,
  )
  assert_eq(lines(fs), [2, 3, 4])
}

///|
test "motion-read" {
  // the app reading whether a motion runs; a Tester's list of what moves, a test's and the framework's not counted
  let cfg = Config::new(@rjson.parse("{\"mbt\": {\"framework\": [\"src/motion\"]}}"))
  let fs = found(
    [
      (
        "src/app/search.mbt",
        "fn v(up : @motion.Anim, t : @ui.Tester) -> Unit {\n" +
        "  if leaving && !up.moving() {\n    close()\n  }\n" +
        "  for m in t.moving() {\n    println(m)\n  }\n" +
        "  let told = self.t.moving().iter().any(fn(l) { l.contains(\"a\") })\n" +
        "}\n",
      ),
      ("src/app/search_wbtest.mbt", "test \"t\" {\n  assert_true(up.moving())\n}\n"),
      ("src/motion/anim.mbt", "pub fn Anim::running(self : Anim) -> Bool {\n  self.moving()\n}\n"),
    ],
    "motion-read",
    1,
    cfg~,
  )
  assert_eq(lines(fs), [2])
}

///|
test "built-by-hand" {
  // the app's forgetting and its frame built again by hand; a test's and the framework's not counted
  let cfg = Config::new(@rjson.parse("{\"mbt\": {\"framework\": [\"src/ui\"]}}"))
  let fs = found(
    [
      (
        "src/app/frame.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n" +
        "  if moved { c.forget_parts() }\n" +
        "  c.built_from_changed(\"an edge dragged\")\n" +
        "  c.forget()\n" +
        "}\n",
      ),
      ("src/app/frame_wbtest.mbt", "test \"t\" {\n  c.forget_parts()\n}\n"),
      ("src/ui/kept_part.mbt", "fn w(c : Ctx) -> Unit {\n  c.forget_parts()\n}\n"),
    ],
    "built-by-hand",
    2,
    cfg~,
  )
  assert_eq(lines(fs), [2, 3])
}

///|
test "layout-read-back" {
  // what was laid out read back by the app; a test's and the framework's not counted
  let cfg = Config::new(@rjson.parse("{\"mbt\": {\"framework\": [\"src/ui\"]}}"))
  let fs = found(
    [
      (
        "src/app/card.mbt",
        "fn v(c : @ui.Ctx) -> Unit {\n" +
        "  let w = c.laid_size(id).map(fn(s) { s.0 }).unwrap_or(0.0)\n" +
        "  match c.rect_of(c.id(\"rail\")) { _ => () }\n" +
        "  let r = c.laid_rect(id)\n" +
        "  let m = @motion.measured_rect(c, \"thumb\")\n" +
        "}\n",
      ),
      ("src/app/card_wbtest.mbt", "test \"t\" {\n  t.ctx().rect_of(1)\n}\n"),
      ("src/ui/list.mbt", "fn w(c : Ctx) -> Unit {\n  c.rect_of(1) |> ignore\n}\n"),
    ],
    "layout-read-back",
    3,
    cfg~,
  )
  assert_eq(lines(fs), [2, 3, 4])
}
