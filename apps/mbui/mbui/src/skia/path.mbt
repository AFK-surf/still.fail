// tiny-skia's Path (path/src/path.rs): verbs and points, never empty, with its bounds.

///|
pub(all) enum PathVerb {
  Move
  Line
  Quad
  Cubic
  Close
} derive(Eq, Show, Debug)

///|
pub(all) enum PathSegment {
  MoveTo(Point)
  LineTo(Point)
  QuadTo(Point, Point)
  CubicTo(Point, Point, Point)
  Close
} derive(Eq, Show, Debug)

///|
/// A path of at least one segment past its first move (PathBuilder::finish), its points' bounds.
pub(all) struct Path {
  verbs : Array[PathVerb]
  points : Array[Point]
  mut bounds : Rect
}

///|
pub fn Path::len(self : Path) -> Int {
  self.verbs.length()
}

///|
pub fn Path::is_empty(self : Path) -> Bool {
  self.verbs.is_empty()
}

///|
pub fn Path::bounds(self : Path) -> Rect {
  self.bounds
}

///|
/// The bounds of the curves themselves, not of their control points.
pub fn Path::compute_tight_bounds(self : Path) -> Rect? {
  let extremas = Array::makei(5, fn(_) { Point::zero() })
  let mut min = self.points[0]
  let mut max = self.points[0]
  let iter = self.segments()
  let mut last_point = Point::zero()
  while iter.next() is Some(segment) {
    let mut count = 0
    match segment {
      MoveTo(p) | LineTo(p) => {
        extremas[0] = p
        count = 1
      }
      QuadTo(p0, p1) => count = compute_quad_extremas(last_point, p0, p1, extremas)
      CubicTo(p0, p1, p2) => count = compute_cubic_extremas(last_point, p0, p1, p2, extremas)
      Close => ()
    }
    last_point = iter.last_point
    for i in 0..<count {
      let tmp = extremas[i]
      min = { x: fmin(min.x, tmp.x), y: fmin(min.y, tmp.y) }
      max = { x: fmax(max.x, tmp.x), y: fmax(max.y, tmp.y) }
    }
  }
  Rect::from_ltrb(min.x, min.y, max.x, max.y)
}

///|
/// The path moved by `ts` (its points mapped), None when its bounds would not be finite.
pub fn Path::transform(self : Path, ts : Transform) -> Path? {
  if ts.is_identity() {
    return Some(self)
  }
  let points = self.points.copy()
  ts.map_points(points)
  match Rect::from_points(points) {
    Some(bounds) => Some({ verbs: self.verbs.copy(), points, bounds })
    None => None
  }
}

///|
pub fn Path::segments(self : Path) -> PathSegmentsIter {
  {
    path: self,
    verb_index: 0,
    points_index: 0,
    is_auto_close: false,
    last_move_to: Point::zero(),
    last_point: Point::zero(),
  }
}

///|
pub fn Path::clear(self : Path) -> PathBuilder {
  PathBuilder::new()
}

///|
/// The path as SVG path data (Debug's segments: "M 1 2 L 3 4 Z").
pub fn Path::to_svg(self : Path) -> String {
  let s = StringBuilder::new()
  let iter = self.segments()
  let parts : Array[String] = []
  while iter.next() is Some(seg) {
    match seg {
      MoveTo(p) => parts.push("M \{fs(p.x)} \{fs(p.y)}")
      LineTo(p) => parts.push("L \{fs(p.x)} \{fs(p.y)}")
      QuadTo(p0, p1) => parts.push("Q \{fs(p0.x)} \{fs(p0.y)} \{fs(p1.x)} \{fs(p1.y)}")
      CubicTo(p0, p1, p2) =>
        parts.push("C \{fs(p0.x)} \{fs(p0.y)} \{fs(p1.x)} \{fs(p1.y)} \{fs(p2.x)} \{fs(p2.y)}")
      Close => parts.push("Z")
    }
  }
  s.write_string(parts.join(" "))
  s.to_string()
}

///|
/// A float as Rust's Display writes it (the shortest that reads back; whole numbers without a point).
fn fs(x : Float) -> String {
  let s = x.to_string()
  if s.has_suffix(".0") {
    s.view(end_offset=s.length() - 2).to_string()
  } else {
    s
  }
}

