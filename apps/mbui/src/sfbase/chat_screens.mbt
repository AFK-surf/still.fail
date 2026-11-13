// A chat's way to the screens of the station it runs on ("A chat's screens"): from its bar
// (the wide frame's chat page) and its agent's card (the phone's), the same for both. One screen alone opens at once;
// more, a menu of them, the machine's own display first (the core's order). Opened as any screen is (open_screen): the
// shell puts it beside the chat where the frame has room, over it where not.

///|
/// Whether `s` is a persistent user-opened tab of the station's browser.
fn chat_screen_user_tab(s : ChatScreen) -> Bool {
  s.id.has_prefix("browser:u_")
}

///|
/// Whether `s` is a sleeping user tab (`line` carries `已休眠` / `Sleeping`).
fn chat_screen_sleeping(s : ChatScreen) -> Bool {
  chat_screen_user_tab(s) && s.line.contains(@sf.t("core-views.screen.sleeping"))
}

///|
/// A screen's mark by its kind: a sleeping user tab, a tab of the station's browser, a simulator, else its display.
pub fn chat_screen_icon(s : ChatScreen) -> String {
  if chat_screen_sleeping(s) {
    return "moon"
  }
  match s.kind {
    "browser" => "web"
    "simulator" => "phone"
    _ => "monitor"
  }
}

///|
/// A screen's words in a menu of them: its title, and that an agent drives it while one does (or that it is sleeping).
pub fn chat_screen_label(s : ChatScreen) -> String {
  if s.agent {
    s.title + " · " + @sf.t("web-pages.chat.screenAgent")
  } else if chat_screen_sleeping(s) {
    s.title + " · " + @sf.t("core-views.screen.sleeping")
  } else {
    s.title
  }
}

///|
/// Whether an agent drives any of the chat's screens now: its way to them marked so.
pub fn chat_screens_driven(screens : Array[ChatScreen]) -> Bool {
  screens.iter().any(fn(s) { s.agent })
}

///|
/// The first of the chat's screens, its station's own display where it has one (its keys, ⌘K, the menu bar: chat.screen).
pub fn chat_screen_first(r : ChatRef, screens : Array[ChatScreen]) -> Unit {
  match screens {
    [s, ..] => open_screen(r.station, s.id, Some(s.title))
    [] => ()
  }
}

///|
/// The chat's screens from what was pressed (`from`): the one alone opened, else a menu of them grouped into user pages,
/// agent pages and physical/simulator screens when more than one group is present.
pub fn chat_screens_open(r : ChatRef, screens : Array[ChatScreen], from~ : @sf.Beside, along? : @ui.Along = Start) -> Unit {
  match screens {
    [] => ()
    [s] => open_screen(r.station, s.id, Some(s.title))
    _ => {
      let user_tabs = screens.filter(chat_screen_user_tab)
      let agent_tabs = screens.filter(fn(s) { s.kind == "browser" && !chat_screen_user_tab(s) })
      let other_screens = screens.filter(fn(s) { s.kind != "browser" })
      let groups = (if !user_tabs.is_empty() { 1 } else { 0 }) +
        (if !agent_tabs.is_empty() { 1 } else { 0 }) +
        (if !other_screens.is_empty() { 1 } else { 0 })
      let items : Array[@sf.MenuItem?] = []
      let add_group = fn(title : String, list : Array[ChatScreen]) {
        if list.is_empty() {
          return
        }
        if !items.is_empty() {
          items.push(None)
        }
        if groups > 1 {
          items.push(Some(@sf.menu_item_of(title, heading=true, fn() { })))
        }
        for s in list {
          items.push(Some(@sf.menu_item_of(chat_screen_label(s), icon=chat_screen_icon(s), fn() { open_screen(r.station, s.id, Some(s.title)) })))
        }
      }
      add_group(@sf.t("web-pages.screen.section"), other_screens)
      add_group(@sf.t("web-pages.screen.userPages"), user_tabs)
      add_group(@sf.t("web-pages.screen.agentPages"), agent_tabs)
      @sf.menu(items, from~, title=@sf.t("web-pages.chat.screen"), along~)
    }
  }
}
