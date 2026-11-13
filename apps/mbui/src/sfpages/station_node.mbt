// A station's own page (station_page.mbt's) made once as nodes of the window's tree, laid out by the width its frame
// gives it (page_node): its head of its own (its mark and name, which its managers change where they are, how it is and
// what it is, what is wrong with it, trying it again while away, 启动 where it is this machine's and stopped, its ⋯),
// then its parts one at a time as its choice says: how it is and what runs on it, its 进程, what it is let do and set
// to, its software and the machine. Everything said is the core's, each part bound to what it says now: the machine's
// figures (station_cards.mbt), its 进程 (resources_node.mbt), a login's card under way (login_card.mbt's node). The
// old view of the page (station_page) is what the rail's 'stations' place (sfdesk places.mbt) and a chat's side panel
// (station_tabs.mbt) still draw: both old views themselves, which cannot hold a part made once.

///|
/// Station `address`'s page (StationSettings, StationScreen) made once in node `v`, as wide as `width` gives it, in the
/// frame it is given: while the stations are read, or where it is gone, a made-up one's in its bones (station_waiting's);
/// made again as the viewer comes to manage it or not. `stint`: the page's time on top (what a picture put up for its
/// mark is asked for on).
pub fn station_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  stint? : () -> Int = fn() { 0 },
) -> Unit {
  // (that station alone, whole: none while the stations are not known, null where the workspace has no such station)
  let listed = fn() {
    match @settings.station_read(core, here(), address).value {
      Some(Object(_)) => Some(true)
      Some(_) => Some(false)
      None => None
    }
  }
  let manager = fn() {
    let r = role_of(core, here())
    r == "owner" || r == "admin"
  }
  // (what is said of what the pointer rests on: the frame's, else drawn over the page in the page's own node, each tip
  // its holder over all of it there: history_node's)
  let tips = match tips {
    Some(t) => t
    None => @sf.TipLayer::new(fn() { Some(v) })
  }
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (one that only runs tasks is no station this device is linked to: its own page, station_rig.mbt)
  let rig = fn() { @settings.rig_at(core, here(), address) }
  v.pick(fn() { (if rig() is Some(_) { None } else { listed() }, listed() == Some(true) && manager(), rig() is Some(_)) }, fn(p, k) {
    p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    if k.2 {
      rig_station_node(p, core, here, address, rig, on_back, frame, said, width, tips)
      return
    }
    match k.0 {
      Some(true) =>
        station_view_node(p, core, here, fn() { @settings.station_of(core, here(), address) }, k.1, None, on_back, frame, said, width, tips, stint)
      // (while they are read: a made-up one's in its bones, waiting on them; removed, or a link from before, the same,
      // waiting on nothing)
      found => {
        let wait = if found is None { @sf.t("common.readingStations") } else { "" }
        let sample = station_sample()
        station_view_node(p, core.quiet(), here, fn() { Some(sample) }, false, Some(wait), on_back, frame, said, width, tips, stint)
      }
    }
  })
}

///|
/// Station `s`'s page (station_view's): its head, then its parts one at a time. `bones`: all of it in its bones,
/// waiting on what it says (station_waiting's: its title the frame's).
fn station_view_node(
  p : @view.View,
  core : Core,
  here : () -> Here,
  s : () -> Json?,
  manager : Bool,
  bones : String?,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  said : ((@sf.PageSaid) -> Unit)?,
  width : (() -> Double)?,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let address = text(@signals.untracked(s), "station")
  // (what the host says of the station here, as it said it last: a signal of that input, read again every few seconds
  // from when it is made, while this page is this machine's station's: it starts, stops and updates on its own time)
  let host : @signals.Signal[String] = @signals.signal(
    if address == this_machine() { @hostapi.app_said("local_station") } else { "" },
    same=fn(a, b) { a == b },
  )
  if bones is None && address == this_machine() {
    fn again(at : Double) -> Unit {
      p.at_moment(at + @settings.local_read_ms, later=true, fn() {
        host.set(@hostapi.app_said("local_station"))
        again(at + @settings.local_read_ms)
      })
      |> ignore
    }
    again(p.logic_at())
  }
  // (the part shown, by station: the settings' own, which a login's card also moves to 设置)
  let part = fn() {
    match @settings.station_parts.get(address) {
      Some(p) if station_part_names.contains(p) => p
      _ => "overview"
    }
  }
  let blocks = fn() {
    let out = ["parts"]
    out.append(
      match part() {
        "processes" => ["processes"]
        "settings" => station_settings_keys(s(), manager)
        "machine" => ["software", "device"]
        _ => station_overview_keys(core, s())
      },
    )
    out
  }
  let block = fn(b : @view.View, key : String) {
    match key {
      "parts" => station_parts_node(b, address)
      "resources" => station_resources_node(b, core, here, s)
      "userPages" => station_user_pages_node(b, core, here, s)
      "agentPages" => station_agent_pages_node(b, core, here, s)
      "screens" => station_screens_node(b, core, here, s)
      "profiles" => station_profiles_node(b, core, here, s)
      "connects" => station_connects_node(b, core, s)
      "drive" => station_drive_node(b, s)
      // its devices, and adding one: any member but one who only reads (a whole station's are every chat's)
      "devices" => {
        let id = text(@signals.untracked(s), "id")
        @settings.station_devices_node(b, core, here, id, false, fn() {
          let role = text(workspace_view(core, here()).value, "role")
          role != "" && role != "viewer"
        })
      }
      "more" => station_more_node(b, core, address)
      "processes" => station_processes_node(b, core, here, s)
      "offline" => @sf.group_node(b, fn(g) { said_row_node(g, fn() { @sf.t("web-pages.stations.settingsOffline") }) })
      "logins" => station_logins_node(b, core, address, fn() { flag(s(), "online") })
      "permissions" => station_permissions_node(b, core, address, fn() { field(field(s(), "overview"), "permissions") })
      "env" => station_env_node(b, core, address, fn() { field(field(s(), "overview"), "agentEnv") }, manager)
      "search" => station_search_node(b, core, address, fn() { field(field(s(), "overview"), "search") }, manager)
      "context" => station_context_node(b, core, address, fn() { field(field(s(), "overview"), "context") }, manager)
      "diagnostics" =>
        station_diagnostics_node(b, core, address, fn() { field(field(s(), "overview"), "diagnostics") }, manager)
      "elevation" => station_elevation_node(b, core, address, fn() { field(field(s(), "overview"), "elevation") })
      "workspaces" => station_workspaces_node(b, core, address)
      "network" => station_network_node(b, core, address, fn() { field(field(s(), "overview"), "network") }, manager)
      "copies" => station_copies_node(b, core, address, fn() { field(field(s(), "overview"), "copies") })
      "software" => station_software_node(b, core, s, manager, tips)
      "device" => station_device_node(b, s)
      _ => ()
    }
  }
  @sf.page_node(
    p,
    // (its head says its name: what it says of itself to a bar that names it, what it is of)
    fn() { @sf.t("android-misc.bar.place.stations") },
    blocks,
    fn(b, key) {
      match bones {
        // (in its bones, breathing: the first waiting on what it says, to a screen reader)
        Some(wait) =>
          @sf.waiting_node(b, fn(w) { block(w, key) }, note=fn() { { reading: true, text: if key == "parts" { wait } else { "" }, failing: [] } })
        None => block(b, key)
      }
    },
    on_back~,
    frame~,
    said?,
    width?,
    tips~,
    // its head says its name: no title over it (StationSettings: Head, then Body)
    head=fn(h) { station_head_node(h, core, here, s, host, manager, bones is Some(_), stint, tips) },
    // (what its head does, on back's line over it where the page puts it there: own_head's back_line)
    actions=fn(a) {
      if bones is None {
        station_actions_node(a, core, here, s, fn() { local_stopped_in(address, host.get()) }, manager, tips)
      }
    },
  )
}

///|
/// The keys of its overview's parts (station_overview's), those it has now: what is left of the machine while it is up,
/// its screens, profiles, connects and folders, and what else of it has a page of its own.
fn station_overview_keys(core : Core, s : Json?) -> Array[String] {
  let address = text(s, "station")
  let o = field(s, "overview")
  let out = []
  if flag(s, "online") && field(s, "host") is Some(Object(_)) {
    out.push("resources")
  }
  match (core.topic)("screens", { "station": str(address) }).get().value {
    Some(Object(_)) as v => {
      let all = items(v, "screens")
      if all.iter().any(fn(sc) { is_user_screen(Some(sc)) }) || (flag(v, "browser") && flag(v, "control")) {
        out.push("userPages")
      }
      if all.iter().any(fn(sc) { is_agent_screen(Some(sc)) }) {
        out.push("agentPages")
      }
      if all.iter().any(fn(sc) { !is_browser_screen(Some(sc)) }) || (all.is_empty() && text(v, "note") != "") {
        out.push("screens")
      }
    }
    _ => ()
  }
  if items(s, "profileGroups").length() > 0 {
    out.push("profiles")
  }
  if items(o, "connects").length() > 0 {
    out.push("connects")
  }
  if field(o, "drive") is Some(Object(_)) {
    out.push("drive")
  }
  // its devices while it is up (one is added there)
  if flag(s, "online") {
    out.push("devices")
  }
  out.push("more")
  out
}

