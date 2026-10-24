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
fn tab_let_go(r : ChatRef, tab : String) -> Unit {
  match tab_job(tab) {
    Some(job) => sv_closing[service_key(r.station, job)] = (r.station, job)
    None => ()
  }
}

///|
fn tab_kept(r : ChatRef, tab : String) -> Unit {
  match tab_job(tab) {
    Some(job) => sv_closing.remove(service_key(r.station, job))
    None => ()
  }
}

///|
/// After a build: the pages of tabs closed that it did not draw let go.
pub fn sv_sweep(c : @ui.Ctx, src : Source) -> Unit {
  for key, at in sv_closing {
    if !sv_drawn.contains(key) {
      let (station, job) = at
      c.tell("sv-let-go/" + key, fn() {
        if sv_closing.contains(key) {
          sv_closing.remove(key)
          service_left(src, station, job)
        }
      })
    }
  }
  sv_drawn.clear()
}

///|
/// The pages of tabs closed (by their service_key: station, job), not yet let go.
// kept across runs: put back by sv_reset (reset)
let sv_closing : Map[String, (String, String)] = {}

///|
/// The pages drawn in this build (by their service_key).
// kept across runs: put back by sv_reset (reset)
let sv_drawn : Map[String, Bool] = {}

///|
fn sv_reset() -> Unit {
  sv_closing.clear()
  sv_drawn.clear()
}

