// A page's bar in a panel of its own on the tape (sfdesk's pane_bar_node.mbt, tape_page.mbt's tape_bar_head) a node of
// the window's tree over its page: its title (one with a head of its own: what it is of) the same node as what the page
// says of it changes; a page with actions of its own its whole bar as before (pane_page), the tree's none; what it is
// for shown as a finger taps its mark, till the next tap; back pressed in it, or swiped from its edge over it, the
// stack's; nothing of it read out while its panel is not the one in use.

///|
/// `mode` on the tape of a window `w` × `h` of `platform` (a finger's: a tablet's Medium, its host saying so), the
/// core's prefs saying the words' language `lang` as it is now (none: the device's, Chinese).
fn tape_bar_in(
  mode : String,
  lang : Ref[String],
  platform? : Int = 2,
  w? : Double = 600.0,
  h? : Double = 900.0,
  wrap? : (Source) -> Source = fn(s) { s },
) -> @ui.Tester {
  let src : Ref[Source?] = Ref(None)
  let made = fn() {
    match src.val {
      Some(s) => s
      None => {
        let base = wrap(fixture_app(mode))
        let s : Source = {
          ..base,
          topic: fn(name, params) {
            let got = (base.topic)(name, params)
            if name != "prefs" || lang.val == "" {
              return got
            }
            let o = match got.value {
              Some(Object(m)) => m.copy()
              _ => {}
            }
            o["lang"] = Json::string(lang.val)
            { ..got, value: Some(Json::object(o)) }
          },
        }
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(
    fn(c) { view(c, made()) },
    tree=fn(root) { app_tree(made())(root) },
    w~,
    h~,
    platform~,
    env=[("MBUI_LOCALE", "zh")],
  )
  if platform == 2 {
    say_room(t, "medium", "medium")
  }
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The page's panel on the tape (the rightmost box as round as a pane, as wide as a page: words_in_page's).
fn tape_page_panel(t : @ui.Tester) -> @ui.Laid? {
  let mut page : @ui.Laid? = None
  for b in t.boxes_held() {
    if b.radius >= 11.0 && b.w >= 300.0 && b.h >= 300.0 && b.y < 50.0 && (page is None || b.x > page.unwrap().x) {
      page = Some(b)
    }
  }
  page
}

///|
/// The nodes of the tree's own (not an old view's) in the page's panel's bar (its top 60) drawing `words`, faded in.
fn bar_words_drawn(t : @ui.Tester, words : String) -> Array[@view.Drawn] {
  guard tape_page_panel(t) is Some(p) else { return [] }
  match @ui.view_tree() {
    Some(tree) =>
      tree
      .drawn()
      .filter(fn(d) {
        !d.hosted && d.words == words && d.alpha > 0.5 && d.x >= p.x && d.x < p.x + p.w && d.y < p.y + 60.0
      })
    None => []
  }
}

///|
/// The words `words` an old view draws in the page's panel's bar (its top 60): each one's place.
fn bar_words_old(t : @ui.Tester, words : String) -> Array[(Double, Double)] {
  guard tape_page_panel(t) is Some(p) else { return [] }
  // (the old views' own: the tree's held boxes hold the tree's words too)
  t.boxes().filter(fn(b) { b.kind == "text" && b.text == words && b.x >= p.x && b.y < p.y + 60.0 }).map(fn(b) {
    (b.x, b.y)
  })
}

///|
test "on the tape a settings page's bar is the tree's: its title the same node as the core's language changes it; one with a head of its own, what it is of" {
  let lang = Ref("")
  let t = tape_bar_in("settings-appearance", lang)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  let zh = bar_words_drawn(t, "外观")
  assert_eq(zh.length(), 1, msg="外观 in the bar: \{zh.length()}")
  // (the old view's none: one bar)
  assert_eq(bar_words_old(t, "外观").length(), 0)
  lang.val = "en"
  t.run_for(@ui.move_most_ms)
  let en = bar_words_drawn(t, "Appearance")
  assert_eq(en.length(), 1, msg="Appearance in the bar: \{en.length()}")
  assert_eq(en[0].id, zh[0].id)
  assert_eq(bar_words_drawn(t, "外观").length(), 0)
  // a head of its own: the bar says what it is of
  for page in [("settings-station", "Station"), ("settings-profile", "Profile")] {
    let t = tape_bar_in(page.0, Ref(""))
    assert_eq(bar_words_drawn(t, page.1).length(), 1, msg="\{page.0}")
    assert_eq(bar_words_old(t, page.1).length(), 0, msg="\{page.0}")
  }
}

///|
test "on the tape 用量 made once: its bar the tree's, its title where a chat's stands, what it does at its end; another workspace, the bar's share its; none, nothing of the one before" {
  let chat = screen_in("chat", ("touch", 600.0, 900.0, 2, "medium"), "zh")
  guard words_in_page(chat, "整理发布清单") is Some((cx, cy, _)) else { fail("no chat's title") }
  // (the workspaces as `listed` says: none while it says so)
  let listed = @signals.signal(true)
  let shared : Array[String] = []
  @sfbase.share_card_of.val = fn(_, w) { shared.push(w.id) }
  let src : Ref[Source?] = Ref(None)
  let t = tape_bar_in("settings-usage", Ref(""), wrap=fn(base) {
    let s : Source = {
      ..base,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name == "workspaces" && !listed.get() {
          return { ..got, value: Some(Json::array([])) }
        }
        got
      },
    }
    src.val = Some(s)
    s
  })
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq(bar_words_drawn(t, "用量").length(), 1)
  assert_eq(bar_words_old(t, "用量").length(), 0)
  guard words_in_page(t, "用量") is Some((x, y, _)) else { fail("no title") }
  assert_true((x - cx).abs() < 0.5 && (y - cy).abs() < 0.5, msg="its title at \{x}, \{y}; a chat's at \{cx}, \{cy}")
  // (its days and its share in the bar)
  assert_eq(bar_words_drawn(t, "7 天").length(), 1, msg="its days in the bar")
  let share = fn() {
    t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == @sf.t("web-main.stations.shareCard") && !s.hidden })
  }
  guard share() is [b] else { fail("its share read out \{share().length()} times") }
  t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  // (another workspace in view: the page made again for it, its share the bar's then)
  @sfbase.pick_workspace(src.val.unwrap(), "ws2")
  t.run_for(@ui.move_most_ms)
  @sfdesk.bring_page()
  t.run_for(@ui.move_most_ms)
  guard share() is [b2] else { fail("its share read out \{share().length()} times in ws2") }
  t.tap(b2.rect.0 + b2.rect.2 / 2.0, b2.rect.1 + b2.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(shared, ["ws1", "ws2"])
  // (no workspace in view: nothing of the page's in the bar)
  listed.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(share().length(), 0, msg="its share left over")
  assert_eq(bar_words_drawn(t, "7 天").length(), 0, msg="its days left over")
  @sfbase.share_card_of.val = fn(_, _) {  }
}

///|
/// Whether what 本机 Station is for shows (its mark's tip, the tree's).
fn about_shows() -> Bool {
  match @ui.view_tree() {
    Some(tree) => tree.drawn().iter().any(fn(d) { !d.hosted && d.words.has_prefix("这台") && d.alpha > 0.5 })
    None => false
  }
}

///|
test "on the tape a finger's tap on the bar's mark shows what the page is for till the next tap: on it, on the bar, on the page; held, dragged or called off it stays" {
  let t = tape_bar_in("settings-local-station", Ref(""))
  let marks = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "说明" && !s.hidden })
  assert_eq(marks.length(), 1)
  let (mx, my, mw, mh) = marks[0].rect
  let tap_mark = fn() {
    t.tap(mx + mw / 2.0, my + mh / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  // (on the bar, past the title and the mark: nothing there takes it)
  let (bx, by) = (mx + mw + 80.0, my + mh / 2.0)
  assert_false(about_shows())
  tap_mark()
  assert_true(about_shows(), msg="tapped open")
  // held on the bar, then called off: shown still
  t.touch(0, bx, by)
  t.run_for(@ui.long_press_ms + 100.0)
  assert_true(about_shows(), msg="held")
  t.touch(3, bx, by)
  t.run_for(@ui.move_most_ms)
  assert_true(about_shows(), msg="called off")
  // dragged past the slop and back to where it went down, let go there: shown still
  t.touch(0, bx, by)
  t.touch(1, bx + 60.0, by)
  t.touch(1, bx, by)
  t.touch(2, bx, by)
  t.run_for(@ui.move_most_ms)
  assert_true(about_shows(), msg="dragged and back")
  // let go away from where it went down, no move told: there the page's own view (its room under the bar), whose rule
  // a tap is (the old views' tapped_anywhere: not dragged, as no move told it): gone, as on main
  t.touch(0, bx, by)
  t.touch(2, bx + 60.0, by)
  t.run_for(@ui.move_most_ms)
  assert_false(about_shows(), msg="let go away, the page's own view's tap")
  tap_mark()
  assert_true(about_shows(), msg="tapped open after")
  // a tap on the bar: gone
  t.tap(bx, by)
  t.run_for(@ui.move_most_ms)
  assert_false(about_shows(), msg="a tap on the bar")
  // open again; a tap on it again: gone, and again: shown
  tap_mark()
  assert_true(about_shows(), msg="tapped open again")
  tap_mark()
  assert_false(about_shows(), msg="a tap on it again")
  tap_mark()
  assert_true(about_shows(), msg="and again")
  // a tap on the page under the bar (its old view's words): gone
  match t.rect_of(local_none) {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("no \{local_none}")
  }
  t.run_for(@ui.move_most_ms)
  assert_false(about_shows(), msg="a tap on the page")
  // pressed by a screen reader: shown; again: gone; shown, then the next tap anywhere: gone
  let press = fn() {
    let id = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "说明" && !s.hidden })[0].id
    t.advance(between_frames_ms)
    @ui.current().ask_action(id, Activate)
    t.run_for(@ui.move_most_ms)
  }
  press()
  assert_true(about_shows(), msg="a screen reader's press")
  press()
  assert_false(about_shows(), msg="a screen reader's press again")
  press()
  t.tap(bx, by)
  t.run_for(@ui.move_most_ms)
  assert_false(about_shows(), msg="the next tap after a screen reader's press")
}

