// Settings pages the wide frame has as the web's has them (ember web/src/pages/Notifications.tsx, Permissions.tsx,
// Archiving.tsx; archiving.ts): what this device tells its person of their chats and how (a banner, each kind of thing
// that happens with whether it comes as one), what the system lets still.fail do here, and 归档: whether a done chat
// suggests archiving it, then each station's own archiving, a page of its own each. The phone's settings say these
// elsewhere (SettingsHome.kt's switch, the station's page).

// ---------------------------------------------------------------------------
// 通知

///|
/// The kinds of thing that happen that are told of (Notifications.tsx KINDS_SHOWN), in the order shown.
// kept across runs: a table, never written
let notify_kinds : Array[String] = ["wait", "failed", "done", "message"]

///|
/// As at the start (core.mbt reset): no kind opened, nothing chosen.
fn notify_page_reset() -> Unit {
  kind_open.val = ""
  kinds_chosen.clear()
  badge_chosen.clear()
}

///|
/// What was just chosen of what the app's icon counts before the prefs say it back (`badgeKinds`), by kind ("on" the
/// badge itself).
let badge_chosen : Map[String, Bool] = {}

///|
/// What the badge counts as kept (prefs `badgeKinds`; Notifications.tsx BADGE_DEFAULT where none is): itself on, the
/// waits and failures, not done turns nor messages.
fn badge_kind(core : Core, kind : String) -> Bool {
  match badge_chosen.get(kind) {
    Some(v) => v
    None =>
      match field(field((core.topic)("prefs", Map::new()).value, "badgeKinds"), kind) {
        Some(True) => true
        Some(False) => false
        _ => kind == "on" || kind == "wait" || kind == "failed"
      }
  }
}

///|
/// What the badge counts changed (`prefs.set {badgeKinds: {kind: on}}`): shown at once.
fn set_badge_kind(core : Core, kind : String, on : Bool) -> Unit {
  badge_chosen[kind] = on
  (core.call)("prefs.set", obj([("badgeKinds", obj([(kind, Json::boolean(on))]))]), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => {
        badge_chosen.remove(kind)
        (core.say)(fill("web-pages.notifications.kindsFailed", [("error", error_text(e))]))
      }
    }
  })
}

///|
/// Whether this app shows a badge where it runs (macOS's Dock tile).
fn badge_here() -> Bool {
  @ui.platform() == 0
}

///|
/// The kind opened on the page to show its ways ("" none).
let kind_open : Ref[String] = Ref("")

///|
/// What was just chosen of the kinds before the core says it back (`notify.set` `kinds`), by kind.
let kinds_chosen : Map[String, Json] = {}

///|
/// Whether `kind` comes as a banner now (Notifications.tsx banner): notifications on, and the kind's own; a done turn
/// unless off.
fn kind_banner(notify : Json?, kind : String) -> Bool {
  if notify is Some(_) && !flag(notify, "on") {
    return false
  }
  let kinds = field(notify, "kinds")
  let now = match kinds_chosen.get(kind) {
    Some(v) => Some(v)
    None => field(kinds, kind)
  }
  match (kind, now) {
    ("done", Some(String(v))) => v != "off"
    ("done", _) => true
    (_, Some(False)) => false
    _ => true
  }
}

///|
/// A done turn's banner: off, while away (the default), or always.
fn done_banner(notify : Json?) -> String {
  match kinds_chosen.get("done") {
    Some(String(v)) => v
    _ =>
      match field(field(notify, "kinds"), "done") {
        Some(String(v)) if v != "" => v
        _ => "away"
      }
  }
}

///|
/// The kinds changed (`notify.set` `kinds`): shown at once, the core's word taken back if it fails.
fn set_kind(core : Core, kind : String, value : Json) -> Unit {
  kinds_chosen[kind] = value
  (core.call)("notify.set", obj([("kinds", obj([(kind, value)]))]), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => {
        kinds_chosen.remove(kind)
        (core.say)(fill("web-pages.notifications.kindsFailed", [("error", error_text(e))]))
      }
    }
  })
}

