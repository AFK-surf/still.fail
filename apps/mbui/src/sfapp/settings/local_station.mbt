// 本机 Station (ember web/src/pages/LocalStation.tsx, apps/desktop/src/main.ts localStation): this machine's station
// whoever runs it (the service the installer made, a process started by hand), as the system says it
// (@ui.local_station): whether it runs and how, its release, the workspace its data is in, where its data is;
// starting, stopping and restarting it, its log and its data opened. Which workspace it is in is only said.

///|
/// 本机 Station's page: read as it is shown and every few seconds (a station starts, stops and updates on its own time).
fn local_station_page(c : @ui.Ctx, core : Core) -> Unit {
  ignore(c.every(local_read_ms))
  let parsed = @json.parse(@ui.local_station()) catch { _ => Json::null() }
  let s = Some(parsed)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.localStation.title")) },
    fn() { section_note(c, tr("android-misc.localStation.lead")) },
  ]
  if text(s, "data") == "" {
    blocks.push(fn() { section_note(c, tr("desktop.local.noService")) })
    scroll_page(c, "local-station", blocks)
    return
  }
  let doing = text(s, "doing")
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
    section_note(c, state)
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
  acts.push(("log", tr("web-pages.localStation.openLog")))
  acts.push(("folder", tr("web-pages.localStation.openFolder")))
  blocks.push(fn() {
    list_card(c, boxed=true, fn() {
      for a in acts {
        let (act, words) = a
        if list_row(c, key="local/" + act, fn() { row_title(c, words) }) {
          // (pressed: handed to the system as the press is read)
          @ui.local_station_act(act)
        }
      }
    })
    match text(s, "failed") {
      "" => ()
      "busy" => section_note(c, tr("desktop.local.busy"))
      "byHand" => section_note(c, tr("desktop.local.byHand"))
      "noService" => section_note(c, tr("desktop.local.noService"))
      e => section_note(c, e)
    }
  })
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "local-station", blocks)
}

///|
/// How often the page reads the station again while shown (LocalStation.tsx: 3 s).
let local_read_ms : Double = 3000.0
