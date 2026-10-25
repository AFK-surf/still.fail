// ⌘K (the web's Switcher.tsx ChatSwitcher and Finder, Switcher.css.ts): a panel high on the window over a scrim, the
// search on top (搜索全部内容和操作), under it what a few words find in the workspace (the core's `search`, docs/search.md:
// its chats, the messages that have them, what every station finds besides, each kind under its heading, a few of each;
// 查看更多 that kind alone, 全部结果 or Esc back to all) and what can be done here by its name (the core's
// `commands.find` of what the frame offers now). With nothing typed, the latest chats, then what can be done. ↑ / ↓
// choose, Enter or a press opens; Esc (in one kind's list: back to all of them) or a press outside closes it.

///|
/// Whether ⌘K is open (what it shows and finds is sfpages' finder: switcher.mbt).
// kept across runs: put back by switcher_reset (reset)
let switching : Ref[Bool] = Ref(false)

///|
fn switcher_reset() -> Unit {
  switching.val = false
}

///|
/// What one opening of it leaves behind, put back as it closes.
fn switcher_closed() -> Unit {
  @sfpages.finder_cleared()
}

///|
/// Whether ⌘K is open.
pub fn switcher_open() -> Bool {
  switching.val
}

///|
/// ⌘K pressed (the keymap's chat.switch): open, empty; open already, closed.
pub fn switcher_toggle(c : @ui.Ctx) -> Unit {
  if switching.val {
    c.blur()
  }
  switching.val = !switching.val
  switcher_closed()
}

///|
/// Esc: in one kind's list, back to all of them; else closed (its field let go: the keyboard goes nowhere until another
/// is pressed). Whether it took it (open).
pub fn switcher_escape(c : @ui.Ctx) -> Bool {
  if !switching.val {
    return false
  }
  if !@sfpages.finder_back() {
    switching.val = false
    switcher_closed()
    c.blur()
  }
  true
}

///|
/// Opened with `words` typed (a made-up run's start).
pub fn switcher_open_with(words : String) -> Unit {
  switching.val = true
  @sfpages.finder_start(words)
}

