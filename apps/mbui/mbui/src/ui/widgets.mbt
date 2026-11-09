///|
fn shade(c : Int64, f : Double) -> Int64 {
  let r = ((c >> 24) & 0xFFL).to_double()
  let g = ((c >> 16) & 0xFFL).to_double()
  let b = ((c >> 8) & 0xFFL).to_double()
  let a = c & 0xFFL
  let ch = fn(v : Double) -> Int64 { dclamp(v * f, 0.0, 255.0).to_int().to_int64() }
  (ch(r) << 24) | (ch(g) << 16) | (ch(b) << 8) | a
}

///|
/// A button, in the theme's accent unless `bg`; `on_press`: what pressing it does, as it is let go (Ctx::on_press).
pub fn Ctx::button(
  self : Ctx,
  label : String,
  key? : String = "",
  bg? : Int64,
  color? : Int64,
  w? : Size = Auto,
  on_press? : () -> Unit,
) -> Unit {
  let bg = bg.unwrap_or(self.theme.accent)
  let color = color.unwrap_or(self.theme.on_accent)
  let id = self.id(if key == "" { label } else { key })
  match on_press {
    Some(f) => self.on_press(id, f)
    None => ()
  }
  let pressed = self.pressed(id)
  let fill = if pressed {
    shade(bg, 0.82)
  } else if self.lit(id) {
    shade(bg, 0.93)
  } else {
    bg
  }
  let s = self.spring("btn-scale", if pressed { 1.0 } else { 0.0 })
  self.box(
    dir=Row,
    w~,
    padx=16.0,
    pady=9.0,
    align=ACenter,
    justify=JCenter,
    bg=fill,
    radius=10.0,
    ty=s * 1.5,
    id~,
    fn() { self.text(label, size=15.0, weight=600, color~, wrap=false) |> ignore },
  )
  |> ignore
}

///|
/// Tabs with an indicator that slides between them on a spring, `selected` the one picked; `on_pick`: what choosing one
/// does, given its index, as it is pressed (Ctx::on_press).
pub fn Ctx::segmented(
  self : Ctx,
  key : String,
  labels : Array[String],
  selected : Int,
  item_w? : Double = 76.0,
  on_pick~ : (Int) -> Unit,
) -> Unit {
  let sel = selected
  let base = self.id(key)
  for i, _ in labels {
    self.on_press(mix(base, i + 1), fn() { on_pick(i) })
  }
  let x = self.spring(key, sel.to_double() * item_w)
  self.box(
    dir=Row,
    pad=3.0,
    bg=self.theme.faint,
    radius=10.0,
    fn() {
      // the indicator sits in a zero-width box, under the tabs that follow
      self.box(
        w=Px(0.0),
        h=Px(30.0),
        fn() {
          self.box(
            w=Px(item_w),
            h=Px(30.0),
            bg=if self.theme.dark { 0x636366FFL } else { 0xFFFFFFFFL },
            radius=8.0,
            shadow=6.0,
            tx=x,
            fn() {  },
          )
          |> ignore
        },
      )
      |> ignore
      self.box(
        dir=Row,
        fn() {
          for i, l in labels {
            self.box(
              w=Px(item_w),
              h=Px(30.0),
              align=ACenter,
              justify=JCenter,
              id=mix(base, i + 1),
              fn() {
                self.text(
                  l,
                  size=13.0,
                  weight=if i == sel { 600 } else { 400 },
                  wrap=false,
                )
                |> ignore
              },
            )
            |> ignore
          }
        },
      )
      |> ignore
    },
  )
  |> ignore
}
