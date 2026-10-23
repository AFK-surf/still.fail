// Settings pages the wide frame has as the web's has them (ember web/src/pages/Permissions.tsx, Archiving.tsx;
// archiving.ts): what the system lets still.fail do here, and 归档: whether a done chat suggests archiving it, then
// each station's own archiving, a page of its own each. The phone's settings say these elsewhere (the station's page).
// 通知 is web_notifications.mbt's.

// ---------------------------------------------------------------------------
// 权限

///|
/// 权限 (PermissionsPage): what the system lets still.fail do on this device, each with what it is for and whether it
/// is given; not given, what goes without it and the way to give it.
fn permissions_page(c : @ui.Ctx, core : Core) -> Unit {
  let notify = (core.topic)("notify", Map::new()).value
  let state = match text(notify, "permission") {
    "granted" | "denied" | "default" => text(notify, "permission")
    _ => "unknown"
  }
  let where_ = fill(
    if @ui.platform() == 0 {
      "web-pages.permissions.where.mac"
    } else {
      "web-pages.permissions.where.windows"
    },
    [("name", "still.fail")],
  )
  scroll_page(c, "permissions", [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.settings.nav.permissions")) },
    fn() { page_note(c, fill("web-pages.permissions.lead", [("name", "still.fail")])) },
    fn() {
      card(c, fn() {
        c.box(style=permission_box, fn() {
          c.box(style=permission_line, fn() {
            c.box(style=permission_icon, fn() {
              @sf.icon(c, "bell", size=@sf.row_icon, color=@sf.theme().p.text) |> ignore
            })
            |> ignore
            c.box(style=@sf.full_width, fn() {
              c.text(tr("web-pages.permissions.notify.name"), style=permission_name) |> ignore
              c.text(tr("web-pages.permissions.notify.purpose"), style=wide_row_sub_lines) |> ignore
            })
            |> ignore
            c.box(style=near_beside, fn() {
              if state == "granted" {
                @sf.icon(c, "check", size=@sf.row_icon, color=@sf.theme().p.muted) |> ignore
              }
              c.text(tr("web-pages.permissions.state." + state), style=wide_value) |> ignore
            })
            |> ignore
          })
          |> ignore
          if state == "default" || state == "denied" {
            c.box(style=permission_line, fn() {
              c.box(style=@sf.full_width, fn() {
                c.text(tr("web-pages.permissions.notify.without"), style=wide_row_title_lines) |> ignore
                if state == "denied" {
                  c.text(where_, style=wide_row_sub_lines) |> ignore
                }
              })
              |> ignore
              if state == "default" {
                if wide_button(c, "permission-allow", tr("web-pages.permissions.allow"), true) {
                  (core.notify_ask)()
                }
              } else if wide_button(c, "permission-open", tr("web-pages.permissions.open"), false) {
                open_notify_settings(core)
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
  ])
}

// ---------------------------------------------------------------------------
// 归档

///|
/// How a station archives on its own: never (no days), once idle, or once idle and recommended by its review.
fn archive_mode(v : Json?) -> String {
  if number(v, "days") <= 0.0 {
    "off"
  } else if flag(v, "reviewed") {
    "reviewed"
  } else {
    "idle"
  }
}

///|
/// Days, as a choice says them: none is never.
fn days_label(n : Double) -> String {
  if n <= 0.0 {
    tr("web-pages.archiving.never")
  } else {
    fill("web-pages.archiving.days", [("n", n.to_int().to_string())])
  }
}

///|
/// Whether a station's archive review (自动决策 › 完成检查) is on.
fn review_on(s : Json?) -> Bool {
  flag(field(field(field(field(s, "overview"), "automaticDecisions"), "settings"), "completion"), "enabled")
}

///|
/// What a station's page says of its archive review, the state alone (archiving.ts reviewOf short): on, by which model.
fn review_short(s : Json?) -> String {
  let ad = field(field(s, "overview"), "automaticDecisions")
  let rule = field(field(ad, "settings"), "completion")
  if !flag(rule, "enabled") {
    return tr("web-pages.archiving.reviewOffShort")
  }
  let id = text(rule, "model")
  let mut model = id
  for m in items(ad, "models") {
    if text(Some(m), "id") == id {
      model = text(Some(m), "name")
    }
  }
  fill("web-pages.archiving.reviewOnShort", [("model", model)])
}

///|
/// 归档 (ArchivingPage): whether a done chat suggests archiving it (this device's `archiveHint`), what that means and,
/// where no station reviews, the way to 自动决策; then each station's own archiving, a row each.
fn archiving_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let hint_now = match pref(core, "archiveHint") {
    "off" | "reviewed" => pref(core, "archiveHint")
    _ => "done"
  }
  let stations = match stations_of(core, here).value {
    Some(Array(a)) => a
    _ => []
  }
  let known = stations.filter(fn(s) { flag(Some(s), "online") && field(Some(s), "overview") is Some(Object(_)) })
  let reviewing = known.filter(fn(s) { review_on(Some(s)) })
  let not_reviewing = known.filter(fn(s) { !review_on(Some(s)) })
  let reviews = if known.length() == 0 || not_reviewing.length() == 0 {
    ""
  } else if reviewing.length() == 0 {
    tr("web-pages.archiving.hintNoReview")
  } else {
    fill("web-pages.archiving.hintSomeReview", [
      ("on", reviewing.map(fn(s) { text(Some(s), "name") }).join("、")),
      ("off", not_reviewing.map(fn(s) { text(Some(s), "name") }).join("、")),
    ])
  }
  let hints = ["off", "done", "reviewed"]
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.archiving.title")) },
    fn() {
      section_header(c, tr("web-pages.appearance.archive.title"))
      section_note(c, tr("web-pages.appearance.archive.description"))
    },
    fn() {
      let at = hints.search(hint_now).unwrap_or(1)
      inset(c, fn() {
        let picked = seg(c, "archiveHint", hints.map(fn(h) { tr("web-pages.appearance.archive." + h) }), at)
        if picked != at {
          set_pref(core, "archiveHint", if hints[picked] == "done" { "" } else { hints[picked] })
        }
      })
      c.box(style=archive_hint_box, fn() {
        c.text(tr("web-pages.appearance.archive." + hint_now + "Hint"), style=wide_row_sub_lines) |> ignore
        if reviews != "" && (hint_now == "reviewed" || reviewing.length() == 0) {
          c.box(style=near_beside, fn() {
            c.text(reviews, style=wide_row_sub_lines) |> ignore
          })
          |> ignore
          if tap_text(c, "archive-review-go", tr("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
            (core.push)(AutoCompletion)
          }
        }
      })
      |> ignore
    },
    fn() {
      section_header(c, tr("web-pages.archiving.auto.title"))
      section_note(c, tr("web-pages.archiving.auto.description"))
    },
  ]
  if stations_of(core, here).value is None {
    blocks.push(fn() { waiting_rows(c, count=1) })
  }
  for s in stations {
    let s = Some(s)
    blocks.push(fn() { archiving_row(c, core, s) })
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "archiving", blocks)
}

///|
/// A station's row (StationRow): online or not, its name, how it archives on its own in a line (or why that is not
/// known); it opens the station's page once it can say.
fn archiving_row(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let view = if flag(s, "online") { field(field(s, "overview"), "archiving") } else { None }
  let station = text(s, "station")
  inset(c, fn() {
    let line = match view {
      Some(Object(_)) as v => {
        let mode = archive_mode(v)
        let how = if mode == "off" {
          tr("web-pages.archiving.mode.off")
        } else {
          tr("web-pages.archiving.mode." + mode) + " · " + days_label(number(v, "days"))
        }
        let stalled = flag(v, "reviewed") && number(v, "days") > 0.0 && !review_on(s)
        if stalled {
          tr("web-pages.archiving.stalled")
        } else {
          fill("web-pages.archiving.summary", [("how", how), ("slack", days_label(number(v, "slackDays")))])
        }
      }
      _ =>
        if !flag(s, "online") {
          tr("web-pages.automaticDecisions.offline")
        } else if !(field(s, "overview") is Some(Object(_))) {
          tr("common.connecting")
        } else {
          tr("web-pages.archiving.upgrade")
        }
    }
    let opens = view is Some(Object(_))
    if list_row(c, key=if opens { "archiving/" + station } else { "" }, fn() {
        @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
        row_lines(c, text(s, "name"), line)
        if opens {
          chevron(c)
        }
      }) {
      (core.push)(StationArchiving(station))
    }
  })
}

///|
/// A station's own archiving (StationArchivingForm): its review (on or off, the way to it), how it archives, after how
/// long idle, and Slack's; only its managers change it (`canEdit`).
fn station_archiving_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let s = station_of(core, here, station)
  let view = if flag(s, "online") { field(field(s, "overview"), "archiving") } else { None }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("web-pages.archiving.title")) },
    fn() { large_title(c, text(s, "name")) },
  ]
  match view {
    Some(Object(_)) as v => {
      let busy = is_doing(core, ["archiving.save"], [("station", station)])
      let locked = !flag(v, "canEdit") || busy
      let save = fn(days : Double, slack : Double, reviewed : Bool) {
        act(
          core,
          tr("web-pages.archiving.saveWhat"),
          "archiving.save",
          obj([
            ("station", str(station)),
            ("days", Json::number(days)),
            ("slackDays", Json::number(slack)),
            ("reviewed", Json::boolean(reviewed)),
          ]),
          done=tr("web-pages.archiving.saved"),
        )
      }
      let days = number(v, "days")
      let slack = number(v, "slackDays")
      let mode = archive_mode(v)
      let review = review_on(s)
      if !flag(v, "canEdit") {
        blocks.push(fn() { page_note(c, tr("web-pages.archiving.adminOnly")) })
      }
      blocks.push(fn() {
        section_header(c, tr("web-pages.archiving.review"))
        c.box(style=archive_hint_box, fn() {
          c.text(review_short(s), style=wide_row_sub_lines) |> ignore
          if tap_text(c, "archiving-review-go", tr("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
            (core.push)(AutoCompletion)
          }
        })
        |> ignore
      })
      let modes = ["off", "idle", "reviewed"]
      blocks.push(fn() {
        section_header(c, tr("web-pages.archiving.mode"))
        let at = modes.search(mode).unwrap_or(0)
        inset(c, fn() {
          let picked = seg(c, "archiving-mode", modes.map(fn(m) { tr("web-pages.archiving.mode." + m) }), at)
          if picked != at && !locked {
            match modes[picked] {
              "off" => save(0.0, slack, false)
              "idle" => save(if days > 0.0 { days } else { archive_days[0] }, slack, false)
              _ => save(if days > 0.0 { days } else { archive_days[0] }, slack, true)
            }
          }
        })
        let mut note = tr("web-pages.archiving.mode." + mode + "Hint")
        if mode == "reviewed" && !review {
          note = note + " " + tr("web-pages.archiving.reviewNeeded")
        } else if !review {
          note = note + " " + tr("web-pages.archiving.stationNeedsReview")
        }
        c.box(style=archive_hint_box, fn() { c.text(note, style=wide_row_sub_lines) |> ignore }) |> ignore
      })
      if mode != "off" {
        blocks.push(fn() {
          section_header(c, tr("web-pages.archiving.idle"))
          let offered = days_offered(days, archive_days)
          let at = offered.search(days).unwrap_or(0)
          inset(c, fn() {
            let picked = seg(c, "archiving-idle", offered.map(days_label), at)
            if picked != at && !locked {
              save(offered[picked], slack, flag(v, "reviewed"))
            }
          })
        })
      }
      blocks.push(fn() {
        section_header(c, tr("web-pages.archiving.slack"))
        let offered = days_offered(slack, slack_days)
        let at = offered.search(slack).unwrap_or(0)
        inset(c, fn() {
          let picked = seg(c, "archiving-slack", offered.map(days_label), at)
          if picked != at && !locked {
            save(days, offered[picked], flag(v, "reviewed"))
          }
        })
        c.box(style=archive_hint_box, fn() {
          c.text(tr("web-pages.archiving.slackHint"), style=wide_row_sub_lines) |> ignore
        })
        |> ignore
      })
    }
    _ =>
      blocks.push(fn() {
        page_note(
          c,
          if !flag(s, "online") {
            tr("web-pages.automaticDecisions.offline")
          } else if !(field(s, "overview") is Some(Object(_))) {
            tr("common.connecting")
          } else {
            tr("web-pages.archiving.upgrade")
          },
        )
      })
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "station-archiving/" + station, blocks)
}

///|
/// A link in a note's words (12).
let link_size : Double = 12.0

///|
/// The days offered (archiving.ts IDLE_DAYS, SLACK_DAYS), with the one kept when it is none of them.
// kept across runs: a table, never written
let archive_days : Array[Double] = [1.0, 3.0, 7.0, 30.0]

///|
// kept across runs: a table, never written
let slack_days : Array[Double] = [0.0, 3.0, 7.0, 30.0]

///|
fn days_offered(kept : Double, base : Array[Double]) -> Array[Double] {
  if kept > 0.0 && !base.contains(kept) {
    let all = base.copy()
    all.push(kept)
    all.sort()
    all
  } else {
    base
  }
}

///|
/// A permission's card (Permissions.css.ts): its line, and what goes without it under it, 14 apart.
// kept across runs: a value (no field of it changes)
let permission_box : @ui.Style = @ui.style(w=Full, gap=S3_5)

///|
// kept across runs: a value (no field of it changes)
let permission_line : @ui.Style = @ui.style(row=true, w=Full, gap=S3, align=ACenter)

///|
/// Its icon in a disc of the page's ground (Permissions.css.ts icon: 36).
// kept across runs: a value (no field of it changes)
let permission_icon : @ui.Style = @ui.style(w=S9, h=S9, radius=Full, align=ACenter, justify=JCenter, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let permission_name : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
/// What a choice means, under it (chat.css.ts appearanceHint: 12, muted, 8 over it), 16 in.
// kept across runs: a value (no field of it changes)
let archive_hint_box : @ui.Style = @ui.style(w=Full, px=S4, pt=S2, gap=S1)
