// Settings pages the wide frame has as the web's has them (ember web/src/pages/Permissions.tsx, Archiving.tsx;
// archiving.ts): what the system lets still.fail do here, and 归档: whether a done chat suggests archiving it, then
// each station's own archiving, a page of its own each. The phone's settings say these elsewhere (the station's page).
// 通知 is notifications.mbt's.

// ---------------------------------------------------------------------------
// 权限

///|
/// 权限 (PermissionsPage): what the system lets still.fail do on this device, each with what it is for and whether it
/// is given; not given, what goes without it and the way to give it.
fn permissions_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
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
  @sf.page(c, on_back=core.pop, frame~, "permissions",
    @sf.t("web-pages.settings.nav.permissions"),
    lead=@sf.t("web-pages.permissions.lead", args=[("name", "still.fail")]),
    [
      fn() {
        permission_row(
          c,
          look,
          "bell",
          @sf.t("web-pages.permissions.notify.name"),
          @sf.t("web-pages.permissions.notify.purpose"),
          @sf.t("web-pages.permissions.notify.without"),
          where_,
          state,
          fn() { (core.notify_ask)() },
          fn() { open_notify_settings(c) },
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
  look : Look,
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
  @sf.page_card(c, fn() {
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
}

// ---------------------------------------------------------------------------
// 归档, one page in every frame (the web's pages/Archiving.tsx and mobile/Archiving.tsx), laid out by its width
// (page_look.mbt). How each station archives and what choosing each way saves, its review and what the hint 按模型判断
// means for the stations' reviews, are the core's (present.ts archiving, the `settings` view).

///|
/// 归档 (ArchivingPage, ArchivingScreen): whether a done chat suggests archiving it (this device's `archiveHint`), what
/// that means and, where some or no station reviews, the way to 自动决策; then each station's own archiving, a row each.
fn archiving_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let hint_now = match pref(core, "archiveHint") {
    "off" | "reviewed" => pref(core, "archiveHint")
    _ => "done"
  }
  let read = @settings.stations_of(core, here).value
  let stations = match read {
    Some(Array(a)) => a
    _ => []
  }
  let said = (core.topic)("settings", { "scope": str(here.workspace) }).value
  let reviews = text(said, "hintReviewText")
  let none_review = flag(said, "hintNoReview")
  let hints = ["off", "done", "reviewed"]
  @sf.page(c, on_back=core.pop, frame~, "archiving", @sf.t("web-pages.archiving.title"), [
    fn() {
      @sf.section(c, @sf.t("web-pages.appearance.archive.title"), heads=true, note=if look == Wide { @sf.t("web-pages.appearance.archive.description") } else { "" }, fn() {
        let at = hints.search(hint_now).unwrap_or(1)
        let picked = @sf.page_choice(c, "archiveHint", hints.map(fn(h) { @sf.t("web-pages.appearance.archive." + h) }), at)
        // (按模型判断 not to be picked while no station reviews, unless it is what is set)
        if picked != at && !(hints[picked] == "reviewed" && none_review) {
          let next = if hints[picked] == "done" { "" } else { hints[picked] }
          c.after_build("archive-hint", fn() { set_pref(core, "archiveHint", next) })
        }
        @sf.page_note(c, @sf.t("web-pages.appearance.archive." + hint_now + "Hint"))
        if reviews != "" && (hint_now == "reviewed" || none_review) {
          c.box(style=if look == Narrow { narrow_note_box } else { desk_hint_line }, fn() {
            c.text(reviews, style=if look == Narrow { narrow_note } else { desk_hint_words }) |> ignore
            if tap_text(c, "archive-review-go", @sf.t("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
              (core.push)(AutoCompletion)
            }
          })
          |> ignore
        }
        if look == Narrow {
          @sf.page_note(c, @sf.t("web-pages.appearance.archive.description"))
        }
      })
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.archiving.auto.title"), heads=true, note=if look == Wide { @sf.t("web-pages.archiving.auto.description") } else { "" }, fn() {
        if read is None {
          @sf.wait_line(c, @sf.t("common.readingStations"), key="archiving-stations")
        }
        @sf.group(c, fn() {
          for s in stations {
            archiving_row(c, core, look, Some(s))
          }
        })
        if look == Narrow {
          @sf.page_note(c, @sf.t("web-pages.archiving.auto.description"))
        }
      })
    },
  ])
}

///|
/// A station's row (StationRow): online or not, its name, how it archives on its own in a line (red where it is set to
/// and cannot; or why that is not known); it opens the station's page once it can say.
fn archiving_row(c : @ui.Ctx, core : Core, look : Look, s : Json?) -> Unit {
  let t = @sf.theme()
  let view = if flag(s, "online") { field(field(s, "overview"), "archiving") } else { None }
  let station = text(s, "station")
  let bad = flag(view, "stalled")
  let line = match view {
    Some(Object(_)) as v => text(v, "lineText")
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
    if hit(c, id) {
      (core.push)(StationArchiving(station))
    }
  }
  let narrow = look == Narrow
  c.box(style=match (narrow, opens) {
    (true, _) => narrow_row
    (false, true) => desk_list_link
    (false, false) => desk_list_row
  }, id~, fn() {
    if !narrow {
      @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
    }
    c.box(style=desk_list_text, fn() {
      c.box(style=desk_named, fn() {
        if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
          @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), desk_mark, t.p.text)
        }
        c.text(text(s, "name"), style=if narrow { narrow_row_title } else { desk_list_title }) |> ignore
      })
      |> ignore
      c.text(line, style=match (narrow, bad) {
        (true, true) => narrow_note_bad
        (true, false) => narrow_note
        (false, true) => desk_note_bad
        (false, false) => desk_note
      })
      |> ignore
    })
    |> ignore
    if opens {
      @sf.icon(c, "chevron-right", size=if narrow { narrow_chevron } else { desk_chevron }, color=if narrow { t.p.subtle } else { t.p.muted })
      |> ignore
    }
    if narrow && opens {
      finger_ripple(c, id)
    }
  })
  |> ignore
}

