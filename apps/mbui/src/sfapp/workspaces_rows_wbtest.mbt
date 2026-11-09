// The workspace sheet's rows (sfpages workspace.mbt workspaces_list): the one in use on its card, the others, 登录其他账号
// and 新建 workspace: their marks in one column and their words on one line (2026-11-07: the card's row stood 16
// further in, an action's words 4 less far than a workspace's).

///|
test "the workspace sheet: every row's mark in one column and its words on one line, on the card or not" {
  let t = native_chat(466.0, 678.0, true, side=70.0)
  @sfpages.open_workspaces(fixture("chat"), At(32.0, 16.0, 150.0, 38.0))
  t.run_for(@ui.move_most_ms)
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog }) is Some(sheet) else {
    fail("no sheet")
  }
  let (sx, sy, sw, sh) = sheet.rect
  let within = fn(x : Double, y : Double) { x >= sx && x <= sx + sw && y >= sy && y <= sy + sh }
  let names = ["星火工作室", "个人", @sf.t("android-misc.workspace.addAccount"), @sf.t("android-misc.workspace.new")]
  let xs : Array[Double] = []
  for n in names {
    guard t.words().iter().find_first(fn(w) { w.0 == n && within(w.1, w.2) }) is Some(w) else { fail("no \{n} in the sheet") }
    xs.push(w.1)
  }
  for i, x in xs {
    assert_eq(x, xs[0], msg="\{names[i]} at \{x}, \{names[0]} at \{xs[0]}")
  }
  // their marks: the squares before them, one column
  let leads = t.boxes().filter(fn(b) { b.w == 24.0 && b.h == 24.0 && within(b.x, b.y) })
  assert_eq(leads.length(), names.length(), msg="\{leads.length()} marks")
  for b in leads {
    assert_eq(b.x, leads[0].x)
  }
}
