// tiny-skia's curve chopping at extrema (src/path_geometry.rs), line and edge clipping (src/line_clipper.rs,
// src/edge_clipper.rs) and edge building (src/edge_builder.rs), after Skia's SkGeometry, SkLineClipper,
// SkEdgeClipper and SkEdgeBuilder.

///|
fn set_x(p : Array[Point], i : Int, x : Float) -> Unit {
  p[i] = { x, y: p[i].y }
}

///|
fn set_y(p : Array[Point], i : Int, y : Float) -> Unit {
  p[i] = { x: p[i].x, y }
}

///|
fn swap_pts(p : Array[Point], i : Int, j : Int) -> Unit {
  let t = p[i]
  p[i] = p[j]
  p[j] = t
}

///|
fn chop_quad_at_x_extrema(src : Array[Point], dst : Array[Point]) -> Int {
  let a = src[0].x
  let mut b = src[1].x
  let c = src[2].x
  if is_not_monotonic(a, b, c) {
    match valid_unit_divide(a - b, a - b - b + c) {
      Some(t) => {
        chop_quad_at(src, 0, t, dst, 0)
        set_x(dst, 1, dst[2].x)
        set_x(dst, 3, dst[2].x)
        return 1
      }
      None => ()
    }
    b = if (a - b).abs() < (b - c).abs() { a } else { c }
  }
  dst[0] = Point::from_xy(a, src[0].y)
  dst[1] = Point::from_xy(b, src[1].y)
  dst[2] = Point::from_xy(c, src[2].y)
  0
}

///|
fn chop_quad_at_y_extrema(src : Array[Point], dst : Array[Point]) -> Int {
  let a = src[0].y
  let mut b = src[1].y
  let c = src[2].y
  if is_not_monotonic(a, b, c) {
    match valid_unit_divide(a - b, a - b - b + c) {
      Some(t) => {
        chop_quad_at(src, 0, t, dst, 0)
        set_y(dst, 1, dst[2].y)
        set_y(dst, 3, dst[2].y)
        return 1
      }
      None => ()
    }
    b = if (a - b).abs() < (b - c).abs() { a } else { c }
  }
  dst[0] = Point::from_xy(src[0].x, a)
  dst[1] = Point::from_xy(src[1].x, b)
  dst[2] = Point::from_xy(src[2].x, c)
  0
}

///|
fn is_not_monotonic(a : Float, b : Float, c : Float) -> Bool {
  let ab = a - b
  let mut bc = b - c
  if ab < 0.0 {
    bc = -bc
  }
  ab == 0.0 || bc < 0.0
}

///|
fn chop_cubic_at_x_extrema(src : Array[Point], dst : Array[Point]) -> Int {
  let t_values = new_t_values()
  let n = find_cubic_extrema(src[0].x, src[1].x, src[2].x, src[3].x, t_values)
  chop_cubic_at(src, t_values, n, dst)
  if n > 0 {
    set_x(dst, 2, dst[3].x)
    set_x(dst, 4, dst[3].x)
    if n == 2 {
      set_x(dst, 5, dst[6].x)
      set_x(dst, 7, dst[6].x)
    }
  }
  n
}

///|
fn chop_cubic_at_y_extrema(src : Array[Point], dst : Array[Point]) -> Int {
  let t_values = new_t_values()
  let n = find_cubic_extrema(src[0].y, src[1].y, src[2].y, src[3].y, t_values)
  chop_cubic_at(src, t_values, n, dst)
  if n > 0 {
    set_y(dst, 2, dst[3].y)
    set_y(dst, 4, dst[3].y)
    if n == 2 {
      set_y(dst, 5, dst[6].y)
      set_y(dst, 7, dst[6].y)
    }
  }
  n
}

///|
/// `src` cut at the first `n` of `t_values` into `dst`.
fn chop_cubic_at(src : Array[Point], t_values : Array[Float], n : Int, dst : Array[Point]) -> Unit {
  if n == 0 {
    for i in 0..<4 {
      dst[i] = src[i]
    }
  } else {
    let mut t = t_values[0]
    let mut src = src
    let mut dst_offset = 0
    for i in 0..<n {
      chop_cubic_at2(src, 0, t, dst, dst_offset)
      if i == n - 1 {
        break
      }
      dst_offset += 3
      let tmp = [dst[dst_offset], dst[dst_offset + 1], dst[dst_offset + 2], dst[dst_offset + 3]]
      src = tmp
      match valid_unit_divide(t_values[i + 1] - t_values[i], 1.0 - t_values[i]) {
        Some(nt) => t = nt
        None => {
          dst[dst_offset + 4] = src[3]
          dst[dst_offset + 5] = src[3]
          dst[dst_offset + 6] = src[3]
          break
        }
      }
    }
  }
}

