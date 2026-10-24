// The panes side by side told apart by their grounds, on either screen (docs/architecture.md, the look): the sidebar a
// step under the page's ground and what is chosen in it a step under that, in the touch palettes as in the web's.

///|
/// A colour's lightness, roughly (its channels' mean, 0 to 255).
fn light_of(c : Int64) -> Double {
  let r = ((c >> 24) & 0xFF).to_double()
  let g = ((c >> 16) & 0xFF).to_double()
  let b = ((c >> 8) & 0xFF).to_double()
  (r + g + b) / 3.0
}

///|
test "grounds: the sidebar a step under the page in every palette, by about the web's step; the chosen a step under it in the light" {
  let web = light_of(wide_light.bg) - light_of(wide_light.sidebar)
  for p in [("wide light", wide_light), ("wide dark", wide_dark), ("touch light", narrow_light), ("touch dark", narrow_dark)] {
    let (name, pal) = p
    let step = light_of(pal.bg) - light_of(pal.sidebar)
    assert_true(step >= web * 0.5 && step <= web * 1.5, msg="\{name}: the sidebar \{step} under the page, the web's \{web}")
  }
  for p in [("wide light", wide_light), ("touch light", narrow_light)] {
    let (name, pal) = p
    assert_true(light_of(pal.sidebar) - light_of(pal.selected) >= web, msg="\{name}: the chosen not a step under the sidebar")
  }
}
