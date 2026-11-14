// 通知, one page in every frame, as the web's (still.fail web/src/pages/Notifications.tsx, Notifications.css.ts; laid out by its
// width, page_look.mbt): what this device
// tells its person about their chats, and how, laid out as a phone's notification settings are: a preview that follows
// the settings (the banner of the kind looked at, the app's badge with what it counts), the ways it tells as tiles each
// with a picture of it, each kind of thing that happens with which of those it uses (opened, each way on or off), and
// the rest. The preview and the pictures are of this device's system (notice_look: where its banners come, its
// icons), and the badge is a way only where the system shows the app's number (@ui.badge_shown): elsewhere a switch of
// it would change nothing. The phone's settings have a switch of their own.

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
  kind_open.set("")
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
fn badge_kind(core : Core, kind : String) -> Bool {
  match badge_chosen.get(kind) {
    Some(v) => v
    None =>
      flag(field((core.topic)("workspaceMarks", @sfbase.marks_asked()).get().value, "badgeKinds"), kind)
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
/// The kind opened on the page to show its ways ("" none).
let kind_open : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

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
/// 通知 (NotificationsPage) made once as nodes of the window's tree (page_node, laid out by the `width` its frame gives
/// it, narrow where none is given): until the core's settings have come, their cards in their bones (made of a sample,
/// its core quiet); then the preview, 提醒方式's tiles, 通知类别's card of kinds, each workspace heard of or not where
/// there is more than one, 其他. All as the core says it and as it is chosen here: what was just chosen of the kinds and
/// the badge shown until the core says the same (its answer as it comes, View::reacts), the kind opened kept (kind_open).
/// `here`: who and where, as that changes; `stint`: the page's time on top, what a workspace's picture is asked for on.
/// What it says of itself told `said`.
pub fn notify_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let notify = fn() { (core.topic)("notify", Map([])).get().value }
  let kept_badge = fn() {
    field((core.topic)("workspaceMarks", @sfbase.marks_asked()).get().value, "badgeKinds")
  }
  // what was chosen, once the core says it: the core's word from then on
  for k in notify_kinds {
    v.reacts(fn() { (kinds_chosen.get(k), field(field(notify(), "kinds"), k)) }, fn(now) {
      match now {
        (Some(a), Some(b)) if a == b => kinds_chosen.remove(k)
        _ => ()
      }
    })
  }
  for k in notify_badge_kinds {
    v.reacts(fn() { (badge_chosen.get(k), field(kept_badge(), k)) }, fn(now) {
      match now {
        (Some(true), Some(True)) | (Some(false), Some(False)) => badge_chosen.remove(k)
        _ => ()
      }
    })
  }
  let page_w = match width {
    Some(w) => w
    None => fn() { v.window().0 }
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.settings.nav.notifications") },
    fn() {
      if notify() is None {
        ["waiting"]
      } else if items(notify(), "workspaces").length() > 1 {
        ["preview", "ways", "kinds", "workspaces", "more"]
      } else {
        ["preview", "ways", "kinds", "more"]
      }
    },
    fn(b, key) {
      match key {
        "waiting" =>
          @sf.waiting_node(b, fn(s) {
            let sample = fn() -> Json? { Some({ "on": true, "permission": "granted" }) }
            for k in ["preview", "ways", "kinds", "more"] {
              notify_block_node(s, core.quiet(), here, sample, stint, page_w, k)
            }
          })
        _ => notify_block_node(b, core, here, notify, stint, page_w, key)
      }
    },
    on_back~,
    frame~,
    said?,
    width?,
  )
}

///|
/// The kinds the badge's counts are kept of ("on": the badge itself), whose choices the core says back.
// kept across runs: a table, never written
let notify_badge_kinds : Array[String] = ["on", "wait", "failed", "done", "message", "services"]

///|
/// One of 通知's blocks (`key`) as nodes in `b`, from `notify` (the core's view of how this device is told) as it
/// changes: the preview (as wide as the page `page_w` wide leaves its blocks), the ways of telling, the kinds told of,
/// each workspace heard of or not, the rest.
fn notify_block_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  notify : () -> Json?,
  stint : () -> Int,
  page_w : () -> Double,
  key : String,
) -> Unit {
  let pending = fn() { is_doing(core, ["notify.set"], []) || notify_switched.get() is Some(_) }
  let on = fn() {
    match notify_switched.get() {
      Some(v) => v
      None => flag(notify(), "on")
    }
  }
  let badge = fn(kind) { badge_kind(core, kind) }
  match key {
    "preview" => notify_preview_node(b, core, here, notify, on, page_w)
    "ways" =>
      @sf.section_node(
        b,
        fn() { @sf.t("web-pages.notifications.ways.title") },
        note=fn() { if @sf.look_node(b) is Wide { @sf.t("web-pages.notifications.noteDevice") } else { "" } },
        fn(sec) {
          @sf.way_tiles_node(sec, fn(r) {
            let permission = fn() { text(notify(), "permission") }
            // a banner: the system's word asked first, or its settings opened where it refused (a browser's, where
            // to allow it said: a page opens none)
            let action = fn() {
              match permission() {
                "denied" =>
                  @sf.t(
                    if @ui.platform() == 4 {
                      "web-pages.notifications.enable.browser"
                    } else {
                      "web-pages.notifications.enable.open"
                    },
                  )
                "default" => @sf.t("web-pages.notifications.enable.allow")
                _ => ""
              }
            }
            @sf.way_tile_node(
              r,
              notice_look(),
              BannerWay,
              fn() { @sf.t("web-pages.notifications.ways.banner") },
              fn() { @sf.t(if on() { "web-pages.notifications.on" } else { "web-pages.notifications.off" }) },
              on,
              action,
              pending,
              fn() {
                if !@signals.untracked(pending) {
                  match @signals.untracked(permission) {
                    "denied" => notice_settings_or_say(core)
                    "default" => (core.notify_ask)()
                    _ => use_notify(core, !@signals.untracked(on))
                  }
                }
              },
            )
            // the badge, where the system shows the app's number
            if @ui.badge_shown() {
              @sf.way_tile_node(
                r,
                notice_look(),
                BadgeWay,
                fn() { @sf.t("web-pages.notifications.ways.badge") },
                fn() { @sf.t(if badge("on") { "web-pages.notifications.on" } else { "web-pages.notifications.off" }) },
                fn() { badge("on") },
                fn() { "" },
                fn() { false },
                fn() { set_badge_kind(core, "on", !@signals.untracked(fn() { badge("on") })) },
              )
            }
          })
          if @sf.look_node(sec) is Narrow {
            @sf.page_note_node(sec, fn() { @sf.t("web-pages.notifications.noteDevice") })
          }
        },
      )
    "kinds" =>
      @sf.section_node(b, fn() { @sf.t("web-pages.notifications.kinds.title") }, fn(sec) {
        @sf.kinds_card_node(sec, fn(k) {
          // (each its row, apart by its room: no line between)
          for kind in notify_kinds_shown {
            kind_row_node(k, core, notify, on, kind)
          }
        })
      })
    "workspaces" =>
      // each workspace heard of or not (`notify.set {workspaces}`)
      @sf.section_node(b, fn() { @sf.t("web-pages.notifications.workspaces.title") }, fn(sec) {
        @sf.page_card_node(sec, fn(k) {
          k.each(fn() { items(notify(), "workspaces") }, fn(w) { text(Some(w), "id") }, fn(row, w) {
            let wv = fn() { Some(w.get()) }
            let name = fn() { text(wv(), "name") }
            let emoji = fn() { text(wv(), "emoji") }
            let icon = fn() { text(wv(), "icon") }
            row.pick(fn() { @sf.has_station_mark(emoji(), icon()) }, fn(r, marked) {
              @sf.switch_row_node(
                r,
                name,
                fn() { flag(wv(), "on") },
                fn(now) {
                  @settings.act(core, @signals.untracked(name), "notify.set", obj([
                    ("workspaces", obj([(text(@signals.untracked(wv), "id"), Json::boolean(now))])),
                  ]))
                },
                disabled=fn() { !on() },
                in_words=true,
                // A mark it chose, or just its name when it has none.
                lead?=if marked {
                  Some(fn(l) { @sf.station_mark_node(l, emoji, icon, profile_ws_mark, fn() { @sf.theme().p.text }, stint) })
                } else {
                  None
                },
              )
            })
          })
        })
        // (its note under its card)
        @sf.page_note_node(sec, fn() { @sf.t("web-pages.notifications.workspaces.note") })
      })
    _ =>
      @sf.section_node(b, fn() { @sf.t("web-pages.notifications.more.title") }, fn(sec) {
        // (a card of words: its switch's row no ground of its own, 20 in from its corner)
        @sf.page_card_node(sec, fn(k) {
          let preview = fn() { flag(notify(), "preview") || field(notify(), "preview") is None }
          @sf.switch_row_node(
            k,
            fn() { @sf.t("web-pages.notifications.preview") },
            preview,
            fn(now) {
              @settings.act(core, @sf.t("web-pages.notifications.preview"), "notify.set", obj([("preview", Json::boolean(now))]))
            },
            note=fn() { @sf.t("web-pages.notifications.previewNote") },
            disabled=fn() { !on() },
            in_words=true,
          )
          if @ui.platform() == 0 {
            @sf.words_node(k, fn() { @sf.t("web-pages.notifications.sound", args=[("name", @sf.product())]) }, fn() {
              sound_words
            })
            |> ignore
          }
        })
      })
  }
}

