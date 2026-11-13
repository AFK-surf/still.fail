// A workspace's devices (设备, 2026-11-10: the core's `devices`, client/core-ts/src/devices.ts): what agents use that runs
// no station, one list, each its person's. A device is attached to a station (on its USB, in its network) or is a
// person's phone lent by its app. On a whole station it is every chat's; on one that only runs tasks, and a phone, a
// chat uses it by its person's grant (a card in the chat, `rig.decide`), or 免批准 on it (`device.setOpen`).
//
// Here: a station's 设备 section (its devices, and adding one: any member on a whole station, its person on one that
// only runs tasks), a device's panel (where it is, whose, who uses it, 免批准 and taking it off for its person), and
// the words a list's row says of one (the stations' place lists them all: settings stations.mbt, sfdesk places.mbt).

///|
/// The workspace's devices as the core says them now.
pub fn devices_listed(core : Core, here : Here) -> Array[Json] {
  if !(core.devices_on)() {
    return []
  }
  let ask = devices_ask(here)
  items((core.topic)(ask.0, ask.1).get().value, "devices")
}

///|
/// What the core is asked for the workspace's devices (devices_listed's, where the core asks them at all): its `devices`.
pub fn devices_ask(here : Here) -> (String, Map[String, Json]) {
  ("devices", { "workspace": str(here.workspace) })
}

///|
/// The device `id` attached to station `station` (a phone's: "" for any station it is lent to), as the core says it now.
fn device_at(core : Core, here : Here, station : String, id : String) -> Json? {
  devices_listed(core, here)
  .iter()
  .find_first(fn(d) { text(Some(d), "id") == id && (station == "" || text(Some(d), "station") == station || text(Some(d), "via") == "phone") })
}

///|
/// What kind of thing `d` is, in words.
pub fn device_kind_words(d : Json?) -> String {
  if text(d, "via") == "phone" {
    return @sf.t("web-pages.devices.kind.phone")
  }
  @sf.t("web-pages.devices.kind." + text(d, "kind"))
}

///|
/// Its mark: a phone, the network's, a plug's.
pub fn device_icon(d : Json?) -> String {
  match (text(d, "via"), text(d, "kind")) {
    ("phone", _) | (_, "adb") => "phone"
    (_, "serial") => "plug"
    _ => "web"
  }
}

///|
/// Whose it is, to the viewer: 我的, or its owner's name.
pub fn device_whose(d : Json?) -> String {
  if flag(d, "mine") {
    @sf.t("web-pages.devices.mine")
  } else {
    let who = if text(d, "ownerName") != "" { text(d, "ownerName") } else { text(d, "ownerEmail") }
    @sf.t("web-pages.devices.owner", args=[("who", who)])
  }
}

///|
/// What a list's row says of `d`: its kind, where it is, whose, and how chats use it (or that it is away).
pub fn device_said(d : Json?) -> String {
  let state = match field(d, "online") {
    Some(False) => @sf.t("web-pages.devices.offline")
    _ => if flag(d, "open") { @sf.t("web-pages.devices.openAll") } else { @sf.t("web-pages.devices.needsGrant") }
  }
  let where_ = if text(d, "via") == "phone" { "" } else { @sf.t("web-pages.devices.on", args=[("station", text(d, "stationName"))]) }
  join([device_kind_words(d), where_, device_whose(d), state], " · ")
}

///|
/// A station's 设备 section, made once in `b`: its devices, a row each opening its panel, and 添加设备 where the viewer
/// may (`can_add`: any member on a whole station, its person on one that only runs tasks).
pub fn station_devices_node(b : @view.View, core : Core, here : () -> Here, station : String, rig : Bool, can_add : () -> Bool) -> Unit {
  let mine = fn() { devices_listed(core, here()).filter(fn(d) { text(Some(d), "station") == station && text(Some(d), "via") != "phone" }) }
  let note = if rig { "web-pages.devices.rigNote" } else { "web-pages.devices.stationNote" }
  @sf.section_node(b, fn() { @sf.t("web-pages.devices.title") }, note=fn() { @sf.t(note) }, fn(s) {
    @sf.group_node(s, fn(g) {
      g.each(mine, fn(d) { "d/" + text(Some(d), "id") }, fn(row, d) {
        let dv = fn() { Some(d.get()) }
        row.box(fn(holder) {
          @sf.link_row_node(
            holder,
            fn() { text(dv(), "name") },
            fn() {
              let (x, y, w, h) = holder.placed_window_now()
              open_device(core, @signals.untracked(here), station, text(@signals.untracked(dv), "id"), @sf.Beside::At(x, y, w, h).anchor())
            },
            note=fn() { join([device_kind_words(dv()), text(dv(), "target"), device_whose(dv())], " · ") },
            lead=LeadLine(fn(l) { @sf.icon_node(l, @signals.untracked(fn() { device_icon(dv()) }), devices_row_glyph, By(fn() { @sf.theme().p.muted })) |> ignore }),
          )
        })
        |> ignore
      })
      g.show(fn() { mine().length() == 0 && !can_add() }, fn(o) {
        @sf.link_row_node(o, fn() { @sf.t("web-pages.devices.none") }, fn() {  }, goes=false, chevron=false, lacks=true)
      })
      g.show(can_add, fn(o) {
        o.box(fn(holder) {
          @sf.link_row_node(
            holder,
            fn() { @sf.t("web-pages.devices.add") },
            fn() {
              let (x, y, w, h) = holder.placed_window_now()
              add_device(core, @signals.untracked(here), station, rig, At(x, y, w, h))
            },
            note=fn() { @sf.t("web-pages.devices.addNote") },
            lead=LeadLine(fn(l) { @sf.icon_node(l, "plus", devices_row_glyph, By(fn() { @sf.theme().p.muted })) |> ignore }),
          )
        })
        |> ignore
      })
    })
  })
}

