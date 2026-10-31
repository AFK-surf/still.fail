// 通知, one page in every frame, as the web's (ember web/src/pages/Notifications.tsx, Notifications.css.ts; laid out by its
// width, page_look.mbt): what this device
// tells its person about their chats, and how, laid out as a phone's notification settings are: a preview that follows
// the settings (the banner of the kind looked at, the app's badge with what it counts), the ways it tells as tiles each
// with a picture of it, each kind of thing that happens with which of those it uses (opened, each way on or off), and
// the rest. The preview and the pictures are of this device's system (notice_system: where its banners come, its
// icons), and the badge is a way only where the system shows the app's number (@ui.badge_shown): elsewhere a switch of
// it would change nothing. The phone's settings have a switch of their own (SettingsHome.kt's).

// ---------------------------------------------------------------------------
// 通知

///|
/// The kinds of thing that happen that are told of (Notifications.tsx KINDS_SHOWN), in the order shown.
// kept across runs: a table, never written
let notify_kinds : Array[String] = ["wait", "failed", "done", "message"]

///|
/// The services and jobs left up long: told of only by the rail's bell (`badgeKinds.services`), after the kinds.
// kept across runs: a table, never written
let notify_kinds_shown : Array[String] = ["wait", "failed", "done", "message", "services"]

///|
/// As at the start (settings_reset): no kind opened, nothing chosen.
fn notify_page_reset() -> Unit {
  kind_open.val = ""
  kinds_chosen.clear()
  badge_chosen.clear()
}

///|
/// What was just chosen of what the app's icon counts before the prefs say it back (`badgeKinds`), by kind ("on" the
/// badge itself).
let badge_chosen : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// What the badge counts, as the core keeps it (`workspaceMarks`' `badgeKinds`: the prefs', or as their older `badge`
/// says), or as it was just chosen here.
fn badge_kind(core : Core, here : Here, kind : String) -> Bool {
  match badge_chosen.get(kind) {
    Some(v) => v
    None =>
      flag(field((core.topic)("workspaceMarks", { "workspace": str(here.workspace) }).value, "badgeKinds"), kind)
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
        (core.say)(@sf.t("web-pages.notifications.kindsFailed", args=[("error", error_text(e))]))
      }
    }
  })
}

///|
/// How this device's system shows the app's notifications, as the preview and the tiles draw it: macOS a banner in
/// the screen's top right corner and the app's icon in the Dock; Windows a banner in the bottom right corner over the
/// taskbar; a phone's system (Android, iOS) a banner across the top under the status bar and the app's icon among the
/// home screen's at the foot. (The web's page draws macOS's on every system.)
priv enum NoticeSystem {
  MacOS
  Windows
  Phone
} derive(Eq)

///|
fn notice_system() -> NoticeSystem {
  match @ui.platform() {
    1 | 2 => Phone
    3 => Windows
    _ => MacOS
  }
}

///|
/// What the preview's app icon carries: the number the app puts on it, where the system shows it (@ui.badge_shown);
/// else on a phone the system's own dot while a notification of the app shows (Android's launcher's); else nothing.
priv enum IconMark {
  Count(Int)
  Dot
  Unmarked
}

///|
/// The kind opened on the page to show its ways ("" none).
let kind_open : Ref[String] = Ref("")

///|
/// What was just chosen of the kinds before the core says it back (`notify.set` `kinds`), by kind.
let kinds_chosen : @sf.LiveMap[String, Json] = @sf.LiveMap::new()

///|
/// Whether `kind` comes as a banner now: notifications on, and the kind's own as the core keeps it (`kinds`, each said:
/// attend.ts kindsOf) or as it was just chosen here; a done turn's unless off.
fn kind_banner(notify : Json?, kind : String) -> Bool {
  if !flag(notify, "on") {
    return false
  }
  let now = match kinds_chosen.get(kind) {
    Some(v) => Some(v)
    None => field(field(notify, "kinds"), kind)
  }
  match now {
    Some(String(v)) => v != "off"
    Some(True) => true
    _ => false
  }
}

///|
/// A done turn's banner: off, while away, or always (the core's `kinds.done`, or as just chosen here).
fn done_banner(notify : Json?) -> String {
  match kinds_chosen.get("done") {
    Some(String(v)) => v
    _ => text(field(notify, "kinds"), "done")
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
        (core.say)(@sf.t("web-pages.notifications.kindsFailed", args=[("error", error_text(e))]))
      }
    }
  })
}