///|
fn chop_cubic_at_max_curvature(src : Array[Point], t_values : Array[Float], dst : Array[Point]) -> Int {
  let roots : Array[Float] = [0.0, 0.0, 0.0]
  let nr = find_cubic_max_curvature(src, roots)
  let mut count = 0
  for i in 0..<nr {
    let root = roots[i]
    if root > 0.0 && root < 1.0 {
      t_values[count] = norm_excl_bounded(root)
      count += 1
    }
  }
  if count == 0 {
    for i in 0..<4 {
      dst[i] = src[i]
    }
  } else {
    chop_cubic_at(src, t_values, count, dst)
  }
  count + 1
}

///|
/// `src` cut where it crosses x (`is_vertical`) or y = `intercept` into `dst` (7 points); false where it does not.
fn cubic_dchop_at_intercept(src : Array[Point], intercept : Float, is_vertical : Bool, dst : Array[Point]) -> Bool {
  let cubic = Cubic64::from_points(src, 0)
  match cubic_intercept(cubic, intercept.to_double(), is_vertical) {
    Some(t) => {
      let pair = cubic.chop_at(t)
      for i in 0..<7 {
        dst[i] = Point::from_xy(fd(pair[i].0), fd(pair[i].1))
      }
      true
    }
    None => false
  }
}

// ── the line clipper ──────────────────────────────────────────────────

///|
/// The line `src` clipped to `clip` (line_clipper::clip): its points (up to 4: vertical pieces at the sides kept),
/// none where it is above, below or culled to the right.
fn line_clip(src : Array[Point], clip : Rect, can_cull_to_the_right : Bool) -> Array[Point] {
  let mut index0 = if src[0].y < src[1].y { 0 } else { 1 }
  let mut index1 = 1 - index0
  if src[index1].y <= clip.top {
    return []
  }
  if src[index0].y >= clip.bottom {
    return []
  }
  let tmp = [src[0], src[1]]
  if src[index0].y < clip.top {
    tmp[index0] = Point::from_xy(sect_with_horizontal(src, clip.top), clip.top)
  }
  if tmp[index1].y > clip.bottom {
    tmp[index1] = Point::from_xy(sect_with_horizontal(src, clip.bottom), clip.bottom)
  }
  let result_storage = Array::make(4, Point::zero())
  let mut line_count = 1
  let mut reverse = false
  if src[0].x < src[1].x {
    index0 = 0
    index1 = 1
    reverse = false
  } else {
    index0 = 1
    index1 = 0
    reverse = true
  }
  let result = if tmp[index1].x <= clip.left {
    set_x(tmp, 0, clip.left)
    set_x(tmp, 1, clip.left)
    reverse = false
    tmp
  } else if tmp[index0].x >= clip.right {
    if can_cull_to_the_right {
      return []
    }
    set_x(tmp, 0, clip.right)
    set_x(tmp, 1, clip.right)
    reverse = false
    tmp
  } else {
    let mut offset = 0
    if tmp[index0].x < clip.left {
      result_storage[offset] = Point::from_xy(clip.left, tmp[index0].y)
      offset += 1
      result_storage[offset] = Point::from_xy(clip.left, sect_clamp_with_vertical(tmp, clip.left))
    } else {
      result_storage[offset] = tmp[index0]
    }
    offset += 1
    if tmp[index1].x > clip.right {
      result_storage[offset] = Point::from_xy(clip.right, sect_clamp_with_vertical(tmp, clip.right))
      offset += 1
      result_storage[offset] = Point::from_xy(clip.right, tmp[index1].y)
    } else {
      result_storage[offset] = tmp[index1]
    }
    line_count = offset
    result_storage
  }
  let points = Array::make(line_count + 1, Point::zero())
  if reverse {
    for i in 0..=line_count {
      points[line_count - i] = result[i]
    }
  } else {
    for i in 0..=line_count {
      points[i] = result[i]
    }
  }
  points
}

