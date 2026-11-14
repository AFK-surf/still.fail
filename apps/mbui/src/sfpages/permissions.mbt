// Settings pages the wide frame has as the web's has them (still.fail web/src/pages/Permissions.tsx, Archiving.tsx;
// archiving.ts): what the system lets still.fail do here, and 归档: whether a done chat suggests archiving it, then
// each station's own archiving, a page of its own each. The phone's settings say these elsewhere (the station's page).
// 通知 is notifications.mbt's.

// ---------------------------------------------------------------------------
// 权限

///|
/// 权限 (PermissionsPage) made once as nodes in node `v`, laid out by the `width` its frame gives it: what the system
/// lets still.fail do on this device, each with what it is for and whether it is given; not given, what goes without it
/// and the way to give it; each as the core says it now.
pub fn permissions_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let state = fn() {
    let notify = (core.topic)("notify", Map([])).get().value
    match text(notify, "permission") {
      "granted" | "denied" | "default" => text(notify, "permission")
      _ => "unknown"
    }
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.settings.nav.permissions") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.permissions.lead", args=[("name", "still.fail")]) },
    fn() { ["notify"] },
    fn(b, _key) {
      permission_row_node(
        b,
        "bell",
        fn() { @sf.t("web-pages.permissions.notify.name") },
        fn() { @sf.t("web-pages.permissions.notify.purpose") },
        fn() { @sf.t("web-pages.permissions.notify.without") },
        notice_where,
        state,
        fn() { (core.notify_ask)() },
        fn() { notice_settings_or_say(core) },
      )
    },
  )
}

///|
/// Where this system keeps whether still.fail may show notifications, once refused: a browser's site settings by its
/// address bar (a page opens none of them), macOS's or the others' settings.
fn notice_where() -> String {
  @sf.t(
    match @ui.platform() {
      0 => "web-pages.permissions.where.mac"
      4 => "web-pages.permissions.where.browser"
      _ => "web-pages.permissions.where.windows"
    },
    args=[("name", "still.fail")],
  )
}

///|
/// The system's settings of still.fail's notifications opened, to allow them once refused; where it has none to open
/// (a browser's page), where to allow them said instead, never nothing.
fn notice_settings_or_say(core : Core) -> Unit {
  if !@ui.notice_settings() {
    (core.say)(notice_where())
  }
}

