// 本机 Station (web/src/pages/LocalStation.tsx; apps/desktop/src/main.ts localStation), one page in every frame: this
// machine's station whoever runs it (the service the installer made, a process started by hand), as the system says
// it (@ui.local_station), shown as a workspace's stations are (cloud/StationCards.css.ts card): its dot, its name and
// how it is, 启动 where it is stopped, its menu (停止 or 启动, 重启, 更新到最新版, 打开日志, its data shown); under
// them who runs it, its version, its workspace, its data, in lines as the room has them; the installer's progress and
// what went wrong in it. None here: 添加这台 Mac where the app adds one. (The phone's copy, its rows a list each, is
// gone: a station is shown the one way everywhere.)

///|
/// 本机 Station (LocalStationPage): read again every few seconds (it starts, stops and updates on its own time).
pub fn local_station_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  ignore(c.every(@settings.local_read_ms))
  let parsed = @json.parse(@ui.local_station()) catch { _ => Json::null() }
  let s = Some(parsed)
  let pc = @settings.local_machine_pc()
  let doing = text(s, "doing")
  let body : Array[() -> Unit] = []
  if text(s, "data") == "" {
    // none here: 添加这台 Mac downloads one, joins it and runs it as a service
    body.push(fn() {
      // (添加这台 Mac last, in the card's foot corner: concentric with it, out past its words: @sf.card_foot_in)
      let adds = doing == "" && @settings.local_station_managed()
      c.box(style=if adds { @sf.desk_card.then(@sf.foot_pad(@sf.button_height())) } else { @sf.desk_card }, fn() {
        if doing != "" {
          local_progress(c, s, doing)
        } else {
          c.text(@sf.t("desktop.local.noService"), style=desk_muted) |> ignore
        }
        local_failed(c, s)
        if adds {
          c.box(style=vt_actions.then(@sf.foot_across(@sf.button_height())), fn() {
            @sf.card_foot_words(fn() {
              if @sf.button(c, @sf.t(if pc { "web-pages.settings.thisPc.add" } else { "web-pages.settings.thisMac.add" }), key="local/install", tone=Primary) {
                (core.local_install)(true)
              }
            })
          })
          |> ignore
        }
      })
      |> ignore
    })
  } else {
    body.push(fn() { local_card(c, core, s, pc) })
  }
  @sf.page(c, on_back=core.pop, frame~, "local-station", @sf.t("web-pages.localStation.title"), about=@sf.t(
      if pc {
        "web-pages.localStation.leadPc"
      } else {
        "web-pages.localStation.lead"
      },
      args=[("name", "still.fail")],
    ), body)
}

