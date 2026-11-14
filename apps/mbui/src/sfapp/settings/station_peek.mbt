// A station's card, from a chat's agent: whether it
// is up and what its agents do, its machine and network at a glance, and where to go on: its files where it lends some,
// its page.

///|
/// The card of the station at `address` (`ws/station`) over the page: the library's panel, titled its name, opened
/// `from` what was pressed (its tag in a chat's bar: a sheet with touch short of Large, else beside it), what it holds
/// nodes of the window's tree made once as it opens (@sf.panel_nodes), with the frame's core (panels_core: as it is
/// said, where it was put up before it was, a fixture's).
pub fn open_station_peek(address : String, from~ : @sf.Anchor) -> Unit {
  @sf.panel_nodes(
    "",
    fn(v, close) {
      // (with the frame's core as it is said: made with it as one comes (put up before it was said: coming in then, as
      // anything coming down a column does), made again with another workspace's as that one is said; none, nothing)
      v.pick(fn() { panels_core.get().map(fn(p) { p.0 }) }, fn(b, workspace) {
        match (workspace, panels_core_as_is()) {
          (Some(_), Some(core)) => station_peek_node(b, core, address, close)
          _ => ()
        }
      })
    },
    from~,
    live=fn() {
      match panels_core_now() {
        Some(core) => (peek_name(core, address), "", "")
        None => ("", "", "")
      }
    },
  )
}

///|
/// The same card over where a chat names its station while the pointer rests there (ChatPage.tsx StationHover, its
/// StationPeek in a small panel: the station's part of its agent's tile, the chat's station beside its title): how it
/// is (its dot, its mark, its name) and what it says of itself, the machine in brief, then where to go on from it, rows
/// at the card's padding (peekLink). Drawn in a hover card that pads nothing itself (@sfpages.hover `padded` false).
/// The app draws it no more (a chat's bar is nodes: station_peek_card_node's); held by the node cards' comparison tests
/// (sfpages' peek_cards_node_wbtest, agent_card_node_wbtest).
pub fn station_peek_card(c : @ui.Ctx, address : String) -> Unit {
  guard panels_core_as_is() is Some(core) else { return }
  let s = peek_station(core, address)
  let t = @sf.theme()
  c.box(style=peek_card, fn() {
    c.box(style=peek_card_words, fn() {
      c.box(style=peek_card_head, fn() {
        // the same dot as on its tile in the chat's bar: how this device reaches it, not only whether it is up
        @sf.status_dot(c, match station_via(s) {
          "direct" => "online"
          "relay" => "busy"
          "offline" => "error"
          "waiting" => "waiting"
          // up, how it is reached not read yet
          _ => "online"
        })
        if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
          @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), peek_card_mark, t.p.muted)
        }
        c.text(peek_name(core, address), style=peek_card_name) |> ignore
      })
      |> ignore
      if s is Some(_) {
        c.text(text(s, "summary"), style=peek_said) |> ignore
        if flag(s, "online") {
          peek_figures(c, core, s)
        } else {
          c.text(peek_down(s), style=peek_said) |> ignore
        }
      }
    })
    |> ignore
    peek_ways(c, core, address, s, fn() { })
  })
  |> ignore
}

///|
/// The same card under another's in one card (a tablet's agent tile held: its agent's card over it), its head as an
/// agent card's so the two start alike (the user, 2026-10-27: 最好有个一致的开头好视觉分割): its mark on a square 28 of
/// the neutral ground, its name beside it; under them a dot in its tone (online or not) and what it says of itself;
/// then its machine at a glance and where to go on, as the card has them.
/// The app draws it no more (a chat's bar is nodes: station_peek_part_node's); held by the node cards' comparison tests
/// (sfpages' peek_cards_node_wbtest, agent_card_node_wbtest).
pub fn station_peek_part(c : @ui.Ctx, address : String) -> Unit {
  guard panels_core_as_is() is Some(core) else { return }
  let s = peek_station(core, address)
  let t = @sf.theme()
  let online = flag(s, "online")
  c.box(style=peek_card, fn() {
    c.box(style=peek_card_words, fn() {
      c.box(style=peek_part_head, fn() {
        c.box(style=peek_part_square.then(@ui.style(radius=@sf.small_radius)), fn() {
          if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
            @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), peek_card_mark, t.p.text)
          } else {
            // (none of its own: its name's first letter)
            let name = peek_name(core, address)
            if name.length() > 0 {
              c.text(name.clamped_view(end=1).to_owned(), style=peek_part_name) |> ignore
            }
          }
        })
        |> ignore
        c.text(peek_name(core, address), style=peek_part_name) |> ignore
      })
      |> ignore
      if s is Some(_) {
        let said = if online { text(s, "summary") } else { peek_down(s) }
        c.box(style=peek_part_status, fn() {
          c.box(style=peek_part_dot_room, fn() {
            c.box(style=peek_part_dot.then(@ui.style(bg=if online { Positive } else { Subtle })), fn() {  }) |> ignore
          })
          |> ignore
          c.text(said, style=peek_part_words) |> ignore
        })
        |> ignore
        if online {
          peek_figures(c, core, s)
        }
      }
    })
    |> ignore
    peek_ways(c, core, address, s, fn() { })
  })
  |> ignore
}

