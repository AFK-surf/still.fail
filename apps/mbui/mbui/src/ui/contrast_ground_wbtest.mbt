///|
test "a shape with words over it is their ground, asked nothing; with none, a mark of its own, asked" {
  // (still.fail's chat find: a highlighter's swipe behind the word found, a yellow at 70% on a white page, 1.13 to 1)
  let swipe = [([0.0, 0.0, 60.0, 1.0, 58.0, 18.0, 2.0, 17.0], true)]
  let scribble = [([2.0, 16.0, 4.0, 2.0, 6.0, 16.0, 8.0, 2.0, 10.0, 16.0, 12.0, 2.0, 14.0, 16.0, 58.0, 2.0], false)]
  for shape in [shape_of(swipe, fill=0xFFF12DB3L), shape_of(scribble, stroke=0xFFF12DB3L, width=3.0)] {
    for words in [true, false] {
      let t = Tester::new(
        fn(c) {
          c.box(w=Px(300.0), h=Px(100.0), bg=0xFFFFFFFFL, fn() {
            c.box(w=Px(60.0), h=Px(24.0), fn() {
              c.layer(fn() {
                c.box(ty=3.0, fn() { c.shapes([shape], w=Px(60.0), h=Px(18.0)) |> ignore })
                |> ignore
              })
              |> ignore
              // (the words over it: a layer after its)
              if words {
                c.layer(fn() { c.text("找到的词", size=14.0, line=24.0) |> ignore }) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        },
        w=300.0,
        h=100.0,
      )
      let faults = t.contrast_faults()
      if words {
        assert_eq(faults, [])
      } else {
        assert_true(faults.length() > 0, msg="a faint swipe with no words on it is a mark of its own")
      }
    }
  }
}
