// The files' page's tabs, as the core keeps them on this device (ember web/src/drive/tabs.ts: its `filesTabs` topic and
// `files.tabs`; client/core-ts/src/drive-browse.ts has what they hold and what is done to them).

///|
/// One of the tabs (FilesTab): a folder, or two side by side (one of them in front).
pub(all) struct FilesTab {
  id : String
  panes : Array[DriveAt]
  front : Int
}

///|
/// The workspace's tabs (FilesTabsView): the tabs, the one shown, the pane in front of it.
pub(all) struct FilesTabs {
  tabs : Array[FilesTab]
  current : String
  front : DriveAt
}

///|
fn pane_of(v : Json?) -> DriveAt {
  { station: text(v, "station"), root: Some(text(v, "root")), path: text(v, "path") }
}

///|
fn pane_json(p : DriveAt) -> Json {
  { "station": Json::string(p.station), "root": Json::string(p.root.unwrap_or("")), "path": Json::string(p.path) }
}

///|
fn tabs_of(v : Json?) -> FilesTabs? {
  match v {
    Some(Object(_)) =>
      Some({
        tabs: items(v, "tabs").map(fn(t) {
          let t = Some(t)
          { id: text(t, "id"), panes: items(t, "panes").map(fn(p) { pane_of(Some(p)) }), front: number(t, "front").to_int() }
        }),
        current: text(v, "current"),
        front: pane_of(field(v, "front")),
      })
    _ => None
  }
}

///|
/// The workspace's tabs as kept: None until the core says, Some(None) before any.
pub fn files_tabs(src : Source, ws : String) -> FilesTabs?? {
  let t = (src.topic)("filesTabs", { "workspace": Json::string(ws) })
  match t.value {
    None => None
    Some(Null) => Some(None)
    v => Some(tabs_of(v))
  }
}

///|
/// What is done to the tabs (`files.tabs`: `act` with what it takes, `pane`, `id`, `side`), answered with the tabs
/// after it.
pub fn files_tabs_act(src : Source, ws : String, act : String, pane? : DriveAt, id? : String, side? : Int, done : (FilesTabs?) -> Unit) -> Unit {
  let o : Map[String, Json] = { "workspace": Json::string(ws), "act": Json::string(act) }
  match pane {
    Some(p) => o["pane"] = pane_json(p)
    None => ()
  }
  match id {
    Some(i) => o["id"] = Json::string(i)
    None => ()
  }
  match side {
    Some(s) => o["side"] = Json::number(s.to_double())
    None => ()
  }
  (src.call)("files.tabs", Json::object(o), fn(r) {
    match r {
      Ok(v) => done(tabs_of(Some(v)))
      Err(_) => ()
    }
  })
}

///|
/// Whether two panes are the same folder.
pub fn same_pane(a : DriveAt, b : DriveAt) -> Bool {
  a.station == b.station && a.root.unwrap_or("") == b.root.unwrap_or("") && a.path == b.path
}
