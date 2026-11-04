// A style laid on a node of the window's tree (an old view's box's look, as the theme says it now): what of a
// @ui.Style a node takes from it, so a part made once is laid out as its old view's box was from the same style.

///|
/// What style `look` says (its base, the theme's as it is now: read again as that changes) laid on node `v`: a row or a
/// column, its size (`in_row`: what holds it lays what it holds in a row, so `w=Full` takes what is left along it, else
/// across it; `h=Full` the other way), its least and most, its padding and margin, the room between what it holds and
/// how that lines up across it and lies along it, its corner, its ground and whether it cuts what it holds. What it
/// says nothing of is left as the node has it.
pub fn style_node(v : @view.View, look : () -> @ui.Style, in_row? : Bool = false) -> Unit {
  let p = fn() { look().base }
  // (what it says as the node is made: what it binds; what it says nothing of, left to the node's maker)
  let q0 = @signals.untracked(p)
  let room = fn(s : @ui.Space?) {
    match s {
      Some(s) => Some(s.px())
      None => None
    }
  }
  let sides = fn(
    room : (@ui.Space?) -> Double?,
    all : @ui.Space?,
    x : @ui.Space?,
    y : @ui.Space?,
    l : @ui.Space?,
    t : @ui.Space?,
    r : @ui.Space?,
    b : @ui.Space?,
  ) {
    let a = room(all).unwrap_or(0.0)
    let x = room(x).unwrap_or(a)
    let y = room(y).unwrap_or(a)
    (room(l).unwrap_or(x), room(t).unwrap_or(y), room(r).unwrap_or(x), room(b).unwrap_or(y))
  }
  // (a margin below 0 too: one taking back a padding)
  let margin = fn(s : @ui.Space?) {
    match s {
      Some(s) => Some(s.margin_px())
      None => None
    }
  }
  let points = fn(l : @ui.Len?) {
    match l {
      Some(l) => l.points()
      None => None
    }
  }
  // (`w=Full` along what holds it in a row, `h=Full` along a column: what is left of it, from none)
  let along = fn(q : @ui.Patch) { if in_row { q.w } else { q.h } }
  v.row(By(fn() { p().row.unwrap_or(false) })) |> ignore
  if points(q0.w) is Some(_) {
    v.width(By(fn() { points(p().w) })) |> ignore
  }
  if points(q0.h) is Some(_) {
    v.height(By(fn() { points(p().h) })) |> ignore
  }
  if along(q0) is Some(Full | Grow(_)) {
    v
    .grow(By(fn() {
      match along(p()) {
        Some(Full) => 1.0
        Some(Grow(k)) => k
        _ => 0.0
      }
    }))
    .basis(Is(Some(0.0)))
    |> ignore
  }
  if q0.min_w is Some(_) {
    v.min_width(By(fn() { points(p().min_w) })) |> ignore
  }
  if q0.max_w is Some(_) {
    v.max_width(By(fn() { points(p().max_w) })) |> ignore
  }
  if q0.min_h is Some(_) {
    v.min_height(By(fn() { points(p().min_h) })) |> ignore
  }
  v
  .padding(By(fn() {
    let q = p()
    sides(room, q.p, q.px, q.py, q.pl, q.pt, q.pr, q.pb)
  }))
  .gap(By(fn() { room(p().gap).unwrap_or(0.0) }))
  .lines_up(By(fn() {
    match p().align {
      Some(AStart) => Some(Start)
      Some(ACenter) => Some(Middle)
      Some(AEnd) => Some(End)
      Some(AStretch) | None => None
    }
  }))
  .lies_along(By(fn() {
    match p().justify {
      Some(JCenter) => Middle
      Some(JEnd) => End
      _ => Start
    }
  }))
  |> ignore
  if q0.m is Some(_) || q0.mx is Some(_) || q0.my is Some(_) || q0.ml is Some(_) || q0.mt is Some(_) || q0.mr is Some(_) || q0.mb is Some(_) {
    v
    .margin(By(fn() {
      let q = p()
      sides(margin, q.m, q.mx, q.my, q.ml, q.mt, q.mr, q.mb)
    }))
    |> ignore
  }
  if q0.radius is Some(_) {
    v
    .radius(By(fn() {
      match p().radius {
        Some(r) => @ui.tree_theme().corner(r)
        None => 0.0
      }
    }))
    |> ignore
  }
  if q0.bg is Some(_) {
    v
    .ground(By(fn() {
      match p().bg {
        Some(Data(k)) => k
        Some(c) => @ui.tree_theme().color(c)
        None => 0L
      }
    }))
    |> ignore
  }
  if q0.clip is Some(_) {
    v.clips(By(fn() { p().clip.unwrap_or(false) })) |> ignore
  }
}