///|
/// 通知 (NotificationsPage): 提醒方式, its banner a tile (on or off; the system's word asked first, or its settings
/// opened where it refused); 通知类别, a row each saying what tells of it, opened to change that; 其他, whether a notice
/// says what was said.
fn notify_page(c : @ui.Ctx, core : Core) -> Unit {
  let notify = (core.topic)("notify", Map::new()).value
  // what was chosen, once the core says it
  for k in notify_kinds {
    match (kinds_chosen.get(k), field(field(notify, "kinds"), k)) {
      (Some(a), Some(b)) if a == b => kinds_chosen.remove(k)
      _ => ()
    }
  }
  let kept_badge = field((core.topic)("prefs", Map::new()).value, "badgeKinds")
  for k in ["on", "wait", "failed", "done", "message"] {
    match (badge_chosen.get(k), field(kept_badge, k)) {
      (Some(true), Some(True)) | (Some(false), Some(False)) => badge_chosen.remove(k)
      _ => ()
    }
  }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.settings.nav.notifications")) },
  ]
  if notify is None {
    blocks.push(fn() { waiting_cards(c) })
    scroll_page(c, "notify", blocks)
    return
  }
  let permission = text(notify, "permission")
  let pending = is_doing(core, ["notify.set"], []) || notify_switched.val is Some(_)
  let on = match notify_switched.val {
    Some(v) => v
    None => flag(notify, "on")
  }
  blocks.push(fn() {
    section_header(c, tr("web-pages.notifications.ways.title"))
    section_note(c, tr("web-pages.notifications.noteDevice"))
  })
  blocks.push(fn() {
    inset(c, fn() {
      let id = c.id("notify-banner")
      let action = match permission {
        "denied" => tr("web-pages.notifications.enable.open")
        "default" => tr("web-pages.notifications.enable.allow")
        _ => ""
      }
      if hit(c, id) && !pending {
        match permission {
          "denied" => open_notify_settings(core)
          "default" => (core.notify_ask)()
          _ => use_notify(core, !on)
        }
      }
      c.cursor(id, Hand)
      let lit = on && action == ""
      // (two to a line, as the web's tiles are: the badge's beside it where there is one)
      c.box(style=way_tiles, fn() {
      c.box(style=if lit { way_tile_on } else { way_tile }, id~, fn() {
        c.box(style=way_picture, fn() { c.box(style=way_banner, fn() {  }) |> ignore }) |> ignore
        c.text(tr("web-pages.notifications.ways.banner"), style=way_name) |> ignore
        if pending {
          spinner(c, inline=true)
        } else if action != "" {
          c.box(style=near_beside, fn() {
            c.text(action, style=way_action) |> ignore
            chevron(c)
          })
          |> ignore
        } else {
          c.text(tr(if on { "web-pages.notifications.on" } else { "web-pages.notifications.off" }), style=wide_meta)
          |> ignore
        }
      })
      |> ignore
      if badge_here() {
        let bid = c.id("notify-badge")
        let badge_on = badge_kind(core, "on")
        c.cursor(bid, Hand)
        if hit(c, bid) {
          c.after_build("notify-badge", fn() { set_badge_kind(core, "on", !badge_on) })
        }
        c.box(style=if badge_on { way_tile_on } else { way_tile }, id=bid, fn() {
          c.box(style=way_picture_app, fn() {
            c.box(style=way_app, fn() { c.box(style=way_dot, fn() {  }) |> ignore }) |> ignore
          })
          |> ignore
          c.text(tr("web-pages.notifications.ways.badge"), style=way_name) |> ignore
          c.text(tr(if badge_on { "web-pages.notifications.on" } else { "web-pages.notifications.off" }), style=wide_meta)
          |> ignore
        })
        |> ignore
      } else {
        c.box(style=way_tile_room, fn() {  }) |> ignore
      }
      // 桌面浮窗 (the desktop's dock: the Mac's, dock_settings.mbt)
      if @ui.dock_available() {
        let did = c.id("notify-dock")
        let dock_on = dock_setting("on")
        c.cursor(did, Hand)
        if hit(c, did) {
          dock_set("on", !dock_on)
        }
        c.box(style=if dock_on { way_tile_on } else { way_tile }, id=did, fn() {
          c.box(style=way_picture_dock, fn() { c.box(style=way_edge, fn() {  }) |> ignore }) |> ignore
          c.text(tr("web-pages.notifications.ways.dock"), style=way_name) |> ignore
          c.text(tr(if dock_on { "web-pages.notifications.on" } else { "web-pages.notifications.off" }), style=wide_meta)
          |> ignore
        })
        |> ignore
      }
      })
      |> ignore
    })
  })
  blocks.push(fn() { section_header(c, tr("web-pages.notifications.kinds.title")) })
  blocks.push(fn() {
    list_card(c, boxed=true, fn() {
      for kind in notify_kinds {
        kind_row(c, core, notify, kind, on)
      }
    })
  })
  blocks.push(fn() { section_header(c, tr("web-pages.notifications.more.title")) })
  blocks.push(fn() {
    list_card(c, boxed=true, fn() {
      let preview = flag(notify, "preview") || field(notify, "preview") is None
      if list_row(c, key=if on { "notify-preview" } else { "" }, fn() {
          row_lines(c, tr("web-pages.notifications.preview"), tr("web-pages.notifications.previewNote"), wrap_sub=true)
          @sf.switch_look(c, "notify-preview", preview)
        }) {
        act(core, tr("web-pages.notifications.preview"), "notify.set", obj([("preview", Json::boolean(!preview))]))
      }
    })
    // new ones peeking out of the dock, or only waiting at the edge
    if @ui.dock_available() {
      list_card(c, boxed=true, fn() {
        let peek = dock_setting("peek")
        if list_row(c, key=if dock_setting("on") { "dock-peek" } else { "" }, fn() {
            row_lines(c, tr("web-pages.dock.peek"), tr("web-pages.dock.peekNote"), wrap_sub=true)
            @sf.switch_look(c, "dock-peek", peek)
          }) {
          dock_set("peek", !peek)
        }
      })
    }
    if @ui.platform() == 0 {
      section_note(c, fill("web-pages.notifications.sound", [("name", "still.fail")]))
    }
  })
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "notify", blocks)
}