///|
fn compute_quad_extremas(p0 : Point, p1 : Point, p2 : Point, extremas : Array[Point]) -> Int {
  let src = [p0, p1, p2]
  let mut idx = 0
  match find_quad_extrema(p0.x, p1.x, p2.x) {
    Some(t) => {
      extremas[idx] = eval_quad_at(src, t)
      idx += 1
    }
    None => ()
  }
  match find_quad_extrema(p0.y, p1.y, p2.y) {
    Some(t) => {
      extremas[idx] = eval_quad_at(src, t)
      idx += 1
    }
    None => ()
  }
  extremas[idx] = p2
  idx + 1
}

///|
fn compute_cubic_extremas(p0 : Point, p1 : Point, p2 : Point, p3 : Point, extremas : Array[Point]) -> Int {
  let ts0 = new_t_values()
  let ts1 = new_t_values()
  let n0 = find_cubic_extrema(p0.x, p1.x, p2.x, p3.x, ts0)
  let n1 = find_cubic_extrema(p0.y, p1.y, p2.y, p3.y, ts1)
  let total = n0 + n1
  let src = [p0, p1, p2, p3]
  let mut idx = 0
  for i in 0..<n0 {
    extremas[idx] = eval_cubic_pos_at(src, ts0[i])
    idx += 1
  }
  for i in 0..<n1 {
    extremas[idx] = eval_cubic_pos_at(src, ts1[i])
    idx += 1
  }
  extremas[total] = p3
  total + 1
}

///|
pub(all) struct PathSegmentsIter {
  path : Path
  mut verb_index : Int
  mut points_index : Int
  mut is_auto_close : Bool
  mut last_move_to : Point
  mut last_point : Point
}

///|
fn PathSegmentsIter::clone(self : PathSegmentsIter) -> PathSegmentsIter {
  {
    path: self.path,
    verb_index: self.verb_index,
    points_index: self.points_index,
    is_auto_close: self.is_auto_close,
    last_move_to: self.last_move_to,
    last_point: self.last_point,
  }
}

///|
pub fn PathSegmentsIter::set_auto_close(self : PathSegmentsIter, flag : Bool) -> Unit {
  self.is_auto_close = flag
}

///|
fn PathSegmentsIter::auto_close(self : PathSegmentsIter) -> PathSegment {
  if self.is_auto_close && self.last_point != self.last_move_to {
    self.verb_index -= 1
    LineTo(self.last_move_to)
  } else {
    Close
  }
}

///|
fn PathSegmentsIter::has_valid_tangent(self : PathSegmentsIter) -> Bool {
  let iter = self.clone()
  while iter.next() is Some(segment) {
    match segment {
      MoveTo(_) => return false
      LineTo(p) => {
        if iter.last_point == p {
          continue
        }
        return true
      }
      QuadTo(p1, p2) => {
        if iter.last_point == p1 && iter.last_point == p2 {
          continue
        }
        return true
      }
      CubicTo(p1, p2, p3) => {
        if iter.last_point == p1 && iter.last_point == p2 && iter.last_point == p3 {
          continue
        }
        return true
      }
      Close => return false
    }
  }
  false
}

///|
pub fn PathSegmentsIter::curr_verb(self : PathSegmentsIter) -> PathVerb {
  self.path.verbs[self.verb_index - 1]
}

///|
pub fn PathSegmentsIter::next_verb(self : PathSegmentsIter) -> PathVerb? {
  self.path.verbs.get(self.verb_index)
}

///|
pub fn PathSegmentsIter::next(self : PathSegmentsIter) -> PathSegment? {
  if self.verb_index < self.path.verbs.length() {
    let verb = self.path.verbs[self.verb_index]
    self.verb_index += 1
    let pts = self.path.points
    match verb {
      Move => {
        self.points_index += 1
        self.last_move_to = pts[self.points_index - 1]
        self.last_point = self.last_move_to
        Some(MoveTo(self.last_move_to))
      }
      Line => {
        self.points_index += 1
        self.last_point = pts[self.points_index - 1]
        Some(LineTo(self.last_point))
      }
      Quad => {
        self.points_index += 2
        self.last_point = pts[self.points_index - 1]
        Some(QuadTo(pts[self.points_index - 2], self.last_point))
      }
      Cubic => {
        self.points_index += 3
        self.last_point = pts[self.points_index - 1]
        Some(CubicTo(pts[self.points_index - 3], pts[self.points_index - 2], self.last_point))
      }
      Close => {
        let seg = self.auto_close()
        self.last_point = self.last_move_to
        Some(seg)
      }
    }
  } else {
    None
  }
}
