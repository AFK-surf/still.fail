// A tab of the station's browser, shown as a browser shows one (the user, 2026-11-13: 「更像普通浏览器」「操作太复杂了，
// 而且不够符合直觉」): over the page, a person's own pages on the station (`userTab`) as a row of tabs, the one shown
// pressed, each closed by its ×, ＋ a new one; under them ← → ⟳ and the address bar, its whole address shown, the
// words typed there gone to (or searched for, the station's `addressOrSearch`) on Enter. Where the page is narrow the
// tabs fold into a button that counts them, its panel listing them. A new tab is there as it is pressed (the user,
// 2026-11-13: 「会等 station 开了这边才开，点个按钮要半天」): its id made here (@settings.new_browser_tab), its view
// opened at once on its blank page, its address bar taking the keys, while its station makes it. That a tab sleeps
// while nobody looks at it is the station's own and never shown: pressed, it is woken.
//
// With keyboard and mouse, a browser's keys: ⌘L (Ctrl+L) the address bar, ⌘T a new tab, ⌘W this one closed, ⌘[ ⌘]
// back and forward, ⌘R again (screen_view's screen_keys_in).

///|
/// Whether the viewer shows the browser's bar: a tab of the station's browser that this viewer may send an address to
/// (driving it), or one of a person's own pages there.
fn browser_shown(s : ScreenSess) -> Bool {
  let tab = s.screen.has_prefix("browser:") || text(s.state, "kind") == "browser"
  s.open_now() && tab && (s.user_tab() || flag(s.state, "openUrl"))
}

///|
/// A person's own pages on the station, in the order they were opened (the station's list keeps it).
fn user_tabs_of(s : ScreenSess) -> Array[Json] {
  let sc = s.src.topic("screens", { "station": Json::string(s.station) }).get().value
  items(sc, "screens").filter(fn(item) { is_user_screen(Some(item)) })
}

///|
/// A tab's name: its page's title; a new tab's blank page (no title, `about:blank`) 新标签页.
fn tab_words(title : String) -> String {
  if title == "" || title == "about:blank" {
    @sf.t("web-pages.screen.newTab")
  } else {
    title
  }
}

///|
/// What the address bar shows of a tab's address: none for a new tab's blank page (its placeholder then).
fn address_shown(s : ScreenSess) -> String {
  let a = text(s.state, "address")
  if a == "about:blank" {
    ""
  } else {
    a
  }
}

///|
/// One of a view's tabs (view_tabs): a person's page on the station's browser, or the whole of a desktop or one of its
/// windows; its words, what its tip says, whether it is the one shown, what pressing it does, and its × (none: kept).
/// What is done is said as a value and done by tab_do in the press's handler, never as a frame is built.
priv struct ViewTab {
  key : String
  words : String
  note : String
  current : Bool
  press : TabAct
  close : TabAct?
}

///|
/// What one of the view's tabs does pressed: a person's page shown (its id, its title), a desktop's window shown alone
/// (none: the whole display), a page closed (its id), a new tab.
priv enum TabAct {
  Show(String, String)
  Window(Double?)
  Close(String)
  Add
}

///|
/// Tab action `act` done (in a press's handler): `close` closes the viewer where its last tab closes.
fn tab_do(s : ScreenSess, u : ScreenUi, act : TabAct, close : () -> Unit) -> Unit {
  match act {
    Show(id, title) => if id != s.screen { switch_screen_to(s, u, id, title, false) }
    Window(window) => {
      let p : Map[String, Json] = { "t": Json::string("window") }
      match window {
        Some(n) => p["id"] = Json::number(n)
        None => ()
      }
      s.input(s.src, Json::object(p))
    }
    Close(id) => close_tab(s, u, id, user_tabs_of(s), close)
    Add => new_tab_from(s, u)
  }
}

