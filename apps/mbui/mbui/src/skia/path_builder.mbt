// tiny-skia's PathBuilder (path/src/path_builder.rs).

///|
priv enum PathDirection {
  CW
  CCW
} derive(Eq)

///|
pub(all) struct PathBuilder {
  verbs : Array[PathVerb]
  points : Array[Point]
  mut last_move_to_index : Int
  mut move_to_required : Bool
}

///|
pub fn PathBuilder::new() -> PathBuilder {
  { verbs: [], points: [], last_move_to_index: 0, move_to_required: true }
}

///|
pub fn PathBuilder::default() -> PathBuilder {
  PathBuilder::new()
}

///|
pub fn PathBuilder::from_rect(rect : Rect) -> Path {
  {
    bounds: rect,
    verbs: [Move, Line, Line, Line, Close],
    points: [
      Point::from_xy(rect.left, rect.top),
      Point::from_xy(rect.right, rect.top),
      Point::from_xy(rect.right, rect.bottom),
      Point::from_xy(rect.left, rect.bottom),
    ],
  }
}

///|
pub fn PathBuilder::from_circle(cx : Float, cy : Float, radius : Float) -> Path? {
  let b = PathBuilder::new()
  b.push_circle(cx, cy, radius)
  b.finish()
}

///|
pub fn PathBuilder::from_oval(oval : Rect) -> Path? {
  let b = PathBuilder::new()
  b.push_oval(oval)
  b.finish()
}

///|
pub fn PathBuilder::len(self : PathBuilder) -> Int {
  self.verbs.length()
}

///|
pub fn PathBuilder::is_empty(self : PathBuilder) -> Bool {
  self.verbs.is_empty()
}

///|
pub fn PathBuilder::move_to(self : PathBuilder, x : Float, y : Float) -> Unit {
  if self.verbs.last() is Some(Move) {
    self.points[self.points.length() - 1] = Point::from_xy(x, y)
  } else {
    self.last_move_to_index = self.points.length()
    self.move_to_required = false
    self.verbs.push(Move)
    self.points.push(Point::from_xy(x, y))
  }
}

///|
fn PathBuilder::inject_move_to_if_needed(self : PathBuilder) -> Unit {
  if self.move_to_required {
    match self.points.get(self.last_move_to_index) {
      Some(p) => self.move_to(p.x, p.y)
      None => self.move_to(0.0, 0.0)
    }
  }
}

///|
pub fn PathBuilder::line_to(self : PathBuilder, x : Float, y : Float) -> Unit {
  self.inject_move_to_if_needed()
  self.verbs.push(Line)
  self.points.push(Point::from_xy(x, y))
}

///|
pub fn PathBuilder::quad_to(self : PathBuilder, x1 : Float, y1 : Float, x : Float, y : Float) -> Unit {
  self.inject_move_to_if_needed()
  self.verbs.push(Quad)
  self.points.push(Point::from_xy(x1, y1))
  self.points.push(Point::from_xy(x, y))
}

///|
fn PathBuilder::quad_to_pt(self : PathBuilder, p1 : Point, p : Point) -> Unit {
  self.quad_to(p1.x, p1.y, p.x, p.y)
}

///|
fn PathBuilder::conic_to(self : PathBuilder, x1 : Float, y1 : Float, x : Float, y : Float, weight : Float) -> Unit {
  if !(weight > 0.0) {
    self.line_to(x, y)
  } else if !fin(weight) {
    self.line_to(x1, y1)
    self.line_to(x, y)
  } else if weight == 1.0 {
    self.quad_to(x1, y1, x, y)
  } else {
    self.inject_move_to_if_needed()
    let last = self.last_point().unwrap()
    match AutoConicToQuads::compute(last, Point::from_xy(x1, y1), Point::from_xy(x, y), weight) {
      Some(quadder) => {
        let mut offset = 1
        for _ in 0..<quadder.len {
          let pt1 = quadder.points[offset + 0]
          let pt2 = quadder.points[offset + 1]
          self.quad_to(pt1.x, pt1.y, pt2.x, pt2.y)
          offset += 2
        }
      }
      None => ()
    }
  }
}

///|
fn PathBuilder::conic_points_to(self : PathBuilder, pt1 : Point, pt2 : Point, weight : Float) -> Unit {
  self.conic_to(pt1.x, pt1.y, pt2.x, pt2.y, weight)
}

///|
pub fn PathBuilder::cubic_to(
  self : PathBuilder,
  x1 : Float,
  y1 : Float,
  x2 : Float,
  y2 : Float,
  x : Float,
  y : Float,
) -> Unit {
  self.inject_move_to_if_needed()
  self.verbs.push(Cubic)
  self.points.push(Point::from_xy(x1, y1))
  self.points.push(Point::from_xy(x2, y2))
  self.points.push(Point::from_xy(x, y))
}