///|
/// 通知 (NotificationsPage): until the core's settings have come, their cards' shapes; then the preview, 提醒方式's
/// tiles, 通知类别's card of kinds, 其他.
pub fn notify_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let notify = (core.topic)("notify", Map::new()).value
  // what was chosen, once the core says it
  for k in notify_kinds {
    match (kinds_chosen.get(k), field(field(notify, "kinds"), k)) {
      (Some(a), Some(b)) if a == b => kinds_chosen.remove(k)
      _ => ()
    }
  }
  let kept_badge = field((core.topic)("workspaceMarks", { "workspace": str(here.workspace) }).value, "badgeKinds")
  for k in ["on", "wait", "failed", "done", "message", "services"] {
    match (badge_chosen.get(k), field(kept_badge, k)) {
      (Some(true), Some(True)) | (Some(false), Some(False)) => badge_chosen.remove(k)
      _ => ()
    }
  }
  let blocks : Array[() -> Unit] = []
  if notify is None {
    blocks.push(fn() {
      block_waiting(c, fn() {
        for b in notify_blocks(c, core.quiet(), here, look, Some({ "on": true, "permission": "granted" })) {
          b()
        }
      })
    })
    @sf.page(c, on_back=core.pop, frame~, "notify", @sf.t("web-pages.settings.nav.notifications"), blocks)
    return
  }
  blocks.append(notify_blocks(c, core, here, look, notify))
  @sf.page(c, on_back=core.pop, frame~, "notify", @sf.t("web-pages.settings.nav.notifications"), blocks)
}

///|
/// What the page holds (`notify`, the core's view of how this device is told): the preview, the ways of telling, the
/// kinds of things told of, the rest.
fn notify_blocks(c : @ui.Ctx, core : Core, here : Here, look : Look, notify : Json?) -> Array[() -> Unit] {
  let blocks : Array[() -> Unit] = []
  let permission = text(notify, "permission")
  let pending = is_doing(core, ["notify.set"], []) || notify_switched.get() is Some(_)
  let on = match notify_switched.get() {
    Some(v) => v
    None => flag(notify, "on")
  }
  // the kind the preview shows: the one opened (one that has a banner), else the first that comes as a banner
  let shown_kind = if notify_kinds.contains(kind_open.val) {
    kind_open.val
  } else {
    notify_kinds.iter().find_first(fn(k) { on && kind_banner(notify, k) }).unwrap_or("wait")
  }
  // (narrow: as wide as the page's room, 12 from its sides; @sf.pg_room)
  let preview_w = match look {
    Narrow => c.width - 2.0 * np_narrow_in
    Wide => desk_column(c)
  }
  blocks.push(fn() { notify_preview(c, core, here, notify, on, shown_kind, preview_w) })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.ways.title"), heads=true, note=if look == Wide { @sf.t("web-pages.notifications.noteDevice") } else { "" }, fn() {
      c.box(style=way_tiles, fn() {
        // a banner: the system's word asked first, or its settings opened where it refused
        let action = match permission {
          "denied" => @sf.t("web-pages.notifications.enable.open")
          "default" => @sf.t("web-pages.notifications.enable.allow")
          _ => ""
        }
        if way_tile(c, "notify-banner", "banner", on, action~, busy=pending) && !pending {
          match permission {
            "denied" => open_notify_settings(c)
            "default" => (core.notify_ask)()
            _ => use_notify(core, !on)
          }
        }
        // the badge, where the system shows the app's number
        if @ui.badge_shown() {
          let badge_on = badge_kind(core, here, "on")
          if way_tile(c, "notify-badge", "badge", badge_on) {
            c.tell("notify-badge", fn() { set_badge_kind(core, "on", !badge_on) })
          }
        }
      })
      |> ignore
      if look == Narrow {
        @sf.page_note(c, @sf.t("web-pages.notifications.noteDevice"))
      }
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.kinds.title"), heads=true, fn() {
      c.box(style=kinds_card, fn() {
        // (each its row, apart by its room: no line between)
        for kind in notify_kinds_shown {
          kind_row(c, core, here, notify, kind, on)
        }
      })
      |> ignore
    })
  })
  // each workspace heard of or not (`notify.set {workspaces}`), where there is more than one
  let workspaces = items(notify, "workspaces")
  if workspaces.length() > 1 {
    blocks.push(fn() {
      @sf.section(c, @sf.t("web-pages.notifications.workspaces.title"), heads=true, fn() {
        @sf.page_card(c, fn() {
          for w in workspaces {
            let wv = Some(w)
            let id = text(wv, "id")
            let name = text(wv, "name")
            let heard = flag(wv, "on")
            let now = @sf.switch_row(
              c,
              "notify-ws/" + id,
              name,
              heard,
              disabled=!on,
              // its mark before it, as the workspace is named everywhere
              lead=fn(c) { @sf.workspace_badge(c, name, text(wv, "emoji"), text(wv, "icon"), profile_ws_mark) },
            )
            if now != heard {
              c.after_build("notify-ws/" + id, fn() {
                @settings.act(core, name, "notify.set", obj([("workspaces", obj([(id, Json::boolean(now))]))]))
              })
            }
          }
        })
        // (its note under its card)
        @sf.page_note(c, @sf.t("web-pages.notifications.workspaces.note"))
      })
    })
  }
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.more.title"), heads=true, fn() {
      // (a card of words: its switch's row no ground of its own, 20 in from its corner)
      @sf.page_card(c, fn() {
        let preview = flag(notify, "preview") || field(notify, "preview") is None
        let now = @sf.switch_row(
          c,
          "notify-preview",
          @sf.t("web-pages.notifications.preview"),
          preview,
          note=@sf.t("web-pages.notifications.previewNote"),
          disabled=!on,
        )
        if now != preview {
          c.after_build("notify-preview", fn() {
            @settings.act(core, @sf.t("web-pages.notifications.preview"), "notify.set", obj([("preview", Json::boolean(now))]))
          })
        }
        if @ui.platform() == 0 {
          c.text(@sf.t("web-pages.notifications.sound", args=[("name", "still.fail")]), style=sound_words) |> ignore
        }
      })
    })
  })
  blocks
}

