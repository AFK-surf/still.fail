// The menu bar on the Mac (still.fail's desktop app's, apps/desktop/src/main.ts setMenu): the app's menu (关于, 检查更新,
// 设置, 服务, 隐藏, 退出), 文件, 编辑, 显示, 前往, 对话, 窗口 and 帮助 in the app's words, given to the host
// (@hostapi.menu_setup) as the app starts and again as what it shows changes (the language, the keys changed in 快捷键, a
// chat open or not); `{app}` in them is the app's name, the host's to put in. The system's items are the system's (their
// keys macOS's); the pages' own (keymap.mbt's actions) show the keys they have here, which the pages take before the
// menu does (as the desktop app's), and chosen, are those keys pressed (said back as the system's `menu`: app.mbt
// system_said, @settings.ask_action); those of a chat only while one is open. 检查更新 opens the update dialog over
// what is open (updates.mbt update_dialog), as 关于's version row does. On Windows, which has no menu bar, its last
// menu is the menu of the app's icon in the notification area ("role": "tray": 打开 and 退出, as the desktop app's
// tray had them), where the app goes as its window closes; the Mac leaves it out.


///|
fn menu_tr(key : String) -> String {
  tr(key)
}

///|
/// What the menu bar was last given for ("": not yet): its language, whether a chat was open, the keys changed here.
pub let menu_bar_given : Ref[String] = Ref("")

///|
/// The menu bar, as JSON (@hostapi.menu_setup's): `prefs` the core's (the keys changed in 快捷键), `in_chat` whether a chat
/// is open (its actions can be done).
pub fn menu_bar_json(prefs : Json?, in_chat : Bool) -> String {
  let role = fn(key : String, role : String) -> Json {
    { "title": Json::string(menu_tr(key)), "role": Json::string(role) }
  }
  // one of the pages' actions: its words, its first key here, whether it can be done now
  let act = fn(action : String, enabled : Bool) -> Json {
    let title = match action {
      "zoom.in" => "desktop.menu.zoomIn"
      "zoom.out" => "desktop.menu.zoomOut"
      "zoom.reset" => "desktop.menu.resetZoom"
      _ => "desktop.menu." + action
    }
    let o : Map[String, Json] = {
      "title": Json::string(menu_tr(title)),
      "action": Json::string(action),
      "enabled": Json::boolean(enabled),
    }
    match @settings.keys_of(prefs, action) {
      [first, ..] => o["keys"] = Json::string(first)
      [] => ()
    }
    Json::object(o)
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
      act("settings", true),
      sep,
      role("desktop.menu.services", "services"),
      sep,
      role("desktop.menu.hide", "hide"),
      role("desktop.menu.hideOthers", "hideOthers"),
      role("desktop.menu.showAll", "showAll"),
      sep,
      role("desktop.menu.quit", "quit"),
    ]),
    menu("desktop.menu.file", "actions", [
      act("chat.new", true),
      act("chat.switch", true),
      sep,
      act("composer.file", in_chat),
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
    menu("desktop.menu.view", "actions", [
      act("sidebar.toggle", true),
      sep,
      act("zoom.in", true),
      act("zoom.out", true),
      act("zoom.reset", true),
      sep,
      act("chat.history", in_chat),
      act("chat.jobs", in_chat),
      act("chat.screen", in_chat),
    ]),
    menu("desktop.menu.go", "actions", [
      act("chat.prev", true),
      act("chat.next", true),
      sep,
      act("chat.latest", in_chat),
      act("chat.find", in_chat),
    ]),
    menu("desktop.menu.chat", "actions", [
      act("chat.stop", in_chat),
      sep,
      act("chat.archive", in_chat),
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
    menu("desktop.menu.help", "actions", [act("shortcuts", true)]),
    menu("desktop.tray.open", "tray", [
      role("desktop.tray.open", "show"),
      sep,
      role("desktop.menu.quit", "quit"),
    ]),
  ]).stringify()
}

///|
/// Each frame: the menu bar given to the host once the frame is built, and again as what it shows changes (the
/// language, the keys, a chat open or not).
pub fn menu_bar(c : @ui.Ctx, src : Source) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let in_chat = app.nav.top() is Chat(_)
  let keys = match field(prefs, "keys") {
    Some(k) => k.stringify()
    None => ""
  }
  let given = "\{@sf.language()}|\{in_chat}|\{keys}"
  if given != menu_bar_given.val {
    c.after_build("menu-bar", fn() {
      menu_bar_given.val = given
      @hostapi.menu_setup(menu_bar_json(prefs, in_chat))
    })
  }
}
