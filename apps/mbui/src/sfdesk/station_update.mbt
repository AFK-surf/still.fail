// A station's update, said in a chat's bar on the desktop (ember web/src/StationUpdate.tsx, StationUpdate.css.ts): a
// dot and a word in the accent's ink (red when it is in trouble); pressed, a small panel under it: the station's name
// and what is said, how far an update is, the versions and 立即更新 (`software.update` of the station). Whether it is
// open, closed or dismissed for this version is the core's (`station.updateNotice`), as is what it says (the chat
// view's `stationUpdate`).

///|
/// The control (StationUpdate's trigger) for station `station`'s `notice`, and its panel while the core says it is open.
fn station_update(c : @ui.Ctx, src : Source, station : String, notice : Json?) -> Unit {
  guard notice is Some(Object(_)) else { return }
  let trouble = text(notice, "tone") == "trouble"
  let open = flag(notice, "open")
  let id = c.id("station-update")
  c.cursor(id, Hand)
  if c.clicked(id) {
    c.tell("station-update/notice", fn() { update_notice(src, station, notice, if open { "close" } else { "open" }) })
  }
  let label = match text(notice, "label") {
    "" => text(notice, "text")
    l => l
  }
  let b = c.box(style=update_trigger, id~, fn() {
    c.box(style=if trouble { update_dot_trouble } else { update_dot }, id=c.id("station-update/dot"), fn() {  })
    |> ignore
    c.text(label, style=if trouble { update_label_trouble } else { update_label }) |> ignore
  })
  c.semantics(b, Button, id~, label=text(notice, "text"))
  let pop = @kit.popover(
    c,
    "station-update-pop",
    open,
    c.id("station-update/dot"),
    side=Bottom,
    along=Middle,
    look=fn(c, _, body) { @sf.small_panel(c, w=@ui.Size::Px(update_pop_w), body) |> ignore },
    fn() { update_panel(c, src, station, notice) },
  )
  // (closed as a popover closes: Escape, a press outside; the core keeps it so)
  if open && !pop.value {
    c.tell("station-update/notice", fn() { update_notice(src, station, notice, "close") })
  }
}

///|
/// The core told the notice is opened, closed or dismissed for this version (`station.updateNotice`).
fn update_notice(src : Source, station : String, notice : Json?, action : String) -> Unit {
  act(src, @sf.t("web-main.stationUpdate.noticeAction"), "", "station.updateNotice", {
    "station": Json::string(station),
    "action": Json::string(action),
    "version": Json::string(text(notice, "version")),
  })
}

///|
/// What its panel holds: its words in by a row's padding (the station's name and its state, or what is said; the
/// detail under them), its close (or 不再提醒此版本 where it may be dismissed) in the top right corner; how far an
/// update is while it goes; the versions and its one thing to do at the foot.
fn update_panel(c : @ui.Ctx, src : Source, station : String, notice : Json?) -> Unit {
  let on = [("station", station), ("id", "station")]
  let busy = core_doing(src, ["software.update"], on)
  let dismissible = flag(notice, "dismissible")
  c.box(style=update_head, fn() {
    c.box(style=update_words, fn() {
      match text(notice, "station") {
        "" => c.text(text(notice, "text"), style=update_name) |> ignore
        name =>
          c.box(style=update_title, fn() {
            c.text(name, style=update_name) |> ignore
            match text(notice, "label") {
              "" => ()
              l => c.text(l, style=if text(notice, "tone") == "trouble" { update_state_trouble } else { update_state }) |> ignore
            }
          })
          |> ignore
      }
      match text(notice, "detail") {
        "" => ()
        d => c.text(d, style=update_detail) |> ignore
      }
    })
    |> ignore
    let closing = if dismissible {
      @sf.t("web-main.stationUpdate.dismiss")
    } else {
      @sf.t("web-main.stationUpdate.collapse")
    }
    if @sf.panel_icon_button(c, "station-update/close", "close", closing) {
      c.tell("station-update/notice", fn() {
        update_notice(src, station, notice, if dismissible { "dismiss" } else { "close" })
      })
    }
  })
  |> ignore
  if text(notice, "tone") == "busy" && text(notice, "station") != "" {
    c.box(style=update_bar, fn() {
      @sf.progress(c, match opt_number(notice, "percent") {
        Some(p) => Some(p / 100.0)
        None => None
      })
    })
    |> ignore
  }
  let versions = [text(notice, "from"), text(notice, "to")].filter(fn(v) { v != "" })
  let can = flag(notice, "canUpdate")
  if versions.length() > 0 || can {
    c.box(style=update_foot, fn() {
      c.box(style=update_versions_room, fn() {
        if versions.length() > 0 {
          c.rich([@ui.span(versions.join(" → "), mono=true)], style=update_versions) |> ignore
        }
      })
      |> ignore
      if can {
        let words = if busy {
          @sf.t("web-main.stationUpdate.updating")
        } else if text(notice, "tone") == "trouble" {
          @sf.t("common.retry")
        } else {
          @sf.t("web-main.stationUpdate.updateNow")
        }
        if busy {
          @settings.doing_mark(c, true, None, inline=true)
        }
        if @sf.panel_button(c, "station-update/now", words, tone=Filled, disabled=busy) {
          c.tell("station-update/now", fn() {
            act(src, @sf.t("web-main.stationUpdate.updateAction"), "", "software.update", {
              "station": Json::string(station),
              "id": "station",
            })
          })
        }
      }
    })
    |> ignore
  }
}

///|
/// How wide its panel is (StationUpdate.css.ts popover: 288).
let update_pop_w : Double = 288.0

///|
/// The control (trigger): its dot (6) and word 5 apart, 6 over and under, 12 on 18, in the accent's ink; red in trouble.
// kept across runs: a value (no field of it changes)
let update_trigger : @ui.Style = @ui.css("row py=S1_5 gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let update_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=AccentText")

///|
// kept across runs: a value (no field of it changes)
let update_dot_trouble : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Danger")

///|
// kept across runs: a value (no field of it changes)
let update_label : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_label_trouble : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Danger, wrap=false)

///|
/// Its head (head): its words 10 in and 10 down, 2 apart; its close in the corner, 8 after them.
// kept across runs: a value (no field of it changes)
let update_head : @ui.Style = @ui.css("row w=Full pl=S2_5 gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let update_words : @ui.Style = @ui.style(w=@sf.grow, pt=S2_5, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let update_title : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
/// The name (13 in 500), its state (12, the accent's ink; red in trouble), the detail (12, muted).
// kept across runs: a value (no field of it changes)
let update_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_state : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_state_trouble : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_detail : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
/// How far it is (bar): on the words' line, 10 in.
// kept across runs: a value (no field of it changes)
let update_bar : @ui.Style = @ui.css("w=Full px=S2_5 pt=S2")

///|
/// Its foot (foot): 8 under what is over it, 24 high at least, 10 in; the versions (11 mono, muted) and its button
/// 12 apart.
// kept across runs: a value (no field of it changes)
let update_foot : @ui.Style = @ui.css("row w=Full min_h=S6 pt=S2 pl=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let update_versions_room : @ui.Style = @ui.style(w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let update_versions : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false, max_lines=1)
