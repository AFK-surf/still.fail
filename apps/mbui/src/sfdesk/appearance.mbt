// 外观 on the desktop (ember web/src/pages/Appearance.tsx): what only this device keeps, how the pages look here, a
// section each with what it is for under its title: 主题, 字体 (font_setting.mbt), 动画, 语言, files dragged into a chat,
// and the rail changed in place. Each choice is the core's prefs (`prefs.set`), shown at once.

///|
/// The page (AppearancePage).
fn appearance_page(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
  // a choice of a few, as a segmented switch (each its section's)
  let choice = fn(key : String, options : Array[(String, String)], now : String) {
    let at = match options.search_by(fn(o) { o.0 == now }) {
      Some(i) => i
      None => 0
    }
    // (as wide as its options, as the web's Segmented)
    c.box(style=appearance_line, fn() {
      let picked = @sf.segmented(c, "appearance/" + key, options.map(fn(o) { @sf.t(o.1) }), at)
      if picked != at {
        @settings.set_pref(core, key, options[picked].0)
      }
    })
    |> ignore
  }
  desk_page(c, core, "appearance", @sf.t("web-pages.appearance.title"), [
    fn() {
      @sf.section(c, @sf.t("web-pages.appearance.theme.title"), note=@sf.t("web-pages.appearance.theme.description"), fn() {
        // (its kept value, or the one just chosen while the core takes it)
        choice("appearance", [("system", "web-main.appearance.system"), ("light", "web-main.appearance.light"), ("dark", "web-main.appearance.dark")], @settings.appearance(prefs))
      })
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.appearance.fonts.title"), note=@sf.t("web-pages.appearance.fonts.description"), fn() {
        font_setting(c, core)
      })
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.appearance.motion.title"), note=@sf.t("web-pages.appearance.motion.description"), fn() {
        choice(
          "motion",
          [("", "web-pages.appearance.motion.system"), ("reduce", "web-pages.appearance.motion.reduce"), ("full", "web-pages.appearance.motion.full")],
          @settings.pref(core, "motion"),
        )
      })
    },
    fn() {
      @sf.section(c, @sf.t("common.language"), note=@sf.t("web-pages.appearance.language.description"), fn() {
        choice("language", [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")], @settings.pref(core, "language"))
      })
    },
    fn() {
      // files dragged into a chat: named by their path (the default), or sent as files
      @sf.section(c, @sf.t("web-pages.appearance.drop.title"), note=@sf.t("web-pages.appearance.drop.description"), fn() {
        choice("dropAs", [("", "web-pages.appearance.drop.path"), ("file", "web-pages.appearance.drop.file")], @settings.pref(core, "dropAs"))
      })
    },
    fn() {
      // the rail, changed where it is (rail.mbt)
      @sf.section(c, @sf.t("web-main.rail.title"), note=@sf.t("web-main.rail.lead"), fn() {
        c.box(style=appearance_line, fn() {
          if @sf.button(c, @sf.t("web-main.rail.customize"), key="appearance/rail") {
            wide.editing = true
          }
        })
        |> ignore
      })
    },
  ])
}

///|
/// A choice's line: what it holds as wide as itself, at its start.
// kept across runs: a value (no field of it changes)
let appearance_line : @ui.Style = @ui.css("row w=Full align=ACenter")
