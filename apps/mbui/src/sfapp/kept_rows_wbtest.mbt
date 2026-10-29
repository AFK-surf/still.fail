// A chat's messages kept as they were drawn as they scroll (mbui's kept_rows.mbt): what is drawn at each moment is
// what building every row draws, on 小屏 and on 中屏's tape.

///|
/// How far apart the moments are that the messages are looked at.
let kept_rows_step_ms : Double = 120.0

///|
/// A long chat's messages dragged back through and flung, then dragged the other way: what is drawn at each moment
/// after (its instances), and how many rows were drawn again then; the rows drawn again where they can be (`again`) or
/// built every frame.
fn kept_rows_scrolled(again : Bool, w : Double, h : Double, a11y? : Bool = false) -> (Array[Array[String]], Int) {
  let t = kept_rows_open("chat-long", w, h)
  t.keep_parts(true)
  t.drawn_again(again)
  t.set_a11y(a11y)
  t.said() |> ignore
  let out = []
  let mut kept = 0
  let x = w * 0.7
  t.drag(x, h * 0.25, x, h * 0.75, steps=8)
  for _ in 0..<6 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0) + kept_rows_read_out(t, a11y) + kept_rows_said(t))
    kept = kept + t.rows_kept()
  }
  t.drag(x, h * 0.7, x, h * 0.4, steps=12)
  for _ in 0..<4 {
    t.run_for(kept_rows_step_ms)
    out.push(drawn_from(t, -1000.0) + kept_rows_read_out(t, a11y) + kept_rows_said(t))
    kept = kept + t.rows_kept()
  }
  (out, kept)
}

///|
/// What the last frame's paint said of it besides its drawing (its targets, what scrolls, the words that can be picked,
/// the scroll bars, the lines of words: Tester::said), a line each.
fn kept_rows_said(t : @ui.Tester) -> Array[String] {
  t.said().split("\n").filter(fn(l) { l.length() > 0 }).map(fn(l) { "said " + l.to_string() }).collect()
}

///|
/// What the host's accessibility was last told the widgets are, a line each (`a11y`: something reads them out; none
/// else). A node's number, what holds it and its widget's id are said by where they are among the lines: ids are the
/// run's own (a second run of the same steps in one test builds its page in another scope).
fn kept_rows_read_out(t : @ui.Tester, a11y : Bool) -> Array[String] {
  if !a11y {
    return []
  }
  let lines : Array[Array[String]] = []
  for l in t.a11y_said().split("\n") {
    if l.length() > 0 {
      lines.push(l.split("\u{1F}").map(fn(v) { v.to_string() }).collect())
    }
  }
  let at : Map[String, Int] = {}
  for k, f in lines {
    at[f[0]] = k
  }
  lines.mapi(fn(k, f) {
    let g = f.copy()
    g[0] = k.to_string()
    if g.length() > 2 {
      g[1] = match at.get(f[1]) {
        Some(p) => p.to_string()
        None => "-"
      }
      g[2] = if f[2] == "0" { "0" } else { "id" }
    }
    "a11y " + g.join("|")
  })
}

///|
/// An instance as `drawn_from` says it, a glyph's place in the atlas left out (the atlas fills in another order where
/// rows are built every frame: what is drawn the same).
fn kept_rows_inst(line : String) -> String {
  let f = line.split(" ").map(fn(v) { v.to_string() }).collect()
  // ("inst", then its numbers: its kind the 6th, in 1/64ths; a glyph's atlas rect the 13th to the 16th)
  if f.length() > 16 && f[0] == "inst" && (f[6] == "64" || f[6] == "192" || f[6] == "448") {
    for j in 13..=16 {
      f[j] = "_"
    }
  }
  f.join(" ")
}

///|
/// The two runs drew the same at each moment: the first line apart said where it is.
fn kept_rows_same(kept : Array[Array[String]], built : Array[Array[String]]) -> Unit raise {
  assert_eq(kept.length(), built.length())
  for i in 0..<kept.length() {
    let a = kept[i]
    let b = built[i]
    for j in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
      if kept_rows_inst(a[j]) != kept_rows_inst(b[j]) {
        fail("moment \{i}, instance \{j} of \{a.length()} drawn again, \{b.length()} built:\n  again \{a[j]}\n  built \{b[j]}")
      }
    }
    if a.length() != b.length() {
      fail("moment \{i}: \{a.length()} instances drawn again, \{b.length()} built")
    }
  }
}

///|
test "a long chat's messages scrolled on 小屏: drawn again as building them draws them" {
  let (kept, n) = kept_rows_scrolled(true, 390.0, 844.0)
  let (built, _) = kept_rows_scrolled(false, 390.0, 844.0)
  assert_true(n > 0, msg="rows drawn again: \{n}")
  kept_rows_same(kept, built)
}

///|
test "a long chat's messages scrolled on 中屏's tape: drawn again as building them draws them" {
  let (kept, n) = kept_rows_scrolled(true, 720.0, 800.0)
  let (built, _) = kept_rows_scrolled(false, 720.0, 800.0)
  assert_true(n > 0, msg="rows drawn again: \{n}")
  kept_rows_same(kept, built)
}

///|
test "a long chat's messages scrolled on 大屏: drawn again as building them draws them" {
  let (kept, n) = kept_rows_scrolled(true, 1280.0, 800.0)
  let (built, _) = kept_rows_scrolled(false, 1280.0, 800.0)
  assert_true(n > 0, msg="rows drawn again: \{n}")
  kept_rows_same(kept, built)
}

///|
test "a long chat's messages scrolled on 小屏, read out: drawn again and read out as building them draws and says them" {
  let (kept, n) = kept_rows_scrolled(true, 390.0, 844.0, a11y=true)
  let (built, _) = kept_rows_scrolled(false, 390.0, 844.0, a11y=true)
  assert_true(n > 0, msg="rows drawn again: \{n}")
  kept_rows_same(kept, built)
}