///|
/// The keys of its 设置's parts (station_settings'), those it has now. Away, none of what only it can change, a line
/// saying so in their place; what it has logged in and the workspaces it is in stay.
fn station_settings_keys(s : Json?, manager : Bool) -> Array[String] {
  let o = field(s, "overview")
  if !flag(s, "online") {
    return if manager { ["offline", "logins", "workspaces"] } else { ["offline", "logins"] }
  }
  let out = []
  if field(o, "permissions") is Some(Object(_)) {
    out.push("permissions")
  }
  out.push("logins")
  if field(o, "agentEnv") is Some(Array(_)) {
    out.push("env")
  }
  match field(o, "search") {
    Some(Object(_)) as search if text(search, "files") == "spotlight" => out.push("search")
    _ => ()
  }
  for k in ["context", "diagnostics", "elevation"] {
    if field(o, k) is Some(Object(_)) {
      out.push(k)
    }
  }
  if manager {
    out.push("workspaces")
  }
  if field(o, "copies") is Some(Object(_)) {
    out.push("copies")
  }
  if field(o, "network") is Some(Object(_)) {
    out.push("network")
  }
  out
}

///|
/// Its head (Head, station_head's): its mark (picked by its managers), its name (renamed by them), how it is (its dot
/// before it), what the machine is, its version, where it is from; what is wrong with it under them; at its end trying
/// it again while away or silent, 启动 where it is this machine's and stopped here, its ⋯. This machine's as the host
/// says it, asked again every few seconds from when it is made (it starts, stops and updates on its own time: a
/// moment said each time). `bones`: all of it in its bones while what it says is read the first time.
fn station_head_node(
  h : @view.View,
  core : Core,
  here : () -> Here,
  s : () -> Json?,
  host : @signals.Signal[String],
  manager : Bool,
  bones : Bool,
  stint : () -> Int,
  tips : @sf.TipLayer,
) -> Unit {
  if bones {
    @sf.waiting_node(h, fn(w) { station_head_node(w, core, here, s, host, manager, false, stint, tips) })
    return
  }
  let address = text(@signals.untracked(s), "station")
  let stopped = fn() { local_stopped_in(address, host.get()) }
  let online = fn() { flag(s(), "online") }
  let dot = fn() { if online() { "online" } else { "offline" } }
  let state = fn() {
    match stopped() {
      Some(_) as st => (local_stopped_words(st), text(st, "doing") != "")
      None => (text(s(), "stateText"), flag(s(), "stateBusy"))
    }
  }
  let name = fn() { text(s(), "name") }
  @sf.own_head_node(
    h,
    fn(m, _side) {
      m.pick(fn() { @sf.has_station_mark(text(s(), "emoji"), text(s(), "icon")) }, fn(k, has) {
        if has {
          @sf.station_mark_node(k, fn() { text(s(), "emoji") }, fn() { text(s(), "icon") }, st_mark_glyph, fn() {
            @sf.theme().p.text
          }, stint)
        } else {
          @sf.words_node(k, fn() {
            match name().iter().next() {
              Some(ch) => ch.to_string().to_upper()
              None => "?"
            }
          }, fn() { st_mark_letter })
          |> ignore
        }
      })
      // its mark: its managers pick it, by what it is called (图标)
      if manager {
        @sf.presses_node(m, fn() {
          let now = @signals.untracked(s)
          let workspace = @signals.untracked(here)
          guard flag(now, "online") else { @settings.mark_offline(core, text(now, "name")) }
          open_mark_pick(core, text(now, "name"), text(now, "emoji"), text(now, "icon"), @sf.t("android-settings.station.emojiWhat"), fn(
            emoji,
            icon,
            done,
          ) {
            (core.call)(
              "workspace.renameStation",
              obj([("workspace", str(workspace.workspace)), ("station", str(text(now, "id"))), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(workspace.sub))]),
              done,
            )
          })
        })
        m.says(By(fn() { Some(@view.said(Button, label=@sf.t("android-settings.station.emoji"))) })) |> ignore
      }
    },
    name,
    rename?=if manager { Some(fn() { station_rename(core, @signals.untracked(here), @signals.untracked(s)) }) } else { None },
    rename_label=fn() { @sf.t("web-pages.settings.stations.rename") },
    lines=fn() {
      let facts = [text(field(s(), "host"), "identity")]
      if text(s(), "version") != "" {
        facts.push("Station " + text(s(), "version"))
      }
      facts.push(joined_text(s()))
      [join(facts, " · ")]
    },
    // its dot before what it says of how it is (reconnecting …; this machine's, how it stands here: 已停止, 正在更新),
    // else before what the machine is
    dot=fn() { if state().0 == "" { dot() } else { "" } },
    state=fn(k) {
      @sf.state_dot_node(k, fn() { if state().1 && stopped() is Some(_) { "busy" } else { dot() } })
      @sf.words_node(k, fn() { state().0 }, fn() { if state().1 { st_fact_busy } else { st_fact } }) |> ignore
    },
    state_shown=fn() { state().0 != "" },
    warnings=fn() {
      let out = items(s(), "problems").map(fn(p) { (text(Some(p), "text"), text(Some(p), "level") == "red") })
      match local_failed_words(stopped()) {
        "" => ()
        words => out.push((words, true))
      }
      out
    },
    actions=fn(a) { station_actions_node(a, core, here, s, stopped, manager, tips) },
  )
}

///|
/// What its head does at its end (station_head's): trying it again while away or silent, 启动 where it is this
/// machine's and stopped here (`stopped`), how its renaming goes and its ⋯ for its managers.
fn station_actions_node(
  a : @view.View,
  core : Core,
  here : () -> Here,
  s : () -> Json?,
  stopped : () -> Json?,
  manager : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let online = fn() { flag(s(), "online") }
  let id = fn() { text(s(), "id") }
  let silent = fn() { items(s(), "problems").iter().any(fn(p) { text(Some(p), "key") == "silent" }) }
  a.pick(fn() { if stopped() is Some(_) { 1 } else if !online() || silent() { 2 } else { 0 } }, fn(e, end) {
    match end {
      // this machine's, not running here: started from here, no try at reaching it again (station_start's)
      1 => {
        let working = fn() { text(stopped(), "doing") != "" }
        @sf.button_node(e, fn() { @sf.t("web-pages.localStation.start") }, fn() { local_start(core, @signals.untracked(stopped)) }, tone=Ghost, busy=working, disabled=working)
        |> ignore
      }
      // tried again now (station_retry's: the core's `client.wake`, every station at once)
      2 => {
        let trying = fn() { flag(field(s(), "link"), "retrying") || is_doing(core, ["client.wake"], []) }
        @sf.button_node(e, fn() { @sf.t("common.retry") }, fn() {
          @settings.act(
            core,
            @sf.t("common.retry"),
            "client.wake",
            obj([("away", Json::number(0.0)), ("network", Json::boolean(true)), ("retry", Json::boolean(true))]),
          )
        }, tone=Ghost, busy=trying, disabled=trying)
        |> ignore
      }
      _ => ()
    }
  })
  if manager {
    let on = fn() { [("station", id())] }
    doing_mark_node(a, fn() { is_doing(core, ["workspace.renameStation", "workspace.removeStation"], on()) }, fn() {
      failed_of(core, ["workspace.renameStation", "workspace.removeStation"], on())
    }, tips~)
    // its ⋯ (station_menu's), beside it
    @sf.icon_action_opens_node(a, "more", fn() { @sf.t("common.more") }, fn(m) {
      let (x, y, w, h) = m.placed_window_now()
      @sf.menu(station_menu_items(core, @signals.untracked(here), @signals.untracked(s)), from=At(x, y, w, h), along=End)
    })
    |> ignore
  }
}

///|
/// The parts to pick from (Body's Segmented, station_parts_choice's).
fn station_parts_node(b : @view.View, address : String) -> Unit {
  @sf.page_choice_node(
    b,
    fn() { station_part_names.map(fn(p) { @sf.t("web-pages.stations.page.part." + p) }) },
    fn() {
      match @settings.station_parts.get(address) {
        Some(p) => station_part_names.search(p).unwrap_or(0)
        None => 0
      }
    },
    fn(i) { @settings.station_parts[address] = station_part_names[i] },
  )
}

///|
/// A section of the page (st_section's), titled `title`, `count` beside its title where it is one or more (wide),
/// `note` what it holds said by it, `ends` what it does at its title's end.
fn st_section_node(
  b : @view.View,
  title : () -> String,
  body : (@view.View) -> Unit,
  count? : () -> Int = fn() { 0 },
  note? : () -> String = fn() { "" },
  ends? : (() -> Bool, (@view.View) -> Unit),
) -> Unit {
  let ends = match ends {
    Some((shown, make)) => Some(fn(e : @view.View) { e.show(shown, make) })
    None => None
  }
  @sf.section_node(b, title, body, note~, ends?, title_after=fn(l) {
    l.show(fn() { count() > 0 }, fn(n) { @sf.words_node(n, fn() { count().to_string() }, fn() { st_count }) |> ignore })
  })
}

///|
/// A row that says how something stands, going nowhere (said_row's: its title, `note` under it).
fn said_row_node(g : @view.View, title : () -> String, note? : () -> String = fn() { "" }, lead? : @sf.RowLead = NoLead) -> Unit {
  @sf.link_row_node(g, title, fn() {  }, note~, goes=false, lead~)
}

