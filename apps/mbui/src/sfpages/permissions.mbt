// Settings pages the wide frame has as the web's has them (still.fail web/src/pages/Permissions.tsx, Archiving.tsx;
// archiving.ts): what the system lets still.fail do here, and 归档: whether a done chat suggests archiving it, then
// each station's own archiving, a page of its own each. The phone's settings say these elsewhere (the station's page).
// 通知 is notifications.mbt's.

// ---------------------------------------------------------------------------
// 权限

///|
/// 权限 (PermissionsPage): what the system lets still.fail do on this device, each with what it is for and whether it
/// is given; not given, what goes without it and the way to give it.
pub fn permissions_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
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
/// 归档 (ArchivingPage, ArchivingScreen) made once as nodes in node `v`, laid out by the `width` its frame gives it:
/// whether a done chat suggests archiving it (its choice, what the one chosen means, the stations' reviews and the way to
/// 自动决策 where some or none review, what it is for), then each station's own archiving, a row each (in their bones while they are read the first time, its core
/// quiet for them), what that is for; all followed as the core says it. `here`: who and where, as that changes; `stint`:
/// the page's time on top, what a station's picture is asked for on.
pub fn archiving_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  // (what it says of itself to a frame's bar that names it: page_node's)
  let told = said
  let hints = ["off", "done", "reviewed"]
  let hint_now = fn() {
    match pref(core, "archiveHint") {
      "off" | "reviewed" => pref(core, "archiveHint")
      _ => "done"
    }
  }
  let read = fn() { @settings.stations_of(core, here()).value }
  let said = fn() { (core.topic)("settings", { "scope": str(here().workspace) }).value }
  @sf.page_node(v, fn() { @sf.t("web-pages.archiving.title") }, on_back~, frame~, said?=told, width?, fn() { ["hint", "auto"] }, fn(b, key) {
    match key {
      "hint" =>
        @sf.section_node(b, fn() { @sf.t("web-pages.appearance.archive.title") }, about=fn() { @sf.t("web-pages.appearance.archive.description") }, fn(sec) {
          @sf.page_choice_node(
            sec,
            fn() { hints.map(fn(h) { @sf.t("web-pages.appearance.archive." + h) }) },
            fn() { hints.search(hint_now()).unwrap_or(1) },
            fn(i) {
              // (the one set chosen again: nothing said; 按模型判断 not to be picked while no station reviews, unless it
              // is what is set)
              let at = hints.search(@signals.untracked(hint_now)).unwrap_or(1)
              if i != at && i >= 0 && i < hints.length() && !(hints[i] == "reviewed" && flag(said(), "hintNoReview")) {
                set_pref(core, "archiveHint", if hints[i] == "done" { "" } else { hints[i] })
              }
            },
          )
          @sf.page_note_node(sec, fn() { @sf.t("web-pages.appearance.archive." + hint_now() + "Hint") })
          sec.show(
            fn() { text(said(), "hintReviewText") != "" && (hint_now() == "reviewed" || flag(said(), "hintNoReview")) },
            fn(n) {
              @sf.note_link_node(n, fn() { text(said(), "hintReviewText") }, fn() { @sf.t("web-pages.archiving.reviewGo") }, fn() {
                (core.push)(AutoCompletion)
              })
            },
          )
        })
      _ =>
        @sf.section_node(b, fn() { @sf.t("web-pages.archiving.auto.title") }, about=fn() { @sf.t("web-pages.archiving.auto.description") }, fn(sec) {
          sec.pick(fn() { read() is None }, fn(p, reading) {
            if reading {
              @sf.waiting_node(
                p,
                fn(s) {
                  archiving_rows_node(s, core.quiet(), stint, fn() {
                    [5, 3].mapi(fn(i, n) {
                      Json::object({
                        "station": Json::string("sample/" + i.to_string()),
                        "name": Json::string(@sf.sample_words(n)),
                        "online": true,
                        "overview": { "archiving": { "lineText": Json::string(@sf.sample_words(12)) } },
                      })
                    })
                  })
                },
                note=fn() { { reading: true, text: @sf.t("common.readingStations"), failing: [] } },
              )
            } else {
              archiving_rows_node(p, core, stint, fn() {
                match read() {
                  Some(Array(a)) => a
                  _ => []
                }
              })
            }
          })
        })
    }
  })
}

