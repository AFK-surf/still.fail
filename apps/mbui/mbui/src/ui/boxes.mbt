// Every node of the last frame with where it is drawn and the few things a page's look is compared by (Tester::boxes):
// what a tool holding an app against another app's page reads (still.fail's apps/mbui/src/sflayout, against the web's
// DOM). Read only.

///|
/// A node as the last frame drew it. `x`, `y`: its top left as drawn (moved by its looks and its ancestors':
/// Ctx::drawn_at), `w`, `h` its size as laid out; `cut`: what of it shows inside the boxes that clip it (x, y, w, h;
/// w or h 0 when none does). `opacity`: its and its ancestors' opacities and looks' alphas, multiplied. `bg`, `border_c`,
/// `color`: RGBA; `dashed`: its border drawn as dashes. `font_size`, `weight`, `color`: its words' (0 for a box).
/// `name`: Ctx::box's `name`; `label`: its `label`, else what Ctx::semantics calls it (a screen reader's name, the
/// web's aria-label); `moves`: the name a move_state moves it by (the web's moveState's selector): either a name of the web's it stands for. `words_w`:
/// how wide its words are drawn, its widest line (0 for a box); `hit`: it takes the presses on its room; `draws`: it
/// draws a picture of its own (an image, shapes or lines over its ground: an icon, a mark); `glass`: its ground is made
/// of what is under it (glass.mbt).
pub(all) struct Laid {
  index : Int
  parent : Int
  depth : Int
  kind : String
  name : String
  moves : String
  label : String
  text : String
  words_w : Double
  hit : Bool
  draws : Bool
  glass : Bool
  x : Double
  y : Double
  w : Double
  h : Double
  cut : (Double, Double, Double, Double)
  radius : Double
  /// each of its corners as drawn (top left, top right, bottom right, bottom left); `radius` the roundest
  radii : (Double, Double, Double, Double)
  bg : Int64
  border_w : Double
  border_c : Int64
  dashed : Bool
  font_size : Double
  weight : Int
  color : Int64
  opacity : Double
}

///|
fn laid_kind(n : Node) -> String {
  if n.kind == kind_text {
    "text"
  } else if n.kind == kind_rich {
    "rich"
  } else if n.kind == kind_editor {
    "editor"
  } else if n.kind == kind_list {
    "list"
  } else if n.kind == kind_scroll {
    "scroll"
  } else if n.kind == kind_image {
    "image"
  } else if n.kind == kind_native {
    "native"
  } else if n.kind == kind_page {
    "page"
  } else if n.dir == Row {
    "row"
  } else {
    "col"
  }
}

///|
/// The last frame's nodes, in the order they were built (a parent before what it holds).
pub fn Tester::boxes(self : Tester) -> Array[Laid] {
  ignore(self)
  let c = g()
  let out = []
  // (what a screen reader is told a node is called, where the box was given no label of its own: the last to say)
  let said : Map[Int, String] = {}
  for s in c.sems {
    if s.label != "" {
      said[s.node] = s.label
    }
  }
  for i in 0..<c.count {
    let n = c.nodes[i]
    let (x, y) = c.drawn_at(i)
    let mut alpha = 1.0
    let mut depth = 0
    // what shows of it: cut by each box above it that clips, where that box is drawn
    let mut l = x
    let mut t = y
    let mut r = x + n.fw
    let mut b = y + n.fh
    let mut p = i
    while p >= 0 {
      let q = c.nodes[p]
      alpha = alpha * q.opacity
      match c.drawn_entry(p) {
        Some(e) => alpha = alpha * e.look.alpha
        None => ()
      }
      if p != i && q.clip {
        let (qx, qy) = c.drawn_at(p)
        l = if qx > l { qx } else { l }
        t = if qy > t { qy } else { t }
        r = if qx + q.fw < r { qx + q.fw } else { r }
        b = if qy + q.fh < b { qy + q.fh } else { b }
      }
      if p != i {
        depth = depth + 1
      }
      p = q.parent
    }
    let words = n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor
    let cut = if r > l && b > t { (l, t, r - l, b - t) } else { (l, t, 0.0, 0.0) }
    out.push({
      index: i,
      parent: n.parent,
      depth,
      kind: laid_kind(n),
      name: n.name,
      moves: n.moves,
      label: if n.label != "" { n.label } else { said.get(i).unwrap_or("") },
      text: if words { n.text } else { "" },
      words_w: match (n.tl, n.rl) {
        (Some(tl), _) if n.kind == kind_text => tl.w
        (_, Some(rl)) if n.kind == kind_rich => rl.w
        _ => 0.0
      },
      hit: n.hit,
      draws: n.kind == kind_image || n.shapes.length() > 0 || n.lines.length() > 0,
      glass: n.glass is Some(_),
      x,
      y,
      w: n.fw,
      h: n.fh,
      cut,
      radius: n.radius,
      radii: (n.radius_at(0), n.radius_at(1), n.radius_at(2), n.radius_at(3)),
      bg: n.bg,
      border_w: n.border_w,
      border_c: n.border_c,
      dashed: n.dashed,
      font_size: if words { n.font_size } else { 0.0 },
      weight: if words { n.weight } else { 0 },
      color: if words { n.color } else { 0L },
      opacity: alpha,
    })
  }
  out
}