///|
/// A row's mark (a screen's, a folder's, a grant's: st_row_mark's): its icon in the muted ink.
fn st_mark_node(l : @view.View, icon : () -> String) -> Unit {
  @sf.icon_node(l, @signals.untracked(icon), st_row_glyph, By(fn() { @sf.theme().p.muted }), name_now=icon) |> ignore
}

// ── Overview ────────────────────────────────────────────────────────────

///|
/// What is left of the machine (and what its agents take of it), this device's connection to it, what still.fail uses
/// of it opening its 进程 (station_overview's 资源).
fn station_resources_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.page.resources") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      @sf.block_node(g, fn(k) {
        k.box(fn(r) {
          @sf.style_node(r, fn() { st_resources_in })
          let address = @signals.untracked(fn() { text(s(), "station") })
          let net = fn() { (core.topic)("stationNet", { "station": str(address) }).get().value }
          let uses = fn() { items(resources_of(core, here(), address), "stations").get(0) }
          station_dials_node(r, fn() { field(s(), "host") })
          r.show(fn() { net() is Some(Object(_)) }, fn(x) { station_net_node(x, net) })
          r.show(fn() { items(field(s(), "overview"), "processes").length() > 0 }, fn(x) {
            @sf.words_node(x, fn() { text(field(s(), "overview"), "processesText") }, fn() { st_memory }) |> ignore
          })
          // (what still.fail itself uses of the machine, opening its 进程: read while shown)
          r.show(fn() { uses() is Some(_) }, fn(x) { station_uses_node(x, address, uses) })
        })
        |> ignore
      })
    })
  })
}

///|
fn is_user_screen(sv : Json?) -> Bool {
  flag(sv, "userTab") || text(sv, "id").has_prefix("browser:u_")
}

///|
fn is_browser_screen(sv : Json?) -> Bool {
  text(sv, "kind") == "browser" || text(sv, "id").has_prefix("browser:")
}

///|
fn is_agent_screen(sv : Json?) -> Bool {
  is_browser_screen(sv) && !is_user_screen(sv)
}

///|
fn screen_row_icon(sv : Json?) -> String {
  if flag(sv, "sleeping") {
    "moon"
  } else if is_browser_screen(sv) {
    "web"
  } else if text(sv, "kind") == "simulator" {
    "phone"
  } else {
    "monitor"
  }
}

///|
/// User-opened browser pages on this station (`station_overview`'s 用户页面): live and recycled (sleeping) tabs in the
/// persistent user profile, plus 打开网页… at the section's end.
fn station_user_pages_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let v = fn() { (core.topic)("screens", { "station": str(address) }).get().value }
  let tabs = fn() { items(v(), "screens").filter(fn(sc) { is_user_screen(Some(sc)) }) }
  st_section_node(
    b,
    fn() { @sf.t("web-pages.screen.userPages") },
    count=fn() { tabs().length() },
    ends=(
      fn() { flag(v(), "browser") && flag(v(), "control") },
      fn(e) {
        @sf.action_node(
          e,
          fn() { @sf.t("web-pages.screen.openBrowser") },
          fn() { @settings.open_station_browser(core, address, from=Node(e)) },
          icon="plus",
          busy=fn() { is_doing(core, ["screen.openBrowser"], [("station", address)]) },
        )
      },
    ),
    fn(sec) {
      @sf.group_node(sec, fn(g) {
        g.each(tabs, fn(sc) { text(Some(sc), "id") }, fn(row, sc) {
          station_browser_row_node(row, core, here, address, fn() { Some(sc.get()) }, true)
        })
        g.show(fn() { tabs().is_empty() }, fn(n) {
          said_row_node(n, fn() { @sf.t("web-pages.screen.noUserPages") }, lead=LeadLine(fn(l) { st_mark_node(l, fn() { "web" }) }))
        })
      })
    },
  )
}

///|
/// Agent-opened and login browser pages on this station (`station_overview`'s Agent 页面), kept apart from user pages.
fn station_agent_pages_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let v = fn() { (core.topic)("screens", { "station": str(address) }).get().value }
  let tabs = fn() { items(v(), "screens").filter(fn(sc) { is_agent_screen(Some(sc)) }) }
  st_section_node(b, fn() { @sf.t("web-pages.screen.agentPages") }, count=fn() { tabs().length() }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(tabs, fn(sc) { text(Some(sc), "id") }, fn(row, sc) {
        station_browser_row_node(row, core, here, address, fn() { Some(sc.get()) }, false)
      })
    })
  })
}

///|
/// One browser tab row (`station_browser_row`'s node counterpart): opens the tab, with 休眠 (while an idle live user tab)
/// and 关闭 at its end, and any active viewer rows under it.
fn station_browser_row_node(
  row : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  sv : () -> Json?,
  user_tab : Bool,
) -> Unit {
  let id = text(@signals.untracked(sv), "id")
  let can_sleep = fn() { user_tab && flag(sv(), "closable") && !flag(sv(), "sleeping") && items(sv(), "views").is_empty() }
  let can_close = fn() { flag(sv(), "closable") }
  row.pick(fn() { (can_sleep(), can_close()) }, fn(p, k) {
    let (sleep_on, close_on) = k
    @sf.group_rows_node(p, fn(r) {
      @sf.link_row_node(
        r,
        fn() { text(sv(), "title") },
        fn() {
          @sfbase.open_page(Screen({ station: address, screen: id, title: text(@signals.untracked(sv), "title"), until_gone: !user_tab }))
        },
        note=fn() { text(sv(), "line") },
        lead=LeadLine(fn(l) { st_mark_node(l, fn() { screen_row_icon(sv()) }) }),
        control?=if sleep_on || close_on {
          Some(fn(e) {
            let on = [("station", address), ("screen", id)]
            e.box(fn(c) {
              c.row(Is(true)).gap(Is(ws_tail_gap)).lines_up(Is(Some(Middle))) |> ignore
              if sleep_on {
                let what = @sf.t("web-pages.screen.sleepWhat")
                let press = fn() { @settings.act(core, what, "screen.sleep", obj([("station", str(address)), ("screen", str(id))])) }
                let busy = fn() { is_doing(core, ["screen.sleep"], on) }
                if close_on {
                  @sf.button_node(c, fn() { @sf.t("web-pages.screen.sleep") }, press, tone=Ghost, busy~) |> ignore
                } else {
                  @sf.row_end_button_node(c, fn() { @sf.t("web-pages.screen.sleep") }, press, busy~) |> ignore
                }
              }
              if close_on {
                let what = @sf.t("web-pages.screen.closeTabWhat")
                @sf.row_end_button_node(
                  c,
                  fn() { @sf.t("web-pages.screen.closeTab") },
                  fn() { @settings.act(core, what, "screen.close", obj([("station", str(address)), ("screen", str(id))])) },
                  busy=fn() { is_doing(core, ["screen.close"], on) },
                )
                |> ignore
              }
            })
            |> ignore
          })
        } else {
          None
        },
      )
      screen_views_node(r, core, here, address, sv)
    })
  })
}

///|
/// Its screens (station_overview's): a row each opening it (this machine's own display said so, not opened), what it
/// lacks in amber, who is on it under it; one from before them says so quietly.
fn station_screens_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let v = fn() { (core.topic)("screens", { "station": str(address) }).get().value }
  let screens = fn() { items(v(), "screens").filter(fn(sc) { !is_browser_screen(Some(sc)) }) }
  st_section_node(b, fn() { @sf.t("web-pages.screen.section") }, count=fn() { screens().length() }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(screens, fn(sc) { text(Some(sc), "id") }, fn(row, sc) {
        let sv = fn() { Some(sc.get()) }
        let id = text(@signals.untracked(sv), "id")
        // this machine's own display: said so, not opened (own_screen); what it lacks, its row made again so (the
        // core's: what cannot be done now)
        let lacks = fn() {
          let access = field(sv(), "access")
          access is Some(Object(_)) && (!flag(access, "capture") || !flag(access, "control"))
        }
        row.pick(fn() { (own_screen(address, id), lacks()) }, fn(p, k) {
          let (own, lacks) = k
          @sf.group_rows_node(p, fn(r) {
          @sf.link_row_node(
            r,
            fn() { text(sv(), "title") },
            fn() {
              if !own {
                @sfbase.open_page(Screen({ station: address, screen: id, title: text(@signals.untracked(sv), "title"), until_gone: false }))
              }
            },
            // what it lacks says so in its line
            note=fn() { if own { @sf.t("android-misc.screen.here") } else { text(sv(), "line") } },
            lacks=!own && lacks,
            goes=!own,
            // (its mark the page's own row mark, st_row_mark's 16 in the muted ink, by its first line, as the old page's)
            lead=LeadLine(fn(l) { st_mark_node(l, fn() { screen_row_icon(sv()) }) }),
          )
          screen_views_node(r, core, here, address, sv)
          })
        })
      })
      g.show(fn() { screens().length() == 0 && items(v(), "screens").is_empty() && text(v(), "note") != "" }, fn(n) {
        said_row_node(n, fn() { text(v(), "note") }, lead=LeadLine(fn(l) { st_mark_node(l, fn() { "monitor" }) }))
      })
    })
  })
}