///|
/// A kind's row (KindRow): its name and what it is, what tells of it in a line, a chevron; opened, its banner (a done
/// turn's: off, while away, always).
fn kind_row(c : @ui.Ctx, core : Core, notify : Json?, kind : String, on : Bool) -> Unit {
  let banner = kind_banner(notify, kind)
  let badged = badge_here() && badge_kind(core, "on") && badge_kind(core, kind)
  let ways : Array[String] = []
  if banner {
    ways.push(
      if kind == "done" && done_banner(notify) == "away" {
        tr("web-pages.notifications.sumBannerAway")
      } else {
        tr("web-pages.notifications.ways.banner")
      },
    )
  }
  if badged {
    ways.push(tr("web-pages.notifications.ways.badge"))
  }
  if @ui.dock_available() && dock_setting("on") && dock_setting(kind) {
    ways.push(tr("web-pages.notifications.ways.dock"))
  }
  let sum = if ways.length() == 0 { tr("web-pages.notifications.none") } else { ways.join(" · ") }
  let open = kind_open.val == kind
  if list_row(c, key="notify-kind/" + kind, fn() {
      row_lines(c, tr("web-pages.notifications.kinds." + kind), tr("web-pages.notifications.kinds." + kind + "Note"))
      c.text(sum, style=wide_value) |> ignore
      chevron(c)
    }) {
    kind_open.val = if open { "" } else { kind }
  }
  if open {
    c.box(style=kind_ways, fn() {
      if kind == "done" {
        c.box(style=way_row, fn() {
          c.text(tr("web-pages.notifications.ways.banner"), style=wide_row_title) |> ignore
          let ways = ["off", "away", "always"]
          let now = done_banner(notify)
          let at = ways.search(now).unwrap_or(1)
          let picked = seg(
            c,
            "notify-done",
            [
              tr("web-pages.notifications.kinds.doneOff"),
              tr("web-pages.notifications.kinds.doneAway"),
              tr("web-pages.notifications.kinds.doneAlways"),
            ],
            at,
          )
          if picked != at && on {
            // (told once the frame's builds are over)
            c.after_build("notify-done", fn() { set_kind(core, "done", str(ways[picked])) })
          }
        })
        |> ignore
      } else if list_row(c, key=if on { "notify-way/" + kind } else { "" }, fn() {
          row_title(c, tr("web-pages.notifications.ways.banner"))
          @sf.switch_look(c, "notify-way/" + kind, banner)
        }) {
        set_kind(core, kind, Json::boolean(!banner))
      }
      // 显示在桌面浮窗: whether the dock holds it (off while the dock is)
      if @ui.dock_available() {
        let held = dock_setting(kind)
        if list_row(c, key=if dock_setting("on") { "notify-dock/" + kind } else { "" }, fn() {
            row_title(c, tr("web-pages.notifications.inDock"))
            @sf.switch_look(c, "notify-dock/" + kind, held)
          }) {
          dock_set(kind, !held)
        }
      }
      // 计入红点: whether the app's icon counts it (off while the badge is)
      if badge_here() {
        let counted = badge_kind(core, kind)
        if list_row(c, key=if badge_kind(core, "on") { "notify-badge/" + kind } else { "" }, fn() {
            row_title(c, tr("web-pages.notifications.inBadge"))
            @sf.switch_look(c, "notify-badge/" + kind, counted)
          }) {
          set_badge_kind(core, kind, !counted)
        }
      }
    })
    |> ignore
  }
}

