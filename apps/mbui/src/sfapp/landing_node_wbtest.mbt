// Signed in with no workspace yet as nodes (@sfpages.no_workspace_node) drawn as the old pages (@sfpages.no_workspace)
// are, over the fixture's modes: none yet, asked for a code (its field the old view's, hosted), an invitation
// waiting, an account not let in.

///|
/// What a page draws: its rects (where, how big, their colour), its glyphs' places and its shapes.
fn landing_drawn(
  t : @ui.Tester,
) -> (
  Array[(Double, Double, Double, Double, Int64)],
  Array[(Double, Double)],
  Array[(Double, Double, Double, Double, Double, Int64)],
) {
  (t.drawn_rects(), t.drawn_glyphs().map(fn(g) { (g.0, g.1) }), t.drawn_shapes())
}

///|
/// The fixture's `mode` without a workspace, a code asked for where `asked`, 390 by 844 to touch: the old pages' or the
/// nodes' (no_workspace_node). What it draws.
fn landing_case(
  node : Bool,
  mode : String,
  asked : Bool,
) -> (
  Array[(Double, Double, Double, Double, Int64)],
  Array[(Double, Double)],
  Array[(Double, Double, Double, Double, Double, Int64)],
) {
  new_run()
  let src = fixture(mode)
  @sfpages.landing_reset()
  let ws = fn() { (src.topic)("workspaces", {}).value }
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        @sfpages.no_workspace(c, src, ws(), fn() {  })
      }
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) { @sfpages.no_workspace_node(root, src, ws, fn() {  }) |> ignore })
  }
  t.draw()
  if asked {
    @sfpages.landing_asked()
    t.draw()
  }
  landing_drawn(t)
}

///|
fn landing_near(
  a : (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
  b : (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
) -> Bool {
  let n = fn(x : Double, y : Double) { (x - y).abs() <= 1.0e-9 }
  a.0.length() == b.0.length() &&
  a.0.iter().zip(b.0.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) && n(p.0.2, p.1.2) && n(p.0.3, p.1.3) && p.0.4 == p.1.4 }) &&
  a.1.length() == b.1.length() &&
  a.1.iter().zip(b.1.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) }) &&
  a.2.length() == b.2.length() &&
  a.2.iter().zip(b.2.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) && n(p.0.2, p.1.2) && n(p.0.3, p.1.3) && n(p.0.4, p.1.4) && p.0.5 == p.1.5 })
}

///|
test "no workspace yet as nodes: none yet, asked for a code, an invitation waiting, an account not let in, each drawn as the old page is" {
  let cases = [("landing", false), ("landing", true), ("landing-invited", false), ("blocked", false)]
  let seen = []
  let same = cases.map(fn(k) {
    let (old, new) = (landing_case(false, k.0, k.1), landing_case(true, k.0, k.1))
    // (asked for a code: its field an old view the tree hosts, put where it is laid out on the window's pixels (view
    // host's islands: on_pixels of its node's place, 2 a point here), what it draws so from there)
    let raw = old
    let (old, field) = if k.1 { landing_field_on_pixels(old) } else { (old, 2) }
    let near = landing_near(old, new) && field == 2
    if !near {
      let old = raw
      // (the first rect, glyph and shape apart)
      seen.push(
        "\{k}: rects \{old.0.length()}/\{new.0.length()} \{landing_first_apart(old.0, new.0)}; glyphs \{old.1.length()}/\{new.1.length()} \{landing_first_apart(old.1, new.1)}; shapes \{old.2.length()}/\{new.2.length()} \{landing_first_apart(old.2, new.2)}",
      )
    }
    near
  })
  assert_eq(same, Array::make(cases.length(), true), msg="\{seen}")
}

