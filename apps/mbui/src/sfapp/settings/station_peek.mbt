// A station's card, from a chat's agent (ember apps/android settings/screens/Stations.kt openStationPeek): whether it
// is up and what its agents do, its machine and network at a glance, and where to go on: its files where it lends some,
// its page.

///|
/// The card of the station at `address` (`ws/station`) over the page, half the window's height (SheetSpec(0.5f)).
pub fn open_station_peek(address : String) -> Unit {
  open_sheet(peek_height, fn(c, core) { station_peek(c, core, address) })
}

///|
/// The card's share of the window (Stations.kt openStationPeek: SheetSpec(0.5f)).
let peek_height : Double = 0.5

///|
/// A station's mark in the card's head (17).
let peek_mark : Double = 17.0

///|
/// The card's body: its words, then its rows, 10 apart, 24 over the sheet's foot.
// kept across runs: a value (no field of it changes)
let peek_body : @ui.Style = @ui.css("w=Full pb=S6 gap=S2_5")

///|
/// Its words 20 in from the sheet's sides, 10 apart.
// kept across runs: a value (no field of it changes)
let peek_words : @ui.Style = @ui.css("w=Full px=S5 gap=S2_5")

///|
/// What it says of itself, and that it is offline (13 on 18, muted).
// kept across runs: a value (no field of it changes)
let peek_said : @ui.TextStyle = @sf.meta.then(@sf.full_words)

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
fn station_peek(c : @ui.Ctx, core : Core, address : String) -> Unit {
  let t = @sf.theme()
  let s = peek_station(core, address)
  let name = if s is Some(_) { text(s, "name") } else { station_name(address) }
  let lead = if s is Some(_) && @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
    Some(fn() { station_mark(c, s, peek_mark, t.p.text) })
  } else {
    None
  }
  sheet_head(c, name, lead?)
  c.box(style=peek_body, fn() {
    if s is Some(_) {
      c.box(style=peek_words, fn() {
        c.text(text(s, "summary"), style=peek_said) |> ignore
        // what its agents' processes are is on its page, a tap away
        if flag(s, "online") {
          peek_figures(c, core, s)
        } else {
          // down for a security mode: why (the core's `blocked`), not how to bring it back
          let blocked = text(s, "blocked")
          let said = if blocked != "" {
            blocked
          } else {
            fill("android-settings.stations.offline", [("app", "still.fail")])
          }
          c.text(said, style=peek_said) |> ignore
        }
      })
      |> ignore
    }
    list_card(c, fn() {
      // its files (docs/drive.md), where it has a drive: a way there from where it is named
      match field(field(s, "overview"), "drive") {
        Some(Object(_)) as drive => {
          let n = items(drive, "roots").length()
          if go_row(
              c,
              "peek-drive",
              tr("android-misc.drive.title"),
              value=if n == 0 {
                tr("android-misc.drive.row.none")
              } else {
                fill("android-misc.drive.roots.count", [("n", n.to_string())])
              },
            ) {
            close_sheet()
            (core.open_drive)(address)
          }
        }
        _ => ()
      }
      if go_row(c, "peek-station", tr("android-chat.station.details")) {
        close_sheet()
        (core.push)(Station(address))
      }
    })
  })
  |> ignore
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
/// Its boxes' places before it is read, 4 apart (Bar 46, 52, 50 by 20, 6 round).
// kept across runs: a value (no field of it changes)
let peek_meters_unread : @ui.Style = @ui.css("row h=S5 gap=S1 align=ACenter")

///|
// kept across runs: a table, never written
let unread_meters : Array[Double] = [46.0, 52.0, 50.0]

///|
let unread_meter_h : Double = 20.0

///|
/// (where a chip goes, its corner)
let unread_meter_r : Double = @sf.fill_chip_corner

///|
/// Its network 6 under the boxes; until it is read, as tall as a real one but unseen, grey bars over it.
// kept across runs: a value (no field of it changes)
let peek_net : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let peek_net_unseen : @ui.Style = @ui.css("w=Full opacity=O0")

///|
/// The bars over it, centred across its height: two on its left, two on its right (Bar 34 and 96, 132 and 132).
// kept across runs: a value (no field of it changes)
let peek_net_bars : @ui.Style = @ui.css("row w=Full h=Full align=ACenter")

///|
/// Each side's two, 9 apart: 8, and a pixel more over the second (the scale has no 9).
// kept across runs: a value (no field of it changes)
let peek_net_side : @ui.Style = @ui.css("gap=S2")

///|
// kept across runs: a value (no field of it changes)
let peek_net_side_fill : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let peek_net_second : @ui.Style = @ui.css("pt=SPx")

///|
let net_bar_h : Double = 10.0

///|
/// The machine in brief: what is left of it in the allowance's boxes (grey bars until it is read), its network under
/// them (Stations.kt StationFigures, `peek`).
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
              meter_chip(c, m)
            }
          })
          |> ignore
        _ =>
          c.box(style=peek_meters_unread, fn() {
            for w in unread_meters {
              @sf.bar(c, Px(w), unread_meter_h, radius=unread_meter_r, breathing=true)
            }
          })
          |> ignore
      }
    })
    |> ignore
    c.box(style=peek_net, fn() {
      // the room under the 6, the bars laid over that alone (matchParentSize inside the Box's padding: a layer covers
      // its parent's padding too)
      c.box(style=@sf.full_width, fn() {
        c.box(style=if net is Some(_) { @sf.full_width } else { peek_net_unseen }, fn() { net_line(c, net) }) |> ignore
        if net is None {
          c.layer(fn() { net_bars(c) }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The network's bars over its line's room, centred across it (Stations.kt's, in a station's card, its page and the
/// list): two on its left (Bar 34 and 96), two on its right (132 and 132).
fn net_bars(c : @ui.Ctx) -> Unit {
  c.box(style=peek_net_bars, fn() {
    net_side(c, peek_net_side_fill, 34.0, 96.0)
    net_side(c, peek_net_side, 132.0, 132.0)
  })
  |> ignore
}

///|
/// One side's two bars, `top` and `under` wide, breathing.
fn net_side(c : @ui.Ctx, side : @ui.Style, top : Double, under : Double) -> Unit {
  c.box(style=side, fn() {
    @sf.bar(c, Px(top), net_bar_h, breathing=true)
    c.box(style=peek_net_second, fn() { @sf.bar(c, Px(under), net_bar_h, breathing=true) }) |> ignore
  })
  |> ignore
}
