// The desktop's 本机 Station (web/src/pages/LocalStation.tsx) on the library's parts: this machine's station as a
// workspace's stations are shown (cloud/StationCards.css.ts card): its dot, its name and how it is, 启动 where it is
// stopped, its menu (停止 or 启动, 重启, 更新到最新版, 打开日志, 在 Finder 中显示数据); under them who runs it, its
// version, its workspace, its data; the installer's progress and what went wrong in it.

///|
/// 本机 Station (LocalStationPage): read again every few seconds (it starts, stops and updates on its own time).
fn local_station_page(c : @ui.Ctx, core : Core) -> Unit {
  ignore(c.every(local_read_ms))
  let parsed = @json.parse(@ui.local_station()) catch { _ => Json::null() }
  let s = Some(parsed)
  let pc = @ui.platform() == 3
  let doing = text(s, "doing")
  let body : Array[() -> Unit] = []
  if text(s, "data") == "" {
    // none here: 添加这台 Mac downloads one, joins it and runs it as a service
    body.push(fn() {
      c.box(style=desk_card, fn() {
        if doing != "" {
          local_progress(c, s, doing)
        } else {
          c.text(@sf.t("desktop.local.noService"), style=desk_muted) |> ignore
          if @ui.platform() == 0 {
            c.box(style=vt_actions, fn() {
              if @sf.button(c, @sf.t("web-pages.settings.thisMac.add"), key="local/install", tone=Primary) {
                (core.local_install)(true)
              }
            })
            |> ignore
          }
        }
        local_failed(c, s)
      })
      |> ignore
    })
  } else {
    body.push(fn() { local_card(c, core, s, pc) })
  }
  desk_page(c, core, "local-station", @sf.t("web-pages.localStation.title"), about=@sf.t(
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
    _ =>
      if service {
        service_name(s)
      } else {
        @sf.t("web-pages.localStation.byApp", args=[("name", "still.fail")])
      }
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
    if a == "update" {
      (core.local_install)(false)
    } else {
      @ui.local_station_act(a)
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
      if !running && !working && service && @sf.button(c, @sf.t("web-pages.localStation.start"), key="local/start-now", tone=Ghost) {
        act("start")
      }
      // its menu (⋯)
      let mid = c.id("local/menu")
      c.cursor(mid, Hand)
      let open = local_menu.val
      if c.clicked(mid) {
        local_menu.val = !open
      }
      let b = c.box(style=ws_more, id=mid, fn() { @sf.icon(c, "more", size=ws_more_icon, color=t.p.muted) |> ignore })
      c.semantics(b, Button, id=mid, label=@sf.t("web-main.menu.more"), expanded=open)
      let entries : Array[@kit.Entry] = []
      if running {
        entries.push(@kit.menu_item("stop", label=@sf.t("web-pages.localStation.stop"), disabled=working))
        if text(s, "runner") != "other" {
          entries.push(@kit.menu_item("restart", label=@sf.t("web-pages.localStation.restart"), disabled=working))
        }
      } else {
        entries.push(@kit.menu_item("start", label=@sf.t("web-pages.localStation.start"), disabled=working || !service))
      }
      // brought up to the latest release (the installer), not one started by hand
      if text(s, "runner") != "other" && @ui.platform() == 0 {
        entries.push(@kit.menu_item("update", label=@sf.t("web-pages.localStation.update"), disabled=working))
      }
      entries.push(@kit.menu_separator())
      entries.push(@kit.menu_item("log", label=@sf.t("web-pages.localStation.openLog")))
      entries.push(
        @kit.menu_item("folder", label=@sf.t(if pc { "web-pages.localStation.openFolderPc" } else { "web-pages.localStation.openFolder" })),
      )
      let m = @sf.dropdown(
        c,
        "local/menu-list",
        open,
        mid,
        entries,
        { "stop": "stop", "start": "play", "restart": "refresh", "update": "refresh", "log": "file-text", "folder": "folder" },
        @sf.menu_w,
        along=End,
      )
      if open && !m.open {
        local_menu.val = false
      }
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
      c.box(style=ls_foot, fn() {
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
    c.box(style=dc_dot_room, fn() {  }) |> ignore
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
  c.box(style=ls_bar, fn() { @sf.progress(c, if known { Some(percent / 100.0) } else { None }) }) |> ignore
  match text(s, "said") {
    "" => ()
    said => c.text(said, style=desk_note) |> ignore
  }
}

///|
/// What went wrong with the last act (warn: red).
fn local_failed(c : @ui.Ctx, s : Json?) -> Unit {
  let words = match text(s, "failed") {
    "" => return
    "busy" => @sf.t("desktop.local.busy")
    "byHand" => @sf.t("desktop.local.byHand")
    "noService" => @sf.t("desktop.local.noService")
    e => e
  }
  c.text(words, style=ls_warn) |> ignore
}

///|
/// Whether its menu is open.
// kept across runs: said by the page's ⋯; settings_reset puts it back
let local_menu : Ref[Bool] = Ref(false)

///|
/// (card: its parts 10 apart, the card's padding and ground)
// kept across runs: a value (no field of it changes)
let ls_card : @ui.Style = desk_card.then(@ui.css("gap=S2_5"))

///|
/// (cardHead: its dot, its title, its buttons, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// (cardTitle: its name and how it is on a line, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_title : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5, align=AEnd)

///|
/// (name: the body's size, 600)
// kept across runs: a value (no field of it changes)
let ls_name : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, weight=Semibold, color=Fg, wrap=false)

///|
/// (state: the list's size, muted)
// kept across runs: a value (no field of it changes)
let ls_state : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
/// (cardFoot: its facts 12 apart in lines, past its dot: 17 in)
// kept across runs: a value (no field of it changes)
let ls_foot : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let ls_past : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ls_fact : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

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
let ls_warn : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Danger, w=Full)

///|
/// 版本 (AppVersionPage): the desktop app's own version, what the last look found under it, and its button: 检查更新,
/// or, with a newer build known, 更新到 it (the app's: version_words, version_tap).
fn version_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let (words, newer) = (core.version_words)()
  let check = @sf.t("android-settings.version.check")
  // what is under way (checking, downloading, installing): said under the version, the button turning
  let note = if newer || words == check { "" } else { words }
  let lead = @sf.t("web-pages.version.lead")
  // (what it is for: narrow under the page's title, wide under its section's)
  look_page(c, core, frame, look, "version", @sf.t("web-pages.settings.nav.version"), lead=if look == Narrow { lead } else { "" }, [
    fn() {
      let title = @sf.t("web-pages.version.title", args=[("name", "still.fail")])
      look_section(c, look, title, heads=true, note=if look == Wide { lead } else { "" }, fn() {
        let row = fn() {
          c.box(style=ver_text, fn() {
            c.text("still.fail mbui " + build_version(), style=desk_words) |> ignore
            if note != "" {
              c.text(note, style=desk_muted) |> ignore
            }
          })
          |> ignore
          if @sf.button(c, if newer { words } else { check }, key="version-app", tone=if newer { Primary } else { Plain }, busy=note != "") {
            (core.version_tap)()
          }
        }
        match look {
          // (narrow: on a card of its own; wide: on the page under its section's title)
          Narrow => look_card(c, look, fn() { c.box(style=ver_row, row) |> ignore })
          Wide => c.box(style=ver_row, row) |> ignore
        }
      })
    },
  ])
}

///|
/// (row: the version and what the last look found on the left, its button on the right, 16 apart)
// kept across runs: a value (no field of it changes)
let ver_row : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ver_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)
