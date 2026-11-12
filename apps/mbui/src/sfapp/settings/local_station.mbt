// What 本机 Station rests on (its page: src/sfpages local_station.mbt, one in every frame): whether this machine's
// station is the app's to add and update, how the machine is called, its data's folder named as the system names it,
// how often the page reads it again; 添加这台 Mac where a station is added.

///|
/// Whether this machine's station is the app's to add and to bring up to date (its host runs the station's installer:
/// macOS's, Windows', Linux's); a phone's and a page's are not.
pub fn local_station_managed() -> Bool {
  let p = @ui.platform()
  p == 0 || p == 3 || p == 5
}

fn local_station_json() -> Json? {
  Some(@json.parse(@ui.local_station()) catch { _ => Json::null() })
}

///|
/// Whether this machine can be added to `workspace` (whose stations already present are `known`): the app manages its
/// local station, nothing is running on it yet, and this machine is not already in `workspace` (nor attached to it).
pub fn local_station_addable_in(workspace : String, known : Array[String]) -> Bool {
  if !local_station_managed() {
    return false
  }
  let s = local_station_json()
  if text(s, "doing") != "" {
    return false
  }
  let ws = field(s, "workspace")
  if ws is Some(Object(_)) && !flag(ws, "removed") {
    let id = text(ws, "id")
    let st = text(ws, "station")
    if (id != "" && id == workspace) || (st != "" && known.contains(st)) {
      return false
    }
  }
  true
}

///|
fn add_here_note(pc : Bool) -> String {
  if text(local_station_json(), "data") != "" {
    tr(if pc { "android-settings.station.addHereExistingPc" } else { "android-settings.station.addHereExisting" })
  } else {
    tr(if pc { "android-settings.station.addHerePc" } else { "android-settings.station.addHere" })
  }
}

///|
fn local_joinable_item(core : Core, here : Here) -> Json? {
  let s = local_station_json()
  let ws = field(s, "workspace")
  guard ws is Some(Object(_)) && !flag(ws, "removed") else { return None }
  let st = text(ws, "station")
  let ws_id = text(ws, "id")
  if st == "" {
    return None
  }
  let joinable = (core.topic)("joinable", { "workspace": str(here.workspace) }).get().value
  items(joinable, "items")
  .iter()
  .find_first(fn(j) {
    text(Some(j), "id") == st || (ws_id != "" && text(Some(j), "station") == ws_id + "/" + st)
  })
}

///|
/// Returns `(join_station_address, needs_lock, lock_reason)` for adding this machine to `here.workspace`.
fn local_here_join_state(core : Core, here : Here) -> (String?, Bool, String) {
  let s = local_station_json()
  let running = text(s, "runner") != "none"
  match local_joinable_item(core, here) {
    Some(j) if flag(Some(j), "needsLock") => (None, true, text(Some(j), "line"))
    Some(j) if flag(Some(j), "online") && running => (Some(text(Some(j), "station")), false, "")
    _ => (None, false, "")
  }
}

///|
fn press_add_here(
  core : Core,
  here : Here,
  join_station : String?,
  close_on_join : Bool,
  then : () -> Unit,
) -> Unit {
  match join_station {
    Some(station) => {
      adding.here_error.set("")
      (core.call)("station.join", obj([("station", str(station)), ("workspace", str(here.workspace))]), fn(r) {
        match r {
          Ok(_) => if close_on_join { then() }
          Err(e) => adding.here_error.set(error_text(e))
        }
      })
    }
    None => {
      then()
      (core.local_install)(true)
      (core.push)(LocalStation)
    }
  }
}

///|
/// 添加这台 Mac offered where a station is added (添加 station's sheet, a workspace's first): what it does, its button;
/// pressed, joins via `station.join` when online and joinable in the mesh, else calls `local_install(true)` and opens
/// 本机 Station.
fn add_this_machine(c : @ui.Ctx, core : Core, here : Here, then : () -> Unit) -> Unit {
  let pc = local_machine_pc()
  let (join_addr, needs_lock, lock_line) = local_here_join_state(core, here)
  let joining = match join_addr {
    Some(st) => is_doing(core, ["station.join"], [("station", st), ("workspace", here.workspace)])
    None => false
  }
  c.box(style=here_column, fn() {
    c.text(add_here_note(pc), style=here_words) |> ignore
    if lock_line != "" {
      c.text(lock_line, style=join_soft_words) |> ignore
    }
    @sf.button(
      c,
      tr(if pc { "web-pages.settings.thisPc.add" } else { "web-pages.settings.thisMac.add" }),
      key="add-here",
      busy=joining,
      disabled=needs_lock || joining,
      on_press=fn() { press_add_here(core, here, join_addr, false, then) },
    )
    let err = adding.here_error.get()
    if err != "" {
      c.text(err, style=add_error_words) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
/// 添加这台 Mac's words over its button.
let here_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let here_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
/// 添加这台 Mac in 添加 station's sheet: in from its sides as its words are, apart from the steps under it.
let here_room : @ui.Style = @ui.css("w=Full pb=S4")

///|
/// This machine called as the person would call it: a Mac, else a computer (Windows', Linux's: 这台电脑).
pub fn local_machine_pc() -> Bool {
  @ui.platform() == 3 || @ui.platform() == 5
}

///|
/// Its data shown in the system's own file manager, named as the system names it (Finder, Explorer, a Linux desktop's).
pub fn local_folder_label() -> String {
  tr(
    match @ui.platform() {
      3 => "web-pages.localStation.openFolderPc"
      5 => "web-pages.localStation.openFolderFiles"
      _ => "web-pages.localStation.openFolder"
    },
  )
}

///|
/// How often the page reads the station again while shown.
pub let local_read_ms : Double = 3000.0
