// align.mbt: the web's align.ts with mbui's smooth corners (the web's superellipse(1.5), --corner-scale 1.25).

///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
test "align: a surface's corner is what sits in it and its padding together, drawn as the web draws them" {
  // the web: a menu's corner 20 × 1.25 = 25, its rows' 25 − 6 = 19; here the corner given, drawn a quarter larger
  let menu = surface(panel_pad, small_panel_inner(r_menu))
  assert_true(near(menu.corner(), r_menu))
  assert_true(near(small_panel_inner(r_menu) * smooth_scale, r_menu * smooth_scale - panel_pad))
  assert_true(near(surface_corner(10.0, 8.0) * smooth_scale, 8.0 * smooth_scale + 10.0))
  assert_eq(inner_or(None, 12.0), 12.0)
  assert_eq(inner_or(Some(menu), 12.0), menu.inner)
}

///|
test "align: a pill in a surface's corner leaves no crescent: the surface round it, its half height and the pad" {
  // the web's pillInner(6, 24, 1.25): (6 + 12) × 1.25 − 6 = 16.5 drawn
  assert_true(near(pill_inner(panel_pad, panel_pill) * smooth_scale, (panel_pad + panel_pill / 2.0) * smooth_scale - panel_pad))
  // a small panel's pill in its corner (PanelFoot): as far in as makes the panel's corner its distance and its half
  assert_eq(around(capsule_in(r_menu, panel_pill), panel_pill / 2.0), r_menu)
}

///|
test "align: a bleed's padding and margin are one number, its words where they were" {
  let b = bleed_x(10.0).base
  assert_eq(b.px, Some(Exact(10.0)))
  assert_eq(b.mx, Some(Exact(-10.0)))
  let r = edge_row(surface(6.0, 14.0), 6.0, first=true).base
  assert_eq(r.mt, Some(Exact(-6.0)))
  assert_eq(r.radius, Some(Exact(concentric_out(14.0, 6.0))))
}