///|
fn sect_with_horizontal(src : Array[Point], y : Float) -> Float {
  let dy = src[1].y - src[0].y
  if is_nearly_zero(dy) {
    ave(src[0].x, src[1].x)
  } else {
    let x0 = src[0].x.to_double()
    let y0 = src[0].y.to_double()
    let x1 = src[1].x.to_double()
    let y1 = src[1].y.to_double()
    let result = x0 + (y.to_double() - y0) * (x1 - x0) / (y1 - y0)
    fd(pin_unsorted_f64(result, x0, x1))
  }
}

///|
fn sect_clamp_with_vertical(src : Array[Point], x : Float) -> Float {
  let y = sect_with_vertical(src, x)
  pin_unsorted_f32(y, src[0].y, src[1].y)
}

///|
fn sect_with_vertical(src : Array[Point], x : Float) -> Float {
  let dx = src[1].x - src[0].x
  if is_nearly_zero(dx) {
    ave(src[0].y, src[1].y)
  } else {
    let x0 = src[0].x.to_double()
    let y0 = src[0].y.to_double()
    let x1 = src[1].x.to_double()
    let y1 = src[1].y.to_double()
    fd(y0 + (x.to_double() - x0) * (y1 - y0) / (x1 - x0))
  }
}

///|
fn pin_unsorted_f32(value : Float, limit0 : Float, limit1 : Float) -> Float {
  let (l0, l1) = if limit1 < limit0 { (limit1, limit0) } else { (limit0, limit1) }
  if value < l0 {
    l0
  } else if value > l1 {
    l1
  } else {
    value
  }
}

///|
fn pin_unsorted_f64(value : Double, limit0 : Double, limit1 : Double) -> Double {
  let (l0, l1) = if limit1 < limit0 { (limit1, limit0) } else { (limit0, limit1) }
  if value < l0 {
    l0
  } else if value > l1 {
    l1
  } else {
    value
  }
}

///|
/// The line `src` cut to `clip` into `dst` (line_clipper::intersect, for hairlines); false where none of it is in.
fn line_intersect(src : Array[Point], clip : Rect, dst : Array[Point]) -> Bool {
  match
    Rect::from_ltrb(
      fmin(src[0].x, src[1].x),
      fmin(src[0].y, src[1].y),
      fmax(src[0].x, src[1].x),
      fmax(src[0].y, src[1].y),
    ) {
    Some(bounds) => {
      if contains_no_empty_check(clip, bounds) {
        dst[0] = src[0]
        dst[1] = src[1]
        return true
      }
      if nested_lt(bounds.right, clip.left, bounds.width()) ||
        nested_lt(clip.right, bounds.left, bounds.width()) ||
        nested_lt(bounds.bottom, clip.top, bounds.height()) ||
        nested_lt(clip.bottom, bounds.top, bounds.height()) {
        return false
      }
    }
    None => ()
  }
  let (index0, index1) = if src[0].y < src[1].y { (0, 1) } else { (1, 0) }
  let tmp = [src[0], src[1]]
  if tmp[index0].y < clip.top {
    tmp[index0] = Point::from_xy(sect_with_horizontal(src, clip.top), clip.top)
  }
  if tmp[index1].y > clip.bottom {
    tmp[index1] = Point::from_xy(sect_with_horizontal(src, clip.bottom), clip.bottom)
  }
  let (index0, index1) = if tmp[0].x < tmp[1].x { (0, 1) } else { (1, 0) }
  if tmp[index1].x <= clip.left || tmp[index0].x >= clip.right {
    if tmp[0].x != tmp[1].x || tmp[0].x < clip.left || tmp[0].x > clip.right {
      return false
    }
  }
  if tmp[index0].x < clip.left {
    tmp[index0] = Point::from_xy(clip.left, sect_with_vertical(src, clip.left))
  }
  if tmp[index1].x > clip.right {
    tmp[index1] = Point::from_xy(clip.right, sect_with_vertical(src, clip.right))
  }
  dst[0] = tmp[0]
  dst[1] = tmp[1]
  true
}

///|
fn nested_lt(a : Float, b : Float, dim : Float) -> Bool {
  a <= b && (a < b || dim > 0.0)
}

///|
fn contains_no_empty_check(outer : Rect, inner : Rect) -> Bool {
  outer.left <= inner.left && outer.top <= inner.top && outer.right >= inner.right && outer.bottom >= inner.bottom
}