///|
/// Its head as an agent card's: its mark's square and its name, 10 apart, in their middle.
// kept across runs: a value (no field of it changes)
let peek_part_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// Its mark's square: 28, the neutral ground, its mark in its middle (an agent card's mark's: agent_mark's tile).
// kept across runs: a value (no field of it changes)
let peek_part_square : @ui.Style = @ui.css("w=S7 h=S7 bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let peek_part_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
/// Where it stands, as an agent card's: a dot 6 across 6 down, 6 before its words, 2 in.
// kept across runs: a value (no field of it changes)
let peek_part_status : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart pl=S0_5")

///|
// kept across runs: a value (no field of it changes)
let peek_part_dot_room : @ui.Style = @ui.css("pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let peek_part_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let peek_part_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, max_lines=3)

///|
/// The hover card's: its words 10 in from its padding, 8 apart, its rows at its padding.
// kept across runs: a value (no field of it changes)
let peek_card : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let peek_card_words : @ui.Style = @ui.css("w=Full p=S2_5 gap=S2")

///|
/// Its dot, its mark and its name in a line, 8 apart.
// kept across runs: a value (no field of it changes)
let peek_card_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
let peek_card_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let peek_card_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// The station's name, as the workspace's stations say it once they are read: none before (its id is no name, not
/// said in its place meanwhile); its id only where they are read and give it none (not among them, or unnamed).
fn peek_name(core : Core, address : String) -> String {
  peek_name_of((core.topic)("stations", { "scope": str(peek_scope(address)) }).get().value, address)
}

///|
/// The station's name (peek_name's), of the workspace's stations as the core says them (`stations`).
fn peek_name_of(stations : Json?, address : String) -> String {
  guard stations is Some(_) else { return "" }
  match text(peek_station_of(stations, address), "name") {
    "" => station_name(address)
    name => name
  }
}

///|
/// The card's body: its words, then its rows, 10 apart.
// kept across runs: a value (no field of it changes)
let peek_body : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// Its rows, as far apart as its words and them (peek_body).
// kept across runs: a value (no field of it changes)
let peek_rows : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// Its words, 10 apart.
// kept across runs: a value (no field of it changes)
let peek_words : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// What it says of itself, and that it is offline (13 on 18, muted).
// kept across runs: a value (no field of it changes)
let peek_said : @ui.TextStyle = @sf.meta.then(@sf.full_words)

///|
/// A station down, why and what comes of it, as the core says it: down for a security mode, why (its `blocked`); gone
/// for its update, that it comes back by itself (its first problem's words); else how to bring it back.
fn peek_down(s : Json?) -> String {
  let blocked = text(s, "blocked")
  if blocked != "" {
    return blocked
  }
  match field(s, "problems") {
    Some(Array([first, ..])) if text(Some(first), "key") == "updating" => text(Some(first), "text")
    _ => fill("android-settings.stations.offline", [("app", "still.fail")])
  }
}

///|
/// The station of `address` as its own page has it (`station`, of that station alone), once it is read.
fn peek_station(core : Core, address : String) -> Json? {
  match station_read_in(core, workspace_of(address), address).value {
    Some(Object(_)) as s => s
    _ => None
  }
}

///|
/// Where to go on from it: its files, where it has a drive, a way there from where it is named; its page.
fn peek_ways(c : @ui.Ctx, core : Core, address : String, s : Json?, close : () -> Unit) -> Unit {
  let screens = (core.topic)("screens", { "station": str(address) }).get().value
  @sf.submenu_row(c, "peek-screen/" + address, tr("android-misc.screen.section"), peek_screen_items(core, address, screens, close))
  match field(field(s, "overview"), "drive") {
    Some(Object(_)) as drive =>
      @sf.submenu_row(c, "peek-drive/" + address, tr("android-misc.drive.title"), peek_file_items(core, address, drive, close))
    _ => ()
  }
  @sf.menu_item(c, tr("android-chat.station.details"), key="peek-station/" + address, end="panel-open", on_press=fn() {
    close()
    (core.push)(Station(address))
  })

}

///|
/// The tab of each station's browser a person looked at last, here (the viewer says it as it shows one): what 浏览器
/// opens to next.
let browser_tabs_seen : Map[String, String] = Map([])

///|
/// The viewer shows tab `screen` of station `address`'s browser: 浏览器 opens to it next.
pub fn browser_tab_seen(address : String, screen : String) -> Unit {
  if browser_tabs_seen.get(address) != Some(screen) {
    browser_tabs_seen[address] = screen
  }
}

///|
/// How many tabs this run made (one more each): a new tab's id is worked out of it with the station's tabs.
let tabs_made : Ref[Int] = Ref(0)

///|
/// A new tab of station `address`'s browser (＋, ⌘T, 浏览器 with none open): its id made here (`u_` and 12 hex digits,
/// a hash of the station, the tabs it has (`listed`, their screen ids: none of them again) and this run's count),
/// asked of the station by it (`screen.openBrowser` with `id`), and its
/// screen (`browser:<id>`) answered at once, so its view opens as it is pressed, the core listing it till its station
/// does (the user, 2026-11-13: 「会等 station 开了这边才开，点个按钮要半天」).
pub fn new_browser_tab(
  call : (String, Json, (Result[Json, Json]) -> Unit) -> Unit,
  address : String,
  listed : Array[String],
  done : (Result[Json, Json]) -> Unit,
) -> String {
  let digits = "0123456789abcdef"
  let made = fn() {
    tabs_made.val += 1
    let n = @ui.stable_hash(address + "|" + listed.join(",") + "|\{tabs_made.val}")
    let hex = StringBuilder()
    for i = 11; i >= 0; i = i - 1 {
      hex.write_char(digits[((n >> (i * 4)) & 0xFL).to_int()].unsafe_to_char())
    }
    "u_" + hex.to_string()
  }
  let mut id = made()
  while listed.contains("browser:" + id) {
    id = made()
  }
  call("screen.openBrowser", obj([("station", str(address)), ("url", str("")), ("id", str(id))]), done)
  "browser:" + id
}

///|
/// 浏览器 (the station's page, its card's 屏幕, a chat's screens): the station's browser opened at once on the tab looked
/// at last, else its newest, else a new one; never a question first.
pub fn open_station_browser(core : Core, address : String, from? : @sf.Anchor = Unanchored) -> Unit {
  ignore(from)
  let listed = items((core.topic)("screens", { "station": str(address) }).get().value, "screens").filter(fn(sc) {
    flag(Some(sc), "userTab") || text(Some(sc), "id").has_prefix("browser:u_")
  }).map(fn(sc) { text(Some(sc), "id") })
  let screen = match browser_tab_to_open(address, listed) {
    Some(screen) => screen
    None =>
      new_browser_tab(core.call, address, listed, fn(r) {
        if r is Err(e) {
          (core.say)(fill("android-misc.act.failed", [("what", tr("web-pages.screen.openBrowserWhat")), ("error", error_text(e))]))
        }
      })
  }
  (core.open_screen)(address, screen)
}

///|
/// Of station `address`'s tabs (`listed`, its screen ids in the order opened), the one its browser opens to: the one looked
/// at last, else the newest; none where it has none.
pub fn browser_tab_to_open(address : String, listed : Array[String]) -> String? {
  let seen = browser_tabs_seen.get(address).unwrap_or("")
  if seen != "" && listed.contains(seen) {
    Some(seen)
  } else {
    listed.last()
  }
}

///|
/// Its screens as its card's 屏幕 offers them (`screens`, the core's for it): its browser (a person's own pages there, one
/// item opening it), agent pages, and physical/simulator screens; none, why (the core's note) or that it has none, not to be chosen.
fn peek_screen_items(core : Core, address : String, screens : Json?, close : () -> Unit) -> Array[@sf.MenuItem?] {
  let screen_items : Array[@sf.MenuItem?] = []
  let user_tabs : Array[Json] = []
  let agent_tabs : Array[Json] = []
  let other_screens : Array[Json] = []
  for screen in items(screens, "screens") {
    let sc = Some(screen)
    if flag(sc, "userTab") || text(sc, "id").has_prefix("browser:u_") {
      user_tabs.push(screen)
    } else if text(sc, "kind") == "browser" {
      agent_tabs.push(screen)
    } else {
      other_screens.push(screen)
    }
  }
  let can_open = flag(screens, "browser") && flag(screens, "control")
  let has_user = !user_tabs.is_empty() || can_open
  let groups = (if has_user { 1 } else { 0 }) +
    (if !agent_tabs.is_empty() { 1 } else { 0 }) +
    (if !other_screens.is_empty() { 1 } else { 0 })
  if !other_screens.is_empty() {
    if groups > 1 {
      screen_items.push(Some(@sf.menu_item_of(tr("android-misc.screen.section"), heading=true, fn() { })))
    }
    for screen in other_screens {
      let sc = Some(screen)
      let icon = if text(sc, "kind") == "simulator" { "phone" } else { "monitor" }
      screen_items.push(Some(@sf.menu_item_of(text(sc, "title"), icon~, fn() {
        close()
        (core.open_screen)(address, text(sc, "id"))
      })))
    }
  }
  if has_user {
    if !screen_items.is_empty() {
      screen_items.push(None)
    }
    screen_items.push(Some(@sf.menu_item_of(tr("web-pages.screen.browser"), icon="web", fn() {
      close()
      open_station_browser(core, address)
    })))
  }
  if !agent_tabs.is_empty() {
    if !screen_items.is_empty() {
      screen_items.push(None)
    }
    if groups > 1 {
      screen_items.push(Some(@sf.menu_item_of(tr("web-pages.screen.agentPages"), heading=true, fn() { })))
    }
    for screen in agent_tabs {
      let sc = Some(screen)
      screen_items.push(Some(@sf.menu_item_of(text(sc, "title"), icon="web", fn() {
        close()
        (core.open_screen)(address, text(sc, "id"))
      })))
    }
  }
  if screen_items.is_empty() {
    let note = text(screens, "note")
    screen_items.push(Some(@sf.menu_item_of(if note == "" { tr("web-pages.screen.none") } else { note }, disabled=true, fn() { })))
  }
  screen_items
}

///|
/// Its files as its card's 文件 offers them (`drive`, its overview's): all of them; where it lends only some folders,
/// under a heading each of those. Pressed, opened (the card closed first).
fn peek_file_items(core : Core, address : String, drive : Json?, close : () -> Unit) -> Array[@sf.MenuItem?] {
  let files : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(tr("web-pages.drive.viewAll"), icon="folder", fn() {
    close()
    (core.open_drive)(address)
  }))]
  let roots = items(drive, "roots")
  if !flag(drive, "anywhere") && !roots.is_empty() {
    files.push(None)
    files.push(Some(@sf.menu_item_of(tr("web-pages.drive.pinnedFolders"), heading=true, fn() { })))
    for root in roots {
      let r = Some(root)
      files.push(Some(@sf.menu_item_of(text(r, "name"), icon="folder", fn() {
        close()
        (core.open_folder)(address, text(r, "path"))
      })))
    }
  }
  files
}

