// A station that only runs tasks (a rig: the core's `rigs`), in the settings' own package for what the stations' lists
// and their ＋ (station_add.mbt) need of it: the rigs as listed, and what a row says of one.

///|
/// The workspace's stations that only run tasks, as the core's `rigs` says them: asked for only where the workspace's
/// view lists any (a workspace with none asks nothing more than it did).
pub fn rigs_listed(core : Core, here : Here) -> Array[Json] {
  if items(workspace_view(core, here).value, "rigs").length() == 0 {
    return []
  }
  items((core.topic)("rigs", { "workspace": str(here.workspace) }).get().value, "rigs")
}

///|
/// The one at `address` (its workspace, a slash, its id), if it is one of them.
pub fn rig_at(core : Core, here : Here, address : String) -> Json? {
  rigs_listed(core, here).iter().find_first(fn(r) { here.workspace + "/" + text(Some(r), "id") == address })
}

///|
/// Whose rig `r` is, to the viewer: 我的, or its owner's name.
pub fn rig_whose(r : Json?) -> String {
  if flag(r, "mine") {
    tr("web-pages.rigs.mine")
  } else {
    let who = if text(r, "ownerName") != "" { text(r, "ownerName") } else { text(r, "ownerEmail") }
    fill("web-pages.rigs.owner", [("who", who)])
  }
}

///|
/// How rig `r` is: its code not compared yet (security mode), reached by a station or not, or not said.
pub fn rig_state(r : Json?) -> String {
  if !flag(r, "vouched") {
    tr("web-pages.rigs.state.unvouched")
  } else {
    match field(r, "reached") {
      Some(True) => tr("web-pages.rigs.state.online")
      Some(False) => tr("web-pages.rigs.state.offline")
      _ => tr("web-pages.rigs.state.unknown")
    }
  }
}

///|
/// What a list's row says of rig `r`: that it only runs tasks, whose it is, how it is.
pub fn rig_said(r : Json?) -> String {
  join([tr("web-pages.rigs.mode.tasks"), rig_whose(r), rig_state(r)], " · ")
}