// ── path edges ────────────────────────────────────────────────────────

///|
priv enum PathEdge {
  ELineTo(Point, Point)
  EQuadTo(Point, Point, Point)
  ECubicTo(Point, Point, Point, Point)
}

///|
/// A path's edges, each contour closed by a line back to its start (edge_builder::edge_iter).
priv struct PathEdgeIter {
  path : Path
  mut verb_index : Int
  mut points_index : Int
  mut move_to : Point
  mut needs_close_line : Bool
}

///|
fn edge_iter(path : Path) -> PathEdgeIter {
  { path, verb_index: 0, points_index: 0, move_to: Point::zero(), needs_close_line: false }
}

///|
fn PathEdgeIter::close_line(self : PathEdgeIter) -> PathEdge? {
  self.needs_close_line = false
  Some(ELineTo(self.path.points[self.points_index - 1], self.move_to))
}

///|
fn PathEdgeIter::next(self : PathEdgeIter) -> PathEdge? {
  let pts = self.path.points
  while self.verb_index < self.path.verbs.length() {
    let verb = self.path.verbs[self.verb_index]
    self.verb_index += 1
    match verb {
      Move => {
        if self.needs_close_line {
          let res = self.close_line()
          self.move_to = pts[self.points_index]
          self.points_index += 1
          return res
        }
        self.move_to = pts[self.points_index]
        self.points_index += 1
      }
      Close => if self.needs_close_line { return self.close_line() }
      Line => {
        self.needs_close_line = true
        let e = ELineTo(pts[self.points_index - 1], pts[self.points_index])
        self.points_index += 1
        return Some(e)
      }
      Quad => {
        self.needs_close_line = true
        let e = EQuadTo(pts[self.points_index - 1], pts[self.points_index], pts[self.points_index + 1])
        self.points_index += 2
        return Some(e)
      }
      Cubic => {
        self.needs_close_line = true
        let e = ECubicTo(
          pts[self.points_index - 1],
          pts[self.points_index],
          pts[self.points_index + 1],
          pts[self.points_index + 2],
        )
        self.points_index += 3
        return Some(e)
      }
    }
  }
  if self.needs_close_line {
    self.close_line()
  } else {
    None
  }
}

// ── the edge clipper ──────────────────────────────────────────────────

///|
priv struct EdgeClipper {
  clip : Rect
  can_cull_to_the_right : Bool
  edges : Array[PathEdge]
}

///|
fn EdgeClipper::clip_line(self : EdgeClipper, p0 : Point, p1 : Point) -> Array[PathEdge]? {
  let points = line_clip([p0, p1], self.clip, self.can_cull_to_the_right)
  if !points.is_empty() {
    for i in 0..<(points.length() - 1) {
      self.edges.push(ELineTo(points[i], points[i + 1]))
    }
  }
  if self.edges.is_empty() {
    None
  } else {
    Some(self.edges)
  }
}

///|
fn EdgeClipper::push_vline(self : EdgeClipper, x : Float, y0 : Float, y1 : Float, reverse : Bool) -> Unit {
  let (y0, y1) = if reverse { (y1, y0) } else { (y0, y1) }
  self.edges.push(ELineTo(Point::from_xy(x, y0), Point::from_xy(x, y1)))
}

///|
fn EdgeClipper::clip_quad(self : EdgeClipper, p0 : Point, p1 : Point, p2 : Point) -> Array[PathEdge]? {
  let pts = [p0, p1, p2]
  let bounds = match Rect::from_points(pts) {
    Some(b) => b
    None => return None
  }
  if !quick_reject(bounds, self.clip) {
    let mono_y = Array::make(5, Point::zero())
    let count_y = chop_quad_at_y_extrema(pts, mono_y)
    for y in 0..=count_y {
      let mono_x = Array::make(5, Point::zero())
      let y_points = [mono_y[y * 2], mono_y[y * 2 + 1], mono_y[y * 2 + 2]]
      let count_x = chop_quad_at_x_extrema(y_points, mono_x)
      for x in 0..=count_x {
        self.clip_mono_quad([mono_x[x * 2], mono_x[x * 2 + 1], mono_x[x * 2 + 2]])
      }
    }
  }
  if self.edges.is_empty() {
    None
  } else {
    Some(self.edges)
  }
}

