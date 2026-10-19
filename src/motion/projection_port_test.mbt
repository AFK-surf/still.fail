// Motion's own unit tests of its layout projection geometry, ported with their inputs and expected numbers
// (motion-dom src/projection/geometry/__tests__: delta-calc, delta-apply, conversion, copy, operations, at
// github.com/motiondivision/motion ce1d082). Ported from Motion (motion.dev), MIT licence: Copyright (c) 2024 Motion
// B.V. (the notice in full: motion_port_test.mbt). transformBox's percentages are Percent offsets here.

///|
fn ax(min : Double, max : Double) -> @motion.Axis {
  @motion.Axis::{ min, max }
}

///|
fn bx(x : @motion.Axis, y : @motion.Axis) -> @motion.Box {
  @motion.Box::{ x, y }
}

///|
test "isNear: whether the value is within maxDistance of the target" {
  assert_true(@motion.is_near(10.1, 10.0, 0.1))
  assert_true(@motion.is_near(9.9, 10.0, 0.1))
  assert_true(!@motion.is_near(10.2, 10.0, 0.1))
  assert_true(!@motion.is_near(9.8, 10.0, 0.1))
}

///|
test "calcAxisDelta: a delta that, applied to source, makes it the same as target" {
  let delta = @motion.create_delta()
  let source = ax(100.0, 200.0)
  let target = ax(300.0, 500.0)
  @motion.calc_axis_delta(delta.x, source, target)
  assert_eq(delta.x, @motion.AxisDelta::{ translate: 250.0, scale: 2.0, origin: 0.5, origin_point: 150.0 })
  @motion.apply_axis_delta(source, delta.x.translate, delta.x.scale, delta.x.origin_point)
  assert_eq(source, target)
}

///|
test "calcAxisDelta: accepts a custom origin" {
  let delta = @motion.create_delta()
  let source = ax(100.0, 200.0)
  let target = ax(300.0, 500.0)
  @motion.calc_axis_delta(delta.x, source, target, origin=0.0)
  assert_eq(delta.x, @motion.AxisDelta::{ translate: 200.0, scale: 2.0, origin: 0.0, origin_point: 100.0 })
  @motion.apply_axis_delta(source, delta.x.translate, delta.x.scale, delta.x.origin_point)
  assert_eq(source, target)
}

///|
test "calcRelativeBox: resolves a relative box from parent.min (anchor 0 by default)" {
  let target = @motion.create_box()
  @motion.calc_relative_box(
    target,
    bx(ax(100.0, 150.0), ax(-100.0, 0.0)),
    bx(ax(500.0, 800.0), ax(100.0, 200.0)),
  )
  assert_eq(target, bx(ax(600.0, 650.0), ax(0.0, 100.0)))
}

///|
test "calcRelativeBox: resolves a relative box with anchor {x: 0.5, y: 0.5}" {
  // parent x 500 … 800 (centre 650), y 100 … 200 (centre 150); relative x 0 … 50, y 0 … 100
  let target = @motion.create_box()
  @motion.calc_relative_box(
    target,
    bx(ax(0.0, 50.0), ax(0.0, 100.0)),
    bx(ax(500.0, 800.0), ax(100.0, 200.0)),
    anchor=(0.5, 0.5),
  )
  assert_eq(target, bx(ax(650.0, 700.0), ax(150.0, 250.0)))
}

///|
test "calcRelativePosition: from parent.min (anchor 0 by default)" {
  let target = @motion.create_box()
  @motion.calc_relative_position(
    target,
    bx(ax(600.0, 650.0), ax(200.0, 300.0)),
    bx(ax(500.0, 800.0), ax(100.0, 200.0)),
  )
  assert_eq(target, bx(ax(100.0, 150.0), ax(100.0, 200.0)))
  @motion.calc_relative_position(
    target,
    bx(ax(600.0, 650.0), ax(200.0, 300.0)),
    bx(ax(600.0, 650.0), ax(200.0, 300.0)),
  )
  assert_eq(target, bx(ax(0.0, 50.0), ax(0.0, 100.0)))
}

///|
test "calcRelativePosition: with anchor 0.5, a centred child's offset is about 0" {
  // parent x 100 … 400 (centre 250); child x 200 … 300, centred: 200 − 250 = −50
  let target = @motion.create_box()
  @motion.calc_relative_position(
    target,
    bx(ax(200.0, 300.0), ax(150.0, 250.0)),
    bx(ax(100.0, 400.0), ax(100.0, 300.0)),
    anchor=(0.5, 0.5),
  )
  assert_eq(target, bx(ax(-50.0, 50.0), ax(-50.0, 50.0)))
}

///|
test "calcRelativePosition then calcRelativeBox gives the box back" {
  let child = bx(ax(200.0, 300.0), ax(150.0, 250.0))
  let parent = bx(ax(100.0, 400.0), ax(100.0, 300.0))
  let relative = @motion.create_box()
  @motion.calc_relative_position(relative, child, parent, anchor=(0.5, 0.5))
  let back = @motion.create_box()
  @motion.calc_relative_box(back, relative, parent, anchor=(0.5, 0.5))
  assert_true((back.x.min - child.x.min).abs() < 0.005)
  assert_true((back.x.max - child.x.max).abs() < 0.005)
  assert_true((back.y.min - child.y.min).abs() < 0.005)
  assert_true((back.y.max - child.y.max).abs() < 0.005)
}

