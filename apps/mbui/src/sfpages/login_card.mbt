// A station's login to a command-line tool its agents use, as a card, the one on every screen (still.fail
// web/src/MachineLogins.tsx LoginCard, ActiveCard, CancelLogin, PasteSteps, CodeField, CardCode, StepButton;
// MachineLogins.css.ts card…; the web's phone the same card): in a chat under the agent's message (decision.mbt), on
// the station page's 登录 while it is under way (station_cards.mbt, settings' station_logins.mbt).
// Its title with 取消 as its × in the card's corner; what the person does now by its step — a device code with 复制并打开,
// a page to open, a loopback login's page once the core listens for the browser's callback, a page whose code is pasted
// back — the step's button the card's width, solid while it is the next thing to do, and where the station has a
// browser of its own the same step there in a ⋯ beside it (seldom used: the step itself only where this device cannot
// do it); while its agent answers the command or it is checked, how it stands. Ended, one quiet line saying how. What it shows is the core's
// (`machineLogins`, `machineLogin`); what is done goes through its calls, under way on its button (the core's `doing`).

///|
/// What was pressed here, by login (a step's button plain grey once pressed: the eye on to what follows; followed, the
/// card made once reading it), whether a code is typed in its field, and the field: these two by the place its card is
/// drawn in as well (login_field), a login's card being in its chat and on its station's page at once.
priv struct LoginsHere {
  pressed : @sf.LiveMap[String, Bool]
  fields : Map[String, @ui.Field]
}

///|
let logins_here : LoginsHere = { pressed: @sf.LiveMap::new(), fields: {} }

///|
/// As at the start (tests).
pub fn login_cards_reset() -> Unit {
  logins_here.pressed.clear()
  logins_here.fields.clear()
  st_logins_open.clear()
}

// ── what a card says and does (its old view's and its node's) ─────────────

///|
/// Login `id` of `station` as the core says it now (None: one it does not know, ended long ago).
fn login_of(core : Core, station : String, id : String) -> Json? {
  let ask = login_ask(station, id)
  match (core.topic)(ask.0, ask.1).get().value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// What the core is asked for login `id` of `station` (login_of's, its card's): its `machineLogin`.
fn login_ask(station : String, id : String) -> (String, Map[String, Json]) {
  ("machineLogin", { "station": Json::string(station), "id": Json::string(id) })
}

///|
/// The station's logins as the core says them now (what may be done of them: `canLogin`, `canRelay`).
fn logins_of(core : Core, station : String) -> Json? {
  let ask = logins_ask(station)
  (core.topic)(ask.0, ask.1).get().value
}

///|
/// What the core is asked for station `station`'s logins (logins_of's, its page's 登录's): its `machineLogins`.
fn logins_ask(station : String) -> (String, Map[String, Json]) {
  ("machineLogins", { "station": Json::string(station) })
}

///|
/// An ended login's line (as an answered decision's: 已在 willow 上登录 gh), and whether it failed (said in red).
fn login_ended(l : Json?) -> (String, Bool) {
  let words = match text(l, "endedText") {
    "" => text(l, "title") + " · " + text(l, "statusText")
    s => s
  }
  (words, text(l, "state") == "failed")
}

///|
/// A line of how a login stands or what to do (login_said's): red, what kept this device from the callback; busy, a
/// spinner before it; last, as far from the card's foot as the title from its top.
priv struct LoginSaid {
  words : String
  red : Bool
  busy : Bool
  last : Bool
}

///|
fn said_line(words : String, red? : Bool = false, busy? : Bool = false, last? : Bool = false) -> LoginSaid {
  { words, red, busy, last }
}

///|
/// A step's button (login_step's): by its key, its words, solid while it is the next thing to do, spinning while it is
/// under way, ↗ for a page opened elsewhere, the other ways of doing it in a ⋯ beside it, last in the card; `press` what
/// it does, at once; `told`: in an old view, told by that key once the frame's builds are over (what is pressed as it
/// is built: Ctx::tell), else done as it is pressed.
priv struct LoginStep {
  key : String
  label : String
  solid : Bool
  busy : Bool
  external : Bool
  more : Array[@sf.MenuItem]
  last : Bool
  press : () -> Unit
  told : String?
}

///|
fn step_of(
  key : String,
  label : String,
  solid : Bool,
  on_press~ : () -> Unit,
  busy? : Bool = false,
  external? : Bool = false,
  more? : Array[@sf.MenuItem] = [],
  last? : Bool = true,
  told? : String,
) -> LoginStep {
  { key, label, solid, busy, external, more, last, press: on_press, told }
}

///|
/// What a login under way shows, for one who may finish it (ActiveCard's): its lines, the device code, the step's own
/// button. One whose page gives a code to paste back is login_paste_shows'.
priv struct LoginShows {
  said : Array[LoginSaid]
  code : String
  step : LoginStep?
}

///|
/// What login `l` of `station` under way shows now (login_active's): what the person does now by its step (or, while
/// its agent answers the command or it is checked, how it stands), then the step; `relay`: this device may take the
/// browser's callback.
fn login_shows(core : Core, station : String, l : Json?, relay : Bool) -> LoginShows {
  let id = text(l, "id")
  let url = text(l, "url")
  // checking what came back (the browser's callback): nothing left for the person but to wait
  let step = if flag(l, "waiting") || text(l, "state") == "verifying" { "" } else { text(l, "step") }
  let domain = match text(l, "domain") {
    "" => ""
    d => @sf.t("web-main.logins.domain", args=[("domain", d)])
  }
  let pressed = logins_here.pressed.get(id).unwrap_or(false)
  let code = text(l, "code")
  // the same step in the station's own browser, for the ⋯ beside the step's button
  let elsewhere = match login_station_way(core, station, l) {
    Some(way) => [way]
    None => []
  }
  match step {
    "device" if code != "" => {
      let page = match text(l, "codeUrl") {
        "" => url
        u => u
      }
      // one press: the code copied first, then its page; the code stays on show for a clipboard that refused it
      let go = step_of("login-main/" + id, @sf.t("web-main.logins.copyOpen"), !pressed, more=login_page_ways(page, elsewhere), on_press=fn() {
        @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
          logins_here.pressed[id] = true
          @sfbase.copy_out(code)
          login_open(core, page)
        })
      })
      { said: [said_line(@sf.t("web-main.logins.device", args=[("domain", text(l, "domain"))]))], code, step: Some(go) }
    }
    // this device cannot take the browser's callback (a web page), or its port was taken just now: the station's
    // browser, which can, is the step (this device's again in its ⋯), else what is wrong is said; the page's host all
    // the same
    "loopback" if elsewhere.length() > 0 && (!relay || text(l, "relayText") != "") => {
      let said : Array[LoginSaid] = []
      if text(l, "relayText") != "" && relay {
        said.push(said_line(text(l, "relayText"), red=true))
      }
      if domain != "" {
        said.push(said_line(domain))
      }
      let busy = @settings.is_doing(core, ["machineLogin.browser"], [("station", station), ("id", id)])
      let again = if relay {
        [
          @sf.menu_item_of(@sf.t("web-main.logins.signIn"), fn() {
            @settings.confirm_claude_auth(text(l, "name") == "claude", fn() { login_relay_now(core, station, id, text(l, "title")) })
          }),
        ]
      } else {
        []
      }
      // (confirmed first where it asks to be, done as it is confirmed; else told once the frame's builds are over)
      let asks = login_station_asks(l)
      let go = step_of(
        "login-station/" + id,
        text(l, "browserText"),
        true,
        busy~,
        more=again,
        told?=if asks { None } else { Some("login-station/" + id) },
        on_press=fn() {
          if asks {
            @settings.confirm_claude_auth(true, fn() { login_station_go(core, station, l) })
          } else {
            login_station_go(core, station, l)
          }
        },
      )
      { said, code: "", step: Some(go) }
    }
    "loopback" if !relay => {
      let said : Array[LoginSaid] = [said_line(@sf.t("web-main.logins.needsDesktop"), last=domain == "")]
      if domain != "" {
        said.push(said_line(domain, last=true))
      }
      { said, code: "", step: None }
    }
    "loopback" => {
      let opened = flag(l, "listening")
      let said : Array[LoginSaid] = []
      if opened {
        said.push(said_line(@sf.t("web-main.logins.waitingBrowser"), busy=true))
      } else if text(l, "relayText") != "" {
        said.push(said_line(text(l, "relayText"), red=true))
        if domain != "" {
          said.push(said_line(domain))
        }
      } else if domain != "" {
        said.push(said_line(domain))
      }
      let busy = @settings.is_doing(core, ["machineLogin.open"], [("station", station), ("id", id)])
      let label = @sf.t(if opened { "web-main.logins.openAgain" } else { "web-main.logins.signIn" })
      // (confirmed first for Claude: done as it is confirmed; else told once the frame's builds are over)
      let claude = text(l, "name") == "claude"
      let go = step_of(
        "login-main/" + id,
        label,
        !opened,
        busy~,
        more=elsewhere,
        told?=if claude { None } else { Some("login-open/" + id) },
        on_press=fn() {
          if claude {
            @settings.confirm_claude_auth(true, fn() { login_relay_now(core, station, id, text(l, "title")) })
          } else {
            login_relay_now(core, station, id, text(l, "title"))
          }
        },
      )
      { said, code: "", step: Some(go) }
    }
    "open" if url != "" => {
      let go = step_of("login-main/" + id, @sf.t("web-main.logins.signIn"), !pressed, more=login_page_ways(url, elsewhere), on_press=fn() {
        @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
          logins_here.pressed[id] = true
          login_open(core, url)
        })
      })
      { said: if domain != "" { [said_line(domain)] } else { [] }, code: "", step: Some(go) }
    }
    _ => { said: [said_line(text(l, "statusText"), busy=true, last=true)], code: "", step: None }
  }
}

