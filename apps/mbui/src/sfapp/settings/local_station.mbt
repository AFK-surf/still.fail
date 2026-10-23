// 本机 Station (ember web/src/pages/LocalStation.tsx, apps/desktop/src/main.ts localStation): this machine's station
// whoever runs it (the service the installer made, a process started by hand), as the system says it
// (@ui.local_station): whether it runs and how, its release, the workspace its data is in, where its data is;
// starting, stopping and restarting it, its log and its data opened. Which workspace it is in is only said.

///|
/// 本机 Station's page: read as it is shown and every few seconds (a station starts, stops and updates on its own time).
fn local_station_page(c : @ui.Ctx, core : Core) -> Unit {
  // the desktop's: the web's (web_local_station.mbt)
  if wide.val {
    return local_station_page_wide(c, core)
  }
  ignore(c.every(local_read_ms))
  let parsed = @json.parse(@ui.local_station()) catch { _ => Json::null() }
  let s = Some(parsed)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.localStation.title")) },
    fn() { section_note(c, tr("android-misc.localStation.lead")) },
  ]
  let doing = text(s, "doing")
  // none here: 添加这台 Mac downloads one, joins it to this workspace and runs it as a service (the app's
  // local_station.mbt: only as the person asks), how far it is as it goes
  if text(s, "data") == "" {
    if doing != "" {
      blocks.push(fn() { local_progress(c, s, doing) })
    } else {
      blocks.push(fn() { section_note(c, tr("desktop.local.noService")) })
      if @ui.platform() == 0 {
        blocks.push(fn() {
          list_card(c, boxed=true, fn() {
            if list_row(c, key="local/install", fn() { row_title(c, tr("web-pages.settings.thisMac.add")) }) {
              (core.local_install)(true)
            }
          })
          local_failed(c, s)
        })
      }
    }
    scroll_page(c, "local-station", blocks)
    return
  }
  let running = text(s, "runner") != "none"
  let service = field(s, "service") is Some(_)
  let workspace = field(s, "workspace")
  let name = match text(workspace, "stationName") {
    "" => tr("web-pages.localStation.thisMac")
    n => n
  }
  let state = if doing != "" {
    tr("web-pages.localStation.doing." + doing)
  } else if running {
    tr("web-pages.localStation.running")
  } else {
    tr("web-pages.localStation.stopped")
  }
  let run_by = match text(s, "runner") {
    "service" => tr("web-pages.localStation.service.launchd")
    "other" => tr("web-pages.localStation.byHand")
    _ => if service { tr("web-pages.localStation.service.launchd") } else { "" }
  }
  let place = if workspace is None {
    tr("web-pages.localStation.noWorkspace")
  } else {
    let ws = match text(workspace, "name") {
      "" => text(workspace, "id")
      n => n
    }
    fill(
      if flag(workspace, "removed") { "web-pages.localStation.removed" } else { "web-pages.localStation.inWorkspace" },
      [("workspace", ws)],
    )
  }
  blocks.push(fn() {
    section_header(c, name)
    // the installer at work (添加这台 Mac, 更新到最新版): how far, not only that it is
    if doing == "install" || doing == "update" {
      local_progress(c, s, doing)
    } else {
      section_note(c, state)
    }
  })
  blocks.push(fn() {
    list_card(c, boxed=true, fn() {
      for line in [(run_by, ""), (text(s, "version"), ""), (place, ""), (text(s, "data"), "")] {
        if line.0 != "" {
          list_row(c, fn() { row_title(c, line.0) }) |> ignore
        }
      }
    })
  })
  // what can be done to it: started (a service's, stopped), stopped, restarted (not one started by hand), opened
  let acts : Array[(String, String)] = []
  if doing == "" {
    if running {
      acts.push(("stop", tr("web-pages.localStation.stop")))
      if text(s, "runner") != "other" {
        acts.push(("restart", tr("web-pages.localStation.restart")))
      }
    } else if service {
      acts.push(("start", tr("web-pages.localStation.start")))
    }
  }
  // brought up to the latest release (the installer, which makes one with no service a service), not one started by hand
  if doing == "" && text(s, "runner") != "other" && @ui.platform() == 0 {
    acts.push(("update", tr("web-pages.localStation.update")))
  }
  acts.push(("log", tr("web-pages.localStation.openLog")))
  acts.push(("folder", tr("web-pages.localStation.openFolder")))
  blocks.push(fn() {
    list_card(c, boxed=true, fn() {
      for a in acts {
        let (act, words) = a
        if list_row(c, key="local/" + act, fn() { row_title(c, words) }) {
          // (pressed: handed to the system as the press is read)
          if act == "update" {
            (core.local_install)(false)
          } else {
            @ui.local_station_act(act)
          }
        }
      }
    })
    local_failed(c, s)
  })
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "local-station", blocks)
}

///|
/// How often the page reads the station again while shown (LocalStation.tsx: 3 s).
let local_read_ms : Double = 3000.0

///|
/// What went wrong with the last act, said under its rows.
fn local_failed(c : @ui.Ctx, s : Json?) -> Unit {
  match text(s, "failed") {
    "" => ()
    "busy" => section_note(c, tr("desktop.local.busy"))
    "byHand" => section_note(c, tr("desktop.local.byHand"))
    "noService" => section_note(c, tr("desktop.local.noService"))
    e => section_note(c, e)
  }
}

///|
/// How the station's installer goes (`install`, `update`): what it is doing and how far its download has come (the
/// host's `percent`, curl's), a bar as far (sweeping while no download says how far: a step that does not), and the
/// step it last said (`said`: downloading, installing, starting).
fn local_progress(c : @ui.Ctx, s : Json?, doing : String) -> Unit {
  let known = field(s, "percent") is Some(_)
  let percent = number(s, "percent")
  section_note(
    c,
    tr("web-pages.localStation.doing." + doing) +
    (if known { " · \{percent.to_int()}%" } else { "" }),
  )
  c.box(style=local_bar_box, fn() {
    @sf.progress(c, if known { Some(percent / 100.0) } else { None })
  })
  |> ignore
  match text(s, "said") {
    "" => ()
    said => section_note(c, said)
  }
}

///|
// kept across runs: a value (no field of it changes)
/// The installer's bar, in from the page's sides as its words are.
let local_bar_box : @ui.Style = @ui.style(w=Full, px=S4, py=S2)