///|
/// The machine in brief (StationFigures with `peek`), faded while it is reconnecting (as last heard).
// kept across runs: a value (no field of it changes)
let peek_figures_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let peek_figures_faded : @ui.Style = @ui.css("w=Full opacity=O45")

///|
/// What is left of it in the allowance's boxes: 4 over and under them.
// kept across runs: a value (no field of it changes)
let peek_meters_room : @ui.Style = @ui.css("w=Full py=S1")

///|
/// 20 high, 8 apart (MeterChips).
// kept across runs: a value (no field of it changes)
let peek_meters : @ui.Style = @ui.css("row w=Full h=S5 gap=S2 align=ACenter")

///|
/// It said what this core cannot read: no reading is on its way, so nothing shows as if one were.
fn unreadable(s : Json?) -> Bool {
  items(s, "problems").iter().any(fn(p) { text(Some(p), "key") == "incompatible" })
}

///|
/// A machine's CPU, memory and disk made up, for what shows while they are read (their chips in their bones).
fn sample_meters(c : @ui.Ctx, key : String) -> Unit {
  @sf.bones(c, fn() {
    c.box(style=peek_meters, fn() {
      for i, n in [50, 60, 40] {
        @sf.meter_chip(c, Some(obj([("short", str(@sf.sample_words(1))), ("remaining", str(@sf.sample_words(3))), ("left", Json::number(n.to_double()))])), key=key + "/sample" + i.to_string())
      }
    })
    |> ignore
  })
}

