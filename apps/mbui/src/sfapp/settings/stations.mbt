// The workspace's stations (settings/Stations.kt): a card each with its mark and what it is doing, what of its load
// runs low and its network; one station's page is the machine (its load large, its network, its details), with how
// many connects and profiles run on it and its memory. Its owners and admins rename it (`workspace.renameStation`),
// pick its mark or take it out from its "…" (Settings.kt openStationMenu).

///|
/// Where a station this workspace joined is at home (Stations.kt joinedMark), as grey words before what is said of it.
fn joined_mark(s : Json?) -> String {
  if !flag(s, "joined") {
    return ""
  }
  match opt_text(s, "home") {
    Some(h) => fill("web-pages.stations.joinedFrom", [("name", h)])
    None => tr("web-pages.stations.joinedElsewhere")
  }
}

///|
/// A station's mark where it has one (StationMark): its glyph, picture or emoji.
fn station_mark(c : @ui.Ctx, s : Json?, size : Double, tint : Int64) -> Unit {
  let emoji = text(s, "emoji")
  let icon = text(s, "icon")
  if @sf.has_station_mark(emoji, icon) {
    @sf.station_mark(c, emoji, icon, size, tint)
  }
}

///|
/// The workspace's stations (StationsScreen), pushed from settings: their cards, each opening its page.
fn stations_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = stations_of(core, here)
  let list = match topic.value {
    Some(Array(a)) => Some(a)
    _ => None
  }
  // adding one: its owners' and admins' ＋ (the bar's notch at the stack's root)
  let add = match place_action(core, here, "stations") {
    Some(run) => Some(("add-station", run))
    None => None
  }
  place_page(c, core, tr("android-misc.bar.place.stations"), primary?=add, fn() {
    let blocks : Array[() -> Unit] = []
    match list {
      None =>
        blocks.push(fn() {
          waiting_cards(
            c,
            fn() {
              for i, n in [5, 3, 7] {
                station_card(c, core.quiet(), {
                  "station": Json::string("sample/" + i.to_string()),
                  "name": Json::string(@sf.sample_words(n)),
                  "online": true,
                  "summary": Json::string(@sf.sample_words(12)),
                })
              }
            },
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        })
      Some(a) if a.length() == 0 => blocks.push(fn() { first_station(c, core, here) })
      Some(a) => {
        for st in a {
          blocks.push(fn() { station_card(c, core, st) })
        }
      }
    }
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "stations", blocks)
  })
}

///|
/// A card's head on this page (a station's, the agents at work's): its mark 28 across, its name and what is said of it
/// under it (`said`: its line, even empty; none, no line), 12 from the mark; what stands at its end (a chevron).
fn card_head(c : @ui.Ctx, mark : () -> Unit, name : String, said : String?, end : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
    // In a box as large whatever it is: an emoji is drawn wider than an icon, and the names line up.
    c.box(w=Px(card_mark), h=Px(card_mark), align=ACenter, justify=JCenter, mark) |> ignore
    c.box(w=Fill(1.0), fn() {
      c.text(name, size=t.t.title, weight=700, color=t.p.text, wrap=false, line=22.0) |> ignore
      match said {
        Some(line) => c.text(line, size=t.t.meta, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
        None => ()
      }
    })
    |> ignore
    end()
  })
  |> ignore
}

///|
/// A card's mark's side.
let card_mark : Double = 28.0

///|
/// A station in the list: its mark (the server's where it has none), its name, what is said of it, and its body (StationBody).
fn station_card(c : @ui.Ctx, core : Core, st : Json) -> Unit {
  let t = @sf.theme()
  let s = Some(st)
  let address = text(s, "station")
  if card(c, key="station/" + address, fn() {
      let emoji = text(s, "emoji")
      let icon = text(s, "icon")
      card_head(
        c,
        fn() {
          if @sf.has_station_mark(emoji, icon) {
            @sf.station_mark(c, emoji, icon, card_mark, t.p.text)
          } else {
            @sf.icon(c, "server", size=card_mark, color=t.p.text) |> ignore
          }
        },
        text(s, "name"),
        Some(join([joined_mark(s), text(s, "summary")], " · ")),
        fn() {
          if flag(s, "reconnecting") {
            reconnecting(c)
          }
          chevron(c)
        },
      )
      station_body(c, core, s)
    }) {
    (core.push)(Station(address))
  }
}

