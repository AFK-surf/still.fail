// An allowance's chips on a line of their own under a row's words (quota_chips' `lines`, as nodes of the window's
// tree): all of them in a line where it has the room, else in lines of their own, every chip whole.

///|
/// An allowance's windows (quota_chips' with `lines`, as a node) in `parent`, `q` as the core says it now: a line as
/// wide as what holds it (under a row's words: a station's account), a chip per window, what is left in it, filled as
/// far as that, its mark before it, `gap` apart, `small` a lower line; where the line has not the room for all of them
/// (View::drops), the account's windows a line and what its models have to themselves a line under it, each by its
/// mark, either going on in lines where it must (quota_chips_lines'). Nothing while the core cannot say or there is
/// no window. Each says what is left of it and when it fills again over it while it is pointed at, in the tips of the
/// panel it is in (panel_tips_lent; none outside a panel). `in_row`: what holds it lays what it holds in a row (its
/// width what that leaves it).
#callsite(autofill(loc))
pub fn quota_lines_node(
  parent : @view.View,
  q : () -> Json?,
  small? : Bool = false,
  gap? : Double = 8.0,
  in_row? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  let tips = parent.lent(panel_tips_lent)
  let windows = fn() {
    match chip_field(q(), "windows") {
      Some(Array(a)) => a
      _ => []
    }
  }
  // (one chip of windows `of`, the k-th, said as quota_worded's `form` says: its mark, what is left)
  let chips = fn(r : @view.View, of : () -> Array[Json], form : Int) {
    r.each(fn() { Array::makei(of().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
      let k = i.untracked()
      let w = fn() { of().get(k) }
      fill_chip_node(
        c,
        fn() { chip_left(w()) },
        fn() { chip_str(w(), "level") },
        fn() { quota_worded(w(), form).0 },
        fn() { quota_worded(w(), form).1 },
        small~,
        said=fn() { quota_said(w()) },
        tips?,
      )
      |> ignore
    })
  }
  parent.show(loc~, fn() { has_quota(q()) }, fn(b) {
    style_node(b, fn() { quota_chips_line }, in_row~)
    b.fits(Is(true)) |> ignore
    // (all of them in a line where it has the room: left out of its row where it has not, View::drops)
    b.box(fn(r) {
      style_node(r, fn() { quota_chips_row.then(@ui.style(gap=room(gap))) }, in_row=true)
      r.drops(Is(1)) |> ignore
      chips(r, windows, 2)
    })
    |> ignore
    // (else the account's a line, its models' own under it, each going on in lines: there only while the line is
    // left out)
    b.box(fn(r) {
      style_node(r, fn() { quota_chips_parts }, in_row=true)
      r.drops(Is(-1)) |> ignore
      let parts = fn() { quota_parts(windows()) }
      for i in [0, 1] {
        let part = fn() { parts().get(i).unwrap_or([]) }
        r.show(fn() { part().length() > 0 }, fn(p) {
          style_node(p, fn() { quota_chips_part.then(@ui.style(gap=room(gap))) })
          p.wraps(Is(Some(quota_chips_part_lines))) |> ignore
          chips(p, part, 2)
        })
      }
    })
    |> ignore
  })
}