///|
/// What a login whose page gives a code to paste back shows now (PasteSteps'): where to sign in and what to bring back,
/// then 打开登录页 (solid until pressed here or a code is in: `typed`), and whether what is typed is sent or checked
/// (`busy`: 完成 turning, nothing more sent).
priv struct LoginPaste {
  lead : LoginSaid
  step : LoginStep
  busy : Bool
}

///|
fn login_paste_shows(core : Core, station : String, l : Json?, typed : Bool) -> LoginPaste {
  let id = text(l, "id")
  let sending = @settings.is_doing(core, ["machineLogin.answer"], [("station", station), ("id", id)])
  let checking = text(l, "state") == "verifying"
  let busy = sending || checking
  let opened = logins_here.pressed.get(id).unwrap_or(false)
  let lead = if checking {
    text(l, "statusText")
  } else {
    match text(l, "domain") {
      "" => text(l, "statusText")
      d => @sf.t("web-main.logins.pasteLead", args=[("domain", d)])
    }
  }
  let elsewhere = match login_station_way(core, station, l) {
    Some(way) => [way]
    None => []
  }
  let step = step_of(
    "login-paste-open/" + id,
    @sf.t("web-main.logins.openPage"),
    !opened && !typed && !busy,
    external=true,
    more=login_page_ways(text(l, "url"), elsewhere),
    last=false,
    on_press=fn() {
      @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
        logins_here.pressed[id] = true
        login_open(core, text(l, "url"))
      })
    },
  )
  { lead: said_line(lead), step, busy }
}

///|
/// The code pasted back for login `id` of `station` sent (`machineLogin.answer`).
fn login_answer(core : Core, station : String, id : String, code : String) -> Unit {
  @settings.act(core, @sf.t("web-main.logins.answerWhat"), "machineLogin.answer", {
    "station": Json::string(station),
    "id": Json::string(id),
    "text": Json::string(code),
  })
}

///|
/// Whether login `id` of `station` is being cancelled (its × spinning).
fn login_cancelling(core : Core, station : String, id : String) -> Bool {
  @settings.is_doing(core, ["machineLogin.cancel"], [("station", station), ("id", id)])
}

///|
/// Login `id` of `station` cancelled (`machineLogin.cancel`), as its × is pressed.
fn login_cancel_now(core : Core, station : String, id : String) -> Unit {
  @settings.act(core, @sf.t("web-main.logins.cancelWhat"), "machineLogin.cancel", { "station": Json::string(station), "id": Json::string(id) })
}

// ── the card, an old view's ─────────────────────────────────────────────