///|
/// A device row's mark's side.
let devices_row_glyph : Double = 18.0

///|
/// A device added to `station`: which kind (a menu beside what asked), its name, what it is reached at, a serial
/// port's speed, then `device.add` (on one that only runs tasks, signed by its person: the core asks them).
pub fn add_device(core : Core, here : Here, station : String, rig : Bool, from : @sf.Beside) -> Unit {
  let kinds = ["tcp", "serial", "adb"]
  @sf.menu(
    kinds.map(fn(k) {
      Some(@sf.menu_item_of(@sf.t("web-pages.devices.kind." + k), icon=if k == "tcp" { "web" } else if k == "serial" { "plug" } else { "phone" }, fn() {
        add_device_named(core, here, station, rig, k)
      }))
    }),
    from~,
    title=@sf.t("web-pages.devices.add"),
  )
}

///|
/// The rest of adding one of kind `kind`: asked a line at a time, each a step further in.
fn add_device_named(core : Core, here : Here, station : String, rig : Bool, kind : String) -> Unit {
  ignore(rig)
  ask(@sf.t("web-pages.devices.name"), "", @sf.t("web-pages.devices.namePlaceholder"), @sf.t("web-pages.devices.continue"), hint=@sf.t("web-pages.devices.kindNote." + kind), fn(name) {
    ask(
      @sf.t("web-pages.devices.target." + kind),
      "",
      @sf.t("web-pages.devices.target." + kind + "Placeholder"),
      if kind == "serial" { @sf.t("web-pages.devices.continue") } else { @sf.t("web-pages.devices.add") },
      fn(target) {
        let add = fn(baud : String) {
          let params : Array[(String, Json)] = [("workspace", str(here.workspace)), ("station", str(station)), ("name", str(name)), ("kind", str(kind)), ("target", str(target))]
          if baud != "" {
            params.push(("baud", str(baud)))
          }
          act(core, @sf.t("web-pages.devices.add"), "device.add", obj(params), done=@sf.t("web-pages.devices.added"))
        }
        if kind == "serial" {
          @sf.ask(@sf.t("web-pages.devices.baud"), @sf.t("web-pages.devices.add"), add, placeholder="115200", hint=@sf.t("web-pages.devices.baudHint"), empty=true)
        } else {
          add("")
        }
      },
    )
  })
}

