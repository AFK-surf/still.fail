// A style laid on a node of the window's tree (an old view's box's look, as the theme says it now): what of a
// @ui.Style a node takes from it, so a part made once is laid out as its old view's box was from the same style.

///|
/// What style `look` says (its base, the theme's as it is now: read again as that changes) laid on node `v`: a row or a
/// column, its size (`in_row`: what holds it lays what it holds in a row, so `w=Full` takes what is left along it, else
/// fills it across; `h=Full` the other way; `w=Cut` cut short where it has not the room), its least and most, its
/// padding and margin, the room between what it holds and how that lines up across it and lies along it (spread
/// between its ends too), its corner, its ground, its border (an edge round its ground) and whether it cuts what it
/// holds. What no node is laid out by is a fault (style_of). What it has never said is left as the node has it; what it
/// said once and says no more is put back to none (no ground, a corner of 0, ...).
#callsite(autofill(loc))
pub fn style_node(v : @view.View, look : () -> @ui.Style, in_row? : Bool = false, loc~ : SourceLoc) -> Unit {
  // (all of it set together, in one binding, set again where it comes out otherwise as what it reads changes (the
  // theme, mostly): a binding each would be made and let go with every node for what changes with the theme alone.
  // What it has said so far, at any time, decides what it sets: `was`'s `says`)
  let was : Ref[StyleSet?] = Ref(None)
  v
  .sets_together(fn() { style_of(look().base, in_row, loc) }, fn(s) {
    style_set(v, was.val, s, loc)
    was.val = Some(match was.val {
      Some(w) => { ..s, says: w.says.joined(s.says) }
      None => s
    })
  })
  |> ignore
}

///|
/// What a style says of a node (style_node), worked out: each property as it is set, and which of them it sets
/// (`says`, as it said them as the node was made).
#derive(Eq)
priv struct StyleSet {
  says : StyleSays
  row : Bool
  w : Double?
  h : Double?
  grow : Double
  fills : Bool
  cut : Bool
  min_w : Double?
  min_w_within : Bool
  max_w : Double?
  min_h : Double?
  padding : (Double, Double, Double, Double)
  gap : Double
  lines_up : @view.Along?
  lies_along : @view.Lies
  margin : (Double, Double, Double, Double)
  corner : Double
  ground : Int64
  edge_w : Double
  edge_c : Int64
  clip : Bool
}

///|
/// Which properties a style sets (StyleSet's `says`).
#derive(Eq)
priv struct StyleSays {
  w : Bool
  h : Bool
  grow : Bool
  fills : Bool
  cut : Bool
  min_w : Bool
  max_w : Bool
  min_h : Bool
  margin : Bool
  corner : Bool
  ground : Bool
  edge : Bool
  clip : Bool
}

///|
/// What `self` says and what `more` says (the same `self` where `more` says nothing it does not: made anew only as a
/// style says something for the first time).
fn StyleSays::joined(self : StyleSays, more : StyleSays) -> StyleSays {
  let all : StyleSays = {
    w: self.w || more.w,
    h: self.h || more.h,
    grow: self.grow || more.grow,
    fills: self.fills || more.fills,
    cut: self.cut || more.cut,
    min_w: self.min_w || more.min_w,
    max_w: self.max_w || more.max_w,
    min_h: self.min_h || more.min_h,
    margin: self.margin || more.margin,
    corner: self.corner || more.corner,
    ground: self.ground || more.ground,
    edge: self.edge || more.edge,
    clip: self.clip || more.clip,
  }
  if all == self {
    self
  } else {
    all
  }
}