///|
test "no workspace yet as nodes, asked for a code: a code typed in its field, 创建 workspace pressed at once makes one with it; the code taken away again, not pressed" {
  let calls : Array[(String, Json)] = []
  new_run()
  let base = fixture("landing")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "workspace.create" => {
          calls.push((name, params))
          done(Ok({ "id": "ws9" }))
        }
        _ => (base.call)(name, params, done)
      }
    },
  }
  @sfpages.landing_reset()
  @sfpages.landing_asked()
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0, platform=2)
  @ui.set_view_app(fn(root) {
    @sfpages.no_workspace_node(root, src, fn() { (src.topic)("workspaces", {}).value }, fn() {  }) |> ignore
  })
  t.draw()
  let create = @sf.t("android-misc.workspace.create")
  // (none typed: not pressed)
  t.tap_text(create)
  t.frame()
  let none_typed = calls.length()
  t.tap_text("XXXX-XXXX-XXXX")
  t.type_text("ABCD-EFGH-IJKL")
  t.tap_text(create)
  t.frame()
  let made = calls.map(fn(c) { text(Some(c.1), "invite_code") })
  for _ in 0..<"ABCD-EFGH-IJKL".length() {
    t.backspace()
  }
  t.frame()
  t.tap_text(create)
  t.frame()
  assert_eq((none_typed, made, calls.length()), (0, ["ABCD-EFGH-IJKL"], 1))
}

///|
/// Where the button read out as `label` is, its middle (what a screen reader finds), in the last frame.
fn landing_button_at(t : @ui.Tester, label : String) -> (Double, Double) {
  match t.semantics().iter().find_first(fn(s) { s.role == Button && s.label == label }) {
    Some(s) => (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
    None => abort("no button read out as \{label}")
  }
}

///|
test "no workspace yet as nodes, asked for a code: a code the input method commits, 创建 workspace pressed and let go before any frame is drawn makes one with it then; the code taken away, before any frame, not pressed" {
  let calls : Array[(String, Json)] = []
  new_run()
  let base = fixture("landing")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "workspace.create" => {
          calls.push((name, params))
          done(Ok({ "id": "ws9" }))
        }
        _ => (base.call)(name, params, done)
      }
    },
  }
  @sfpages.landing_reset()
  @sfpages.landing_asked()
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0, platform=2)
  @ui.set_view_app(fn(root) {
    @sfpages.no_workspace_node(root, src, fn() { (src.topic)("workspaces", {}).value }, fn() {  }) |> ignore
  })
  t.draw()
  // (its field taken: what the input method commits goes there)
  t.tap_text("XXXX-XXXX-XXXX")
  let (bx, by) = landing_button_at(t, @sf.t("android-misc.workspace.create"))
  // (no frame drawn from here: each told as a host tells it, between frames)
  t.text_told("ABCD-EFGH-IJKL", t.time())
  t.touch(0, bx, by)
  t.touch(2, bx, by)
  let made = calls.map(fn(c) { text(Some(c.1), "invite_code") })
  for _ in 0..<"ABCD-EFGH-IJKL".length() {
    t.key_told(@ui.key_code_backspace, 0, t.time())
  }
  t.touch(0, bx, by)
  t.touch(2, bx, by)
  assert_eq((made, calls.length()), (["ABCD-EFGH-IJKL"], 1))
}

///|
/// The first of two lists where they differ, both of it there.
fn[T : Eq + Show] landing_first_apart(a : Array[T], b : Array[T]) -> String {
  for k in 0..<@cmp.minimum(a.length(), b.length()) {
    if a[k] != b[k] {
      return "at \{k}: old \{a[k]} node \{b[k]}"
    }
  }
  "none apart"
}

///|
/// What a page draws, the invite code's field put where the tree hosts it: an old view's island, its top left on the
/// window's pixels (2 a point: view_host's on_pixels of its node's place), all of it moved by as much. Its rects are its
/// ground and its edge, the two of the field's room (as wide as its row leaves it, 41 tall: 10 over and under its
/// line of 21) at its top left; how many were found so, and what is drawn so.
fn landing_field_on_pixels(
  d : (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
) -> (
  (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
  Int,
) {
  let field = d.0.filter(fn(r) { r.3 == 41.0 && r.2 < 330.0 && r.0 == 30.0 })
  guard field.length() > 0 else { return (d, 0) }
  let (x0, y0) = (field[0].0, field[0].1)
  let on = fn(v : Double) { (v * 2.0).round() / 2.0 }
  let (dx, dy) = (on(x0) - x0, on(y0) - y0)
  let moved = d.0.map(fn(r) { if r.3 == 41.0 && r.2 < 330.0 && r.0 == x0 && r.1 == y0 { (r.0 + dx, r.1 + dy, r.2, r.3, r.4) } else { r } })
  ((moved, d.1, d.2), field.filter(fn(r) { r.1 == y0 }).length())
}
