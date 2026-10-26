// This machine's station on the Mac and on Windows, as the app looks after it (the user, 2026-10-24: the app manages the station here,
// the one there is; one is downloaded only as the person asks for it, 添加这台 Mac, never as the app opens). Still.fail's
// desktop app ran one it carried (apps/desktop/src/station.ts); this app runs the station's own installer
// (mac_app.m local_station_act), which makes it a launchd service:
// - 添加这台 Mac, none here: a one-time token for the workspace (`workspace.enroll`, which the cloud gives only its owner
//   and admins) and the installer run with it (`install`): downloaded, joined, run as a service;
// - 更新到最新版: the installer run without a token (`update`): the station here brought up to the latest release and
//   run as a service as it is (one still.fail's desktop app ran, with none, becomes one), in the workspaces it is in.
// How far it is goes on 本机 Station's page as it runs (settings/local_station.mbt).

///|
/// Whether this machine's station is the app's to add and to bring up to date (its host runs the station's installer:
/// macOS's, Windows'); a phone's and a page's are not.
pub fn local_station_managed() -> Bool {
  @ui.platform() == 0 || @ui.platform() == 3
}

///|
/// This machine called as the person would call it: a Mac, else a PC (Windows').
pub fn local_machine_pc() -> Bool {
  @ui.platform() == 3
}

///|
/// What the installer is told (mac_app.m local_install): the cloud, the workspace's token (none: the station here as it
/// is), the release's channel (a beta app's, the beta's).
fn local_install_ask(token : String) -> String {
  let o : Map[String, Json] = {
    "origin": Json::string(cloud_origin()),
    "channel": Json::string(if @ui.env("MBUI_BETA") == "1" { "beta" } else { "stable" }),
  }
  if token != "" {
    o["token"] = Json::string(token)
  }
  Json::object(o).stringify()
}

///|
/// 添加这台 Mac: the station's installer run here with a token for `workspace`, asked of the cloud first (only its owner
/// and admins are given one: anyone else's ask fails, and nothing is run).
fn local_station_install(src : Source, workspace : String) -> Unit {
  (src.call)("workspace.enroll", { "workspace": Json::string(workspace) }, fn(r) {
    match r {
      Ok(v) =>
        match text(Some(v), "token") {
          "" => ()
          token => @ui.local_station_act("install " + local_install_ask(token))
        }
      Err(_) => ()
    }
  })
}

///|
/// 更新到最新版: the station here brought up to the latest release and run as a service, as it is.
fn local_station_update() -> Unit {
  @ui.local_station_act("update " + local_install_ask(""))
}

///|
/// The station still.fail's desktop app ran here carried on as this app takes that app's place (MBUI_OWN: built as
/// it, its ids and data). That app ran the station it carried in its own bundle while it ran, never installed on its
/// own; its bundle replaced by this one's, that station is gone, and the machine would drop out of its workspace. So a
/// station only that app ran (its data in a workspace, not removed from it; no release of its own, `installed`, nor a
/// service; nothing running it) is made a service as it is: the installer without a token, as 更新到最新版 runs it
/// (the user, 2026-10-24: the app manages the station there is), how far on 本机 Station's page. Not one added anew:
/// that is 添加这台 Mac's alone. Asked as the app starts; once it is a service, never again.
pub fn local_station_carry_on() -> Unit {
  if @ui.env("MBUI_OWN") != "1" {
    return
  }
  let s = match @ui.local_station() {
    "" => return
    j => try Some(@json.parse(j)) catch { _ => None }
  }
  let workspace = field(s, "workspace")
  let only_that_apps = text(workspace, "id") != "" &&
    !flag(workspace, "removed") &&
    text(s, "runner") == "none" &&
    field(s, "service") is None &&
    !flag(s, "installed") &&
    text(s, "doing") == ""
  if only_that_apps {
    @hostapi.log("local station: the one still.fail's desktop app ran, made a service")
    local_station_update()
  }
}
