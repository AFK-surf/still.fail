// This machine's station on the Mac, on Windows and on Linux, as the app looks after it (the user, 2026-10-24: the app
// manages the station here, the one there is; one is downloaded only as the person asks for it, 添加这台 Mac, never as
// the app opens; on which systems: settings' local_station_managed). Still.fail's desktop app ran one it carried
// (apps/desktop/src/station.ts); this app runs the station's own installer (mac_app.m, win_station.h, linux_station.h
// local_station_act), which makes it a service (launchd's, a scheduled task, a systemd user service):
// - 添加这台 Mac, none here: a one-time token for the workspace (`workspace.enroll`, which the cloud gives only its owner
//   and admins) and the installer run with it (`install`): downloaded, joined, run as a service;
// - 更新到最新版: the installer run without a token (`update`): the station here brought up to the latest release and
//   run as a service as it is (one still.fail's desktop app ran, with none, becomes one), in the workspaces it is in.
// How far it is goes on 本机 Station's page as it runs (settings/local_station.mbt).

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
/// 添加这台 Mac: the station's installer run here with a token for `workspace`, asked of the cloud first under this
/// machine's name (only its owner and admins are given one: anyone else's ask fails, said so, and nothing is run).
fn local_station_install(src : Source, workspace : String) -> Unit {
  let pc = @settings.local_machine_pc()
  let failed = fn(error : String) {
    toast_later(fill(if pc { "web-pages.settings.thisPc.failed" } else { "web-pages.settings.thisMac.failed" }, [("error", error)]))
  }
  // (the cloud names the station by its token: a token asked without a name is refused, invalid_name)
  (src.call)("workspace.enroll", { "workspace": Json::string(workspace), "name": Json::string(local_machine_name()) }, fn(r) {
    match r {
      Ok(v) =>
        match text(Some(v), "token") {
          "" => failed(tr("web-pages.settings.thisMac.noAnswer"))
          token => @ui.local_station_act("install " + local_install_ask(token))
        }
      // refused (not its owner or admin, the workspace's stations full): said, not passed over
      Err(e) => failed(@settings.error_text(e))
    }
  })
}

///|
/// What a station added from here is called in its workspace (still.fail's desktop app: the computer's name): the
/// host's name for this machine (MBUI_MACHINE: mac_app.m, linux_app.c; Windows' own COMPUTERNAME), its `.local` cut;
/// none said, the machine as the person would call it.
pub fn local_machine_name() -> String {
  for name in ["MBUI_MACHINE", "COMPUTERNAME"] {
    let v = @ui.env(name).trim(chars=" \t\n").to_string()
    if v != "" {
      return if v.has_suffix(".local") { v.view(end_offset=v.length() - 6).to_string() } else { v }
    }
  }
  if @settings.local_machine_pc() { "PC" } else { "Mac" }
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