///|
fn EdgeClipper::clip_mono_quad(self : EdgeClipper, src : Array[Point]) -> Unit {
  let pts = Array::make(3, Point::zero())
  let mut reverse = sort_increasing_y(src, pts)
  let clip = self.clip
  if pts[2].y <= clip.top || pts[0].y >= clip.bottom {
    return
  }
  chop_quad_in_y(clip, pts)
  if pts[0].x > pts[2].x {
    swap_pts(pts, 0, 2)
    reverse = !reverse
  }
  if pts[2].x <= clip.left {
    self.push_vline(clip.left, pts[0].y, pts[2].y, reverse)
    return
  }
  if pts[0].x >= clip.right {
    if !self.can_cull_to_the_right {
      self.push_vline(clip.right, pts[0].y, pts[2].y, reverse)
    }
    return
  }
  let tmp = Array::make(5, Point::zero())
  if pts[0].x < clip.left {
    match chop_mono_quad_at(pts[0].x, pts[1].x, pts[2].x, clip.left) {
      Some(t) => {
        chop_quad_at(pts, 0, t, tmp, 0)
        self.push_vline(clip.left, tmp[0].y, tmp[2].y, reverse)
        set_x(tmp, 2, clip.left)
        set_x(tmp, 3, fmax(tmp[3].x, clip.left))
        pts[0] = tmp[2]
        pts[1] = tmp[3]
      }
      None => {
        self.push_vline(clip.left, pts[0].y, pts[2].y, reverse)
        return
      }
    }
  }
  if pts[2].x > clip.right {
    match chop_mono_quad_at(pts[0].x, pts[1].x, pts[2].x, clip.right) {
      Some(t) => {
        chop_quad_at(pts, 0, t, tmp, 0)
        set_x(tmp, 1, fmin(tmp[1].x, clip.right))
        set_x(tmp, 2, clip.right)
        self.push_quad([tmp[0], tmp[1], tmp[2]], reverse)
        self.push_vline(clip.right, tmp[2].y, tmp[4].y, reverse)
      }
      None => {
        set_x(pts, 1, fmin(pts[1].x, clip.right))
        set_x(pts, 2, fmin(pts[2].x, clip.right))
        self.push_quad(pts, reverse)
      }
    }
  } else {
    self.push_quad(pts, reverse)
  }
}

///|
fn EdgeClipper::push_quad(self : EdgeClipper, pts : Array[Point], reverse : Bool) -> Unit {
  if reverse {
    self.edges.push(EQuadTo(pts[2], pts[1], pts[0]))
  } else {
    self.edges.push(EQuadTo(pts[0], pts[1], pts[2]))
  }
}

///|
fn EdgeClipper::clip_cubic(self : EdgeClipper, p0 : Point, p1 : Point, p2 : Point, p3 : Point) -> Array[PathEdge]? {
  let pts = [p0, p1, p2, p3]
  let bounds = match Rect::from_points(pts) {
    Some(b) => b
    None => return None
  }
  if bounds.bottom > self.clip.top && bounds.top < self.clip.bottom {
    if too_big_for_reliable_float_math(bounds) {
      return self.clip_line(p0, p3)
    } else {
      let mono_y = Array::make(10, Point::zero())
      let count_y = chop_cubic_at_y_extrema(pts, mono_y)
      for y in 0..=count_y {
        let mono_x = Array::make(10, Point::zero())
        let y_points = [mono_y[y * 3], mono_y[y * 3 + 1], mono_y[y * 3 + 2], mono_y[y * 3 + 3]]
        let count_x = chop_cubic_at_x_extrema(y_points, mono_x)
        for x in 0..=count_x {
          self.clip_mono_cubic([mono_x[x * 3], mono_x[x * 3 + 1], mono_x[x * 3 + 2], mono_x[x * 3 + 3]])
        }
      }
    }
  }
  if self.edges.is_empty() {
    None
  } else {
    Some(self.edges)
  }
}

