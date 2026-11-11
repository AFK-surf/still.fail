// Code's colours read by a node of the window's tree (ink_node.mbt): plain till the core says them, then the same node
// drawn in them in the first frame after the answer came, and no other; asked again as they are let go to keep the
// inks within their budget; what read them let go, nothing kept for it; the old views' read (code_ink) as before,
// making nothing of a node's.

///|
/// The core's `code.ink` as a test's: each ask kept in `asked` (its code, its language, its answer to give), answered as
/// the test says, between frames, as a core's answer comes.
fn inkn_core(asked : Array[(String, String, (String?) -> Unit)]) -> Unit {
  ink_read.val = Some(fn(code, lang, done) { asked.push((code, lang, done)) })
}

///|
/// Each of `codes` in a node of its own, in MoonBit's colours as the core says them, while `shown`; how many times each
/// node's runs were worked out counted in `made`. Drawn once; the core's asks.
fn inkn_case(
  codes : Array[String],
  shown : () -> Bool,
  made : Array[Int],
) -> (@ui.Tester, Array[(String, String, (String?) -> Unit)]) {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=400.0)
  let asked = []
  inkn_core(asked)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    for k, code in codes {
      root.box(fn(b) {
        b.show(shown, fn(n) {
          let ink = code_ink_node(n, fn() { code }, fn() { "moonbit" })
          n
          .words_runs(By(fn() {
            made[k] = made[k] + 1
            match ink() {
              Some(Some(i)) => ink_runs(code, i, theme().dark)
              _ => [@ui.span(code, mono=true)]
            }
          }))
          |> ignore
        })
      })
      |> ignore
    }
  })
  t.draw()
  (t, asked)
}

///|
/// The colour of each run of the words `code` drawn now ([] where they are not).
fn inkn_colours(code : String) -> Array[Int64] {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.runs.length() > 0 && d.runs.map(fn(r) { r.text }).join("") == code {
      return d.runs.map(fn(r) { r.color })
    }
  }
  []
}

///|
/// The fixture's code and what each piece of it is (`let`, a name, `=`, a number), as the core's `code.ink` says it.
// kept across runs: a value
let inkn_a : String = "let a = 1"

///|
// kept across runs: a value
let inkn_b : String = "let b = 2"

///|
// kept across runs: a value
let inkn_said : String = "h3ajacaf"

///|
test "code's colours read by a node: plain till the core says them, then that node in them in the first frame after; the other's not worked out again" {
  let made = [0, 0]
  let (t, asked) = inkn_case([inkn_a, inkn_b], fn() { true }, made)
  // (each asked once, as its node was made)
  assert_eq(asked.map(fn(a) { (a.0, a.1) }), [(inkn_a, "moonbit"), (inkn_b, "moonbit")])
  assert_eq(inkn_colours(inkn_a), [0L])
  assert_eq(inkn_colours(inkn_b), [0L])
  let before = made.copy()
  // (the core's answer for the first, between frames)
  (asked[0].2)(Some(inkn_said))
  assert_eq(made, before, msg="nothing worked out before the frame")
  t.draw()
  assert_eq(made, [before[0] + 1, before[1]], msg="that node alone, once")
  let said = ink_runs(inkn_a, inkn_said, theme().dark).map(fn(r) { r.color })
  assert_true(said.length() > 1 && said.iter().all(fn(c) { c != 0L }), msg="\{Repr(said)}")
  assert_eq(inkn_colours(inkn_a), said)
  assert_eq(inkn_colours(inkn_b), [0L])
  // (asked no more: it is here)
  assert_eq(asked.length(), 2)
  t.draw()
  assert_eq(made, [before[0] + 1, before[1]], msg="nothing again")
  assert_eq(t.audit(), [])
}

///|
test "code's colours let go to keep the inks within their budget: the node reading them told, plain, and asks the core again" {
  let made = [0]
  let (t, asked) = inkn_case([inkn_a], fn() { true }, made)
  (asked[0].2)(Some(inkn_said))
  t.draw()
  let said = ink_runs(inkn_a, inkn_said, theme().dark).map(fn(r) { r.color })
  assert_eq(inkn_colours(inkn_a), said)
  // (another's kept, as long as all of the budget: the first let go)
  ink_keep("text\u{1}" + String::make(inks_budget, 'x'), None)
  t.draw()
  assert_eq(inkn_colours(inkn_a), [0L])
  assert_eq(asked.map(fn(a) { a.0 }), [inkn_a, inkn_a], msg="asked again, once")
  (asked[1].2)(Some(inkn_said))
  t.draw()
  assert_eq(inkn_colours(inkn_a), said)
  assert_eq(t.audit(), [])
}

///|
test "code's colours no node reads any more: what told it let go as they come, nothing worked out for it" {
  let shown = @signals.signal(true)
  let made = [0]
  let (t, asked) = inkn_case([inkn_a], fn() { shown.get() }, made)
  let key = "moonbit\u{1}" + inkn_a
  assert_true(inks_told.contains(key))
  shown.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(inkn_colours(inkn_a), [])
  let before = made.copy()
  // (the answer comes after the node has gone: kept, told to none)
  (asked[0].2)(Some(inkn_said))
  t.draw()
  assert_true(!inks_told.contains(key))
  assert_eq(inks.get(key), Some(Some(inkn_said)))
  assert_eq(made, before)
  assert_eq(t.audit(), [])
}

///|
test "the old views' read of code's colours asks, keeps and gives them as before, making nothing of a node's" {
  let seen : Ref[String??] = Ref(None)
  let asked = []
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      // (the core as the run's first frame is built: Tester::new resets what was bound before it)
      if ink_read.val is None {
        inkn_core(asked)
      }
      seen.val = code_ink(c, inkn_a, "moonbit")
    },
    w=400.0,
    h=400.0,
  )
  // (asked once, as its first frame was built; nothing here yet)
  assert_eq(asked.length(), 1)
  assert_true(seen.val is None)
  t.draw()
  assert_eq(asked.length(), 1)
  assert_true(inks_told.is_empty())
  (asked[0].2)(Some(inkn_said))
  t.draw()
  assert_eq(seen.val, Some(Some(inkn_said)))
  assert_eq(asked.length(), 1)
  assert_true(inks_told.is_empty())
}
