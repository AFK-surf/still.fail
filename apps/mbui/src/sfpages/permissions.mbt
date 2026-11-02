// Settings pages the wide frame has as the web's has them (ember web/src/pages/Permissions.tsx, Archiving.tsx;
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
/// 归档 (ArchivingPage, ArchivingScreen): whether a done chat suggests archiving it (this device's `archiveHint`), what
/// that means and, where some or no station reviews, the way to 自动决策; then each station's own archiving, a row each.
pub fn archiving_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
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
        // (read the first time: rows' shapes where their card's rows will be, not a wait's line over an empty card)
        if read is None {
          @sf.group_waiting(c, text=@sf.t("common.readingStations"), fn() {
            for i, n in [5, 3] {
              archiving_row(c, core.quiet(), look, Some({
                "station": Json::string("sample/" + i.to_string()),
                "name": Json::string(@sf.sample_words(n)),
                "online": true,
                "overview": { "archiving": { "lineText": Json::string(@sf.sample_words(12)) } },
              }))
            }
          })
        } else {
          @sf.group(c, fn() {
            for s in stations {
              archiving_row(c, core, look, Some(s))
            }
          })
        }
        if look == Narrow {
          @sf.page_note(c, @sf.t("web-pages.archiving.auto.description"))
        }
      })
    },
  ])
}

///|
/// 归档 made once as nodes (archiving_page's, narrow: page_node) in node `v`: whether a done chat suggests archiving it
/// (its choice, what the one chosen means, the stations' reviews and the way to 自动决策 where some or none review, what
/// it is for), then each station's own archiving, a row each (in their bones while they are read the first time, its core
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
  @sf.page_node(v, fn() { @sf.t("web-pages.archiving.title") }, on_back~, frame~, said?=told, fn() { ["hint", "auto"] }, fn(b, key) {
    match key {
      "hint" => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.appearance.archive.title") })
        @sf.page_choice_node(
          b,
          fn() { hints.map(fn(h) { @sf.t("web-pages.appearance.archive." + h) }) },
          fn() { hints.search(hint_now()).unwrap_or(1) },
          fn(i) {
            // (the one set chosen again: nothing said; 按模型判断 not to be picked while no station reviews, unless it is
            // what is set)
            let at = hints.search(@signals.untracked(hint_now)).unwrap_or(1)
            if i != at && i >= 0 && i < hints.length() && !(hints[i] == "reviewed" && flag(said(), "hintNoReview")) {
              set_pref(core, "archiveHint", if hints[i] == "done" { "" } else { hints[i] })
            }
          },
        )
        @sf.page_note_node(b, fn() { @sf.t("web-pages.appearance.archive." + hint_now() + "Hint") })
        b.show(
          fn() { text(said(), "hintReviewText") != "" && (hint_now() == "reviewed" || flag(said(), "hintNoReview")) },
          fn(n) {
            n.padding(Is((archiving_note_x, archiving_note_top, archiving_note_x, archiving_note_foot))) |> ignore
            n.box(fn(w) {
              w
              .words(By(fn() { text(said(), "hintReviewText") }))
              .words_look(By(fn() { @ui.style_words(@sf.pg_note) }))
              .ink(By(fn() { @ui.style_ink(@sf.pg_note) }))
              |> ignore
            })
            |> ignore
            n.box(fn(l) {
              l.lines_up(Is(Some(Start))) |> ignore
              @sf.tap_text_node(l, fn() { @sf.t("web-pages.archiving.reviewGo") }, fn() { (core.push)(AutoCompletion) }, size=link_size)
            })
            |> ignore
          },
        )
        @sf.page_note_node(b, fn() { @sf.t("web-pages.appearance.archive.description") })
      }
      _ => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.archiving.auto.title") })
        b.pick(fn() { read() is None }, fn(p, reading) {
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
        @sf.page_note_node(b, fn() { @sf.t("web-pages.archiving.auto.description") })
      }
    }
  })
}

///|
/// archiving's note of the stations' reviews (narrow_note_box: pg_note_box's room, px=S3, pt=S2, pb=S1).
let archiving_note_x : Double = 12.0

///|
let archiving_note_top : Double = 8.0

///|
let archiving_note_foot : Double = 4.0

///|
/// `stations`' rows on a card as they are now, by their addresses (archiving_row's, as nodes).
fn archiving_rows_node(v : @view.View, core : Core, stint : () -> Int, stations : () -> Array[Json]) -> Unit {
  @sf.group_node(v, fn(g) {
    g.each(stations, fn(s) { text(Some(s), "station") }, fn(row, s) { archiving_row_node(row, core, stint, fn() { Some(s.get()) }) })
  })
}

