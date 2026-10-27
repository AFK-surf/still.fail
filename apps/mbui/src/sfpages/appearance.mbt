// 外观, one page for every frame (web/src/pages/Appearance.tsx and mobile/Settings.tsx AppearanceScreen): how this
// device shows still.fail, its settings (@sf.settings: wide, rows of one list card, each choice at its row's end;
// narrow, a block each): 主题, 字体 (the faces chosen, opening their page: FontRow; font_setting.mbt), 动画, 震动, 语言; with
// keyboard and mouse the files dragged into a chat too, and laid out wide the rail changed in place (as the web's,
// `wideOnly`). Each choice is the core's prefs (`prefs.set`), shown at once. When a done chat is offered to archive is
// 归档's (archiving.mbt), as the web's.

///|
/// The page (AppearancePage, AppearanceScreen), in the frame it is given.
pub fn appearance_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let prefs = (core.topic)("prefs", Map::new()).value
  // a choice of a few (Segmented, Seg), its kept value or the one just chosen while the core takes it
  let choice = fn(key : String, options : Array[(String, String)], now : String) {
    let at = options.search_by(fn(o) { o.0 == now }).unwrap_or(0)
    let picked = @sf.page_choice(c, "appearance/" + key, options.map(fn(o) { @sf.t(o.1) }), at)
    if picked != at {
      // another theme picked: it spreads from where it was picked (mbui reveal.mbt)
      if key == "appearance" {
        let (x, y, _) = c.pointer()
        c.tell("appearance/reveal", fn() { c.reveal_from(x, y, dark=fn() { @sf.theme().dark }) })
      }
      c.after_build("appearance/" + key, fn() { @settings.set_pref(core, key, options[picked].0) })
    }
  }
  let settings : Array[() -> Unit] = [
    fn() {
      @sf.setting(c, @sf.t("web-pages.appearance.theme.title"), note=@sf.t("web-pages.appearance.theme.description"), fn() {
        choice(
          "appearance",
          [("system", "web-main.appearance.system"), ("light", "web-main.appearance.light"), ("dark", "web-main.appearance.dark")],
          @settings.appearance(prefs),
        )
      })
    },
    // the faces chosen, opening their page (a chat as they set it and their list are a page's own, on every screen)
    fn() {
      if @sf.setting_link(
          c,
          "appearance/fonts",
          @sf.t("web-pages.appearance.fonts.title"),
          fonts_said(prefs),
          note=@sf.t("web-pages.appearance.fonts.description"),
        ) {
        (core.push)(Fonts)
      }
    },
    fn() {
      @sf.setting(c, @sf.t("web-pages.appearance.motion.title"), note=@sf.t("web-pages.appearance.motion.description"), fn() {
        choice(
          "motion",
          [("", "web-pages.appearance.motion.system"), ("reduce", "web-pages.appearance.motion.reduce"), ("full", "web-pages.appearance.motion.full")],
          @settings.pref(core, "motion"),
        )
      })
    },
    // haptics, all of them (on unless turned off: @ui.set_haptics, app_frame.mbt)
    fn() {
      let title = @sf.t("web-pages.appearance.haptics.title")
      @sf.setting(c, title, note=@sf.t("web-pages.appearance.haptics.description"), fn() {
        let on = @settings.pref(core, "haptics") != "off"
        let now = @sf.switch(c, "appearance/haptics", on, label=title)
        if now != on {
          c.tell("appearance/haptics", fn() { @settings.set_pref(core, "haptics", if now { "" } else { "off" }) })
        }
      })
    },
    fn() {
      @sf.setting(c, @sf.t("common.language"), note=@sf.t("web-pages.appearance.language.description"), fn() {
        choice("language", [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")], @settings.pref(core, "language"))
      })
    },
  ]
  if @ui.window_zoom_supported() {
    settings.push(fn() {
      let zoom = @settings.pref(core, "windowZoom")
      let label = if zoom == "" { "100%" } else { zoom + "%" }
      let id = c.id("appearance/window-zoom")
      @sf.setting(c, @sf.t("desktop.menu.zoom"), fn() {
        if @sf.button(c, label, key="appearance/window-zoom") {
          let choices = @sfbase.window_zoom_levels.map(fn(z) {
            @sf.choice(z.0, (if z.0 == "" { "100" } else { z.0 }) + "%")
          })
          @sf.pick(@sf.t("desktop.menu.zoom"), choices, zoom, fn(value) {
            @settings.set_pref(core, "windowZoom", value)
          }, from=Of(id), search=false)
        }
      })
    })
  }
  // files dragged into a chat from outside (where they can be: @ui.takes_drops): named by their path (the default), or
  // sent as files
  if @ui.takes_drops() {
    settings.push(fn() {
      @sf.setting(c, @sf.t("web-pages.appearance.drop.title"), note=@sf.t("web-pages.appearance.drop.description"), fn() {
        choice("dropAs", [("", "web-pages.appearance.drop.path"), ("file", "web-pages.appearance.drop.file")], @settings.pref(core, "dropAs"))
      })
    })
  }
  // the rail, changed where it is (rail.mbt): laid out wide, where the rail is beside the page (the web's wideOnly)
  if look == Wide {
    settings.push(fn() {
      @sf.setting(c, @sf.t("web-main.rail.title"), note=@sf.t("web-main.rail.lead"), fn() {
        if @sf.button(c, @sf.t("web-main.rail.customize"), key="appearance/rail") {
          @sfbase.edit_rail()
        }
      })
    })
  }
  @sf.page(c, on_back=core.pop, frame~, "appearance", @sf.t("web-pages.appearance.title"), @sf.settings(c, settings))
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
/// 字体's page, one for every frame (mobile/Fonts.tsx FontScreen, opened from 外观's row narrow): what it is for under
/// its title, the setting (font_setting.mbt).
pub fn fonts_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  @sf.page(c, on_back=core.pop, frame~, "fonts", @sf.t("web-pages.appearance.fonts.title"), fonts_blocks(c, core), lead=@sf.t(
    "web-pages.appearance.fonts.description",
  ))
}
