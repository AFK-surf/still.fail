// A station's update, said in a chat's bar (ember apps/android shared/screens/StationUpdate.kt StationUpdateControl,
// web StationUpdate): a dot and a word in the accent (in red when it is in trouble); tapped, a popover under it with
// the station's name and what is said, how far an update is, the versions and 立即更新 (`software.update` of the
// station). Whether it is open, closed or dismissed for this version is the core's (`station.updateNotice`), as is
// what it says (the chat view's `stationUpdate`).

///|
/// Where the control was laid out (the frame before): the popover is put under it, its arrow at its dot.
priv struct UpdateAnchor {
  mut x : Double
  mut bottom : Double
}

///|
let update_anchor : UpdateAnchor = { x: 0.0, bottom: 0.0 }

///|
/// As at the start (tests).
fn update_anchor_reset() -> Unit {
  update_anchor.x = 0.0
  update_anchor.bottom = 0.0
}

///|
/// The control's dot and word, 5 apart, at least 32 high.
// kept across runs: a value (no field of it changes)
let update_control_row : @ui.Style = @ui.style(row=true, min_h=S8, gap=S1_25, align=ACenter)

///|
/// Its dot (6, round) and its word (12 on 18), in the accent's ink; red when it is in trouble.
// kept across runs: a value (no field of it changes)
let update_dot : @ui.Style = @ui.style(w=S1_5, h=S1_5, radius=Full, bg=AccentText)

///|
// kept across runs: a value (no field of it changes)
let update_dot_trouble : @ui.Style = update_dot.then(@ui.style(bg=Danger))

///|
// kept across runs: a value (no field of it changes)
let update_label : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, leading=L5, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_label_trouble : @ui.TextStyle = update_label.then(@ui.text_style(color=Danger))

///|
/// Whether it is said in red.
fn update_trouble(notice : Json?) -> Bool {
  text(notice, "tone") == "trouble"
}

///|
/// The control's width in the bar (what follows a chat's title is laid out by its width): its dot, its gap, its word.
fn update_control_w(notice : Json?) -> Double {
  let words = match text(notice, "label") {
    "" => text(notice, "text")
    l => l
  }
  let mut w = 0.0
  for ch in words {
    w = w + (if ch.to_int() > 0x2E80 { 12.0 } else { 7.0 })
  }
  6.0 + 5.0 + w
}

///|
/// Tells the core how the notice of `station`'s update now is: `open`, `close` or `dismiss` (for this version).
fn update_notice(src : Source, station : String, notice : Json?, action : String) -> Unit {
  act(src, tr("android-misc.stationUpdate.noticeWhat"), "station.updateNotice/" + station, "station.updateNotice", {
    "station": Json::string(station),
    "action": Json::string(action),
    "version": Json::string(text(notice, "version")),
  })
}

