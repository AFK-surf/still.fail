// The menu bar on the Mac (still.fail's desktop app's, apps/desktop/src/main.ts setMenu): the app's menu (关于, 检查更新,
// 服务, 隐藏, 退出), 编辑 and 窗口 in the app's words, given to the host (@hostapi.menu_setup) as the app starts and again
// as its language changes; `{app}` in them is the app's name, the host's to put in. Its items are the system's (their
// keys macOS's) but 检查更新, which asks now as the settings' 版本 row does (updates.mbt; said back as the system's
// `menu`: app.mbt system_said). The pages' own actions are not in it yet (the desktop app's 文件, 显示, 前往, 对话).

///|
// kept across runs: a table, never written
let menu_zh : Map[String, String] = {
  "desktop.menu.about": "关于 {app}",
  "desktop.menu.checkUpdates": "检查更新…",
  "desktop.menu.services": "服务",
  "desktop.menu.hide": "隐藏 {app}",
  "desktop.menu.hideOthers": "隐藏其他",
  "desktop.menu.showAll": "全部显示",
  "desktop.menu.quit": "退出 {app}",
  "desktop.menu.edit": "编辑",
  "desktop.menu.undo": "撤销",
  "desktop.menu.redo": "重做",
  "desktop.menu.window": "窗口",
  "desktop.menu.minimize": "最小化",
  "desktop.menu.zoom": "缩放",
  "desktop.menu.fullScreen": "进入/退出全屏",
  "desktop.menu.close": "关闭窗口",
  "desktop.menu.front": "前置全部窗口",
}

///|
fn menu_tr(key : String) -> String {
  match english(key) {
    Some(s) => s
    // (the editing items' words are the context menu's: strings_wide.mbt)
    None => menu_zh.get(key).unwrap_or(tr(key))
  }
}

///|
/// The language the menu bar was last given in ("": not yet).
let menu_bar_given : Ref[String] = Ref("")

///|
/// The menu bar, as JSON (@hostapi.menu_setup's).
fn menu_bar_json() -> String {
  let role = fn(key : String, role : String) -> Json {
    { "title": Json::string(menu_tr(key)), "role": Json::string(role) }
  }
  let sep : Json = { "separator": true }
  let menu = fn(key : String, role : String, items : Array[Json]) -> Json {
    let m : Map[String, Json] = { "title": Json::string(menu_tr(key)), "items": Json::array(items) }
    if role != "" {
      m["role"] = Json::string(role)
    }
    Json::object(m)
  }
  let check : Json = {
    "title": Json::string(menu_tr("desktop.menu.checkUpdates")),
    "action": "update.check",
  }
  Json::array([
    menu("desktop.menu.about", "", [
      role("desktop.menu.about", "about"),
      check,
      sep,
      role("desktop.menu.services", "services"),
      sep,
      role("desktop.menu.hide", "hide"),
      role("desktop.menu.hideOthers", "hideOthers"),
      role("desktop.menu.showAll", "showAll"),
      sep,
      role("desktop.menu.quit", "quit"),
    ]),
    menu("desktop.menu.edit", "", [
      role("desktop.menu.undo", "undo"),
      role("desktop.menu.redo", "redo"),
      sep,
      role("desktop.contextMenu.cut", "cut"),
      role("desktop.contextMenu.copy", "copy"),
      role("desktop.contextMenu.paste", "paste"),
      role("desktop.contextMenu.selectAll", "selectAll"),
    ]),
    menu("desktop.menu.window", "window", [
      role("desktop.menu.minimize", "minimize"),
      role("desktop.menu.zoom", "zoom"),
      role("desktop.menu.fullScreen", "fullScreen"),
      sep,
      role("desktop.menu.close", "close"),
      sep,
      role("desktop.menu.front", "front"),
    ]),
  ]).stringify()
}

///|
/// Each frame: the menu bar given to the host once the frame is built, and again as the language changes (nothing
/// else changes it).
pub fn menu_bar(c : @ui.Ctx) -> Unit {
  let lang = @sf.language()
  if lang != menu_bar_given.val {
    c.after_build("menu-bar", fn() {
      menu_bar_given.val = lang
      @hostapi.menu_setup(menu_bar_json())
    })
  }
}