///|
/// Login `id` of `station` as its card; one the core does not know (ended long ago) draws nothing, the message's words
/// say it. `marked`: the one a link pointed to (its ground the accent, faint). `place`: where it is drawn (its chat, its
/// station's page), each place's code field its own.
pub fn login_card(
  c : @ui.Ctx,
  core : Core,
  station : String,
  id : String,
  marked? : Bool = false,
  place? : String = "chat",
) -> Unit {
  let l = match login_of(core, station, id) {
    Some(_) as v => v
    None => return
  }
  // signed in while its card is in view, felt as something done; failed, as something refused (feel.mbt)
  @sfbase.felt_change(c, "login-done/" + station + "/" + id, text(l, "state") == "done", Confirm)
  @sfbase.felt_change(c, "login-failed/" + station + "/" + id, text(l, "state") == "failed", Reject)
  // ended: one quiet line, failed in red; no card
  if !flag(l, "active") {
    let (words, failed) = login_ended(l)
    c.text(words, style=if failed { lc_ended_failed } else { lc_ended }) |> ignore
    return
  }
  let all = logins_of(core, station)
  let in_sheet = place == "sheet"
  let room = if in_sheet {
    lc_room_sheet.then(@sf.panel_card_out()).then(@sf.panel_card_last())
  } else {
    lc_room
  }
  let card = if in_sheet {
    if marked { lc_card_sheet_marked } else { lc_card_sheet }
  } else {
    if marked { lc_card_marked } else { lc_card }
  }
  c.box(style=room, fn() {
    c.box(style=card, fn() {
      if flag(all, "canLogin") {
        if in_sheet {
          c.box(style=lc_title_room, fn() { c.text(text(l, "title"), style=lc_title) |> ignore }) |> ignore
        } else {
          c.box(style=lc_head, fn() {
            c.box(style=lc_title_room, fn() { c.text(text(l, "title"), style=lc_title) |> ignore }) |> ignore
            login_cancel(c, core, station, id)
          })
          |> ignore
        }
        login_active(c, core, station, l, flag(all, "canRelay"), place)
      } else {
        c.box(style=lc_title_room, fn() { c.text(text(l, "title"), style=lc_title) |> ignore }) |> ignore
        login_said(c, said_line(text(l, "statusText"), last=true))
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A step left of something under an agent's message, as a login's card looks (its ground, its title, a line under it
/// where there is one), the whole card the way to it (`go`), a › in its corner where a login's × is: what is left on
/// the phone for an approved request of it (decision.mbt phone_ask_card). Quiet as the cards beside it are, no button
/// of its own (2026-10-30, user: a card with a solid button was 「明显有点过大了，而且好像不是很搭风格」). A step with
/// nothing to press (`go` None) is the card alone: no ›, no answer to a press.
pub fn step_card(c : @ui.Ctx, key : String, title : String, line : String, go? : (() -> Unit)? = None) -> Unit {
  let x = if go is Some(_) { c.id(key) } else { 0 }
  match go {
    Some(go) => c.on_press(x, fn() { go() })
    None => ()
  }
  c.box(style=lc_room, fn() {
    let b = c.box(style=if go is Some(_) { lc_card_step } else { lc_card }, id=x, fn() {
      c.box(style=lc_head, fn() {
        c.box(style=if line == "" { lc_title_alone } else { lc_title_room }, fn() { c.text(title, style=lc_title) |> ignore }) |> ignore
        if go is Some(_) {
          c.box(style=lc_cancel, fn() { @sf.icon(c, "chevron-right", size=lc_icon, color=@sf.theme().p.muted) |> ignore }) |> ignore
        }
      })
      |> ignore
      if line != "" {
        login_said(c, said_line(line, last=true))
      }
    })
    if go is Some(_) {
      c.semantics(b, Button, id=x, label=title)
    }
  })
  |> ignore
}

///|
/// 取消, as the card's × (CancelLogin: a small panel's icon button, in its corner, concentric with it).
fn login_cancel(c : @ui.Ctx, core : Core, station : String, id : String) -> Unit {
  let busy = login_cancelling(core, station, id)
  let x = if busy { 0 } else { c.id("login-cancel/" + station + "/" + id) }
  c.on_press(x, fn() {
    login_cancel_now(core, station, id)
  })
  let b = c.box(style=lc_cancel, id=x, fn() {
    if busy {
      @sf.spinner(c, size=lc_spin) |> ignore
    } else {
      @sf.icon(c, "close", size=lc_icon, color=@sf.theme().p.muted) |> ignore
    }
  })
  c.semantics(b, Button, id=x, label=@sf.t("web-main.logins.cancelWhat"))
}

///|
/// A line of how it stands or what to do (cardStatus: 12 on 18, grey; red what kept this device from the callback), a
/// spinner 6 before it while it waits; `last`, as far from the card's foot as the title from its top.
fn login_said(c : @ui.Ctx, s : LoginSaid) -> Unit {
  c.box(style=if s.last { lc_said_last } else { lc_said }, fn() {
    if s.busy {
      @sf.spinner(c, size=lc_spin) |> ignore
    }
    c.text(s.words, style=if s.red { lc_said_red } else { lc_said_words }) |> ignore
  })
  |> ignore
}

///|
/// A step's button (StepButton): the card's width, solid while it is the next thing to do, a plain grey one once it has
/// been; a spinner while it is under way, ↗ for a page opened elsewhere; the other ways in a ⋯ beside it.
fn login_step(c : @ui.Ctx, s : LoginStep) -> Unit {
  let p = @sf.theme().p
  let id = if s.busy { 0 } else { c.id(s.key) }
  let ink = if s.solid { p.on_primary } else { p.text }
  let step = fn(style : @ui.Style) {
    c.box(style~, id~, fn() {
      if s.busy {
        @sf.spinner(c, size=lc_spin, arc=ink) |> ignore
      }
      c.text(s.label, style=if s.solid { lc_step_words_solid } else { lc_step_words }) |> ignore
      if s.external {
        @sf.icon(c, "arrow-up-right", size=lc_icon, color=ink) |> ignore
      }
    })
    |> ignore
  }
  let foot = fn(style : @ui.Style) { if s.last { style.then(lc_foot_reach) } else { style } }
  if s.more.is_empty() {
    step(foot(if s.solid { lc_step_solid } else { lc_step }).then(lc_inner_round))
  } else {
    // the other ways of doing the step, seldom used, in a ⋯ at the row's end (sf/align.mbt: what is used least
    // goes into the row's ⋯)
    c.box(style=foot(lc_step_row), fn() {
      step((if s.solid { lc_step_solid_in_row } else { lc_step_in_row }).then(lc_inner_round))
      let mid = c.id(s.key + "/more")
      let what = @sf.t("common.login.otherWays")
      let b = c.box(style=lc_more.then(lc_inner_round), id=mid, fn() { @sf.icon(c, "more", size=lc_icon, color=p.text) |> ignore })
      c.semantics(b, Button, id=mid, label=what)
      c.on_press(mid, fn() {
        @sf.menu(s.more.map(fn(i) { Some(i) }), from=Of(mid), along=End)
      })
    })
    |> ignore
  }
  if id != 0 {
    c.on_press(id, fn() {
      match s.told {
        Some(key) => c.tell(key, s.press)
        None => (s.press)()
      }
    })
  }
}

///|
/// A login under way, for one who may finish it (ActiveCard): login_shows' lines, its code, its step's button. One
/// whose page gives a code to paste back is its own (PasteSteps).
fn login_active(c : @ui.Ctx, core : Core, station : String, l : Json?, relay : Bool, place : String) -> Unit {
  if flag(l, "paste") && text(l, "url") != "" {
    login_paste(c, core, station, l, place)
    return
  }
  let shows = login_shows(core, station, l, relay)
  for s in shows.said {
    login_said(c, s)
  }
  if shows.code != "" {
    login_code(c, core, shows.code)
  }
  match shows.step {
    Some(s) => login_step(c, s)
    None => ()
  }
}

///|
/// The step in the station's own browser (`machineLogin.browser`), where the station has one: what it is called (在 … 的
/// 浏览器中打开, or 回到 … 的浏览器 while its tab is open) and what does it: its page opened in a tab there (the one open,
/// if it is), whose view opens here and goes back by itself once the login ends; a loopback's callback comes back to the
/// command there, nothing relayed or pasted.
fn login_station_way(core : Core, station : String, l : Json?) -> @sf.MenuItem? {
  if !flag(l, "browser") || text(l, "browserText") == "" {
    return None
  }
  // (a ⋯'s item chosen, outside a build: done as it is chosen, or as it is confirmed)
  Some(
    @sf.menu_item_of(text(l, "browserText"), fn() {
      @settings.confirm_claude_auth(login_station_asks(l), fn() { login_station_go(core, station, l) })
    }),
  )
}

///|
/// Whether the station's own browser is asked for a login only once confirmed: Claude's, no tab of it open yet.
fn login_station_asks(l : Json?) -> Bool {
  text(l, "name") == "claude" && text(l, "screen") == ""
}

///|
/// The login's page opened in the station's own browser (`machineLogin.browser`), its view opened here.
fn login_station_go(core : Core, station : String, l : Json?) -> Unit {
  let label = text(l, "browserText")
  @settings.act(core, label, "machineLogin.browser", { "station": Json::string(station), "id": Json::string(text(l, "id")) }, then=fn(v) {
    (core.open_screen)(station, text(Some(v), "screen"))
  })
}

///|
/// What a ⋯ beside a login page's button offers: its address copied (for a browser elsewhere), then `elsewhere`.
fn login_page_ways(url : String, elsewhere : Array[@sf.MenuItem]) -> Array[@sf.MenuItem] {
  [@sf.menu_item_of(@sf.t("common.link.copy"), fn() { @sfbase.copy_out(url, said=@sf.t("common.link.copied")) }), ..elsewhere]
}

///|
/// A login's page, opened in the browser.
fn login_open(core : Core, url : String) -> Unit {
  if url != "" && !@ui.open_tab(url) {
    (core.say)(@sf.t("android-misc.link.cantOpen"))
  }
}

///|
/// A loopback login's browser, on this device (useRelay), the app held up meanwhile: the core listens for the browser's
/// callback (not on the station's own machine: the browser comes back there by itself), then answers the page to open;
/// this device's port taken is said on the card (the core's `relayText`), nothing opened. Asked for as its step is
/// pressed (told so in an old view), as a confirm's or a ⋯'s item's is chosen.
fn login_relay_now(core : Core, station : String, id : String, title : String) -> Unit {
  let here = this_machine() == station
  // the app held up while the core waits for the browser, by a notice saying which login (LoginRelay.kt: its title;
  // where the system keeps nothing up, nothing)
  @ui.hold_words(
    channel=@sf.t("web-main.logins.title"),
    title=if title == "" { @sf.t("web-main.logins.title") } else { title },
    body=@sf.t("web-main.logins.waitingBrowser"),
  )
  (core.call)(
    "machineLogin.open",
    { "station": Json::string(station), "id": Json::string(id), "here": Json::boolean(here) },
    fn(r) {
      match r {
        Ok(v) => login_open(core, text(Some(v), "url"))
        Err(e) if text(Some(e), "code") == "port_taken" => ()
        Err(e) =>
          (core.say)(
            @sf.t("android-misc.act.failed", args=[
              ("what", @sf.t("web-main.logins.openWhat")),
              ("error", error_words(e)),
            ]),
          )
      }
    },
  )
}

///|
/// The device code, large enough to read and copy by eye (CardCode): pressed, it is copied (nothing opened), said so.
fn login_code(c : @ui.Ctx, core : Core, code : String) -> Unit {
  let id = c.id("login-code/" + code)
  c.on_press(id, fn() {
    c.copy_text(code)
    (core.say)(@sf.t("web-main.logins.codeCopied"))
  })
  c.box(style=lc_code_room, id~, label=@sf.t("web-main.logins.copyCode") + " " + code, fn() {
    c.rich([@ui.span(code, mono=true)], style=lc_code) |> ignore
  })
  |> ignore
}

///|
/// The field a login's code is pasted in, by its key (login_paste's: the place, station and login; kept across frames).
/// One a place: a card shown in its chat and on its station's page beside it is two editors, and one Field given to
/// both faulted, the chat in its place 这部分显示出错了 as it opened (2026-11-06).
fn login_field(key : String) -> @ui.Field {
  match logins_here.fields.get(key) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      logins_here.fields[key] = f
      f
    }
  }
}

///|
/// A login whose page gives a code to paste back (PasteSteps): login_paste_shows' line and step, then the field, 完成
/// at its end once a code is in (Enter too); sent, the keyboard goes, the code stays and 完成 turns while it is checked.
fn login_paste(c : @ui.Ctx, core : Core, station : String, l : Json?, place : String) -> Unit {
  let p = @sf.theme().p
  let id = text(l, "id")
  let here = place + "\u{1}" + station + "\u{1}" + id
  let field = login_field(here)
  let shows = login_paste_shows(core, station, l, field.text().trim(chars=" \n").to_owned() != "")
  let busy = shows.busy
  login_said(c, shows.lead)
  login_step(c, shows.step)
  // sent, nothing is left to type: the keyboard goes (the code stays in the field as it is checked)
  let send = fn(code : String) {
    c.blur()
    c.tell("login-answer/" + id, fn() { login_answer(core, station, id, code) })
  }
  c.box(style=lc_paste.then(lc_inner_round), fn() {
    let mut words = ""
    c.box(style=lc_paste_words, fn() {
      let r = c.editor(
        "login-paste/" + id,
        placeholder=@sf.t("web-main.logins.pasteCode"),
        font_size=lc_paste_size,
        line=lc_paste_line,
        max_lines=1,
        plain=true,
        color=p.text,
        placeholder_color=p.muted,
        caret_color=p.accent,
        enter_sends=true,
        field~,
      )
      words = r.text.trim(chars=" \n").to_owned()
      match r.submitted {
        Some(sent) if sent.trim(chars=" \n").to_owned() != "" && !busy => send(sent.trim(chars=" \n").to_owned())
        _ => ()
      }
    })
    |> ignore
    if words != "" || busy {
      let go = if busy { 0 } else { c.id("login-paste-go/" + id) }
      c.on_press(go, fn() {
        if go != 0 {
          send(words)
        }
      })
      c.box(style=lc_done.then(lc_done_round), id=go, fn() {
        // busy: a spinner over its word, as wide as before
        let w = c.text(@sf.t("web-main.logins.finish"), style=lc_done_words)
        if busy {
          c.look(w, @ui.look(alpha=0.0))
          c.layer(fn() { c.box(style=lc_done_spin, fn() { @sf.spinner(c, size=lc_spin, arc=p.on_primary) |> ignore }) |> ignore })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

// ── the card, made once ─────────────────────────────────────────────────

///|
/// Login `id` of `station` as its card (login_card's, as nodes of a page made once), all of it as the core says it now:
/// nothing for one it does not know; ended, one quiet line; else its title, its × where it may be finished here, what
/// to do now and its step (a code to paste back, its field). `marked`, `place`: login_card's. The chat's card is the
/// old view's till its page is made once.
pub fn login_card_node(
  p : @view.View,
  core : Core,
  station : String,
  id : String,
  marked? : Bool = false,
  place? : String = "chat",
) -> Unit {
  let l = fn() { login_of(core, station, id) }
  let all = fn() { logins_of(core, station) }
  // signed in while its card is in view, felt as something done; failed, as something refused (feel.mbt)
  @sfbase.felt_change_node(p, fn() { text(l(), "state") == "done" }, Confirm)
  @sfbase.felt_change_node(p, fn() { text(l(), "state") == "failed" }, Reject)
  // (0: none; 1: ended; 2: under way, finished here; 3: under way, not here)
  let stands = fn() {
    match l() {
      None => 0
      Some(_) as v if !flag(v, "active") => 1
      _ => if flag(all(), "canLogin") { 2 } else { 3 }
    }
  }
  p.pick(stands, fn(x, k) {
    match k {
      0 => ()
      1 =>
        @sf.words_node(x, fn() { login_ended(l()).0 }, fn() { if login_ended(l()).1 { lc_ended_failed } else { lc_ended } })
        |> ignore
      _ =>
        x.box(fn(room) {
          @sf.style_node(room, fn() { lc_room })
          room.box(fn(card) {
            @sf.style_node(card, fn() { if marked { lc_card_body_marked } else { lc_card_body } })
            // (what is on it as wide as it, a step's button the card's width: its own lines up at the start)
            card.lines_up(Is(None)) |> ignore
            // (as wide as what it holds, 360 at least where there is the room: within the width its place gives it)
            card.min_width(Is(Some(lc_card_least)), within=true).max_width(Is(Some(lc_card_most)), within=true) |> ignore
            let title = fn(t : @view.View) {
              t.box(fn(r) {
                @sf.style_node(r, fn() { lc_title_room }, in_row=k == 2)
                @sf.words_node(r, fn() { text(l(), "title") }, fn() { lc_title }) |> ignore
              })
              |> ignore
            }
            if k == 2 {
              card.box(fn(h) {
                @sf.style_node(h, fn() { lc_head })
                title(h)
                login_cancel_node(h, core, station, id)
              })
              |> ignore
              login_active_node(card, core, station, l, fn() { flag(all(), "canRelay") }, place)
            } else {
              title(card)
              login_said_node(card, fn() { said_line(text(l(), "statusText"), last=true) })
            }
          })
          |> ignore
        })
        |> ignore
    }
  })
}

///|
/// 取消 as the card's × (login_cancel's), spinning while it is done.
fn login_cancel_node(h : @view.View, core : Core, station : String, id : String) -> Unit {
  let busy = fn() { login_cancelling(core, station, id) }
  h.box(fn(b) {
    @sf.style_node(b, fn() { if @sf.lit_node(b) && !busy() { lc_cancel_lit } else { lc_cancel } }, in_row=true)
    @sf.presses_node(b, fn() { login_cancel_now(core, station, id) }, on=fn() { !busy() })
    b.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.logins.cancelWhat"))) })) |> ignore
    b.pick(busy, fn(m, spins) {
      if spins {
        @sf.spinner_node(m, size=lc_spin) |> ignore
      } else {
        @sf.icon_node(m, "close", lc_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// A line of how it stands (login_said's), as `s` says it now.
fn login_said_node(p : @view.View, s : () -> LoginSaid) -> Unit {
  p.box(fn(b) {
    @sf.style_node(b, fn() { if s().last { lc_said_last } else { lc_said } })
    b.show(fn() { s().busy }, fn(x) { @sf.spinner_node(x, size=lc_spin) |> ignore })
    @sf.words_node(b, fn() { s().words }, fn() { if s().red { lc_said_red } else { lc_said_words } }) |> ignore
  })
  |> ignore
}

///|
/// What a login under way shows (login_active's), as the core says it now: a code to paste back, else
/// login_shows' lines, its code and its step.
fn login_active_node(card : @view.View, core : Core, station : String, l : () -> Json?, relay : () -> Bool, place : String) -> Unit {
  card.pick(fn() { flag(l(), "paste") && text(l(), "url") != "" }, fn(x, paste) {
    // (its lines, its code and its step as far apart as the card's own: lc_card_body's)
    @sf.style_node(x, fn() { lc_active })
    if paste {
      login_paste_node(x, core, station, l, place)
      return
    }
    let shows = @signals.computed(fn(_) { login_shows(core, station, l(), relay()) })
    let shows = fn() { shows.get() }
    x.each(fn() { shows().said.mapi(fn(i, _) { i }) }, fn(i) { i }, fn(r, i) {
      let i = i.untracked()
      login_said_node(r, fn() { shows().said.get(i).unwrap_or(said_line("")) })
    })
    x.show(fn() { shows().code != "" }, fn(r) { login_code_node(r, core, fn() { shows().code }) })
    x.show(fn() { shows().step is Some(_) }, fn(r) {
      login_step_node(r, fn() { shows().step.unwrap_or(step_of("", "", false, on_press=fn() {  })) })
    })
  })
}

///|
/// The device code (login_code's), as `code` says it now: pressed, copied, said so.
fn login_code_node(p : @view.View, core : Core, code : () -> String) -> Unit {
  p.box(fn(b) {
    @sf.style_node(b, fn() { lc_code_room })
    @sf.presses_node(b, fn() {
      @sfbase.copy_out(code())
      (core.say)(@sf.t("web-main.logins.codeCopied"))
    })
    b.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.logins.copyCode") + " " + code())) })) |> ignore
    b.box(fn(w) {
      w
      .words_runs(By(fn() { [@ui.span(code(), mono=true)] }))
      .words_look(Is(@ui.style_words(lc_code)))
      .ink(By(fn() { @ui.style_ink(lc_code) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A step's button (login_step's), as `s` says it now: solid while it is the next thing to do, lit under the hand; its
/// other ways in a ⋯ beside it.
fn login_step_node(p : @view.View, s : () -> LoginStep) -> Unit {
  let foot = fn(style : @ui.Style) { if s().last { style.then(lc_foot_reach) } else { style } }
  let button = fn(at : @view.View, in_row : Bool) {
    at.box(fn(b) {
      @sf.style_node(
        b,
        fn() {
          let now = s()
          let lit = @sf.lit_node(b) && !now.busy
          let look = match (now.solid, lit) {
            (true, true) => lc_step_solid_lit
            (true, false) => lc_step_solid
            (false, true) => lc_step_lit
            (false, false) => lc_step
          }
          let step = if in_row {
            look.then(lc_in_row)
          } else {
            foot(look)
          }
          step.then(lc_inner_round)
        },
        in_row~,
      )
      @sf.presses_node(b, fn() { (s().press)() }, on=fn() { !s().busy })
      b.says(By(fn() { Some(@view.said(Button, label=s().label)) })) |> ignore
      let ink = fn() { if s().solid { @sf.theme().p.on_primary } else { @sf.theme().p.text } }
      b.show(fn() { s().busy }, fn(x) { @sf.spinner_node(x, size=lc_spin, arc=ink) |> ignore })
      @sf.words_node(b, fn() { s().label }, fn() { if s().solid { lc_step_words_solid } else { lc_step_words } }) |> ignore
      b.show(fn() { s().external }, fn(x) { @sf.icon_node(x, "arrow-up-right", lc_icon, By(ink)) |> ignore })
    })
    |> ignore
  }
  p.pick(fn() { s().more.is_empty() }, fn(x, alone) {
    if alone {
      button(x, false)
      return
    }
    // the other ways of doing the step, seldom used, in a ⋯ at the row's end
    x.box(fn(r) {
      @sf.style_node(r, fn() { foot(lc_step_row) })
      button(r, true)
      r.box(fn(m) {
        @sf.style_node(m, fn() { (if @sf.lit_node(m) { lc_more_lit } else { lc_more }).then(lc_inner_round) }, in_row=true)
        @sf.presses_node(m, fn() {
          let (wx, wy, ww, wh) = m.placed_window_now()
          @sf.menu(s().more.map(fn(i) { Some(i) }), from=At(wx, wy, ww, wh), along=End)
        })
        m.says(By(fn() { Some(@view.said(Button, label=@sf.t("common.login.otherWays"))) })) |> ignore
        @sf.icon_node(m, "more", lc_icon, By(fn() { @sf.theme().p.text })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A login whose page gives a code to paste back (login_paste's), as the core says it now: its line and its step, then
/// the field (this place's: login_field), 完成 at its end once a code is in (Enter too); sent, the keyboard goes, the
/// code stays and 完成 turns while it is checked.
fn login_paste_node(x : @view.View, core : Core, station : String, l : () -> Json?, place : String) -> Unit {
  let id = text(@signals.untracked(l), "id")
  let field = login_field(place + "\u{1}" + station + "\u{1}" + id)
  let words = fn() { field.text().trim(chars=" \n").to_owned() }
  let shows = @signals.computed(fn(_) { login_paste_shows(core, station, l(), words() != "") })
  let shows = fn() { shows.get() }
  login_said_node(x, fn() { shows().lead })
  login_step_node(x, fn() { shows().step })
  // sent, nothing is left to type: the keyboard goes (the code stays in the field as it is checked)
  let send = fn(code : String) {
    // (let go of on either side of what hosts the tree, its keyboard with it: View::focus_let_go)
    x.focus_let_go()
    login_answer(core, station, id, code)
  }
  x.box(fn(b) {
    @sf.style_node(b, fn() { lc_paste.then(lc_inner_round) })
    b.box(fn(w) {
      @sf.style_node(w, fn() { lc_paste_words }, in_row=true)
      @ui.field(
        w,
        field,
        placeholder=@sf.t("web-main.logins.pasteCode"),
        font_size=lc_paste_size,
        line=lc_paste_line,
        max_lines=1,
        enter_sends=true,
        colors_by=fn() {
          let p = @sf.theme().p
          (p.text, p.muted, p.accent)
        },
        submitted=fn(sent) {
          let code = sent.trim(chars=" \n").to_owned()
          if code != "" && !shows().busy {
            send(code)
          }
        },
      )
      |> ignore
    })
    |> ignore
    b.show(fn() { words() != "" || shows().busy }, fn(d) {
      d.box(fn(go) {
        @sf.style_node(go, fn() { (if @sf.lit_node(go) && !shows().busy { lc_done_lit } else { lc_done }).then(lc_done_round) }, in_row=true)
        @sf.presses_node(go, fn() { send(words()) }, on=fn() { !shows().busy })
        go.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.logins.finish"))) })) |> ignore
        // busy: a spinner over its word, as wide as before
        @sf.words_node(go, fn() { @sf.t("web-main.logins.finish") }, fn() { lc_done_words }).alpha(By(fn() {
          if shows().busy {
            0.0
          } else {
            1.0
          }
        }))
        |> ignore
        go.show(fn() { shows().busy }, fn(s) {
          s.over(Is(true)) |> ignore
          @sf.style_node(s, fn() { lc_done_spin })
          @sf.spinner_node(s, size=lc_spin, arc=fn() { @sf.theme().p.on_primary }) |> ignore
        })
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// The card (card): under the agent's message as a decision's options are, as wide as what it holds and at least 360
/// where there is the room (minWidth: min(100%, 360px)), 560 at most and never wider than where it is (min(100%,
/// 560px), as a vault item's card: not drawn across a wide chat's column), 8 in all round, its parts 2
/// apart, on the ink at 5%; its corner its padding and its × pill's; the accent at 10% when it is the one a link
/// pointed to.
// kept across runs: a value (no field of it changes)
let lc_card : @ui.Style = lc_card_body.then(@ui.style(min_w=@sf.login_card_least, max_w=@sf.login_card_most))

///|
/// The card but how wide it is (its node's: that by where it is, as laid out).
// kept across runs: a value (no field of it changes)
let lc_card_body : @ui.Style = @ui.style(w=Cut, p=@sf.inset_room, gap=S0_5, radius=@sf.login_card_corner, bg=A(Fg, O5), align=AStart)

///|
/// What a login under way shows in its card (login_active_node's): its lines, code and step as far apart as the card's.
// kept across runs: a value (no field of it changes)
let lc_active : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let lc_card_body_marked : @ui.Style = lc_card_body.then(@ui.css("bg=A(Accent,O10)"))

///|
/// How wide the card is at least and at most where there is the room (login_card_least's, login_card_most's).
let lc_card_least : Double = 360.0

///|
let lc_card_most : Double = 560.0

///|
/// Where it is: all of the column's width, 8 under what is above it (the card in it as wide as it says).
// kept across runs: a value (no field of it changes)
let lc_room : @ui.Style = @ui.css("w=Full pt=S2 align=AStart")

///|
/// In a panel's body (place="sheet"): full width, concentric with the panel's sides and foot.
// kept across runs: a value (no field of it changes)
let lc_room_sheet : @ui.Style = @ui.css("w=Full align=AStart")

///|
// kept across runs: a value (no field of it changes)
let lc_card_sheet : @ui.Style = lc_card_body.then(@ui.css("w=Full"))

///|
// kept across runs: a value (no field of it changes)
let lc_card_sheet_marked : @ui.Style = lc_card_body_marked.then(@ui.css("w=Full"))

///|
/// A step's card (step_card): pressed as a whole, lit under a pointer.
// kept across runs: a value (no field of it changes)
let lc_card_step : @ui.Style = lc_card.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let lc_card_marked : @ui.Style = lc_card.then(@ui.css("bg=A(Accent,O10)"))

///|
/// Ended: 12 on 18 in the subtle ink; failed, red.
// kept across runs: a value (no field of it changes)
let lc_ended : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle)

///|
// kept across runs: a value (no field of it changes)
let lc_ended_failed : @ui.TextStyle = lc_ended.then(@ui.text_style(color=Danger))

///|
/// Its title and its × (cardHead): the title takes the row, the × in the card's top corner, 4 apart.
// kept across runs: a value (no field of it changes)
let lc_head : @ui.Style = @ui.css("row w=Full gap=S1 align=AStart")

///|
/// Its title (cardTitle): 13 on 20, medium, 10 in and 10 down (a small panel's row).
// kept across runs: a value (no field of it changes)
let lc_title_room : @ui.Style = @ui.css("w=Full px=S2_5 pt=S2_5")

///|
/// Its title with no line under it (step_card's): as far from the card's foot as from its top, as a last line is.
// kept across runs: a value (no field of it changes)
let lc_title_alone : @ui.Style = lc_title_room.then(@ui.css("pb=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let lc_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L5)

///|
/// 取消 (PanelIconButton): 24, round, its ground under the pointer, in the card's top end corner as far in as makes it
/// concentric with it (capsule_in: the card's corner less its half), past the card's padding.
// kept across runs: a value (no field of it changes)
let lc_cancel : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}").then(
  @ui.style(mt=@sf.room_of(lc_cancel_off), mr=@sf.room_of(lc_cancel_off)),
)

///|
/// 取消 under the hand (its node's: lc_cancel's hovered).
// kept across runs: a value (no field of it changes)
let lc_cancel_lit : @ui.Style = lc_cancel.then(@ui.css("bg=Hover"))

///|
/// How far past the card's padding 取消 stands (lc_cancel), and its side (S6).
let lc_cancel_off : Double = @ui.capsule_in(@sf.card_corner, lc_cancel_side) - @sf.corner_inset

///|
let lc_cancel_side : Double = 24.0

///|
/// A line of how it stands (cardStatus): 12 on 18, grey, 10 in, a spinner 6 before it; last, 10 over the card's foot.
// kept across runs: a value (no field of it changes)
let lc_said : @ui.Style = @ui.css("row px=S2_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let lc_said_last : @ui.Style = lc_said.then(@ui.css("pb=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let lc_said_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let lc_said_red : @ui.TextStyle = lc_said_words.then(@ui.text_style(color=Danger))

///|
/// The device code (cardCode): 10 in, 4 over and under; its words the heading's size, semibold, in the code face.
// kept across runs: a value (no field of it changes)
let lc_code_room : @ui.Style = @ui.css("px=S2_5 py=S1")

///|
// kept across runs: a value (no field of it changes)
let lc_code : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false)

///|
/// A step's button (cardStep): the card's width, 32 high, 8 under what is above it, 12 in, its corner the card's less
/// its padding; the ink at 5% (the pointer's over it, mbui ui/hand_moves.mbt), solid (the primary's, a step towards
/// the page under the pointer) while it is the next thing to do; its words 13 medium, a spinner or ↗ 6 beside them.
// kept across runs: a value (no field of it changes)
let lc_step : @ui.Style = @ui.css(
  "row w=Full h=S8 mt=S2 px=S3 gap=S1_5 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}",
).then(@ui.style(mx=@sf.room_of(-lc_step_reach)))

///|
/// How far past the card's padding a step's button (a capsule 32 high, in the card's foot corners where it is last, a
/// pasted code's field so: lc_paste) reaches,
/// to stand concentric with them (capsule_in: 8.87 in, the card's padding 10).
let lc_step_reach : Double = @sf.corner_inset - @ui.capsule_in(@sf.card_corner, 32.0)

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid : @ui.Style = lc_step.then(@ui.css("bg=Primary hovered{bg=Over(Primary, A(Bg, O15))}"))

///|
/// A step's button under the hand (its node's: lc_step's and lc_step_solid's hovered).
// kept across runs: a value (no field of it changes)
let lc_step_lit : @ui.Style = lc_step.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid_lit : @ui.Style = lc_step_solid.then(@ui.css("bg=Over(Primary, A(Bg, O15))"))

///|
/// A step's button with its ⋯ (login_step's `more`): the row 8 under what is over it, the button the rest of it, the ⋯
/// a round one as high, 6 after it, on the step's grey.
// kept across runs: a value (no field of it changes)
let lc_step_row : @ui.Style = @ui.css("row w=Full mt=S2 gap=S1_5 align=ACenter").then(
  @ui.style(mx=@sf.room_of(-lc_step_reach)),
)

///|
/// What is last in the card reaching its foot as far as its sides (lc_step_reach).
// kept across runs: a value (no field of it changes)
let lc_foot_reach : @ui.Style = @ui.style(mb=@sf.room_of(-lc_step_reach))

///|
// kept across runs: a value (no field of it changes)
let lc_step_in_row : @ui.Style = lc_step.then(lc_in_row)

///|
/// A step's button beside its ⋯: none of its own room round it.
// kept across runs: a value (no field of it changes)
let lc_in_row : @ui.Style = @ui.css("mt=S0 mx=S0 mb=S0")

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid_in_row : @ui.Style = lc_step_solid.then(lc_in_row)

///|
// kept across runs: a value (no field of it changes)
let lc_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// The ⋯ under the hand (its node's).
// kept across runs: a value (no field of it changes)
let lc_more_lit : @ui.Style = lc_more.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let lc_step_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let lc_step_words_solid : @ui.TextStyle = lc_step_words.then(@ui.text_style(color=OnPrimary))

///|
/// The code pasted back (cardPaste): the card's width, 32 high, 6 under the step, 12 in on the left and 4 on the right,
/// on the canvas, its corner the step's; 完成 at its end (cardPasteDone): 24 high, 12 in, solid, its corner the field's
/// less 4, its words 12 medium.
// kept across runs: a value (no field of it changes)
let lc_paste : @ui.Style = @ui.css("row w=Full h=S8 mt=S1_5 pl=S3 pr=S1 gap=S1 radius=Inner bg=Bg align=ACenter").then(
  @ui.style(mx=@sf.room_of(-lc_step_reach), mb=@sf.room_of(-lc_step_reach)),
)

///|
// kept across runs: a value (no field of it changes)
let lc_paste_words : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let lc_done : @ui.Style = @ui.css(
  "row h=S6 px=S3 radius=Inner bg=Primary align=ACenter justify=JCenter hovered{bg=Over(Primary, A(Bg, O15))}",
)

///|
// kept across runs: a value (no field of it changes)
let lc_done_lit : @ui.Style = lc_done.then(@ui.css("bg=Over(Primary, A(Bg, O15))"))

///|
// kept across runs: a value (no field of it changes)
let lc_done_spin : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let lc_done_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=OnPrimary, wrap=false)

///|
/// The field's words (cardPasteInput): the ui's 13 on 20.
let lc_paste_size : Double = 13.0

///|
let lc_paste_line : Double = 20.0

///|
/// The spinner's and the icons' sizes (Spinner inline, Close 14, ArrowUpRight 14).
let lc_spin : Double = 12.0

///|
let lc_icon : Double = 14.0

///|
/// The corner of what stands in the card's corners as a step's button does (Inner, its node's: concentric with the
/// card, as far in as lc_step_reach leaves it), and 完成's in the pasted code's field (4 in from its end).
let lc_inner_corner : Double = @ui.concentric(@sf.card_corner, @ui.capsule_in(@sf.card_corner, 32.0))

///|
let lc_done_corner : Double = @ui.concentric(lc_inner_corner, 4.0)

///|
// kept across runs: a value (no field of it changes)
let lc_inner_round : @ui.Style = @ui.style(radius=@sf.radius_between(lc_inner_corner))

///|
// kept across runs: a value (no field of it changes)
let lc_done_round : @ui.Style = @ui.style(radius=@sf.radius_between(lc_done_corner))

///|
/// A step left of something under an agent's message (step_card's, as nodes), as it says it now: its title, a line
/// under it where there is one, the whole card the way to it (`go`) with a › in its corner; none to go by, the card
/// alone, taking no press.
pub fn step_card_node(
  v : @view.View,
  title : () -> String,
  line : () -> String,
  go : () -> (() -> Unit)?,
) -> Unit {
  v.box(fn(room) {
    @sf.style_node(room, fn() { lc_room })
    room.box(fn(card) {
      let goes = fn() { go() is Some(_) }
      @sf.style_node(card, fn() { if goes() && @sf.lit_node(card) { lc_card_step_lit } else { lc_card } })
      @sf.presses_node(
        card,
        fn() {
          match @signals.untracked(go) {
            Some(f) => f()
            None => ()
          }
        },
        on=goes,
      )
      card.says(By(fn() { if goes() { Some(@view.said(Button, label=title())) } else { None } })) |> ignore
      card.box(fn(h) {
        @sf.style_node(h, fn() { lc_head })
        h.box(fn(t) {
          @sf.style_node(t, fn() { if line() == "" { lc_title_alone } else { lc_title_room } }, in_row=true)
          @sf.words_node(t, title, fn() { lc_title }) |> ignore
        })
        |> ignore
        h.show(goes, fn(s) {
          s.box(fn(b) {
            @sf.style_node(b, fn() { lc_cancel }, in_row=true)
            @sf.icon_node(b, "chevron-right", lc_icon, By(fn() { @sf.theme().p.muted })) |> ignore
          })
          |> ignore
        })
      })
      |> ignore
      card.show(fn() { line() != "" }, fn(s) { login_said_node(s, fn() { said_line(line(), last=true) }) })
    })
    |> ignore
  })
  |> ignore
}

///|
/// A step's card (step_card_node) under the pointer: lit, as lc_card_step's hovered.
// kept across runs: a value (no field of it changes)
let lc_card_step_lit : @ui.Style = lc_card.then(@ui.css("bg=Hover"))