///|
/// A station's own archiving (StationArchivingForm): its review (on or off, the way to it), how it archives, after how
/// long idle, and Slack's; only its managers change it (`canEdit`).
fn station_archiving_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, station : String) -> Unit {
  let look = look_of(c)
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
      let mode = match text(v, "mode") {
        "" => "off"
        m => m
      }
      if !flag(v, "canEdit") {
        blocks.push(fn() { @sf.page_note(c, @sf.t("web-pages.archiving.adminOnly")) })
      }
      // its review: how it stands and the way to it
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.review"), heads=true, fn() {
          c.box(style=if look == Narrow { narrow_note_box } else { desk_said_line }, fn() {
            c.box(style=desk_said_line, fn() {
              // (its words as wide as they are, the way to it right after them)
              c.text(text(v, "reviewText") + " · ", style=if look == Narrow { narrow_note_inline } else { desk_hint_inline }) |> ignore
              if tap_text(c, "archiving-review-go", @sf.t("web-pages.archiving.reviewGo"), color=@sf.link_ink(), size=link_size) {
                (core.push)(AutoCompletion)
              }
            })
            |> ignore
          })
          |> ignore
        })
      })
      // how it archives: each way, what choosing it saves (the core's)
      let modes = items(v, "modes")
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.mode"), heads=true, fn() {
          let at = modes.search_by(fn(m) { text(Some(m), "mode") == mode }).unwrap_or(0)
          let picked = @sf.page_choice(c, "archiving-mode", modes.map(fn(m) { text(Some(m), "label") }), at)
          if picked != at && !locked {
            let m = Some(modes[picked])
            if flag(m, "allowed") {
              save(number(m, "days"), slack, flag(m, "reviewed"))
            }
          }
          @sf.page_note(c, text(v, "modeNote"))
        })
      })
      if mode != "off" {
        blocks.push(fn() {
          @sf.section(c, @sf.t("web-pages.archiving.idle"), heads=true, fn() {
            let offered = items(v, "daysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) })
            let at = offered.search(days).unwrap_or(0)
            let picked = @sf.page_choice(c, "archiving-idle", strings(v, "daysOfferedText"), at)
            if picked != at && !locked && picked < offered.length() {
              save(offered[picked], slack, flag(v, "reviewed"))
            }
          })
        })
      }
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.archiving.slack"), heads=true, fn() {
          let offered = items(v, "slackDaysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) })
          let at = offered.search(slack).unwrap_or(0)
          let picked = @sf.page_choice(c, "archiving-slack", strings(v, "slackDaysOfferedText"), at)
          if picked != at && !locked && picked < offered.length() {
            save(days, offered[picked], flag(v, "reviewed"))
          }
          @sf.page_note(c, @sf.t("web-pages.archiving.slackHint"))
        })
      })
    }
    _ =>
      blocks.push(fn() {
        @sf.page_note(c, if !flag(s, "online") {
            @sf.t("web-pages.automaticDecisions.offline")
          } else if !(field(s, "overview") is Some(Object(_))) {
            @sf.t("common.connecting")
          } else {
            @sf.t("web-pages.archiving.upgrade")
          },
        )
      })
  }
  @sf.page(c, on_back=core.pop, frame~, "station-archiving/" + station, title, blocks)
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
let permission_icon : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let permission_state : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let permission_state_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let permission_state_given : @ui.TextStyle = permission_state_words.then(@ui.text_style(color=Positive))

///|
// kept across runs: a value (no field of it changes)
let permission_state_refused : @ui.TextStyle = permission_state_words.then(@ui.text_style(color=Danger))
