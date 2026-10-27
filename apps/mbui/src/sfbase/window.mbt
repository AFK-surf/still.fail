// A page in a window of its own (a desktop's: @ui.window_open), beside the app's: another run of the app, started with
// what it shows (MBUI_WINDOW, as window_text writes it), that shows that page alone over the same account and ends as
// its window closes. A station's screen is the page that goes there now: from the side panel's bar beside a chat
// (sfdesk's panel.mbt) and from its viewer's 控制中心 (sfpages' screen_panel.mbt), the screen leaving where it was.

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
  match window_text(p) {
    Some(what) => @ui.window_open(what)
    None => false
  }
}