///|
fn EdgeClipper::clip_mono_cubic(self : EdgeClipper, src : Array[Point]) -> Unit {
  let pts = Array::make(4, Point::zero())
  let mut reverse = sort_increasing_y(src, pts)
  let clip = self.clip
  if pts[3].y <= clip.top || pts[0].y >= clip.bottom {
    return
  }
  chop_cubic_in_y(clip, pts)
  if pts[0].x > pts[3].x {
    swap_pts(pts, 0, 3)
    swap_pts(pts, 1, 2)
    reverse = !reverse
  }
  if pts[3].x <= clip.left {
    self.push_vline(clip.left, pts[0].y, pts[3].y, reverse)
    return
  }
  if pts[0].x >= clip.right {
    if !self.can_cull_to_the_right {
      self.push_vline(clip.right, pts[0].y, pts[3].y, reverse)
    }
    return
  }
  if pts[0].x < clip.left {
    let tmp = Array::make(7, Point::zero())
    chop_mono_cubic_at_x(pts, clip.left, tmp)
    self.push_vline(clip.left, tmp[0].y, tmp[3].y, reverse)
    set_x(tmp, 3, clip.left)
    set_x(tmp, 4, fmax(tmp[4].x, clip.left))
    pts[0] = tmp[3]
    pts[1] = tmp[4]
    pts[2] = tmp[5]
  }
  if pts[3].x > clip.right {
    let tmp = Array::make(7, Point::zero())
    chop_mono_cubic_at_x(pts, clip.right, tmp)
    set_x(tmp, 3, clip.right)
    set_x(tmp, 2, fmin(tmp[2].x, clip.right))
    self.push_cubic([tmp[0], tmp[1], tmp[2], tmp[3]], reverse)
    self.push_vline(clip.right, tmp[3].y, tmp[6].y, reverse)
  } else {
    self.push_cubic(pts, reverse)
  }
}

///|
fn EdgeClipper::push_cubic(self : EdgeClipper, pts : Array[Point], reverse : Bool) -> Unit {
  if reverse {
    self.edges.push(ECubicTo(pts[3], pts[2], pts[1], pts[0]))
  } else {
    self.edges.push(ECubicTo(pts[0], pts[1], pts[2], pts[3]))
  }
}

///|
/// The path's edges clipped to `clip`, a group per edge of the path (EdgeClipperIter).
fn clipped_edges(path : Path, clip : Rect, can_cull_to_the_right : Bool, each : (Array[PathEdge]) -> Bool) -> Bool {
  let iter = edge_iter(path)
  while iter.next() is Some(edge) {
    let clipper : EdgeClipper = { clip, can_cull_to_the_right, edges: [] }
    let edges = match edge {
      ELineTo(p0, p1) => clipper.clip_line(p0, p1)
      EQuadTo(p0, p1, p2) => clipper.clip_quad(p0, p1, p2)
      ECubicTo(p0, p1, p2, p3) => clipper.clip_cubic(p0, p1, p2, p3)
    }
    match edges {
      Some(es) => if !each(es) { return false }
      None => ()
    }
  }
  true
}

///|
fn quick_reject(bounds : Rect, clip : Rect) -> Bool {
  bounds.top >= clip.bottom || bounds.bottom <= clip.top
}

///|
fn sort_increasing_y(src : Array[Point], dst : Array[Point]) -> Bool {
  let n = src.length()
  if src[0].y > src[n - 1].y {
    for i in 0..<n {
      dst[i] = src[n - 1 - i]
    }
    true
  } else {
    for i in 0..<n {
      dst[i] = src[i]
    }
    false
  }
}

///|
fn chop_quad_in_y(clip : Rect, pts : Array[Point]) -> Unit {
  let tmp = Array::make(5, Point::zero())
  if pts[0].y < clip.top {
    match chop_mono_quad_at(pts[0].y, pts[1].y, pts[2].y, clip.top) {
      Some(t) => {
        chop_quad_at(pts, 0, t, tmp, 0)
        set_y(tmp, 2, clip.top)
        set_y(tmp, 3, fmax(tmp[3].y, clip.top))
        pts[0] = tmp[2]
        pts[1] = tmp[3]
      }
      None =>
        for i in 0..<3 {
          if pts[i].y < clip.top {
            set_y(pts, i, clip.top)
          }
        }
    }
  }
  if pts[2].y > clip.bottom {
    match chop_mono_quad_at(pts[0].y, pts[1].y, pts[2].y, clip.bottom) {
      Some(t) => {
        chop_quad_at(pts, 0, t, tmp, 0)
        set_y(tmp, 1, fmin(tmp[1].y, clip.bottom))
        set_y(tmp, 2, clip.bottom)
        pts[1] = tmp[1]
        pts[2] = tmp[2]
      }
      None =>
        for i in 0..<3 {
          if pts[i].y > clip.bottom {
            set_y(pts, i, clip.bottom)
          }
        }
    }
  }
}

