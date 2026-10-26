// The panes side by side told apart by their grounds, on every screen (docs/architecture.md, the look): the sidebar a
// step under the page's ground and what is chosen in it a step under that, light and dark, by about the web's step.

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
  let web = light_of(web_light.bg) - light_of(web_light.sidebar)
  for p in [("light", light_palette), ("dark", dark_palette)] {
    let (name, pal) = p
    let step = light_of(pal.bg) - light_of(pal.sidebar)
    assert_true(step >= web * 0.5 && step <= web * 1.5, msg="\{name}: the sidebar \{step} under the page, the web's \{web}")
  }
  assert_true(
    light_of(light_palette.sidebar) - light_of(light_palette.selected) >= web,
    msg="the chosen not a step under the sidebar",
  )
}