///|
/// The view's tabs (the user, 2026-11-13: 「远程控制也支持按窗口查看，类似浏览器按 tab 查看」): a person's pages on the
/// station's browser while one is shown, each closed by its × (`add` then 新标签页); a desktop's whole screen and each
/// window its station says it has (`windows`, `window` the one shown alone), pressed shown alone; else none (an agent's
/// tab, a simulator: its name in their place).
fn view_tabs(s : ScreenSess) -> (Array[ViewTab], Bool) {
  if s.user_tab() {
    let listed = user_tabs_of(s)
    let tabs = listed.map(fn(item) {
      let id = text(Some(item), "id")
      let title = text(Some(item), "title")
      {
        key: id,
        words: tab_words(title),
        note: text(Some(item), "site"),
        current: id == s.screen,
        press: Show(id, title),
        close: Some(Close(id)),
      }
    })
    return (tabs, true)
  }
  let windows = items(s.state, "windows")
  if windows.is_empty() || !s.open_now() {
    return ([], false)
  }
  let shown = match field(s.state, "window") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let tabs : Array[ViewTab] = [
    {
      key: "screen",
      words: @sf.t("web-pages.screen.wholeScreen"),
      note: "",
      current: shown is None,
      press: Window(None),
      close: None,
    },
  ]
  for w in windows {
    let id = match field(Some(w), "id") {
      Some(Number(n, ..)) => n
      _ => continue
    }
    let app = text(Some(w), "app")
    let title = text(Some(w), "title")
    tabs.push({
      key: "w\{id}",
      words: if title == "" { app } else if app == "" { title } else { app + " – " + title },
      note: app,
      current: shown == Some(id),
      press: Window(Some(id)),
      close: None,
    })
  }
  (tabs, false)
}

///|
/// The view's tabs in a row (the viewer's bar's middle with keyboard and mouse): each a capsule, the one shown pressed,
/// then ＋ where there is one to add.
fn tabs_row(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, tabs : Array[ViewTab], add : Bool, close : () -> Unit) -> Unit {
  c.box(style=browser_tabs_row, fn() {
    for t in tabs {
      view_tab(c, s, u, t, close)
    }
    if add {
      round_button(c, "browser-new-tab", "plus", @sf.t("web-pages.screen.newTab"), on_press=fn() { tab_do(s, u, Add, close) })
    }
  })
  |> ignore
}

///|
/// Whether the view's bar is laid out narrow: beside its chat in a panel's tab, or in a narrow window.
fn view_narrow(c : @ui.Ctx, u : ScreenUi) -> Bool {
  u.in_tab || c.window_size().0 < browser_wide_at
}

///|
/// The browser's row over the page (see the file's head): ← → ⟳ and the address bar; narrow, ← and the address bar,
/// the tabs folded into the button counting them (`tabs`) at its end.
fn browser_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, close : () -> Unit) -> Unit {
  browser_seen(s)
  let narrow = view_narrow(c, u)
  c.box(style=browser_bar_box, fn() {
    c.box(style=browser_tools_row, fn() { browser_tools(c, s, u, close, narrow) }) |> ignore
  })
  |> ignore
}

///|
/// ← (→ ⟳ where there is the room) and the address bar; narrow, the tabs' button after it.
fn browser_tools(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, close : () -> Unit, narrow : Bool) -> Unit {
  round_button(c, "browser-back", "arrow-left", @sf.t("web-pages.screen.back"), on_press=fn() {
    browser_act(s, "screen.back", @sf.t("web-pages.screen.backWhat"))
  })
  if !narrow {
    round_button(c, "browser-forward", "arrow-right", @sf.t("web-pages.screen.forward"), on_press=fn() {
      browser_act(s, "screen.forward", @sf.t("web-pages.screen.forwardWhat"))
    })
    round_button(c, "browser-reload", "refresh", @sf.t("web-pages.screen.reload"), on_press=fn() {
      browser_act(s, "screen.reload", @sf.t("web-pages.screen.reloadWhat"))
    })
  }
  address_bar(c, s, u)
  if narrow {
    let (tabs, _) = view_tabs(s)
    if !tabs.is_empty() {
      tabs_button(c, s, u, tabs.length(), close)
    }
  }
}

///|
/// What the viewer shows of a person's own page is the one their station's browser opens to next (@settings's).
fn browser_seen(s : ScreenSess) -> Unit {
  if s.user_tab() {
    @settings.browser_tab_seen(s.station, s.screen)
  }
}

///|
/// One tab of the row: its name (cut short), pressed the page shown; its × closes it.
fn view_tab(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, t : ViewTab, close : () -> Unit) -> Unit {
  let key = "view-tab/" + t.key
  let tid = c.id(key)
  let b = c.box(style=if t.close is Some(_) { browser_tab_box } else { browser_tab_box_kept }, selected=t.current, id=tid, fn() {
    c.text(t.words, style=browser_tab_words) |> ignore
    match t.close {
      Some(act) => {
        let xid = c.id(key + "/close")
        let x = c.box(style=browser_tab_close_box, id=xid, fn() {
          @sf.icon(c, "close", size=browser_tab_close_icon, color=c.color(Muted)) |> ignore
        })
        let closing = @sf.t("web-pages.screen.closeTab")
        c.semantics(x, Button, id=xid, label=closing, actions=[Activate])
        @sf.tip(c, key + "/close", xid, closing)
        c.on_press(xid, fn() { tab_do(s, u, act, close) })
      }
      None => ()
    }
  })
  c.semantics(b, Button, id=tid, label=t.words, pressed=t.current, actions=[Activate])
  @sf.tip(c, key, tid, if t.note != "" { t.note } else { t.words })
  c.on_press(tid, fn() { tab_do(s, u, t.press, close) })
}

