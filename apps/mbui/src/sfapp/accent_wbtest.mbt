// 外观's 主题色 (sfpages appearance.mbt, @sf.accent_pick; the prefs' `accent`): a colour theme chosen is the app's at once,
// by day and by night, the core told to keep it; still.fail's orange chosen again, none kept.

///|
test "主题色 蓝色 chosen, laid out narrow and wide, with touch and with a mouse: the accent and the grounds blue at once in light and dark, the core keeps it; 橙色, none kept" {
  for case in [(390.0, 2), (390.0, 0), (1280.0, 0)] {
    let (w, platform) = case
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=844.0, platform~)
    app.nav.push(Settings)
    app.nav.push(Setting(@settings.Route::Appearance))
    t.draw()
    t.run_for(@ui.move_most_ms)
    let orange = @sf.accents[0]
    let blue = @sf.accents[1]
    assert_eq(@sf.theme().p.accent, orange.light, msg="\{w}")
    let bg_orange = @sf.theme().p.bg
    assert_eq(t.get(Radio, label="橙色").selected, Some(true))
    // (each dot a press's least room apart from the next: 36 with a mouse, 44 with touch)
    let (x0, _, w0, _) = t.get(Radio, label="橙色").rect
    let (x1, _, w1, _) = t.get(Radio, label="蓝色").rect
    assert_eq(x1 + w1 / 2.0 - (x0 + w0 / 2.0), @ui.room_least(), msg="\{w}")
    t.click(Radio, label="蓝色")
    t.frame()
    t.frame()
    let set = named(calls, "prefs.set")
    assert_eq(text(Some(set[set.length() - 1].params), "accent"), "blue")
    assert_eq(@sf.accent_key(), "blue")
    assert_eq(@sf.theme().p.accent, blue.light)
    assert_eq(@sf.theme().p.accent_text, blue.light_text)
    // the page's grounds neutral (no warmth, no hue), the rail and the sidebar deep in its hue with white words, as
    // Slack's themes draw them
    let page = @sf.theme().p
    assert_true(page.bg != bg_orange, msg="\{w}: the warm paper gone")
    assert_true(neutral(page.bg), msg="\{w}: the page neutral")
    assert_eq(@sf.ui_theme().bg, page.bg)
    let side = @view.in_scope(@sf.side_scope, fn() { @sf.theme() })
    assert_true(side.dark, msg="\{w}")
    assert_true(@ui.contrast_ratio(0xFFFFFFFFL, side.p.sidebar) >= 9.0, msg="\{w}: the sidebar deep")
    assert_true(blue_ish(side.p.sidebar), msg="\{w}: the sidebar in its hue")
    assert_eq(@view.in_scope(@sf.side_scope, fn() { @sf.ui_theme() }).sidebar, side.p.sidebar)
    assert_eq(@view.in_scope(@sf.side_scope, fn() { @sf.ui_theme() }).bg, side.p.bg)
    // what a style's Accent and AccentText say, mbui's theme's
    assert_eq(@sf.ui_theme().accent, blue.light)
    assert_eq(@sf.ui_theme().accent_text, blue.light_text)
    assert_eq(t.get(Radio, label="蓝色").selected, Some(true))
    assert_eq(t.get(Radio, label="橙色").selected, Some(false))
    @sf.set_dark(Some(true))
    assert_eq(@sf.theme().p.accent, blue.dark)
    assert_eq(@sf.theme().p.accent_text, blue.dark_text)
    assert_eq(@sf.palette_of(true).accent, blue.dark)
    assert_true(neutral(@sf.theme().p.bg), msg="\{w}: the night's page neutral")
    assert_true(blue_ish(@view.in_scope(@sf.side_scope, fn() { @sf.theme() }).p.sidebar), msg="\{w}: by night too")
    @sf.set_dark(Some(false))
    t.click(Radio, label="橙色")
    t.frame()
    t.frame()
    let set = named(calls, "prefs.set")
    assert_true(field(Some(set[set.length() - 1].params), "accent") is Some(Null))
    assert_eq(@sf.accent_key(), "")
    assert_eq(@sf.theme().p.accent, orange.light)
    assert_eq(@sf.theme().p.bg, bg_orange, msg="the warm paper back")
    // the orange's sidebar its own, as it was: the warm paper's a step under the page
    assert_eq(@view.in_scope(@sf.side_scope, fn() { @sf.theme() }).p.sidebar, @sf.theme().p.sidebar)
  }
}

///|
test "an accent the build does not know (kept by a newer one): still.fail's orange" {
  new_run()
  @sf.set_accent("indigo")
  assert_eq(@sf.accent_key(), "")
  @sf.set_accent("teal")
  assert_eq(@sf.theme().p.accent, @sf.accents[2].light)
  @sf.set_accent("")
}