///|
/// A station's memory a level further in from 记忆 on the tape of a window 600 × 760 of `platform` (a Mac's; else a
/// finger's, its host saying Medium), its page in use: back to 记忆 there.
fn tape_station_memory(platform? : Int = 0, said? : Bool = false, font? : Double = 1.0, w? : Double = 600.0) -> @ui.Tester raise {
  new_run()
  let src = fixture("settings")
  let src = if said { @sffixture.said_longest_source(src) } else { src }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=760.0, platform~)
  if platform != 0 {
    say_room(t, "medium", "medium")
  }
  if font != 1.0 {
    t.set_font_scale(font)
  }
  t.draw()
  open_page(Settings)
  t.run_for(@ui.move_most_ms)
  t.click(Link, label="记忆")
  t.run_for(@ui.move_most_ms)
  page_over(t, w)
  // (the station's row: its name as it wrote it, the first line of it)
  match t.words().search_by(fn(w) { w.0.has_prefix("Studio") }) {
    Some(i) => {
      let w = t.words()[i]
      t.tap(w.1 + 4.0, w.2 + 4.0)
    }
    None => fail("no Studio")
  }
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(settings_page_whole(t, "发布流程", w))
  t
}

///|
/// The tree's back in the bar, by what it is: the one button read out 记忆 (where it goes), in the panel's bar (its top
/// 60, at its left); where it is.
fn tape_bar_back(t : @ui.Tester) -> (Double, Double, Double, Double) raise {
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  let backs = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "记忆" && !s.hidden })
  guard backs is [b] else { fail("back read out \{backs.length()} times") }
  let (x, y, w, h) = b.rect
  assert_true(x >= p.x && x + w < p.x + 80.0 && y >= p.y && y + h <= p.y + 60.0, msg="back at \{b.rect}")
  b.rect
}