///|
/// `stations`' rows on a card as they are now, by their addresses.
fn archiving_rows_node(v : @view.View, core : Core, stint : () -> Int, stations : () -> Array[Json]) -> Unit {
  @sf.group_node(v, fn(g) {
    g.each(stations, fn(s) { text(Some(s), "station") }, fn(row, s) { archiving_row_node(row, core, stint, fn() { Some(s.get()) }) })
  })
}

///|
/// A station's row (StationRow) as a node: online or not where the page is wide, its mark where it has one, before its
/// name; how it archives on its own in a line (red where it is set to and cannot; or why that is not known); it opens the station's page once it
/// can say.
fn archiving_row_node(v : @view.View, core : Core, stint : () -> Int, s : () -> Json?) -> Unit {
  let view = fn() { if flag(s(), "online") { field(field(s(), "overview"), "archiving") } else { None } }
  let line = fn() {
    match view() {
      Some(Object(_)) as v => text(v, "lineText")
      _ =>
        if !flag(s(), "online") {
          @sf.t("web-pages.automaticDecisions.offline")
        } else if !(field(s(), "overview") is Some(Object(_))) {
          @sf.t("common.connecting")
        } else {
          @sf.t("web-pages.archiving.upgrade")
        }
    }
  }
  let bad = fn() { flag(view(), "stalled") }
  let opens = fn() { view() is Some(Object(_)) }
  v.pick(opens, fn(r, goes) {
    // (what is before its name: online or not where the page is wide, its mark where it has one)
    let lead = @sf.station_lead(fn() { flag(s(), "online") }, fn() { text(s(), "emoji") }, fn() { text(s(), "icon") }, stint)
    @sf.link_row_node(
      r,
      fn() { text(s(), "name") },
      fn() { (core.push)(StationArchiving(text(s(), "station"))) },
      note=fn() { if bad() { "" } else { line() } },
      trouble=fn() { if bad() { line() } else { "" } },
      lead~,
      goes~,
    )
  })
}