///|
fn chop_mono_quad_at(c0 : Float, c1 : Float, c2 : Float, target : Float) -> Float? {
  let a = c0 - c1 - c1 + c2
  let b : Float = 2.0 * (c1 - c0)
  let c = c0 - target
  let roots = new_t_values()
  if find_unit_quad_roots(a, b, c, roots) != 0 {
    Some(roots[0])
  } else {
    None
  }
}

///|
fn too_big_for_reliable_float_math(r : Rect) -> Bool {
  let limit : Float = 4194304.0
  r.left < -limit || r.top < -limit || r.right > limit || r.bottom > limit
}

///|
fn chop_cubic_in_y(clip : Rect, pts : Array[Point]) -> Unit {
  if pts[0].y < clip.top {
    let tmp = Array::make(7, Point::zero())
    chop_mono_cubic_at_y(pts, clip.top, tmp)
    if tmp[3].y < clip.top && tmp[4].y < clip.top && tmp[5].y < clip.top {
      let tmp2 = [tmp[3], tmp[4], tmp[5], tmp[6]]
      chop_mono_cubic_at_y(tmp2, clip.top, tmp)
    }
    set_y(tmp, 3, clip.top)
    set_y(tmp, 4, fmax(tmp[4].y, clip.top))
    pts[0] = tmp[3]
    pts[1] = tmp[4]
    pts[2] = tmp[5]
  }
  if pts[3].y > clip.bottom {
    let tmp = Array::make(7, Point::zero())
    chop_mono_cubic_at_y(pts, clip.bottom, tmp)
    set_y(tmp, 3, clip.bottom)
    set_y(tmp, 2, fmin(tmp[2].y, clip.bottom))
    pts[1] = tmp[1]
    pts[2] = tmp[2]
    pts[3] = tmp[3]
  }
}

///|
fn chop_mono_cubic_at_x(src : Array[Point], x : Float, dst : Array[Point]) -> Unit {
  if cubic_dchop_at_intercept(src, x, true, dst) {
    return
  }
  let t = mono_cubic_closest_t(src[0].x, src[1].x, src[2].x, src[3].x, x)
  chop_cubic_at2(src, 0, t, dst, 0)
}

///|
fn chop_mono_cubic_at_y(src : Array[Point], y : Float, dst : Array[Point]) -> Unit {
  if cubic_dchop_at_intercept(src, y, false, dst) {
    return
  }
  let t = mono_cubic_closest_t(src[0].y, src[1].y, src[2].y, src[3].y, y)
  chop_cubic_at2(src, 0, t, dst, 0)
}

///|
fn mono_cubic_closest_t(s0 : Float, s1 : Float, s2 : Float, s3 : Float, x : Float) -> Float {
  let mut t : Float = 0.5
  let mut last_t : Float = 0.0
  let mut best_t = t
  let mut step : Float = 0.25
  let d = s0
  let a = s3 + 3.0 * (s1 - s2) - d
  let b : Float = 3.0 * (s2 - s1 - s1 + d)
  let c : Float = 3.0 * (s1 - d)
  let x = x - d
  let mut closest = scalar_max
  while true {
    let loc = ((a * t + b) * t + c) * t
    let dist = (loc - x).abs()
    if closest > dist {
      closest = dist
      best_t = t
    }
    last_t = t
    t = t + (if loc < x { step } else { -step })
    step = step * 0.5
    if !(closest > 0.25 && last_t != t) {
      break
    }
  }
  best_t
}

// ── the edge builder ──────────────────────────────────────────────────

///|
/// A clip rect in the supersampled space (ShiftedIntRect): the screen rect it came from, shifted.
priv struct ShiftedIntRect {
  shifted : ScreenIntRect
  shift : Int
}

///|
fn ShiftedIntRect::new(rect : ScreenIntRect, shift : Int) -> ShiftedIntRect? {
  match ScreenIntRect::from_xywh(rect.x << shift, rect.y << shift, rect.width << shift, rect.height << shift) {
    Some(shifted) => Some({ shifted, shift })
    None => None
  }
}

///|
fn ShiftedIntRect::recover(self : ShiftedIntRect) -> ScreenIntRect {
  ScreenIntRect::from_xywh(
    self.shifted.x >> self.shift,
    self.shifted.y >> self.shift,
    self.shifted.width >> self.shift,
    self.shifted.height >> self.shift,
  ).unwrap()
}