///|
test "on the tape back in a page's bar pressed, or a swipe from its edge over the bar: the page under it; the swipe let go back where it began, the page stays" {
  // pressed
  let t = tape_station_memory()
  let depth = app.nav.depth()
  let (x, y, w, h) = tape_bar_back(t)
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), depth - 1)
  // swiped from its left edge, from the bar, by a finger where the app takes it (an iPad's: Android's is the system's,
  // a Mac's top row moves the window)
  let t = tape_station_memory(platform=1)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  let y = p.y + 20.0
  // (across and back where it began, one hold, its moves a finger's apart: called off, the page stays)
  t.touch(0, p.x + 6.0, y)
  for i in 1..=6 {
    t.advance(@ui.input_step_ms)
    t.touch(1, p.x + 6.0 + 194.0 * i.to_double() / 6.0, y)
  }
  for i in 1..=6 {
    t.advance(@ui.input_step_ms)
    t.touch(1, p.x + 200.0 - 194.0 * i.to_double() / 6.0, y)
  }
  t.touch(2, p.x + 6.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), depth, msg="let go where it began")
  assert_true(settings_page_whole(t, "发布流程", 600.0))
  t.drag(p.x + 6.0, y, p.x + 400.0, y, steps=10)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), depth - 1, msg="swiped across")
}

