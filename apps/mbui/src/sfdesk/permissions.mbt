// Settings pages the wide frame has as the web's has them (ember web/src/pages/Permissions.tsx, Archiving.tsx;
// archiving.ts): what the system lets still.fail do here, and 归档: whether a done chat suggests archiving it, then
// each station's own archiving, a page of its own each. The phone's settings say these elsewhere (the station's page).
// 通知 is notifications.mbt's.

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
  let where_ = @sf.t(
    if @ui.platform() == 0 {
      "web-pages.permissions.where.mac"
    } else {
      "web-pages.permissions.where.windows"
    },
    args=[("name", "still.fail")],
  )
  desk_page(
    c,
    core,
    "permissions",
    @sf.t("web-pages.settings.nav.permissions"),
    lead=@sf.t("web-pages.permissions.lead", args=[("name", "still.fail")]),
    [
      fn() {
        permission_row(
          c,
          "bell",
          @sf.t("web-pages.permissions.notify.name"),
          @sf.t("web-pages.permissions.notify.purpose"),
          @sf.t("web-pages.permissions.notify.without"),
          where_,
          state,
          fn() { (core.notify_ask)() },
          fn() { open_notify_settings(core) },
        )
      },
    ],
  )
}

///|
/// One permission (PermissionRow): a card, its round mark, what it is for and whether it is given (given in green, refused
/// in red); not given, what goes without it, where the system keeps it when refused, and the way to give it.
fn permission_row(
  c : @ui.Ctx,
  icon : String,
  name : String,
  purpose : String,
  without : String,
  where_ : String,
  state : String,
  allow : () -> Unit,
  open : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(style=desk_card, fn() {
    c.box(style=desk_card_row, fn() {
      c.box(style=permission_icon, fn() { @sf.icon(c, icon, size=permission_glyph, color=t.p.text) |> ignore }) |> ignore
      c.box(style=desk_card_text, fn() {
        c.text(name, style=desk_strong) |> ignore
        c.text(purpose, style=desk_muted) |> ignore
      })
      |> ignore
      c.box(style=permission_state, fn() {
        let ink = match state {
          "granted" => t.p.green_ink
          "denied" => t.p.red
          _ => t.p.muted
        }
        if state == "granted" {
          @sf.icon(c, "check", size=permission_check, color=ink) |> ignore
        }
        c.text(@sf.t("web-pages.permissions.state." + state), style=match state {
          "granted" => permission_state_given
          "denied" => permission_state_refused
          _ => permission_state_words
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    if state == "default" || state == "denied" {
      c.box(style=desk_card_row, fn() {
        c.box(style=desk_card_text, fn() {
          c.text(without, style=desk_words) |> ignore
          if state == "denied" {
            c.text(where_, style=desk_muted) |> ignore
          }
        })
        |> ignore
        if state == "default" {
          if @sf.button(c, @sf.t("web-pages.permissions.allow"), key="permission-allow", tone=Primary) {
            allow()
          }
        } else if @sf.button(c, @sf.t("web-pages.permissions.open"), key="permission-open") {
          open()
        }
      })
      |> ignore
    }
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// 归档

///|
/// How a station archives on its own: never (no days), once idle, or once idle and recommended by its review.
fn archive_mode(v : Json?) -> String {
  match text(v, "mode") {
    "" => "off"
    m => m
  }
}

///|
/// Days, as a choice says them: none is never.
fn days_label(n : Double) -> String {
  if n <= 0.0 {
    @sf.t("web-pages.archiving.never")
  } else {
    @sf.t("web-pages.archiving.days", args=[("n", n.to_int().to_string())])
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
    return @sf.t("web-pages.archiving.reviewOffShort")
  }
  let id = text(rule, "model")
  let mut model = id
  for m in items(ad, "models") {
    if text(Some(m), "id") == id {
      model = text(Some(m), "name")
    }
  }
  @sf.t("web-pages.archiving.reviewOnShort", args=[("model", model)])
}

///|
/// 归档 (ArchivingPage): whether a done chat suggests archiving it (this device's `archiveHint`), what that means and,
/// where no station reviews, the way to 自动决策; then each station's own archiving, a row each.
fn archiving_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let hint_now = match pref(core, "archiveHint") {
    "off" | "reviewed" => pref(core, "archiveHint")
    _ => "done"
  }
  let read = @settings.stations_of(core, here).value
  let stations = match read {
    Some(Array(a)) => a
    _ => []
  }
  let known = stations.filter(fn(s) { flag(Some(s), "online") && field(Some(s), "overview") is Some(Object(_)) })
  let reviewing = known.filter(fn(s) { review_on(Some(s)) })
  let not_reviewing = known.filter(fn(s) { !review_on(Some(s)) })
  // (hintReviews: what the stations' reviews say, where some or none review)
  let reviews = if known.length() == 0 || not_reviewing.length() == 0 {
    ""
  } else if reviewing.length() == 0 {
    @sf.t("web-pages.archiving.hintNoReview")
  } else {
    @sf.t("web-pages.archiving.hintSomeReview", args=[
      ("on", reviewing.map(fn(s) { text(Some(s), "name") }).join("、")),
      ("off", not_reviewing.map(fn(s) { text(Some(s), "name") }).join("、")),
    ])
  }
  let none_review = known.length() > 0 && reviewing.length() == 0
  let hints = ["off", "done", "reviewed"]
  desk_page(c, core, "archiving", @sf.t("web-pages.archiving.title"), [
    fn() {
      @sf.section(c, @sf.t("web-pages.appearance.archive.title"), note=@sf.t("web-pages.appearance.archive.description"), fn() {
        let at = hints.search(hint_now).unwrap_or(1)
        let mut picked = 0
        desk_choice(c, fn() { picked = @sf.segmented(c, "archiveHint", hints.map(fn(h) { @sf.t("web-pages.appearance.archive." + h) }), at) })
        // (按模型判断 not to be picked while no station reviews, unless it is what is set)
        if picked != at && !(hints[picked] == "reviewed" && none_review) {
          let next = if hints[picked] == "done" { "" } else { hints[picked] }
          c.after_build("archive-hint", fn() { set_pref(core, "archiveHint", next) })
        }
        desk_hint(c, @sf.t("web-pages.appearance.archive." + hint_now + "Hint"))
        if reviews != "" && (hint_now == "reviewed" || none_review) {
          c.box(style=desk_hint_line, fn() {
            c.text(reviews, style=desk_hint_words) |> ignore
            if tap_text(c, "archive-review-go", @sf.t("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
              (core.push)(AutoCompletion)
            }
          })
          |> ignore
        }
      })
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.archiving.auto.title"), note=@sf.t("web-pages.archiving.auto.description"), fn() {
        if read is None {
          @sf.wait_line(c, @sf.t("common.readingStations"), key="archiving-stations")
        }
        c.box(style=desk_list, fn() {
          for s in stations {
            archiving_row(c, core, Some(s))
          }
        })
        |> ignore
      })
    },
  ])
}

///|
/// A station's row (StationRow): online or not, its name, how it archives on its own in a line (red where it is set to
/// and cannot; or why that is not known); it opens the station's page once it can say.
fn archiving_row(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let t = @sf.theme()
  let view = if flag(s, "online") { field(field(s, "overview"), "archiving") } else { None }
  let station = text(s, "station")
  let mut bad = false
  let line = match view {
    Some(Object(_)) as v => {
      let stalled = flag(v, "reviewed") && number(v, "days") > 0.0 && !review_on(s)
      if stalled {
        bad = true
        @sf.t("web-pages.archiving.stalled")
      } else {
        text(v, "summaryText")
      }
    }
    _ =>
      if !flag(s, "online") {
        @sf.t("web-pages.automaticDecisions.offline")
      } else if !(field(s, "overview") is Some(Object(_))) {
        @sf.t("common.connecting")
      } else {
        @sf.t("web-pages.archiving.upgrade")
      }
  }
  let opens = view is Some(Object(_))
  let id = if opens { c.id("archiving/" + station) } else { 0 }
  if opens {
    c.cursor(id, Hand)
    if hit(c, id) {
      (core.push)(StationArchiving(station))
    }
  }
  c.box(style=if opens { desk_list_link } else { desk_list_row }, id~, fn() {
    @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
    c.box(style=desk_list_text, fn() {
      c.box(style=desk_named, fn() {
        if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
          @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), desk_mark, t.p.text)
        }
        c.text(text(s, "name"), style=desk_list_title) |> ignore
      })
      |> ignore
      c.text(line, style=if bad { desk_note_bad } else { desk_note }) |> ignore
    })
    |> ignore
    if opens {
      @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
    }
  })
  |> ignore
}

///|
/// A station's own archiving (StationArchivingForm): its review (on or off, the way to it), how it archives, after how
/// long idle, and Slack's; only its managers change it (`canEdit`).
fn station_archiving_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let s = station_of(core, here, station)
  let view = if flag(s, "online") { field(field(s, "overview"), "archiving") } else { None }
  let name = text(s, "name")
  let title = if name == "" {
    @sf.t("web-pages.archiving.auto.title")
  } else {
    @sf.t("web-pages.archiving.auto.title") + " · " + name
  }
  let blocks : Array[() -> Unit] = []
  match view {
    Some(Object(_)) as v => {
      let busy = is_doing(core, ["archiving.save"], [("station", station)])
      let locked = !flag(v, "canEdit") || busy
      let save = fn(days : Double, slack : Double, reviewed : Bool) {
        c.after_build("archiving-save", fn() {
          @settings.act(
            core,
            @sf.t("web-pages.archiving.saveWhat"),
            "archiving.save",
            obj([
              ("station", str(station)),
              ("days", Json::number(days)),
              ("slackDays", Json::number(slack)),
              ("reviewed", Json::boolean(reviewed)),
            ]),
            done=@sf.t("web-pages.archiving.saved"),
          )
        })
      }
      let days = number(v, "days")
      let slack = number(v, "slackDays")
      let mode = archive_mode(v)
      let review = review_on(s)
      if !flag(v, "canEdit") {
        blocks.push(fn() { desk_hint(c, @sf.t("web-pages.archiving.adminOnly")) })
      }
      // its review: how it stands and the way to it, said under the section's title
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.review"), fn() {
          c.box(style=desk_said_line, fn() {
            c.text(review_short(s) + " · ", style=desk_hint_words) |> ignore
            if tap_text(c, "archiving-review-go", @sf.t("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
              (core.push)(AutoCompletion)
            }
          })
          |> ignore
        })
      })
      let modes = ["off", "idle", "reviewed"]
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.mode"), fn() {
          let at = modes.search(mode).unwrap_or(0)
          let mut picked = 0
          desk_choice(c, fn() { picked = @sf.segmented(c, "archiving-mode", modes.map(fn(m) { @sf.t("web-pages.archiving.mode." + m) }), at) })
          if picked != at && !locked && !(modes[picked] == "reviewed" && !review) {
            match modes[picked] {
              "off" => save(0.0, slack, false)
              "idle" => save(if days > 0.0 { days } else { 1.0 }, slack, false)
              _ => save(if days > 0.0 { days } else { 1.0 }, slack, true)
            }
          }
          let mut note = @sf.t("web-pages.archiving.mode." + mode + "Hint")
          if mode == "reviewed" && !review {
            note = note + " " + @sf.t("web-pages.archiving.reviewNeeded")
          } else if !review {
            note = note + " " + @sf.t("web-pages.archiving.stationNeedsReview")
          }
          desk_hint(c, note)
        })
      })
      if mode != "off" {
        blocks.push(fn() {
          @sf.section(c, @sf.t("web-pages.archiving.idle"), fn() {
            let offered = items(v, "daysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) })
            let at = offered.search(days).unwrap_or(0)
            let mut picked = 0
            desk_choice(c, fn() { picked = @sf.segmented(c, "archiving-idle", offered.map(days_label), at) })
            if picked != at && !locked {
              save(offered[picked], slack, flag(v, "reviewed"))
            }
          })
        })
      }
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.slack"), fn() {
          let offered = items(v, "slackDaysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) })
          let at = offered.search(slack).unwrap_or(0)
          let mut picked = 0
          desk_choice(c, fn() { picked = @sf.segmented(c, "archiving-slack", offered.map(days_label), at) })
          if picked != at && !locked {
            save(days, offered[picked], flag(v, "reviewed"))
          }
          desk_hint(c, @sf.t("web-pages.archiving.slackHint"))
        })
      })
    }
    _ =>
      blocks.push(fn() {
        c.text(
          if !flag(s, "online") {
            @sf.t("web-pages.automaticDecisions.offline")
          } else if !(field(s, "overview") is Some(Object(_))) {
            @sf.t("common.connecting")
          } else {
            @sf.t("web-pages.archiving.upgrade")
          },
          style=desk_note,
        )
        |> ignore
      })
  }
  desk_page(c, core, "station-archiving/" + station, title, blocks, back=@sf.t("web-pages.archiving.title"))
}

///|
/// A link in a note's words (12).
let link_size : Double = 12.0


///|
/// A permission's mark (Permissions.css.ts icon: as tall as a button, round, on the canvas, its glyph 18), its state
/// at its first row's end (the meta's 12 in 500: given in green with a check 14, refused in red).
let permission_glyph : Double = 18.0

///|
let permission_check : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let permission_icon : @ui.Style = @ui.style(w=S9, h=S9, radius=Full, align=ACenter, justify=JCenter, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let permission_state : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let permission_state_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let permission_state_given : @ui.TextStyle = permission_state_words.then(@ui.text_style(color=Positive))

///|
// kept across runs: a value (no field of it changes)
let permission_state_refused : @ui.TextStyle = permission_state_words.then(@ui.text_style(color=Danger))