///|
/// Who is on one of its screens now (screen_views'): a row a view, whose and on which device, whether it drives it and
/// since when; 转为只看 and 断开 at its end for one the viewer may let go of, and 全部断开 once there is more than one.
fn screen_views_node(g : @view.View, core : Core, here : () -> Here, address : String, screen : () -> Json?) -> Unit {
  let id = text(@signals.untracked(screen), "id")
  let asked = fn(name : String, what : String, params : Array[(String, Json)]) {
    @settings.act(core, what, name, obj([("station", str(address)), ("screen", str(id)), ("account", str(@signals.untracked(here).sub)), ..params]))
  }
  g.each(fn() { items(screen(), "views") }, fn(v) { text(Some(v), "id") }, fn(row, vs) {
    let vv = fn() { Some(vs.get()) }
    let view = text(@signals.untracked(vv), "id")
    let on = [("view", view)]
    row.pick(fn() { (flag(vv(), "may"), flag(vv(), "control")) }, fn(r, k) {
      let (may, control) = k
      @sf.link_row_node(
        r,
        fn() { text(vv(), "name") },
        fn() {  },
        // (the device is what tells one's own views apart: in the note, which wraps where 转为只看 and 断开 leave little room)
        note=fn() {
          let device = if flag(vv(), "here") { @sf.t("web-pages.screen.viewHere") } else { text(vv(), "device") }
          let mode = @sf.t(if flag(vv(), "control") { "web-pages.screen.viewControl" } else { "web-pages.screen.viewWatch" })
          if device == "" { mode + " · " + text(vv(), "ago") } else { device + " · " + mode + " · " + text(vv(), "ago") }
        },
        goes=false,
        tail?=if may {
          Some(fn(e) {
            @sf.line_end_node(e, fn(l) {
              if control {
                let what = @sf.t("web-pages.screen.viewWatchOnly")
                @sf.button_node(l, fn() { what }, fn() { asked("screen.watchOnly", what, [("view", str(view))]) }, tone=Ghost, busy=fn() {
                  is_doing(core, ["screen.watchOnly"], on)
                })
                |> ignore
              }
              let what = @sf.t("web-pages.screen.viewEnd")
              @sf.button_node(l, fn() { what }, fn() { asked("screen.endView", what, [("view", str(view))]) }, tone=Ghost, busy=fn() {
                is_doing(core, ["screen.endView"], on)
              })
              |> ignore
            })
          })
        } else {
          None
        },
      )
    })
  })
  g.show(fn() { items(screen(), "views").filter(fn(v) { flag(Some(v), "may") }).length() > 1 }, fn(r) {
    let what = @sf.t("web-pages.screen.viewsEndAll")
    @sf.link_row_node(r, fn() { "" }, fn() {  }, goes=false, tail=fn(e) {
      @sf.line_end_node(e, fn(l) {
        @sf.button_node(l, fn() { what }, fn() { asked("screen.endViews", what, []) }, tone=Ghost, busy=fn() {
          is_doing(core, ["screen.endViews"], [("screen", id)])
        })
        |> ignore
      })
    })
  })
}

///|
/// Its profiles by account kind (station_overview's): a row a kind, how many and how many need a look, pressed open to
/// its accounts beside it (station_profiles_panel), from the row (link_row_opens_node).
fn station_profiles_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  st_section_node(b, fn() { @sf.t("android-misc.bar.place.profiles") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(fn() { items(s(), "profileGroups") }, fn(gr) { text(Some(gr), "group") }, fn(row, gr) {
        let gv = fn() { Some(gr.get()) }
        let kind = text(@signals.untracked(gv), "group")
        let ids = fn() { strings(gv(), "profiles") }
        let attention = fn() {
          match field(gv(), "attention") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
        }
        row.box(fn(holder) {
          // (opened from the row itself: beside it, following it, the focus back on it as it closes)
          @sf.link_row_opens_node(
            holder,
            fn() { text(gv(), "title") },
            fn(at) {
              let many = @signals.untracked(ids).length() >= @sf.pick_search_from
              station_profiles_panel(core, @signals.untracked(here), address, kind, text(@signals.untracked(gv), "title"), Node(at), many)
            },
            value=fn() { @sf.t("web-mobile.settings.profilesCount", args=[("n", ids().length().to_string())]) },
            trouble=fn() {
              if attention() > 0 {
                @sf.t("web-mobile.settings.profilesShort", args=[("n", attention().to_string())])
              } else {
                ""
              }
            },
            lead=LeadLine(fn(l) { vt_group_mark_node(l, kind) }),
          )
        })
        |> ignore
      })
    })
  })
}

///|
/// Its connects (station_overview's): a row each, its team and how it runs, how it is where it is not online, opening
/// its page.
fn station_connects_node(b : @view.View, core : Core, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let connects = fn() { items(field(s(), "overview"), "connects") }
  st_section_node(b, fn() { @sf.t("web-pages.settings.nav.connects") }, count=fn() { connects().length() }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(connects, fn(cn) { text(Some(cn), "id") }, fn(row, cn) {
        let cv = fn() { Some(cn.get()) }
        @sf.link_row_node(
          row,
          fn() { text(cv(), "name") },
          fn() { (core.push)(Connect(address, text(@signals.untracked(cv), "id"))) },
          note=fn() { join([text(cv(), "team"), text(cv(), "runText")], " · ") },
          value=fn() { if text(cv(), "presence") != "online" { text(cv(), "statusText") } else { "" } },
          lead=LeadLine(fn(l) { @sf.state_dot_node(l, fn() { text(cv(), "presence") }) }),
        )
      })
    })
  })
}

///|
/// Its drive (station_overview's): a station that offers its home opens there; older ones still show their configured
/// folders, 打开文件 at its title's end.
fn station_drive_node(b : @view.View, s : () -> Json?) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let drive = fn() { field(field(s(), "overview"), "drive") }
  let roots = fn() { items(drive(), "roots") }
  let open = fn(root : String?) { @sfbase.open_page(Drive({ station: address, root, path: "" })) }
  b.pick(fn() { flag(drive(), "anywhere") }, fn(p, anywhere) {
    if anywhere {
      st_section_node(p, fn() { @sf.t("web-pages.drive.title") }, fn(sec) {
        @sf.group_node(sec, fn(g) {
          @sf.link_row_node(g, fn() { @sf.t("web-pages.stations.page.openFiles") }, fn() { open(None) }, lead=LeadLine(fn(l) { st_mark_node(l, fn() { "folder" }) }))
        })
      })
    } else {
      st_section_node(
        p,
        fn() { @sf.t("web-pages.drive.title") },
        count=fn() { roots().length() },
        ends=(fn() { true }, fn(e) {
          @sf.action_node(e, fn() { @sf.t("web-pages.stations.page.openFiles") }, fn() { open(None) }, icon="folder")
        }),
        fn(sec) {
          @sf.group_node(sec, fn(g) {
            g.show(fn() { roots().length() == 0 }, fn(n) { said_row_node(n, fn() { @sf.t("web-pages.drive.noneYet") }) })
            g.each(roots, fn(r) { text(Some(r), "path") }, fn(row, r) {
              let rv = fn() { Some(r.get()) }
              @sf.link_row_node(
                row,
                fn() { text(rv(), "name") },
                fn() { open(Some(text(@signals.untracked(rv), "path"))) },
                note=fn() { text(rv(), "path") },
                lead=LeadLine(fn(l) { st_mark_node(l, fn() { "folder" }) }),
              )
            })
          })
        },
      )
    }
  })
}

///|
/// What else of it has a page of its own (station_overview's 更多): its memory.
fn station_more_node(b : @view.View, core : Core, address : String) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.page.more") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      @sf.link_row_node(g, fn() { @sf.t("android-settings.memory") }, fn() { (core.push)(Memory(address)) })
      // (共享调试 is no station's: a chat's agent asks for the phone, and settings' 共享调试 is where it stands)
    })
  })
}

///|
/// Its 进程 (station_processes'): what still.fail uses of the machine; offline, a line saying it cannot be seen.
fn station_processes_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?) -> Unit {
  b.pick(fn() { flag(s(), "online") }, fn(p, online) {
    if online {
      resources_node(p, core, here, text(@signals.untracked(s), "station"))
    } else {
      @sf.words_node(p, fn() { @sf.t("web-pages.stations.processesOffline") }, fn() { st_memory }) |> ignore
    }
  })
}

// ── Settings ────────────────────────────────────────────────────────────

///|
/// Its 登录 (station_logins'): only the logins done there through still.fail; one under way its card (as in its chat), those ended a row per program naming it, who last logged in to it, from
/// which chat, and how many tries, pressed open to them. Nothing when there are none. Away (`online` false), no card of
/// one under way: it can be neither done nor cancelled until it is back.
fn station_logins_node(b : @view.View, core : Core, station : String, online : () -> Bool) -> Unit {
  let view = fn() { (core.topic)("machineLogins", { "station": str(station) }).get().value }
  let active = fn() { if online() { items(view(), "logins").filter(fn(l) { flag(Some(l), "active") }) } else { [] } }
  let tools = fn() { items(view(), "tools") }
  b.show(fn() { flag(view(), "supported") && active().length() + tools().length() > 0 }, fn(p) {
    st_section_node(p, fn() { @sf.t("web-main.logins.title") }, note=fn() { @sf.t("web-main.logins.lead") }, fn(sec) {
      sec.show(fn() { active().length() > 0 }, fn(k) {
        k.box(fn(cards) {
          @sf.style_node(cards, fn() { lg_cards })
          cards.each(fn() { active().map(fn(l) { text(Some(l), "id") }) }, fn(id) { id }, fn(c, id) {
            login_card_node(c, core, station, id.untracked(), place="station")
          })
        })
        |> ignore
      })
      sec.show(fn() { tools().length() > 0 }, fn(gp) {
        @sf.group_node(gp, fn(g) {
          // (a row a program, and under one open a row a try: each a row of the card's)
          let rows = fn() {
            let out : Array[(String, Int)] = []
            for tool in tools() {
              let name = text(Some(tool), "name")
              out.push((name, -1))
              if st_logins_open.get(station) == Some(name) {
                for i, _ in items(Some(tool), "tries") {
                  out.push((name, i))
                }
              }
            }
            out
          }
          let tool_of = fn(name : String) { tools().iter().find_first(fn(t) { text(Some(t), "name") == name }) }
          g.each(rows, fn(r) { r }, fn(row, r) {
            let (name, at) = r.untracked()
            if at < 0 {
              login_tool_row_node(row, station, name, fn() { tool_of(name) })
            } else {
              login_try_row_node(row, fn() { items(tool_of(name), "tries").get(at) })
            }
          })
        })
      })
    })
  })
}

