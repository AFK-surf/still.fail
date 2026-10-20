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
  place_page(c, core, tr("android-misc.bar.place.stations"), fn() {
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
      Some(a) if a.length() == 0 => blocks.push(fn() { first_station(c) })
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
/// A workspace with no station yet (Settings.kt FirstStation): what a station is. (Adding one here, its command to
/// copy and the wait, is a later slice's.)
fn first_station(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
    @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, 240.0) |> ignore
    c.text(tr("android-settings.station.first"), size=17.0, weight=600, color=t.p.text, center=true, w=Fill(1.0))
    |> ignore
    c.text(tr("android-settings.station.firstNote"), size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0)
    |> ignore
  })
  |> ignore
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
      station_body(c, s)
    }) {
    (core.push)(Station(address))
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
fn station_body(c : @ui.Ctx, s : Json?) -> Unit {
  let t = @sf.theme()
  let online = flag(s, "online")
  let host = if online { field(s, "host") } else { None }
  let net = if online { field(s, "net") } else { None }
  let faded = if flag(s, "reconnecting") { 0.45 } else { 1.0 }
  c.box(w=Fill(1.0), pt=10.0, fn() {
    c.box(w=Fill(1.0), opacity=faded, fn() {
      c.box(dir=Row, h=Px(20.0), gap=8.0, align=ACenter, opacity=if host is Some(_) { 1.0 } else { 0.0 }, fn() {
        for m in items(host, "meters") {
          if text(Some(m), "level") != "ok" {
            fill_chip(c, 100 - clamp(count(Some(m), "left")), text(Some(m), "level"), text(Some(m), "short"), text(Some(m), "remaining"))
          }
        }
      })
      |> ignore
      c.box(w=Fill(1.0), pt=10.0, opacity=if net is Some(_) { 1.0 } else { 0.0 }, fn() { net_line(c, net) }) |> ignore
    })
    |> ignore
    if !online {
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), gap=12.0, align=ACenter, fn() {
          let pic = if t.dark { "illus_station_offline_dark" } else { "illus_station_offline" }
          if @sf.has_drawable(pic) {
            @sf.drawable(c, pic, 72.0) |> ignore
          }
          c.text(
            fill("android-settings.stations.silent", [("app", "still.fail")]),
            size=13.0,
            color=t.p.muted,
            w=Fill(1.0),
            line=18.0,
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    } else {
      let breath = @sf.breath(c)
      c.layer(fn() {
        if host is None {
          c.box(dir=Row, h=Px(20.0), gap=4.0, opacity=breath, fn() {
            for w in [46.0, 52.0, 50.0] {
              @sf.bar(c, Px(w), 20.0, radius=6.0)
            }
          })
          |> ignore
        }
        if net is None {
          c.box(dir=Row, w=Fill(1.0), pt=30.0, align=ACenter, opacity=breath, fn() {
            c.box(w=Fill(1.0), gap=9.0, fn() {
              @sf.bar(c, Px(34.0), 10.0)
              @sf.bar(c, Px(96.0), 10.0)
            })
            |> ignore
            c.box(gap=9.0, fn() {
              @sf.bar(c, Px(132.0), 10.0)
              @sf.bar(c, Px(132.0), 10.0)
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
}

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
/// The corner of a chip whose ground fills from the left (how far a download or a use has come): its fill, flush with
/// the chip's edges, is concentric with it (the chip's clip does not round what is in it until mbui#42).
let fill_chip_radius : Double = 6.0

///|
/// A rounded box with a figure in it, its mark before it, its ground filled from the left as far as `fill` (0–100):
/// grey while it is ok, faintly the level's colour once it is not, the figure then in that colour (Parts.kt FillChip).
fn fill_chip(c : @ui.Ctx, fill : Int, level : String, mark : String, words : String, small? : Bool = false) -> Unit {
  let t = @sf.theme()
  let tone = level_color(level)
  let low = level == "amber" || level == "red"
  let ground = if low || level == "progress" { @sf.alpha(tone, 0.2) } else { @sf.alpha(t.p.muted, 0.22) }
  let fs = if small { 10.0 } else { 11.0 }
  c.box(h=Px(if small { 16.0 } else { 20.0 }), radius=fill_chip_radius, bg=t.p.chip, clip=true, justify=JCenter, fn() {
    if fill > 0 {
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(fill.to_double()), h=Fill(1.0), radius=@ui.concentric(fill_chip_radius, 0.0), bg=ground, fn() {  }) |> ignore
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
          c.box(w=Px(68.0), pl=5.0, fn() {
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
/// An online station's machine on its page (Stations.kt StationFigures): what is left of it large, its network, the
/// rest a row each, its agents' processes; reconnecting, as last heard, faded.
fn station_figures(c : @ui.Ctx, s : Json?) -> Unit {
  let t = @sf.theme()
  let host = field(s, "host")
  let net = field(s, "net")
  c.box(w=Fill(1.0), opacity=if flag(s, "reconnecting") { 0.45 } else { 1.0 }, fn() {
    c.box(w=Fill(1.0), pt=4.0, fn() {
      match host {
        Some(Object(_)) => meter_dials(c, items(host, "meters"))
        _ =>
          c.box(dir=Row, w=Fill(1.0), gap=16.0, opacity=@sf.breath(c), fn() {
            for _ in 0..<3 {
              @sf.bar(c, Px(90.0), 76.0, radius=6.0)
            }
          })
          |> ignore
      }
    })
    |> ignore
    c.box(w=Fill(1.0), pt=14.0, opacity=if net is Some(_) { 1.0 } else { 0.0 }, fn() { net_line(c, net) }) |> ignore
    c.box(w=Fill(1.0), pt=16.0, gap=8.0, fn() {
      for d in items(host, "details") {
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
    let running = text(field(s, "overview"), "processesText")
    if running != "" {
      c.box(w=Fill(1.0), pt=8.0, fn() {
        c.text(running, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

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
        scroll_page(c, "station/" + address, [
          fn() { gap(c, 12.0) },
          fn() {
            if flag(st, "online") {
              card(c, fn() { station_figures(c, st) }) |> ignore
            } else {
              card(c, fn() {
                c.box(w=Fill(1.0), gap=4.0, align=ACenter, fn() {
                  let pic = if t.dark { "illus_station_offline_dark" } else { "illus_station_offline" }
                  if @sf.has_drawable(pic) {
                    @sf.drawable(c, pic, 220.0) |> ignore
                  }
                  c.text(
                    fill("android-settings.stations.offline", [("app", "still.fail")]),
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
          },
          fn() { section_header(c, tr("android-settings.stations.onIt")) },
          fn() {
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
          },
          fn() { gap(c, 30.0) },
        ])
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
    // (its mark picked from still.fail's icons, an emoji or a picture: the picker is a later slice's)
    pick_row(c, "st-mark", tr("android-settings.station.emoji"), mark=fn() { station_mark(c, s, 15.0, t.p.text) })
    |> ignore
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