///|
/// The narrow page's room at its sides (@sf.pg_room).
let np_narrow_in : Double = 12.0

///|
/// One way of telling as a tile (Tile): a picture of it, its name, on or off; `action` (the system has to allow it
/// first): ringed in red, its picture marked, a red button in it that goes there. True on the frame after a press.
fn way_tile(c : @ui.Ctx, key : String, way : String, on : Bool, action? : String = "", busy? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let lit = on && action == ""
  let b = c.box(style=if action != "" { tile_action } else if lit { tile_on } else { tile }, id~, fn() {
    c.box(style=tile_picture, fn() {
      match (way, notice_system()) {
        ("banner", MacOS) => c.box(style=pic_banner, top=pic_in, right=pic_in, fn() {  }) |> ignore
        ("banner", Windows) => c.box(style=pic_banner, right=pic_in, bottom=pic_in, fn() {  }) |> ignore
        ("banner", Phone) => c.box(style=pic_banner_across, left=pic_in, top=pic_in, right=pic_in, fn() {  }) |> ignore
        _ =>
          c.box(style=pic_app, bottom=pic_in, left=pic_app_left, fn() {
            c.box(style=pic_badge, top=pic_badge_top, right=pic_badge_right, fn() {  }) |> ignore
          })
          |> ignore
      }
      // (a little under the middle)
      if action != "" {
        c.box(style=pic_alert_at, left=0.0, right=0.0, top=0.0, bottom=0.0, fn() {
          c.box(style=pic_alert, fn() { c.text("!", style=pic_alert_words) |> ignore }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    c.text(@sf.t("web-pages.notifications.ways." + way), style=tile_name) |> ignore
    if busy {
      spinner(c, inline=true)
    } else if action != "" {
      c.box(style=tile_action_button, fn() {
        c.text(action, style=tile_action_words) |> ignore
        @sf.icon(c, "chevron-right", size=tile_action_chevron, color=t.p.on_primary) |> ignore
      })
      |> ignore
    } else {
      c.text(@sf.t(if on { "web-pages.notifications.on" } else { "web-pages.notifications.off" }), style=tile_state) |> ignore
    }
  })
  c.semantics(b, Button, id~, label=@sf.t("web-pages.notifications.ways." + way), pressed=lit)
  hit(c, id)
}

///|
/// A kind of thing that happens (KindRow): its name and what it is, what tells of it in a line, a chevron turned down
/// while open; opened, each way on or off (a done turn's banner: off, while away, always).
fn kind_row(c : @ui.Ctx, core : Core, here : Here, notify : Json?, kind : String, on : Bool) -> Unit {
  let t = @sf.theme()
  // the services left up long: the bell's alone
  let bell = kind == "services"
  let banner = !bell && on && kind_banner(notify, kind)
  let ways : Array[String] = []
  if bell && badge_kind(core, here, kind) {
    ways.push(@sf.t("web-pages.notifications.ways.bell"))
  }
  if banner {
    ways.push(
      if kind == "done" && done_banner(notify) == "away" {
        @sf.t("web-pages.notifications.sumBannerAway")
      } else {
        @sf.t("web-pages.notifications.ways.banner")
      },
    )
  }
  if !bell && @ui.badge_shown() && badge_kind(core, here, "on") && badge_kind(core, here, kind) {
    ways.push(@sf.t("web-pages.notifications.ways.badge"))
  }
  let open = kind_open.val == kind
  let id = c.id("notify-kind/" + kind)
  if hit(c, id) {
    kind_open.val = if open { "" } else { kind }
  }
  let head = c.box(style=kind_head, id~, fn() {
    c.box(style=kind_top, fn() {
      c.box(style=kind_text, fn() { c.text(@sf.t("web-pages.notifications.kinds." + kind), style=kind_title) |> ignore })
      |> ignore
      c.text(if ways.length() == 0 { @sf.t("web-pages.notifications.none") } else { ways.join(" · ") }, style=kind_sum)
      |> ignore
      @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=kind_chevron, color=t.p.muted) |> ignore
    })
    |> ignore
    c.text(@sf.t("web-pages.notifications.kinds." + kind + "Note"), style=kind_note) |> ignore
  })
  c.semantics(head, Button, id~, label=@sf.t("web-pages.notifications.kinds." + kind), expanded=open)
  if !open {
    return
  }
  c.box(style=kind_ways, fn() {
    if bell {
      // 点亮铃铛: whether they put the dot on the rail's bell until it has shown them
      way_switch(c, "notify-bell/" + kind, @sf.t("web-pages.notifications.inBell"), badge_kind(core, here, kind), false, fn(
        v,
      ) {
        c.after_build("notify-bell/" + kind, fn() { set_badge_kind(core, kind, v) })
      })
    } else if kind == "done" {
      c.box(style=way_row, fn() {
        c.text(@sf.t("web-pages.notifications.ways.banner"), style=way_words) |> ignore
        let choices = ["off", "away", "always"]
        let at = choices.search(done_banner(notify)).unwrap_or(1)
        let picked = @sf.segmented(
          c,
          "notify-done",
          [
            @sf.t("web-pages.notifications.kinds.doneOff"),
            @sf.t("web-pages.notifications.kinds.doneAway"),
            @sf.t("web-pages.notifications.kinds.doneAlways"),
          ],
          at,
        )
        if picked != at && on {
          // (told once the frame's builds are over)
          c.tell("notify-done", fn() { set_kind(core, "done", str(choices[picked])) })
        }
      })
      |> ignore
    } else {
      way_switch(c, "notify-way/" + kind, @sf.t("web-pages.notifications.ways.banner"), kind_banner(notify, kind), !on, fn(
        v,
      ) {
        set_kind(core, kind, Json::boolean(v))
      })
    }
    // 计入红点: whether the app's icon counts it (off while the badge is), where the system shows the app's number
    if !bell && @ui.badge_shown() {
      way_switch(c, "notify-badge/" + kind, @sf.t("web-pages.notifications.inBadge"), badge_kind(core, here, kind), !badge_kind(core, here, "on"), fn(
        v,
      ) {
        c.after_build("notify-badge/" + kind, fn() { set_badge_kind(core, kind, v) })
      })
    }
  })
  |> ignore
}

///|
/// A way of a kind (WayRow): its name, a small switch at its end; turned, `set` what it is now.
fn way_switch(c : @ui.Ctx, key : String, title : String, now : Bool, off : Bool, set : (Bool) -> Unit) -> Unit {
  c.box(style=way_row, fn() {
    c.text(title, style=way_words) |> ignore
    let next = @sf.switch(c, key, now, label=title, disabled=off, small=true)
    if next != now {
      set(next)
    }
  })
  |> ignore
}

///|
/// The preview (Preview): a small screen of this device's system as the settings make it (notice_system): the banner of
/// `kind` (the latest one that came, else a sample) where the system shows one, the app's icon among others with what
/// it carries now (IconMark).
fn notify_preview(
  c : @ui.Ctx,
  core : Core,
  here : Here,
  notify : Json?,
  on : Bool,
  kind : String,
  w : Double,
) -> Unit {
  let t = @sf.theme()
  let latest = items((core.topic)("notices", { "workspace": str(here.workspace) }).value, "items")
    .rev()
    .iter()
    .find_first(fn(n) {
      let k = text(Some(n), "kind")
      (if k == "block" { "wait" } else { k }) == kind
    })
  let (title, body) = match latest {
    Some(n) => (text(Some(n), "title"), text(Some(n), "body"))
    None => (@sf.t("web-pages.notifications.sample.title"), @sf.t("web-pages.notifications.sample." + kind))
  }
  let preview = flag(notify, "preview") || field(notify, "preview") is None
  let body = if preview { body } else { @sf.t("web-pages.notifications.hidden." + kind) }
  let banner = on && kind_banner(notify, kind)
  let count = count(
    (core.topic)("workspaceMarks", { "workspace": str(here.workspace) }).value,
    "badge",
  )
  let system = notice_system()
  let mark = if @ui.badge_shown() {
    if badge_kind(core, here, "on") && count > 0 {
      Count(count)
    } else {
      Unmarked
    }
  } else if system == Phone && banner {
    Dot
  } else {
    Unmarked
  }
  if system == Phone {
    let b = device_preview(c, w, banner, title, body, mark)
    c.semantics(b, Image, label=@sf.t("web-pages.notifications.previewLabel"))
    return
  }
  let b = c.box(style=screen, fn() {
    // (its ground the web's linear-gradient(150deg, blue-bg, accent-bg): the column's width by the screen's height)
    c.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
      @sf.gradient(c, w, screen_h, screen_angle, t.p.blue_bg, t.p.accent_bg, radius=screen_corner)
    })
    |> ignore
    if banner {
      if system == Windows {
        c.box(right=banner_in, bottom=taskbar_h + banner_in, fn() { banner_card(c, banner_box, title, body) })
        |> ignore
      } else {
        c.box(top=banner_in, right=banner_in, fn() { banner_card(c, banner_box, title, body) }) |> ignore
      }
    }
    if system == Windows {
      c.box(style=taskbar, left=0.0, right=0.0, bottom=0.0, fn() {
        icons_with_mine(c, dock_app, dock_app_mine, dock_icon, mark)
      })
      |> ignore
    } else {
      c.box(style=dock_at, left=0.0, right=0.0, bottom=dock_bottom, fn() {
        c.box(style=dock_bar, fn() { icons_with_mine(c, dock_app, dock_app_mine, dock_icon, mark) }) |> ignore
      })
      |> ignore
    }
  })
  c.semantics(b, Image, label=@sf.t("web-pages.notifications.previewLabel"))
}

///|
/// A phone's system's preview: the device itself, a phone (a tablet where a tablet's frame has room), standing up from
/// the preview's foot with its top in view: its frame round its screen, on the screen the status bar (its camera
/// where the system has it: iOS's island, Android's hole), the banner across the top (a phone's width at most) over
/// the home screen's first row of icons, the app's with its mark.
fn device_preview(
  c : @ui.Ctx,
  w : Double,
  banner : Bool,
  title : String,
  body : String,
  mark : IconMark,
) -> Int {
  let t = @sf.theme()
  let room = w - 2.0 * device_side
  let device_w = if room >= tablet_w { tablet_w } else if room >= phone_w { phone_w } else { room }
  let inner = c.theme().corner(Xl2)
  c.box(style=device_stage, fn() {
    c.box(style=device_at, left=0.0, top=device_top, right=0.0, fn() {
      c.box(style=device_frame.then(@ui.style(w=Fixed(device_w), h=Fixed(screen_h))), fn() {
        c.box(style=device_screen, fn() {
          // (its wallpaper the preview's ground as it was: the web's linear-gradient(150deg, blue-bg, accent-bg))
          c.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
            @sf.gradient(
              c,
              device_w - 2.0 * device_bezel,
              screen_h - 2.0 * device_bezel,
              screen_angle,
              t.p.blue_bg,
              t.p.accent_bg,
              radius=inner,
            )
          })
          |> ignore
          c.box(style=status_row, left=status_in, top=0.0, right=status_in, fn() {
            c.text(status_time, style=status_words) |> ignore
            c.box(style=status_battery, fn() {  }) |> ignore
          })
          |> ignore
          c.box(style=camera_at, left=0.0, top=camera_top, right=0.0, fn() {
            c.box(style=if @ui.platform() == 1 { camera_island } else { camera_hole }, fn() {  }) |> ignore
          })
          |> ignore
          c.box(style=home_row, left=0.0, top=home_top, right=0.0, fn() {
            icons_with_mine(c, home_app, home_app_mine, home_icon, mark)
          })
          |> ignore
          if banner {
            c.box(style=banner_across_at, left=banner_side, top=status_h, right=banner_side, fn() {
              banner_card(c, banner_across, title, body)
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
}

///|
/// A banner (banner): the app's icon, the chat's title with when, what it says.
fn banner_card(c : @ui.Ctx, style : @ui.Style, title : String, body : String) -> Unit {
  c.box(style~, fn() {
    app_icon(c, banner_icon)
    c.box(style=banner_text, fn() {
      c.box(style=banner_head, fn() {
        c.text(title, style=banner_title) |> ignore
        c.text(@sf.t("web-pages.notifications.now"), style=banner_muted) |> ignore
      })
      |> ignore
      c.text(body, style=banner_body) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Apps' icons in a row, the app's third (`side` square) with its mark: the number in a red capsule, or the system's
/// dot, at its top right corner.
fn icons_with_mine(c : @ui.Ctx, other : @ui.Style, mine : @ui.Style, side : Double, mark : IconMark) -> Unit {
  c.box(style=other, fn() {  }) |> ignore
  c.box(style=other, fn() {  }) |> ignore
  c.box(style=mine, fn() {
    app_icon(c, side)
    match mark {
      Count(n) =>
        c.box(top=dock_badge_top, right=dock_badge_right, fn() {
          c.box(style=dock_badge, fn() {
            c.text(if n > 99 { "99+" } else { n.to_string() }, style=dock_badge_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      Dot =>
        c.box(top=icon_dot_at, right=icon_dot_at, fn() { c.box(style=icon_dot, fn() {  }) |> ignore }) |> ignore
      Unmarked => ()
    }
  })
  |> ignore
  c.box(style=other, fn() {  }) |> ignore
}

///|
/// The app's own icon as the system draws it (its launcher icon, src/sf's drawables): its square, rounded 22%;
/// still.fail's or youdid.wtf's where the app is still.fail's own (MBUI_OWN), else still.fail mbui's.
fn app_icon(c : @ui.Ctx, side : Double) -> Unit {
  let name = if @ui.env("MBUI_OWN") != "1" {
    "launcher_icon"
  } else if @ui.env("MBUI_BETA") == "1" {
    "launcher_icon_beta"
  } else {
    "launcher_icon_stable"
  }
  c.box(style=app_icon_box, fn() { @sf.drawable(c, name, side) |> ignore }) |> ignore
}

///|
/// The system's settings of this app's notifications, where they are allowed again once refused (the host knows where:
/// Android's page of the app's notifications, iOS's, macOS's and Windows' Notifications), told as the frame ends.
fn open_notify_settings(c : @ui.Ctx) -> Unit {
  c.tell("notify-settings", fn() { @ui.notice_settings() |> ignore })
}


// ---------------------------------------------------------------------------
// Notifications.css.ts (the page's words on its 1.5 lines: the ui's 13 on 20, the meta's 12 on 18)

///|
/// The preview's screen: 200 high, 28 under it; its banner 12 in from its top and right, 16 round (the screen's corner
/// the two together), its ground's angle; the dock 10 up from its foot.
let screen_h : Double = 200.0

///|
let screen_corner : Double = 28.0

///|
let screen_angle : Double = 150.0

///|
let banner_in : Double = 12.0

///|
let banner_w : Double = 320.0

///|
let banner_icon : Double = 28.0

///|
let dock_icon : Double = 30.0

///|
let dock_bottom : Double = 10.0

///|
let dock_badge_top : Double = -6.0

///|
let dock_badge_right : Double = -8.0

///|
let dock_badge_least : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let screen : @ui.Style = @ui.style(w=Full, h=Fixed(screen_h), mb=S7, clip=true, radius=Xl4)

///|
/// The banner (banner: 10 by 12 in, 10 between the icon and the words, 16 round, on what floats, a soft shadow).
// kept across runs: a value (no field of it changes)
let banner_box : @ui.Style = @ui.style(
  row=true,
  w=Fixed(banner_w),
  px=S3,
  py=S2_5,
  gap=S2_5,
  align=AStart,
  radius=Xl1_5,
  bg=Raised,
  shadow=Sm,
)

///|
// kept across runs: a value (no field of it changes)
let banner_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let banner_head : @ui.Style = @ui.css("row w=Full gap=S2 justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let banner_title : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let banner_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let banner_body : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, w=Full, max_lines=2)

///|
/// The app's icon (22% round: Md on a 28 or 30 square).
// kept across runs: a value (no field of it changes)
let app_icon_box : @ui.Style = @ui.css("radius=Md clip")

///|
/// The Dock (dockBar: 7 in, its icons 10 apart, on what floats at 70%; the others the line's grey, 8 round).
// kept across runs: a value (no field of it changes)
let dock_at : @ui.Style = @ui.css("row justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let dock_bar : @ui.Style = @ui.css("row p=S1_5 gap=S2_5 radius=Xl1_5 bg=A(Raised,O70)")

///|
// kept across runs: a value (no field of it changes)
let dock_app : @ui.Style = @ui.style(w=Fixed(dock_icon), h=Fixed(dock_icon), radius=Lg, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let dock_app_mine : @ui.Style = @ui.style(w=Fixed(dock_icon), h=Fixed(dock_icon))

///|
/// The badge (badge: 18 high at least, 5 in, round, red, the caption's words white).
// kept across runs: a value (no field of it changes)
let dock_badge : @ui.Style = @ui.style(
  min_w=Fixed(dock_badge_least),
  h=Fixed(dock_badge_least),
  px=S1_25,
  radius=Full,
  bg=Danger,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let dock_badge_words : @ui.TextStyle = @ui.text_style(size=Caption, color=OnPrimary, wrap=false)

///|
/// Windows' taskbar (the whole width at the screen's foot, its icons in its middle, on what floats at 70%).
let taskbar_h : Double = 44.0

///|
// kept across runs: a value (no field of it changes)
let taskbar : @ui.Style = @ui.style(
  row=true,
  h=Fixed(taskbar_h),
  gap=S2_5,
  align=ACenter,
  justify=JCenter,
  radius=InnerOr(Sharp),
  bg=A(Raised, O70),
)

///|
/// A phone's system's preview (device_preview): the device a tablet's width where it has the room, else a phone's at
/// most, 32 at least from the preview's sides and 20 under its top, as high as the preview (so its foot is out of
/// it); its frame 6 round its screen, the frame's corner the screen's with it concentric; the preview round it the
/// card's ground.
let phone_w : Double = 300.0

///|
let tablet_w : Double = 520.0

///|
let device_side : Double = 32.0

///|
let device_top : Double = 20.0

///|
let device_bezel : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let device_stage : @ui.Style = @ui.style(w=Full, h=Fixed(screen_h), mb=S7, clip=true, radius=Xl4, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let device_at : @ui.Style = @ui.css("row justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let device_frame : @ui.Style = @ui.css("p=S1_5 radius=Xl4 bg=Fg")

///|
// kept across runs: a value (no field of it changes)
let device_screen : @ui.Style = @ui.css("w=Full h=Full clip radius=Xl2")

///|
/// Its status bar (its time at the start, its battery at the end, both as far in as past the screen's corner), its
/// camera in the middle of it (Android's hole, 8 round; iOS's island, 36 by 11); its banner across the top 8 from the
/// screen's sides (a phone's width at most, in the middle of a tablet's), over the home screen's first row of icons
/// (36 square, 24 apart, in the middle).
let status_h : Double = 24.0

///|
let status_in : Double = 22.0

///|
let status_time : String = "9:41"

///|
let status_battery_w : Double = 18.0

///|
let status_battery_h : Double = 9.0

///|
let camera_top : Double = 8.0

///|
let camera_hole_side : Double = 8.0

///|
let camera_island_w : Double = 36.0

///|
let camera_island_h : Double = 11.0

///|
let banner_side : Double = 8.0

///|
let banner_across_most : Double = 400.0

///|
let home_icon : Double = 36.0

///|
let home_top : Double = 100.0

///|
// kept across runs: a value (no field of it changes)
let status_row : @ui.Style = @ui.style(row=true, h=Fixed(status_h), align=ACenter, justify=JBetween)

///|
// kept across runs: a value (no field of it changes)
let status_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let status_battery : @ui.Style = @ui.style(w=Fixed(status_battery_w), h=Fixed(status_battery_h), radius=Sm, bg=Fg)

///|
// kept across runs: a value (no field of it changes)
let camera_at : @ui.Style = @ui.css("row justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let camera_hole : @ui.Style = @ui.style(w=Fixed(camera_hole_side), h=Fixed(camera_hole_side), radius=Full, bg=Fg)

///|
// kept across runs: a value (no field of it changes)
let camera_island : @ui.Style = @ui.style(w=Fixed(camera_island_w), h=Fixed(camera_island_h), radius=Full, bg=Fg)

///|
// kept across runs: a value (no field of it changes)
let banner_across_at : @ui.Style = @ui.css("row justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let banner_across : @ui.Style = banner_box.then(@ui.style(w=Full, max_w=Fixed(banner_across_most)))

///|
// kept across runs: a value (no field of it changes)
let home_row : @ui.Style = @ui.css("row justify=JCenter gap=S6")

///|
// kept across runs: a value (no field of it changes)
let home_app : @ui.Style = @ui.style(w=Fixed(home_icon), h=Fixed(home_icon), radius=Lg, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let home_app_mine : @ui.Style = @ui.style(w=Fixed(home_icon), h=Fixed(home_icon))

///|
/// The system's dot on the app's icon (Android's launcher's: 10, red, a little over its corner).
let icon_dot_at : Double = -3.0

///|
let icon_dot_side : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let icon_dot : @ui.Style = @ui.style(w=Fixed(icon_dot_side), h=Fixed(icon_dot_side), radius=Full, bg=Danger)

///|
/// The ways' tiles side by side, 10 apart, as wide as they share.
// kept across runs: a value (no field of it changes)
let way_tiles : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
/// A tile (tile: a card's ground and corner, 14 over, 10 at the sides, 12 under, its parts 4 apart in its middle; a
/// ring of 2, the accent's while on, red at 55% while the system has to allow it first).
// kept across runs: a value (no field of it changes)
let tile : @ui.Style = @ui.style(
  w=@sf.grow,
  pt=S3_5,
  px=S2_5,
  pb=S3,
  gap=S1,
  align=ACenter,
  radius=Xl3,
  bg=Card,
  border=B2,
  border_color=Clear,
)

///|
// kept across runs: a value (no field of it changes)
let tile_on : @ui.Style = tile.then(@ui.css("border_color=Accent"))

///|
/// (its foot as far up as its way to allow it stands concentric with its corners: tile_action_button)
// kept across runs: a value (no field of it changes)
let tile_action : @ui.Style = tile.then(@ui.css("border_color=A(Danger,O55)")).then(
  @ui.style(pb=@sf.room_of(@sf.card_foot_in(tile_action_h))),
)

///|
/// A tile's picture (tilePicture: a screen drawn small, 72 by 46, 4 over its name, 8 round, the canvas on a line):
/// a banner in its top right corner 5 in (38 by 11, 3 round), the app's icon at its foot (18, 5 round, the accent's,
/// a red dot 9 at its corner).
let tile_picture_w : Double = 72.0

///|
let tile_picture_h : Double = 46.0

///|
let pic_in : Double = 5.0

///|
let pic_app_left : Double = 26.0

///|
let pic_badge_top : Double = -4.0

///|
let pic_badge_right : Double = -5.0

///|
let pic_banner_w : Double = 38.0

///|
let pic_banner_h : Double = 11.0

///|
let pic_app_side : Double = 18.0

///|
let pic_badge_side : Double = 9.0

///|
// kept across runs: a value (no field of it changes)
let tile_picture : @ui.Style = @ui.style(
  w=Fixed(tile_picture_w),
  h=Fixed(tile_picture_h),
  mb=S1,
  clip=true,
  radius=Lg,
  bg=Bg,
  border=B1,
  border_color=Line,
)

///|
// kept across runs: a value (no field of it changes)
let pic_banner : @ui.Style = @ui.style(w=Fixed(pic_banner_w), h=Fixed(pic_banner_h), radius=Base, bg=Border)

///|
// kept across runs: a value (no field of it changes)
let pic_app : @ui.Style = @ui.style(w=Fixed(pic_app_side), h=Fixed(pic_app_side), radius=Md, bg=Accent)

///|
/// A phone's banner across the picture's top.
// kept across runs: a value (no field of it changes)
let pic_banner_across : @ui.Style = @ui.style(h=Fixed(pic_banner_h), radius=Base, bg=Border)

///|
// kept across runs: a value (no field of it changes)
let pic_badge : @ui.Style = @ui.style(w=Fixed(pic_badge_side), h=Fixed(pic_badge_side), radius=Full, bg=Danger)

///|
/// The mark that the system has to allow it first (picAlert: 18 round, red, its "!" white, a little under the middle).
// kept across runs: a value (no field of it changes)
let pic_alert_at : @ui.Style = @ui.css("pt=S2 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pic_alert : @ui.Style = @ui.style(
  w=Fixed(pic_app_side),
  h=Fixed(pic_app_side),
  radius=Full,
  bg=Danger,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let pic_alert_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The way to allow it (tileAction: 4 over, 26 high, its words and chevron 12 in from either end (the web's 12 and 10:
/// across a wide tile's foot they stood off its middle), round, red; its words the meta's 12 in 500 white): a capsule
/// across the tile's foot, its ends in the tile's foot corners concentric with them (@sf.card_foot_in: 13 from its
/// sides and foot), as a card's button at its foot is. As wide as its words, its ends came into those corners off their
/// arcs where the tile is narrow (a phone's two side by side: 18.5 from its sides, 12 from its foot).
let tile_action_chevron : Double = 14.0

///|
let tile_action_h : Double = 26.0

///|
// kept across runs: a value (no field of it changes)
let tile_action_button : @ui.Style = @ui.css("row w=Full mt=S1 px=S3 gap=SPx align=ACenter justify=JCenter radius=Full bg=Danger").then(
  @ui.style(h=Fixed(tile_action_h), mx=@sf.room_of(@sf.card_foot_in(tile_action_h) - @ui.Space::px(S2_5))),
)

///|
// kept across runs: a value (no field of it changes)
let tile_action_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=OnPrimary, wrap=false)

///|
/// The kinds' card (card, kinds: 20 at the sides, 6 over and under), its rows apart by their room.
let kind_chevron : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let kinds_card : @ui.Style = @ui.css("w=Full px=S5 py=S1_5 radius=Xl3 bg=Card")


///|
/// A kind's head (kindHead: 12 over and under; its words the ui's 13, what tells of it the meta's 12 muted at that
/// line's end, 12 apart, its chevron after them; what it is muted 2 under, across the row: beside what tells of it, it
/// broke onto two lines on a phone where alone it fits one, the user, 2026-10-27, 「agent 暂停等待你：有卡片，或需要你 /
/// 协助」).
// kept across runs: a value (no field of it changes)
let kind_head : @ui.Style = @ui.css("w=Full py=S3 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let kind_top : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let kind_text : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let kind_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let kind_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let kind_sum : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// Its ways, opened (kindWays: 4 apart, 14 in and under, ending as far from the card's edge as from its side).
// kept across runs: a value (no field of it changes)
let kind_ways : @ui.Style = @ui.css("w=Full pl=S3_5 pb=S3_5 gap=S1")

///|
/// A way (wayRow: 32 high at least, its name and its switch at the two ends, 12 apart; the ui's 13).
// kept across runs: a value (no field of it changes)
let way_row : @ui.Style = @ui.css("row w=Full min_h=S8 gap=S3 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let way_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=@sf.grow)

///|
/// 其他's sound note (sound: the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let sound_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)
