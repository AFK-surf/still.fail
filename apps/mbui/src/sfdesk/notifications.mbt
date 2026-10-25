// 通知, one page in every frame, as the web's (ember web/src/pages/Notifications.tsx, Notifications.css.ts; laid out by its
// width, page_look.mbt): what this device
// tells its person about their chats, and how, laid out as a phone's notification settings are: a preview that follows
// the settings (the banner of the kind looked at, the app's badge with what it counts, the dock on the screen's edge
// with the kinds it holds), the ways it tells as tiles each with a picture of it, each kind of thing that happens with
// which of those it uses (opened, each way on or off), and the rest. The phone's settings have a switch of their own
// (SettingsHome.kt's).

// ---------------------------------------------------------------------------
// 通知

///|
/// The kinds of thing that happen that are told of (Notifications.tsx KINDS_SHOWN), in the order shown.
// kept across runs: a table, never written
let notify_kinds : Array[String] = ["wait", "failed", "done", "message"]

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
let badge_chosen : Map[String, Bool] = {}

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
fn notify_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
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
  for k in ["on", "wait", "failed", "done", "message"] {
    match (badge_chosen.get(k), field(kept_badge, k)) {
      (Some(true), Some(True)) | (Some(false), Some(False)) => badge_chosen.remove(k)
      _ => ()
    }
  }
  let blocks : Array[() -> Unit] = []
  if notify is None {
    blocks.push(fn() { waiting_cards(c) })
    look_page(c, core, frame, "notify", @sf.t("web-pages.settings.nav.notifications"), blocks)
    return
  }
  let permission = text(notify, "permission")
  let pending = is_doing(core, ["notify.set"], []) || notify_switched.val is Some(_)
  let on = match notify_switched.val {
    Some(v) => v
    None => flag(notify, "on")
  }
  let dock = @ui.dock_available()
  // the kind the preview shows: the one opened, else the first that comes as a banner
  let shown_kind = if kind_open.val != "" {
    kind_open.val
  } else {
    notify_kinds.iter().find_first(fn(k) { on && kind_banner(notify, k) }).unwrap_or("wait")
  }
  // (narrow: 12 from the page's sides, as its cards are; the preview as wide as what is left)
  let side = fn(body : () -> Unit) {
    match look {
      Narrow => c.box(style=np_narrow, body) |> ignore
      Wide => body()
    }
  }
  let preview_w = match look {
    Narrow => c.width - 2.0 * np_narrow_in
    Wide => desk_column(c)
  }
  blocks.push(fn() { side(fn() { notify_preview(c, core, here, notify, on, shown_kind, preview_w) }) })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.ways.title"), heads=true, note=if look == Wide { @sf.t("web-pages.notifications.noteDevice") } else { "" }, fn() {
      side(fn() { c.box(style=way_tiles, fn() {
        // a banner: the system's word asked first, or its settings opened where it refused
        let action = match permission {
          "denied" => @sf.t("web-pages.notifications.enable.open")
          "default" => @sf.t("web-pages.notifications.enable.allow")
          _ => ""
        }
        if way_tile(c, "notify-banner", "banner", on, action~, busy=pending) && !pending {
          match permission {
            "denied" => open_notify_settings(core)
            "default" => (core.notify_ask)()
            _ => use_notify(core, !on)
          }
        }
        let badge_on = badge_kind(core, here, "on")
        if way_tile(c, "notify-badge", "badge", badge_on) {
          c.after_build("notify-badge", fn() { set_badge_kind(core, "on", !badge_on) })
        }
        // the desktop's dock (dock_settings.mbt), where this Mac app runs it
        if dock {
          let dock_on = dock_setting("on")
          if way_tile(c, "notify-dock", "dock", dock_on) {
            dock_set("on", !dock_on)
          }
        }
      })
      |> ignore })
      if look == Narrow {
        @sf.page_note(c, @sf.t("web-pages.notifications.noteDevice"))
      }
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.kinds.title"), heads=true, fn() {
      side(fn() { c.box(style=kinds_card, fn() {
        for i, kind in notify_kinds {
          if i > 0 {
            c.box(style=kind_rule, fn() {  }) |> ignore
          }
          kind_row(c, core, here, notify, kind, on, dock)
        }
      })
      |> ignore })
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.notifications.more.title"), heads=true, fn() {
      side(fn() { c.box(style=more_card, fn() {
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
        // new ones peeking out of the dock, or only waiting at the edge
        if dock {
          let peek = dock_setting("peek")
          let next = @sf.switch_row(
            c,
            "dock-peek",
            @sf.t("web-pages.dock.peek"),
            peek,
            note=@sf.t("web-pages.dock.peekNote"),
            disabled=!dock_setting("on"),
          )
          if next != peek {
            dock_set("peek", next)
          }
        }
        if @ui.platform() == 0 {
          c.text(@sf.t("web-pages.notifications.sound", args=[("name", "still.fail")]), style=sound_words) |> ignore
        }
      })
      |> ignore })
    })
  })
  look_page(c, core, frame, "notify", @sf.t("web-pages.settings.nav.notifications"), blocks)
}

