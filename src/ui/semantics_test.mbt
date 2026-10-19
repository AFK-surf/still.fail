///|
test "the semantics tree: widgets with their state, words named by what holds them, hidden parts left out" {
  let t = Tester::new(fn(c) {
    c.column(gap=4.0, fn() {
      c.text("Settings", size=20.0) |> ignore
      btn(c, "Save") |> ignore
      let i = c.box(id=c.id("wifi"), fn() { c.text("Wi-Fi") |> ignore })
      c.semantics(i, Switch, id=c.id("wifi"), check=On, actions=[Activate])
      let g = c.box(fn() {
        c.hidden_from_semantics(fn() { c.text("★") |> ignore })
        c.visually_hidden("Favourite")
      })
      c.semantics(g, Group, label="Stars")
      let s = c.box(w=Px(100.0), h=Px(10.0), fn() {  })
      c.semantics(s, Slider, label="Volume", range=(0.0, 30.0, 100.0), disabled=true)
    })
    |> ignore
  })
  inspect(
    t.semantics_dump(),
    content=(
      #|Text "Settings"
      #|Button "Save"
      #|Switch "Wi-Fi" checked
      #|Group "Stars"
      #|  Text "Favourite"
      #|Slider "Volume" range=0..100@30 disabled
      #|
    ),
  )
  assert_eq(t.get(Switch, label="Wi-Fi").check, Some(On))
  // none, and more than one, fail
  assert_true((try Some(t.get(Button, label="Cancel")) catch { _ => None }) is None)
  assert_true((try Some(t.get(Text)) catch { _ => None }) is None)
  assert_eq(t.all(Text).length(), 2)
}

///|
test "the theme: words, and the old button, take their colours from it unless told" {
  let t = Tester::new(fn(c) {
    c.column(fn() {
      c.text("a") |> ignore
      c.with_theme({ ..Theme::light(), fg: 0x112233FFL, accent: 0x445566FFL }, fn() {
        c.text("b") |> ignore
        c.button("c") |> ignore
      })
      c.text("d", color=0x778899FFL) |> ignore
    })
    |> ignore
  })
  let glyphs = t.drawn_glyphs()
  assert_eq(glyphs[0].2, 0x1D1D1FFFL)
  assert_eq(glyphs[1].2, 0x112233FFL)
  assert_eq(glyphs[2].2, 0xFFFFFFFFL)
  assert_eq(glyphs[3].2, 0x778899FFL)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x445566FFL }))
}

///|
test "aspect: a box's height follows its width" {
  let t = Tester::new(fn(c) {
    let i = c.box(w=Px(160.0), aspect=16.0 / 9.0, fn() {  })
    c.semantics(i, Image, label="picture")
  })
  let (_, _, w, h) = t.get(Image, label="picture").rect
  assert_eq(w, 160.0)
  assert_eq(h, 90.0)
}
