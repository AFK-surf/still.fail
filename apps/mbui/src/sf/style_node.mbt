// A style laid on a node of the window's tree (an old view's box's look, as the theme says it now): what of a
// @ui.Style a node takes from it, so a part made once is laid out as its old view's box was from the same style.

///|
/// What style `look` says (its base, the theme's as it is now: read again as that changes) laid on node `v`: a row or a
/// column, its size (`in_row`: what holds it lays what it holds in a row, so `w=Full` takes what is left along it, else
/// across it; `h=Full` the other way), its least and most, its padding and margin, the room between what it holds and
/// how that lines up across it and lies along it, its corner, its ground and whether it cuts what it holds. What it
/// says nothing of is left as the node has it.
#callsite(autofill(loc))
pub fn style_node(v : @view.View, look : () -> @ui.Style, in_row? : Bool = false, loc~ : SourceLoc) -> Unit {
  // (all of it set together, in one binding, set again where it comes out otherwise as what it reads changes (the
  // theme, mostly): a binding each would be made and let go with every node for what changes with the theme alone.
  // What it says as the node is made decides what it sets)
  let was : Ref[StyleSet?] = Ref(None)
  v
  .sets_together(fn() { style_of(look().base, in_row) }, fn(s) {
    style_set(v, was.val, s, loc)
    was.val = Some(match was.val {
      Some(w) => { ..s, says: w.says }
      None => s
    })
  })
  |> ignore
}

///|
/// What a style says of a node (style_node), worked out: each property as it is set, and which of them it sets
/// (`says`, as it said them as the node was made).
priv struct StyleSet {
  says : StyleSays
  row : Bool
  w : Double?
  h : Double?
  grow : Double
  min_w : Double?
  max_w : Double?
  min_h : Double?
  padding : (Double, Double, Double, Double)
  gap : Double
  lines_up : @view.Along?
  lies_along : @view.Along
  margin : (Double, Double, Double, Double)
  corner : Double
  ground : Int64
  clip : Bool
} derive(Eq)

///|
/// Which properties a style sets (StyleSet's `says`).
priv struct StyleSays {
  w : Bool
  h : Bool
  grow : Bool
  min_w : Bool
  max_w : Bool
  min_h : Bool
  margin : Bool
  corner : Bool
  ground : Bool
  clip : Bool
} derive(Eq)

///|
/// Style `q` worked out (`in_row`: what holds it lays what it holds in a row), its corner and ground as the theme makes
/// them now: the same tokens are another corner and colour in another.
fn style_of(q : @ui.Patch, in_row : Bool) -> StyleSet {
  let along = if in_row { q.w } else { q.h }
  {
    says: {
      w: style_points(q.w) is Some(_),
      h: style_points(q.h) is Some(_),
      grow: along is Some(Full | Grow(_)),
      min_w: q.min_w is Some(_),
      max_w: q.max_w is Some(_),
      min_h: q.min_h is Some(_),
      margin: q.m is Some(_) ||
      q.mx is Some(_) ||
      q.my is Some(_) ||
      q.ml is Some(_) ||
      q.mt is Some(_) ||
      q.mr is Some(_) ||
      q.mb is Some(_),
      corner: q.radius is Some(_),
      ground: q.bg is Some(_),
      clip: q.clip is Some(_),
    },
    row: q.row.unwrap_or(false),
    w: style_points(q.w),
    h: style_points(q.h),
    grow: match along {
      Some(Full) => 1.0
      Some(Grow(k)) => k
      _ => 0.0
    },
    min_w: style_points(q.min_w),
    max_w: style_points(q.max_w),
    min_h: style_points(q.min_h),
    padding: style_sides(false, q.p, q.px, q.py, q.pl, q.pt, q.pr, q.pb),
    gap: style_room(q.gap).unwrap_or(0.0),
    lines_up: match q.align {
      Some(AStart) => Some(Start)
      Some(ACenter) => Some(Middle)
      Some(AEnd) => Some(End)
      Some(AStretch) | None => None
    },
    lies_along: match q.justify {
      Some(JCenter) => Middle
      Some(JEnd) => End
      _ => Start
    },
    margin: style_sides(true, q.m, q.mx, q.my, q.ml, q.mt, q.mr, q.mb),
    corner: match q.radius {
      Some(r) => @ui.tree_theme().corner(r)
      None => 0.0
    },
    ground: match q.bg {
      Some(Data(k)) => k
      Some(c) => @ui.tree_theme().color(c)
      None => 0L
    },
    clip: q.clip.unwrap_or(false),
  }
}

