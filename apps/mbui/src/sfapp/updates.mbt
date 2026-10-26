// The phone's offers of a newer build (ember apps/android app/Updates.kt; Home.kt's update button): Home offers a build
// that brings something the changelog says (a download key with its dot; how far while it downloads); the words of
// updates, both frames'. How an update stands, where a build comes from, the settings' version row (更新到 …,
// 检查更新) and the dialog it and the menu bar open are both frames' (sfbase updates.mbt).

///|
fn up(key : String, args? : Array[(String, String)] = []) -> String {
  fill(key, args)
}

///|
/// Home's update key (Home.kt, the library's update_key): a newer build that brings something the changelog says,
/// the size of the bar's other keys; while it comes, how far under its mark, as on every screen. Tapped, it is
/// installed.
fn update_button(c : @ui.Ctx, src : Source) -> Unit {
  let progress = update_progress()
  let offered = match update.available {
    Some(v) => items(Some(v), "news").length() > 0
    None => false
  }
  if progress == "" && !offered && update.phase != "failed" {
    return
  }
  let said = up("android-chat.home.update", args=[("version", text(update.available, "versionName"))])
  let failed = update.phase == "failed"
  let why = if failed { update_error("") } else { "" }
  if @sf.update_key(c, "home-update", 34.0, 20.0, if progress != "" { progress } else { said }, why, update_part(), failed, update_under_way()) {
    update_install(src)
  }
}