///|
/// Its network 6 under the boxes.
// kept across runs: a value (no field of it changes)
let peek_net : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
/// The machine in brief: what is left of it in the allowance's boxes (in their bones until it is read), its network
/// under them (`peek`).
fn peek_figures(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let host = field(s, "host")
  let net = station_net(core, s)
  c.box(style=if flag(s, "reconnecting") { peek_figures_faded } else { peek_figures_box }, fn() {
    c.box(style=peek_meters_room, fn() {
      match host {
        Some(Object(_)) =>
          c.box(style=peek_meters, fn() {
            @sf.meter_line(c, items(host, "meters"), key="station-peek/" + text(s, "station"))
          })
          |> ignore
        _ => if !unreadable(s) { sample_meters(c, "station-peek/" + text(s, "station")) }
      }
    })
    |> ignore
    c.box(style=peek_net, fn() {
      // the room under the 6, the bars laid over that alone (matchParentSize inside the Box's padding: a layer covers
      // its parent's padding too)
      c.box(style=@sf.full_width, fn() {
        // (until it is read, a made-up one's in its bones)
        match net {
          Some(_) => net_line(c, net)
          None => @sf.bones(c, fn() { net_line(c, None) })
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How this device reaches a station of the workspace's `stations`: `direct`,
/// `relay`, `waiting` (coming back, or a way still being chosen), `offline`, or "" while there is no reading of it.
/// One answer wherever a station's dot says it: its tile in a chat's bar, its card.
pub fn station_via(s : Json?) -> String {
  if !flag(s, "online") {
    "offline"
  } else if flag(s, "reconnecting") {
    "waiting"
  } else {
    match text(field(s, "way"), "via") {
      "direct" => "direct"
      "relay" => "relay"
      "choosing" => "waiting"
      _ => ""
    }
  }
}

///|
/// The card's body in node `v` (the panel's, made once as it opens), with `core`: what the station says of itself and,
/// up, its machine in brief (else why it is down), as its stations say it now; then where to go on, the panel's rows at
/// a dialog's foot (concentric with its foot corners there), their words on its line. Each part followed as what it
/// shows changes.
fn station_peek_node(v : @view.View, core : Core, address : String, close : () -> Unit) -> Unit {
  let stations = (core.topic)("stations", { "scope": str(peek_scope(address)) })
  let screens = (core.topic)("screens", { "station": str(address) })
  let net = (core.topic)("stationNet", { "station": str(address) })
  let s = fn() { peek_station_of(stations.get().value, address) }
  v.box(fn(b) {
    @sf.style_node(b, fn() { peek_body })
    b.show(fn() { s() is Some(_) }, fn(w) {
      // (its words as far in as its rows' words: a dialog's, a small panel's)
      @sf.style_node(w, fn() { peek_words.then(@sf.panel_words_in_node(w)) })
      @sf.words_node(w, fn() { text(s(), "summary") }, fn() { peek_said }) |> ignore
      // (what its agents' processes are is on its page, a tap away)
      w.pick(fn() { flag(s(), "online") }, fn(x, online) {
        if online {
          peek_figures_node(x, s, fn() { station_net_of(net.get().value) })
        } else {
          @sf.words_node(x, fn() { peek_down(s()) }, fn() { peek_said }) |> ignore
        }
      })
    })
    // where to go on: the panel's rows, their grounds out across its sides, their words on its line (in a dialog, at
    // its foot: concentric with its foot corners)
    @sf.dialog_foot_rows_node(b, peek_rows, fn(r) {
      @sf.submenu_row_node(r, fn() { tr("android-misc.screen.section") }, fn() {
        peek_screen_items(core, address, screens.get().value, close)
      })
      r.show(fn() { field(field(s(), "overview"), "drive") is Some(Object(_)) }, fn(d) {
        @sf.submenu_row_node(d, fn() { tr("android-misc.drive.title") }, fn() {
          peek_file_items(core, address, field(field(s(), "overview"), "drive"), close)
        })
      })
      @sf.panel_row_node(r, fn() { tr("android-chat.station.details") }, fn() {
        close()
        (core.push)(Station(address))
      }, end="panel-open", plain=true)
    })
  })
  |> ignore
}

///|
/// The workspace of station `address` (`ws/station`).
fn peek_scope(address : String) -> String {
  match address.find("/") {
    Some(i) => address.exact_view(end=i).to_owned()
    None => address
  }
}

///|
/// The station of `address` in the workspace's stations as the core says them (`stations`), once they are read.
fn peek_station_of(stations : Json?, address : String) -> Json? {
  match stations {
    Some(Array(a)) =>
      for x in a {
        if text(Some(x), "station") == address {
          return Some(x)
        }
      }
    _ => ()
  }
  None
}

///|
/// How this device reaches a station now, as its `stationNet` view says it (station_net's): none before a connection of
/// its own is open.
fn station_net_of(v : Json?) -> Json? {
  match v {
    Some(Object(_)) => v
    _ => None
  }
}

///|
/// The machine in brief (peek_figures', as nodes) in `p`, station `s` and its network `net` as they are now: what is
/// left of it in the allowance's boxes (in their bones until it is read, none where it said what this core cannot
/// read), its network under them (in its bones until it is read); faded while it is reconnecting.
fn peek_figures_node(p : @view.View, s : () -> Json?, net : () -> Json?) -> Unit {
  p.box(fn(f) {
    @sf.style_node(f, fn() { peek_figures_box })
    f.alpha(By(fn() { if flag(s(), "reconnecting") { peek_faded } else { 1.0 } })) |> ignore
    f.box(fn(m) {
      @sf.style_node(m, fn() { peek_meters_room })
      // (read: its chips; not yet: made-up ones in their bones; what this core cannot read: none)
      let way = fn() {
        match field(s(), "host") {
          Some(Object(_)) => 1
          _ => if unreadable(s()) { 0 } else { 2 }
        }
      }
      // (one in the other's place: the chips read in their bones' place, from as tall as those were)
      m.pick(way, fn(x, k) {
        match k {
          1 =>
            x.box(fn(r) {
              @sf.style_node(r, fn() { peek_meters })
              @sf.meter_line_node(r, fn() { items(field(s(), "host"), "meters") }, in_row=true)
            })
            |> ignore
          2 => sample_meters_node(x)
          _ => ()
        }
      })
    })
    |> ignore
    f.box(fn(n) {
      @sf.style_node(n, fn() { peek_net })
      // (the room under the 6, the bars laid over that alone)
      n.box(fn(w) {
        @sf.style_node(w, fn() { @sf.full_width })
        // (until it is read, a made-up one's in its bones)
        w.pick(fn() { net() is Some(_) }, fn(x, read) {
          if read {
            net_line_node(x, net)
          } else {
            @sf.waiting_node(x, fn(b) { net_line_node(b, fn() { None }) })
          }
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How faint the machine in brief is while it is reconnecting (peek_figures_faded's O45).
let peek_faded : Double = 0.45

///|
/// A machine's CPU, memory and disk made up, in their bones (sample_meters', as nodes), in `p`.
fn sample_meters_node(p : @view.View) -> Unit {
  @sf.waiting_node(p, fn(b) {
    b.box(fn(r) {
      @sf.style_node(r, fn() { peek_meters })
      for n in [50, 60, 40] {
        @sf.fill_chip_node(r, fn() { 100 - n }, fn() { "" }, fn() { @sf.sample_words(1) }, fn() { @sf.sample_words(3) }) |> ignore
      }
    })
    |> ignore
  })
}

///|
/// This device's connection to a station (net_line's, as nodes) in `p`, as `net` says it now (none: a made-up one, to
/// be drawn in its bones, its words in Chinese): how it goes (and packets lost) over its round trip on the left, cut
/// short before the figures are; on the right ↑ over ↓, the speed each way and what went that way.
fn net_line_node(p : @view.View, net : () -> Json?) -> Unit {
  let n = fn() {
    match net() {
      Some(_) as x => x
      None =>
        Some(
          obj([
            ("path", str("直连")),
            ("rtt", obj([("text", str("0 ms")), ("level", str("ok"))])),
            ("down", str("0.0 KB/s")),
            ("up", str("0.0 KB/s")),
          ]),
        )
    }
  }
  // (a figure's ink: its level's)
  let tone = fn(f : () -> Json?) {
    fn() {
      let t = @sf.theme()
      match text(f(), "level") {
        "red" => t.p.red
        "amber" => t.p.warn_ink
        _ => t.p.text
      }
    }
  }
  let muted = fn() { @sf.theme().p.muted }
  p.box(fn(row) {
    @sf.style_node(row, fn() { net_row })
    row.wraps(Is(Some(2.0))) |> ignore
    row.box(fn(left) {
      @sf.style_node(left, fn() { net_left }, in_row=true)
      left.box(fn(l) {
        @sf.style_node(l, fn() { net_path })
        net_words_node(l, fn() { text(n(), "path") }, muted)
        l.show(fn() { field(n(), "loss") is Some(Object(_)) }, fn(x) {
          net_words_node(x, fn() { text(field(n(), "loss"), "text") }, tone(fn() { field(n(), "loss") }), weight=500)
        })
      })
      |> ignore
      left.show(fn() { field(n(), "rtt") is Some(Object(_)) }, fn(x) {
        x.box(fn(l) {
          @sf.style_node(l, fn() { net_rtt }, in_row=true)
          net_words_node(l, fn() { "·" }, muted)
          net_words_node(l, fn() { tr("android-settings.stations.rtt") }, muted, cut=true)
          net_words_node(l, fn() { text(field(n(), "rtt"), "text") }, tone(fn() { field(n(), "rtt") }), weight=500)
        })
        |> ignore
      })
    })
    |> ignore
    row.box(fn(right) {
      @sf.style_node(right, fn() { net_right }, in_row=true)
      for way in [("↑", "up"), ("↓", "down")] {
        right.box(fn(l) {
          @sf.style_node(l, fn() { net_way })
          net_words_node(l, fn() { way.0 }, muted)
          net_words_node(l, fn() { text(n(), way.1) }, fn() { @sf.theme().p.text }, weight=500)
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Its line (net_line's): the left of it and ↑ / ↓, 10 apart, in their middle.
// kept across runs: a value (no field of it changes)
let net_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter justify=JBetween")

///|
/// Its left: how it goes and its round trip, 6 apart, taking what the right leaves.
// kept across runs: a value (no field of it changes)
let net_left : @ui.Style = @ui.css("row w=Cut gap=S1_5 align=ACenter")

///|
/// How it goes and packets lost, 6 apart.
// kept across runs: a value (no field of it changes)
let net_path : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let net_rtt : @ui.Style = @ui.css("row w=Cut gap=S1 align=ACenter")

///|
/// ↑ and ↓, 10 apart.
// kept across runs: a value (no field of it changes)
let net_right : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let net_way : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// Words of it (net_line's) in `p`: the meta's size on a line of 18, `weight`, in `ink`; `cut`: cut short where the
/// line has not the room for them.
fn net_words_node(p : @view.View, words : () -> String, ink : () -> Int64, weight? : Int = 400, cut? : Bool = false) -> Unit {
  p.box(fn(w) {
    if cut {
      w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    }
    w
    .words(By(words))
    .words_look(By(fn() { { size: @sf.theme().t.meta, weight, line: net_line_h, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 } }))
    .ink(By(ink))
    |> ignore
  })
  |> ignore
}

///|
/// Its lines' height (net_line's: 18).
// kept across runs: a value
let net_line_h : Double = 18.0
