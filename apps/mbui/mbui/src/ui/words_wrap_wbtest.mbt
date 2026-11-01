// Words of the window's tree in what is as wide as they need, as an old view's are (leaf_size): broken onto more lines
// than their own where the room offered runs out, as wide as that room; broken only at their own new lines, or not at
// all, as wide as their widest line. Words, and words in pieces (View::words_runs).

///|
/// Words `s` in a box of their own in a column 200 wide, in its middle, as one piece or as pieces (`runs`): how wide and
/// tall the words are laid out.
fn wrap_case(s : String, runs : Bool) -> (Double, Double) {
  let made : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(wrap_column))).lines_up(Is(Some(Middle))) |> ignore
      col.box(fn(b) {
        b.box(fn(w) {
          made.val = Some(w)
          if runs {
            w.words_runs(Is(s.split("|").map(fn(p) { ({ text: p.to_string(), weight: 0, ink: 0L } : @view.WordsRun) }).collect())) |> ignore
          } else {
            w.words(Is(s)) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  match view_tree().unwrap().drawn_of(made.val.unwrap().id()) {
    Some(d) => (d.w, d.h)
    None => (-1.0, -1.0)
  }
}

///|
/// The column's width (wrap_case's).
let wrap_column : Double = 200.0

///|
test "words broken where the room runs out: as wide as the room; broken only at their own new lines, or fitting: as wide as their widest line; one piece or many" {
  let seen = [false, true].map(fn(runs) {
    let long = if runs { "一段很长很长的话，|在两百点宽的一列里|放不下，要折到下一行去" } else { "一段很长很长的话，在两百点宽的一列里放不下，要折到下一行去" }
    let own = if runs { "短的\n|一行" } else { "短的\n一行" }
    let fits = if runs { "短|的" } else { "短的" }
    let (lw, lh) = wrap_case(long, runs)
    let (ow, oh) = wrap_case(own, runs)
    let (fw, fh) = wrap_case(fits, runs)
    (lw == wrap_column && lh > fh * 1.5, ow < wrap_column && oh > fh * 1.5, fw < wrap_column && fw > 0.0)
  })
  assert_eq(seen, [(true, true, true), (true, true, true)])
}
