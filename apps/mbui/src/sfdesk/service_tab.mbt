// A web service an agent started, or a visualization it posted, in a tab of the chat's side panel on the desktop (ember
// web/src/pages/ChatPage.tsx's `service:<job>` and `file:[…]` tabs; Preview.tsx ServiceFrame, FileFrame, PreviewBar,
// Restart; Preview.css.ts): the bar over it (back, forward, reload; how far the page's resources came; where it is, its
// name then its path, typed to go elsewhere — a visualization's only its name), the page under it, what is said over it
// while its service starts again. A service stopped, or failed, is said in its place. What serves the page and what it
// keeps is sfbase's (service_page.mbt, viz_file.mbt); closing its tab lets it go.

///|
/// A tab's service, `service:<job>` (None: none).
pub fn tab_service(tab : String) -> String? {
  if tab.has_prefix("service:") {
    Some(tab.view(start_offset="service:".length()).to_string())
  } else {
    None
  }
}

///|
/// A tab's visualization, `file:["<session>","<path>","<name>"]` (chat-tabs.ts, Preview.tsx fileService): its session,
/// its path and its name (None: none, or one that does not read).
pub fn tab_file(tab : String) -> (String, String, String)? {
  if !tab.has_prefix("file:") {
    return None
  }
  match (try Some(@json.parse(tab.view(start_offset="file:".length()).to_string())) catch { _ => None }) {
    Some(Array([String(session), String(path), String(name)])) => Some((session, path, name))
    _ => None
  }
}

///|
/// The tab of a visualization `path` named `name` that session `session` sent.
pub fn file_tab(session : String, path : String, name : String) -> String {
  "file:" + Json::array([Json::string(session), Json::string(path), Json::string(name)]).stringify()
}

///|
/// A service's or a visualization's page key among the service pages (sfbase's service_page_for): as the phone's are.
fn tab_job(tab : String) -> String? {
  match (tab_service(tab), tab_file(tab)) {
    (Some(job), _) => Some(job)
    (_, Some((session, path, _))) => Some("file:" + session + "\n" + path)
    _ => None
  }
}

///|
/// Its tab closed: what its page asked of the station stopped, its view gone (web: closePreview), once it is no longer
/// drawn (the panel shows what it showed as it slides out: sv_sweep); opened again before, kept.
fn tab_let_go(src : Source, r : ChatRef, tab : String) -> Unit {
  panel_screen_pages.remove(tabs_key(r) + "/" + tab)
  history_let_go(r, tab)
  match tab_job(tab) {
    Some(job) => {
      let key = service_key(r.station, job)
      sv_release_number.val += 1
      sv_closing[key] = { station: r.station, job, excluding: Some((r, tab)), id: sv_release_number.val }
      service_ownership_watch(src)
      service_release_pending(src, r.station, job)
    }
    None => ()
  }
}

///|
fn tab_kept(r : ChatRef, tab : String) -> Unit {
  match tab_job(tab) {
    Some(job) => {
      sv_closing.remove(service_key(r.station, job))
      service_ownership_idle()
    }
    None => ()
  }
}

///|
// A failed close leaves the tab as an owner. Keep the release request (there may also have been a page drop), but do
// not exclude this tab from the ownership check; a later real close or topic update can then finish the release.
fn service_close_failed(r : ChatRef, tab : String) -> Unit {
  guard tab_job(tab) is Some(job) else { return }
  let key = service_key(r.station, job)
  guard sv_closing.get(key) is Some(waiting) else { return }
  match waiting.excluding {
    Some((other, omitted)) if tabs_key(other) == tabs_key(r) && omitted == tab => {
      sv_release_number.val += 1
      sv_closing[key] = { ..waiting, excluding: None, id: sv_release_number.val }
    }
    _ => ()
  }
}

///|
/// After a build: the pages of tabs closed that it did not draw let go.
pub fn sv_sweep(c : @ui.Ctx, src : Source) -> Unit {
  for key, at in sv_closing {
    if !sv_drawn.contains(key) && !sv_nodes.contains(key) {
      c.tell("sv-let-go/" + key, fn() {
        service_release_pending(src, at.station, at.job)
      })
    }
  }
  sv_drawn.clear()
}

