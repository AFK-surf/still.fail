// A sheet from the bottom (not one of Radix's: Vaul's Drawer, a phone's bottom sheet; a dialog by its behaviour):
// whether it is open the view's. Modal: the page under it dimmed, out of the semantics tree and taking no press, Tab
// kept in it, the focus back where it was as it goes. It comes up from the bottom and goes down again by `presence`;
// Escape, the back, a press on the page above it and a drag down by its grabber (past a quarter of it, or quick)
// close it.

///|
/// What a sheet's look is given: how far up it is (0 … 1), its height, how far it is dragged down.
pub(all) struct SheetState {
  t : Double
  h : Double
  dragged : Double
}

///|
/// `key`'s sheet (see the file's head), `open` or not, `h` high (at most 90% of the window), what `body` builds in
/// it, named `label` for the semantics tree. Whether it is open now.
pub fn sheet(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  h : Double,
  body : () -> Unit,
  label? : String = "",
  look? : (@ui.Ctx, SheetState, () -> Unit) -> Unit = sheet_look,
) -> @ui.Changed[Bool] {
  let t = c.theme()
  let p = presence(c, key, open, enter=@motion.tween(300.0, ease=Arrive), exit=@motion.tween(260.0, ease=Out))
  let mut now = open
  if p.built {
    let (_, wh) = c.window_size()
    let tall = dmin(h, wh * 0.9)
    let gid = c.id(key + "/grab")
    // the grabber's drag: followed down while held, let go past a quarter (or quick) it closes, else it goes back
    let dragged = match c.drag_of(gid) {
      Some(d) if p.shown => {
        let dy = if d.down && d.moving { dmax(0.0, d.y - d.y0) } else { 0.0 }
        if d.take_end() && (d.y - d.y0 > tall / 4.0 || d.vy > 0.5) {
          now = false
        }
        dy
      }
      _ => 0.0
    }
    let k = if p.t > 1.0 { 1.0 } else if p.t < 0.0 { 0.0 } else { p.t }
    let o = c.overlay(key, modal=true, scrim=faded(t.scrim, k), inert=p.leaving(), fn() {
      let i = c.box(w=Fill(1.0), h=Px(tall), ty=wh - tall + (1.0 - k) * tall + dragged, fn() {
        look(c, { t: k, h: tall, dragged }, fn() {
          c.drag_area(gid, axis=Vertical, w=Fill(1.0), fn() { grabber(c) }) |> ignore
          body()
        })
      })
      c.semantics(i, Dialog, label~, modal=true)
    })
    if o.dismissed is Some(_) {
      now = false
    }
  }
  { value: now, response: { ..@ui.Response::none(), id: c.id(key), changed: told(c, now != open) } }
}

///|
/// A sheet's grabber: 38 by 5 in the theme's line colour, 12 above it and 8 under.
fn grabber(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
    c.box(w=Px(38.0), h=Px(5.0), radius=2.5, bg=t.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A sheet's default look (still.fail's phone sheets): the theme's surface, its top corners 26 round (its bottom ones
/// below the window), a shadow; its grabber, then what it holds.
pub fn sheet_look(c : @ui.Ctx, s : SheetState, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(w=Fill(1.0), h=Px(s.h + 26.0), radius=26.0, bg=t.surface, shadow=24.0, shadow_color=t.shadow, clip=true, fn() {
    c.box(w=Fill(1.0), h=Px(s.h), body) |> ignore
  })
  |> ignore
}
