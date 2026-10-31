// What the hand changes, measured of the window's tree's nodes too (hand_moves.mbt): a node that reads the pointer or
// the press (View::pointed, View::pressed) and is set otherwise for it found, by its own identity, its words set
// otherwise, it taller or moved; one only drawn otherwise (its ground, its ink) not; the tree's hand as it was after.

///|
/// Words set bigger, on a taller line.
let hand_big : @view.WordsLook = { size: 18.0, weight: 400, line: 26.0, wrap: true }

///|
/// A tree of buttons (taking presses, read out): `grow`, its words set bigger while pointed at; `ink`, its ground
/// another while pointed at; `held`, its words on a taller line while pressed; `before`, a line shown before `after`
/// while `after` is pointed at; `weighed bold`, of a set size, its piece `bold` set heavier while pointed at, and
/// `inked run`, its piece `run` another ink; `split same`, its pieces cut otherwise, each in the weight it was;
/// `展开`, of a set size, saying `展开详情` while pointed at; `nudged`, drawn further down while pointed at; and an old view's box beside
/// them.
fn hand_tree() -> Tester {
  let t = Tester::new(fn(_c) {  }, w=600.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(120.0)))
      .on_press(fn() {  })
      .words(Is("grow"))
      .words_look(By(fn() { if b.pointed() { hand_big } else { @view.words_plain } }))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(120.0)))
      .on_press(fn() {  })
      .words(Is("ink"))
      .ground(By(fn() { if b.pointed() { 0x112233FFL } else { 0L } }))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(120.0)))
      .on_press(fn() {  })
      .words(Is("held"))
      .words_look(By(fn() { if b.pressed() { hand_big } else { @view.words_plain } }))
      |> ignore
    })
    |> ignore
    root.box(fn(col) {
      // (a signal: the line before it made before it is, shown once it is there and pointed at)
      let after : @signals.Signal[@view.View?] = @signals.signal(None, same=fn(_, _) { false })
      col.show(fn() {
        match after.get() {
          Some(v) => @view.View::pointed(v)
          None => false
        }
      }, fn(v) { v.words(Is("before")) |> ignore })
      col.box(fn(b) {
        after.set(Some(b))
        b.width(Is(Some(120.0))).on_press(fn() {  }).words(Is("after")) |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(col) {
      col.box(fn(b) {
        b
        .width(Is(Some(120.0)))
        .height(Is(Some(22.0)))
        .on_press(fn() {  })
        .words_runs(By(fn() { [@view.words_run("weighed "), @view.words_run("bold", weight=if b.pointed() { 600 } else { 400 })] }))
        |> ignore
      })
      |> ignore
      col.box(fn(b) {
        b
        .width(Is(Some(120.0)))
        .height(Is(Some(22.0)))
        .on_press(fn() {  })
        .words_runs(By(fn() { [@view.words_run("inked "), @view.words_run("run", ink=if b.pointed() { 0x2255AAFFL } else { 0L })] }))
        |> ignore
      })
      |> ignore
      col.box(fn(b) {
        b
        .width(Is(Some(120.0)))
        .height(Is(Some(22.0)))
        .on_press(fn() {  })
        .words_runs(By(fn() {
          if b.pointed() {
            [@view.words_run("sp"), @view.words_run("lit ", weight=400), @view.words_run("same")]
          } else {
            [@view.words_run("split "), @view.words_run("same")]
          }
        }))
        |> ignore
      })
      |> ignore
      col.box(fn(b) {
        b
        .width(Is(Some(120.0)))
        .height(Is(Some(22.0)))
        .on_press(fn() {  })
        .words(By(fn() { if b.pointed() { "展开详情" } else { "展开" } }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(col) {
      col.box(fn(b) {
        b
        .width(Is(Some(120.0)))
        .on_press(fn() {  })
        .words(Is("nudged"))
        .offset(By(fn() { if b.pointed() { (0.0, 3.0) } else { (0.0, 0.0) } }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(120.0))).height(Is(Some(40.0))) |> ignore
      old(v, fn(c) { c.box(w=Px(80.0), h=Px(30.0), id=c.id("old"), label="旧的", fn() {  }) |> ignore })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "hand moves of the window's tree: words set bigger while pointed at, on a taller line while pressed, a line shown before one while it is pointed at, a piece of words set heavier and words drawn further down while pointed at, each told; a ground, a piece's ink another, pieces cut otherwise, other words of a set size while pointed at not" {
  let t = hand_tree()
  let faults = t.hand_moves()
  let says = fn(w : String) { faults.iter().any(fn(f) { f.contains("「" + w + "」") }) }
  assert_eq(
    (
      says("grow"),
      says("held"),
      says("after"),
      says("weighed bold"),
      says("nudged"),
      says("ink"),
      says("before"),
      says("inked run"),
      says("split same"),
      says("展开") || says("展开详情"),
    ),
    (true, true, true, true, true, false, false, false, false, false),
    msg=faults.join("\n"),
  )
}

///|
test "hand moves of the window's tree: the hand as it was once measured, nothing pointed at nor pressed, each node as it was" {
  let t = hand_tree()
  let before = view_tree().unwrap().hand_nodes()
  t.hand_moves() |> ignore
  t.draw()
  let tree = view_tree().unwrap()
  let after = tree.hand_nodes()
  let sizes = fn(ns : Array[@view.HandNode]) { ns.map(fn(n) { (n.key, n.y, n.h, n.size, n.weights, n.line) }) }
  assert_eq((tree.pointed, tree.pressing, sizes(after)), (None, None, sizes(before)))
}
