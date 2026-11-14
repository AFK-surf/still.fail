// 外观, one page for every frame, made once: how this
// device shows still.fail, its settings (@sf.settings: wide, rows of one list card, each choice at its row's end;
// narrow, a block each): 主题, 主题色, 字体 (the faces chosen, opening their page: FontRow; font_setting.mbt), 动画, 震动, 语言; with
// keyboard and mouse the files dragged into a chat too, and laid out wide the rail changed in place (as the web's,
// `wideOnly`). Each choice is the core's prefs (`prefs.set`), shown at once. When a done chat is offered to archive is
// 归档's, as the web's.

///|
/// The page (AppearancePage, AppearanceScreen), made once in node `v` as wide as `width` gives it, in the frame it is
/// given: its settings (@sf.setting_node's) wide the rows of one list card, narrow a block each.
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
  // (what this device offers: its window zoomed, files dropped in; the rail changed where it is beside the page)
  let keys = fn() {
    let k = ["theme", "accent", "fonts", "motion", "haptics", "language"]
    if @ui.window_zoom_supported() {
      k.push("zoom")
    }
    if @ui.takes_drops() {
      k.push("drop")
    }
    // (the chat page tried: last of this device's own, a trial's place)
    k.push("chatPage")
    if wide() {
      k.push("rail")
    }
    k
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.appearance.title") },
    on_back~,
    frame~,
    said?,
    width?,
    fn() { if wide() { ["settings"] } else { keys() } },
    fn(b, key) {
      if key == "settings" {
        @sf.group_node(b, fn(g) { g.each(keys, fn(k) { k }, fn(r, k) { appearance_setting(r, core, k.untracked()) }) })
      } else {
        appearance_setting(b, core, key)
      }
    },
  )
}