///|
/// The control in a chat's bar (StationUpdateControl), when the chat view says the station has an update.
fn station_update_control(c : @ui.Ctx, src : Source, station : String, notice : Json?) -> Unit {
  if !(notice is Some(Object(_))) {
    return
  }
  let trouble = update_trouble(notice)
  let id = c.id("station-update")
  c.cursor(id, Hand)
  if c.clicked(id) {
    update_notice(src, station, notice, if flag(notice, "open") { "close" } else { "open" })
  }
  match c.rect_of(id) {
    Some((x, y, _, h)) => {
      update_anchor.x = x
      update_anchor.bottom = y + h
    }
    None => ()
  }
  c.box(style=update_control_row, id~, fn() {
    c.box(style=if trouble { update_dot_trouble } else { update_dot }, fn() {  }) |> ignore
    c.text(
      match text(notice, "label") {
        "" => text(notice, "text")
        l => l
      },
      style=if trouble { update_label_trouble } else { update_label },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The popover's room: 12 round it (its arrow in the top 12), at most 308 wide (284 and its 12s), 12 from the window's
/// right edge.
let update_pop_most : Double = 308.0

///|
let update_pop_margin : Double = 12.0

///|
/// The control's dot's centre from its left (its dot: 6), and how far from the room's sides its arrow keeps.
let update_dot_center : Double = 3.0

///|
let update_arrow_keep : Double = 30.0

///|
/// What a tap beside the popover lands on: all of the window.
// kept across runs: a value (no field of it changes)
let update_scrim : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// The popover (24 round, raised, a soft shadow): 14 in on the left, 8 on the right, 12 over and 10 under; its rows 8
/// apart.
// kept across runs: a value (no field of it changes)
let update_pop : @ui.Style = @ui.style(
  w=Full,
  pl=S3_5,
  pr=S2,
  pt=S3,
  pb=S2_5,
  gap=S2,
  radius=Xl4,
  bg=Raised,
  shadow=Md,
)

///|
/// Its head: what is said and its close button, 8 apart.
// kept across runs: a value (no field of it changes)
let update_head : @ui.Style = @ui.style(row=true, w=Full, gap=S2, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let update_words : @ui.Style = @ui.style(w=Full, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let update_name_row : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
/// The station's name, or what is said where there is none (13 on 19, medium, the ink).
// kept across runs: a value (no field of it changes)
let update_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L4_75, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let update_said : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L4_75, w=Full)

///|
/// What more is said (12, muted; on 16.8, Xs's own, for Android's 17: off the scale's lines).
// kept across runs: a value (no field of it changes)
let update_detail : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
/// The versions it goes between (11 on 16, the code face, muted, on one line).
// kept across runs: a value (no field of it changes)
let update_versions : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, leading=L4, wrap=false)

///|
/// Its close button: 32, round, 4 up.
// kept across runs: a value (no field of it changes)
let update_close : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Full,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=A(Fg, O5)),
)

///|
/// The versions and 立即更新, 12 apart.
// kept across runs: a value (no field of it changes)
let update_foot : @ui.Style = @ui.style(row=true, w=Full, pr=SPx, gap=S3, align=ACenter)

///|
/// 立即更新: a pill on the accent's ground, 12 and 6 in, its spinner and word 4 apart.
// kept across runs: a value (no field of it changes)
let update_now : @ui.Style = @ui.style(
  row=true,
  px=S3,
  py=S1_5,
  gap=S1,
  radius=Full,
  bg=AccentBg,
  align=ACenter,
  pressed=@ui.patch(bg=Over(AccentBg, A(Fg, O5))),
)

///|
// kept across runs: a value (no field of it changes)
let update_now_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=AccentText, wrap=false)

///|
/// How far the update is, 4 short of its right.
// kept across runs: a value (no field of it changes)
let update_progress_room : @ui.Style = @ui.style(w=Full, pr=S1)

///|
/// The popover under the control while the core says it is open; a tap beside it closes it.
fn station_update_popover(c : @ui.Ctx, src : Source, station : String, notice : Json?) -> Unit {
  if !(notice is Some(Object(_))) || !flag(notice, "open") {
    return
  }
  let trouble = update_trouble(notice)
  let scrim = c.id("station-update-scrim")
  if c.clicked(scrim) {
    update_notice(src, station, notice, "close")
  }
  // the room (the popover and the 12 round it) right in the window less 12, its top 4 over the control's foot
  // (StationUpdate.kt: gap -4); its arrow at the control's dot, kept 30 from the room's sides
  let room_w = dmin(update_pop_most, c.width - update_pop_margin)
  let room_left = c.width - update_pop_margin - room_w
  let arrow = dmin(dmax(update_anchor.x + update_dot_center - room_left, update_arrow_keep), room_w - update_arrow_keep)
  c.layer(fn() { c.box(style=update_scrim, id=scrim, fn() {  }) |> ignore }) |> ignore
  c.layer(fn() {
    c.box(style=@ui.style(w=Fixed(room_w), p=S3), tx=room_left, ty=update_anchor.bottom - 4.0, fn() {
      c.box(style=@sf.full_width, fn() {
        // its arrow, from the popover's top edge up toward the control's dot (the layer is the room's inside, 12 in)
        c.layer(fn() {
          c.box(tx=arrow - 7.0 - update_pop_margin, ty=-7.0, fn() { @sf.popover_arrow(c, @sf.theme().p.raised) |> ignore })
          |> ignore
        })
        |> ignore
        c.box(style=update_pop, fn() {
          c.box(style=update_head, fn() {
            c.box(style=update_words, fn() {
              match opt_text(notice, "station") {
                Some(name) =>
                  c.box(style=update_name_row, fn() {
                    c.text(name, style=update_name) |> ignore
                    match opt_text(notice, "label") {
                      Some(l) => c.text(l, style=if trouble { update_label_trouble } else { update_label }) |> ignore
                      None => ()
                    }
                  })
                  |> ignore
                None => c.text(text(notice, "text"), style=update_said) |> ignore
              }
              match opt_text(notice, "detail") {
                Some(d) => c.text(d, style=update_detail) |> ignore
                None => ()
              }
            })
            |> ignore
            let close = c.id("station-update-close")
            if c.clicked(close) {
              update_notice(src, station, notice, if flag(notice, "dismissible") { "dismiss" } else { "close" })
            }
            c.box(style=update_close, id=close, fn() { @sf.icon(c, "close", size=14.0, color=@sf.theme().p.muted) |> ignore })
            |> ignore
          })
          |> ignore
          if text(notice, "tone") == "busy" && opt_text(notice, "station") is Some(_) {
            c.box(style=update_progress_room, fn() {
              @sf.progress(c, opt_number(notice, "percent").map(fn(p) { p / 100.0 }))
            })
            |> ignore
          }
          let versions = [opt_text(notice, "from"), opt_text(notice, "to")].filter_map(fn(v) { v })
          let can = flag(notice, "canUpdate")
          if versions.length() > 0 || can {
            c.box(style=update_foot, fn() {
              c.box(style=@sf.full_width, fn() {
                c.rich([@ui.span(versions.join(" → "), mono=true)], style=update_versions) |> ignore
              })
              |> ignore
              if can {
                update_now_button(c, src, station, notice)
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// 立即更新 (重试 in trouble; 更新中 with its spinner while it is under way): `software.update` of the station.
fn update_now_button(c : @ui.Ctx, src : Source, station : String, notice : Json?) -> Unit {
  let key = "software.update/" + station + "/station"
  let busy = doing(key)
  let id = if busy { 0 } else { c.id("station-update-now") }
  if id != 0 && c.clicked(id) {
    act(src, tr("android-misc.stationUpdate.updateWhat"), key, "software.update", {
      "station": Json::string(station),
      "id": Json::string("station"),
    })
  }
  c.box(style=update_now, id~, fn() {
    @settings.doing_mark(c, busy, if failed_lately(c, key) { Some("") } else { None }, inline=true)
    c.text(
      if busy {
        tr("android-misc.stationUpdate.updating")
      } else if text(notice, "tone") == "trouble" {
        tr("common.retry")
      } else {
        tr("android-misc.stationUpdate.updateNow")
      },
      style=update_now_words,
    )
    |> ignore
  })
  |> ignore
}
