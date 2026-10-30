// A web service an agent started (a dev server, a report it serves), full screen over its chat (ember apps/android
// chat/screens/Preview.kt PreviewScreen, PreviewWeb.kt, PreviewLoad.kt; web mobile/Preview.tsx): found by its job (the
// `job` topic), known by its name, never its port. Its page is a site view (src/ui/native.mbt `NativeView::site`: a
// web view of a host of its own) whose every request is answered here from the station through the core
// (`station.preview` with `stream`: the head, then the body as it comes; stopped at the station when the page lets it
// go), redirects followed here (to the service only, 5 at most, resolved as a browser does) and its cookies kept here
// and sent along (where the host keeps them itself, as Android's WebView does, they are its). page.js goes first in
// each of its pages, with the app's StillFailPreviewNative behind it (service_link.mbt): its WebSockets, its requests'
// bodies, its top page's fetch() as it comes, marking it (service_marks.mbt). No port on the station is open to anyone.
//
// Its bar under the page, one row in a thumb's reach (as a phone's browser has it: Safari's compact bar at the foot;
// sfpages' service_foot_bar): back and forward in the page's own history (the system's back too, while there is a page
// to go back to), where it is (its name, then its path; typed, it goes there) with reload at its end and how far its
// resources came along its foot (the `previewLoad` topic), marking it, its ⋯ (its size; each of its resources, in a
// sheet). The page fills what is over the bar, or is laid out at
// a size of its own (a phone's, a tablet's, a laptop's, a desktop's, one typed) on the grey of a canvas, fitted and
// centred, with its screen's corners; the ground dragged moves it, two fingers zoom it, a double tap fits it again: its
// sizes chosen from the ⋯ (the sizes, 自定义, turned; 移动页面, 适应), as on every screen (sfpages' service.mbt). A
// service being started again is said over the page, which loads anew once it is back; one stopped, or not found, is
// said in its place.
//
// The size chosen is kept on the device (the core's prefs `previewSizes`); the address is typed with the keyboard for
// addresses, its key 前往.
//
// Not yet, against the Android app (each waits on something mbui's hosts or the core do not do yet): a marked picture's
// pin and edge as the page shows them (drawn as an image's marks are), and on Android the top page's fetch() on its
// port (the WebView's cookies are not the app's to send along: it goes as the page's other requests do).

///|
/// A station's name as the workspace's stations say it.
fn station_name(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  match stations_of((src.topic)("stations", { "scope": Json::string(scope) }).value).iter().find_first(fn(s) {
    s.address == station
  }) {
    Some(s) => s.name
    None => ""
  }
}

///|
/// The service `job` of `station`'s page (Preview.kt PreviewScreen).
pub fn service_page(c : @ui.Ctx, src : Source, station : String, job : String) -> Unit {
  let t = @sf.theme()
  let found = (src.topic)("job", { "station": Json::string(station), "id": Json::string(job) })
  let j = found.value
  let name = match text(j, "name") {
    "" => svc("android-chat.preview.service")
    n => n
  }
  let port = number(j, "port").to_int()
  let up = j is Some(Object(_)) && port > 0 && flag(j, "open")
  // over the navigation bar (Preview.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
    service_bar(c, name, station_name(src, station))
    match (j, found.error) {
      (None, Some(e)) | (Some(Null), Some(e)) =>
        @sfpages.service_note(c, svc("android-chat.preview.notFound", args=[("error", text(Some(e), "message"))]))
      (None, _) | (Some(Null), _) =>
        c.box(w=Fill(1.0), padx=20.0, pady=8.0, align=ACenter, fn() {
          @sf.wait_line(c, svc("common.reading"), key="service")
        })
        |> ignore
      _ =>
        if !up {
          @sfpages.service_note(c, svc("android-chat.preview.stopped", args=[("name", name)]))
        } else {
          @sfpages.service_view(
            c,
            src,
            station,
            job,
            port,
            name,
            text(j, "state") == "exited",
            number(j, "restarts").to_int(),
            text(j, "session"),
          )
        }
    }
  })
  |> ignore
}

///|
/// The page's compact bar (Parts.kt NavBar): 对话 back in the accent, the service's name and its station on one line (as
/// an in-app browser's bar has its page's: what is over the page as little as it can be; the user, 2026-10-27:
/// 是不是上面也应该少一点).
fn service_bar(c : @ui.Ctx, title : String, station : String) -> Unit {
  let said = if station == "" { title } else { title + " · " + station }
  if @sf.nav_bar(c, "service/back", svc("android-chat.preview.back"), said, top=status_top()) {
    @sfbase.go_back() |> ignore
  }
}

///|
/// The visualization at `path` of the session `key` of `station`, as a page of its own (web mobile's Preview.tsx for a
/// `file:` service): the file served to the preview's page from here, with what its widget kept (and keeps from now
/// on); its bar has only its name.
fn preview_file_page(c : @ui.Ctx, src : Source, station : String, key : String, path : String, name : String) -> Unit {
  // over the navigation bar (Preview.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  within_bars(c, top=false, ground=file_view_page, fn() { c.box(style=bars_fill, fn() {
    service_bar(c, name, station_name(src, station))
    match viz_load(c, src, station, key, path) {
      Some(Err(_)) => @sfpages.service_note(c, viz_tr("android-chat.preview.unreadable", args=[("name", name)]))
      None =>
        c.box(style=@sfpages.file_wait, fn() { @sf.wait_line(c, viz_tr("common.opening"), key="preview-file") }) |> ignore
      Some(Ok((html, state))) => {
        let job = "file:" + key + "\n" + path
        let f = match service_files.get(service_key(station, job)) {
          Some(f) => f
          None => {
            let f : FilePage = { html, state: @signals.signal(state, same=fn(a, b) { a == b }), station, key, path }
            service_files[service_key(station, job)] = f
            f
          }
        }
        @sfpages.service_view(c, src, station, job, 0, name, false, 0, key, file=Some(f))
      }
    }
  })
  |> ignore })
}

///|
/// The page, on the page's ground; what it waits on where its note would be (PreviewWait: 20 in, 8 over and under,
/// in the middle); the name in the address's place (13, medium, the ink, one line).
// kept across runs: a value (no field of it changes)
let file_view_page : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