///|
/// A program's row (station_logins'): its maker's mark, bare; its name; who last logged in to it, from which chat (in
/// red where none went through and the latest failed); how many tries at its end; pressed, its tries open or shut.
fn login_tool_row_node(row : @view.View, station : String, name : String, tool : () -> Json?) -> Unit {
  let said = fn() {
    let chat = match text(tool(), "chatTitle") {
      "" => ""
      title => "「" + title + "」"
    }
    join([text(tool(), "summaryText"), chat].filter(fn(w) { w != "" }), " · ")
  }
  let open = fn() { st_logins_open.get(station) == Some(name) }
  @sf.link_row_node(
    row,
    fn() { name },
    fn() { st_logins_open[station] = if @signals.untracked(open) { "" } else { name } },
    note=fn() { if flag(tool(), "failed") { "" } else { said() } },
    trouble=fn() { if flag(tool(), "failed") { said() } else { "" } },
    folds=open,
    // (its maker's mark, bare, in its colours; else a terminal's: one key for all told them apart by nothing)
    lead=LeadMade(fn(l) {
      l.box(fn(m) {
        @sf.style_node(m, fn() { lg_mark })
        @sf.tool_mark_node(m, text(@signals.untracked(tool), "mark"), lg_mark_glyph)
      })
      |> ignore
    }),
    // (how many tries at its end, not as what it says: its name, a station's words, keeps the line)
    tail=fn(t) { @sf.words_node(t, fn() { text(tool(), "countText") }, fn() { lg_count }) |> ignore },
  )
}

///|
/// A try under its program's row (station_logins'): when, how it ended (who ended it says so: 张三 取消; else the status:
/// 已取消), in red where it failed, from which chat; its words where the program's name is.
fn login_try_row_node(row : @view.View, l : () -> Json?) -> Unit {
  @sf.link_row_node(
    row,
    fn() { text(l(), "whenText") },
    fn() {  },
    value=fn() {
      match text(l(), "doneByText") {
        "" => text(l(), "statusText")
        by => by
      }
    },
    value_bad=fn() { text(l(), "state") == "failed" },
    note=fn() {
      match text(l(), "chatTitle") {
        "" => ""
        title => "「" + title + "」"
      }
    },
    goes=false,
    lead=LeadMade(fn(m) { @sf.style_node(m, fn() { lg_no_mark }) }),
  )
}

///|
/// What macOS lets its still.fail Helper do (station_permissions'): a row each, what it is for, given or not; one not
/// given asked for from here (`permissions.request`), its screen opened where it can be driven.
fn station_permissions_node(b : @view.View, core : Core, address : String, p : () -> Json?) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.permissions.section") }, note=fn() { text(p(), "note") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.each(fn() { items(p(), "grants") }, fn(gr) { text(Some(gr), "id") }, fn(row, gr) {
        let gv = fn() { Some(gr.get()) }
        let gid = text(@signals.untracked(gv), "id")
        let end = fn() {
          if flag(gv(), "granted") {
            "granted"
          } else if flag(gv(), "asking") {
            if text(p(), "screen") != "" { "open" } else { "waiting" }
          } else if flag(p(), "canRequest") {
            "request"
          } else {
            "missing"
          }
        }
        row.pick(end, fn(r, now) {
          let button = now == "open" || now == "request"
          @sf.link_row_node(
            r,
            fn() { text(gv(), "name") },
            fn() {  },
            note=fn() { text(gv(), "line") },
            value=fn() {
              match now {
                "granted" => @sf.t("web-pages.stations.permissions.granted")
                "waiting" => @sf.t("web-pages.stations.permissions.waiting")
                "missing" => @sf.t("web-pages.stations.permissions.missing")
                _ => ""
              }
            },
            goes=false,
            // (a button at its end makes its first line as tall as the button: its mark across that line's middle, by
            // its title, not the body line's above it)
            lead=LeadLine(fn(l) {
              if button {
                l.box(fn(m) {
                  m.height(By(fn() { Some(@sf.button_height()) })).lies_along(Is(Middle)) |> ignore
                  st_mark_node(m, fn() { grant_icon(gid) })
                })
                |> ignore
              } else {
                st_mark_node(l, fn() { grant_icon(gid) })
              }
            }),
            tail?=match now {
              "open" =>
                Some(fn(t) {
                  @sf.button_node(t, fn() { @sf.t("web-pages.stations.permissions.openScreen") }, fn() {
                    open_screen_link(core, text(@signals.untracked(p), "screen"))
                  })
                  |> ignore
                })
              "request" =>
                Some(fn(t) {
                  let busy = fn() { is_doing(core, ["permissions.request"], [("station", address), ("grant", gid)]) }
                  @sf.button_node(t, fn() { @sf.t("web-pages.stations.permissions.request") }, fn() {
                    let screen = text(@signals.untracked(p), "screen")
                    @settings.act(
                      core,
                      @sf.t("web-pages.stations.permissions.requestWhat", args=[("name", text(@signals.untracked(gv), "name"))]),
                      "permissions.request",
                      obj([("station", str(address)), ("grant", str(gid))]),
                      then=fn(answer) {
                        if text(Some(answer), "window") == "up" && flag(Some(answer), "screen") && screen != "" {
                          open_screen_link(core, screen)
                        }
                      },
                    )
                  }, tone=Primary, busy~, disabled=busy)
                  |> ignore
                })
              _ => None
            },
          )
        })
      })
    })
  })
}

///|
/// Its agents' variables (station_env's): its managers edit them as a .env file's lines in the core's draft
/// (`agentEnvForm`) on a card, saved with 保存; the others see them, a secret's value masked.
fn station_env_node(b : @view.View, core : Core, address : String, env : () -> Json?, manager : Bool) -> Unit {
  if manager {
    st_section_node(b, fn() { @sf.t("web-pages.stations.agentEnv") }, note=fn() { @sf.t("web-pages.stations.agentEnvLead") }, fn(sec) {
      @sf.page_card_node(sec, footed=true, fn(k) { station_env_editor_node(k, core, address, @ui.Field::new()) })
    })
    return
  }
  let list = fn() {
    match env() {
      Some(Array(a)) => a
      _ => []
    }
  }
  b.show(fn() { list().length() > 0 }, fn(p) {
    st_section_node(p, fn() { @sf.t("web-pages.stations.agentEnv") }, fn(sec) {
      @sf.group_node(sec, fn(g) {
        g.each(fn() { list().mapi(fn(i, e) { (i, e) }) }, fn(x) { x.0 }, fn(row, x) {
          said_row_node(row, fn() { text(Some(x.get().1), "key") }, note=fn() { text(Some(x.get().1), "value") })
        })
      })
    })
  })
}

