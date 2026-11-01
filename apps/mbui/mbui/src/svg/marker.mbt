// usvg's markers (parser/marker.rs): a marker's content drawn at a path's vertices, turned to its direction.

///|
priv enum MSeg {
  MMove(@skia.Point)
  MLine(@skia.Point)
  MCubic(@skia.Point, @skia.Point, @skia.Point)
  MClose
}

///|
fn marker_is_valid(doc : SDoc, node : Int) -> Bool {
  for n in doc.ancestors(node) {
    if doc.tag(n) == "clipPath" {
      return false
    }
  }
  find_marker_link(doc, node, "marker-start") >= 0 ||
  find_marker_link(doc, node, "marker-mid") >= 0 ||
  find_marker_link(doc, node, "marker-end") >= 0
}

///|
fn find_marker_link(doc : SDoc, node : Int, aid : String) -> Int {
  let n = doc.find_attr_node(node, aid)
  if n < 0 {
    -1
  } else {
    doc.node_attr(n, aid)
  }
}

///|
fn convert_markers(doc : SDoc, node : Int, path : @skia.Path, state : State, cache : Cache, parent : Group) -> Unit {
  for k in [("marker-start", 0), ("marker-mid", 1), ("marker-end", 2)] {
    let link = find_marker_link(doc, node, k.0)
    if link >= 0 && doc.tag(link) == "marker" {
      if state.parent_markers.contains(link) {
        continue
      }
      ignore(resolve_marker(doc, node, path, link, k.1, state, cache, parent))
    }
  }
}

///|
fn resolve_marker(
  doc : SDoc,
  shape : Int,
  path : @skia.Path,
  marker : Int,
  kind : Int,
  state : State,
  cache : Cache,
  parent : Group,
) -> Unit? {
  let stroke_scale : Float = match doc.attr(marker, "markerUnits") {
    Some("userSpaceOnUse") => 1.0
    _ =>
      match doc.resolve_valid_length(shape, "stroke-width", state, 1.0) {
        Some(w) => w
        None => return None
      }
  }
  let r = match
    @skia.NonZeroRect::from_xywh(
      doc.convert_user_length(marker, "refX", state, Length::zero()),
      doc.convert_user_length(marker, "refY", state, Length::zero()),
      doc.convert_user_length(marker, "markerWidth", state, { number: 3.0, unit: LNone }),
      doc.convert_user_length(marker, "markerHeight", state, { number: 3.0, unit: LNone }),
    ) {
    Some(r) => r
    None => return None
  }
  let view_box_ts = match doc.parse_viewbox(marker) {
    Some(vb) => {
      let v : SViewBox = { rect: vb, aspect: doc.attr_aspect(marker).unwrap_or(AspectRatio::default()) }
      v.to_transform(r.size())
    }
    None => @skia.Transform::default()
  }
  let overflow = doc.attr(marker, "overflow")
  let has_overflow = overflow is None || overflow == Some("hidden") || overflow == Some("scroll")
  let clip_path = if has_overflow {
    let inv = match view_box_ts.invert() {
      Some(i) => i
      None => return None
    }
    let clip_rect = match size_to_non_zero_rect(r.size(), 0.0, 0.0).transform(inv) {
      Some(c) => c
      None => return None
    }
    let p = new_simple_path(@skia.PathBuilder::from_rect(clip_rect.to_rect()))
    p.fill = Some(Fill::default())
    let root = Group::empty()
    root.children.push(NPath(p))
    let c : ClipPath = { id: cache.gen_clip_path_id(), transform: @skia.Transform::default(), clip_path: None, root }
    Some(c)
  } else {
    None
  }
  let segments : Array[MSeg] = []
  let mut prev = @skia.Point::zero()
  let mut prev_move = @skia.Point::zero()
  let it = path.segments()
  while it.next() is Some(seg) {
    match seg {
      MoveTo(p) => {
        segments.push(MMove(p))
        prev = p
        prev_move = p
      }
      LineTo(p) => {
        segments.push(MLine(p))
        prev = p
      }
      QuadTo(p1, p) => {
        let calc = fn(n1 : Float, n2 : Float) -> Float { (n1 + n2 * 2.0) / 3.0 }
        segments.push(
          MCubic(@skia.Point::from_xy(calc(prev.x, p1.x), calc(prev.y, p1.y)), @skia.Point::from_xy(calc(p.x, p1.x), calc(p.y, p1.y)), p),
        )
        prev = p
      }
      CubicTo(p1, p2, p) => {
        segments.push(MCubic(p1, p2, p))
        prev = p
      }
      Close => {
        segments.push(MClose)
        prev = prev_move
      }
    }
  }
  let draw_marker = fn(p : @skia.Point, idx : Int) {
    let mut ts = @skia.Transform::from_translate(p.x, p.y)
    let angle = match doc.attr(marker, "orient") {
      Some("auto-start-reverse") =>
        if idx == 0 {
          frem(calc_vertex_angle(segments, idx) + 180.0, 360.0)
        } else {
          calc_vertex_angle(segments, idx)
        }
      Some("auto") => calc_vertex_angle(segments, idx)
      Some(v) =>
        match parse_angle_str(v) {
          Some(a) => fd(a)
          None => 0.0
        }
      None => 0.0
    }
    if !approx_zero(angle) {
      ts = ts.pre_rotate(angle)
    }
    let (sx, sy) = view_box_ts.get_scale()
    ts = ts.pre_scale(sx * stroke_scale, sy * stroke_scale)
    ts = ts.pre_translate(-r.x(), -r.y())
    let g = { ..Group::empty(), transform: ts, abs_transform: parent.abs_transform.pre_concat(ts), clip_path }
    let markers = state.parent_markers.copy()
    markers.push(marker)
    convert_children(doc, marker, { ..state, parent_markers: markers }, cache, g)
    if !g.children.is_empty() {
      parent.children.push(NGroup(g))
    }
  }
  match kind {
    0 =>
      if segments.length() > 0 {
        match segments[0] {
          MMove(p) => draw_marker(p, 0)
          _ => ()
        }
      }
    1 => {
      let total = segments.length() - 1
      let mut i = 1
      while i < total {
        match segments[i] {
          MMove(p) | MLine(p) | MCubic(_, _, p) => draw_marker(p, i)
          MClose => ()
        }
        i += 1
      }
    }
    _ => {
      let idx = segments.length() - 1
      if idx >= 0 {
        match segments[idx] {
          MLine(p) | MCubic(_, _, p) => draw_marker(p, idx)
          MClose => draw_marker(get_subpath_start(segments, idx), idx)
          MMove(_) => ()
        }
      }
    }
  }
  Some(())
}

