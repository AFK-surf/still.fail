// The phone's offers of a newer build (ember apps/android app/Updates.kt; Home.kt's update button): Home offers a build
// that brings something the changelog says (a download key with its dot; how far while it downloads); the words of
// updates, both frames'. How an update stands, where a build comes from, the settings' version row (更新到 …,
// 检查更新) and the dialog it and the menu bar open are both frames' (sfbase updates.mbt).

///|
// kept across runs: a table, never written
let up_zh : Map[String, String] = {
  "android-chat.home.update": "更新到 {version}",
  "android-misc.updates.allowInstall": "允许 {app} 安装应用后，再点一次更新",
  "android-misc.updates.checkFailed": "检查更新失败：{error}",
  "android-misc.updates.checking": "正在检查最新版本",
  "android-misc.updates.downloading": "下载中",
  "android-misc.updates.downloadingPercent": "下载中 {percent}%",
  "android-misc.updates.failed": "无法更新：{error}",
  "android-misc.updates.incomplete": "下载的文件不完整，请重试",
  "android-misc.updates.httpStatus": "下载返回 {status}",
  "android-misc.updates.installing": "正在安装",
  "android-misc.updates.latest": "已是最新",
  "android-misc.updates.retrying": "网络中断，正在继续下载",
  "android-settings.version.check": "检查更新",
  "android-settings.version.checking": "正在检查",
  "android-settings.version.update": "更新到 {version}",
  "desktop.update.available": "有新版本 {version}",
  "desktop.update.checkFailed": "检查更新失败",
  "desktop.update.dev": "开发版不检查更新",
  "desktop.update.later": "稍后",
  "desktop.update.latest": "已是最新版本",
  "desktop.update.update": "更新",
}

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
