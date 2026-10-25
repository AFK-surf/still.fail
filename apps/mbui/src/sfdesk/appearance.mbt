// 外观, one page for every frame (web/src/pages/Appearance.tsx and mobile/Settings.tsx AppearanceScreen): how this
// device shows still.fail, a section each: 主题, 字体, 动画, 语言; with keyboard and mouse the files dragged into a chat too, and
// laid out wide the rail changed in place (as the web's, `wideOnly`). Each choice is the core's prefs (`prefs.set`),
// shown at once. The faces are a row that opens 字体's page (FontRow; font_setting.mbt), on every screen. When a
// done chat is offered to archive is 归档's (archiving.mbt), as the web's.

///|
/// The page (AppearancePage, AppearanceScreen), in the frame it is given.
fn appearance_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let prefs = (core.topic)("prefs", Map::new()).value
  // a choice of a few (Segmented, Seg), its kept value or the one just chosen while the core takes it
  let choice = fn(key : String, options : Array[(String, String)], now : String) {
    let at = options.search_by(fn(o) { o.0 == now }).unwrap_or(0)
    let picked = @sf.page_choice(c, "appearance/" + key, options.map(fn(o) { @sf.t(o.1) }), at)
    if picked != at {
      c.after_build("appearance/" + key, fn() { @settings.set_pref(core, key, options[picked].0) })
    }
  }
  // a section: its title over it; what it is for under its title (wide: the web's Section), under the choice (narrow:
  // mSegNote, where the phone's says it)
  let section = fn(title : String, note : String, narrow_note : Bool, body : () -> Unit) {
    @sf.section(c, title, heads=true, note=if look == Wide { note } else { "" }, fn() {
      body()
      if look == Narrow && narrow_note && note != "" {
        @sf.page_note(c, note)
      }
    })
  }
  let blocks : Array[() -> Unit] = [
    fn() {
      section(@sf.t("web-pages.appearance.theme.title"), @sf.t("web-pages.appearance.theme.description"), false, fn() {
        choice(
          "appearance",
          [("system", "web-main.appearance.system"), ("light", "web-main.appearance.light"), ("dark", "web-main.appearance.dark")],
          @settings.appearance(prefs),
        )
      })
    },
    // (the faces' row on a card of its own: SettingsHome.kt, mobile FontRow; a chat as they set it and their list are
    // a page's own, on every screen)
    fn() {
      @sf.group(c, fn() {
        if @sf.link_row(c, "appearance/fonts", @sf.t("web-pages.appearance.fonts.title"), value=fonts_said(prefs)) {
          (core.push)(Fonts)
        }
      })
    },
    fn() {
      section(@sf.t("web-pages.appearance.motion.title"), @sf.t("web-pages.appearance.motion.description"), true, fn() {
        choice(
          "motion",
          [("", "web-pages.appearance.motion.system"), ("reduce", "web-pages.appearance.motion.reduce"), ("full", "web-pages.appearance.motion.full")],
          @settings.pref(core, "motion"),
        )
      })
    },
    fn() {
      section(@sf.t("common.language"), @sf.t("web-pages.appearance.language.description"), false, fn() {
        choice("language", [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")], @settings.pref(core, "language"))
      })
    },
  ]
  // files dragged into a chat, keyboard and mouse's: named by their path (the default), or sent as files
  if @sf.native_input() is Mouse {
    blocks.push(fn() {
      section(@sf.t("web-pages.appearance.drop.title"), @sf.t("web-pages.appearance.drop.description"), true, fn() {
        choice("dropAs", [("", "web-pages.appearance.drop.path"), ("file", "web-pages.appearance.drop.file")], @settings.pref(core, "dropAs"))
      })
    })
  }
  // the rail, changed where it is (rail.mbt): laid out wide, where the rail is beside the page (the web's wideOnly)
  if look == Wide {
    blocks.push(fn() {
      section(@sf.t("web-main.rail.title"), @sf.t("web-main.rail.lead"), false, fn() {
        c.box(style=appearance_line, fn() {
          if @sf.button(c, @sf.t("web-main.rail.customize"), key="appearance/rail") {
            wide.editing = true
          }
        })
        |> ignore
      })
    })
  }
  look_page(c, core, frame, "appearance", @sf.t("web-pages.appearance.title"), blocks)
}

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
/// A choice's line: what it holds as wide as itself, at its start.
// kept across runs: a value (no field of it changes)
let appearance_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// 字体's page, one for every frame (mobile/Fonts.tsx FontScreen, opened from 外观's row narrow): what it is for under
/// its title, the setting (font_setting.mbt).
fn fonts_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  look_page(c, core, frame, "fonts", @sf.t("web-pages.appearance.fonts.title"), fonts_blocks(c, core), lead=@sf.t(
    "web-pages.appearance.fonts.description",
  ))
}
