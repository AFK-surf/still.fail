// The census counted of the window's tree's nodes too (census.mbt, Tree::styled): their words' sizes, lines, weights
// and inks (each piece's that says something, the node's where a piece says none), their paddings and gaps, corners
// and grounds, as each is set; an old view's beside them as before.

///|
test "census: the window's tree's nodes counted with an old view's" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card.pad(Is(7.0)).gap(Is(5.0)).radius(Is(9.0)).ground(Is(0xABCDEFFFL)) |> ignore
      card.box(fn(w) {
        w.words(Is("words"), ink=0x123456FFL, look={ size: 19.0, weight: 700, line: 27.0, wrap: true }) |> ignore
      })
      |> ignore
      card.box(fn(r) {
        r.words_runs(Is([@view.words_run("a "), @view.words_run("b", weight=500, ink=0x654321FFL)])) |> ignore
      })
      |> ignore
      // (an empty piece's weight and ink, and the node's ink where every piece says its own: none of it drawn)
      card.box(fn(r) {
        r
        .words_runs(
          Is([@view.words_run("c", ink=0x111111FFL), @view.words_run("", weight=900, ink=0x999999FFL)]),
          ink=0x777777FFL,
        )
        |> ignore
      })
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(100.0))).height(Is(Some(40.0))) |> ignore
        old(v, fn(c) { c.box(w=Px(80.0), h=Px(30.0), radius=3.0, bg=0x0F0F0FFFL, fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let k = t.census()
  let has = fn(vs : Array[String], v : String) { vs.contains(v) }
  assert_eq(
    (
      has(k.text, "19/27"),
      has(k.weight, "700"),
      has(k.weight, "500"),
      has(k.space, "7"),
      has(k.space, "5"),
      has(k.radius, "9"),
      has(k.color, "ABCDEFFF"),
      has(k.color, "123456FF"),
      has(k.color, "654321FF"),
      has(k.radius, "3"),
      has(k.color, "0F0F0FFF"),
      has(k.color, "111111FF"),
      has(k.weight, "900"),
      has(k.color, "999999FF"),
      has(k.color, "777777FF"),
    ),
    (true, true, true, true, true, true, true, true, true, true, true, true, false, false, false),
    msg=[k.text, k.weight, k.space, k.radius, k.color].map(fn(v) { v.join(" ") }).join("\n"),
  )
}
