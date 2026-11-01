// tiny-skia's tests/integration/hairline.rs (tiny-skia 5d475477), against its reference images.


///|
fn draw_line(x0 : Float, y0 : Float, x1 : Float, y1 : Float, anti_alias : Bool, width : Float, line_cap : LineCap) -> Pixmap {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let pb = PathBuilder::new()
    pb.move_to(x0, y0)
    pb.line_to(x1, y1)
    let path = pb.finish().unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = anti_alias
    let stroke = Stroke::default()
    stroke.width = width
    stroke.line_cap = line_cap
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), None)
    pixmap
}

///|
test "hairline hline_05" {
    let expected = load_pixmap(img("hairline/hline-05.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 90.0, 10.0, false, 0.5, LineCap::Butt), expected)
}

///|
test "hairline hline_05_aa" {
    let expected = load_pixmap(img("hairline/hline-05-aa.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 90.0, 10.0, true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline hline_05_aa_round" {
    let expected = load_pixmap(img("hairline/hline-05-aa-round.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 90.0, 10.0, true, 0.5, LineCap::Round), expected)
}

///|
test "hairline vline_05" {
    let expected = load_pixmap(img("hairline/vline-05.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 10.0, 90.0, false, 0.5, LineCap::Butt), expected)
}

///|
test "hairline vline_05_aa" {
    let expected = load_pixmap(img("hairline/vline-05-aa.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 10.0, 90.0, true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline vline_05_aa_round" {
    let expected = load_pixmap(img("hairline/vline-05-aa-round.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 10.0, 90.0, true, 0.5, LineCap::Round), expected)
}

///|
test "hairline horish_05_aa" {
    let expected = load_pixmap(img("hairline/horish-05-aa.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 90.0, 70.0, true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline vertish_05_aa" {
    let expected = load_pixmap(img("hairline/vertish-05-aa.png")).unwrap()
    assert_eq(draw_line(10.0, 10.0, 70.0, 90.0, true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline clip_line_05_aa" {
    let expected = load_pixmap(img("hairline/clip-line-05-aa.png")).unwrap()
    assert_eq(draw_line(-10.0, 10.0, 110.0, 70.0, true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline clip_line_00" {
    let expected = load_pixmap(img("hairline/clip-line-00.png")).unwrap()
    assert_eq(draw_line(-10.0, 10.0, 110.0, 70.0, false, 0.0, LineCap::Butt), expected)
}

///|
test "hairline clip_line_00_v2" {
    let pixmap = Pixmap::new(512, 512).unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let stroke = Stroke::default()
    stroke.width = 0.0
    let builder = PathBuilder::default()
    builder.move_to(369.26462, 577.8069)
    builder.line_to(488.0846, 471.04388)
    let path = builder.finish().unwrap()
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), None)
    let expected = load_pixmap(img("hairline/clip-line-00-v2.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "hairline clip_hline_top_aa" {
    let expected = load_pixmap(img("hairline/clip-hline-top-aa.png")).unwrap()
    assert_eq(draw_line(-1.0, 0.0, 101.0, 0.0, true, 1.0, LineCap::Butt), expected)
}

///|
test "hairline clip_hline_bottom_aa" {
    let expected = load_pixmap(img("hairline/clip-hline-bottom-aa.png")).unwrap()
    assert_eq(draw_line(-1.0, 100.0, 101.0, 100.0, true, 1.0, LineCap::Butt), expected)
}

///|
test "hairline clip_vline_left_aa" {
    let expected = load_pixmap(img("hairline/clip-vline-left-aa.png")).unwrap()
    assert_eq(draw_line(0.0, -1.0, 0.0, 101.0, true, 1.0, LineCap::Butt), expected)
}

///|
test "hairline clip_vline_right_aa" {
    let expected = load_pixmap(img("hairline/clip-vline-right-aa.png")).unwrap()
    assert_eq(draw_line(100.0, -1.0, 100.0, 101.0, true, 1.0, LineCap::Butt), expected)
}

///|
fn draw_quad(anti_alias : Bool, width : Float, line_cap : LineCap) -> Pixmap {
    let pixmap = Pixmap::new(200, 100).unwrap()
    let pb = PathBuilder::new()
    pb.move_to(25.0, 80.0)
    pb.quad_to(155.0, 75.0, 175.0, 20.0)
    let path = pb.finish().unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = anti_alias
    let stroke = Stroke::default()
    stroke.width = width
    stroke.line_cap = line_cap
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), None)
    pixmap
}

///|
test "hairline quad_width_05_aa" {
    let expected = load_pixmap(img("hairline/quad-width-05-aa.png")).unwrap()
    assert_eq(draw_quad(true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline quad_width_05_aa_round" {
    let expected = load_pixmap(img("hairline/quad-width-05-aa-round.png")).unwrap()
    assert_eq(draw_quad(true, 0.5, LineCap::Round), expected)
}

///|
test "hairline quad_width_00" {
    let expected = load_pixmap(img("hairline/quad-width-00.png")).unwrap()
    assert_eq(draw_quad(false, 0.0, LineCap::Butt), expected)
}

///|
fn draw_cubic(points : Array[Float], anti_alias : Bool, width : Float, line_cap : LineCap) -> Pixmap {
    let pixmap = Pixmap::new(200, 100).unwrap()
    let pb = PathBuilder::new()
    pb.move_to(points[0], points[1])
    pb.cubic_to(points[2], points[3], points[4], points[5], points[6], points[7])
    let path = pb.finish().unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = anti_alias
    let stroke = Stroke::default()
    stroke.width = width
    stroke.line_cap = line_cap
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), None)
    pixmap
}

///|
test "hairline cubic_width_10_aa" {
    let expected = load_pixmap(img("hairline/cubic-width-10-aa.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], true, 1.0, LineCap::Butt), expected)
}

///|
test "hairline cubic_width_05_aa" {
    let expected = load_pixmap(img("hairline/cubic-width-05-aa.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline cubic_width_00_aa" {
    let expected = load_pixmap(img("hairline/cubic-width-00-aa.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], true, 0.0, LineCap::Butt), expected)
}

///|
test "hairline cubic_width_00" {
    let expected = load_pixmap(img("hairline/cubic-width-00.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], false, 0.0, LineCap::Butt), expected)
}

///|
test "hairline cubic_width_05_aa_round" {
    let expected = load_pixmap(img("hairline/cubic-width-05-aa-round.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], true, 0.5, LineCap::Round), expected)
}

///|
test "hairline cubic_width_00_round" {
    let expected = load_pixmap(img("hairline/cubic-width-00-round.png")).unwrap()
    assert_eq(draw_cubic([25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], false, 0.0, LineCap::Round), expected)
}

///|
test "hairline chop_cubic_01" {
    let expected = load_pixmap(img("hairline/chop-cubic-01.png")).unwrap()
    // This curve will invoke `path_geometry::chop_cubic_at_max_curvature` branch of `hair_cubic`.
    assert_eq(draw_cubic([57.0, 13.0, 17.0, 15.0, 55.0, 97.0, 89.0, 62.0], true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline clip_cubic_05_aa" {
    let expected = load_pixmap(img("hairline/clip-cubic-05-aa.png")).unwrap()
    assert_eq(draw_cubic([-25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], true, 0.5, LineCap::Butt), expected)
}

///|
test "hairline clip_cubic_00" {
    let expected = load_pixmap(img("hairline/clip-cubic-00.png")).unwrap()
    assert_eq(draw_cubic([-25.0, 80.0, 55.0, 25.0, 155.0, 75.0, 175.0, 20.0], false, 0.0, LineCap::Butt), expected)
}

///|
test "hairline clipped_circle_aa" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = true
    let stroke = Stroke::default()
    stroke.width = 0.5
    let path = PathBuilder::from_circle(50.0, 50.0, 55.0).unwrap()
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), None)
    let expected = load_pixmap(img("hairline/clipped-circle-aa.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}
