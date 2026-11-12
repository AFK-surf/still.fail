// Signed in with no workspace yet as nodes (@sfpages.no_workspace_node), over the fixture's modes: none yet, asked for
// a code (its field the old view's, hosted), an invitation waiting, an account not let in.

///|
/// The fixture's `mode` without a workspace, a code asked for where `asked`, 390 by 844 to touch, as nodes
/// (no_workspace_node). The Tester.
fn landing_case(mode : String, asked : Bool) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  @sfpages.landing_reset()
  let ws = fn() { src.topic("workspaces", {}).get().value }
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) { @sfpages.no_workspace_node(root, src, ws, fn() {  }) |> ignore })
  t.draw()
  if asked {
    @sfpages.landing_asked()
    t.draw()
  }
  t
}

///|
/// Each mode without a workspace with its title found drawn, as landing_case opens it, and each as it should be (all
/// found): the words of each title read in that mode's own run, once it has begun (read before, they are the run
/// before's, in its language: read_after_run_wbtest.mbt).
fn landing_titles() -> (Array[(String, Bool, Bool)], Array[(String, Bool, Bool)]) {
  let cases : Array[(String, Bool, () -> String)] = [
    ("landing", false, fn() { @sf.t("android-misc.workspace.none") }),
    ("landing", true, fn() { @sf.t("android-misc.invite.onlyInvited", args=[("app", "still.fail")]) }),
    ("landing-invited", false, fn() { @sf.t("android-misc.invite.received") }),
    ("blocked", false, fn() { "此账号暂未开放测试版" }),
  ]
  let seen = cases.map(fn(k) {
    let t = landing_case(k.0, k.1)
    (k.0, k.1, t.find((k.2)()) is Some(_) && t.drawn_glyphs().length() > 0)
  })
  (seen, cases.map(fn(k) { (k.0, k.1, true) }))
}

///|
test "no workspace yet as nodes: none yet, asked for a code, an invitation waiting, an account not let in, each its title" {
  let (seen, all) = landing_titles()
  assert_eq(seen, all)
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
    @sfpages.no_workspace_node(root, src, fn() { src.topic("workspaces", {}).get().value }, fn() {  }) |> ignore
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
    None => @halt.saying("no button read out as \{label}")
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
    @sfpages.no_workspace_node(root, src, fn() { src.topic("workspaces", {}).get().value }, fn() {  }) |> ignore
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