///|
fn calc_vertex_angle(path : Array[MSeg], idx : Int) -> Float {
  if idx == 0 {
    if path.length() < 2 {
      return 0.0
    }
    match (path[0], path[1]) {
      (MMove(pm), MLine(p)) => calc_line_angle(pm.x, pm.y, p.x, p.y)
      (MMove(pm), MCubic(p1, _, p)) =>
        if approx_eq_ulps(pm.x, p1.x, 4) && approx_eq_ulps(pm.y, p1.y, 4) {
          calc_line_angle(pm.x, pm.y, p.x, p.y)
        } else {
          calc_line_angle(pm.x, pm.y, p1.x, p1.y)
        }
      _ => 0.0
    }
  } else if idx == path.length() - 1 {
    match (path[idx - 1], path[idx]) {
      (_, MMove(_)) => 0.0
      (_, MLine(p)) => {
        let prev = get_prev_vertex(path, idx)
        calc_line_angle(prev.x, prev.y, p.x, p.y)
      }
      (_, MCubic(p1, p2, p)) =>
        if approx_eq_ulps(p2.x, p.x, 4) && approx_eq_ulps(p2.y, p.y, 4) {
          calc_line_angle(p1.x, p1.y, p.x, p.y)
        } else {
          calc_line_angle(p2.x, p2.y, p.x, p.y)
        }
      (MLine(p), MClose) => {
        let next = get_subpath_start(path, idx)
        calc_line_angle(p.x, p.y, next.x, next.y)
      }
      (MCubic(_, p2, p), MClose) => {
        let prev = get_prev_vertex(path, idx)
        let next = get_subpath_start(path, idx)
        calc_curves_angle(prev.x, prev.y, p2.x, p2.y, p.x, p.y, next.x, next.y, next.x, next.y)
      }
      (_, MClose) => 0.0
    }
  } else {
    match (path[idx], path[idx + 1]) {
      (MMove(pm), MLine(p)) => calc_line_angle(pm.x, pm.y, p.x, p.y)
      (MMove(pm), MCubic(p1, _, _)) => calc_line_angle(pm.x, pm.y, p1.x, p1.y)
      (MLine(p1), MLine(p2)) => {
        let prev = get_prev_vertex(path, idx)
        calc_angle(prev.x, prev.y, p1.x, p1.y, p1.x, p1.y, p2.x, p2.y)
      }
      (MCubic(_, c1_p2, c1_p), MCubic(c2_p1, _, c2_p)) => {
        let prev = get_prev_vertex(path, idx)
        calc_curves_angle(prev.x, prev.y, c1_p2.x, c1_p2.y, c1_p.x, c1_p.y, c2_p1.x, c2_p1.y, c2_p.x, c2_p.y)
      }
      (MLine(pl), MCubic(p1, _, p)) => {
        let prev = get_prev_vertex(path, idx)
        calc_curves_angle(prev.x, prev.y, prev.x, prev.y, pl.x, pl.y, p1.x, p1.y, p.x, p.y)
      }
      (MCubic(_, p2, p), MLine(pl)) => {
        let prev = get_prev_vertex(path, idx)
        calc_curves_angle(prev.x, prev.y, p2.x, p2.y, p.x, p.y, pl.x, pl.y, pl.x, pl.y)
      }
      (MLine(p), MMove(_)) => {
        let prev = get_prev_vertex(path, idx)
        calc_line_angle(prev.x, prev.y, p.x, p.y)
      }
      (MCubic(_, p2, p), MMove(_)) =>
        if approx_eq_ulps(p.x, p2.x, 4) && approx_eq_ulps(p.y, p2.y, 4) {
          let prev = get_prev_vertex(path, idx)
          calc_line_angle(prev.x, prev.y, p.x, p.y)
        } else {
          calc_line_angle(p2.x, p2.y, p.x, p.y)
        }
      (MLine(p), MClose) => {
        let prev = get_prev_vertex(path, idx)
        let next = get_subpath_start(path, idx)
        calc_angle(prev.x, prev.y, p.x, p.y, p.x, p.y, next.x, next.y)
      }
      (_, MClose) => {
        let prev = get_prev_vertex(path, idx)
        let next = get_subpath_start(path, idx)
        calc_line_angle(prev.x, prev.y, next.x, next.y)
      }
      (_, MMove(_)) | (MClose, _) => 0.0
    }
  }
}