///|
test "on the tape a page's bar read out while its panel is the one in use, none of it while another is" {
  let t = tape_bar_in("settings-local-station", Ref(""))
  let said = fn() {
    t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "说明" && !s.hidden }).length()
  }
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq(said(), 1)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(said(), 0)
}

///|
test "on the tape a page's bar with a long title in words twice as large: the title cut short, back and its mark whole in the bar, nothing past the panel" {
  let t = tape_station_memory(platform=1, said=true, font=2.0)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  let (bx, _, bw, _) = tape_bar_back(t)
  let marks = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "说明" && !s.hidden })
  assert_eq(marks.length(), 1)
  let (mx, _, mw, _) = marks[0].rect
  // (back and the mark as large as they are, the mark after back, both in the panel short of its end)
  assert_true(bw >= 32.0 && mw >= 20.0, msg="back \{bw}, the mark \{mw}")
  assert_true(bx + bw <= mx && mx + mw <= p.x + p.w, msg="back to \{bx + bw}, the mark \{mx} to \{mx + mw}, the panel to \{p.x + p.w}")
  // (the title cut between them: begun after back, ended before the mark)
  match @ui.view_tree() {
    Some(tree) => {
      let titles = tree.drawn().filter(fn(d) { !d.hosted && d.words.has_prefix("Studio") && d.y < p.y + 60.0 })
      assert_eq(titles.length(), 1)
      assert_true(titles[0].x >= bx + bw && titles[0].x + titles[0].w <= mx, msg="the title \{titles[0].x} to \{titles[0].x + titles[0].w}")
    }
    None => fail("no tree")
  }
}


///|
/// The tree's own nodes in the page's panel under its bar drawing `words` (a page made once's), not an old view's.
fn page_words_made(t : @ui.Tester, words : String) -> Int {
  guard tape_page_panel(t) is Some(p) else { return 0 }
  match @ui.view_tree() {
    Some(tree) =>
      tree.drawn().filter(fn(d) { !d.hosted && d.words == words && d.x >= p.x && d.y >= p.y + 50.0 && d.alpha > 0.5 }).length()
    None => 0
  }
}

///|
test "on the tape 关于 made once under the tape's bar, its page narrow or wider: its rows the tree's, its title the bar's alone" {
  // (600 across: its page 530, narrow; 839: wider than a narrow page is, laid out wide)
  for win in [600.0, 839.0] {
    let t = tape_bar_in("settings-about", Ref(""), w=win, h=900.0)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
    assert_eq(page_words_made(t, "更新日志"), 1, msg="\{win}: its rows the tree's")
    assert_eq(bar_words_drawn(t, "关于").length(), 1, msg="\{win}: the bar's title")
    assert_eq(bar_words_old(t, "关于").length(), 0, msg="\{win}: no old bar")
  }
}