///|
/// The address bar: the page's whole address while it is not written in, the words written in it gone to on Enter;
/// picked whole as it is pressed into, as a browser's is.
fn address_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let shown = address_shown(s)
  // not written in: a field holding the page's address as the station last said it, made anew as that changes (its
  // editor's key with it, so it shows it from its first frame)
  let field = match u.address {
    Some((was, f)) if was == shown || f.focused() => f
    _ => {
      // (its caret at its start: the address read from its site on, not scrolled to its end)
      let f = @ui.Field::new()
      f.set(shown, caret=0)
      u.address = Some((shown, f))
      u.address_made += 1
      f
    }
  }
  let key = "browser-address/" + s.screen + "/\{u.address_made}"
  c.box(style=browser_address_box, fn() {
    let focused = field.focused()
    // pressed into: all of it picked, to be written over
    if focused && !u.address_in {
      field.pick(0, field.text().length())
    }
    u.address_in = focused
    if u.address_asked {
      u.address_asked = false
      field.focus()
    }
    @sf.input(c, key, placeholder=@sf.t("web-pages.screen.addressHint"), field~, small=true, on_submit=fn(words) {
      let go = words.trim().to_owned()
      if go == "" {
        return
      }
      field.let_go()
      // (the station's address again once it says it, not the words given up)
      u.address = None
      let p : Map[String, Json] = {
        "station": Json::string(s.station),
        "screen": Json::string(s.screen),
        "url": Json::string(go),
      }
      (s.src.call)("screen.openUrl", Json::object(p), screen_act(c, @sf.t("web-pages.screen.goUrlWhat")))
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where the bar is narrow: the view's tabs folded into one button counting them; pressed, they are listed in a panel
/// (each pressed shown) with 新标签页 at its head and, a person's page shown, 关闭此标签页 at its foot.
fn tabs_button(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, count : Int, close : () -> Unit) -> Unit {
  let key = "view-tabs"
  let id = c.id(key)
  let label = @sf.t(if s.user_tab() { "web-pages.screen.tabs" } else { "web-pages.screen.windows" })
  let b = c.box(style=browser_count_box, id~, fn() {
    c.box(style=browser_count_square, fn() { c.text("\{count}", style=browser_count_words) |> ignore }) |> ignore
  })
  c.semantics(b, Button, id~, label=label + " \{count}", actions=[Activate])
  @sf.tip(c, key, id, label)
  let open = fn() {
    screen_panel_toggle(u, "tabs", fn() {
      @sf.panel_nodes(label, fn(v, done) { tabs_node(v, s, u, done, close) }, from=Of(id), side=screen_panel_side(), focus=false)
    })
  }
  c.on_press(id, open)
  // (asked from elsewhere, a fixture's: opened as it is seen)
  if u.asked_panel == "tabs" {
    u.asked_panel = ""
    open()
  }
}

///|
/// The tabs' panel (tabs_button's): 新标签页 where a tab is added, then each tab, the one shown ticked; 关闭此标签页 under
/// them on a person's page.
fn tabs_node(v : @view.View, s : ScreenSess, u : ScreenUi, done : () -> Unit, close : () -> Unit) -> Unit {
  // (made again as the view's state or the station's tabs change)
  let tabs = fn() {
    s.said.get() |> ignore
    view_tabs(s)
  }
  @sf.panel_group_node(v, fn() { "" }, fn(g) {
    g.show(fn() { tabs().1 }, fn(n) {
      @sf.panel_row_node(
        n,
        fn() { @sf.t("web-pages.screen.newTab") },
        fn() {
          done()
          tab_do(s, u, Add, close)
        },
        icon=fn() { "plus" },
      )
    })
    // (each by what it shows: its key, words, note and whether it is the one shown; what pressing it does looked up as
    // it is pressed)
    g.each(fn() { tabs().0.map(fn(t) { (t.key, t.words, t.note, t.current) }) }, fn(t) { t.0 }, fn(row, t) {
      @sf.panel_row_node(
        row,
        fn() { t.get().1 },
        fn() {
          done()
          let key = t.untracked().0
          match @signals.untracked(tabs).0.search_by(fn(x) { x.key == key }) {
            Some(i) => tab_do(s, u, @signals.untracked(tabs).0[i].press, close)
            None => ()
          }
        },
        icon=fn() { if s.user_tab() { "web" } else if t.get().0 == "screen" { "monitor" } else { "square" } },
        note=fn() { if s.user_tab() { t.get().2 } else { "" } },
        end=if t.untracked().3 { "check" } else { "" },
      )
    })
  })
  v.show(fn() { s.said.get() |> ignore; s.user_tab() }, fn(f) {
    @sf.panel_group_node(f, fn() { "" }, fn(g) {
      @sf.panel_row_node(
        g,
        fn() { @sf.t("web-pages.screen.closeTabFull") },
        fn() {
          done()
          close_tab(s, u, s.screen, user_tabs_of(s), close)
        },
        icon=fn() { "close" },
        danger=true,
      )
    })
  })
}

///|
/// A new tab (＋, ⌘T): there at once on its blank page, its address bar taking the keys, while the station makes it.
fn new_tab_from(s : ScreenSess, u : ScreenUi) -> Unit {
  let listed = user_tabs_of(s).map(fn(t) { text(Some(t), "id") })
  let next = @settings.new_browser_tab(s.src.call, s.station, listed, failed_said(@sf.t("web-pages.screen.openBrowserWhat")))
  screen_ui(screen_key(s.station, next)).address_asked = true
  switch_screen_to(s, u, next, "", false)
}

///|
/// Tab `id` closed (its ×, ⌘W): where it is the one shown, the one after it is shown in its place (else the one
/// before; none left, the viewer closes), as a browser does.
fn close_tab(s : ScreenSess, u : ScreenUi, id : String, tabs : Array[Json], close : () -> Unit) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(s.station), "screen": Json::string(id) }
  (s.src.call)("screen.close", Json::object(p), failed_said(@sf.t("web-pages.screen.closeTabWhat")))
  if id != s.screen {
    return
  }
  let at = tabs.search_by(fn(t) { text(Some(t), "id") == id }).unwrap_or(-1)
  let rest = tabs.filter(fn(t) { text(Some(t), "id") != id })
  if rest.is_empty() {
    close()
    return
  }
  let next = rest[if at >= 0 && at < rest.length() { at } else { rest.length() - 1 }]
  switch_screen_to(s, u, text(Some(next), "id"), text(Some(next), "title"), false)
}

///|
/// ← → ⟳: asked of the station for the tab shown, what failed said.
fn browser_act(s : ScreenSess, call : String, what : String) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  (s.src.call)(call, Json::object(p), failed_said(what))
}

///|
/// A browser's own keys (⌘ or Ctrl with L, T, W, R, [ and ]) on a tab of the station's browser: what they do here,
/// their key-down; true where `code` is one of them (its keys not sent to the page).
fn browser_key(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, code : String, mods : Int, down : Bool) -> Bool {
  if !browser_shown(s) || (mods & (mod_meta | mod_ctrl)) == 0 || (mods & mod_alt) != 0 {
    return false
  }
  let act : String? = match code {
    "KeyL" | "KeyR" | "BracketLeft" | "BracketRight" => Some(code)
    "KeyT" | "KeyW" if s.user_tab() => Some(code)
    _ => None
  }
  match act {
    Some(key) => {
      // (done once the frame's builds are over, as a key's press is: what it opens is another page)
      if down {
        u.browser_keys += 1
        c.tell("browser-key/" + s.view + "/\{u.browser_keys}", fn() { browser_key_do(s, u, key) })
      }
      true
    }
    None => false
  }
}

///|
/// What a browser's key (browser_key's) does, once the frame's builds are over.
fn browser_key_do(s : ScreenSess, u : ScreenUi, code : String) -> Unit {
  match code {
    "KeyL" => u.address_asked = true
    "KeyR" => browser_act(s, "screen.reload", @sf.t("web-pages.screen.reloadWhat"))
    "BracketLeft" => browser_act(s, "screen.back", @sf.t("web-pages.screen.backWhat"))
    "BracketRight" => browser_act(s, "screen.forward", @sf.t("web-pages.screen.forwardWhat"))
    "KeyT" => tab_do(s, u, Add, u.close_page)
    "KeyW" => tab_do(s, u, Close(s.screen), u.close_page)
    _ => ()
  }
}

///|
/// What failed of a call said as a toast (`what` it was meant to do, and why): screen_act's, for what is done outside a
/// build (tab_do's, a key's) where no build's Ctx is to hand.
fn failed_said(what : String) -> (Result[Json, Json]) -> Unit {
  fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => @sfbase.toast_later(@sf.t("android-misc.act.failed", args=[("what", what), ("error", error_words(e))]))
    }
  }
}
