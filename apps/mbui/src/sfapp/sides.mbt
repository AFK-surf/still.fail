// What the system has at the window's sides (@ui.system_bars `left` and `right`: iOS's view runs from side to side,
// and an iPhone Duo's outer screen has its status bar down its right side, iOS 27.1; a phone on its side its cutout):
// the app's pages beside it, the page's paper under it, and a page's frosted top bar carried under it (Home's, a chat's,
// a place's: its hairline; its frost over the paper alone is the paper), so the bar runs to the screen's edge as the
// page does rather than stopping short of the status bar. Android keeps a cutout at a side out of the view: nothing is said there, nothing done.

///|
/// Whether this frame's page has a frosted top bar (top_frost: Home's, a chat's, a place's), carried under what is at
/// the window's sides.
let top_frost_built : Ref[Bool] = Ref(false)

///|
/// A page's frosted top bar is built this frame: carried under what is at the window's sides (beside_sides).
fn top_frost() -> Unit {
  top_frost_built.val = true
}

///|
/// `body` (the app) beside what the system has at the window's sides, the page's paper under that, and a page's top
/// bar's frost and hairline (top_bar_h high) carried under it; `body` alone when there is nothing there.
fn beside_sides(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let b = @ui.system_bars()
  let (left, right) = (dmax(0.0, b.left), dmax(0.0, b.right))
  if left == 0.0 && right == 0.0 {
    body()
    return
  }
  let w = dmax(0.0, c.width - left - right)
  top_frost_built.val = false
  c.box(style=sides_row, fn() {
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Fixed(w), h=Full, clip=true), fn() { c.sized(w, c.height, body) }) |> ignore
  })
  |> ignore
  // (after the page: whether it has a frosted bar is known once it is built)
  if top_frost_built.val {
    c.layer(fn() {
      c.box(style=sides_band, fn() {
        side_frost(c, left)
        c.spacer()
        side_frost(c, right)
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// A side's part of the top bar, `w` wide: as tall as the bar, its hairline under it (its frost over the page's paper
/// alone is that paper: what is under it already).
fn side_frost(c : @ui.Ctx, w : Double) -> Unit {
  if w <= 0.0 {
    return
  }
  c.box(style=@ui.style(w=Fixed(w)), fn() {
    c.box(style=@ui.style(w=Full, h=Fixed(top_bar_h())), fn() {  }) |> ignore
    c.box(style=sides_hairline, fn() {  }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let sides_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let sides_band : @ui.Style = @ui.style(row=true, w=Full, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let sides_hairline : @ui.Style = @ui.style(w=Full, h=@sf.hairline, bg=Line)