///|
/// Style `q` worked out (`in_row`: what holds it lays what it holds in a row), its corner and ground as the theme makes
/// them now: the same tokens are another corner and colour in another. What of it a node cannot be laid out by (a share
/// of what holds it as a size or a bound, a least across as a size) is a fault of the style said at `loc`
/// (style_wrong), the node laid out as though it had not said it.
fn style_of(q : @ui.Patch, in_row : Bool, loc : SourceLoc) -> StyleSet {
  let along = if in_row { q.w } else { q.h }
  let across = if in_row { q.h } else { q.w }
  let fills = across is Some(Full | Grow(_))
  let w = style_size(q.w, "w", loc)
  let h = style_size(q.h, "h", loc)
  let min_w = style_bound(q.min_w, "min_w", loc)
  let max_w = style_bound(q.max_w, "max_w", loc)
  let min_h = style_bound(q.min_h, "min_h", loc)
  {
    says: {
      w: w is Some(_),
      h: h is Some(_),
      grow: along is Some(Full | Grow(_)),
      fills,
      cut: q.w is Some(Cut),
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
      edge: q.border is Some(_) || q.border_color is Some(_),
      clip: q.clip is Some(_),
    },
    row: q.row.unwrap_or(false),
    w,
    h,
    // (no grow along it for the rest: none said, as what it holds, a size in points, or cut short (`cut`); a share or
    // a least as its size is style_size's fault)
    grow: match along {
      Some(Full) => 1.0
      Some(Grow(k)) => k
      _ => 0.0
    },
    // (filling what holds it across, an old view's Fill across: stretched there whatever it lines up by)
    fills,
    // (cut short where what holds it has not the room across, an old view's w=Cut: View::cuts, which gives way along a
    // row and keeps its height in a column)
    cut: q.w is Some(Cut),
    min_w,
    // (a least across: View::min_width's `within`)
    min_w_within: q.min_w is Some(Within(_)),
    max_w,
    min_h,
    padding: style_sides(false, q.p, q.px, q.py, q.pl, q.pt, q.pr, q.pb),
    gap: style_room(q.gap).unwrap_or(0.0),
    lines_up: match q.align {
      Some(AStart) => Some(Start)
      Some(ACenter) => Some(Middle)
      Some(AEnd) => Some(End)
      Some(AStretch) | None => None
    },
    lies_along: match q.justify {
      Some(JStart) | None => Start
      Some(JCenter) => Middle
      Some(JEnd) => End
      Some(JBetween) => Between
    },
    margin: style_sides(true, q.m, q.mx, q.my, q.ml, q.mt, q.mr, q.mb),
    corner: match q.radius {
      Some(Inner) => {
        @view.fault("style_node at \{loc}: radius=Inner is laid on no node")
        0.0
      }
      Some(InnerOr(_)) => {
        @view.fault("style_node at \{loc}: radius=InnerOr is laid on no node")
        0.0
      }
      Some(Around) => {
        @view.fault("style_node at \{loc}: radius=Around is laid on no node")
        0.0
      }
      Some(r) => @ui.tree_theme().corner(r)
      None => 0.0
    },
    ground: match q.bg {
      Some(Data(k)) => k
      Some(c) => @ui.tree_theme().color(c)
      None => 0L
    },
    // (an old view's border: drawn round its ground, inside it, in no colour where it says none)
    edge_w: match q.border {
      Some(b) => b.px()
      None => 0.0
    },
    edge_c: match q.border_color {
      Some(Data(k)) => k
      Some(c) => @ui.tree_theme().color(c)
      None => 0L
    },
    clip: q.clip.unwrap_or(false),
  }
}


///|
/// Size `l` (its `w` or `h`, `name`) in points: none where it says none of its own (none said, as what it holds, grown
/// along what holds it, cut short: style_of's grow and cut). A share of what holds it (`Pct`) and a least across
/// (`Within`, a bound's) are no size a node is laid out by here: a fault of the style said at `loc`.
fn style_size(l : @ui.Len?, name : String, loc : SourceLoc) -> Double? {
  match l {
    Some(Pct(_) | Within(_)) => {
      style_wrong(loc, name, l)
      None
    }
    _ => style_points(l)
  }
}

///|
/// Bound `l` (`name`: its min_w, max_w or min_h) in points (a least across, `Within`, its points: so much where what
/// holds it has the room, a least width taking all of it where it has less by View::min_width's `within`, style_of's
/// `min_w_within`; as an old view's bound took it). None where it says none (as what it holds, cut short, grown: no
/// bound, as an old view's). A share of what holds it (`Pct`) is no bound: a fault of the style said at `loc`.
fn style_bound(l : @ui.Len?, name : String, loc : SourceLoc) -> Double? {
  match l {
    Some(Pct(_)) => {
      style_wrong(loc, name, l)
      None
    }
    Some(Within(v)) => Some(v)
    _ => style_points(l)
  }
}

