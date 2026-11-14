// A code block as nodes (markdown_node.mbt's code_block_node) beside the old view's (markdown.mbt's code_block): its
// keys (换行, 复制) pressed as far round them as a press's room reaches, the code under them as it was; its bar's words
// at the system's size of words set to 1.3 as the old view's are.

///|
/// A block of `cb_code` in sh in a column `w` wide, the old view's (code_block) or the nodes' (code_block_node), with
/// a finger (platform 2) or a mouse (0), its words at `scale`. Drawn at rest.
fn cb_tester(nodes : Bool, w? : Double = 390.0, platform? : Int = 2, scale? : Double = 1.0, code? : String = cb_line) -> @ui.Tester {
  let t = if nodes {
    @ui.Tester::new(
      fn(c) { begin(c) |> ignore },
      tree=fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        root.box(fn(b) {
          b.padding(Is((16.0, 40.0, 16.0, 0.0))) |> ignore
          b.box(fn(k) { code_block_node(k, fn() { code }, fn() { "sh" }, fn() { None }) }) |> ignore
        })
        |> ignore
      },
      w~,
      h=400.0,
      platform~,
    )
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.box(pl=16.0, pr=16.0, pt=40.0, fn() { code_block(c, code, "sh") }) |> ignore
        })
      },
      w~,
      h=400.0,
      platform~,
    )
  }
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
// kept across runs: a value
let cb_line : String = "moon test --target native src/sf/code_block_node_wbtest.mbt"

///|
/// Words drawn and rectangles, each place and size to a hundredth of a point.
fn cb_drawn(t : @ui.Tester) -> String {
  let r = fn(x : Double) { (x * 100.0).round() / 100.0 }
  t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(d) { "\{r(d.0)},\{r(d.1)} \{r(d.2)}x\{r(d.3)} \{d.4}" }).join("\n")
}

///|
/// What `t.audit()` says of a code block but a press's room what scrolls its code is short of with a finger at the
/// default size of words (42 high, under 44): said exactly `known` times, so that once it is mended this is taken out.
/// Its keys (换行, 复制) have theirs as the hit test reaches them, over what scrolls too (the test below).
fn cb_audit(t : @ui.Tester, known : Int) -> Array[String] {
  let all = t.audit()
  let room = all.filter(fn(f) { f.has_prefix("room: ") && f.contains("sf/markdown_node.mbt") })
  let faults = all.filter(fn(f) { !room.contains(f) })
  if room.length() != known {
    faults.push("a code block's rooms short \{room.length()} times, \{known} known: " + room.join(" | "))
  }
  faults
}

///|
test "a code block's bar (its language, 换行, 复制) at the system's words set to 1.3 is drawn as the old view's, at 1 as before; a finger's and a mouse's" {
  for platform in [2, 0] {
    for scale in [1.0, 1.3] {
      let at = "platform \{platform} at \{scale}"
      let old = cb_tester(false, platform~, scale~)
      let was = cb_drawn(old)
      let t = cb_tester(true, platform~, scale~)
      assert_eq(cb_drawn(t), was, msg=at)
      // (with a finger at 1, what scrolls its code, under 44 high)
      let faults = cb_audit(t, 0)
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" || "))
    }
  }
}

///|
test "a code block's 换行 is pressed as far round it as a press's room: over it, and under it where the code is" {
  for dy in [-6.0, 26.0] {
    let t = cb_tester(true)
    let w = t.words().iter().find_first(fn(w) { w.0 == md_wrap_words(false) }).unwrap()
    assert_eq(cb_audit(t, 0), [])
    t.tap(w.1 + w.3 / 2.0, w.2 + dy)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(md_wrap_words(true)) is Some(_), msg="\{dy} from its words' top")
  }
}