///|
/// The narrow page's blocks 12 from its sides, as its cards are.
// kept across runs: a value (no field of it changes)
let np_narrow : @ui.Style = @ui.css("w=Full px=S3")

///|
let np_narrow_in : Double = 12.0

///|
/// One way of telling as a tile (Tile): a picture of it, its name, on or off; `action` (the system has to allow it
/// first): ringed in red, its picture marked, a red button in it that goes there. True on the frame after a press.
fn way_tile(c : @ui.Ctx, key : String, way : String, on : Bool, action? : String = "", busy? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let lit = on && action == ""
  let b = c.box(style=if action != "" { tile_action } else if lit { tile_on } else { tile }, id~, fn() {
    c.box(style=tile_picture, fn() {
      match way {
        "banner" => c.box(style=pic_banner, top=pic_in, right=pic_in, fn() {  }) |> ignore
        "badge" =>
          c.box(style=pic_app, bottom=pic_in, left=pic_app_left, fn() {
            c.box(style=pic_badge, top=pic_badge_top, right=pic_badge_right, fn() {  }) |> ignore
          })
          |> ignore
        _ => {
          c.box(style=pic_edge, right=0.0, top=pic_edge_top, fn() {  }) |> ignore
          c.box(style=pic_edge, right=0.0, top=pic_edge_low, fn() {  }) |> ignore
        }
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
fn kind_row(c : @ui.Ctx, core : Core, here : Here, notify : Json?, kind : String, on : Bool, dock : Bool) -> Unit {
  let t = @sf.theme()
  let banner = on && kind_banner(notify, kind)
  let ways : Array[String] = []
  if banner {
    ways.push(
      if kind == "done" && done_banner(notify) == "away" {
        @sf.t("web-pages.notifications.sumBannerAway")
      } else {
        @sf.t("web-pages.notifications.ways.banner")
      },
    )
  }
  if badge_kind(core, here, "on") && badge_kind(core, here, kind) {
    ways.push(@sf.t("web-pages.notifications.ways.badge"))
  }
  if dock && dock_setting("on") && dock_setting(kind) {
    ways.push(@sf.t("web-pages.notifications.ways.dock"))
  }
  let open = kind_open.val == kind
  let id = c.id("notify-kind/" + kind)
  c.cursor(id, Hand)
  if hit(c, id) {
    kind_open.val = if open { "" } else { kind }
  }
  let head = c.box(style=kind_head, id~, fn() {
    c.box(style=kind_text, fn() {
      c.text(@sf.t("web-pages.notifications.kinds." + kind), style=kind_title) |> ignore
      c.text(@sf.t("web-pages.notifications.kinds." + kind + "Note"), style=kind_note) |> ignore
    })
    |> ignore
    c.text(if ways.length() == 0 { @sf.t("web-pages.notifications.none") } else { ways.join(" · ") }, style=kind_sum)
    |> ignore
    @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=kind_chevron, color=t.p.muted) |> ignore
  })
  c.semantics(head, Button, id~, label=@sf.t("web-pages.notifications.kinds." + kind), expanded=open)
  if !open {
    return
  }
  c.box(style=kind_ways, fn() {
    if kind == "done" {
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
          c.after_build("notify-done", fn() { set_kind(core, "done", str(choices[picked])) })
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
    // 计入红点: whether the app's icon counts it (off while the badge is)
    way_switch(c, "notify-badge/" + kind, @sf.t("web-pages.notifications.inBadge"), badge_kind(core, here, kind), !badge_kind(core, here, "on"), fn(
      v,
    ) {
      c.after_build("notify-badge/" + kind, fn() { set_badge_kind(core, kind, v) })
    })
    // 显示在桌面浮窗: whether the dock holds it (off while the dock is)
    if dock {
      way_switch(c, "notify-dock/" + kind, @sf.t("web-pages.notifications.inDock"), dock_setting(kind), !dock_setting("on"), fn(
        v,
      ) {
        dock_set(kind, v)
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
/// The preview (Preview): a small screen as the settings make it: the banner of `kind` (the latest one that came,
/// else a sample) in its top right corner, the dock on its right edge with the kinds it holds, the app's icon in the
/// Dock below with what its badge counts now.
fn notify_preview(c : @ui.Ctx, core : Core, here : Here, notify : Json?, on : Bool, kind : String, w : Double) -> Unit {
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
  let badge = badge_kind(core, here, "on") && count > 0
  let docked = if @ui.dock_available() && dock_setting("on") {
    notify_kinds.filter(fn(k) { dock_setting(k) })
  } else {
    []
  }
  let b = c.box(style=screen, fn() {
    // (its ground the web's linear-gradient(150deg, blue-bg, accent-bg): the column's width by the screen's height)
    c.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
      @sf.gradient(c, w, screen_h, screen_angle, t.p.blue_bg, t.p.accent_bg, radius=screen_corner)
    })
    |> ignore
    if banner {
      c.box(top=banner_in, right=banner_in, fn() {
        c.box(style=banner_box, fn() {
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
      })
      |> ignore
    }
    if docked.length() > 0 {
      // half way down the right edge, a little under the middle: clear of the banner and of the screen's corner
      c.box(style=edge_at, top=0.0, bottom=0.0, right=0.0, fn() {
        for k in docked {
          c.box(style=edge_item, fn() {
            c.text(@sf.t("web-pages.notifications.kinds." + k), style=match k {
              "failed" => edge_failed
              "wait" => edge_wait
              _ => edge_words
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    c.box(style=dock_at, left=0.0, right=0.0, bottom=dock_bottom, fn() {
      c.box(style=dock_bar, fn() {
        c.box(style=dock_app, fn() {  }) |> ignore
        c.box(style=dock_app, fn() {  }) |> ignore
        c.box(style=dock_app_mine, fn() {
          app_icon(c, dock_icon)
          if badge {
            c.box(top=dock_badge_top, right=dock_badge_right, fn() {
              c.box(style=dock_badge, fn() {
                c.text(if count > 99 { "99+" } else { count.to_string() }, style=dock_badge_words) |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
        c.box(style=dock_app, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  c.semantics(b, Image, label=@sf.t("web-pages.notifications.previewLabel"))
}

///|
/// The app's own icon as the system draws it (its launcher icon, src/sf's drawables): its square, rounded 22%.
fn app_icon(c : @ui.Ctx, side : Double) -> Unit {
  c.box(style=app_icon_box, fn() { @sf.drawable(c, "launcher_icon", side) |> ignore }) |> ignore
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
let banner_title : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let banner_muted : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let banner_body : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Fg, w=Full, max_lines=2)

///|
/// The app's icon (22% round: Md on a 28 or 30 square).
// kept across runs: a value (no field of it changes)
let app_icon_box : @ui.Style = @ui.css("radius=Md clip")

///|
/// The dock on the right edge (edge: its kinds 4 apart, at their end; its middle at 60% of the screen's height, 40
/// under its own middle), each half a capsule against the edge (2, 10 and 12 in; the caption's 11).
// kept across runs: a value (no field of it changes)
let edge_at : @ui.Style = @ui.css("pt=S10 gap=S1 align=AEnd justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let edge_item : @ui.Style = @ui.css("pl=S3 pr=S2_5 py=S0_5 radius=Full bg=Raised")

///|
// kept across runs: a value (no field of it changes)
let edge_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let edge_failed : @ui.TextStyle = edge_words.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let edge_wait : @ui.TextStyle = edge_words.then(@ui.text_style(color=AccentText))

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
let dock_badge_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=OnPrimary, wrap=false)

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
// kept across runs: a value (no field of it changes)
let tile_action : @ui.Style = tile.then(@ui.css("border_color=A(Danger,O55) hovered{bg=DangerBg}"))

///|
/// A tile's picture (tilePicture: a screen drawn small, 72 by 46, 4 over its name, 8 round, the canvas on a line):
/// a banner in its top right corner 5 in (38 by 11, 3 round), the app's icon at its foot (18, 5 round, the accent's,
/// a red dot 9 at its corner), the dock's two slivers on its right edge (18 by 7).
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
let pic_edge_top : Double = 13.0

///|
let pic_edge_low : Double = 24.0

///|
let pic_banner_w : Double = 38.0

///|
let pic_banner_h : Double = 11.0

///|
let pic_app_side : Double = 18.0

///|
let pic_badge_side : Double = 9.0

///|
let pic_edge_h : Double = 7.0

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
// kept across runs: a value (no field of it changes)
let pic_badge : @ui.Style = @ui.style(w=Fixed(pic_badge_side), h=Fixed(pic_badge_side), radius=Full, bg=Danger)

///|
// kept across runs: a value (no field of it changes)
let pic_edge : @ui.Style = @ui.style(w=Fixed(pic_app_side), h=Fixed(pic_edge_h), radius=Base, bg=Border)

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
let pic_alert_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_state : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// The way to allow it (tileAction: 4 over, 4 by 10 and 12 in, round, red; its words the meta's 12 in 500 white).
let tile_action_chevron : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let tile_action_button : @ui.Style = @ui.css(
  #|row mt=S1 pl=S3 pr=S2_5 py=S1 gap=SPx align=ACenter radius=Full bg=Danger
)

///|
// kept across runs: a value (no field of it changes)
let tile_action_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=OnPrimary, wrap=false)

///|
/// The kinds' card (card, kinds: 20 at the sides, 6 over and under), a line between them.
let kind_chevron : Double = 16.0

///|
let rule_w : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let kinds_card : @ui.Style = @ui.css("w=Full px=S5 py=S1_5 radius=Xl3 bg=Card")

///|
// kept across runs: a value (no field of it changes)
let kind_rule : @ui.Style = @ui.style(w=Full, h=Fixed(rule_w), bg=Line)

///|
/// A kind's head (kindHead: 12 over and under, 12 apart; its words the ui's 13, what it is muted 2 under; what tells of
/// it the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let kind_head : @ui.Style = @ui.css("row w=Full py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let kind_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let kind_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let kind_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let kind_sum : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

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
let way_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=@sf.grow)

///|
/// 其他's card (card: 20 in, its rows 14 apart); the sound's note (sound: the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let more_card : @ui.Style = @ui.css("w=Full p=S5 gap=S3_5 radius=Xl3 bg=Card")

///|
// kept across runs: a value (no field of it changes)
let sound_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)