///|
test "calcRelativePosition then calcRelativeBox with anchor 0 (as before anchors)" {
  let child = bx(ax(600.0, 650.0), ax(200.0, 300.0))
  let parent = bx(ax(500.0, 800.0), ax(100.0, 200.0))
  let relative = @motion.create_box()
  @motion.calc_relative_position(relative, child, parent)
  let back = @motion.create_box()
  @motion.calc_relative_box(back, relative, parent)
  assert_eq(back, child)
}

///|
test "calcRelativeAxisPosition: anchor 0 is the default (parent.min)" {
  let t1 = ax(0.0, 0.0)
  let t2 = ax(0.0, 0.0)
  @motion.calc_relative_axis_position(t1, ax(200.0, 300.0), ax(100.0, 500.0), anchor=0.0)
  @motion.calc_relative_axis_position(t2, ax(200.0, 300.0), ax(100.0, 500.0))
  assert_eq(t1, t2)
}

///|
test "calcRelativeAxisPosition: anchor 1 measures from parent.max" {
  let t = ax(0.0, 0.0)
  @motion.calc_relative_axis_position(t, ax(200.0, 300.0), ax(100.0, 500.0), anchor=1.0)
  assert_eq(t, ax(-300.0, -200.0))
}

///|
test "calcRelativeAxis: anchor 0 is the default (parent.min)" {
  let t1 = ax(0.0, 0.0)
  let t2 = ax(0.0, 0.0)
  @motion.calc_relative_axis(t1, ax(100.0, 150.0), ax(500.0, 800.0), anchor=0.0)
  @motion.calc_relative_axis(t2, ax(100.0, 150.0), ax(500.0, 800.0))
  assert_eq(t1, t2)
}

///|
test "calcRelativeAxis: anchor 0.5 resolves from the parent's centre" {
  let t = ax(0.0, 0.0)
  @motion.calc_relative_axis(t, ax(-25.0, 25.0), ax(500.0, 800.0), anchor=0.5)
  assert_eq(t, ax(625.0, 675.0))
}

///|
test "scalePoint scales a point by a factor about an originPoint" {
  assert_eq(@motion.scale_point(100.0, 2.0, 50.0), 150.0)
  assert_eq(@motion.scale_point(100.0, 0.5, 50.0), 75.0)
  assert_eq(@motion.scale_point(100.0, 2.0, 150.0), 50.0)
  assert_eq(@motion.scale_point(100.0, 0.5, 150.0), 125.0)
}

///|
test "applyPointDelta applies a delta to a point" {
  assert_eq(@motion.apply_point_delta(100.0, 100.0, 2.0, 50.0), 250.0)
  assert_eq(@motion.apply_point_delta(100.0, 100.0, 2.0, 150.0), 150.0)
}

///|
test "applyPointDelta with an additional boxScale" {
  assert_eq(@motion.apply_point_delta(100.0, 100.0, 2.0, 50.0, box_scale=2.0), 350.0)
  assert_eq(@motion.apply_point_delta(100.0, 100.0, 2.0, 150.0, box_scale=2.0), 50.0)
}

///|
test "applyAxisDelta applies a delta to an axis" {
  let a = ax(100.0, 200.0)
  @motion.apply_axis_delta(a, 100.0, 2.0, 150.0)
  assert_eq(a, ax(150.0, 350.0))
}

///|
test "applyAxisDelta with an additional boxScale" {
  let a = ax(100.0, 200.0)
  @motion.apply_axis_delta(a, 100.0, 2.0, 150.0, box_scale=2.0)
  assert_eq(a, ax(50.0, 450.0))
}

///|
test "transformBox: a percentage x is of the axis's width" {
  let b = bx(ax(100.0, 300.0), ax(0.0, 100.0))
  // 100% of the width (200) moves x by 200
  @motion.transform_box(b, x=Percent(100.0))
  assert_eq(b.x, ax(300.0, 500.0))
  assert_eq(b.y, ax(0.0, 100.0))
}

///|
test "transformBox: a percentage y is of the axis's height" {
  let b = bx(ax(0.0, 100.0), ax(100.0, 300.0))
  // 50% of the height (200) is 100
  @motion.transform_box(b, y=Percent(50.0))
  assert_eq(b.y, ax(200.0, 400.0))
  assert_eq(b.x, ax(0.0, 100.0))
}

///|
test "transformBox: 0% moves nothing" {
  let b = bx(ax(100.0, 300.0), ax(0.0, 100.0))
  @motion.transform_box(b, x=Percent(0.0))
  assert_eq(b.x, ax(100.0, 300.0))
}

///|
test "convertBoundingBoxToBox converts a bounding box into a box" {
  assert_eq(@motion.box_of_edges(top=1.0, right=4.0, bottom=3.0, left=2.0), bx(ax(2.0, 4.0), ax(1.0, 3.0)))
}

///|
test "copyBoxInto copies one box into an existing one" {
  let a = @motion.create_box()
  let b = bx(ax(1.0, 2.0), ax(3.0, 4.0))
  @motion.copy_box_into(a, b)
  assert_eq(a, b)
  assert_true(!physical_equal(a, b))
}

///|
test "translateAxis applies a translation to an axis" {
  let a = @motion.create_axis()
  a.max = 100.0
  @motion.translate_axis(a, 100.0)
  assert_eq(a, ax(100.0, 200.0))
  @motion.translate_axis(a, -100.0)
  assert_eq(a, ax(0.0, 100.0))
}
