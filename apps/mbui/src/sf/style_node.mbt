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
    Some(Full | Grow(_)) if !along => Some(Percent(100.0))
    Some(Full | Grow(_) | Hug | Cut) => Some(Automatic)
    Some(Pct(p)) => Some(Percent(p))
    Some(Within(_)) => abort("style: Within is a bound, not a size")
    Some(v) => v.points().map(fn(n) { Points(n) })
  }
}

///|
fn node_style_bound(len : @ui.Len?) -> @view.StyleSize? {
  match len {
    None => None
    Some(Within(v)) => Some(Within(v))
    Some(Hug | Cut | Full | Grow(_)) => Some(Automatic)
    Some(Pct(_)) => abort("style: a bound cannot be a percentage")
    Some(v) => v.points().map(fn(n) { Points(n) })
  }
}

///|
/// Linked corners of a retained node follow its tree's window and theme, not the old frame's current context.
fn node_style_radius(theme : @ui.Theme, radius : @ui.Radius) -> Double {
  match radius {
    Linked(link) => link.radius(@ui.tree_corner_roots_now())
    LinkedEach(a, b, c, d) => {
      let roots = @ui.tree_corner_roots_now()
      theme.corner(Corners(a.radius(roots), b.radius(roots), c.radius(roots), d.radius(roots)))
    }
    InnerOr(own) => node_style_radius(theme, own)
    _ => theme.corner(radius)
  }
}

///|
fn node_style_corners(radius : @ui.Radius) -> (Double, Double, Double, Double)? {
  match radius {
    LinkedEach(a, b, c, d) => {
      let roots = @ui.tree_corner_roots_now()
      Some((a.radius(roots), b.radius(roots), c.radius(roots), d.radius(roots)))
    }
    InnerOr(own) => node_style_corners(own)
    _ => radius.each().map(fn(c) { (c[0], c[1], c[2], c[3]) })
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
    let hovered = if s.hovered is Some(_) {
      match @ui.pointing() {
        Mouse => v.pointed_in()
        Finger => v.pressed()
      }
    } else {
      false
    }
    let q = s.resolve(
      s.narrow is Some(_) && @ui.tree_narrow(),
      s.dark is Some(_) && @ui.tree_theme().dark,
      if s.selected is Some(_) { selected() } else { false },
      hovered,
      s.focused is Some(_) && v.focus_shown(),
      s.pressed is Some(_) && v.pressed(),
      if s.disabled is Some(_) { disabled() } else { false },
    )
    // A size-only style with no dark block does not need to follow the theme at all.
    let th = if q.bg is Some(_) || q.radius is Some(_) || q.border_color is Some(_) || q.shadow is Some(_) {
      Some(@ui.tree_theme())
    } else {
      None
    }
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
      Some(radius) => Some(node_style_corners(radius))
    }
    let corner_rule = match q.radius {
      Some(Inner) => Some(@view.StyleCornerRule::FromContainer)
      Some(InnerOr(_)) => Some(@view.StyleCornerRule::FromContainerOrOwn)
      Some(Around) => Some(@view.StyleCornerRule::AroundContents)
      _ => None
    }
    let corner_context = if corner_rule is Some(_) {
      Some((@ui.tree_corner_roots_now(), @ui.tree_window_corners_now()))
    } else {
      None
    }
    let shadow = q.shadow.map(fn(s) {
      let (blur, y) = s.blur_y()
      let color = match s { Cast(_, _, c) => c; _ => th.unwrap().shadow }
      (blur, y, color)
    })
    {
      row: q.row,
      width: node_style_size(q.w, in_row),
      height: node_style_size(q.h, !in_row),
      min_width: node_style_bound(q.min_w),
      max_width: node_style_bound(q.max_w),
      min_height: node_style_bound(q.min_h),
      max_height: node_style_bound(q.max_h),
      grow,
      basis,
      cut: match q.w { Some(Cut) => Some(true); _ => None },
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
        Some(JCenter) => Some(JustifyMiddle)
        Some(JEnd) => Some(JustifyEnd)
        Some(JBetween) => Some(JustifyBetween)
        Some(JStart) => Some(JustifyStart)
      },
      ground: q.bg.map(fn(c) { th.unwrap().color(c) }),
      radius: q.radius.map(fn(r) { node_style_radius(th.unwrap(), r) }),
      corners,
      corner_links: match q.radius { Some(r) => r.links(); None => None },
      corner_rule,
      corner_context,
      clips: q.clip,
      alpha: q.opacity.map(fn(o) { o.value() }),
      edge_width: q.border.map(fn(b) { b.px() }),
      edge_color: q.border_color.map(fn(c) { th.unwrap().color(c) }),
      edge_dashed: q.dashed,
      shadow,
    }
  }, size_along_width=in_row)
  |> ignore
}