///|
test "主题色 自定义: a hue of one's own, its slider under the dots; a step along it is the theme's at once, the core keeps it" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=844.0, platform~)
    app.nav.push(Settings)
    app.nav.push(Setting(@settings.Route::Appearance))
    t.draw()
    t.run_for(@ui.move_most_ms)
    // no slider till 自定义 is chosen
    assert_true(t.semantics().filter(fn(s) { s.role == Slider }).is_empty(), msg="\{w}")
    t.click(Radio, label="自定义")
    t.frame()
    t.frame()
    let set = named(calls, "prefs.set")
    assert_eq(text(Some(set[set.length() - 1].params), "accent"), "custom:210")
    assert_eq(@sf.accent_key(), "custom:210")
    assert_eq(@sf.theme().p.accent, @sf.custom_tone(210).light)
    assert_true(neutral(@sf.theme().p.bg), msg="\{w}")
    assert_eq(t.get(Radio, label="自定义").selected, Some(true))
    // its hues, as wide as the dots: a step along
    let hue = t.get(Slider, label="色相")
    let (dx, _, _, _) = t.get(Radio, label="橙色").rect
    let (ex, _, ew, _) = t.get(Radio, label="自定义").rect
    let (hx, _, hw, _) = hue.rect
    assert_eq((hx, hw), (dx, ex + ew - dx), msg="\{w}: the slider under the dots")
    t.act(Slider, Increment, label="色相")
    t.frame()
    t.frame()
    let set = named(calls, "prefs.set")
    assert_eq(text(Some(set[set.length() - 1].params), "accent"), "custom:215")
    assert_eq(@sf.theme().p.accent, @sf.custom_tone(215).light)
    // a preset again: the slider goes, the hue kept for 自定义's next press
    t.click(Radio, label="紫色")
    t.frame()
    t.frame()
    assert_eq(@sf.accent_key(), "purple")
    t.draw()
    assert_true(t.semantics().filter(fn(s) { s.role == Slider }).is_empty(), msg="\{w}")
    t.click(Radio, label="自定义")
    t.frame()
    t.frame()
    assert_eq(@sf.accent_key(), "custom:215")
  }
}

///|
/// Whether a colour is a grey (its channels within 5 of each other).
fn neutral(c : Int64) -> Bool {
  let (r, g, b) = ((c >> 24) & 0xFFL, (c >> 16) & 0xFFL, (c >> 8) & 0xFFL)
  let most = r.max(g).max(b)
  let least = r.min(g).min(b)
  most - least <= 5L
}

///|
/// Whether a colour is a blue (its blue well over its red and green).
fn blue_ish(c : Int64) -> Bool {
  let (r, g, b) = ((c >> 24) & 0xFFL, (c >> 16) & 0xFFL, (c >> 8) & 0xFFL)
  b > r + 30L && b > g + 20L
}

///|
test "主题色 蓝色, wide: the rail and the sidebar drawn deep in its hue, the page beside them neutral; 橙色, the sidebar the warm paper's again" {
  for dark in [false, true] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w=1280.0, h=800.0)
    @sf.set_dark(Some(dark))
    // (chosen as a person does: the prefs' accent, which the frame applies)
    app.nav.push(Settings)
    app.nav.push(Setting(@settings.Route::Appearance))
    t.draw()
    t.run_for(@ui.move_most_ms)
    t.click(Radio, label="蓝色")
    t.frame()
    t.frame()
    // the settings' sidebar (an old view in the block) in the hue
    let side = @view.in_scope(@sf.side_scope, fn() { @sf.theme() }).p
    assert_true(blue_ish(side.sidebar), msg="dark \{dark}")
    assert_true(
      t.drawn_rects().iter().any(fn(r) { r.4 == side.sidebar && r.0 < 80.0 && r.3 >= 700.0 }),
      msg="dark \{dark}: no rect of the sidebar's hue beside the settings",
    )
    // 外观 lit in the settings' list (its rows built as the list lays them out) on what is chosen in the hue
    assert_true(
      t.drawn_rects().iter().any(fn(r) { r.4 == side.selected && r.0 < 80.0 && r.2 > 150.0 && r.0 + r.2 < 300.0 }),
      msg="dark \{dark}: 外观 not lit in the sidebar's hue",
    )
    app.nav.pop() |> ignore
    app.nav.pop() |> ignore
    t.draw()
    t.run_for(@ui.move_most_ms)
    let side = @view.in_scope(@sf.side_scope, fn() { @sf.theme() }).p
    let page = @sf.theme().p
    let rects = t.drawn_rects()
    // the block's ground, the window's height, from its left
    assert_true(
      rects.iter().any(fn(r) { r.4 == side.sidebar && r.0 < 80.0 && r.3 >= 700.0 }),
      msg="dark \{dark}: no rect of the sidebar's hue down the window's left",
    )
    // its words (新建对话) on it
    let (nx, _) = t.find("新建对话").unwrap()
    assert_true(
      rects.iter().any(fn(r) { r.4 == side.sidebar && r.0 <= nx && r.0 + r.2 >= nx }),
      msg="dark \{dark}: 新建对话 off the sidebar's hue",
    )
    // the page neutral beside it
    assert_true(rects.iter().any(fn(r) { r.4 == page.bg && r.0 >= 200.0 }), msg="dark \{dark}: no neutral page")
    assert_true(neutral(page.bg), msg="dark \{dark}: \{page.bg.to_string(radix=16)}")
    app.nav.push(Settings)
    app.nav.push(Setting(@settings.Route::Appearance))
    t.draw()
    t.run_for(@ui.move_most_ms)
    t.click(Radio, label="橙色")
    t.frame()
    t.frame()
    let orange = @sf.theme().p
    assert_true(!t.drawn_rects().iter().any(fn(r) { r.4 == side.sidebar }), msg="dark \{dark}: the hue left over")
    assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == orange.sidebar && r.0 < 80.0 }), msg="dark \{dark}")
    @sf.set_dark(Some(false))
  }
}