///|
/// This device's system as the preview and the tiles draw it (the web's page draws macOS's on every system).
fn notice_look() -> @sf.NoticeLook {
  match @ui.platform() {
    1 => Phone(island=true)
    2 => Phone(island=false)
    3 => Windows
    _ => MacOS
  }
}

///|
/// The preview (Preview) as nodes: the banner of the kind looked at (the one opened, else the first that comes as a
/// banner; the latest that came of it, else a sample; its words hidden where the settings say so) where one comes, the
/// app's icon with what it carries now (IconMark), as they change.
fn notify_preview_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  notify : () -> Json?,
  on : () -> Bool,
  page_w : () -> Double,
) -> Unit {
  let kind = fn() {
    let open = kind_open.get()
    if notify_kinds.contains(open) {
      open
    } else {
      notify_kinds.iter().find_first(fn(k) { on() && kind_banner(notify(), k) }).unwrap_or("wait")
    }
  }
  let latest = fn() {
    let k = kind()
    items((core.topic)("notices", { "workspace": str(here().workspace) }).get().value, "items")
    .rev()
    .iter()
    .find_first(fn(n) {
      let nk = text(Some(n), "kind")
      (if nk == "block" { "wait" } else { nk }) == k
    })
  }
  let title = fn() {
    match latest() {
      Some(n) => text(Some(n), "title")
      None => @sf.t("web-pages.notifications.sample.title")
    }
  }
  let body = fn() {
    let preview = flag(notify(), "preview") || field(notify(), "preview") is None
    if !preview {
      @sf.t("web-pages.notifications.hidden." + kind())
    } else {
      match latest() {
        Some(n) => text(Some(n), "body")
        None => @sf.t("web-pages.notifications.sample." + kind())
      }
    }
  }
  let banner = fn() { on() && kind_banner(notify(), kind()) }
  let look = notice_look()
  let mark = fn() -> @sf.IconMark {
    if @ui.badge_shown() {
      let n = count((core.topic)("workspaceMarks", @sfbase.marks_asked()).get().value, "badge")
      if badge_kind(core, "on") && n > 0 {
        Count(n)
      } else {
        Unmarked
      }
    } else if look is Phone(..) && banner() {
      Dot
    } else {
      Unmarked
    }
  }
  @sf.notify_preview_node(
    b,
    look,
    fn() { @sf.block_width(@sf.look_node(b), page_w()) },
    banner,
    title,
    body,
    mark,
    app_icon_name(),
    fn() { @sf.t("web-pages.notifications.previewLabel") },
  )
}