///|
/// ⌘K over the page (ChatSwitcher): over a scrim, 14% down the window, 560 wide at most (32 short of the window), 480
/// high at most (72% of the window); its search, then sfpages' list of what is found and what can be done (finder_list),
/// the latest chats with nothing typed. Drawn each frame; nothing while closed.
pub fn switcher(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !switching.val {
    return
  }
  let offered = switcher_offered(c, src)
  let t = @sf.theme()
  let close = fn() {
    switching.val = false
    switcher_closed()
    c.blur()
  }
  let most = dmin(switcher_most_h, c.height * switcher_most_share) - switcher_panel_rest
  let panel = c.id("switcher")
  // mbui's layer over the page (modal: its scrim takes the presses outside, Tab stays in it; Esc, back or a press
  // outside dismiss it), the panel 14% down the window in its middle
  let o = c.overlay("switcher-layer", modal=true, scrim=t.p.overlay, initial_focus=0, fn() {
    // (32 short of the window at most: room round it however narrow the frame is)
    let room = dmin(switcher_w, c.width - switcher_side - switcher_side)
    let i = c.box(
      style=switcher_panel.then(@ui.style(max_w=Fixed(room))),
      bg=@sf.panel_ground(),
      shadow=@sf.dialog_shadow,
      shadow_y=@sf.dialog_shadow_y,
      shadow_color=t.p.shadow,
      id=panel,
      fn() {
        c.box(style=switcher_search_box, fn() {
          let res = c.editor(
            "switcher/field",
            placeholder=@sf.t("web-main.switcher.search"),
            font_size=switcher_search_size,
            line=switcher_search_line,
            max_lines=1,
            plain=true,
            color=t.p.text,
            placeholder_color=t.p.subtle,
            caret_color=t.p.accent,
            enter_sends=true,
            field=@sfpages.finder_field(),
          )
          // (modal, its search the only field: it has the keys while it is open, the composer's given up as it opens)
          if !res.focused {
            c.focus_editor("switcher/field")
          }
          match res.submitted {
            // Enter: the line chosen opened
            Some(typed) => {
              @sfpages.finder_typed(typed)
              @sfpages.finder_enter(close)
            }
            None => @sfpages.finder_typed(res.text)
          }
        })
        |> ignore
        if switching.val {
          @sfpages.finder_list(c, src, w, offered, close, idle_chats=true, most~, width=room - 2.0 * switcher_edge)
        }
      },
    )
    c.place_by_size(i, fn(pw, _) { ((c.width - pw) / 2.0, c.height * switcher_top_share) })
  })
  if o.dismissed is Some(_) {
    close()
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// The panel (Switcher.css.ts switcher): 14% down the window, 560 wide at most and 32 short of the window, 480 high at
/// most and 72% of the window; 12 in (EDGE), its corner from a row's (a pill 38 high 12 in: pillInner), a small panel's
/// ground and line, a deep shadow (0 24px 64px); what its search takes of it (76).
let switcher_top_share : Double = 0.14

///|
let switcher_most_h : Double = 480.0

///|
let switcher_most_share : Double = 0.72

///|
let switcher_edge : Double = 12.0

///|
let switcher_row_h : Double = 38.0

///|
// kept across runs: a value (no field of it changes)
let switcher_surface : @sf.Surface = @sf.surface(switcher_edge, @sf.pill_inner(switcher_edge, switcher_row_h))

///|
// kept across runs: a value (no field of it changes)
let switcher_panel : @ui.Style = switcher_surface
  .style()
  .then(
    @ui.style(w=Full, max_w=Fixed(switcher_w), border=B1, border_color=Line, clip=true),
  )

///|
let switcher_w : Double = 560.0

///|
/// What is left of the window either side of it at least (the web's calc(100vw - 32px)).
let switcher_side : Double = 16.0

///|
/// What the panel holds besides its list: its search's 48, its 12 in at its top and foot, 4 over the list.
let switcher_panel_rest : Double = 76.0

///|
/// The search (Switcher.css.ts search): 48 high, 12 in, the words a title's (16), the placeholder subtle.
// kept across runs: a value (no field of it changes)
let switcher_search_box : @ui.Style = @ui.css("row w=Full h=S12 px=S3 align=ACenter")

///|
let switcher_search_size : Double = 16.0

///|
let switcher_search_line : Double = 24.0

///|
///|
/// What ⌘K offers of what the frame can do now (Switcher.tsx offered: the keys' actions it answers, and its own): the
/// open chat's (find, its services), the app's (a new chat, the sidebar, settings, the shortcuts), settings' pages (only
/// found by typing). The core names the keys' actions and finds what was typed among them (sfdesk/switcher.mbt).
fn switcher_offered(c : @ui.Ctx, src : Source) -> Array[@sfpages.Offered] {
  // an action's first keys as shown (as kept on this device: settings' 快捷键)
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  // the open chat's (ChatPage.tsx chat.find, chat.jobs)
  let all : Array[@sfpages.Offered] = match app.nav.top() {
    Chat(r) =>
      [
        {
          id: "chat.find",
          group: "",
          label: "",
          words: "",
          icon: "search",
          keys: keys("chat.find"),
          typed: false,
          run: fn() { chat_find_open(c, r) },
        },
        {
          id: "chat.jobs",
          group: "",
          label: "",
          words: "",
          icon: "web",
          keys: keys("chat.jobs"),
          typed: false,
          run: fn() { open_jobs_pop() },
        },
      ]
    _ => []
  }
  all.push({
    id: "chat.new",
    group: "",
    label: "",
    words: "",
    icon: "compose",
    keys: keys("chat.new"),
    typed: false,
    run: fn() { new_chat() },
  })
  // (the wide frame's alone)
  if is_wide(c) { all.push({
    id: "sidebar.toggle",
    group: "",
    label: "",
    words: "",
    icon: "panel-open",
    keys: keys("sidebar.toggle"),
    typed: false,
    run: fn() { sidebar_toggle() },
  })
  }
  all.push({
    id: "settings",
    group: "",
    label: "",
    words: "",
    icon: "settings",
    keys: keys("settings"),
    typed: false,
    run: fn() { open_settings() },
  })
  all.push({
    id: "shortcuts",
    group: "",
    label: "",
    words: "",
    icon: "command",
    keys: keys("shortcuts"),
    typed: false,
    run: fn() { wide.keys_open = true },
  })
  let routes : Array[(String, @settings.Route, String)] = [
    ("appearance", @settings.Route::Appearance, @sf.t("web-pages.settings.nav.appearance")),
    ("notifications", @settings.Route::Notifications, @sf.t("web-pages.settings.nav.notifications")),
    ("permissions", @settings.Route::Permissions, @sf.t("web-pages.settings.nav.permissions")),
    ("archive", @settings.Route::Archiving, @sf.t("web-pages.archiving.title")),
    ("memory", @settings.Route::Memories, @sf.t("web-pages.settings.nav.memory")),
    ("security", @settings.Route::Security, @sf.t("web-pages.security.title")),
    ("vault", @settings.Route::Vault, @sf.t("web-pages.vault.title")),
    ("changelog", @settings.Route::Changelog, @sf.t("web-pages.settings.nav.changelog")),
    ("about", @settings.Route::About, @sf.t("web-pages.settings.nav.about")),
  ]
  for p in routes {
    let (key, route, label) = p
    all.push({
      id: "settings." + key,
      group: "settings",
      label,
      words: "",
      icon: "settings",
      keys: "",
      typed: true,
      run: fn() {
        open_settings_at(route)
      },
    })
  }
  all
}