///|
/// The service `job` of chat `r`'s station, beside the chat: the page while it is up (and as it starts again), what
/// stopped it said otherwise.
fn service_pane(c : @ui.Ctx, src : Source, r : ChatRef, job : String) -> Unit {
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
      sv_page(c, src, r, job, port, name, state == "exited", number(j, "restarts").to_int(), text(j, "session"), None)
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
/// The page and its bar (Framed): the page under the bar as wide and tall as the pane; over it, while its service
/// starts again, what is said; once it is up, it loads anew.
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
) -> Unit {
  svc_keep.val = fn(patch) { (src.call)("prefs.set", patch, fn(_) {  }) }
  let p = service_page_for(r.station, job, prefs=(src.topic)("prefs", {}).value)
  sv_drawn[service_key(r.station, job)] = true
  p.port = port
  p.name = name
  p.session = session
  src_now.val = src.now
  let site = service_site(src, p, file, fn(url) {
    // a link elsewhere: one of still.fail's opened here as the core says, any other in the system's browser
    (chat_parts.val.open_link)(url)
  })
  // up again after a restart: the page loads anew (Restart)
  if p.restarting && !restarting {
    c.tell("service-tab/reload", fn() { site.reload() })
  }
  p.restarting = restarting
  c.box(style=sv_box, fn() {
    sv_bar(c, src, p, site, name, file is Some(_))
    c.box(style=sv_stage, fn() {
      c.after_build("service-tab/scale", fn() { site.set_scale(1.0) })
      c.native(site) |> ignore
      if restarting {
        c.layer(fn() {
          c.box(style=sv_restart_room, fn() { sv_restart(c, name, restarts) }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Back, forward, reload, how far its resources came, where it is (PreviewBar): typed, it goes there; a
/// visualization's only its name.
fn sv_bar(c : @ui.Ctx, src : Source, p : ServicePage, site : @ui.NativeView, name : String, fixed : Bool) -> Unit {
  let t = @sf.theme()
  let (at, can_back, can_forward, _, _) = site.page_at()
  let field_key = "service-tab/address/" + service_key(p.station, p.job)
  let editing = c.editor_focused(field_key)
  if at != p.logged_path {
    p.logged_path = at
    @ui.log("service: at \{at}")
  }
  c.box(style=sv_bar_row, fn() {
    if sv_button(c, "service-tab/back", "arrow-left", @sf.t("web-main.keymap.nav.back"), can_back) {
      site.go_back()
    }
    if sv_button(c, "service-tab/forward", "arrow-right", @sf.t("web-main.keymap.nav.forward"), can_forward) {
      site.go_forward()
    }
    if sv_button(c, "service-tab/reload", "refresh", @sf.t("web-main.preview.reload"), true) {
      site.reload()
    }
    // how far the page's resources came (PreviewLoad): a ring, red with one failed (a visualization's has none)
    if !fixed {
      let load = (src.topic)("previewLoad", { "station": Json::string(p.station), "port": Json::number(p.port.to_double()) }).value
      match load {
        Some(Object(_)) =>
          c.box(style=sv_ring, fn() {
            @sf.progress_ring(c, sv_ring_size, number(load, "percent") / 100.0, if number(load, "failed") > 0.0 {
              t.p.red
            } else {
              t.p.muted
            })
            |> ignore
          })
          |> ignore
        _ => ()
      }
    }
    let pill = c.id("service-tab/address")
    if c.clicked(pill) && !editing && !fixed {
      c.focus_editor(field_key)
    }
    c.box(style=if editing { sv_address_on } else { sv_address }, id=pill, fn() {
      @sf.icon(c, "web", size=sv_icon, color=t.p.muted) |> ignore
      c.text(name, style=sv_host) |> ignore
      if fixed {
        return
      }
      // where it went is what the bar says, unless someone is typing there
      if !editing && at != p.shown_path {
        p.shown_path = at
        p.address.set(at)
      }
      c.box(style=sv_path, fn() {
        let r = c.editor(
          field_key,
          font_size=sv_path_size,
          max_lines=1,
          plain=true,
          color=if editing { t.p.text } else { t.p.muted },
          caret_color=t.p.accent,
          enter_sends=true,
          field=p.address,
        )
        match r.submitted {
          Some(typed) => {
            let path = typed.trim().to_string()
            site.load(if path.has_prefix("/") { path } else { "/" + path })
            c.blur()
          }
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// One of the bar's buttons (iconBtn in the preview's bar): 28 square, faint and pressing nothing at either end of the
/// page's history; its name in its tip. True as it is pressed.
fn sv_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = if on { c.id(key) } else { 0 }
  c.cursor(id, Hand)
  let hot = on && c.lit(id)
  let b = c.box(style=if !on { sv_button_off } else if hot { sv_button_hot } else { sv_button_box }, id~, fn() {
    @sf.icon(c, icon, size=sv_icon, color=if hot { t.p.text } else { t.p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  if on {
    @sf.tip(c, key + "/tip", id, label)
  }
  id != 0 && c.clicked(id)
}

///|
/// Over the page while its service starts again (Restart): an amber dot, its name 正在重启, and how often so far.
fn sv_restart(c : @ui.Ctx, name : String, restarts : Int) -> Unit {
  c.box(style=sv_restart_pill, glass=@sf.glass_floating(), fn() {
    c.box(style=sv_restart_dot, fn() {  }) |> ignore
    c.box(style=sv_restart_words, fn() {
      c.text(@sf.t("web-main.preview.restarting", args=[("name", name)]), style=sv_restart_title) |> ignore
      c.text(
        if restarts > 0 {
          @sf.t("web-main.preview.restartAgain", args=[("n", restarts.to_string())])
        } else {
          @sf.t("web-main.preview.restartNote")
        },
        style=sv_restart_note,
      )
      |> ignore
    })
    |> ignore
  })
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
/// The bar (previewBar): 6 by 8 in, its parts 2 apart.
// kept across runs: a value (no field of it changes)
let sv_bar_row : @ui.Style = @ui.css("row w=Full px=S2 py=S1_5 gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sv_button_box : @ui.Style = @ui.css("w=S7 h=S7 radius=Lg align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sv_button_hot : @ui.Style = sv_button_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let sv_button_off : @ui.Style = sv_button_box.then(@ui.css("opacity=O35"))

///|
// kept across runs: a value (no field of it changes)
let sv_ring : @ui.Style = @ui.css("w=S7 h=S7 align=ACenter justify=JCenter")

///|
/// Where it is (previewAddress): the rest of the bar, 30 high, 4 from its neighbours, 12 in, a pill on the neutral
/// ground (the canvas with the focus's ring while typed in); its name (13, 500, the ink), its path after it (13, muted).
// kept across runs: a value (no field of it changes)
let sv_address : @ui.Style = @ui.style(
  row=true,
  w=@sf.grow,
  h=@sf.preview_address_h,
  mx=S1,
  px=S3,
  gap=S1_5,
  radius=Full,
  bg=Neutral,
  align=ACenter,
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let sv_address_on : @ui.Style = sv_address.then(@ui.css("bg=Bg border=B1_5 border_color=Focus"))

///|
// kept across runs: a value (no field of it changes)
let sv_host : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sv_path : @ui.Style = @ui.style(w=@sf.grow)

///|
/// The page under the bar: the rest of the pane, on the page's ground while it loads.
// kept across runs: a value (no field of it changes)
let sv_stage : @ui.Style = @ui.style(w=Full, h=@sf.grow, bg=Bg, clip=true)

///|
// kept across runs: a value (no field of it changes)
let sv_wait : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sv_said_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true)

///|
/// While it starts again (previewRestart): at the foot of the page, a pill 10 by 16 in on the glass, its dot (8, amber)
/// 12 before its words (13; how often, 12 muted).
// kept across runs: a value (no field of it changes)
let sv_restart_room : @ui.Style = @ui.css("w=Full h=Full pb=S5 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let sv_restart_pill : @ui.Style = @ui.css("row pl=S4 pr=S4_5 py=S2_5 gap=S3 radius=Full shadow=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sv_restart_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
// kept across runs: a value (no field of it changes)
let sv_restart_words : @ui.Style = @ui.css("gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let sv_restart_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sv_restart_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
let sv_icon : Double = 14.0

///|
let sv_ring_size : Double = 18.0

///|
/// The path typed (previewPath: the ui's 13).
let sv_path_size : Double = 13.0

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
  chat_page(c, src, w, r)
}
