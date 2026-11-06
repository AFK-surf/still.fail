// 外观's controls made once in the window's tree. Their values follow the core's prefs and a choice made here before
// the core says it back, as the settings shared with the other pages do.

///|
/// The device's appearance settings in the frame given by its shell. A narrow page has a block per setting; a wide
/// page has those settings together on one list card, with each control beside its description.
pub fn appearance_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let wide = fn() {
    match width {
      Some(w) => @sf.look_for(w()) is Wide
      None => false
    }
  }
  let keys = fn() {
    let out = ["theme", "fonts", "motion", "haptics", "language"]
    if @ui.window_zoom_supported() {
      out.push("zoom")
    }
    if @ui.takes_drops() {
      out.push("drop")
    }
    if wide() {
      out.push("rail")
    }
    out
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.appearance.title") },
    fn() { if wide() { ["settings"] } else { keys() } },
    fn(b, key) {
      if key == "settings" {
        @sf.group_node(b, fn(g) {
          for item in @signals.untracked(keys) {
            appearance_setting_node(g, core, item)
          }
        })
      } else {
        appearance_setting_node(b, core, key)
      }
    },
    on_back~,
    frame~,
    said?,
    width?,
  )
}

///|
/// One setting, as the common settings parts arrange it for the page's width.
fn appearance_setting_node(v : @view.View, core : Core, key : String) -> Unit {
  match key {
    "theme" =>
      @sf.setting_node(v, fn() { @sf.t("web-pages.appearance.theme.title") }, fn(c) {
        appearance_choice_node(c, core, "appearance", [
          ("system", "web-main.appearance.system"),
          ("light", "web-main.appearance.light"),
          ("dark", "web-main.appearance.dark"),
        ])
      }, note=fn() { @sf.t("web-pages.appearance.theme.description") })
    "fonts" =>
      @sf.setting_link_node(
        v,
        fn() { @sf.t("web-pages.appearance.fonts.title") },
        fn() { fonts_said((core.topic)("prefs", Map::new()).value) },
        fn() { (core.push)(Fonts) },
        note=fn() { @sf.t("web-pages.appearance.fonts.description") },
      )
    "motion" =>
      @sf.setting_node(v, fn() { @sf.t("web-pages.appearance.motion.title") }, fn(c) {
        appearance_choice_node(c, core, "motion", [
          ("", "web-pages.appearance.motion.system"),
          ("reduce", "web-pages.appearance.motion.reduce"),
          ("full", "web-pages.appearance.motion.full"),
        ])
      }, note=fn() { @sf.t("web-pages.appearance.motion.description") })
    "haptics" =>
      @sf.setting_switch_node(
        v,
        fn() { @sf.t("web-pages.appearance.haptics.title") },
        fn() { @settings.pref(core, "haptics") != "off" },
        fn(on) { @settings.set_pref(core, "haptics", if on { "" } else { "off" }) },
        note=fn() { @sf.t("web-pages.appearance.haptics.description") },
      )
    "language" =>
      @sf.setting_node(v, fn() { @sf.t("common.language") }, fn(c) {
        appearance_choice_node(c, core, "language", [
          ("", "common.language.system"),
          ("zh", "common.language.zh"),
          ("en", "common.language.en"),
        ])
      })
    "zoom" =>
      @sf.setting_node(v, fn() { @sf.t("desktop.menu.zoom") }, fn(c) { appearance_zoom_node(c, core) })
    "drop" =>
      @sf.setting_node(v, fn() { @sf.t("web-pages.appearance.drop.title") }, fn(c) {
        appearance_choice_node(c, core, "dropAs", [
          ("", "web-pages.appearance.drop.path"),
          ("file", "web-pages.appearance.drop.file"),
        ])
      }, note=fn() { @sf.t("web-pages.appearance.drop.description") })
    "rail" =>
      @sf.setting_node(v, fn() { @sf.t("web-main.rail.title") }, fn(c) {
        @sf.button_node(c, fn() { @sf.t("web-main.rail.customize") }, fn() { @sfbase.edit_rail() }) |> ignore
      }, note=fn() { @sf.t("web-main.rail.lead") })
    _ => ()
  }
}

///|
/// A choice of a few in one setting. The theme change spreads from the point at which it was asked, as it did in the
/// old page. The other choices are sent through the same optimistic preference path.
fn appearance_choice_node(
  v : @view.View,
  core : Core,
  key : String,
  options : Array[(String, String)],
) -> Unit {
  let labels = fn() { options.map(fn(o) { @sf.t(o.1) }) }
  let at = fn() {
    let value = if key == "appearance" {
      @settings.appearance((core.topic)("prefs", Map::new()).value)
    } else {
      @settings.pref(core, key)
    }
    options.search_by(fn(o) { o.0 == value }).unwrap_or(0)
  }
  let choose = fn(i : Int) {
    if i != @signals.untracked(at) {
      match options.get(i) {
        Some((value, _)) => {
          if key == "appearance" {
            let c = @ui.current()
            let (x, y, _) = c.pointer()
            c.reveal_from(x, y, dark=fn() { @sf.theme().dark })
          }
          @settings.set_pref(core, key, value)
        }
        None => ()
      }
    }
  }
  if @sf.look_node(v) is Wide {
    @sf.seg_node(v, labels, at, choose) |> ignore
  } else {
    @sf.page_choice_node(v, labels, at, choose)
  }
}

///|
/// Window zoom's button and its pick. The presenter follows the button while it moves and chooses the sheet or
/// popover from the screen, keeping the setting's current value in the button.
fn appearance_zoom_node(v : @view.View, core : Core) -> Unit {
  let anchor : Ref[@view.View?] = Ref(None)
  let zoom = fn() { @settings.pref(core, "windowZoom") }
  let button = @sf.button_node(v, fn() {
    let value = zoom()
    if value == "" { "100%" } else { value + "%" }
  }, fn() {
    match anchor.val {
      Some(b) => {
        let choices = @sfbase.window_zoom_levels.map(fn(z) {
          @sf.choice(z.0, (if z.0 == "" { "100" } else { z.0 }) + "%")
        })
        @sf.pick(@sf.t("desktop.menu.zoom"), choices, @signals.untracked(zoom), fn(value) {
          @settings.set_pref(core, "windowZoom", value)
        }, from=@sf.beside_node(b), search=false)
      }
      None => ()
    }
  })
  anchor.val = Some(button)
}