///|
/// The app's own icon as the system draws it (its launcher icon, src/sf's drawables): still.fail's or youdid.wtf's
/// where the app is still.fail's own (MBUI_OWN), else still.fail mbui's.
fn app_icon_name() -> String {
  if @ui.env("MBUI_OWN") != "1" {
    "launcher_icon"
  } else if @ui.env("MBUI_BETA") == "1" {
    "launcher_icon_beta"
  } else {
    "launcher_icon_stable"
  }
}

///|
/// A kind of thing that happens (KindRow) as nodes: what tells of it in a line, opened (kind_open), each way on or off (a
/// done turn's banner: off, while away, always; the services left up long: the bell's alone), as they change.
fn kind_row_node(k : @view.View, core : Core, notify : () -> Json?, on : () -> Bool, kind : String) -> Unit {
  let bell = kind == "services"
  let badge = fn(kind) { badge_kind(core, kind) }
  let sum = fn() {
    let ways : Array[String] = []
    if bell && badge(kind) {
      ways.push(@sf.t("web-pages.notifications.ways.bell"))
    }
    if !bell && on() && kind_banner(notify(), kind) {
      ways.push(
        if kind == "done" && done_banner(notify()) == "away" {
          @sf.t("web-pages.notifications.sumBannerAway")
        } else {
          @sf.t("web-pages.notifications.ways.banner")
        },
      )
    }
    if !bell && @ui.badge_shown() && badge("on") && badge(kind) {
      ways.push(@sf.t("web-pages.notifications.ways.badge"))
    }
    if ways.length() == 0 {
      @sf.t("web-pages.notifications.none")
    } else {
      ways.join(" · ")
    }
  }
  let open = fn() { kind_open.get() == kind }
  @sf.kind_row_node(
    k,
    fn() { @sf.t("web-pages.notifications.kinds." + kind) },
    sum,
    fn() { @sf.t("web-pages.notifications.kinds." + kind + "Note") },
    open,
    fn() { kind_open.set(if @signals.untracked(open) { "" } else { kind }) },
    fn(w) {
      if bell {
        // 点亮铃铛: whether they put the dot on the rail's bell until it has shown them
        way_switch_node(w, fn() { @sf.t("web-pages.notifications.inBell") }, fn() { badge(kind) }, fn() { false }, fn(v) {
          set_badge_kind(core, kind, v)
        })
      } else if kind == "done" {
        @sf.way_row_node(w, fn() { @sf.t("web-pages.notifications.ways.banner") }, fn(r) {
          let choices = ["off", "away", "always"]
          r.box(fn(slot) {
            @sf.segmented_node(
              slot,
              fn() {
                [
                  @sf.t("web-pages.notifications.kinds.doneOff"),
                  @sf.t("web-pages.notifications.kinds.doneAway"),
                  @sf.t("web-pages.notifications.kinds.doneAlways"),
                ]
              },
              fn() { choices.search(done_banner(notify())).unwrap_or(1) },
              fn(picked) {
                let at = choices.search(@signals.untracked(fn() { done_banner(notify()) })).unwrap_or(1)
                if picked != at && @signals.untracked(on) {
                  set_kind(core, "done", str(choices[picked]))
                }
              },
            )
          })
          |> ignore
        })
      } else {
        way_switch_node(w, fn() { @sf.t("web-pages.notifications.ways.banner") }, fn() { kind_banner(notify(), kind) }, fn() {
          !on()
        }, fn(v) { set_kind(core, kind, Json::boolean(v)) })
      }
      // 计入红点: whether the app's icon counts it (off while the badge is), where the system shows the app's number
      if !bell && @ui.badge_shown() {
        way_switch_node(w, fn() { @sf.t("web-pages.notifications.inBadge") }, fn() { badge(kind) }, fn() { !badge("on") }, fn(
          v,
        ) {
          set_badge_kind(core, kind, v)
        })
      }
    },
  )
}

///|
/// A way of a kind (WayRow) as nodes: its name, a small switch at its end (off while `off`); turned, `set` what it is to
/// be.
fn way_switch_node(w : @view.View, title : () -> String, now : () -> Bool, off : () -> Bool, set : (Bool) -> Unit) -> Unit {
  @sf.way_row_node(w, title, fn(r) { @sf.switch_node(r, now, set, title, small=true, disabled=off) })
}

///|
/// 其他's sound note (sound: the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let sound_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)