///|
test "on the tape 关于 as the window is made wider and narrower, its page told nothing: the same nodes while its arrangement stays, laid out again only as it changes (narrow, wide, narrow)" {
  let t = tape_bar_in("settings-about", Ref(""), w=600.0, h=900.0)
  let rows = fn() { @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == "更新日志" }).map(fn(d) { d.id }) }
  assert_eq(page_words_made(t, "更新日志"), 1)
  let narrow = rows()
  // (wider, its page still narrow: the same nodes; 590 would be no tape at all, a small screen's)
  t.resize(620.0, 900.0)
  t.run_for(@ui.move_most_ms)
  assert_true(rows() == narrow)
  // (wide, its page 650: laid out again, wide)
  t.resize(720.0, 900.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(page_words_made(t, "更新日志"), 1)
  let wide = rows()
  assert_true(wide != narrow)
  // (wider still, as wide as a tape is: the same nodes)
  t.resize(839.0, 900.0)
  t.run_for(@ui.move_most_ms)
  assert_true(rows() == wide)
  // (narrow again: laid out again, narrow)
  t.resize(600.0, 900.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(page_words_made(t, "更新日志"), 1)
  assert_true(rows() != wide)
}

///|
test "on the tape 关于 made once scrolled: what it holds goes under nothing of the bar, cut at the bar's foot" {
  // (a window too short for all it holds, its words twice as large: it scrolls)
  let t = tape_bar_in("settings-about", Ref(""), w=600.0, h=420.0)
  t.set_font_scale(2.0)
  t.run_for(@ui.move_most_ms)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  let foot = p.y + @sf.wide_bar_h + @sf.tape_bar_over()
  let under_bar = fn() {
    // (what of a glyph is seen (its left, top, right, foot) in the bar's lowest 10, where the bar's own words are not:
    // the page's, come under it)
    t.glyphs_seen().filter(fn(g) { g.0 >= p.x && g.0 < p.x + p.w && g.3 > foot - 10.0 && g.1 < foot - 0.5 })
  }
  assert_eq(under_bar(), [])
  let row = fn() {
    match @ui.view_tree() {
      Some(tree) =>
        match tree.drawn().search_by(fn(d) { !d.hosted && d.words == "更新日志" }) {
          Some(i) => tree.drawn()[i].y
          None => -1.0e9
        }
      None => -1.0e9
    }
  }
  let y0 = row()
  t.drag(p.x + p.w / 2.0, 360.0, p.x + p.w / 2.0, 100.0, steps=8)
  t.run_for(@ui.move_most_ms)
  // (scrolled: its rows gone up, those above the bar's foot cut there)
  assert_true(row() < y0 - 50.0, msg="its row at \{y0}, then \{row()}")
  assert_eq(under_bar(), [])
}

///|
/// `base` with the station Studio (ws1/st1) named `name` in what the core says of the stations, as that is set ("" as
/// it is): told as it changes, as the core tells it.
fn station_named(base : Source, name : @signals.Signal[String]) -> Source {
  {
    ..base,
    topic: fn(topic, params) {
      let r = (base.topic)(topic, params)
      let n = name.get()
      match (topic, r.value) {
        ("stations", Some(Array(a))) if n != "" =>
          {
            ..r,
            value: Some(
              Json::array(
                a.map(fn(st) {
                  match st {
                    Object(m) if m.get("station") == Some(Json::string("ws1/st1")) => {
                      let m2 = m.copy()
                      m2["name"] = Json::string(n)
                      Json::object(m2)
                    }
                    _ => st
                  }
                }),
              ),
            ),
          }
        _ => r
      }
    },
  }
}

///|
/// 归档 on a tablet's tape 600 across (its page narrow), the core's prefs saying the language `lang` as it is now, a
/// station's row pressed: its own archiving, made once, its page in use.
fn tape_station_archiving(
  lang : Ref[String],
  platform? : Int = 2,
  name? : @signals.Signal[String] = @signals.signal(""),
) -> @ui.Tester raise {
  let t = tape_bar_in("settings-archiving", lang, platform~, w=600.0, h=900.0, wrap=fn(s) { station_named(s, name) })
  t.tap_text("Studio")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::StationArchiving("ws1/st1")), msg="on top \{@sfbase.page_kind(app.nav.top())}")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t
}

///|
test "on the tape a station's own archiving made once under the tape's bar: its title as the page says it, the same node as the language changes it; back to 归档 in the bar" {
  let lang = Ref("")
  let t = tape_station_archiving(lang)
  assert_eq(page_words_made(t, @sf.t("web-pages.archiving.mode")), 1, msg="its rows the tree's")
  let zh = bar_words_drawn(t, "自动归档 · Studio")
  assert_eq(zh.length(), 1, msg="the bar's title")
  assert_eq(bar_words_old(t, "自动归档 · Studio").length(), 0)
  let backs = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "归档" && !s.hidden })
  assert_eq(backs.length(), 1, msg="back to 归档")
  lang.val = "en"
  t.run_for(@ui.move_most_ms)
  let en = bar_words_drawn(t, "Automatic archiving · Studio")
  assert_eq(en.length(), 1, msg="the bar's title in English")
  assert_eq(en[0].id, zh[0].id)
}

///|
test "on the tape a station's own archiving made once, its station renamed as the core tells it: its title anew in the same bar, the page and the bar not made again" {
  let name = @signals.signal("")
  let t = tape_station_archiving(Ref(""), name~)
  let title = bar_words_drawn(t, "自动归档 · Studio")
  assert_eq(title.length(), 1)
  let rows = @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == @sf.t("web-pages.archiving.mode") }).map(fn(d) { d.id })
  assert_eq(rows.length(), 1)
  let depth = app.nav.depth()
  name.set("工作室")
  t.run_for(@ui.move_most_ms)
  let renamed = bar_words_drawn(t, "自动归档 · 工作室")
  assert_eq(renamed.length(), 1, msg="its title anew")
  assert_eq(renamed[0].id, title[0].id, msg="the same bar")
  assert_true(@ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == @sf.t("web-pages.archiving.mode") }).map(fn(d) { d.id }) == rows, msg="the same page")
  assert_eq(app.nav.depth(), depth)
}