///|
/// A page left by its last stack entry or tab: wait until every other owner, including pending tab calls, lets it go.
priv struct ServiceRelease {
  station : String
  job : String
  excluding : (ChatRef, String)?
  id : Int
}

///|
/// The pages waiting to be released, by service_key.
// kept across runs: put back by sv_reset (reset)
let sv_closing : Map[String, ServiceRelease] = {}

///|
// kept across runs: a unique number, never reused across reset
let sv_release_number : Ref[Int] = Ref(0)

///|
/// A stack page has left. If another page or tab still owns the site, retain the request and check it again when that
/// owner leaves; a tab's existing exclusion remains until its close has been reflected in the core's topic.
pub fn service_page_drop(src : Source, station : String, job : String) -> Unit {
  let key = service_key(station, job)
  if !sv_closing.contains(key) {
    sv_release_number.val += 1
    sv_closing[key] = { station, job, excluding: None, id: sv_release_number.val }
  }
  service_ownership_watch(src)
  service_release_pending(src, station, job)
}

///|
/// Recheck after a holder leaves or a pending tab request changes; a later open can cancel this particular release.
fn service_release_pending(src : Source, station : String, job : String) -> Unit {
  let key = service_key(station, job)
  guard sv_closing.get(key) is Some(waiting) else { return }
  if service_page_kept(src, station, job, excluding=waiting.excluding) { return }
  guard sv_closing.get(key) is Some(current) && current.id == waiting.id else { return }
  sv_closing.remove(key)
  service_left(src, station, job)
  service_ownership_idle()
}

///|
/// The pages drawn in this build (by their service_key).
// kept across runs: put back by sv_reset (reset)
let sv_drawn : Map[String, Bool] = {}

///|
/// Service page and tab nodes still shown, including while they slide out. A temporarily hidden node does not release
/// the page; a closed page or tab releases it only once its last visible node leaves.
// kept across runs: put back by sv_reset (reset)
let sv_nodes : Map[String, Array[Int]] = {}

///|
/// A unique holder also keeps a node left from before a reset from releasing a later node's page.
// kept across runs: a unique number, never reused across reset
let sv_node_number : Ref[Int] = Ref(0)

///|
pub fn service_node_held(v : @view.View, src : Source, station : String, job : String) -> Unit {
  let key = service_key(station, job)
  sv_node_number.val += 1
  let id = sv_node_number.val
  let held = sv_nodes.get(key).unwrap_or([])
  held.push(id)
  sv_nodes[key] = held
  v.owns(fn() {
    match sv_nodes.get(key) {
      Some(holders) =>
        match holders.search_by(fn(holder) { holder == id }) {
          Some(i) => {
            holders.remove(i) |> ignore
            if holders.is_empty() {
              sv_nodes.remove(key)
              service_release_pending(src, station, job)
            }
          }
          None => ()
        }
      None => ()
    }
  }) |> ignore
}

///|
fn sv_reset() -> Unit {
  sv_closing.clear()
  sv_drawn.clear()
  sv_nodes.clear()
  service_ownership_reset()
}

///|
/// The service `job` of chat `r`'s station, beside the chat: the page while it is up (and as it starts again), what
/// stopped it said otherwise.
fn service_pane(c : @ui.Ctx, src : Source, r : ChatRef, job : String, close? : (() -> Unit)? = None) -> Unit {
  let found = (src.topic)("job", { "station": Json::string(r.station), "id": Json::string(job) })
  let j = found.value
  let name = match text(j, "name") {
    "" => svc("android-chat.preview.service")
    n => n
  }
  let port = number(j, "port").to_int()
  let state = text(j, "state")
  match j {
    None | Some(Null) =>
      match found.error {
        Some(e) => sv_said(c, svc("android-chat.preview.notFound", args=[("error", text(Some(e), "message"))]))
        None => c.box(style=sv_wait, fn() { @sf.wait_line(c, @sf.t("common.connecting"), key="service-tab") }) |> ignore
      }
    _ if port > 0 && flag(j, "open") && (state == "running" || state == "exited") =>
      sv_page(c, src, r, job, port, name, state == "exited", number(j, "restarts").to_int(), text(j, "session"), None, close~)
    _ =>
      sv_said(c, @sf.t(if state == "failed" { "web-pages.chat.serviceFailed" } else { "web-pages.chat.serviceStopped" }, args=[
        ("name", name),
      ]))
  }
}

