// A chat's way to the screens of the station it runs on (docs/remote-screens.md, "A chat's screens"): from its bar
// (the wide frame's chat page) and its agent's card (the phone's), the same for both. One screen alone opens at once;
// more, a menu of them, the machine's own display first (the core's order). Opened as any screen is (open_screen): the
// shell puts it beside the chat where the frame has room, over it where not.

///|
/// A screen's mark by its kind: a tab of the station's browser, a simulator, else its display.
pub fn chat_screen_icon(s : ChatScreen) -> String {
  match s.kind {
    "browser" => "web"
    "simulator" => "phone"
    _ => "monitor"
  }
}

///|
/// A screen's words in a menu of them: its title, and that an agent drives it while one does.
pub fn chat_screen_label(s : ChatScreen) -> String {
  if s.agent {
    s.title + " · " + @sf.t("web-pages.chat.screenAgent")
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
/// The chat's screens from what was pressed (`from`): the one alone opened, else a menu of them.
pub fn chat_screens_open(r : ChatRef, screens : Array[ChatScreen], from~ : @sf.Beside) -> Unit {
  match screens {
    [] => ()
    [s] => open_screen(r.station, s.id, Some(s.title))
    _ =>
      @sf.menu(
        screens.map(fn(s) {
          Some(@sf.menu_item_of(chat_screen_label(s), icon=chat_screen_icon(s), fn() { open_screen(r.station, s.id, Some(s.title)) }))
        }),
        from~,
        title=@sf.t("web-pages.chat.screen"),
      )
  }
}
