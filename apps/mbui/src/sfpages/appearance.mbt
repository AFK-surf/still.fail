// 外观, one page for every frame (web/src/pages/Appearance.tsx and mobile/Settings.tsx AppearanceScreen): how this
// device shows still.fail, its settings (@sf.settings: wide, rows of one list card, each choice at its row's end;
// narrow, a block each): 主题, 字体 (the faces chosen, opening their page: FontRow; font_setting.mbt), 动画, 震动, 语言; with
// keyboard and mouse the files dragged into a chat too, and laid out wide the rail changed in place (as the web's,
// `wideOnly`). Each choice is the core's prefs (`prefs.set`), shown at once. When a done chat is offered to archive is
// 归档's (archiving.mbt), as the web's.

///|
/// 外观 (AppearancePage, AppearanceScreen) made once as nodes in node `v`, laid out by the `width` its frame gives it
/// (narrow where none is given): its settings (settings_node: wide, one list card; narrow, a section each), each choice
/// the core's prefs as they are now, set as it is chosen. Another theme chosen spreads from where it was chosen (mbui
/// reveal.mbt). What it says of itself told `said`.
pub fn appearance_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let look = fn() {
    match width {
      Some(w) => @sf.look_for(w())
      None => Narrow
    }
  }
  let prefs = fn() { (core.topic)("prefs", Map::new()).value }
  // (the rail changed where it is: laid out wide, where the rail is beside the page, the web's wideOnly; the window's
  // zoom where the host has one; files dragged in where they can be: @ui.takes_drops)
  let keys = fn() {
    let keys = ["theme", "fonts", "motion", "haptics", "language"]
    if @ui.window_zoom_supported() {
      keys.push("zoom")
    }
    if @ui.takes_drops() {
      keys.push("drop")
    }
    if look() is Wide {
      keys.push("rail")
    }
    keys
  }
  // a choice of a few (Segmented, Seg): its kept value or the one just chosen while the core takes it
  let choice = fn(
    p : @view.View,
    key : String,
    options : Array[(String, String)],
    now : () -> String,
  ) {
    let at = fn() { options.search_by(fn(o) { o.0 == now() }).unwrap_or(0) }
    @sf.page_choice_node(p, fn() { options.map(fn(o) { @sf.t(o.1) }) }, at, fn(i) {
      if i == @signals.untracked(at) || i < 0 || i >= options.length() {
        return
      }
      // (another theme chosen: it spreads from where it was chosen)
      if key == "appearance" {
        let c = @ui.current()
        let (x, y, _) = c.pointer()
        c.reveal_from(x, y, dark=fn() { @sf.theme().dark })
      }
      @settings.set_pref(core, key, options[i].0)
    })
  }
  @sf.page_node(v, fn() { @sf.t("web-pages.appearance.title") }, on_back~, frame~, said?, width?, fn() {
    @sf.settings_blocks(look(), keys())
  }, fn(b, block) {
    @sf.settings_node(b, block, keys, fn(r, key) {
      match key {
        "theme" =>
          @sf.setting_node(
            r,
            fn() { @sf.t("web-pages.appearance.theme.title") },
            note=fn() { @sf.t("web-pages.appearance.theme.description") },
            fn(p) {
              choice(
                p,
                "appearance",
                [("system", "web-main.appearance.system"), ("light", "web-main.appearance.light"), ("dark", "web-main.appearance.dark")],
                fn() { @settings.appearance(prefs()) },
              )
            },
          )
        // (the faces chosen, opening their page: a chat as they set it and their list are a page's own)
        "fonts" =>
          @sf.setting_link_node(
            r,
            fn() { @sf.t("web-pages.appearance.fonts.title") },
            fn() { fonts_said(prefs()) },
            fn() { (core.push)(Fonts) },
            note=fn() { @sf.t("web-pages.appearance.fonts.description") },
          )
        "motion" =>
          @sf.setting_node(
            r,
            fn() { @sf.t("web-pages.appearance.motion.title") },
            note=fn() { @sf.t("web-pages.appearance.motion.description") },
            fn(p) {
              choice(
                p,
                "motion",
                [("", "web-pages.appearance.motion.system"), ("reduce", "web-pages.appearance.motion.reduce"), ("full", "web-pages.appearance.motion.full")],
                fn() { @settings.pref(core, "motion") },
              )
            },
          )
        // (haptics, all of them: on unless turned off, @ui.set_haptics, app_frame.mbt)
        "haptics" => {
          let title = fn() { @sf.t("web-pages.appearance.haptics.title") }
          @sf.setting_node(r, title, note=fn() { @sf.t("web-pages.appearance.haptics.description") }, fn(p) {
            @sf.switch_node(
              p,
              fn() { @settings.pref(core, "haptics") != "off" },
              fn(now) { @settings.set_pref(core, "haptics", if now { "" } else { "off" }) },
              title,
              small=true,
            )
          })
        }
        "language" =>
          @sf.setting_node(
            r,
            fn() { @sf.t("common.language") },
            note=fn() { @sf.t("web-pages.appearance.language.description") },
            fn(p) {
              choice(
                p,
                "language",
                [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")],
                fn() { @settings.pref(core, "language") },
              )
            },
          )
        // (the window's zoom, picked beside its key)
        "zoom" =>
          @sf.setting_node(r, fn() { @sf.t("desktop.menu.zoom") }, fn(p) {
            let zoom = fn() { @settings.pref(core, "windowZoom") }
            let key : Ref[@view.View?] = Ref(None)
            key.val = Some(
              @sf.button_node(p, fn() { if zoom() == "" { "100%" } else { zoom() + "%" } }, fn() {
                let choices = @sfbase.window_zoom_levels.map(fn(z) {
                  @sf.choice(z.0, (if z.0 == "" { "100" } else { z.0 }) + "%")
                })
                let (x, y, w, h) = key.val.map(fn(k) { k.placed_window_now() }).unwrap_or((0.0, 0.0, 0.0, 0.0))
                @sf.pick(
                  @sf.t("desktop.menu.zoom"),
                  choices,
                  @signals.untracked(zoom),
                  fn(value) { @settings.set_pref(core, "windowZoom", value) },
                  from=At(x, y, w, h),
                  search=false,
                )
              }),
            )
          })
        // (files dragged into a chat from outside: named by their path (the default), or sent as files)
        "drop" =>
          @sf.setting_node(
            r,
            fn() { @sf.t("web-pages.appearance.drop.title") },
            note=fn() { @sf.t("web-pages.appearance.drop.description") },
            fn(p) {
              choice(
                p,
                "dropAs",
                [("", "web-pages.appearance.drop.path"), ("file", "web-pages.appearance.drop.file")],
                fn() { @settings.pref(core, "dropAs") },
              )
            },
          )
        // (the rail, changed where it is: rail.mbt)
        _ =>
          @sf.setting_node(r, fn() { @sf.t("web-main.rail.title") }, note=fn() { @sf.t("web-main.rail.lead") }, fn(p) {
            @sf.button_node(p, fn() { @sf.t("web-main.rail.customize") }, @sfbase.edit_rail) |> ignore
          })
      }
    })
  })
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