///|
/// The visualization `path` named `name` of session `session` on chat `r`'s station, beside the chat (FileFrame): the
/// file in the web's stylesheet with what its widget kept; nowhere else to go, its bar names it.
fn file_pane(c : @ui.Ctx, src : Source, r : ChatRef, session : String, path : String, name : String) -> Unit {
  match viz_load(c, src, r.station, session, path) {
    Some(Err(_)) => sv_said(c, @sf.t("web-main.preview.unreadable", args=[("name", name)]))
    None => c.box(style=sv_wait, fn() { @sf.wait_line(c, @sf.t("common.connecting"), key="file-tab") }) |> ignore
    Some(Ok((html, state))) => {
      let job = "file:" + session + "\n" + path
      let key = service_key(r.station, job)
      let f = match service_files.get(key) {
        Some(f) => f
        None => {
          let f : FilePage = { html, state, station: r.station, key: session, path }
          service_files[key] = f
          f
        }
      }
      sv_page(c, src, r, job, 0, name, false, 0, session, Some(f))
    }
  }
}

///|
/// The page and its bar, in the pane (the pages' one service view, sfpages service.mbt), kept while it is drawn.
fn sv_page(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  job : String,
  port : Int,
  name : String,
  restarting : Bool,
  restarts : Int,
  session : String,
  file : FilePage?,
  close? : (() -> Unit)? = None,
) -> Unit {
  sv_drawn[service_key(r.station, job)] = true
  c.box(style=sv_box, fn() { @sfpages.service_view(c, src, r.station, job, port, name, restarting, restarts, session, file~, close~) })
  |> ignore
}

///|
/// What is said in the page's place (Empty, previewMissing): in the middle, muted.
fn sv_said(c : @ui.Ctx, words : String) -> Unit {
  @sf.empty(c, fn() { c.text(words, style=sv_said_words) |> ignore })
}

///|
// kept across runs: a value (no field of it changes)
let sv_box : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let sv_wait : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sv_said_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
/// A web service asked as a page (a link's `?service=<job>`, OpenJobs' open): on the desktop its chat (the one of the
/// agent that runs it, as the station says) with it beside it, the page the chat's; not found, said so.
fn service_beside(c : @ui.Ctx, src : Source, w : Workspace, station : String, job : String) -> Unit {
  let found = (src.topic)("job", { "station": Json::string(station), "id": Json::string(job) })
  match text(found.value, "session") {
    "" =>
      match found.error {
        Some(e) => sv_said(c, svc("android-chat.preview.notFound", args=[("error", text(Some(e), "message"))]))
        None => ()
      }
    session => tab_beside(c, src, w, station, session, "service:" + job)
  }
}

///|
/// Tab `tab` opened in front beside chat `session` on `station`, the page the chat's in place of the one that asked
/// (drawn as it is until then): the chat under it where it was asked from there (as it mostly is: a chat's link, its
/// jobs), else that chat.
fn tab_beside(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  station : String,
  session : String,
  tab : String,
) -> Unit {
  let stack = app.nav.pages()
  let (r, under) = match stack {
    [.., Chat(u), _] if u.station == station && u.session == session => (u, true)
    _ => ({ station, session, title: "", station_name: "" }, false)
  }
  c.tell("beside/" + tab, fn() {
    if under {
      app.nav.pop() |> ignore
    } else {
      app.nav.replace(Chat(r))
    }
    side_change(src, r, "open", Some(tab))
  })
}