///|
/// What the style said at `loc` (style_node's caller's) says of `name` that no node is laid out by: `l`. A fault
/// (@view.fault): a test stops on it, naming where, what and how; an app's run is told it once and lays the node out
/// as though it had not said it.
fn style_wrong(loc : SourceLoc, name : String, l : @ui.Len?) -> Unit {
  let said = match l {
    Some(l) => l.to_string()
    None => "none"
  }
  @view.fault("style_node at \{loc}: \{name}=\{said} is laid on no node")
}

///|
/// Style `s` set on node `v`, each property said Is (View::sets_together), said at `loc` (style_node's caller's: what a
/// test finds said there, view's source.mbt): all it says the first time (`was` None); then what it says where it
/// differs from what it was (`was`), what it says for the first time whatever it was, and what it said before (`was`'s
/// `says`, all it has said) and says no more put back to none (`s` has none there: style_of's).
fn style_set(v : @view.View, was : StyleSet?, s : StyleSet, loc : SourceLoc) -> Unit {
  let new = was is None
  let w = was.unwrap_or(s)
  // (said now or before: set where it differs; said now for the first time: set)
  let before = match was {
    Some(w) => w.says
    None => s.says
  }
  let now = s.says
  if new || w.row != s.row {
    v.row(loc~, Is(s.row)) |> ignore
  }
  if style_first(new, before.w, now.w) || (before.w && w.w != s.w) {
    v.width(loc~, Is(s.w)) |> ignore
  }
  if style_first(new, before.h, now.h) || (before.h && w.h != s.h) {
    v.height(loc~, Is(s.h)) |> ignore
  }
  if style_first(new, before.grow, now.grow) || (before.grow && w.grow != s.grow) {
    v.grow(loc~, Is(s.grow)) |> ignore
    if style_first(new, before.grow, now.grow) {
      v.basis(loc~, Is(Some(0.0))) |> ignore
    }
  }
  if style_first(new, before.fills, now.fills) || (before.fills && w.fills != s.fills) {
    v.fills_across(loc~, Is(s.fills)) |> ignore
  }
  if style_first(new, before.cut, now.cut) || (before.cut && w.cut != s.cut) {
    v.cuts(loc~, Is(s.cut)) |> ignore
  }
  if style_first(new, before.min_w, now.min_w) ||
    (before.min_w && (w.min_w != s.min_w || w.min_w_within != s.min_w_within)) {
    v.min_width(loc~, Is(s.min_w), within=s.min_w_within) |> ignore
  }
  if style_first(new, before.max_w, now.max_w) || (before.max_w && w.max_w != s.max_w) {
    v.max_width(loc~, Is(s.max_w)) |> ignore
  }
  if style_first(new, before.min_h, now.min_h) || (before.min_h && w.min_h != s.min_h) {
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
  if style_first(new, before.margin, now.margin) || (before.margin && w.margin != s.margin) {
    v.margin(loc~, Is(s.margin)) |> ignore
  }
  if style_first(new, before.corner, now.corner) || (before.corner && w.corner != s.corner) {
    v.radius(loc~, Is(s.corner)) |> ignore
  }
  if style_first(new, before.ground, now.ground) || (before.ground && w.ground != s.ground) {
    v.ground(loc~, Is(s.ground)) |> ignore
  }
  if style_first(new, before.edge, now.edge) || (before.edge && (w.edge_w != s.edge_w || w.edge_c != s.edge_c)) {
    v.edge(loc~, Is((s.edge_w, s.edge_c))) |> ignore
  }
  if style_first(new, before.clip, now.clip) || (before.clip && w.clip != s.clip) {
    v.clips(loc~, Is(s.clip)) |> ignore
  }
}

///|
/// Whether a property is said for the first time: said `now`, the style `new` or not said `before`.
fn style_first(new : Bool, before : Bool, now : Bool) -> Bool {
  now && (new || !before)
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
