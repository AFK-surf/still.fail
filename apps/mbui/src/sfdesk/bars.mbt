// 下方栏, one page for every frame (web/src/mobile/BarSettings.tsx BarSettingsScreen; the web's desktop has no bottom
// bar, so no page of it): this device's bottom bars, each a card of its places, a bar made the one in view, deleted, or
// a new one made (@settings.bars_blocks: what the core keeps, `bars`). The bar is laid out Small's; a wider frame shows
// the same page in its box, to set what a phone-sized window shows.

///|
/// The page (BarSettingsScreen), in the frame it is given.
fn bars_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  look_page(c, core, frame, look, "bars", @sf.t("android-misc.bar.title"), @settings.bars_blocks(c, core), small=@sf.t(
    "android-misc.bar.small",
  ))
}
