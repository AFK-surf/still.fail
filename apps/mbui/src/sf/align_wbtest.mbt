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
  assert_true(near(small_panel_inner(r_menu), r_menu - panel_pad))
  assert_true(near(@ui.concentric_out(8.0, 10.0), 18.0))
}

///|
test "align: a pill in a surface's corner leaves no crescent: the surface round it, its half height and the pad" {
  // a small panel's pill in its corner (PanelFoot): as far in as makes the panel's corner its distance and its half
  assert_true(near(around(@ui.capsule_in(r_menu, panel_pill), panel_pill / 2.0), r_menu))
}

