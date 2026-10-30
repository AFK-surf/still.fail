// A station's card, from a chat's agent (ember apps/android settings/screens/Stations.kt openStationPeek): whether it
// is up and what its agents do, its machine and network at a glance, and where to go on: its files where it lends some,
// its page.

///|
/// The card of the station at `address` (`ws/station`) over the page: the library's panel, titled its name, opened
/// `from` what was pressed (its tag in a chat's bar: a sheet with touch short of Large, else beside it), drawn with
/// the frame's core as it is drawn (put up before a frame is, a fixture's, as well).
pub fn open_station_peek(address : String, from~ : @sf.Anchor) -> Unit {
  @sf.panel(
    "",
    fn(c, close) {
      match panels_core.val {
        Some(core) => station_peek(c, core, address, close)
        None => ()
      }
    },
    from~,
    live=fn() { (peek_name(address), "", "") },
  )
}

///|
/// The same card over where a chat names its station while the pointer rests there (ChatPage.tsx StationHover, its
/// StationPeek in a small panel: the station's part of its agent's tile, the chat's station beside its title): how it
/// is (its dot, its mark, its name) and what it says of itself, the machine in brief, then where to go on from it, rows
/// at the card's padding (peekLink). Drawn in a hover card that pads nothing itself (@sfpages.hover `padded` false).
pub fn station_peek_card(c : @ui.Ctx, address : String) -> Unit {
  guard panels_core.val is Some(core) else { return }
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
        c.text(peek_name(address), style=peek_card_name) |> ignore
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
pub fn station_peek_part(c : @ui.Ctx, address : String) -> Unit {
  guard panels_core.val is Some(core) else { return }
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
            let name = peek_name(address)
            if name.length() > 0 {
              c.text(name.view(end_offset=1).to_string(), style=peek_part_name) |> ignore
            }
          }
        })
        |> ignore
        c.text(peek_name(address), style=peek_part_name) |> ignore
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
/// Its head as an agent card's (AgentCard.css.ts head): its mark's square and its name, 10 apart, in their middle.
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
/// The hover card's: its words 10 in from its padding, 8 apart (Hover.css.ts card), its rows at its padding.
// kept across runs: a value (no field of it changes)
let peek_card : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let peek_card_words : @ui.Style = @ui.css("w=Full p=S2_5 gap=S2")

///|
/// Its dot, its mark and its name in a line, 8 apart (StationCards.css.ts peekHead).
// kept across runs: a value (no field of it changes)
let peek_card_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
let peek_card_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let peek_card_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// The station's name, as the workspace's stations say it once they are read.
fn peek_name(address : String) -> String {
  match panels_core.val {
    Some(core) =>
      match peek_station(core, address) {
        Some(_) as s => text(s, "name")
        None => station_name(address)
      }
    None => station_name(address)
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
/// The station of `address` in the workspace's stations, once they are read.
fn peek_station(core : Core, address : String) -> Json? {
  let ws = match address.find("/") {
    Some(i) => address.view(end_offset=i).to_owned()
    None => address
  }
  match (core.topic)("stations", { "scope": str(ws) }).value {
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
fn station_peek(c : @ui.Ctx, core : Core, address : String, close : () -> Unit) -> Unit {
  let s = peek_station(core, address)
  c.box(style=peek_body, fn() {
    if s is Some(_) {
      // (its words as far in as its rows' words: a dialog's, a small panel's)
      c.box(style=peek_words.then(@sf.panel_words_in()), fn() {
        c.text(text(s, "summary"), style=peek_said) |> ignore
        // what its agents' processes are is on its page, a tap away
        if flag(s, "online") {
          peek_figures(c, core, s)
        } else {
          c.text(peek_down(s), style=peek_said) |> ignore
        }
      })
      |> ignore
    }
    // where to go on: the panel's rows, their grounds out across its sides, their words on its line (in a dialog, at
    // its foot: concentric with its foot corners)
    @sf.dialog_foot_rows(c, peek_rows, fn() { peek_ways(c, core, address, s, close) })
  })
  |> ignore
}

///|
/// Where to go on from it: its files (docs/drive.md), where it has a drive, a way there from where it is named; its page.
fn peek_ways(c : @ui.Ctx, core : Core, address : String, s : Json?, close : () -> Unit) -> Unit {
  let screens = (core.topic)("screens", { "station": str(address) }).value
  let screen_items : Array[@sf.MenuItem?] = []
  for screen in items(screens, "screens") {
    let sc = Some(screen)
    screen_items.push(Some(@sf.menu_item_of(text(sc, "title"), icon=if text(sc, "kind") == "browser" { "web" } else { "monitor" }, fn() {
      close()
      (core.open_screen)(address, text(sc, "id"))
    })))
  }
  if screen_items.is_empty() {
    let note = text(screens, "note")
    screen_items.push(Some(@sf.menu_item_of(if note == "" { tr("web-pages.screen.none") } else { note }, disabled=true, fn() { })))
  }
  @sf.submenu_row(c, "peek-screen/" + address, tr("android-misc.screen.section"), screen_items)
  match field(field(s, "overview"), "drive") {
    Some(Object(_)) as drive => {
      let files : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(tr("web-pages.drive.viewAll"), icon="folder", fn() {
        close()
        (core.open_drive)(address)
      }))]
      let roots = items(drive, "roots")
      if !roots.is_empty() {
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
      @sf.submenu_row(c, "peek-drive/" + address, tr("android-misc.drive.title"), files)
    }
    _ => ()
  }
  if @sf.menu_item(c, tr("android-chat.station.details"), key="peek-station/" + address, end="panel-open") {
    close()
    (core.push)(Station(address))
  }

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
let peek_meters : @ui.Style = @ui.css("row h=S5 gap=S2 align=ACenter")

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
/// under them (Stations.kt StationFigures, `peek`).
fn peek_figures(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let host = field(s, "host")
  let net = station_net(core, s)
  c.box(style=if flag(s, "reconnecting") { peek_figures_faded } else { peek_figures_box }, fn() {
    c.box(style=peek_meters_room, fn() {
      match host {
        Some(Object(_)) =>
          c.box(style=peek_meters, fn() {
            for m in items(host, "meters") {
              let m = Some(m)
              @sf.meter_chip(c, m, key="station-peek/" + text(s, "station"))
            }
          })
          |> ignore
        _ => sample_meters(c, "station-peek/" + text(s, "station"))
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
/// How this device reaches a station of the workspace's `stations` (StationLink.tsx useStationLink): `direct`,
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