///|
test "on the tape a station's own archiving made once: back in its bar pressed, or a swipe from its edge over the bar (an iPad's), 归档 again" {
  let t = tape_station_archiving(Ref(""))
  let depth = app.nav.depth()
  match said_at(t, "归档") {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("no back")
  }
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), depth - 1)
  assert_true(app.nav.top() == Setting(@settings.Route::Archiving))
  let t = tape_station_archiving(Ref(""), platform=1)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  t.drag(p.x + 6.0, p.y + 20.0, p.x + 400.0, p.y + 20.0, steps=10)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), depth - 1, msg="swiped from the bar")
}

///|
test "on the tape a station's own archiving become another station's in its place: that one's page made anew, its title in the bar" {
  let t = tape_station_archiving(Ref(""))
  let rows = @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == @sf.t("web-pages.archiving.mode") }).map(fn(d) { d.id })
  app.nav.become(Setting(@settings.Route::StationArchiving("ws1/st2")))
  t.run_for(@ui.move_most_ms)
  let now = @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == @sf.t("web-pages.archiving.mode") }).map(fn(d) { d.id })
  assert_true(now.length() <= 1 && now != rows, msg="\{rows.length()} → \{now.length()}")
  assert_eq(bar_words_drawn(t, "自动归档 · Studio").length(), 0)
  assert_eq(bar_words_drawn(t, "自动归档 · MBA").length(), 1, msg="that station's title")
  // (what that page shows under its bar, the tree's: something of its own)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  let shown = @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words != "" && d.x >= p.x && d.y >= p.y + 56.0 && d.alpha > 0.5 })
  assert_true(shown.length() > 0, msg="that page empty")
}

///|
test "on the tape 记忆, 归档 and 自动决策 made once under the tape's bar where their page is narrow: their title the bar's alone, what they hold the tree's" {
  for page in [("settings-memories", "记忆"), ("settings-archiving", "归档"), ("settings-decisions", "自动决策")] {
    let t = tape_bar_in(page.0, Ref(""), w=600.0, h=900.0)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg="\{page.0}")
    assert_eq(bar_words_drawn(t, page.1).length(), 1, msg="\{page.0}: the bar's title")
    assert_eq(bar_words_old(t, page.1).length(), 0, msg="\{page.0}: no old bar")
    guard tape_page_panel(t) is Some(p) else { fail("no page") }
    let held = @ui.view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words != "" && d.x >= p.x && d.y >= p.y + 56.0 && d.alpha > 0.5 })
    assert_true(held.length() > 0, msg="\{page.0}: what it holds the tree's")
    // (what it is for by a mark in the bar where the page says so: 自动决策's, as its old bar has it)
    let marks = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "说明" && !s.hidden }).length()
    assert_eq(marks, if page.0 == "settings-decisions" { 1 } else { 0 }, msg="\{page.0}: its mark")
  }
}

///|
test "on the tape 一台 station 的记忆 swiped from its edge by a scripted run's drag (its steps taken as each frame ends, as a film's): each frame held to the corner rule where the page is not in the hand; across, the page under it, short, the page stays" {
  // (Tester::hold_corners on every frame drawn: a frame with the page off its place and not said to be in the hand
  // fails the test where it is drawn)
  for case in [(300.0, -1, 600.0), (60.0, 0, 600.0), (300.0, -1, 720.0), (60.0, 0, 720.0), (300.0, -1, 839.0), (60.0, 0, 839.0)] {
    let (across, went, w) = case
    let t = tape_station_memory(platform=1, w~)
    let depth = app.nav.depth()
    guard tape_page_panel(t) is Some(p) else { fail("no page") }
    let x = (p.x + 6.0).to_int()
    let y = (p.y + 300.0).to_int()
    t.drive("drag \{x} \{y} \{across.to_int()} 0 600\nwait 800\nexit") |> ignore
    assert_eq(app.nav.depth(), depth + went, msg="\{across} across at \{w}")
  }
}