///|
/// How this device reaches station `s` now, its figures (Stations.kt rememberStationNet: the `stationNet` view, sampled
/// while shown; none before a connection of its own is open).
fn station_net(core : Core, s : Json?) -> Json? {
  // (the view's null: no connection of this device's own open yet, as none; Stations.kt's StationNet?)
  match (core.topic)("stationNet", { "station": str(text(s, "station")) }).value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// Up but not reached just now (Stations.kt Reconnecting): what shows of it is from before.
fn reconnecting(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, gap=5.0, align=ACenter, fn() {
    spinner(c, inline=true)
    c.text(tr("common.reconnecting"), size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore
  })
  |> ignore
}

///|
/// Under a station's name in the list (StationBody): what of its load runs low and its network, in the same room
/// whatever state it is in; offline, its picture asleep and a line saying so; not read yet, grey bars.
fn station_body(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let t = @sf.theme()
  let online = flag(s, "online")
  // (a host the core says is null as none: not read yet)
  let host = match field(s, "host") {
    Some(Object(_)) as h if online => h
    _ => None
  }
  let net = if online { station_net(core, s) } else { None }
  let faded = flag(s, "reconnecting")
  c.box(style=station_body_box, fn() {
    // the room under the 10: what is laid over it covers that alone (StationBody's matchParentSize inside the Box's
    // padding; a layer covers its parent's padding too)
    c.box(style=@sf.full_width, fn() {
      // the boxes of what runs low; not read yet, grey bars over their room
      c.box(style=@sf.full_width, fn() {
        c.box(style=seen(peek_meters, host is Some(_), faded), fn() {
          for m in items(host, "meters") {
            if text(Some(m), "level") != "ok" {
              @sf.meter_chip(c, Some(m), key="station-body/" + text(s, "station"))
            }
          }
        })
        |> ignore
        if online && host is None {
          c.layer(fn() { sample_meters(c, "station-body/" + text(s, "station")) }) |> ignore
        }
      })
      |> ignore
      // its network 10 under them; not read yet, grey bars centred across its line's room
      c.box(style=station_body_net, fn() {
        c.box(style=@sf.full_width, fn() {
          c.box(style=seen(@sf.full_width, net is Some(_), faded), fn() { net_line(c, net) }) |> ignore
          if online && net is None {
            c.layer(fn() { @sf.bones(c, fn() { net_line(c, None) }) }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      if !online {
        c.layer(fn() {
          c.box(style=offline_row, fn() {
            let pic = if t.dark { "illus_station_offline_dark" } else { "illus_station_offline" }
            if @sf.has_drawable(pic) {
              // as tall as the room (fillMaxHeight), as wide as that keeps it
              @sf.drawable(c, pic, offline_picture_w) |> ignore
            }
            c.text(
              tr("android-settings.stations.silent"),
              size=t.t.meta,
              color=t.p.muted,
              w=Fill(1.0),
              line=18.0,
              max_lines=3,
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// `style` as shown: unseen while what it shows is not known yet (laid out keeping its room), faded while the station
/// is reconnecting (as last heard).
fn seen(style : @ui.Style, known : Bool, faded : Bool) -> @ui.Style {
  if !known {
    style.then(unseen)
  } else if faded {
    style.then(faded_look)
  } else {
    style
  }
}

///|
// kept across runs: a value (no field of it changes)
let unseen : @ui.Style = @ui.css("opacity=O0")

///|
// kept across runs: a value (no field of it changes)
let faded_look : @ui.Style = @ui.css("opacity=O45")

///|
/// Under a station's name, 10 down (StationBody's padding).
// kept across runs: a value (no field of it changes)
let station_body_box : @ui.Style = @ui.css("w=Full pt=S2_5")

///|
/// Its network, 10 under the boxes of what runs low.
// kept across runs: a value (no field of it changes)
let station_body_net : @ui.Style = @ui.css("w=Full pt=S2_5")

///|
/// Offline: its picture and a line saying so, centred across the room, 12 apart.
// kept across runs: a value (no field of it changes)
let offline_row : @ui.Style = @ui.css("row w=Full h=Full gap=S3 align=ACenter")

///|
/// The offline picture's width in a station's card: the room's height (the load's 20, 10, the network's two lines of 18
/// 2 apart: 68) times the picture's 2:1.
let offline_picture_w : Double = 136.0

///|
fn clamp(n : Int) -> Int {
  if n < 0 {
    0
  } else if n > 100 {
    100
  } else {
    n
  }
}

///|
/// A machine's CPU, memory and disk (components.tsx MeterChips), each a chip (MeterChip) with what it is in its tip;
/// `alerts`: only those running low. 8 apart.
pub fn meter_chips(c : @ui.Ctx, key : String, meters : Array[Json], alerts? : Bool = false) -> Unit {
  c.box(style=peek_meters, fn() {
    for m in meters {
      let mv = Some(m)
      if alerts && text(mv, "level") == "ok" {
        continue
      }
      // (what it is in the chip's own tip)
      @sf.meter_chip(c, mv, key=key + "/meter")
    }
  })
  |> ignore
}

///|
/// This device's connection to a station (Stations.kt NetLine): how it goes (and packets lost) over its round trip on
/// the left; on the right ↑ over ↓, the speed each way and what went that way.
fn net_line(c : @ui.Ctx, net : Json?) -> Unit {
  let t = @sf.theme()
  let tone = fn(f : Json?) {
    match text(f, "level") {
      "red" => t.p.red
      "amber" => t.p.warn_ink
      _ => t.p.text
    }
  }
  // (none: a made-up one, to be drawn in its bones while it is read, its words in Chinese)
  let n = match net {
    Some(_) => net
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
  c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), gap=2.0, fn() {
      // (short of room, how it is reached and what its latency is called are cut short; the figures are not)
      c.box(dir=Row, gap=8.0, align=ACenter, fn() {
        c.text(text(n, "path"), size=t.t.meta, color=t.p.muted, wrap=false, line=18.0, w=Cut) |> ignore
        match field(n, "loss") {
          Some(Object(_)) as l =>
            c.text(text(l, "text"), size=@sf.theme().t.meta, weight=500, color=tone(l), wrap=false, line=18.0) |> ignore
          _ => ()
        }
      })
      |> ignore
      match field(n, "rtt") {
        Some(Object(_)) as r =>
          c.box(dir=Row, align=ACenter, fn() {
            c.text(tr("android-settings.stations.rtt"), size=t.t.meta, color=t.p.muted, wrap=false, line=18.0, w=Cut) |> ignore
            c.text(text(r, "text"), size=@sf.theme().t.meta, weight=500, color=tone(r), wrap=false, line=18.0) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
    c.box(gap=2.0, fn() {
      for way in [("↑", "up", "upTotal"), ("↓", "down", "downTotal")] {
        c.box(dir=Row, align=ACenter, fn() {
          c.text(way.0, size=t.t.meta, color=t.p.muted, wrap=false, line=18.0) |> ignore
          // (5 before it, then 68 for it: Stations.kt padding(start = 5.dp).width(68.dp))
          c.box(w=Px(73.0), pl=5.0, fn() {
            c.text(text(n, way.1), size=t.t.meta, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
          })
          |> ignore
          match opt_text(n, way.2) {
            Some(total) =>
              c.box(min_w=60.0, fn() {
                c.text(fill("android-settings.stations.total", [("total", total)]), size=t.t.meta, color=t.p.muted, wrap=false, line=18.0)
                |> ignore
              })
              |> ignore
            None => ()
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A machine's CPU, memory and disk on its page (Parts.kt MeterDials): each what is left large over ten cells (lit as
/// far as is used), what it is and what it is out of; three sharing the width.
fn meter_dials(c : @ui.Ctx, meters : Array[Json]) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), gap=16.0, fn() {
    for m in meters {
      let v = Some(m)
      let level = text(v, "level")
      let tone = @sf.level_color(level)
      let low = level == "amber" || level == "red"
      let lit = ((100 - clamp(count(v, "left"))).to_double() / 10.0 + 0.5).floor().to_int()
      c.box(w=Fill(1.0), gap=2.0, fn() {
        c.box(dir=Row, align=AEnd, fn() {
          c.text(text(v, "big"), size=t.t.display, weight=600, color=if low { tone } else { t.p.text }, wrap=false, line=32.0)
          |> ignore
          c.box(pl=1.0, fn() {
            c.text(text(v, "unit"), size=t.t.ui, weight=500, color=t.p.muted, wrap=false, line=26.0) |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(dir=Row, pt=4.0, pb=6.0, gap=2.0, fn() {
          for i in 0..<10 {
            c.box(w=Px(7.0), h=Px(14.0), radius=2.0, bg=if i < lit { tone } else { t.p.line }, fn() {  }) |> ignore
          }
        })
        |> ignore
        c.text(text(v, "title"), size=t.t.meta, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          match text(v, "total") {
            "" => " "
            x => x
          },
          size=t.t.caption,
          color=t.p.muted,
          wrap=false,
          line=17.0,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// What is left of it large, 4 down.
// kept across runs: a value (no field of it changes)
let figures_dials : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let figures_dials_in : @ui.Style = @ui.css("w=Full pt=S1")

///|
/// The dials' places before it is read, 16 apart (Bar 90 by 76, 6 round).
// kept across runs: a value (no field of it changes)
let figures_dials_unread : @ui.Style = @ui.css("row w=Full h=Full gap=S4")

///|
let unread_dial_w : Double = 90.0

///|
let unread_dial_h : Double = 76.0

///|
let unread_dial_r : Double = 6.0

///|
/// Its network 14 under the dials.
// kept across runs: a value (no field of it changes)
let figures_net : @ui.Style = @ui.css("w=Full pt=S3_5")

///|
/// Its rows, 8 apart (HostDetails).
// kept across runs: a value (no field of it changes)
let figures_rows : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// What lies evenly down a room (its spacers share what is left).
// kept across runs: a value (no field of it changes)
let figures_spread : @ui.Style = @ui.css("w=Full h=Full")

///|
let unread_detail_w : Double = 180.0

///|
/// Its agents' processes, 14 under its network.
// kept across runs: a value (no field of it changes)
let figures_running : @ui.Style = @ui.css("w=Full pt=S3_5")

///|
/// A line's room, as tall as a line in Chinese (18), what it says centred across it (Line).
// kept across runs: a value (no field of it changes)
let figures_line : @ui.Style = @ui.css("w=Full h=S4_5 justify=JCenter")

///|
let unread_running_w : Double = 120.0

///|
/// A part's line where it has nothing to show (offline): 13 on 20, muted (Stations.kt StationDevice's, StationMachine's).
// kept across runs: a value (no field of it changes)
let part_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, w=Full)

///|
/// The parts' choice under the bar (StationScreen's Seg): 12 in from the page's sides as its cards, 10 over the first.
// kept across runs: a value (no field of it changes)
let parts_room : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5")

///|
/// The page's part shown, by station, by its name (StationPage.tsx Part: overview 概览, processes 进程, settings 设置,
/// machine 软件与设备); none, the overview. Kept while the page is in the stack; a login's link opens the settings
/// (mark_login).
pub let station_parts : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// Whose page has its 高级网络设置 opened, by station (opened by the person, or the fixture's
/// settings-station-network); kept while the page is in the stack.
pub let station_network_open : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