///|
/// The draft of a station's variables (station_env_editor's) in node `k`, typed in `field_`: the field (following the
/// draft every page of it shares, the latest edit kept while the core catches up), what is wrong under it (a line the
/// core cannot take), 取消 while changed, 保存. What is typed told the core as it is typed; one typed while it saves,
/// once it is done.
fn station_env_editor_node(k : @view.View, core : Core, address : String, field_ : @ui.Field) -> Unit {
  let form = match env_forms.get(address) {
    Some(f) => f
    None => {
      env_forms_made.val += 1
      let f = "mbui-env-" + env_forms_made.val.to_string()
      env_forms[address] = f
      @settings.act(core, @sf.t("web-pages.stations.agentEnvRead"), "agentEnv.form.open", obj([("station", str(address)), ("form", str(f))]))
      f
    }
  }
  let d = fn() { (core.topic)("agentEnvForm", { "station": str(address), "form": str(form) }).get().value }
  let draft = match env_drafts.get(address) {
    Some(draft) => draft
    None => {
      let draft : EnvDraft = { pending: @signals.signal(None, same=fn(a, b) { a == b }), reset: @signals.signal(0), source: None, sent: None }
      env_drafts[address] = draft
      draft
    }
  }
  // (the core's words as it says them, while it is not saving)
  let said = fn() {
    match d() {
      Some(Object(_)) as v if !flag(v, "pending") => Some(text(v, "text"))
      _ => None
    }
  }
  // (what the core says becomes what the draft holds, and clears what was pending where it is that: an older answer for
  // an older edit leaves a newer edit be)
  let known : @signals.Signal[String?] = @signals.signal(draft.source, same=fn(a, b) { a == b })
  k.reacts(said, fn(now) {
    match now {
      Some(words) => {
        draft.source = now
        known.set(now)
        if draft.pending.untracked() == Some(words) {
          draft.pending.set(None)
          draft.sent = None
        }
      }
      None => ()
    }
  })
  let source = fn() {
    match draft.pending.get() {
      Some(_) as p => p
      None => known.get()
    }
  }
  // Keep the latest edit visible on every page while the core catches up: the field follows what the draft holds.
  k.reacts(fn() { (source(), draft.reset.get()) }, fn(now) {
    match now.0 {
      Some(words) => field_.follow(words, generation=now.1)
      None => ()
    }
  })
  // The core cannot edit a form while it saves: an edit typed then is shared at once, and sent once saving finishes;
  // an older acknowledgement never clears or resends a newer value.
  k.reacts(fn() { (draft.pending.get(), d()) }, fn(now) {
    match now {
      (Some(words), Some(Object(_)) as v) if !flag(v, "pending") && text(v, "text") != words && draft.sent != Some(words) => {
        draft.sent = Some(words)
        station_env_edit(core, address, form, words)
      }
      _ => ()
    }
  })
  // what the person types here, as they type it (the field's edit, never what it is given to follow): the draft's,
  // told the core once it can take it. Typed before the core has said the form's words (just opened, it has not
  // answered yet) or while it saves, it is pending and sent as the core says them (the reaction above).
  let typed = fn(typed : String) {
    let known = @signals.untracked(source)
    if known != Some(typed) {
      draft.pending.set(Some(typed))
      if known is None || flag(@signals.untracked(d), "pending") {
        draft.sent = None
      } else {
        draft.sent = Some(typed)
        station_env_edit(core, address, form, typed)
      }
    }
  }
  let saving = fn() { is_doing(core, ["agentEnv.form.save"], [("station", address), ("form", form)]) }
  let read = fn() { d() is Some(Object(_)) && text(d(), "text") == field_.text() }
  k.box(fn(e) {
    @sf.style_node(e, fn() { st_editor })
    // (first in its card, a block in its corners: `corner_inset` in, a row's corner, its words on the card's line:
    // @sf.card_block_out)
    e.box(fn(f) {
      @sf.style_node(f, fn() { @sf.card_block_out(top=true) })
      @sf.textarea_node(f, field_, rows=6, placeholder=env_placeholder, corner=@sf.row_corner, edited=typed) |> ignore
    })
    |> ignore
    // what is wrong, a line each
    let problems = fn() {
      if !read() {
        return []
      }
      let out : Array[(Int, String, Bool)] = []
      for i, l in items(d(), "lines") {
        let lv = Some(l)
        if text(lv, "problem") != "" {
          out.push((i + 1, text(lv, "problem"), flag(lv, "error")))
        }
      }
      out
    }
    e.show(fn() { problems().length() > 0 }, fn(w) {
      w.box(fn(ps) {
        @sf.style_node(ps, fn() { st_env_problems })
        ps.each(problems, fn(x) { x.0 }, fn(l, x) {
          @sf.words_node(l, fn() {
            @sf.t("web-pages.stations.agentEnvLine", args=[("line", x.get().0.to_string()), ("problem", x.get().1)])
          }, fn() { if x.get().2 { st_problem_bad } else { st_problem } })
          |> ignore
        })
      })
      |> ignore
    })
    // (its buttons at its foot's end, reaching its foot corners: card_foot's at_end)
    e.box(fn(a) {
      @sf.style_node(a, fn() { st_env_foot.then(@sf.foot_across(@sf.button_height())) })
      a.show(fn() { flag(d(), "dirty") }, fn(c) {
        @sf.button_node(c, fn() { @sf.t("common.cancel") }, fn() {
          @signals.start_batch()
          draft.pending.set(None)
          draft.sent = None
          draft.reset.set(draft.reset.untracked() + 1)
          @signals.end_batch()
          @settings.act(
            core,
            @sf.t("web-pages.stations.agentEnvEdit"),
            "agentEnv.form.edit",
            obj([("station", str(address)), ("form", str(form)), ("input", obj([("reset", Json::boolean(true))]))]),
          )
        }, tone=Ghost)
        |> ignore
      })
      let can = fn() {
        let v = d()
        v is Some(Object(_)) && flag(v, "dirty") && !flag(v, "pending") && !saving() && read() && count(v, "errors") == 0
      }
      @sf.button_node(a, fn() { @sf.t("common.save") }, fn() {
        @settings.act(
          core,
          @sf.t("web-pages.stations.agentEnvSave"),
          "agentEnv.form.save",
          obj([("station", str(address)), ("form", str(form))]),
          done=@sf.t("web-pages.profiles.saved"),
        )
      }, tone=Primary, busy=saving, disabled=fn() { !can() })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A switch of its 设置 (search's, diagnostics', context's, elevation's): `title`, on as `on` says, `note` under it,
/// turned (the core's `call` with `key` set to what it is to be, said `what`) by its managers only; waiting on what was
/// set meanwhile.
fn st_switch_node(
  g : @view.View,
  core : Core,
  address : String,
  title : () -> String,
  on : () -> Bool,
  note : () -> String,
  call : String,
  key : String,
  what : () -> String,
  can : () -> Bool,
  busy? : () -> Bool = fn() { false },
) -> Unit {
  let busy = fn() { is_doing(core, [call], [("station", address)]) || busy() }
  @sf.switch_row_node(
    g,
    title,
    on,
    fn(now) { @settings.act(core, what(), call, obj([("station", str(address)), (key, Json::boolean(now))])) },
    note~,
    disabled=fn() { !can() },
    busy~,
  )
}

///|
/// What its search finds of the machine (station_search's): whether the person's own mail and the like are found too.
fn station_search_node(b : @view.View, core : Core, address : String, search : () -> Json?, manager : Bool) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.search.section") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      st_switch_node(
        g,
        core,
        address,
        fn() { @sf.t("web-pages.stations.search.personal") },
        fn() { flag(search(), "personal") },
        fn() { @sf.t("web-pages.stations.search.personalLine") },
        "search.setPersonal",
        "personal",
        fn() { @sf.t("web-pages.stations.search.what") },
        fn() { manager },
      )
    })
  })
}

///|
/// What it sends still.fail to find its problems by (station_diagnostics'): whether its log goes, scrubbed.
fn station_diagnostics_node(b : @view.View, core : Core, address : String, diagnostics : () -> Json?, manager : Bool) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.diagnostics.section") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      st_switch_node(
        g,
        core,
        address,
        fn() { @sf.t("web-pages.stations.diagnostics.logs") },
        fn() { flag(diagnostics(), "logs") },
        fn() { @sf.t("web-pages.stations.diagnostics.logsLine") },
        "diagnostics.setLogs",
        "logs",
        fn() { @sf.t("web-pages.stations.diagnostics.what") },
        fn() { manager },
      )
    })
  })
}

///|
/// How it goes on with a session whose prompt cache is over (station_context's): the station default, and once it is
/// on, its estimated cost threshold changed from the section's title (its managers').
fn station_context_node(b : @view.View, core : Core, address : String, context : () -> Json?, manager : Bool) -> Unit {
  let cost = fn() {
    match field(context(), "afreshAbove") {
      Some(Number(value, ..)) => Some(value)
      _ => None
    }
  }
  let on = fn() { flag(context(), "afreshWhenCold") }
  let busy = fn() { is_doing(core, ["context.setAfresh"], [("station", address)]) }
  st_section_node(
    b,
    fn() { @sf.t("web-pages.stations.context.section") },
    ends=(fn() { cost() is Some(_) && on() && manager }, fn(e) {
      @sf.action_node(e, fn() { @sf.t("web-pages.stations.context.customAmount") }, fn() {
        match @signals.untracked(cost) {
          Some(value) => station_cold_custom(core, address, value)
          None => ()
        }
      }, disabled=busy)
    }),
    fn(sec) {
      @sf.group_node(sec, fn(g) {
        @sf.switch_row_node(
          g,
          fn() { @sf.t("web-pages.stations.context.afresh") },
          on,
          fn(now) {
            @settings.act(
              core,
              @sf.t("web-pages.stations.context.what"),
              "context.setAfresh",
              obj([("station", str(address)), ("afreshWhenCold", Json::boolean(now))]),
            )
          },
          note=fn() {
            match cost() {
              Some(value) if value == 0.0 => @sf.t("web-pages.stations.context.afreshZeroLine")
              Some(value) => @sf.t("web-pages.stations.context.afreshCostLine", args=[("amount", "$" + value.to_string())])
              None => @sf.t("web-pages.stations.context.afreshLineLegacy")
            }
          },
          disabled=fn() { !manager },
          busy~,
        )
      })
    },
  )
}

///|
/// Whether a Windows station runs as the machine's administrator (station_elevation's): switched by the workspace's
/// managers, Windows asking on the machine and the station restarting; how the last change failed under it.
fn station_elevation_node(b : @view.View, core : Core, address : String, elevation : () -> Json?) -> Unit {
  st_section_node(b, fn() { @sf.t("web-pages.stations.elevation.section") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      st_switch_node(
        g,
        core,
        address,
        fn() { @sf.t("web-pages.stations.elevation.admin") },
        fn() { flag(elevation(), "on") },
        fn() { text(elevation(), "line") },
        "elevation.set",
        "on",
        fn() { @sf.t("web-pages.stations.elevation.what") },
        fn() { flag(elevation(), "canChange") },
        busy=fn() { flag(elevation(), "busy") },
      )
    })
    sec.show(fn() { text(elevation(), "failed") != "" }, fn(f) {
      @sf.words_node(f, fn() { text(elevation(), "failed") }, fn() { st_problem_bad }) |> ignore
    })
  })
}