///|
/// The station's card (StationCards card): its head, its facts, the installer's progress, what went wrong.
fn local_card(c : @ui.Ctx, core : Core, s : Json?, pc : Bool) -> Unit {
  let t = @sf.theme()
  let doing = text(s, "doing")
  let working = doing != ""
  let running = text(s, "runner") != "none"
  let service = field(s, "service") is Some(_)
  let workspace = field(s, "workspace")
  let startable = local_startable(s)
  let name = match text(workspace, "stationName") {
    "" => @sf.t(if pc { "web-pages.localStation.thisPc" } else { "web-pages.localStation.thisMac" })
    n => n
  }
  let state = if working {
    @sf.t("web-pages.localStation.doing." + doing)
  } else if running {
    @sf.t("web-pages.localStation.running")
  } else {
    @sf.t("web-pages.localStation.stopped")
  }
  let run_by = match text(s, "runner") {
    "service" => service_name(s)
    "other" => @sf.t("web-pages.localStation.byHand")
    "app" => @sf.t("web-pages.localStation.byApp", args=[("name", "still.fail")])
    // stopped: its service's; with none, nothing runs it (this app runs none of its own)
    _ => if service { service_name(s) } else { "" }
  }
  let place = if workspace is None {
    @sf.t("web-pages.localStation.noWorkspace")
  } else {
    let ws = match text(workspace, "name") {
      "" => text(workspace, "id")
      n => n
    }
    @sf.t(if flag(workspace, "removed") { "web-pages.localStation.removed" } else { "web-pages.localStation.inWorkspace" }, args=[("workspace", ws)])
  }
  let act = fn(a : String) {
    match a {
      "update" => (core.local_install)(false)
      "start" => local_start(core, s)
      _ => @ui.local_station_act(a)
    }
  }
  c.box(style=ls_card, fn() {
    c.box(style=ls_head, fn() {
      @sf.status_dot(c, if working { "busy" } else if running { "online" } else { "offline" })
      c.box(style=ls_title, fn() {
        c.text(name, style=ls_name) |> ignore
        c.text(state, style=ls_state) |> ignore
      })
      |> ignore
      // (words alone, on its name's line: the line as high as with none, its ⋯ concentric in the card's corner)
      if !running && !working && startable {
        @sf.line_end(c, fn() {
          if @sf.button(c, @sf.t("web-pages.localStation.start"), key="local/start-now", tone=Ghost) {
            act("start")
          }
        })
      }
      // its menu (⋯)
      let mid = c.id("local/menu")
      let open = local_menu.val
      // (pressed: opened or closed as it is let go, as it is then)
      c.on_press(mid, fn() { local_menu.val = !local_menu.val })
      let b = c.box(style=ls_more, id=mid, fn() { @sf.icon(c, "more", size=ws_more_icon, color=t.p.muted) |> ignore })
      c.semantics(b, Button, id=mid, label=@sf.t("web-main.menu.more"), expanded=open)
      let entries : Array[@kit.Entry] = []
      if running {
        entries.push(@kit.menu_item("stop", label=@sf.t("web-pages.localStation.stop"), disabled=working))
        if text(s, "runner") != "other" {
          entries.push(@kit.menu_item("restart", label=@sf.t("web-pages.localStation.restart"), disabled=working))
        }
      } else {
        entries.push(@kit.menu_item("start", label=@sf.t("web-pages.localStation.start"), disabled=working || !startable))
      }
      // brought up to the latest release (the installer), not one started by hand
      if text(s, "runner") != "other" && @settings.local_station_managed() {
        entries.push(@kit.menu_item("update", label=@sf.t("web-pages.localStation.update"), disabled=working))
      }
      entries.push(@kit.menu_separator())
      entries.push(@kit.menu_item("log", label=@sf.t("web-pages.localStation.openLog")))
      entries.push(
        @kit.menu_item("folder", label=@settings.local_folder_label()),
      )
      // (dismissed by the hand, Escape or a press outside it and its ⋯: closed at that moment; closed as one is chosen)
      let menu : Ref[@kit.Menu?] = Ref(None)
      c.with_dismissed(fn(_) { local_menu.val = false }, fn() {
        menu.val = Some(
          @sf.dropdown(
            c,
            "local/menu-list",
            open,
            mid,
            entries,
            { "stop": "stop", "start": "play", "restart": "refresh", "update": "refresh", "log": "file-text", "folder": "folder" },
            @sf.menu_w,
            along=End,
          ),
        )
      })
      let m = menu.val.unwrap()
      match m.chosen {
        Some(a) => {
          local_menu.val = false
          act(a)
        }
        None => ()
      }
    })
    |> ignore
    // its facts (cardFoot): who runs it, its version, its workspace, its data, past its dot
    ls_past_dot(c, fn() {
      c.box(style=ls_foot, flow=true, line_gap=0.0, fn() {
        for line in [run_by, text(s, "version"), place, text(s, "data")] {
          if line != "" {
            c.text(line, style=ls_fact) |> ignore
          }
        }
      })
      |> ignore
    })
    if doing == "install" || doing == "update" {
      ls_past_dot(c, fn() { c.box(style=ls_under, fn() { local_progress(c, s, doing) }) |> ignore })
    }
    if text(s, "failed") != "" {
      ls_past_dot(c, fn() { local_failed(c, s) })
    }
  })
  |> ignore
}

///|
/// What stands under its head past its dot (cardFoot's margin: the dot and the head's gap after it).
fn ls_past_dot(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ls_past, fn() {
    c.box(style=ls_dot_room, fn() {  }) |> ignore
    c.box(style=ls_under, body) |> ignore
  })
  |> ignore
}

///|
/// Which service runs it (launchd, systemd, a task), as the host says.
fn service_name(s : Json?) -> String {
  match text(field(s, "service"), "kind") {
    "" => @sf.t("web-pages.localStation.service.launchd")
    k => @sf.t("web-pages.localStation.service." + k)
  }
}

///|
/// The installer at work (install, update): what it does and how far, a bar as far, the step it last said.
fn local_progress(c : @ui.Ctx, s : Json?, doing : String) -> Unit {
  let known = field(s, "percent") is Some(_)
  let percent = number(s, "percent")
  c.text(@sf.t("web-pages.localStation.doing." + doing) + (if known { " · \{percent.to_int()}%" } else { "" }), style=desk_muted)
  |> ignore
  c.box(style=ls_bar, fn() { @sf.progress(c, "local-station", if known { Some(percent / 100.0) } else { None }) }) |> ignore
  match text(s, "said") {
    "" => ()
    said => c.text(said, style=desk_note) |> ignore
  }
}