///|
/// One permission (PermissionRow) as nodes: a card, its round mark, what it is for and whether it is given (given in
/// green with a check, refused in red); not given, what goes without it, where the system keeps it when refused, and the
/// way to give it (asked, or the system's settings opened); each as `state` says it now.
fn permission_row_node(
  parent : @view.View,
  icon : String,
  name : () -> String,
  purpose : () -> String,
  without : () -> String,
  where_ : () -> String,
  state : () -> String,
  allow : () -> Unit,
  open : () -> Unit,
) -> Unit {
  @sf.page_card_node(parent, fn(k) {
    k.box(fn(r) {
      @sf.style_node(r, fn() { desk_card_row })
      r.box(fn(m) {
        @sf.style_node(m, fn() { permission_icon }, in_row=true)
        @sf.icon_node(m, icon, permission_glyph, By(fn() { @sf.theme().p.text })) |> ignore
      })
      |> ignore
      r.box(fn(w) {
        @sf.style_node(w, fn() { desk_card_text }, in_row=true)
        @sf.words_node(w, name, fn() { desk_strong }) |> ignore
        @sf.words_node(w, purpose, fn() { desk_muted }) |> ignore
      })
      |> ignore
      r.box(fn(st) {
        @sf.style_node(st, fn() { permission_state }, in_row=true)
        st.show(fn() { state() == "granted" }, fn(c) {
          @sf.icon_node(c, "check", permission_check, By(fn() { @sf.theme().p.green_ink })) |> ignore
        })
        @sf.words_node(st, fn() { @sf.t("web-pages.permissions.state." + state()) }, fn() {
          match state() {
            "granted" => permission_state_given
            "denied" => permission_state_refused
            _ => permission_state_words
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    k.show(fn() { state() == "default" || state() == "denied" }, fn(r) {
      @sf.style_node(r, fn() { desk_card_row })
      r.box(fn(w) {
        @sf.style_node(w, fn() { desk_card_text }, in_row=true)
        @sf.words_node(w, without, fn() { desk_words }) |> ignore
        w.show(fn() { state() == "denied" }, fn(d) { @sf.words_node(d, where_, fn() { desk_muted }) |> ignore })
      })
      |> ignore
      r.pick(fn() { state() == "default" }, fn(p, asks) {
        if asks {
          @sf.button_node(p, fn() { @sf.t("web-pages.permissions.allow") }, allow, tone=Primary) |> ignore
        } else {
          @sf.button_node(p, fn() { @sf.t("web-pages.permissions.open") }, open) |> ignore
        }
      })
    })
  })
}

// ---------------------------------------------------------------------------
// 归档, one page in every frame, laid out by its width
// . How each station archives and what choosing each way saves, its review and what the hint 按模型判断
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
  let said = fn() { (core.topic)("settings", { "scope": str(here().workspace) }).get().value }
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
                  archiving_rows_node(
                    s,
                    core.quiet(),
                    stint,
                    fn() {
                      [5, 3].mapi(fn(i, n) {
                        Json::object({
                          "station": Json::string("sample/" + i.to_string()),
                          "name": Json::string(@sf.sample_words(n)),
                          "online": true,
                          "overview": {},
                        })
                      })
                    },
                    fn(_) { Some(Json::object({ "lineText": Json::string(@sf.sample_words(12)) })) },
                  )
                },
                note=fn() { { reading: true, text: @sf.t("common.readingStations"), failing: [] } },
              )
            } else {
              archiving_rows_node(
                p,
                core,
                stint,
                fn() {
                  match read() {
                    Some(Array(a)) => a
                    _ => []
                  }
                },
                fn(station) { @settings.station_part(core, here(), station, "archiving") },
              )
            }
          })
        })
    }
  })
}

///|
/// `stations`' rows on a card as they are now, by their addresses, each with how it archives (`archiving`: that part
/// of its overview, asked by each row of its own station).
fn archiving_rows_node(
  v : @view.View,
  core : Core,
  stint : () -> Int,
  stations : () -> Array[Json],
  archiving : (String) -> Json?,
) -> Unit {
  @sf.group_node(v, fn(g) {
    g.each(stations, fn(s) { text(Some(s), "station") }, fn(row, s) {
      let address = text(Some(s.untracked()), "station")
      archiving_row_node(row, core, stint, fn() { Some(s.get()) }, fn() { archiving(address) })
    })
  })
}

///|
/// A station's row (StationRow) as a node: online or not where the page is wide, its mark where it has one, before its
/// name; how it archives on its own in a line (`archiving`, its overview's part: red where it is set to and cannot; or
/// why that is not known); it opens the station's page once it can say.
fn archiving_row_node(v : @view.View, core : Core, stint : () -> Int, s : () -> Json?, archiving : () -> Json?) -> Unit {
  let view = fn() { if flag(s(), "online") { archiving() } else { None } }
  let line = fn() {
    match view() {
      Some(Object(_)) as v => text(v, "lineText")
      _ =>
        if !flag(s(), "online") {
          @sf.t("web-pages.automaticDecisions.offline")
        } else if !(field(s(), "overview") is Some(Object(_))) || view() is None {
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
  let days_offered = fn() { items(view(), "daysOffered").map(fn(n) { (if n is Number(n, ..) { Some(n) } else { None }).unwrap_or(0.0) }) }
  let slack_offered = fn() { items(view(), "slackDaysOffered").map(fn(n) { (if n is Number(n, ..) { Some(n) } else { None }).unwrap_or(0.0) }) }
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
    match key.split("/").to_array()[0].to_owned() {
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
/// A permission's mark (round, on the canvas, its glyph 18), its state
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