///|
/// Its advanced network controls (station_network's), folded until asked for: opened, a row of its card under the row
/// that folds them, the congestion controller chosen for the next station start.
fn station_network_node(b : @view.View, core : Core, address : String, network : () -> Json?, manager : Bool) -> Unit {
  // (open as the settings keep it, by station: turned here, told there as well)
  let open = @signals.signal(@settings.station_network_open.get(address).unwrap_or(false))
  @sf.group_node(b, fn(g) {
    @sf.link_row_node(g, fn() { @sf.t("web-pages.stations.network.advanced") }, fn() {
      let now = !open.untracked()
      @settings.station_network_open[address] = now
      open.set(now)
    }, folds=fn() { open.get() })
    g.show(fn() { open.get() }, fn(o) {
      @sf.setting_node(o, fn() { @sf.t("web-pages.stations.network.algorithm") }, note=fn() { @sf.t("web-pages.stations.network.note") }, in_card=true, fn(c) {
        let busy = fn() { is_doing(core, ["network.setCongestion"], [("station", address)]) }
        @sf.select_node(
          c,
          fn() { text(network(), "congestion") },
          fn() { ["cubic", "bbr"].map(fn(algorithm) { (algorithm, @sf.t("web-pages.stations.network." + algorithm)) }) },
          fn(algorithm) {
            @settings.act(
              core,
              @sf.t("web-pages.stations.network.what"),
              "network.setCongestion",
              obj([("station", str(address)), ("congestion", str(algorithm))]),
              done=@sf.t("web-pages.stations.network.saved"),
            )
          },
          label=fn() { @sf.t("web-pages.stations.network.algorithm") },
          disabled=fn() { !manager || busy() },
          whole=true,
        )
      })
    })
  })
}

///|
/// The workspaces it is in (station_workspaces'), for its home's owners and admins once it is in more than one: its
/// home first, what each has of the machine.
fn station_workspaces_node(b : @view.View, core : Core, address : String) -> Unit {
  let m = fn() { (core.topic)("memberships", { "station": str(address) }).get().value }
  let ws = fn() { items(m(), "workspaces") }
  b.show(fn() { flag(m(), "manages") && ws().length() >= 2 }, fn(p) {
    st_section_node(p, fn() { "Workspace" }, count=fn() { ws().length() }, note=fn() { @sf.t("web-pages.stations.workspacesLead") }, fn(sec) {
      @sf.group_node(sec, fn(g) {
        g.each(fn() { ws().mapi(fn(i, w) { (i, w) }) }, fn(x) { x.0 }, fn(row, x) {
          let wv = fn() { Some(x.get().1) }
          row.pick(fn() { @sf.has_station_mark(text(wv(), "emoji"), text(wv(), "icon")) }, fn(r, marked) {
            said_row_node(r, fn() { text(wv(), "name") }, note=fn() { text(wv(), "line") }, lead=if marked {
              LeadLine(fn(l) { @sf.station_mark_node(l, fn() { text(wv(), "emoji") }, fn() { text(wv(), "icon") }, st_ws_mark, fn() { @sf.theme().p.text }, fn() { 0 }) })
            } else {
              NoLead
            })
          })
        })
      })
    })
  })
}

// ── Machine ─────────────────────────────────────────────────────────────

///|
/// Its software (station_machine's 软件与更新): its versions (updated by its home's managers), away a line saying they
/// cannot be seen; its own version where it lists none.
fn station_software_node(b : @view.View, core : Core, s : () -> Json?, manager : Bool, tips : @sf.TipLayer) -> Unit {
  let station = text(@signals.untracked(s), "station")
  let updates = fn() { items(field(s(), "overview"), "updates") }
  st_section_node(b, fn() { @sf.t("web-pages.stations.software") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      // (its rows the card's own, away none: a line saying so in their place)
      software_list_node(g, core, station, fn() { if flag(s(), "online") { updates() } else { [] } }, manager, fn() {
        flag(s(), "betaOffered")
      }, tips)
      g.show(fn() { !flag(s(), "online") }, fn(r) { said_row_node(r, fn() { @sf.t("web-pages.stations.softwareOffline") }) })
      g.show(fn() { updates().length() == 0 && text(s(), "version") != "" }, fn(r) {
        said_row_node(r, fn() { "Station " + text(s(), "version") })
      })
    })
  })
}