///|
/// The system's notification settings for this app, where it can open them (macOS's; Windows' its own).
fn open_notify_settings(core : Core) -> Unit {
  (core.open_link)(
    if @ui.platform() == 0 {
      "x-apple.systempreferences:com.apple.preference.notifications"
    } else {
      "ms-settings:notifications"
    },
  )
}

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
/// A way's tile (Notifications.css.ts tile): a picture of it over its name and whether it is on; the accent's ring
/// round it while on.
// kept across runs: a value (no field of it changes)
let way_tile : @ui.Style = @ui.style(
  w=@sf.grow,
  py=S4,
  gap=S1_5,
  align=ACenter,
  radius=Xl3,
  bg=Card,
  border=B2,
  border_color=Clear,
)

///|
// kept across runs: a value (no field of it changes)
let way_tiles : @ui.Style = @ui.style(row=true, w=Full, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let way_tile_room : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let way_tile_on : @ui.Style = way_tile.then(@ui.style(border_color=Accent))

///|
/// The badge's tile's picture: the app's icon, a red dot at its corner (Notifications.css.ts picApp, picBadge).
// kept across runs: a value (no field of it changes)
let way_picture_app : @ui.Style = @ui.style(w=S16, h=S10, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let way_app : @ui.Style = @ui.style(w=S8, h=S8, p=SPx, align=AEnd, radius=Lg, bg=Faint)

///|
// kept across runs: a value (no field of it changes)
let way_dot : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, bg=Danger)

///|
/// The dock's tile's picture: a screen, the dock's sliver at its right edge (Notifications.css.ts picEdge).
// kept across runs: a value (no field of it changes)
let way_picture_dock : @ui.Style = @ui.style(w=S16, h=S10, p=S1_5, align=AEnd, justify=JCenter, radius=Lg, bg=Bg, border=B1, border_color=Line)

///|
// kept across runs: a value (no field of it changes)
let way_edge : @ui.Style = @ui.style(w=S1, h=S5, radius=Full, bg=Link)

///|
/// The tile's picture: a window, a banner in its corner.
// kept across runs: a value (no field of it changes)
let way_picture : @ui.Style = @ui.style(w=S16, h=S10, p=S1_5, align=AEnd, radius=Lg, bg=Bg, border=B1, border_color=Line)

///|
// kept across runs: a value (no field of it changes)
let way_banner : @ui.Style = @ui.style(w=S10, h=S2, radius=Sm, bg=Faint)

///|
// kept across runs: a value (no field of it changes)
let way_name : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let way_action : @ui.TextStyle = @ui.text_style(size=Xs, color=Link, wrap=false)

///|
/// A kind's ways, opened under it (Notifications.css.ts kindWays).
// kept across runs: a value (no field of it changes)
let kind_ways : @ui.Style = @ui.style(w=Full, pl=S6, pb=S1)

///|
// kept across runs: a value (no field of it changes)
let way_row : @ui.Style = @ui.style(row=true, w=Full, px=S3, py=S2, gap=S3, align=ACenter)

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
