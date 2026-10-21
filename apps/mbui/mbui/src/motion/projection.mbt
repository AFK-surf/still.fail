// Motion's layout projection geometry (motion-dom src/projection/geometry): axes and boxes, the delta (translate,
// scale, origin) that takes one box onto another, applying deltas and transforms, boxes relative to a parent. What
// `layout` does (FLIP: drawn from where it was laid out, going to where it is) is this arithmetic on a node's laid-out
// rect. Ported from Motion (motion.dev): Copyright (c) 2024 Motion B.V., MIT licence.

///|
/// An extent along one axis (Motion's Axis).
pub(all) struct Axis {
  mut min : Double
  mut max : Double
} derive(Eq, Show, Debug)

///|
/// A box: an extent along x and along y (Motion's Box).
pub(all) struct Box {
  x : Axis
  y : Axis
} derive(Eq, Show, Debug)

///|
/// What takes an axis onto another (Motion's AxisDelta): scaled about `origin_point` (at `origin` of it), then moved.
pub(all) struct AxisDelta {
  mut translate : Double
  mut scale : Double
  mut origin : Double
  mut origin_point : Double
} derive(Eq, Show, Debug)

///|
pub(all) struct Delta {
  x : AxisDelta
  y : AxisDelta
} derive(Eq, Show, Debug)

///|
pub fn create_axis() -> Axis {
  { min: 0.0, max: 0.0 }
}

///|
pub fn create_box() -> Box {
  { x: create_axis(), y: create_axis() }
}

///|
pub fn create_axis_delta() -> AxisDelta {
  { translate: 0.0, scale: 1.0, origin: 0.0, origin_point: 0.0 }
}

///|
pub fn create_delta() -> Delta {
  { x: create_axis_delta(), y: create_axis_delta() }
}

///|
/// A box from a bounding box's edges (Motion's convertBoundingBoxToBox).
pub fn box_of_edges(top~ : Double, right~ : Double, bottom~ : Double, left~ : Double) -> Box {
  { x: { min: left, max: right }, y: { min: top, max: bottom } }
}

///|
/// `from` copied into `into` (Motion's copyBoxInto).
pub fn copy_box_into(into : Box, from : Box) -> Unit {
  into.x.min = from.x.min
  into.x.max = from.x.max
  into.y.min = from.y.min
  into.y.max = from.y.max
}

///|
pub fn calc_length(axis : Axis) -> Double {
  axis.max - axis.min
}

///|
/// Whether `value` is within `max_distance` of `target`.
pub fn is_near(value : Double, target : Double, max_distance : Double) -> Bool {
  (value - target).abs() <= max_distance
}

///|
/// The delta that takes `source` onto `target`, about `origin` of it (Motion's calcAxisDelta): a scale within .0001
/// of 1 is 1, a translation within .01 of 0 is 0.
pub fn calc_axis_delta(delta : AxisDelta, source : Axis, target : Axis, origin? : Double = 0.5) -> Unit {
  delta.origin = origin
  delta.origin_point = mix(source.min, source.max, origin)
  delta.scale = calc_length(target) / calc_length(source)
  delta.translate = mix(target.min, target.max, origin) - delta.origin_point
  if (delta.scale >= 0.9999 && delta.scale <= 1.0001) || delta.scale.is_nan() {
    delta.scale = 1.0
  }
  if (delta.translate >= -0.01 && delta.translate <= 0.01) || delta.translate.is_nan() {
    delta.translate = 0.0
  }
}

///|
/// Both axes' (Motion's calcBoxDelta).
pub fn calc_box_delta(
  delta : Delta,
  source : Box,
  target : Box,
  origin_x? : Double = 0.5,
  origin_y? : Double = 0.5,
) -> Unit {
  calc_axis_delta(delta.x, source.x, target.x, origin=origin_x)
  calc_axis_delta(delta.y, source.y, target.y, origin=origin_y)
}

///|
/// `relative` placed in `parent` from its `anchor` (0 its min, 1 its max) (Motion's calcRelativeAxis).
pub fn calc_relative_axis(target : Axis, relative : Axis, parent : Axis, anchor? : Double = 0.0) -> Unit {
  let point = if anchor != 0.0 { mix(parent.min, parent.max, anchor) } else { parent.min }
  target.min = point + relative.min
  target.max = target.min + calc_length(relative)
}