///|
/// A station's software (software_list's): a row each, then when it was last checked, with checking again.
fn software_list_node(
  g : @view.View,
  core : Core,
  station : String,
  updates : () -> Array[Json],
  manager : Bool,
  beta : () -> Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let batch = fn() { is_doing(core, ["software.updateAll"], [("station", station)]) }
  g.each(updates, fn(u) { text(Some(u), "id") }, fn(row, u) {
    let id = text(Some(u.untracked()), "id")
    software_row_node(row, core, station, fn() { Some(u.get()) }, manager, fn() {
      batch() || is_doing(core, ["software.update"], [("station", station), ("id", id)])
    }, beta, tips)
  })
  // (in lines: checking again after when it was last checked, under it where the line has not the room; why it failed a
  // line of its own)
  g.show(fn() { updates().length() > 0 }, fn(f) {
    let checked = fn() {
      match field(updates().get(0), "checkedAt") {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
    }
    f.box(fn(foot) {
      @sf.style_node(foot, fn() { sw_foot })
      foot.wraps(Is(Some(sw_foot_lines))) |> ignore
      @sf.words_node(foot, fn() {
        match checked() {
          None => @sf.t("web-main.versions.checkingVersions")
          Some(n) => @sf.t("web-main.versions.lastChecked", args=[("time", @settings.short_date_time(n))])
        }
      }, fn() { sw_foot_words })
      |> ignore
      foot.show(fn() { software_failed.get(station) is Some(_) }, fn(w) {
        @sf.words_node(w, fn() { software_failed.get(station).unwrap_or("") }, fn() { sw_failed_line }) |> ignore
      })
      foot.show(fn() { checked() is Some(_) }, fn(w) {
        let checking = fn() { is_doing(core, ["software.check"], [("station", station)]) }
        w.box(fn(k) {
          @sf.style_node(k, fn() { sw_check })
          @sf.presses_node(k, fn() { software_call(core, station, "software.check", []) }, on=fn() { !checking() })
          k.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.versions.check"))) })) |> ignore
          @sf.words_node(k, fn() {
            if checking() {
              @sf.t("web-main.versions.checking")
            } else {
              @sf.t("web-main.versions.check")
            }
          }, fn() { if @sf.lit_node(k) && !checking() { sw_check_lit } else { sw_check_words } })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// One piece of software (software_row's): its mark; its name and what is newer with updating it on its first line;
/// its version (what more there is of it beside it, under the hand), what an update under way or done says, why it
/// cannot be updated and the station's own
/// switches (its channel, updating by itself, for its managers) under them, as wide as its words.
fn software_row_node(
  row : @view.View,
  core : Core,
  station : String,
  v : () -> Json?,
  manager : Bool,
  busy : () -> Bool,
  beta : () -> Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let id = text(@signals.untracked(v), "id")
  let own = id == "station"
  let switches = fn() { own && manager && ((beta() && has(v(), "channel")) || has(v(), "auto")) }
  let call = fn(name : String, params : Array[(String, Json)]) { software_call(core, station, name, params) }
  @sf.item_row_node(row, fn(r) {
    r.box(fn(m) {
      @sf.style_node(m, fn() { sw_mark })
      if own {
        m.pick(fn() { @sf.theme().dark }, fn(k, dark) {
          @sf.drawable_node(k, if dark { "stillfail_mark_dark" } else { "stillfail_mark" }, sw_glyph) |> ignore
        })
      } else {
        @sf.maker_mark_node(m, "", id, sw_glyph) |> ignore
      }
    })
    |> ignore
    @sf.row_lines_node(r, spaced=true, fn(h) {
      h.box(fn(n) {
        @sf.style_node(n, fn() { sw_name_line.then(sw_name_grow) }, in_row=true)
        n.min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(n, fn() { text(v(), "name") }, fn() { sw_name }) |> ignore
        n.show(fn() { text(v(), "channel") == "beta" && !switches() }, fn(t) {
          t.box(fn(tag) {
            @sf.style_node(tag, fn() { sw_beta })
            @sf.words_node(tag, fn() { @sf.t("web-main.versions.beta") }, fn() { sw_beta_words }) |> ignore
          })
          |> ignore
        })
      })
      |> ignore
      h.pick(fn() { software_end(v()) }, fn(e, end) {
        @sf.style_node(e, fn() { sw_rest })
        software_end_node(e, end, v, manager, busy, call)
      })
    }, fn(u) {
      u.box(fn(vb) {
        @sf.style_node(vb, fn() { sw_version_box })
        vb.points(Is(true)) |> ignore
        @sf.words_node(vb, fn() { text(v(), "shownText") }, fn() { sw_version }) |> ignore
        if text(@signals.untracked(v), "tipText") != "" {
          @sf.tip_node(tips, vb, fn() { text(v(), "tipText") }) |> ignore
        }
      })
      |> ignore
      // what it says of an update under way or done: a sentence, on a line of its own under its version, never beside
      // its name, which it would squeeze there on a narrow page
      u.show(fn() { software_said(v()) != "" }, fn(w) {
        @sf.words_node(w, fn() { software_said(v()) }, fn() { sw_note }) |> ignore
      })
      u.show(fn() { text(v(), "note") != "" }, fn(w) { @sf.words_node(w, fn() { text(v(), "note") }, fn() { sw_note }) |> ignore })
      u.show(fn() { text(v(), "state") == "failed" && text(v(), "message") != "" }, fn(w) {
        @sf.words_node(w, fn() { text(v(), "message") }, fn() { sw_note }) |> ignore
      })
      // the station's own: which releases it takes, and whether it takes them by itself
      u.show(switches, fn(w) {
        w.box(fn(sw) {
          @sf.style_node(sw, fn() { sw_switches })
          sw.show(fn() { beta() && has(v(), "channel") }, fn(l) {
            software_switch_node(
              l,
              tips,
              fn() { @sf.t("web-main.versions.beta") },
              fn() { @sf.t("web-main.versions.betaStation") },
              fn() { text(v(), "channel") == "beta" },
              fn(now) { call("software.channel", [("channel", str(if now { "beta" } else { "stable" }))]) },
              fn() { is_doing(core, ["software.channel"], [("station", station)]) },
              busy,
              fn() { @sf.t("web-main.versions.betaNote") },
            )
          })
          sw.show(fn() { has(v(), "auto") }, fn(l) {
            software_switch_node(
              l,
              tips,
              fn() { @sf.t("web-main.versions.auto") },
              fn() { @sf.t("web-main.versions.auto") },
              fn() { flag(v(), "auto") },
              fn(now) { call("software.auto", [("on", Json::boolean(now))]) },
              fn() { is_doing(core, ["software.auto"], [("station", station)]) },
              busy,
              fn() { @sf.t(if flag(v(), "idleOnly") { "web-main.versions.autoIdleTip" } else { "web-main.versions.autoTip" }) },
            )
          })
        })
        |> ignore
      })
    })
  })
}

///|
/// What a piece of software has at its first line's end, by how it stands (software_row's): updating (how far, what it
/// says under its version), failed (why, trying again), to repair, to install, newer (updating to it), a way back to the
/// stable release; nothing.
fn software_end(v : Json?) -> String {
  let state = text(v, "state")
  if state == "updating" {
    "updating"
  } else if state == "failed" {
    "failed"
  } else if flag(v, "repairable") {
    "repair"
  } else if !flag(v, "installed") {
    "install"
  } else if flag(v, "newer") && text(v, "latest") != "" {
    "newer"
  } else if flag(v, "downgrade") && text(v, "latest") != "" {
    "downgrade"
  } else {
    ""
  }
}

///|
/// What a piece of software says of its update under its version (software_row's): how one under way goes, or, with
/// nothing else at its first line's end, that one is done.
fn software_said(v : Json?) -> String {
  match software_end(v) {
    "updating" => text(v, "updatingText")
    "" => text(v, "done")
    _ => ""
  }
}

///|
/// What software_end says is at its first line's end, made in `e`: its words, and the button that does it (where its
/// managers may: updating it, or repairing it where that is what it needs; not again while that is under way).
fn software_end_node(
  e : @view.View,
  end : String,
  v : () -> Json?,
  manager : Bool,
  busy : () -> Bool,
  call : (String, Array[(String, Json)]) -> Unit,
) -> Unit {
  let id = text(@signals.untracked(v), "id")
  let button = fn(label : () -> String, primary : Bool) {
    if manager && flag(@signals.untracked(v), "updatable") {
      @sf.button_node(e, label, fn() { call("software.update", [("id", str(id))]) }, tone=if primary { Primary } else { Plain }, disabled=busy)
      |> ignore
    }
  }
  let repair = fn(label : () -> String) {
    if manager && flag(@signals.untracked(v), "repairable") {
      @sf.button_node(e, label, fn() { call("software.update", [("id", str(id)), ("repair", Json::boolean(true))]) }, tone=Primary, disabled=busy)
      |> ignore
    }
  }
  let words = fn(said : () -> String, look : @ui.TextStyle) { @sf.words_node(e, said, fn() { look }) |> ignore }
  match end {
    "updating" => {
      e.show(fn() { field(v(), "percent") is Some(Number(_, ..)) }, fn(b) {
        b.box(fn(bar) {
          bar.width(Is(Some(sw_progress_w))) |> ignore
          @sf.progress_node(bar, fn() { Some(number(v(), "percent") / 100.0) }, fn() { @ui.tree_theme().line }, fn() {
            @sf.theme().p.accent
          })
          |> ignore
        })
        |> ignore
      })
    }
    "failed" => {
      words(fn() { text(v(), "failedText") }, sw_failed)
      if flag(@signals.untracked(v), "repairable") {
        repair(fn() { @sf.t("common.retry") })
      } else {
        button(fn() { @sf.t("common.retry") }, false)
      }
    }
    "repair" => repair(fn() { @sf.t("web-main.versions.repairNpm") })
    "install" => button(fn() { @sf.t("web-main.versions.install") }, false)
    "newer" => {
      words(fn() { text(v(), "latest") }, sw_newer)
      button(fn() { @sf.t("web-main.versions.update") }, true)
    }
    "downgrade" => {
      words(fn() { text(v(), "latest") }, sw_newer)
      button(fn() { @sf.t("web-main.versions.backToStable") }, false)
    }
    _ => ()
  }
}

///|
/// One of the station's own switches under its version (software_row's): its `word`, a small switch (read out
/// `label`), on as `on` says, `turn` told what it is to be; a ring before it while what it set is on its way (`doing`),
/// not turned while the station's software is (`busy`); what it means (`tip`) beside it under the hand.
fn software_switch_node(
  l : @view.View,
  tips : @sf.TipLayer,
  word : () -> String,
  label : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  doing : () -> Bool,
  busy : () -> Bool,
  tip : () -> String,
) -> Unit {
  l.box(fn(line) {
    @sf.style_node(line, fn() { sw_switch_line })
    line.points(Is(true)) |> ignore
    @sf.words_node(line, word, fn() { sw_switch_word }) |> ignore
    line.show(doing, fn(s) { @sf.spinner_node(s, size=@sf.spinner_inline) |> ignore })
    @sf.switch_node(line, on, turn, label, small=true, disabled=fn() { busy() || doing() })
    @sf.tip_node(tips, line, tip) |> ignore
  })
  |> ignore
}

///|
/// What the machine is (station_machine's 设备信息): a quiet row each, its label beside it; while it is not read, that
/// it is being read, or away that it cannot be.
fn station_device_node(b : @view.View, s : () -> Json?) -> Unit {
  let host = fn() {
    match field(s(), "host") {
      Some(Object(_)) as h => h
      _ => None
    }
  }
  st_section_node(b, fn() { @sf.t("web-pages.stations.device") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.pick(fn() { host() is Some(_) }, fn(p, known) {
        if known {
          let rows = fn() {
            let out : Array[(String, String)] = items(host(), "details").map(fn(d) { (text(Some(d), "label"), text(Some(d), "value")) })
            out
          }
          @sf.block_node(p, fn(k) { host_details_node(k, rows) })
        } else {
          said_row_node(p, fn() {
            if flag(s(), "online") {
              @sf.t("web-pages.stations.deviceLoading")
            } else {
              @sf.t("web-pages.stations.deviceOffline")
            }
          })
        }
      })
    })
  })
}

///|
/// The rest of a machine (host_details'), a quiet row each: its label beside it, quieter.
fn host_details_node(k : @view.View, rows : () -> Array[(String, String)]) -> Unit {
  let numbered = fn() { rows().mapi(fn(i, r) { (i, r) }) }
  k.box(fn(grid) {
    @sf.style_node(grid, fn() { hd_grid })
    grid.box(fn(labels) {
      @sf.style_node(labels, fn() { hd_labels }, in_row=true)
      labels.each(numbered, fn(x) { x.0 }, fn(l, x) { @sf.words_node(l, fn() { x.get().1.0 }, fn() { hd_label }) |> ignore })
    })
    |> ignore
    grid.box(fn(values) {
      @sf.style_node(values, fn() { hd_values }, in_row=true)
      values.min_width(Is(Some(0.0))) |> ignore
      values.each(numbered, fn(x) { x.0 }, fn(l, x) { @sf.words_node(l, fn() { x.get().1.1 }, fn() { hd_value }) |> ignore })
    })
    |> ignore
  })
  |> ignore
}

// ── styles ──────────

///|
/// The machine's figures in its block (station_overview's: @sf.block's 12 apart).
// kept across runs: a value (no field of it changes)
let st_resources_in : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A program's mark's side in its row (station_logins' 20).
let lg_mark_glyph : Double = 20.0

///|
/// A footed card's buttons at its end (card_foot's at_end: pg_card_foot_end).
// kept across runs: a value (no field of it changes)
let st_env_foot : @ui.Style = @ui.css("row w=Full gap=S2 justify=JEnd align=ACenter")

///|
/// The software's foot's lines apart where checking again goes under (software_list's line_gap).
let sw_foot_lines : Double = 4.0