///|
/// One of 外观's settings, by its key: 主题, 主题色, 字体 (the faces chosen, opening their page), 动画, 震动, 语言, 缩放,
/// 拖入的文件, 侧栏. Each choice the core's prefs (`prefs.set`), shown at once.
fn appearance_setting(v : @view.View, core : Core, key : String) -> Unit {
  let prefs = fn() { (core.topic)("prefs", Map([])).get().value }
  // a choice of a few (Segmented, Seg): the kept value, or the one just chosen while the core takes it
  let choice = fn(title : String, note : String, options : Array[(String, String)], now : () -> String) {
    @sf.setting_choice_node(
      v,
      fn() { @sf.t(title) },
      fn() { options.map(fn(o) { @sf.t(o.1) }) },
      fn() { options.search_by(fn(o) { o.0 == now() }).unwrap_or(0) },
      fn(i) {
        // another theme picked: it spreads from where it was picked (mbui reveal.mbt)
        if key == "theme" {
          let (x, y) = @signals.untracked(fn() { v.window_down_point() })
          @ui.reveal_from(x, y, dark=fn() { @sf.theme().dark })
        }
        @settings.set_pref(core, if key == "theme" { "appearance" } else { key }, options[i].0)
      },
      note=fn() { if note == "" { "" } else { @sf.t(note) } },
    )
  }
  match key {
    "theme" =>
      choice(
        "web-pages.appearance.theme.title",
        "web-pages.appearance.theme.description",
        [("system", "web-main.appearance.system"), ("light", "web-main.appearance.light"), ("dark", "web-main.appearance.dark")],
        fn() { @settings.appearance(prefs()) },
      )
    // the colour theme (@sf.accents, or a hue of one's own), its dots in their own colours
    "accent" => {
      let shown = fn() {
        let now = @settings.pref(core, "accent")
        if @sf.tone_of(now) is Some(_) {
          now
        } else {
          ""
        }
      }
      @sf.setting_node(
        v,
        fn() { @sf.t("web-pages.appearance.accent.title") },
        note=fn() { @sf.t("web-pages.appearance.accent.description") },
        fn(r) {
          @sf.accent_pick_node(
            r,
            fn() { accent_names.map(fn(k) { @sf.t(k) }) },
            fn() { @sf.t("web-pages.appearance.accent.custom") },
            fn() { @sf.t("web-pages.appearance.accent.hue") },
            shown,
            fn(picked) {
              if picked != @signals.untracked(shown) {
                @settings.set_pref(core, "accent", picked)
              }
            },
          )
        },
      )
    }
    // the faces chosen, opening their page (a chat as they set it and their list are a page's own, on every screen)
    "fonts" =>
      @sf.setting_link_node(
        v,
        fn() { @sf.t("web-pages.appearance.fonts.title") },
        fn() { fonts_said(prefs()) },
        fn() { (core.push)(Fonts) },
        note=fn() { @sf.t("web-pages.appearance.fonts.description") },
      )
    "motion" =>
      choice(
        "web-pages.appearance.motion.title",
        "web-pages.appearance.motion.description",
        [("", "web-pages.appearance.motion.system"), ("reduce", "web-pages.appearance.motion.reduce"), ("full", "web-pages.appearance.motion.full")],
        fn() { @settings.pref(core, "motion") },
      )
    // haptics, all of them (on unless turned off: @ui.set_haptics, app_frame.mbt)
    "haptics" =>
      @sf.setting_switch_node(
        v,
        fn() { @sf.t("web-pages.appearance.haptics.title") },
        fn() { @settings.pref(core, "haptics") != "off" },
        fn(on) { @settings.set_pref(core, "haptics", if on { "" } else { "off" }) },
        note=fn() { @sf.t("web-pages.appearance.haptics.description") },
      )
    // the chat page made as nodes, tried (the prefs' `chatPage`: sfbase's chat_page_from_prefs), off unless turned on:
    // a chat page made after the switch is pressed is the one chosen
    "chatPage" =>
      @sf.setting_switch_node(
        v,
        fn() { @sf.t("web-pages.appearance.chatPage.title") },
        fn() { @settings.pref(core, "chatPage") == "nodes" },
        fn(on) { @settings.set_pref(core, "chatPage", if on { "nodes" } else { "" }) },
        note=fn() { @sf.t("web-pages.appearance.chatPage.description") },
      )
    "language" =>
      choice(
        "common.language",
        "",
        [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")],
        fn() { @settings.pref(core, "language") },
      )
    // the window's zoom, picked beside its button
    "zoom" => {
      let zoom = fn() { @settings.pref(core, "windowZoom") }
      @sf.setting_node(v, fn() { @sf.t("desktop.menu.zoom") }, fn(r) {
        let button : Ref[@view.View?] = Ref(None)
        button.val = Some(
          @sf.button_node(r, fn() { if zoom() == "" { "100%" } else { zoom() + "%" } }, fn() {
            guard button.val is Some(b) else { return }
            let (x, y, w, h) = b.placed_window_now()
            let choices = @sfbase.window_zoom_levels.map(fn(z) {
              @sf.choice(z.0, (if z.0 == "" { "100" } else { z.0 }) + "%")
            })
            @sf.pick(@sf.t("desktop.menu.zoom"), choices, @signals.untracked(zoom), fn(value) {
              @settings.set_pref(core, "windowZoom", value)
            }, from=At(x, y, w, h), search=false)
          }),
        )
      })
    }
    // files dragged into a chat from outside (where they can be: @ui.takes_drops): named by their path (the default),
    // or sent as files
    "drop" =>
      choice(
        "web-pages.appearance.drop.title",
        "web-pages.appearance.drop.description",
        [("", "web-pages.appearance.drop.path"), ("file", "web-pages.appearance.drop.file")],
        fn() { @settings.pref(core, "dropAs") },
      )
    // the rail, changed where it is (rail.mbt): laid out wide, where the rail is beside the page (the web's wideOnly)
    "rail" =>
      @sf.setting_node(v, fn() { @sf.t("web-main.rail.title") }, note=fn() { @sf.t("web-main.rail.lead") }, fn(r) {
        @sf.button_node(r, fn() { @sf.t("web-main.rail.customize") }, fn() { @sfbase.edit_rail() }) |> ignore
      })
    _ => ()
  }
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
/// 字体's page, one for every frame (opened from 外观's row narrow): what it is for under
/// its title, the setting (font_setting.mbt).
pub fn fonts_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  @sf.page(c, on_back=core.pop, frame~, "fonts", @sf.t("web-pages.appearance.fonts.title"), fonts_blocks(c, core), lead=@sf.t(
    "web-pages.appearance.fonts.description",
  ))
}

///|
/// The accents' names, as @sf.accents has them.
// kept across runs: a value (no element of it changes)
let accent_names : Array[String] = [
  "web-pages.appearance.accent.orange", "web-pages.appearance.accent.blue", "web-pages.appearance.accent.teal", "web-pages.appearance.accent.purple",
  "web-pages.appearance.accent.pink",
]
