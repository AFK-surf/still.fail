// The fonts selected in 外观, and the 字体 page.

///|
/// The faces chosen at a glance (FontRow: their names, " · " between), or the app's own.
fn fonts_said(prefs : Json?) -> String {
  let faces = field(prefs, "faces")
  let names = []
  for place in @settings.font_places {
    if text(field(prefs, "fonts"), place) != "" {
      names.push(text(field(faces, place), "name"))
    }
  }
  if names.is_empty() {
    @sf.t("web-pages.appearance.fonts.default")
  } else {
    names.join(" · ")
  }
}

///|
/// 字体's page, one for every frame (mobile/Fonts.tsx FontScreen, opened from 外观's row narrow): what it is for under
/// its title, the setting (font_setting.mbt).
pub fn fonts_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  @sf.page(c, on_back=core.pop, frame~, "fonts", @sf.t("web-pages.appearance.fonts.title"), fonts_blocks(c, core), lead=@sf.t(
    "web-pages.appearance.fonts.description",
  ))
}