///|
/// A station's row as a node (archiving_row's, narrow): its mark where it has one before its name, how it archives on
/// its own in a line (red where it is set to and cannot; or why that is not known); it opens the station's page once it
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
  let marked = fn() { @sf.has_station_mark(text(s(), "emoji"), text(s(), "icon")) }
  v.pick(fn() { (opens(), marked()) }, fn(r, how) {
    let (goes, mark) = how
    // (what is before its name, always there, its mark in it where it has one: archiving_lead's row, across the middle of
    // its name's line where lines are under it, as a row's lead is)
    let lead = @sf.LeadMade(fn(l) {
      l
      .row(Is(true))
      .gap(Is(8.0))
      .lines_up(Is(Some(Middle)))
      .min_height(By(fn() {
        l.words_redone() |> ignore
        Some(@ui.current().sp(@ui.tree_theme().text_size(Body).1))
      }))
      |> ignore
      if mark {
        @sf.station_mark_node(l, fn() { text(s(), "emoji") }, fn() { text(s(), "icon") }, @sf.row_mark, fn() {
          @sf.theme().p.text
        }, stint)
      }
    })
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
  let narrow = look == Narrow
  // (online or not before its words, wide; its mark before its name)
  let lead = fn() {
    c.box(style=archiving_lead, fn() {
      if !narrow {
        @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
      }
      if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
        @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), desk_mark, t.p.text)
      }
    })
    |> ignore
  }
  if @sf.link_row(
      c,
      "archiving/" + station,
      text(s, "name"),
      note=if bad { "" } else { line },
      trouble=if bad { line } else { "" },
      lead~,
      goes=opens,
    ) {
    (core.push)(StationArchiving(station))
  }
}

///|
/// What is before a station's name in its row: online or not, then its mark, 8 apart, across their middle.
// kept across runs: a value (no field of it changes)
let archiving_lead : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A station's own archiving (StationArchivingForm): its review (on or off, the way to it), how it archives, after how
/// long idle, and Slack's; only its managers change it (`canEdit`).
pub fn station_archiving_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, station : String) -> Unit {
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
/// A station's own archiving as nodes (station_archiving_page's, narrow): its review (how it stands, the way to it), how
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
  @sf.page_node(v, title, on_back~, frame~, said?, blocks, fn(b, key) {
    match key.split("/").to_array()[0].to_string() {
      "admin" => @sf.page_note_node(b, fn() { @sf.t("web-pages.archiving.adminOnly") })
      "review" => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.archiving.review") })
        // its review: how it stands, the way to it right after its words
        b.box(fn(n) {
          n.padding(Is((archiving_note_x, archiving_note_top, archiving_note_x, archiving_note_foot))) |> ignore
          n.box(fn(line) {
            line.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
            line.box(fn(w) {
              w
              .words(By(fn() { text(view(), "reviewText") + " · " }))
              .words_look(By(fn() { @ui.style_words(review_line_words) }))
              .ink(By(fn() { @ui.style_ink(review_line_words) }))
              |> ignore
            })
            |> ignore
            @sf.tap_text_node(line, fn() { @sf.t("web-pages.archiving.reviewGo") }, fn() { (core.push)(AutoCompletion) }, size=link_size)
          })
          |> ignore
        })
        |> ignore
      }
      "mode" => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.archiving.mode") })
        let modes = fn() { items(view(), "modes") }
        let at = fn() { modes().search_by(fn(m) { text(Some(m), "mode") == mode() }).unwrap_or(0) }
        @sf.page_choice_node(b, fn() { modes().map(fn(m) { text(Some(m), "label") }) }, at, fn(i) {
          let now = @signals.untracked(at)
          if i != now && !locked() {
            match @signals.untracked(modes).get(i) {
              Some(m) if flag(Some(m), "allowed") =>
                save(number(Some(m), "days"), @signals.untracked(fn() { number(view(), "slackDays") }), flag(Some(m), "reviewed"))
              _ => ()
            }
          }
        })
        @sf.page_note_node(b, fn() { text(view(), "modeNote") })
      }
      "idle" => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.archiving.idle") })
        let at = fn() { days_offered().search(number(view(), "days")).unwrap_or(0) }
        @sf.page_choice_node(b, fn() { strings(view(), "daysOfferedText") }, at, fn(i) {
          let now = @signals.untracked(at)
          let offered = @signals.untracked(days_offered)
          if i != now && !locked() && i < offered.length() {
            @signals.untracked(fn() { save(offered[i], number(view(), "slackDays"), flag(view(), "reviewed")) })
          }
        })
      }
      "slack" => {
        @sf.heading_node(b, fn() { @sf.t("web-pages.archiving.slack") })
        let at = fn() { slack_offered().search(number(view(), "slackDays")).unwrap_or(0) }
        @sf.page_choice_node(b, fn() { strings(view(), "slackDaysOfferedText") }, at, fn(i) {
          let now = @signals.untracked(at)
          let offered = @signals.untracked(slack_offered)
          if i != now && !locked() && i < offered.length() {
            @signals.untracked(fn() { save(number(view(), "days"), offered[i], flag(view(), "reviewed")) })
          }
        })
        @sf.page_note_node(b, fn() { @sf.t("web-pages.archiving.slackHint") })
      }
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
/// A station's review in a line (narrow_note_inline's: the secondary words, on one line).
// kept across runs: a value (no field of it changes)
let review_line_words : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

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
