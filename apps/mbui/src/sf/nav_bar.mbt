// A page's compact bar, the one every pushed page of the phone has (Android Parts.kt NavBar, web mobile/parts.css.ts
// mNavbar): back with where it goes, in the accent, at its start; a centred title (and a line under it, `sub`); what
// it does at its end. The back word, the title's first line and what is at the end share one 32 line at the bar's top,
// each in its middle; a title's second line hangs below it, the bar taller by it. (NavBar sets the title's line 30, 1
// higher, to stand on the back word's baseline, with 2 under it: on the Mac's text its letters then stood 1 over the
// back word's. Here the title's line is the 32 and nothing under it: the line under the title and the bar's height
// are NavBar's.) The title is in the middle of the bar inside its padding (10 at the start, 16 at the end) and keeps 84 clear
// at either side.

///|
/// Back, in the accent: a chevron and where to (Parts.kt NavBack); its word no wider than `max_w` when it is said.
/// True on the frame after it was tapped.
pub fn nav_back(c : @ui.Ctx, key : String, label : String, max_w? : Double = 0.0) -> Bool {
  let t = theme()
  let id = c.id(key)
  c.box(
    dir=Row,
    pr=6.0,
    pt=4.0,
    pb=4.0,
    radius=8.0,
    align=ACenter,
    opacity=if c.pressed(id) { 0.6 } else { 1.0 },
    id~,
    fn() {
      icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
      if max_w > 0.0 {
        c.box(max_w~, fn() {
          c.text(label, size=17.0, color=t.p.accent, wrap=false) |> ignore
        })
        |> ignore
      } else {
        c.text(label, size=17.0, color=t.p.accent, wrap=false) |> ignore
      }
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// The bar (NavBar): back (`back_key` its id, `back` its word, `back_max` how wide the word may be), `title` in the
/// middle and `sub` under it, `trailing` at the end; on `bg` when it is said. True on the frame after back was tapped.
pub fn nav_bar(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  trailing? : () -> Unit,
  back_max? : Double = 0.0,
  bg? : Int64 = 0L,
) -> Bool {
  let t = theme()
  let mut went = false
  c.box(w=Fill(1.0), pl=10.0, pr=16.0, pt=6.0, pb=10.0, bg~, fn() {
    c.box(w=Fill(1.0), align=ACenter, fn() {
      // the title, in the flow: as tall as its lines make the bar
      c.box(pl=84.0, pr=84.0, align=ACenter, fn() {
        c.box(h=Px(32.0), justify=JCenter, clip=true, fn() {
          c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false) |> ignore
        })
        |> ignore
        match sub {
          Some(f) => c.box(dir=Row, ty=-4.0, gap=5.0, align=ACenter, fn() { f() }) |> ignore
          None => ()
        }
      })
      |> ignore
      // back and what is at the end, on the 32 line at its top
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(32.0), align=ACenter, fn() {
          went = nav_back(c, back_key, back, max_w=back_max)
          c.spacer()
          match trailing {
            Some(f) => c.box(dir=Row, h=Px(32.0), align=ACenter, fn() { f() }) |> ignore
            None => ()
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  went
}
