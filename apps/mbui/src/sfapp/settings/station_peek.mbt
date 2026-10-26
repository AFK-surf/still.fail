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
        @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
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
          let blocked = text(s, "blocked")
          c.text(
            if blocked != "" {
              blocked
            } else {
              fill("android-settings.stations.offline", [("app", "still.fail")])
            },
            style=peek_said,
          )
          |> ignore
        }
      }
    })
    |> ignore
    match field(field(s, "overview"), "drive") {
      Some(Object(_)) =>
        if @sf.menu_item(c, tr("android-misc.drive.title"), key="peek-card/drive/" + address, end="chevron-right") {
          (core.open_drive)(address)
        }
      _ => ()
    }
    if @sf.menu_item(c, tr("android-chat.station.details"), key="peek-card/station/" + address, end="chevron-right") {
      (core.push)(Station(address))
    }
  })
  |> ignore
}

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
    // where to go on: the panel's rows, their grounds out across its sides, their words on its line (in a dialog, at
    // its foot: concentric with its foot corners)
    @sf.dialog_foot_rows(c, peek_rows, fn() { peek_ways(c, core, address, s, close) })
  })
  |> ignore
}

///|
/// Where to go on from it: its files (docs/drive.md), where it has a drive, a way there from where it is named; its page.
fn peek_ways(c : @ui.Ctx, core : Core, address : String, s : Json?, close : () -> Unit) -> Unit {
  match field(field(s, "overview"), "drive") {
    Some(Object(_)) as drive => {
      let n = items(drive, "roots").length()
      if @sf.link_row(
          c,
          "peek-drive",
          tr("android-misc.drive.title"),
          value=if n == 0 {
            tr("android-misc.drive.row.none")
          } else {
            fill("android-misc.drive.roots.count", [("n", n.to_string())])
          },
        ) {
        close()
        (core.open_drive)(address)
      }
    }
    _ => ()
  }
  if @sf.link_row(c, "peek-station", tr("android-chat.station.details")) {
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
              @sf.meter_chip(c, m, key="station-peek/" + text(s, "station"))
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