///|
fn PathBuilder::cubic_to_pt(self : PathBuilder, p1 : Point, p2 : Point, p : Point) -> Unit {
  self.cubic_to(p1.x, p1.y, p2.x, p2.y, p.x, p.y)
}

///|
pub fn PathBuilder::close(self : PathBuilder) -> Unit {
  if !self.verbs.is_empty() {
    if !(self.verbs.last() is Some(Close)) {
      self.verbs.push(Close)
    }
  }
  self.move_to_required = true
}

///|
pub fn PathBuilder::last_point(self : PathBuilder) -> Point? {
  self.points.last()
}

///|
fn PathBuilder::set_last_point(self : PathBuilder, pt : Point) -> Unit {
  if self.points.is_empty() {
    self.move_to(pt.x, pt.y)
  } else {
    self.points[self.points.length() - 1] = pt
  }
}

///|
fn PathBuilder::is_zero_length_since_point(self : PathBuilder, start : Int) -> Bool {
  let count = self.points.length() - start
  if count < 2 {
    return true
  }
  let first = self.points[start]
  for i in 1..<count {
    if first != self.points[start + i] {
      return false
    }
  }
  true
}

///|
pub fn PathBuilder::push_rect(self : PathBuilder, rect : Rect) -> Unit {
  self.move_to(rect.left, rect.top)
  self.line_to(rect.right, rect.top)
  self.line_to(rect.right, rect.bottom)
  self.line_to(rect.left, rect.bottom)
  self.close()
}

///|
pub fn PathBuilder::push_oval(self : PathBuilder, oval : Rect) -> Unit {
  let cx = half(oval.left) + half(oval.right)
  let cy = half(oval.top) + half(oval.bottom)
  let oval_points = [
    Point::from_xy(cx, oval.bottom),
    Point::from_xy(oval.left, cy),
    Point::from_xy(cx, oval.top),
    Point::from_xy(oval.right, cy),
  ]
  let rect_points = [
    Point::from_xy(oval.right, oval.bottom),
    Point::from_xy(oval.left, oval.bottom),
    Point::from_xy(oval.left, oval.top),
    Point::from_xy(oval.right, oval.top),
  ]
  self.move_to(oval_points[3].x, oval_points[3].y)
  for i in 0..<4 {
    self.conic_points_to(rect_points[i], oval_points[i], scalar_root_2_over_2)
  }
  self.close()
}

///|
pub fn PathBuilder::push_circle(self : PathBuilder, x : Float, y : Float, r : Float) -> Unit {
  match Rect::from_xywh(x - r, y - r, r + r, r + r) {
    Some(r) => self.push_oval(r)
    None => ()
  }
}

///|
pub fn PathBuilder::push_path(self : PathBuilder, other : Path) -> Unit {
  self.last_move_to_index = self.points.length()
  self.verbs.append(other.verbs)
  self.points.append(other.points)
}

///|
fn PathBuilder::push_path_builder(self : PathBuilder, other : PathBuilder) -> Unit {
  if other.is_empty() {
    return
  }
  if self.last_move_to_index != 0 {
    self.last_move_to_index = self.points.length() + other.last_move_to_index
  }
  self.verbs.append(other.verbs)
  self.points.append(other.points)
}

///|
fn PathBuilder::reverse_path_to(self : PathBuilder, other : PathBuilder) -> Unit {
  if other.is_empty() {
    return
  }
  let mut off = other.points.length() - 1
  let mut i = other.verbs.length() - 1
  while i >= 0 {
    match other.verbs[i] {
      Move => break
      Line => {
        let pt = other.points[off - 1]
        off -= 1
        self.line_to(pt.x, pt.y)
      }
      Quad => {
        let pt1 = other.points[off - 1]
        let pt2 = other.points[off - 2]
        off -= 2
        self.quad_to(pt1.x, pt1.y, pt2.x, pt2.y)
      }
      Cubic => {
        let pt1 = other.points[off - 1]
        let pt2 = other.points[off - 2]
        let pt3 = other.points[off - 3]
        off -= 3
        self.cubic_to(pt1.x, pt1.y, pt2.x, pt2.y, pt3.x, pt3.y)
      }
      Close => ()
    }
    i -= 1
  }
}

///|
pub fn PathBuilder::clear(self : PathBuilder) -> Unit {
  self.verbs.clear()
  self.points.clear()
  self.last_move_to_index = 0
  self.move_to_required = true
}

///|
/// The path made (None when it is empty, a lone move, or its bounds are not finite).
pub fn PathBuilder::finish(self : PathBuilder) -> Path? {
  if self.is_empty() || self.verbs.length() == 1 {
    return None
  }
  match Rect::from_points(self.points) {
    Some(bounds) => Some({ bounds, verbs: self.verbs.copy(), points: self.points.copy() })
    None => None
  }
}
