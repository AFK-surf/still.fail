// A list's rows moving on their springs as its rows change (layout, list_keys), kept as they were drawn while nothing
// changes (mbui's kept_rows.mbt): what a row's build said is seen while it is drawn again, so a row put above them
// moves them from where they were drawn, as when every row is built every frame.

///|
/// How far apart the moments are that the rows are looked at as they move.
let kept_look_ms : Double = 50.0

///|
/// What the last frame drew (Tester::drawn_text's instances), a glyph's place in the atlas left out (the atlas fills in
/// another order where rows are built every frame: what is drawn the same).
fn kept_drawn(t : @ui.Tester) -> Array[String] {
  let out = []
  for line in t.drawn_text().split("\n") {
    if line.has_prefix("inst ") {
      let f = line.split(" ").map(fn(v) { v.to_string() }).collect()
      // ("inst", then its numbers: its kind the 6th, in 1/64ths; a glyph's atlas rect the 13th to the 16th)
      if f.length() > 16 && (f[6] == "64" || f[6] == "192" || f[6] == "448") {
        for j in 13..=16 {
          f[j] = "_"
        }
      }
      out.push(f.join(" "))
    }
  }
  out
}

///|
/// Twelve rows, kept a while, then one put above them: what is drawn at each moment after, the rows drawn again where
/// they can be (`again`) or built every frame; how many were drawn again before.
fn kept_glide(again : Bool) -> (Array[Array[String]], Int) {
  let keys = Array::makei(12, fn(i) { "r\{i}" })
  let view = fn(c : @ui.Ctx) {
    // (the keys as they are this frame: a new array once they change, as a page makes them)
    @motion.list_keys(c, "glide", keys.copy()) |> ignore
    c.list("glide", keys.length(), 40.0, fn(i) {
      let k = keys[i]
      let b = c.box(h=Px(40.0), padx=10.0, fn() { c.text(k, size=12.0) |> ignore })
      @motion.layout(c, b, "row/" + k)
    })
    |> ignore
  }
  let t = @ui.Tester::new(view, w=320.0, h=420.0, platform=2)
  t.keep_parts(true)
  t.drawn_again(again)
  t.draw()
  t.run_for(kept_look_ms)
  t.run_for(kept_look_ms)
  let kept = t.rows_kept()
  keys.insert(0, "new")
  let out = []
  for _ in 0..<8 {
    t.run_for(kept_look_ms)
    out.push(kept_drawn(t))
  }
  (out, kept)
}

///|
test "a list's rows drawn again move as a row comes in above them, as rows built every frame do" {
  let (kept, _) = kept_glide(true)
  let (built, _) = kept_glide(false)
  assert_eq(kept.length(), built.length())
  for i in 0..<kept.length() {
    let a = kept[i]
    let b = built[i]
    for j in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
      if a[j] != b[j] {
        fail("moment \{i}, instance \{j}:\n  drawn again \{a[j]}\n  built \{b[j]}")
      }
    }
    assert_eq(a.length(), b.length())
  }
  // (they moved: the last moment is not the first)
  assert_true(kept[0] != kept[kept.length() - 1])
}
