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
/// How ⌘K's panel comes (Switcher.css.ts switcher: popKeyframes from its top, 140 ms on the ease-out).
// kept across runs: a value (no field of it changes)
let switcher_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, oy=0.0, spec=@motion.tween(@kit.pop_ms, ease=Out), ground_first=true)

///|
/// How ⌘K goes: at once, as the web's (unmounted).
// kept across runs: a value (no field of it changes)
let gone_at_once : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.Snap(0.0))

///|
/// ⌘K over the page (ChatSwitcher): over a scrim, 14% down the window, 560 wide at most (32 short of the window), 480
/// high at most (72% of the window); its search, then sfpages' list of what is found and what can be done (finder_list),
/// the latest chats with nothing typed. Drawn each frame; nothing while closed. It comes in as the web's (Switcher.css.ts):
/// its scrim faded in over 120 ms, the panel grown out of 97% from its top and faded in over 140 ms; it goes at once.
pub fn switcher(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // (asked closed too: opened again, it comes in again)
  let shows = @motion.presence(c, "\u{2}switcher", switching.val, initial=true, enter=switcher_in, exit=gone_at_once)
  let ground = @motion.presence(c, "\u{2}switcher-ground", switching.val, initial=true, enter=@kit.tip_in, exit=gone_at_once)
  if !switching.val {
    return
  }
  let offered = switcher_offered(c, src, w)
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
  let scrim = @sf.alpha(t.p.overlay, ground.map(fn(l) { l.alpha }).unwrap_or(1.0))
  let o = c.overlay("switcher-layer", modal=true, scrim~, initial_focus=0, fn() {
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
          // (its lines as wide as the panel inside its edge: what they go by)
          c.sized(room - 2.0 * switcher_edge, c.height, fn() {
            @sfpages.finder_list(c, src, w, offered, close, idle_chats=true, most~)
          })
        }
      },
    )
    c.place_by_size(i, fn(pw, _) { ((c.width - pw) / 2.0, c.height * switcher_top_share) })
    match shows {
      Some(l) => c.look(i, l)
      None => ()
    }
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
/// One of the keys' actions as ⌘K offers it (the core names it): its icon, what it does; for update.app and
/// update.station, the version it goes to and the station updated. Its keys are put in as it is offered.
fn action_offered(id : String, icon : String, version? : String = "", station? : String = "", run : () -> Unit) -> @sfpages.Offered {
  { id, group: "", label: "", words: "", typed: false, version, station, icon, keys: "", run }
}

///|
/// What ⌘K offers of what the frame can do now (Switcher.tsx offered: the keys' actions it answers, and its own): the
/// open chat's (find, its services, into the archive, its agents' history, its agents stopped, a file into its draft,
/// relayed, its station updated: as its keys and its bar's offer them now), the app's newer build or looking for one, the app's (a new
/// chat, the sidebar, settings, the shortcuts), settings' pages (only found by typing). The core names the keys'
/// actions and finds what was typed among them (sfdesk/switcher.mbt).
fn switcher_offered(c : @ui.Ctx, src : Source, w : Workspace) -> Array[@sfpages.Offered] {
  // an action's first keys as shown (as kept on this device: settings' 快捷键)
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  let all : Array[@sfpages.Offered] = []
  let offer = fn(o : @sfpages.Offered) { all.push({ ..o, keys: keys(o.id) }) }
  // the open chat's (ChatPage.tsx chat.find, chat.jobs, chat.archive, chat.history, chat.stop, composer.file; Relay.tsx
  // chat.relay; StationUpdate.tsx update.station)
  match app.nav.top() {
    Chat(r) => {
      let view = view_of_chat(src, r).0
      if view is Some({ thread: Some(_), .. }) {
        offer(action_offered("chat.find", "search", fn() { chat_find_open(c, r) }))
      }
      offer(action_offered("chat.jobs", "web", fn() { open_jobs_pop() }))
      match view {
        Some(v) => {
          let chat = (src.topic)("chat", chat_params(r)).value
          let open = !v.archived && !v.offline
          if open {
            offer(action_offered("chat.archive", "archive", fn() { c.tell("chat/archive", fn() { archive_asked(src, w, r, v, chat) }) }))
          }
          if v.agents.length() > 0 {
            offer(action_offered("chat.history", "thread", fn() { c.tell("chat/history", fn() { history_toggle(src, r, v) }) }))
          }
          if agents_working(v) {
            offer(action_offered("chat.stop", "stop", fn() { stop_agents(src, r, v) }))
          }
          if open {
            offer(action_offered("composer.file", "file", fn() { @sfpages.pick_files(writing(src, r.station + ":" + r.session)) }))
          }
          match v.thread {
            Some(th) if open && v.agents.length() > 0 =>
              offer(action_offered("chat.relay", "arrow-up-right", fn() { @sfpages.open_relay(src, r, th, from=Unanchored) }))
            _ => ()
          }
          let notice = v.station_update
          let on = [("station", r.station), ("id", "station")]
          if flag(notice, "canUpdate") && !core_doing(src, ["software.update"], on) {
            offer(action_offered("update.station", "download", station=text(notice, "station"), fn() {
              act(src, @sf.t("web-main.stationUpdate.updateAction"), "", "software.update", {
                "station": Json::string(r.station),
                "id": "station",
              })
            }))
          }
        }
        None => ()
      }
    }
    _ => ()
  }
  // the app's newer build, as 更新 over the sidebar offers it (brand.mbt)
  if update.available.get() is Some(_) && !update_under_way() {
    offer(action_offered("update.app", "download", version=text(update.available.get(), "versionName"), fn() { update_install(src) }))
  }
  // looking for a newer build now, as the menu's 检查更新… does (its dialog: what it finds, or that there is none); found
  // only by typing (the core's), wherever the app asks still.fail cloud for its builds
  if update.source is Some(_) && !update_under_way() {
    offer(action_offered("update.check", "refresh", fn() { @sfbase.update_from_menu(src) }))
  }
  offer(action_offered("chat.new", "compose", fn() { new_chat() }))
  // (the wide frame's alone)
  if is_wide(c) {
    offer(action_offered("sidebar.toggle", "panel-open", fn() { sidebar_toggle() }))
  }
  offer(action_offered("settings", "settings", fn() { open_settings() }))
  offer(action_offered("shortcuts", "command", fn() { wide.keys_open.set(true) }))
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
      version: "",
      station: "",
      run: fn() {
        open_settings_at(route)
      },
    })
  }
  all
}