///|
/// A station's own archiving (StationArchivingForm) as nodes, laid out by the `width` its frame gives it: its review (how it stands, the way to it), how
/// it archives, after how long idle (where it archives), and Slack's, each a choice of the ways the core offers and a
/// note; only its managers change it (`canEdit`: else said so first, and no choice saves), and none while a save of it
/// is on its way. A way the core does not allow (reviewed where nothing reviews) is not saved; nor the one chosen
/// again. Offline, connecting, or a station too old to say: that, alone.
pub fn station_archiving_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  station : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let s = fn() { station_of(core, here(), station) }
  let view = fn() { if flag(s(), "online") { field(field(s(), "overview"), "archiving") } else { None } }
  let title = fn() {
    match text(s(), "name") {
      "" => @sf.t("web-pages.archiving.auto.title")
      name => @sf.t("web-pages.archiving.auto.title") + " · " + name
    }
  }
  let mode = fn() {
    match text(view(), "mode") {
      "" => "off"
      m => m
    }
  }
  let days_offered = fn() { items(view(), "daysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) }) }
  let slack_offered = fn() { items(view(), "slackDaysOffered").map(fn(n) { n.as_number().unwrap_or(0.0) }) }
  // (as it is when a choice is made: what it reads not followed by what chose)
  let locked = fn() {
    @signals.untracked(fn() {
      !flag(view(), "canEdit") || is_doing(core, ["archiving.save"], [("station", station)])
    })
  }
  let save = fn(days : Double, slack : Double, reviewed : Bool) {
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
  }
  // (each choice's block by how many ways it offers: a choice is made for as many as it has, made again for another
  // number)
  let blocks = fn() {
    match view() {
      Some(Object(_)) as v => {
        let out = []
        if !flag(v, "canEdit") {
          out.push("admin")
        }
        out.push("review")
        out.push("mode/" + items(v, "modes").length().to_string())
        if mode() != "off" {
          out.push("idle/" + strings(v, "daysOfferedText").length().to_string())
        }
        out.push("slack/" + strings(v, "slackDaysOfferedText").length().to_string())
        out
      }
      _ => ["said"]
    }
  }
  @sf.page_node(v, title, on_back~, frame~, said?, width?, blocks, fn(b, key) {
    match key.split("/").to_array()[0].to_string() {
      "admin" => @sf.page_note_node(b, fn() { @sf.t("web-pages.archiving.adminOnly") })
      // its review: how it stands, the way to it right after its words
      "review" =>
        @sf.section_node(b, fn() { @sf.t("web-pages.archiving.review") }, fn(sec) {
          @sf.note_link_node(sec, fn() { text(view(), "reviewText") + " · " }, fn() { @sf.t("web-pages.archiving.reviewGo") }, fn() {
            (core.push)(AutoCompletion)
          }, inline=true)
        })
      "mode" =>
        @sf.section_node(b, fn() { @sf.t("web-pages.archiving.mode") }, fn(sec) {
          let modes = fn() { items(view(), "modes") }
          let at = fn() { modes().search_by(fn(m) { text(Some(m), "mode") == mode() }).unwrap_or(0) }
          @sf.page_choice_node(sec, fn() { modes().map(fn(m) { text(Some(m), "label") }) }, at, fn(i) {
            let now = @signals.untracked(at)
            if i != now && !locked() {
              match @signals.untracked(modes).get(i) {
                Some(m) if flag(Some(m), "allowed") =>
                  save(number(Some(m), "days"), @signals.untracked(fn() { number(view(), "slackDays") }), flag(Some(m), "reviewed"))
                _ => ()
              }
            }
          })
          @sf.page_note_node(sec, fn() { text(view(), "modeNote") })
        })
      "idle" =>
        @sf.section_node(b, fn() { @sf.t("web-pages.archiving.idle") }, fn(sec) {
          let at = fn() { days_offered().search(number(view(), "days")).unwrap_or(0) }
          @sf.page_choice_node(sec, fn() { strings(view(), "daysOfferedText") }, at, fn(i) {
            let now = @signals.untracked(at)
            let offered = @signals.untracked(days_offered)
            if i != now && !locked() && i < offered.length() {
              @signals.untracked(fn() { save(offered[i], number(view(), "slackDays"), flag(view(), "reviewed")) })
            }
          })
        })
      "slack" =>
        @sf.section_node(b, fn() { @sf.t("web-pages.archiving.slack") }, fn(sec) {
          let at = fn() { slack_offered().search(number(view(), "slackDays")).unwrap_or(0) }
          @sf.page_choice_node(sec, fn() { strings(view(), "slackDaysOfferedText") }, at, fn(i) {
            let now = @signals.untracked(at)
            let offered = @signals.untracked(slack_offered)
            if i != now && !locked() && i < offered.length() {
              @signals.untracked(fn() { save(number(view(), "days"), offered[i], flag(view(), "reviewed")) })
            }
          })
          @sf.page_note_node(sec, fn() { @sf.t("web-pages.archiving.slackHint") })
        })
      _ =>
        @sf.page_note_node(b, fn() {
          if !flag(s(), "online") {
            @sf.t("web-pages.automaticDecisions.offline")
          } else if !(field(s(), "overview") is Some(Object(_))) {
            @sf.t("common.connecting")
          } else {
            @sf.t("web-pages.archiving.upgrade")
          }
        })
    }
  })
}

///|
/// A link in a note's words (12).
pub let link_size : Double = 12.0


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

///|
/// The system's settings of this app's notifications, where they are allowed again once refused (the host knows where:
/// Android's page of the app's notifications, iOS's, macOS's and Windows' Notifications), told as the frame ends.
fn open_notify_settings(c : @ui.Ctx) -> Unit {
  c.tell("notify-settings", fn() { @ui.notice_settings() |> ignore })
}