///|
/// The edges of `path` (clipped to `clip` where there is one) in the space `clip_shift` supersamples; None when they
/// are not finite or fewer than 2 (BasicEdgeBuilder::build_edges).
fn build_edges(path : Path, clip : ShiftedIntRect?, clip_shift : Int) -> Array[Edge]? {
  let edges : Array[Edge] = []
  let push_line = fn(p0 : Point, p1 : Point) {
    match line_edge(p0, p1, clip_shift) {
      Some(edge) => {
        let combine = if edge.is_vertical() && !edges.is_empty() {
          let last = edges[edges.length() - 1]
          if last.kind == ELine {
            combine_vertical(edge, last)
          } else {
            0
          }
        } else {
          0
        }
        match combine {
          2 => ignore(edges.pop())
          1 => ()
          _ => edges.push(edge)
        }
      }
      None => ()
    }
  }
  let push_quad = fn(p : Array[Point]) {
    match quadratic_edge(p, clip_shift) {
      Some(e) => edges.push(e)
      None => ()
    }
  }
  let push_cubic = fn(p : Array[Point]) {
    match cubic_edge(p, clip_shift) {
      Some(e) => edges.push(e)
      None => ()
    }
  }
  match clip {
    Some(clip) => {
      let clip = clip.recover().to_rect()
      let ok = clipped_edges(path, clip, false, fn(es) {
        for e in es {
          match e {
            ELineTo(p0, p1) => {
              if !p0.is_finite() || !p1.is_finite() {
                return false
              }
              push_line(p0, p1)
            }
            EQuadTo(p0, p1, p2) => {
              if !p0.is_finite() || !p1.is_finite() || !p2.is_finite() {
                return false
              }
              push_quad([p0, p1, p2])
            }
            ECubicTo(p0, p1, p2, p3) => {
              if !p0.is_finite() || !p1.is_finite() || !p2.is_finite() || !p3.is_finite() {
                return false
              }
              push_cubic([p0, p1, p2, p3])
            }
          }
        }
        true
      })
      if !ok {
        return None
      }
    }
    None => {
      let iter = edge_iter(path)
      while iter.next() is Some(e) {
        match e {
          ELineTo(p0, p1) => push_line(p0, p1)
          EQuadTo(p0, p1, p2) => {
            let mono_x = Array::make(5, Point::zero())
            let n = chop_quad_at_y_extrema([p0, p1, p2], mono_x)
            for i in 0..=n {
              push_quad([mono_x[i * 2], mono_x[i * 2 + 1], mono_x[i * 2 + 2]])
            }
          }
          ECubicTo(p0, p1, p2, p3) => {
            let mono_y = Array::make(10, Point::zero())
            let n = chop_cubic_at_y_extrema([p0, p1, p2, p3], mono_y)
            for i in 0..=n {
              push_cubic([mono_y[i * 3], mono_y[i * 3 + 1], mono_y[i * 3 + 2], mono_y[i * 3 + 3]])
            }
          }
        }
      }
    }
  }
  if edges.length() < 2 {
    return None
  }
  Some(edges)
}

///|
/// Combines the vertical `edge` into `last`: 0 not, 1 partly (`last` changed), 2 they cancel (Combine).
fn combine_vertical(edge : Edge, last : Edge) -> Int {
  if last.dx != 0 || edge.x != last.x {
    return 0
  }
  if edge.winding == last.winding {
    return if edge.last_y + 1 == last.first_y {
      last.first_y = edge.first_y
      1
    } else if edge.first_y == last.last_y + 1 {
      last.last_y = edge.last_y
      1
    } else {
      0
    }
  }
  if edge.first_y == last.first_y {
    return if edge.last_y == last.last_y {
      2
    } else if edge.last_y < last.last_y {
      last.first_y = edge.last_y + 1
      1
    } else {
      last.first_y = last.last_y + 1
      last.last_y = edge.last_y
      last.winding = edge.winding
      1
    }
  }
  if edge.last_y == last.last_y {
    if edge.first_y > last.first_y {
      last.last_y = edge.first_y - 1
    } else {
      last.last_y = last.first_y - 1
      last.first_y = edge.first_y
      last.winding = edge.winding
    }
    return 1
  }
  0
}