///|
/// Device `id` (attached to `station`)'s panel beside what opened it: what it is and where, whose; the chats using it
/// (taken back by its person) and asking for it; 免批准 on one of a rig's (its person's); taking it off (its person's,
/// a whole station's by the workspace's owners and admins too).
pub fn open_device(core : Core, here : Here, station : String, id : String, from : @sf.Anchor) -> Unit {
  let d = fn() { device_at(core, here, station, id) }
  let first = d()
  let via = text(first, "via")
  let role = text(workspace_view(core, here).value, "role")
  let manager = role == "owner" || role == "admin"
  let on = fn() { [("device", id)] }
  @sf.panel_nodes(text(first, "name"), from~, fn(v, close) {
    // taken off meanwhile (here or elsewhere): the panel goes
    v.reacts(fn() { d() is None }, fn(gone) {
      if gone {
        close()
      }
    })
    // what it is, a row each, named at its start and said at its end: its kind, its address (pressed, copied), the
    // station it is on (pressed, that station's page), whose it is, and which chats may use it
    @sf.panel_group_node(v, fn() { "" }, fn(g) {
      @sf.panel_row_node(g, fn() { @sf.t("web-pages.devices.label.kind") }, fn() {  }, note=fn() { device_kind_words(d()) })
      @sf.panel_row_node(
        g,
        fn() { @sf.t("web-pages.devices.label.target") },
        fn() {
          @ui.clipboard_set(text(@signals.untracked(d), "target"))
          (core.say)(@sf.t("common.copied"))
        },
        note=fn() {
          text(d(), "target") +
          (match field(d(), "baud") {
            Some(Number(n, ..)) => " · " + n.to_int().to_string() + " baud"
            _ => ""
          })
        },
        end="copy",
      )
      g.show(fn() { via != "phone" }, fn(o) {
        @sf.panel_row_node(
          o,
          fn() { @sf.t("web-pages.devices.label.station") },
          fn() {
            close()
            (core.push)(Station(here.workspace + "/" + station))
          },
          note=fn() { text(d(), "stationName") },
          end="chevron-right",
        )
      })
      @sf.panel_row_node(g, fn() { @sf.t("web-pages.devices.label.owner") }, fn() {  }, note=fn() {
        if flag(d(), "mine") {
          @sf.t("web-pages.devices.me")
        } else if text(d(), "ownerName") != "" {
          text(d(), "ownerName")
        } else {
          text(d(), "ownerEmail")
        }
      })
      @sf.panel_row_node(g, fn() { @sf.t("web-pages.devices.label.who") }, fn() {  }, note=fn() {
        if flag(d(), "open") { @sf.t("web-pages.devices.whoAll") } else { @sf.t("web-pages.devices.whoGranted") }
      })
    })
    // 免批准 on one of a rig's: its person's switch
    v.show(fn() { via == "rig" && flag(d(), "mine") }, fn(o) {
      @sf.panel_switch_noted_node(
        o,
        fn() { @sf.t("web-pages.devices.open") },
        fn() { flag(d(), "ownOpen") },
        fn(to) {
          act(core, @sf.t("web-pages.devices.open"), "device.setOpen", obj([("workspace", str(here.workspace)), ("station", str(station)), ("device", str(id)), ("open", Json::boolean(to))]))
        },
        note=fn() { @sf.t("web-pages.devices.openNote") },
      )
    })
    // who uses it: the chats granted it (a grant of its station gives it too), taken back by its person
    v.show(fn() { via != "station" }, fn(o) {
      // (its heading where the rows' words start, as the rows above it have theirs: not in by a row's padding)
      o.box(fn(l) {
        @sf.style_node(l, device_using_at)
        @sf.words_node(l, fn() { @sf.t("web-pages.devices.using") }, device_using_words) |> ignore
      })
      |> ignore
      @sf.panel_group_node(o, fn() { "" }, fn(g) {
        g.each(fn() { items(d(), "grants") }, fn(x) { "g/" + text(Some(x), "request") }, fn(row, x) {
          let r = fn() { Some(x.get()) }
          @sf.panel_row_node(
            row,
            fn() { device_chat_title(r()) },
            fn() {
              let now = @signals.untracked(r)
              if !flag(@signals.untracked(d), "mine") || flag(now, "whole") || via != "rig" {
                return
              }
              confirm(device_chat_title(now), "", @sf.t("web-pages.rigs.revoke"), fn() {
                act(core, @sf.t("web-pages.rigs.revoke"), "rig.revoke", obj([("workspace", str(here.workspace)), ("rig", str(station)), ("request", str(text(now, "request"))), ("station", str(text(now, "station")))]))
              })
            },
            note=fn() {
              if flag(r(), "whole") {
                @sf.t("web-pages.devices.byStation", args=[("name", text(d(), "stationName"))])
              } else {
                @sf.t("web-pages.devices.chatOn", args=[("station", text(r(), "stationName"))])
              }
            },
          )
        })
        g.show(fn() { items(d(), "grants").length() == 0 && !flag(d(), "open") }, fn(n) { @sf.panel_note_node(n, fn() { @sf.t("web-pages.devices.useNone") }) })
      })
    })
    // taking it off
    v.show(fn() { via != "phone" && (flag(d(), "mine") || (via == "station" && manager)) }, fn(o) {
      @sf.panel_row_node(
        o,
        fn() { @sf.t("web-pages.devices.remove") },
        fn() {
          close()
          confirm(@sf.t("web-pages.devices.removeAsk", args=[("name", text(first, "name"))]), @sf.t("web-pages.devices.removeNote"), @sf.t("web-pages.devices.remove"), danger=true, fn() {
            act(core, @sf.t("web-pages.devices.remove"), "device.remove", obj([("workspace", str(here.workspace)), ("station", str(station)), ("device", str(id))]), done=@sf.t("web-pages.devices.removed"))
          })
        },
        icon=fn() { "trash" },
        danger=true,
      )
    })
    ignore(on)
  })
}

///|
/// A chat as a grant names it: its title, or that it has none yet.
fn device_chat_title(r : Json?) -> String {
  let title = text(r, "title")
  if title == "" {
    @sf.t("web-pages.rigs.grant.untitled")
  } else {
    title
  }
}

///|
/// The heading of a device's chats in its panel: the panel's quiet words, a little over its rows.
fn device_using_words() -> @ui.TextStyle {
  @ui.text_style(size=Meta, leading=L5, color=Muted)
}

///|
fn device_using_at() -> @ui.Style {
  @ui.css("pt=S3 pb=S1")
}
