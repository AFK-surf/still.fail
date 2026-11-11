// A page in a window of its own (a desktop's: @ui.window_open), beside the app's: another run of the app, started with
// what it shows (MBUI_WINDOW, as window_text writes it), that shows that page alone over the same account and ends as
// its window closes or the app's run ends. A station's screen is the page that goes there now: from the side panel's bar beside a chat
// (sfdesk's panel.mbt) and from its viewer's 控制中心 (sfpages' screen_panel.mbt), the screen leaving where it was.
// While its window is open, every way to that screen (a chat's link, its card, the station's page) brings the window
// to the front instead of opening it here too, a toast here saying so (window_front, open_page).

///|
/// The page this run shows alone, in a window of its own (MBUI_WINDOW, src/stillfail's main); None: the app's run.
pub let lone_page : Ref[Page?] = Ref(None)

///|
/// What a window of its own is started with to show `p` (window_page reads it back): a station's screen; None for a
/// page that goes in none.
pub fn window_text(p : Page) -> String? {
  match p {
    Screen(at) =>
      Some(
        (
          {
            "screen": {
              "station": Json::string(at.station),
              "screen": Json::string(at.screen),
              "title": Json::string(at.title),
            },
          } : Json
        ).stringify(),
      )
    _ => None
  }
}

///|
/// The page a window of its own was started to show (window_text's), None when it names none.
pub fn window_page(s : String) -> Page? {
  let v = @json.parse(s) catch { _ => return None }
  guard v is Object(m) && m.get("screen") is Some(Object(at)) else { return None }
  guard at.get("station") is Some(String(station)) && station != "" else { return None }
  guard at.get("screen") is Some(String(screen)) && screen != "" else { return None }
  let title = match at.get("title") {
    Some(String(t)) => t
    _ => ""
  }
  Some(Screen({ station, screen, title, until_gone: false }))
}

///|
/// Whether `p` can be opened in a window of its own here: a desktop's app (not one such window already), a page that
/// goes in one.
pub fn window_opens_for(p : Page) -> Bool {
  lone_page.val is None && @ui.window_opens() && window_text(p) is Some(_)
}

///|
/// Page `p` opened in a window of its own (window_opens_for): whether it was. Where it showed, the caller takes it off.
pub fn open_window(p : Page) -> Bool {
  guard window_opens_for(p) else { return false }
  if window_front(p) {
    return true
  }
  match (window_text(p), window_key(p)) {
    (Some(what), Some(key)) => {
      let opened = @ui.window_open(what)
      if opened {
        windows_open[key] = what
      }
      opened
    }
    _ => false
  }
}

///|
/// What each window this run opened was started with, by what it shows (window_key): its title can differ from the
/// next way to it, the window being the same.
let windows_open : Map[String, String] = Map([])

///|
/// What `p` is, whichever way it was opened (its title aside): None for a page that goes in no window.
fn window_key(p : Page) -> String? {
  match p {
    Screen(at) => Some(at.station + "\n" + at.screen)
    _ => None
  }
}

///|
/// The window showing `p`, where one is open, brought to the front and a toast here saying so: whether it was (the
/// page is then not to be opened here as well). A window closed since is forgotten.
pub fn window_front(p : Page) -> Bool {
  guard lone_page.val is None && window_key(p) is Some(key) else { return false }
  guard windows_open.get(key) is Some(what) else { return false }
  let there = @ui.window_front(what)
  if there {
    toast_later(@sf.t("web-pages.screen.windowOpen"))
  } else {
    windows_open.remove(key)
  }
  there
}