///|
pub fn calc_relative_box(target : Box, relative : Box, parent : Box, anchor? : (Double, Double) = (0.0, 0.0)) -> Unit {
  calc_relative_axis(target.x, relative.x, parent.x, anchor=anchor.0)
  calc_relative_axis(target.y, relative.y, parent.y, anchor=anchor.1)
}

///|
/// Where `layout` is in `parent`, from its `anchor` (Motion's calcRelativeAxisPosition).
pub fn calc_relative_axis_position(target : Axis, layout : Axis, parent : Axis, anchor? : Double = 0.0) -> Unit {
  let point = if anchor != 0.0 { mix(parent.min, parent.max, anchor) } else { parent.min }
  target.min = layout.min - point
  target.max = target.min + calc_length(layout)
}

///|
pub fn calc_relative_position(
  target : Box,
  layout : Box,
  parent : Box,
  anchor? : (Double, Double) = (0.0, 0.0),
) -> Unit {
  calc_relative_axis_position(target.x, layout.x, parent.x, anchor=anchor.0)
  calc_relative_axis_position(target.y, layout.y, parent.y, anchor=anchor.1)
}

///|
/// `point` scaled by `scale` about `origin_point`.
pub fn scale_point(point : Double, scale : Double, origin_point : Double) -> Double {
  origin_point + scale * (point - origin_point)
}

///|
/// A delta applied to a point (scaled first by `box_scale` when there is one) (Motion's applyPointDelta).
pub fn apply_point_delta(
  point : Double,
  translate : Double,
  scale : Double,
  origin_point : Double,
  box_scale? : Double,
) -> Double {
  let p = match box_scale {
    Some(b) => scale_point(point, b, origin_point)
    None => point
  }
  scale_point(p, scale, origin_point) + translate
}

///|
pub fn apply_axis_delta(
  axis : Axis,
  translate : Double,
  scale : Double,
  origin_point : Double,
  box_scale? : Double,
) -> Unit {
  axis.min = apply_point_delta(axis.min, translate, scale, origin_point, box_scale?=box_scale)
  axis.max = apply_point_delta(axis.max, translate, scale, origin_point, box_scale?=box_scale)
}

///|
pub fn apply_box_delta(box : Box, delta : Delta) -> Unit {
  apply_axis_delta(box.x, delta.x.translate, delta.x.scale, delta.x.origin_point)
  apply_axis_delta(box.y, delta.y.translate, delta.y.scale, delta.y.origin_point)
}

///|
pub fn translate_axis(axis : Axis, distance : Double) -> Unit {
  axis.min = axis.min + distance
  axis.max = axis.max + distance
}

///|
/// A transform's move along an axis: so many pixels, or a share (%) of the box's extent.
pub(all) enum Offset {
  Pixels(Double)
  Percent(Double)
} derive(Eq, Show)

///|
/// An axis moved and scaled about `origin` of it (Motion's transformAxis).
pub fn transform_axis(
  axis : Axis,
  translate? : Double = 0.0,
  scale? : Double = 1.0,
  box_scale? : Double,
  origin? : Double = 0.5,
) -> Unit {
  let origin_point = mix(axis.min, axis.max, origin)
  apply_axis_delta(axis, translate, scale, origin_point, box_scale?=box_scale)
}

///|
/// A box moved by `x`, `y` and scaled (Motion's transformBox), a share of an extent taken from `source` (by default
/// the box).
pub fn transform_box(
  box : Box,
  x? : Offset,
  y? : Offset,
  scale_x? : Double = 1.0,
  scale_y? : Double = 1.0,
  scale? : Double,
  origin_x? : Double = 0.5,
  origin_y? : Double = 0.5,
  source? : Box,
) -> Unit {
  let from = source.unwrap_or(box)
  let resolve = fn(o : Offset?, axis : Axis) {
    match o {
      Some(Pixels(p)) => p
      Some(Percent(p)) => p / 100.0 * (axis.max - axis.min)
      None => 0.0
    }
  }
  let tx = resolve(x, from.x)
  let ty = resolve(y, from.y)
  transform_axis(box.x, translate=tx, scale=scale_x, box_scale?=scale, origin=origin_x)
  transform_axis(box.y, translate=ty, scale=scale_y, box_scale?=scale, origin=origin_y)
}
