// A photo grid, to try images: 3,000 cells over a few pictures (macOS's
// desktop pictures natively, JPEGs made from them on the web), in a
// virtual list of rows of three.

///|
let count = 3000

///|
fn view(c : @ui.Ctx) -> Unit {
  c.column(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(dir=Row, padx=16.0, pady=12.0, align=ACenter, bg=0xFFFFFFFFL, fn() {
      c.text("照片", size=17.0, weight=700, wrap=false) |> ignore
      c.spacer()
      c.text("\{count} 张", size=13.0, color=0x8E8E93FFL, wrap=false) |> ignore
    })
    |> ignore
    c.list("grid", (count + 2) / 3, 130.0, fn(r) {
      c.box(dir=Row, gap=2.0, pady=1.0, fn() {
        for k in 0..<3 {
          let i = r * 3 + k
          if i < count {
            c.image(
              picture(i),
              w=Fill(1.0),
              h=Px(128.0),
              radius=if i % 7 == 0 { 12.0 } else { 0.0 },
            )
            |> ignore
          } else {
            c.spacer()
          }
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
fn main {
  @ui.run("照片", view)
}