///|
/// What went wrong with the last act (warn: red).
fn local_failed(c : @ui.Ctx, s : Json?) -> Unit {
  match local_failed_words(s) {
    "" => ()
    words => c.text(words, style=ls_warn) |> ignore
  }
}

///|
/// What went wrong with the last act, in words ("" nothing).
fn local_failed_words(s : Json?) -> String {
  match text(s, "failed") {
    "busy" => @sf.t("desktop.local.busy")
    "byHand" => @sf.t("desktop.local.byHand")
    "noService" => @sf.t("desktop.local.noService")
    e => e
  }
}

///|
/// Whether the station here can be started from here: by its service; with none (still.fail's desktop app ran it from
/// its own bundle, gone with that app; its service taken away), where the app looks after the station here, by the
/// installer without a token, which makes it one as it is and starts it (更新到最新版's, local_station_carry_on's): a
/// station in a workspace, the installer's `update` refusing one in none.
fn local_startable(s : Json?) -> Bool {
  field(s, "service") is Some(_) ||
  (text(field(s, "workspace"), "id") != "" && @settings.local_station_managed())
}

///|
/// 启动 the station here (local_startable): its service started, else the installer without a token.
fn local_start(core : Core, s : Json?) -> Unit {
  if field(s, "service") is Some(_) {
    @ui.local_station_act("start")
  } else {
    (core.local_install)(false)
  }
}

///|
/// The station here as its host says it, where it is the station at `address` (the page of one in a workspace, the
/// stations' row) and is not running, but can be started from here (stopped, or being started, installed or updated):
/// 启动 offered for it there, not a try at reaching it again. None for any other.
pub fn local_stopped(address : String) -> Json? {
  if address == "" || address != this_machine() {
    return None
  }
  let s = match @ui.local_station() {
    "" => return None
    j => try Some(@json.parse(j)) catch { _ => return None }
  }
  if text(s, "runner") == "none" && local_startable(s) {
    s
  } else {
    None
  }
}

///|
/// How the station here stands where it is not running (local_stopped): what is being done to it, else 已停止.
pub fn local_stopped_words(s : Json?) -> String {
  match text(s, "doing") {
    "" => @sf.t("web-pages.localStation.stopped")
    doing => @sf.t("web-pages.localStation.doing." + doing)
  }
}

///|
/// Whether its menu is open.
// kept across runs: said by the page's ⋯; reset puts it back
let local_menu : Ref[Bool] = Ref(false)

///|
/// Whether its menu is open (tests).
pub fn local_menu_open() -> Bool {
  local_menu.val
}

///|
/// (card: its parts 10 apart, the card's padding and ground)
// kept across runs: a value (no field of it changes)
let ls_card : @ui.Style = @sf.desk_card.then(@ui.css("gap=S2_5"))

///|
/// (cardHead: its dot, its title, its buttons, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// Its ⋯ (an icon button: 32, a block: in the card's top right corner on its words' line, 20 in, concentric with the
/// card's there: a small block's corner of the ladder's, all four alike).
// kept across runs: a value (no field of it changes)
let ls_more : @ui.Style = @ui.css("w=S8 h=S8 align=ACenter justify=JCenter hovered{bg=Hover}").then(
  @ui.style(radius=@sf.small_radius),
)

///|
/// (cardTitle: its name and how it is on a line, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_title : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5, align=AEnd)

///|
/// (name: the body's size, 600)
// kept across runs: a value (no field of it changes)
let ls_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Semibold, color=Fg, wrap=false)

///|
/// (state: the list's size, muted)
// kept across runs: a value (no field of it changes)
let ls_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// (cardFoot: its facts 12 apart, going on in lines where the room ends, past its dot: 17 in)
// kept across runs: a value (no field of it changes)
let ls_foot : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let ls_past : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ls_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// What comes under its facts, as far in.
// kept across runs: a value (no field of it changes)
let ls_under : @ui.Style = @ui.style(w=@sf.grow, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let ls_bar : @ui.Style = @ui.css("w=Full py=S1")

///|
/// (warn: red, the list's size, 500)
// kept across runs: a value (no field of it changes)
let ls_warn : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Danger, w=Full)

///|
/// Its dot's room, what stands under its head being past it.
// kept across runs: a value (no field of it changes)
let ls_dot_room : @ui.Style = @ui.style(w=@sf.dot_size)
