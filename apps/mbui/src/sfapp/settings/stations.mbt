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
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        })
      Some(a) if a.length() == 0 => blocks.push(fn() { first_station(c, core, here) })
      Some(a) =>
        for st in a {
          blocks.push(fn() { station_card(c, core, st) })
        }
    }
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "stations", blocks)
  })
}

///|
/// A station in the list: its mark (the server's where it has none), its name, what is said of it, and its body (StationBody).
fn station_card(c : @ui.Ctx, core : Core, st : Json) -> Unit {
  let t = @sf.theme()
  let s = Some(st)
  let address = text(s, "station")
  if card(c, key="station/" + address, fn() {
      c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
        let emoji = text(s, "emoji")
        let icon = text(s, "icon")
        // In a box as large whatever it is: an emoji is drawn wider than an icon, and the names line up.
        c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, fn() {
          if @sf.has_station_mark(emoji, icon) {
            @sf.station_mark(c, emoji, icon, 28.0, t.p.text)
          } else {
            @sf.icon(c, "server", size=28.0, color=t.p.text) |> ignore
          }
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          c.text(text(s, "name"), size=16.0, weight=700, color=t.p.text, wrap=false, line=22.0) |> ignore
          c.text(join([joined_mark(s), text(s, "summary")], " · "), size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0)
          |> ignore
        })
        |> ignore
        if flag(s, "reconnecting") {
          reconnecting(c)
        }
        chevron(c)
      })
      |> ignore
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
    c.text(tr("common.reconnecting"), size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
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
              fill_chip(c, 100 - clamp(count(Some(m), "left")), text(Some(m), "level"), text(Some(m), "short"), text(Some(m), "remaining"))
            }
          }
        })
        |> ignore
        if online && host is None {
          c.layer(fn() {
            c.box(style=peek_meters_unread, fn() {
              for w in unread_meters {
                @sf.bar(c, Px(w), unread_meter_h, radius=unread_meter_r, breathing=true)
              }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      // its network 10 under them; not read yet, grey bars centred across its line's room
      c.box(style=station_body_net, fn() {
        c.box(style=@sf.full_width, fn() {
          c.box(style=seen(@sf.full_width, net is Some(_), faded), fn() { net_line(c, net) }) |> ignore
          if online && net is None {
            c.layer(fn() { net_bars(c) }) |> ignore
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
              fill("android-settings.stations.silent", [("app", "still.fail")]),
              size=13.0,
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
let unseen : @ui.Style = @ui.style(opacity=O0)

///|
// kept across runs: a value (no field of it changes)
let faded_look : @ui.Style = @ui.style(opacity=O45)

///|
/// Under a station's name, 10 down (StationBody's padding).
// kept across runs: a value (no field of it changes)
let station_body_box : @ui.Style = @ui.style(w=Full, pt=S2_5)

///|
/// Its network, 10 under the boxes of what runs low.
// kept across runs: a value (no field of it changes)
let station_body_net : @ui.Style = @ui.style(w=Full, pt=S2_5)

///|
/// Offline: its picture and a line saying so, centred across the room, 12 apart.
// kept across runs: a value (no field of it changes)
let offline_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, gap=S3, align=ACenter)

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
/// How full, as a colour: the core's level (Parts.kt levelColor).
fn level_color(level : String) -> Int64 {
  let t = @sf.theme()
  match level {
    "red" => t.p.red
    "amber" => warn
    "progress" => t.p.accent
    _ => t.p.green
  }
}

///|
/// A rounded box with a figure in it, its mark before it, its ground filled from the left as far as `fill` (0–100):
/// grey while it is ok, faintly the level's colour once it is not, the figure then in that colour (Parts.kt FillChip).
fn fill_chip(
  c : @ui.Ctx,
  fill : Int,
  level : String,
  mark : String,
  words : String,
  small? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let tone = level_color(level)
  let low = level == "amber" || level == "red"
  let ground = if low || level == "progress" { @sf.alpha(tone, 0.2) } else { @sf.alpha(t.p.muted, 0.22) }
  let fs = if small { 10.0 } else { 11.0 }
  // (its fill a plain rectangle the chip's clip cuts along its corners, FillChip's drawRect in its clip; its end square
  // where it stops)
  c.box(h=Px(if small { 16.0 } else { 20.0 }), radius=@sf.fill_chip_corner, bg=t.p.chip, clip=true, justify=JCenter, fn() {
    if fill > 0 {
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(fill.to_double()), h=Fill(1.0), bg=ground, fn() {  }) |> ignore
          if fill < 100 {
            c.box(w=Fill((100 - fill).to_double()), h=Fill(1.0), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(dir=Row, padx=if small { 5.0 } else { 8.0 }, gap=5.0, align=ACenter, fn() {
      if mark != "" {
        c.text(mark, size=fs, weight=600, color=@sf.mix(t.p.text, 0.5, t.p.muted), wrap=false, line=fs + 2.0)
        |> ignore
      }
      c.text(words, size=fs, weight=600, color=if low { tone } else { t.p.text }, wrap=false, line=fs + 2.0)
      |> ignore
    })
    |> ignore
  })
  |> ignore
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
      let id = c.id(key + "/meter/" + text(mv, "label"))
      c.box(id~, taps=false, fn() {
        fill_chip(c, 100 - clamp(count(mv, "left")), text(mv, "level"), text(mv, "short"), text(mv, "remaining"))
      })
      |> ignore
      let note = text(mv, "note")
      @sf.tip(c, key + "/meter/" + text(mv, "label"), id, text(mv, "label") + " " + text(mv, "value") + (if note != "" {
        " · " + note
      } else {
        ""
      }))
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
      "amber" => warn
      _ => t.p.text
    }
  }
  // as tall as a real one, unseen, while there is none (its words in Chinese)
  let n = match net {
    Some(_) => net
    None => Some(obj([("path", str("直连")), ("rtt", obj([("text", str("0 ms")), ("level", str("ok"))])), ("down", str(" ")), ("up", str(" "))]))
  }
  c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), gap=2.0, fn() {
      c.box(dir=Row, gap=8.0, align=ACenter, fn() {
        c.text(text(n, "path"), size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
        match field(n, "loss") {
          Some(Object(_)) as l =>
            c.text(text(l, "text"), size=13.0, weight=500, color=tone(l), wrap=false, line=18.0) |> ignore
          _ => ()
        }
      })
      |> ignore
      match field(n, "rtt") {
        Some(Object(_)) as r =>
          c.box(dir=Row, align=ACenter, fn() {
            c.text(tr("android-settings.stations.rtt"), size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
            c.text(text(r, "text"), size=13.0, weight=500, color=tone(r), wrap=false, line=18.0) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
    c.box(gap=2.0, fn() {
      for way in [("↑", "up", "upTotal"), ("↓", "down", "downTotal")] {
        c.box(dir=Row, align=ACenter, fn() {
          c.text(way.0, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
          // (5 before it, then 68 for it: Stations.kt padding(start = 5.dp).width(68.dp))
          c.box(w=Px(73.0), pl=5.0, fn() {
            c.text(text(n, way.1), size=13.0, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
          })
          |> ignore
          match opt_text(n, way.2) {
            Some(total) =>
              c.box(min_w=60.0, fn() {
                c.text(fill("android-settings.stations.total", [("total", total)]), size=13.0, color=t.p.muted, wrap=false, line=18.0)
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
      let tone = level_color(level)
      let low = level == "amber" || level == "red"
      let lit = ((100 - clamp(count(v, "left"))).to_double() / 10.0 + 0.5).floor().to_int()
      c.box(w=Fill(1.0), gap=2.0, fn() {
        c.box(dir=Row, align=AEnd, fn() {
          c.text(text(v, "big"), size=28.0, weight=600, color=if low { tone } else { t.p.text }, wrap=false, line=32.0)
          |> ignore
          c.box(pl=1.0, fn() {
            c.text(text(v, "unit"), size=15.0, weight=500, color=t.p.muted, wrap=false, line=26.0) |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(dir=Row, pt=4.0, pb=6.0, gap=2.0, fn() {
          for i in 0..<10 {
            c.box(w=Px(7.0), h=Px(14.0), radius=2.0, bg=if i < lit { tone } else { t.p.chip }, fn() {  }) |> ignore
          }
        })
        |> ignore
        c.text(text(v, "title"), size=13.0, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          match text(v, "total") {
            "" => " "
            x => x
          },
          size=12.0,
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
/// An online station's machine on its page's 概览 (Stations.kt StationFigures): what is left of it large, its network,
/// its agents' processes (what it is, a row each, is under 软件与设备: station_device); in its room whether known yet
/// or not (grey bars over it until it is: laid out unseen as when it is, so nothing below moves as it comes);
/// reconnecting, as last heard, faded.
fn station_figures(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let t = @sf.theme()
  let host = match field(s, "host") {
    Some(Object(_)) as h => h
    _ => None
  }
  let read = host is Some(_)
  let net = station_net(core, s)
  let running = text(field(s, "overview"), "processesText")
  // (each part's room a box of its own under its padding: what is laid over it covers that alone, as matchParentSize
  // in a padded Box)
  c.box(style=if flag(s, "reconnecting") { peek_figures_faded } else { peek_figures_box }, fn() {
    c.box(style=figures_dials, fn() {
      c.box(style=@sf.full_width, fn() {
        c.box(style=seen(@sf.full_width, read, false), fn() {
          meter_dials(c, if read { items(host, "meters") } else { unread_dials() })
        })
        |> ignore
        if !read {
          c.layer(fn() {
            c.box(style=figures_dials_unread, fn() {
              for _ in 0..<3 {
                @sf.bar(c, Px(unread_dial_w), unread_dial_h, radius=unread_dial_r, breathing=true)
              }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=figures_net, fn() {
      c.box(style=@sf.full_width, fn() {
        c.box(style=seen(@sf.full_width, net is Some(_), false), fn() { net_line(c, net) }) |> ignore
        if net is None {
          c.layer(fn() { net_bars(c) }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // its agents' processes, a line (Line): a grey bar in its room until they are known
    c.box(style=figures_running, fn() {
      c.box(style=figures_line, fn() {
        if running != "" {
          c.text(running, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
        } else {
          @sf.bar(c, Px(unread_running_w), net_bar_h, breathing=true)
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What is left of it large, 4 down.
// kept across runs: a value (no field of it changes)
let figures_dials : @ui.Style = @ui.style(w=Full, pt=S1)

///|
/// The dials' places before it is read, 16 apart (Bar 90 by 76, 6 round).
// kept across runs: a value (no field of it changes)
let figures_dials_unread : @ui.Style = @ui.style(row=true, w=Full, h=Full, gap=S4)

///|
let unread_dial_w : Double = 90.0

///|
let unread_dial_h : Double = 76.0

///|
let unread_dial_r : Double = 6.0

///|
/// Its network 14 under the dials.
// kept across runs: a value (no field of it changes)
let figures_net : @ui.Style = @ui.style(w=Full, pt=S3_5)

///|
/// Its rows, 8 apart (HostDetails).
// kept across runs: a value (no field of it changes)
let figures_rows : @ui.Style = @ui.style(w=Full, gap=S2)

///|
/// What lies evenly down a room (its spacers share what is left).
// kept across runs: a value (no field of it changes)
let figures_spread : @ui.Style = @ui.style(w=Full, h=Full)

///|
let unread_detail_w : Double = 180.0

///|
/// Its agents' processes, 14 under its network.
// kept across runs: a value (no field of it changes)
let figures_running : @ui.Style = @ui.style(w=Full, pt=S3_5)

///|
/// A line's room, as tall as a line in Chinese (18), what it says centred across it (Line).
// kept across runs: a value (no field of it changes)
let figures_line : @ui.Style = @ui.style(w=Full, h=S4_5, justify=JCenter)

///|
let unread_running_w : Double = 120.0

///|
/// What a machine not read yet is laid out as, unseen (Stations.kt unreadHost): its dials as tall as a real one's
/// (their words in Chinese).
fn unread_dials() -> Array[Json] {
  Array::make(3, obj([("big", str("0")), ("unit", str("%")), ("title", str("内存剩")), ("total", str("共 0 GB")), ("left", Json::number(0.0)), ("level", str("ok"))]))
}

///|
/// Its rows as tall as a real one's, unseen (unreadHost's details).
fn unread_details() -> Array[Json] {
  Array::make(4, obj([("label", str("主机名")), ("value", str("直连"))]))
}

///|
/// What the machine is, a row each (Stations.kt StationDevice: its hostname, chip, how long it has been up, the process)
/// and what still.fail keeps on it, as the web's 设备信息: grey bars in their room while it is not read yet; offline and
/// never read, a line saying so.
fn station_device(c : @ui.Ctx, s : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let host = match field(s, "host") {
    Some(Object(_)) as h => h
    _ => None
  }
  let read = host is Some(_)
  let footprint = text(field(field(s, "overview"), "footprint"), "text")
  // (a copy: the topic's own array is not added to)
  let details = if read { items(host, "details").copy() } else { unread_details() }
  if footprint != "" {
    details.push(obj([("label", str(tr("web-pages.stations.page.footprint"))), ("value", str(footprint))]))
  }
  [
    fn() { section_header(c, tr("web-pages.stations.device"), start=S6) },
    fn() {
      card(c, fn() {
        if !read && !flag(s, "online") {
          c.text(tr("web-pages.stations.deviceOffline"), style=part_note) |> ignore
        } else {
          c.box(style=@sf.full_width, fn() {
            c.box(style=seen(figures_rows, read, false), fn() {
              for d in details {
                c.box(dir=Row, w=Fill(1.0), gap=16.0, fn() {
                  c.box(min_w=52.0, fn() {
                    c.text(text(Some(d), "label"), size=13.0, color=t.p.subtle, wrap=false, line=20.0) |> ignore
                  })
                  |> ignore
                  c.text(text(Some(d), "value"), size=13.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
            // a bar a row, evenly down its room (Arrangement.SpaceEvenly: as much room over each as under the last)
            if !read {
              c.layer(fn() {
                c.box(style=figures_spread, fn() {
                  c.spacer()
                  for _ in 0..<details.length() {
                    @sf.bar(c, Px(unread_detail_w), net_bar_h, breathing=true)
                    c.spacer()
                  }
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
  ]
}

///|
/// A part's line where it has nothing to show (offline): 13 on 20, muted (Stations.kt StationDevice's, StationMachine's).
// kept across runs: a value (no field of it changes)
let part_note : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L5, w=Full)

///|
/// The parts' choice under the bar (StationScreen's Seg): 12 in from the page's sides as its cards, 10 over the first.
// kept across runs: a value (no field of it changes)
let parts_room : @ui.Style = @ui.style(w=Full, px=S3, pb=S2_5)

///|
/// The page's part shown, by station (StationScreen's `part`: 0 概览, 1 设置, 2 软件与设备); none, the overview. Kept
/// while the page is in the stack; a login's link opens the settings (mark_login).
let station_parts : Map[String, Int] = {}

///|
/// A station's page (StationScreen): its bar (back to Station, its name, what the machine is under it, "…" for its
/// owners and admins), the machine or that it is offline, what runs on it.
fn station_page(c : @ui.Ctx, core : Core, here : Here, address : String) -> Unit {
  let t = @sf.theme()
  let topic = stations_of(core, here)
  let mut s : Json? = None
  match topic.value {
    Some(Array(a)) =>
      for x in a {
        if text(Some(x), "station") == address {
          s = Some(x)
        }
      }
    _ => ()
  }
  let manager = manager_of(core, here) == Some(true)
  let st = s
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let sub = fn() {
      c.box(h=Px(16.0), justify=JCenter, fn() {
        if flag(st, "reconnecting") {
          reconnecting(c)
        } else {
          let what = match opt_text(field(st, "host"), "identity") {
            Some(i) if i != "" => i
            _ => text(st, "line")
          }
          c.text(join([joined_mark(st), what], " · "), size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
        }
      })
      |> ignore
    }
    let title = match st {
      Some(_) => text(st, "name")
      None => station_name(address)
    }
    match st {
      Some(_) if manager =>
        nav_bar(c, core, "Station", title, sub~, trailing=fn() {
          if nav_button(c, "station-more", "more") {
            station_menu(core, here, st)
          }
        })
      Some(_) => nav_bar(c, core, "Station", title, sub~)
      None => nav_bar(c, core, "Station", title)
    }
    match st {
      None =>
        waiting_cards(
          c,
          error=match topic.error {
            Some(e) => error_text(e)
            None => ""
          },
        )
      Some(_) => {
        let overview = field(st, "overview")
        let read = overview is Some(Object(_))
        let online = flag(st, "online")
        // in three parts, as the web's (StationPage.tsx Body): how it is and what runs on it; what it is let do and set
        // to; its software and the machine
        let part = station_parts.get(address).unwrap_or(0)
        let blocks : Array[() -> Unit] = [
          fn() { gap(c, 12.0) },
          fn() {
            c.box(style=parts_room, fn() {
              let i = seg(
                c,
                "station-part/" + address,
                [
                  tr("web-pages.stations.page.part.overview"),
                  tr("web-pages.stations.page.part.settings"),
                  tr("web-pages.stations.page.part.machine"),
                ],
                part,
                fill=true,
                height=34.0,
              )
              if i != part {
                station_parts[address] = i
              }
            })
            |> ignore
          },
        ]
        let mut logins_at = -1
        let mut logins_n = 0
        match part {
          0 => {
            blocks.push(fn() {
              if online {
                card(c, fn() { station_figures(c, core, st) }) |> ignore
              } else {
                card(c, fn() {
                  c.box(w=Fill(1.0), gap=4.0, align=ACenter, fn() {
                    let pic = if t.dark { "illus_station_offline_dark" } else { "illus_station_offline" }
                    if @sf.has_drawable(pic) {
                      @sf.drawable(c, pic, 220.0) |> ignore
                    }
                    // down for a security mode: why (the core's `blocked`), not how to bring it back
                    let blocked = text(st, "blocked")
                    c.text(
                      if blocked != "" {
                        blocked
                      } else {
                        fill("android-settings.stations.offline", [("app", "still.fail")])
                      },
                      size=13.0,
                      color=t.p.muted,
                      center=true,
                      w=Fill(1.0),
                      line=18.0,
                    )
                    |> ignore
                    c.box(pt=6.0, fn() { retry_pill(c, core, flag(field(st, "link"), "retrying")) }) |> ignore
                  })
                  |> ignore
                })
                |> ignore
              }
            })
            blocks.push(fn() { section_header(c, tr("android-settings.stations.onIt"), start=S6) })
            blocks.push(fn() {
              list_card(c, fn() {
                let n = fn(key : String) {
                  if read {
                    fill("android-settings.count", [("n", items(overview, key).length().to_string())])
                  } else {
                    ""
                  }
                }
                if go_row(c, "st-connects", tr("android-settings.connects.title"), value=n("connects")) {
                  (core.push)(Connects(address))
                }
                if go_row(c, "st-profiles", "Profile", value=n("profiles")) {
                  (core.push)(Profiles(address))
                }
                if go_row(c, "st-memory", tr("android-settings.memory")) {
                  (core.push)(Memory(address))
                }
                // this device's adb, lent to its agents (AdbShare.kt)
                let shared = (core.topic)("adbShare", Map([])).value
                if go_row(
                    c,
                    "st-adb",
                    tr("android-misc.adb.title"),
                    value=if flag(shared, "sharing") && text(shared, "station") == address {
                      tr("android-misc.adb.sharing")
                    } else {
                      ""
                    },
                  ) {
                  (core.push)(AdbShare(address))
                }
                // the folders it lends its members (docs/drive.md); none offered by a station from before the drive
                match field(overview, "drive") {
                  Some(Object(_)) as drive => {
                    let n = items(drive, "roots").length()
                    if go_row(
                        c,
                        "st-drive",
                        tr("android-misc.drive.title"),
                        value=if n == 0 {
                          tr("android-misc.drive.row.none")
                        } else {
                          fill("android-misc.drive.roots.count", [("n", n.to_string())])
                        },
                      ) {
                      (core.open_drive)(address)
                    }
                  }
                  _ => ()
                }
              })
            })
            for b in station_screens(c, core, address) {
              blocks.push(b)
            }
          }
          1 => {
            // what is under it, each from its own topic or the overview's part (none from a station older than it)
            match field(overview, "permissions") {
              Some(Object(_)) as p if online =>
                for b in station_permissions(c, core, address, p) {
                  blocks.push(b)
                }
              _ => ()
            }
            // the logins its agents did there (LoginCards.kt StationLogins): those under way as their cards (the
            // second block of them: where a link's login is brought to)
            logins_at = blocks.length() + 1
            let logins = station_logins(c, core, address)
            logins_n = logins.length()
            for b in logins {
              blocks.push(b)
            }
            match field(overview, "agentEnv") {
              Some(Array(env)) =>
                for b in station_agent_env(c, core, address, env, manager) {
                  blocks.push(b)
                }
              _ => ()
            }
            match field(overview, "search") {
              Some(Object(_)) as sr if online && text(sr, "files") == "spotlight" =>
                for b in station_search(c, core, address, flag(sr, "personal"), manager) {
                  blocks.push(b)
                }
              _ => ()
            }
            if manager {
              for b in station_workspaces(c, core, address) {
                blocks.push(b)
              }
            }
          }
          _ => {
            // its updates are its home workspace's managers'
            if online && read {
              for b in station_versions(c, core, address, items(overview, "updates"), manager, flag(st, "betaOffered")) {
                blocks.push(b)
              }
            } else if !online {
              blocks.push(fn() { section_header(c, tr("web-pages.stations.software"), start=S6) })
              blocks.push(fn() {
                card(c, fn() {
                  c.text(tr("web-pages.stations.softwareOffline"), style=part_note) |> ignore
                })
                |> ignore
              })
            }
            for b in station_device(c, st) {
              blocks.push(b)
            }
          }
        }
        blocks.push(fn() { gap(c, 30.0) })
        scroll_page(c, "station/" + address, blocks)
        if logins_n > 1 {
          bring_marked_login(c, address, "settings/station/" + address, logins_at)
        }
      }
    }
  })
  |> ignore
}

///|
/// 重试 as a small grey pill (Connection.kt RetryPill): the connections tried again at once (`client.wake`), a spinner
/// in it meanwhile.
fn retry_pill(c : @ui.Ctx, core : Core, retrying : Bool) -> Unit {
  let t = @sf.theme()
  let trying = retrying || is_doing(core, ["client.wake"], [])
  let id = c.id("retry-pill")
  if hit(c, id) && !trying {
    act(
      core,
      tr("android-misc.connection.reconnect"),
      "client.wake",
      obj([("away", Json::number(0.0)), ("network", Json::boolean(true)), ("retry", Json::boolean(true))]),
    )
  }
  c.box(dir=Row, h=Px(22.0), radius=11.0, bg=t.p.chip, padx=10.0, gap=5.0, align=ACenter, id~, fn() {
    if trying {
      spinner(c, inline=true)
    }
    c.text(tr("common.retry"), size=13.0, color=t.p.text, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A station's own actions (Settings.kt openStationMenu): its name, its mark, taking it out of the workspace.
fn station_menu(core : Core, here : Here, s : Json?) -> Unit {
  let name = text(s, "name")
  let id = text(s, "id")
  open_sheet(0.34, fn(c, _core) {
    let t = @sf.theme()
    sheet_head(c, name)
    if pick_row(c, "st-rename", tr("android-settings.station.rename")) {
      ask(
        tr("android-settings.station.renameTitle"),
        name,
        tr("android-settings.station.renamePlaceholder"),
        tr("common.save"),
        fn(line) {
          act(
            core,
            tr("android-settings.station.renameWhat"),
            "workspace.renameStation",
            obj([
              ("workspace", str(here.workspace)),
              ("station", str(id)),
              ("name", str(line)),
              ("account", str(here.sub)),
            ]),
            done=tr("android-settings.renamed"),
          )
        },
      )
    }
    if pick_row(c, "st-mark", tr("android-settings.station.emoji"), mark?=if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
        Some(fn() { station_mark(c, s, 15.0, t.p.text) })
      } else {
        None
      }) {
      open_mark_pick(core, name, text(s, "emoji"), text(s, "icon"), tr("android-settings.station.emojiWhat"), fn(
        emoji,
        icon,
        done,
      ) {
        (core.call)(
          "workspace.renameStation",
          obj([
            ("workspace", str(here.workspace)),
            ("station", str(id)),
            ("emoji", str(emoji)),
            ("icon", str(icon)),
            ("account", str(here.sub)),
          ]),
          done,
        )
      })
    }
    if pick_row(c, "st-remove", tr("android-settings.station.removeRow"), color=t.p.red) {
      confirm(
        fill("android-settings.station.removeTitle", [("name", name)]),
        fill("android-settings.station.removeText", [("app", "still.fail")]),
        tr("android-settings.station.remove"),
        danger=true,
        fn() {
          (core.pop)()
          act(
            core,
            tr("android-settings.station.removeWhat"),
            "workspace.removeStation",
            obj([("workspace", str(here.workspace)), ("station", str(id)), ("account", str(here.sub))]),
            done=tr("android-settings.station.removed"),
          )
        },
      )
    }
  })
}
