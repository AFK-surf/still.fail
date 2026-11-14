// The workspace's stations: a card each with its mark and what it is doing, what of its load
// runs low and its network; one station's page is the machine (its load large, its network, its details), with how
// many connects and profiles run on it and its memory. Its owners and admins rename it (`workspace.renameStation`),
// pick its mark or take it out from its "…".

///|
/// Where a station this workspace joined is at home, as grey words before what is said of it.
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
    // those that only run tasks after the whole ones, a card each: its page a press away
    let rigs = if list is Some(_) { rigs_listed(core, here) } else { [] }
    for r in rigs {
      blocks.push(fn() { rig_station_card(c, core, here, r) })
    }
    // the workspace's devices after its stations (设备: attached to one, or a person's phone), under their heading
    let devices = if list is Some(_) { devices_listed(core, here) } else { [] }
    if devices.length() > 0 {
      blocks.push(fn() { @sf.heading(c, @sf.t("web-pages.devices.title")) })
    }
    for d in devices {
      blocks.push(fn() { device_card(c, core, here, d) })
    }
    blocks.push(fn() { gap(c, 30.0) })
    // (each block by what it is: a station by its id, so one joining or leaving comes and goes where it is)
    let keys = match list {
      Some(a) if a.length() > 0 => a.mapi(fn(i, st) { "st/" + (match opt_text(Some(st), "station") { Some(id) => id; None => i.to_string() }) })
      Some(_) => ["first"]
      None => ["waiting"]
    }
    for r in rigs {
      keys.push("rig/" + text(Some(r), "id"))
    }
    if devices.length() > 0 {
      keys.push("devices")
    }
    for d in devices {
      keys.push("device/" + text(Some(d), "station") + "/" + text(Some(d), "id"))
    }
    keys.push("foot")
    scroll_page(c, "stations", blocks, keys~, continuity=fn(k) { k.has_prefix("st/") || k.has_prefix("rig/") || k.has_prefix("device/") })
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
      // A card is a summary; its page can show the station's name in full.
      c.text(name, size=t.t.title, weight=700, color=t.p.text, wrap=false, line=22.0, allow_ellipsis=true) |> ignore
      // what is said of it goes on to a line more where it does not fit (words set larger: a rig's whose and how)
      match said {
        Some(line) => c.text(line, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
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
  card(c, key="station/" + address, fn() {
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
  }, on_press=fn() {
    (core.push)(Station(address))
  })
}

///|
/// A station that only runs tasks in the list (rig `r`): its mark, its name, and that it only runs tasks, whose it is
/// and how it is; no body (this device is not linked to it: a station says how it is).
fn rig_station_card(c : @ui.Ctx, core : Core, here : Here, r : Json) -> Unit {
  let t = @sf.theme()
  let address = here.workspace + "/" + text(Some(r), "id")
  card(c, key="station/" + address, fn() {
    card_head(c, fn() { @sf.icon(c, "boxes", size=card_mark, color=t.p.text) |> ignore }, text(Some(r), "name"), Some(rig_said(Some(r))), fn() { chevron(c) })
  }, on_press=fn() {
    (core.push)(Station(address))
  })
}

///|
/// A device in the list (设备): its mark, its name, what it is, where, whose and how chats use it; its panel a press away.
fn device_card(c : @ui.Ctx, core : Core, here : Here, d : Json) -> Unit {
  let t = @sf.theme()
  let key = "device/" + text(Some(d), "station") + "/" + text(Some(d), "id")
  card(c, key~, fn() {
    card_head(c, fn() { @sf.icon(c, device_icon(Some(d)), size=card_mark, color=t.p.text) |> ignore }, text(Some(d), "name"), Some(device_said(Some(d))), fn() { chevron(c) })
  }, on_press=fn() {
    open_device(core, here, text(Some(d), "station"), text(Some(d), "id"), Unanchored)
  })
}

///|
/// How this device reaches station `s` now, its figures (Stations.kt rememberStationNet: the `stationNet` view, sampled
/// while shown; none before a connection of its own is open).
fn station_net(core : Core, s : Json?) -> Json? {
  // (the view's null: no connection of this device's own open yet, as none)
  match (core.topic)("stationNet", { "station": str(text(s, "station")) }).get().value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// Up but not reached just now: what shows of it is from before.
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
          let meters = items(host, "meters")
          @sf.meter_line(c, meters, key="station-body/" + text(s, "station"))
        })
        |> ignore
        if online && host is None && !unreadable(s) {
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
/// A machine's CPU, memory and disk, each a chip (MeterChip) with what it is in its tip;
/// `alerts`: only those running low. 8 apart.
pub fn meter_chips(c : @ui.Ctx, key : String, meters : Array[Json], alerts? : Bool = false) -> Unit {
  c.box(style=peek_meters, fn() {
    // (what it is in the chip's own tip)
    let shown = if alerts { meters.filter(fn(m) { text(Some(m), "level") != "ok" }) } else { meters }
    @sf.meter_line(c, shown, key=key + "/meter")
  })
  |> ignore
}

///|
/// This device's connection to a station: how it goes (and packets lost) over its round trip on
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
    c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
      // (short of room, how it is reached and what its latency is called are cut short; the figures are not)
      c.box(dir=Row, gap=6.0, align=ACenter, fn() {
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
          c.box(dir=Row, gap=4.0, align=ACenter, fn() {
            c.text("·", size=t.t.meta, color=t.p.muted, wrap=false, line=18.0) |> ignore
            c.text(tr("android-settings.stations.rtt"), size=t.t.meta, color=t.p.muted, wrap=false, line=18.0, w=Cut) |> ignore
            c.text(text(r, "text"), size=@sf.theme().t.meta, weight=500, color=tone(r), wrap=false, line=18.0) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
    c.box(dir=Row, gap=10.0, align=ACenter, fn() {
      for way in [("↑", "up"), ("↓", "down")] {
        c.box(dir=Row, gap=4.0, align=ACenter, fn() {
          c.text(way.0, size=t.t.meta, color=t.p.muted, wrap=false, line=18.0) |> ignore
          c.text(text(n, way.1), size=t.t.meta, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A dial's number large and its unit small after it, on one line so both stand on its baseline.
fn dial_figure(c : @ui.Ctx, big : String, unit : String, color : Int64) -> Unit {
  let t = @sf.theme()
  c.rich(
    [@ui.span(big), @ui.span(unit, weight=500, scale=t.t.ui / t.t.display, color=t.p.muted)],
    size=t.t.display,
    weight=600,
    color~,
    wrap=false,
    line=32.0,
  )
  |> ignore
}

///|
/// The page's part shown, by station, by its name (StationPage.tsx Part: overview 概览, processes 进程, settings 设置,
/// machine 软件与设备); none, the overview. Kept while the page is in the stack; a login's link opens the settings
/// (mark_login).
pub let station_parts : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// Whose page has its 高级网络设置 opened, by station (opened by the person, or the fixture's
/// settings-station-network); kept while the page is in the stack.
pub let station_network_open : Map[String, Bool] = Map([])