///|
/// Style `s` set on node `v`, each property said Is (View::sets_together): what it says (as it said it the first time,
/// `was`'s) where it differs from what it was (`was`; all of it the first time), said at `loc`
/// (style_node's caller's: what a test finds said there, view's source.mbt).
fn style_set(v : @view.View, was : StyleSet?, s : StyleSet, loc : SourceLoc) -> Unit {
  let says = match was {
    Some(w) => w.says
    None => s.says
  }
  let new = was is None
  let w = was.unwrap_or(s)
  if new || w.row != s.row {
    v.row(loc~, Is(s.row)) |> ignore
  }
  if says.w && (new || w.w != s.w) {
    v.width(loc~, Is(s.w)) |> ignore
  }
  if says.h && (new || w.h != s.h) {
    v.height(loc~, Is(s.h)) |> ignore
  }
  if says.grow && (new || w.grow != s.grow) {
    v.grow(loc~, Is(s.grow)) |> ignore
    if new {
      v.basis(loc~, Is(Some(0.0))) |> ignore
    }
  }
  if says.min_w && (new || w.min_w != s.min_w) {
    v.min_width(loc~, Is(s.min_w)) |> ignore
  }
  if says.max_w && (new || w.max_w != s.max_w) {
    v.max_width(loc~, Is(s.max_w)) |> ignore
  }
  if says.min_h && (new || w.min_h != s.min_h) {
    v.min_height(loc~, Is(s.min_h)) |> ignore
  }
  if new || w.padding != s.padding {
    v.padding(loc~, Is(s.padding)) |> ignore
  }
  if new || w.gap != s.gap {
    v.gap(loc~, Is(s.gap)) |> ignore
  }
  if new || w.lines_up != s.lines_up {
    v.lines_up(loc~, Is(s.lines_up)) |> ignore
  }
  if new || w.lies_along != s.lies_along {
    v.lies_along(loc~, Is(s.lies_along)) |> ignore
  }
  if says.margin && (new || w.margin != s.margin) {
    v.margin(loc~, Is(s.margin)) |> ignore
  }
  if says.corner && (new || w.corner != s.corner) {
    v.radius(loc~, Is(s.corner)) |> ignore
  }
  if says.ground && (new || w.ground != s.ground) {
    v.ground(loc~, Is(s.ground)) |> ignore
  }
  if says.clip && (new || w.clip != s.clip) {
    v.clips(loc~, Is(s.clip)) |> ignore
  }
}

///|
/// Room `s` in points.
fn style_room(s : @ui.Space?) -> Double? {
  match s {
    Some(s) => Some(s.px())
    None => None
  }
}

///|
/// The four sides (left, top, right, bottom) of a padding, or of a margin (`margin`: one below 0 too, taking back a
/// padding), from all of them, across, up and down and each.
fn style_sides(
  margin : Bool,
  all : @ui.Space?,
  x : @ui.Space?,
  y : @ui.Space?,
  l : @ui.Space?,
  t : @ui.Space?,
  r : @ui.Space?,
  b : @ui.Space?,
) -> (Double, Double, Double, Double) {
  let a = style_side(margin, all).unwrap_or(0.0)
  let x = style_side(margin, x).unwrap_or(a)
  let y = style_side(margin, y).unwrap_or(a)
  (
    style_side(margin, l).unwrap_or(x),
    style_side(margin, t).unwrap_or(y),
    style_side(margin, r).unwrap_or(x),
    style_side(margin, b).unwrap_or(y),
  )
}

///|
/// Length `l` in points.
fn style_points(l : @ui.Len?) -> Double? {
  match l {
    Some(l) => l.points()
    None => None
  }
}

///|
/// Room `s` in points, of a padding, or of a margin (`margin`: one below 0 too).
fn style_side(margin : Bool, s : @ui.Space?) -> Double? {
  match s {
    Some(s) => Some(if margin { s.margin_px() } else { s.px() })
    None => None
  }
}
