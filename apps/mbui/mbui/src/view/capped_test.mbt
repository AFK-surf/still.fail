// One line of words in a column, no width said (Tree::capped_applied, an old view's `capped`): no wider than the
// column, cut short there; a most said held to the column's width where it has less (Within); in a row, said a width
// or wrapped, as wide as it is or as said. The same node told otherwise, as it changes; past a slot (show's) alike.

///|
/// Words 210 wide on one line (30 characters, 7 each, as words_measure counts them: wrapped where they say so), in a box
/// 100 wide that is a row as `row` says, with a width and a most as `width` and `most` say, wrapping as `wrap` says;
/// `shown`, made by a show in the box (past its slot). How wide they are drawn.
fn capped_tree(
  row : @signals.Signal[Bool],
  width : @signals.Signal[Double?],
  most : @signals.Signal[Double?],
  wrap : @signals.Signal[Bool],
  shown? : Bool = false,
) -> () -> Double {
  let id : Ref[@view.NodeId?] = Ref(None)
  let words = fn(w : @view.View) {
    id.val = Some(w.id())
    w
    .words(Is("abcdefghijklmnopqrstuvwxyz0123"))
    .words_look(By(fn() { { ..@view.words_plain, wrap: wrap.get() } }))
    .width(By(fn() { width.get() }))
    .max_width(By(fn() { most.get() }))
    |> ignore
  }
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(c) {
        c.width(Is(Some(100.0))).lines_up(Is(Some(Start))).row(By(fn() { row.get() })) |> ignore
        if shown {
          c.show(fn() { true }, words)
        } else {
          c.box(words) |> ignore
        }
      })
      |> ignore
    },
    // (on one line as wide as all of them, as a host measures words that do not wrap)
    measure=fn(s, look, w, k) { if look.wrap { @view.words_measure(s, look, w, k) } else { (s.length().to_double() * 7.0, 18.0) } },
    time=fn() { 0.0 },
  )
  fn() {
    t.frame(390.0, 844.0) |> ignore
    match t.drawn().search_by(fn(d) { Some(d.id) == id.val }) {
      Some(i) => t.drawn()[i].w
      None => -1.0
    }
  }
}

///|
test "one line of words in a column: as wide as the column; a most said, that where the column has more, the column's where it has less; said none again, the column's; in a row, said a width or wrapped, as it is; past a slot alike" {
  for shown in [false, true] {
    let row = @signals.signal(false)
    let width : @signals.Signal[Double?] = @signals.signal(None)
    let most : @signals.Signal[Double?] = @signals.signal(None)
    let wrap = @signals.signal(false)
    let w = capped_tree(row, width, most, wrap, shown~)
    let seen = []
    seen.push(w())
    most.set(Some(150.0))
    seen.push(w())
    most.set(Some(80.0))
    seen.push(w())
    most.set(None)
    seen.push(w())
    row.set(true)
    seen.push(w())
    row.set(false)
    seen.push(w())
    width.set(Some(180.0))
    seen.push(w())
    width.set(None)
    wrap.set(true)
    seen.push(w())
    wrap.set(false)
    seen.push(w())
    // (column 100: 100; most 150: 100; most 80: 80; none again: 100; a row: 210; a column again: 100; 180 said: 180;
    // wrapped: within the column; one line again: 100)
    assert_eq(seen, [100.0, 100.0, 80.0, 100.0, 210.0, 100.0, 180.0, 100.0, 100.0], msg="shown \{shown}: \{Repr(seen)}")
  }
}

