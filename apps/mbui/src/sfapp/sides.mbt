// What the system has at the window's sides (@ui.system_bars `left` and `right`: iOS's view runs from side to side,
// and an iPhone Duo's outer screen has its status bar down its right side, iOS 27.1; a phone on its side its cutout):
// the app's pages beside it, the page's paper under it (a top bar has no line along its foot to carry under it: its
// frost over the paper alone is the paper). Android keeps a cutout at a side out of the view: nothing is said there,
// nothing done.

///|
/// `body` (the app) beside what the system has at the window's sides, the page's paper under that; `body` alone when
/// there is nothing there.
fn beside_sides(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let b = @ui.system_bars()
  let (left, right) = (dmax(0.0, b.left), dmax(0.0, b.right))
  if left == 0.0 && right == 0.0 {
    body()
    return
  }
  let w = dmax(0.0, c.width - left - right)
  c.box(style=sides_row, fn() {
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Fixed(w), h=Full, clip=true), fn() { c.sized(w, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let sides_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, bg=Bg)
