// What a person reading the screen out has of its words (Tester::words_said): the window's tree's under a modal layer
// they are not in left out, each of them by its own node, whatever else is drawn among them (a field: its placeholder
// words of its own or none), what is over them said.

///|
test "words said: under a modal layer of the window's tree, a field among them, none of theirs; the layer's own, each" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(under) {
      field(under, Field::new(), placeholder="下面的字段") |> ignore
      under.box(fn(w) { w.words(Is("下面的字")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(m) {
      m.over(Is(true)).modal(Is(true)) |> ignore
      m.box(fn(w) { w.words(Is("上面的字")) |> ignore }) |> ignore
      field(m, Field::new(), placeholder="上面的字段") |> ignore
      m.box(fn(w) { w.words(Is("上面的第二行")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  let all = t.words().map(fn(w) { w.0 })
  let said = t.words_said().map(fn(w) { w.0 })
  // (each field by its hint, under the layer and over it)
  assert_true(
    all.contains("下面的字") && all.contains("下面的字段") && all.contains("上面的字") && all.contains("上面的字段") &&
    all.contains("上面的第二行"),
    msg="\{Repr(all)}",
  )
  assert_true(!said.contains("下面的字") && !said.contains("下面的字段"), msg="\{Repr(said)}")
  assert_true(said.contains("上面的字") && said.contains("上面的字段") && said.contains("上面的第二行"), msg="\{Repr(said)}")
}
