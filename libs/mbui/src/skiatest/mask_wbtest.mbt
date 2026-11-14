// tiny-skia's tests/integration/mask.rs (tiny-skia 5d475477), against its reference images.


///|
test "mask rect" {
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, false, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let pixmap = Pixmap::new(100, 100).unwrap()
    let rect = Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap()
    pixmap.fill_rect(rect, paint, Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/rect.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask rect_aa" {
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.5, 10.0, 80.0, 80.5).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, true, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let pixmap = Pixmap::new(100, 100).unwrap()
    let rect = Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap()
    pixmap.fill_rect(rect, paint, Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/rect-aa.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask rect_ts" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    let clip_path = clip_path.transform(Transform::from_row(1.0, -0.3, 0.0, 1.0, 0.0, 15.0)).unwrap()
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, false, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let rect = Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap()
    pixmap.fill_rect(rect, paint, Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/rect-ts.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask circle_bottom_right_aa" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let clip_path = PathBuilder::from_circle(100.0, 100.0, 50.0).unwrap()
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, true, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let rect = Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap()
    pixmap.fill_rect(rect, paint, Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/circle-bottom-right-aa.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask stroke" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, false, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let stroke = Stroke::default()
    stroke.width = 10.0
    let path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    pixmap.stroke_path(path, paint, stroke, Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/stroke.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

// Make sure we're clipping only source and not source and destination
///|
test "mask skip_dest" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    pixmap.fill_path(
        PathBuilder::from_rect(Rect::from_xywh(5.0, 5.0, 60.0, 60.0).unwrap()),
        paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    )
    let pixmap2 = Pixmap::new(200, 200).unwrap()
    pixmap2.as_mut().fill_path(
        PathBuilder::from_rect(Rect::from_xywh(35.0, 35.0, 60.0, 60.0).unwrap()),
        paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    )
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(40.0, 40.0, 40.0, 40.0).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, true, Transform::default())
    pixmap.draw_pixmap(0, 0, pixmap2.as_ref(), PixmapPaint::default(),
                                Transform::identity(), Some(mask))
    let expected = load_pixmap(img("mask/skip-dest.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask intersect_aa" {
    let circle1 = PathBuilder::from_circle(75.0, 75.0, 50.0).unwrap()
    let circle2 = PathBuilder::from_circle(125.0, 125.0, 50.0).unwrap()
    let mask = Mask::new(200, 200).unwrap()
    mask.fill_path(circle1, FillRule::Winding, true, Transform::default())
    mask.intersect_path(circle2, FillRule::Winding, true, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_rect(
        Rect::from_xywh(0.0, 0.0, 200.0, 200.0).unwrap(),
        paint,
        Transform::identity(),
        Some(mask),
    )
    let expected = load_pixmap(img("mask/intersect-aa.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask ignore_memset" {
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, false, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 255)
    paint.anti_alias = false
    let pixmap = Pixmap::new(100, 100).unwrap()
    pixmap.fill_rect(
        Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap(),
        paint,
        Transform::identity(),
        Some(mask),
    )
    let expected = load_pixmap(img("mask/ignore-memset.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask ignore_source" {
    let clip_path = PathBuilder::from_rect(Rect::from_xywh(10.0, 10.0, 80.0, 80.0).unwrap())
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, false, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 255); // Must be opaque.
    paint.blend_mode = BlendMode::SourceOver
    paint.anti_alias = false
    let pixmap = Pixmap::new(100, 100).unwrap()
    pixmap.fill(@skia.color_white)
    pixmap.fill_rect(
        Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap(),
        paint,
        Transform::identity(),
        Some(mask),
    )
    let expected = load_pixmap(img("mask/ignore-source.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask apply_mask" {
    let pixmap = Pixmap::new(100, 100).unwrap()
    let clip_path = PathBuilder::from_circle(100.0, 100.0, 50.0).unwrap()
    let mask = Mask::new(100, 100).unwrap()
    mask.fill_path(clip_path, FillRule::Winding, true, Transform::default())
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = false
    let rect = Rect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap()
    pixmap.fill_rect(rect, paint, Transform::identity(), None)
    pixmap.apply_mask(mask)
    let expected = load_pixmap(img("mask/apply-mask.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "mask mask_from_alpha" {
    let path = PathBuilder::from_circle(100.0, 100.0, 50.0).unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = true
    let pixmap = Pixmap::new(100, 100).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::default(), None)
    let mask = Mask::from_pixmap(pixmap.as_ref(), MaskType::Alpha)
    let expected = load_mask(img("mask/mask-from-alpha.png")).unwrap()
    assert_eq(mask, expected)
}

///|
test "mask mask_from_luma" {
    let path = PathBuilder::from_circle(100.0, 100.0, 50.0).unwrap()
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = true
    let pixmap = Pixmap::new(100, 100).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::default(), None)
    let mask = Mask::from_pixmap(pixmap.as_ref(), MaskType::Luminance)
    let expected = load_mask(img("mask/mask-from-luma.png")).unwrap()
    assert_eq(mask, expected)
}
