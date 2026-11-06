// A style laid on an existing node of the window's tree. The style is resolved for the theme and the node's state;
// properties not said by it remain the node's, and return to the node's own binding when the style stops saying them.

///|
fn node_style_room(s : @ui.Space?) -> Double? {
  s.map(fn(x) { x.px() })
}

///|
fn node_style_margin(s : @ui.Space?) -> Double? {
  s.map(fn(x) { x.margin_px() })
}

///|
fn node_style_sides(
  room : (@ui.Space?) -> Double?,
  all : @ui.Space?, x : @ui.Space?, y : @ui.Space?,
  l : @ui.Space?, t : @ui.Space?, r : @ui.Space?, b : @ui.Space?,
) -> (Double, Double, Double, Double)? {
  if all is None && x is None && y is None && l is None && t is None && r is None && b is None {
    return None
  }
  let a = room(all).unwrap_or(0.0)
  let x = room(x).unwrap_or(a)
  let y = room(y).unwrap_or(a)
  Some((room(l).unwrap_or(x), room(t).unwrap_or(y), room(r).unwrap_or(x), room(b).unwrap_or(y)))
}

///|
fn node_style_size(len : @ui.Len?, along : Bool) -> @view.StyleSize? {
  match len {
    None => None
    Some(Full) if !along => Some(Percent(100.0))
    Some(Full | Grow(_) | Hug | Cut) => Some(Automatic)
    Some(Pct(p)) => Some(Percent(p))
    Some(Within(v)) => Some(Within(v))
    Some(v) => v.points().map(fn(n) { Points(n) })
  }
}

///|
/// Lay `look` on the already made `v`, following its theme, narrowness, hand and visible keyboard focus. In a row,
/// `w=Full` and `w=Grow` take the room left along it; in a column `h` does. `selected` and `disabled` give the
/// caller-owned states where the style has those blocks. What the style does not say belongs to the node's maker;
/// a property set after this call continues to win over the style.
pub fn style_node(
  v : @view.View,
  look : () -> @ui.Style,
  in_row? : Bool = false,
  selected? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
) -> Unit {
  v.style_layer(fn() {
    let s = look()
    let th = @ui.tree_theme()
    let hovered = if s.hovered is Some(_) {
      match @ui.pointing() {
        Mouse => v.pointed_in()
        Finger => v.pressed()
      }
    } else {
      false
    }
    let q = s.resolve(
      @ui.tree_narrow(), th.dark,
      if s.selected is Some(_) { selected() } else { false },
      hovered,
      s.focused is Some(_) && v.focus_shown(),
      s.pressed is Some(_) && v.pressed(),
      if s.disabled is Some(_) { disabled() } else { false },
    )
    let along = if in_row { q.w } else { q.h }
    let grow = match along {
      None => None
      Some(Full) => Some(1.0)
      Some(Grow(k)) => Some(k)
      Some(_) => Some(0.0)
    }
    let basis = match along {
      None => None
      Some(Full | Grow(_)) => Some(@view.StyleSize::Points(0.0))
      Some(_) => Some(@view.StyleSize::Automatic)
    }
    let corners = match q.radius {
      None => None
      Some(radius) =>
        Some(match radius.each() {
          Some(c) => Some((c[0], c[1], c[2], c[3]))
          None => None
        })
    }
    let edge = if q.border is Some(_) || q.border_color is Some(_) {
      Some((q.border.map(fn(b) { b.px() }).unwrap_or(0.0), q.border_color.map(fn(c) { th.color(c) }).unwrap_or(0L)))
    } else {
      None
    }
    let shadow = q.shadow.map(fn(s) {
      let (blur, y) = s.blur_y()
      let color = match s { Cast(_, _, c) => c; _ => th.shadow }
      (blur, y, color)
    })
    {
      row: q.row,
      width: node_style_size(q.w, in_row),
      height: node_style_size(q.h, !in_row),
      min_width: node_style_size(q.min_w, false),
      max_width: node_style_size(q.max_w, false),
      min_height: node_style_size(q.min_h, false),
      max_height: node_style_size(q.max_h, false),
      grow,
      basis,
      padding: node_style_sides(node_style_room, q.p, q.px, q.py, q.pl, q.pt, q.pr, q.pb),
      margin: node_style_sides(node_style_margin, q.m, q.mx, q.my, q.ml, q.mt, q.mr, q.mb),
      gap: node_style_room(q.gap),
      align: match q.align {
        None => None
        Some(AStart) => Some(Some(Start))
        Some(ACenter) => Some(Some(Middle))
        Some(AEnd) => Some(Some(End))
        Some(AStretch) => Some(None)
      },
      justify: match q.justify {
        None => None
        Some(JCenter) => Some(Middle)
        Some(JEnd) => Some(End)
        Some(_) => Some(Start)
      },
      ground: q.bg.map(fn(c) { th.color(c) }),
      radius: q.radius.map(fn(r) { th.corner(r) }),
      corners,
      clips: q.clip,
      alpha: q.opacity.map(fn(o) { o.value() }),
      edge,
      edge_dashed: q.dashed,
      shadow,
    }
  })
  |> ignore
}