///|
fn calc_line_angle(x1 : Float, y1 : Float, x2 : Float, y2 : Float) -> Float {
  calc_angle(x1, y1, x2, y2, x1, y1, x2, y2)
}

///|
fn calc_curves_angle(
  px : Float,
  py : Float,
  cx1 : Float,
  cy1 : Float,
  x : Float,
  y : Float,
  cx2 : Float,
  cy2 : Float,
  nx : Float,
  ny : Float,
) -> Float {
  if approx_eq_ulps(cx1, x, 4) && approx_eq_ulps(cy1, y, 4) {
    calc_angle(px, py, x, y, x, y, cx2, cy2)
  } else if approx_eq_ulps(x, cx2, 4) && approx_eq_ulps(y, cy2, 4) {
    calc_angle(cx1, cy1, x, y, x, y, nx, ny)
  } else {
    calc_angle(cx1, cy1, x, y, x, y, cx2, cy2)
  }
}

///|
fn calc_angle(x1 : Float, y1 : Float, x2 : Float, y2 : Float, x3 : Float, y3 : Float, x4 : Float, y4 : Float) -> Float {
  let two_pi : Float = f32_pi * 2.0
  let normalize = fn(rad : Float) -> Float {
    let v = frem(rad, two_pi)
    if v < 0.0 {
      v + two_pi
    } else {
      v
    }
  }
  let vector_angle = fn(vx : Float, vy : Float) -> Float {
    let rad = fatan2(vy, vx)
    if rad.is_nan() {
      0.0
    } else {
      normalize(rad)
    }
  }
  let in_a = vector_angle(x2 - x1, y2 - y1)
  let out_a = vector_angle(x4 - x3, y4 - y3)
  let d = (out_a - in_a) * 0.5
  let mut angle = in_a + d
  if f32_pi / 2.0 < d.abs() {
    angle = angle - f32_pi
  }
  to_degrees(normalize(angle))
}

///|
fn get_subpath_start(segments : Array[MSeg], idx : Int) -> @skia.Point {
  let offset = segments.length() - idx
  // rev().skip(offset): from index idx - 1 down
  let mut i = segments.length() - 1 - offset
  while i >= 0 {
    match segments[i] {
      MMove(p) => return p
      _ => ()
    }
    i -= 1
  }
  @skia.Point::zero()
}

///|
fn get_prev_vertex(segments : Array[MSeg], idx : Int) -> @skia.Point {
  match segments[idx - 1] {
    MMove(p) | MLine(p) | MCubic(_, _, p) => p
    MClose => get_subpath_start(segments, idx)
  }
}
