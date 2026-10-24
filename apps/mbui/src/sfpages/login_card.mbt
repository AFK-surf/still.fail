// A station's login to a command-line tool its agents use, as a card on the desktop (ember web/src/MachineLogins.tsx
// LoginCard, ActiveCard, CancelLogin, PasteSteps, CodeField, CardCode, StepButton; MachineLogins.css.ts card…): in a
// chat under the agent's message (decision.mbt), on the station page's 登录 while it is under way (station_cards.mbt).
// Its title with 取消 as its × in the card's corner; what the person does now by its step — a device code with 复制并打开,
// a page to open, a loopback login's page once the core listens for the browser's callback, a page whose code is pasted
// back — the step's button the card's width, solid while it is the next thing to do; while its agent answers the
// command or it is checked, how it stands. Ended, one quiet line saying how. What it shows is the core's
// (`machineLogins`, `machineLogin`); what is done goes through its calls, under way on its button (the core's `doing`).

///|
/// What was pressed here, by login (a step's button plain grey once pressed: the eye on to what follows), whether a code
/// is typed in its field, and the field.
priv struct LoginsHere {
  pressed : Map[String, Bool]
  typed : Map[String, Bool]
  fields : Map[String, @ui.Field]
}

///|
let logins_here : LoginsHere = { pressed: {}, typed: {}, fields: {} }

///|
/// As at the start (tests).
pub fn login_cards_reset() -> Unit {
  logins_here.pressed.clear()
  logins_here.typed.clear()
  logins_here.fields.clear()
}

///|
/// Login `id` of `station` as its card; one the core does not know (ended long ago) draws nothing, the message's words
/// say it. `marked`: the one a link pointed to (its ground the accent, faint).
pub fn login_card(c : @ui.Ctx, core : Core, station : String, id : String, marked? : Bool = false) -> Unit {
  let l = match (core.topic)("machineLogin", { "station": Json::string(station), "id": Json::string(id) }).value {
    Some(Object(_)) as v => v
    _ => return
  }
  // ended: one quiet line, as an answered decision's (已在 studio 上登录 gh), failed in red; no card
  if !flag(l, "active") {
    let words = match text(l, "endedText") {
      "" => text(l, "title") + " · " + text(l, "statusText")
      s => s
    }
    c.text(words, style=if text(l, "state") == "failed" { lc_ended_failed } else { lc_ended }) |> ignore
    return
  }
  let all = (core.topic)("machineLogins", { "station": Json::string(station) }).value
  // 360 at least where there is the room, else as wide as where it is (minWidth: min(100%, 360px)): what it holds never
  // widens what it is in
  let room = c.id("login-room/" + station + "/" + id)
  let least = match c.laid_size(room) {
    Some((w, _)) => dmin(@sf.login_card_least, w)
    None => 0.0
  }
  c.box(style=lc_room, id=room, fn() {
    c.box(style=(if marked { lc_card_marked } else { lc_card }).then(@ui.style(min_w=Fixed(least))), fn() {
      if flag(all, "canLogin") {
        c.box(style=lc_head, fn() {
          c.box(style=lc_title_room, fn() { c.text(text(l, "title"), style=lc_title) |> ignore }) |> ignore
          login_cancel(c, core, station, id)
        })
        |> ignore
        login_active(c, core, station, l, flag(all, "canRelay"))
      } else {
        c.box(style=lc_title_room, fn() { c.text(text(l, "title"), style=lc_title) |> ignore }) |> ignore
        login_said(c, text(l, "statusText"), last=true)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// 取消, as the card's × (CancelLogin: a small panel's icon button, in its corner, concentric with it).
fn login_cancel(c : @ui.Ctx, core : Core, station : String, id : String) -> Unit {
  let busy = @settings.is_doing(core, ["machineLogin.cancel"], [("station", station), ("id", id)])
  let what = @sf.t("web-main.logins.cancelWhat")
  let x = if busy { 0 } else { c.id("login-cancel/" + station + "/" + id) }
  if x != 0 && c.clicked(x) {
    c.tell("login-cancel/" + id, fn() {
      @settings.act(core, what, "machineLogin.cancel", { "station": Json::string(station), "id": Json::string(id) })
    })
  }
  c.cursor(x, Hand)
  let b = c.box(style=lc_cancel, id=x, fn() {
    if busy {
      @sf.spinner(c, size=lc_spin) |> ignore
    } else {
      @sf.icon(c, "close", size=lc_icon, color=@sf.theme().p.muted) |> ignore
    }
  })
  c.semantics(b, Button, id=x, label=what)
}

///|
/// A line of how it stands or what to do (cardStatus: 12 on 18, grey; red what kept this device from the callback), a
/// spinner 6 before it while it waits; `last`, as far from the card's foot as the title from its top.
fn login_said(c : @ui.Ctx, words : String, red? : Bool = false, busy? : Bool = false, last? : Bool = false) -> Unit {
  c.box(style=if last { lc_said_last } else { lc_said }, fn() {
    if busy {
      @sf.spinner(c, size=lc_spin) |> ignore
    }
    c.text(words, style=if red { lc_said_red } else { lc_said_words }) |> ignore
  })
  |> ignore
}

///|
/// A step's button (StepButton): the card's width, solid while it is the next thing to do, a plain grey one once it has
/// been; a spinner while it is under way, ↗ for a page opened elsewhere. True as it is pressed.
fn login_step(c : @ui.Ctx, key : String, label : String, solid : Bool, busy? : Bool = false, external? : Bool = false) -> Bool {
  let p = @sf.theme().p
  let id = if busy { 0 } else { c.id(key) }
  let ink = if solid { p.on_primary } else { p.text }
  c.cursor(id, Hand)
  c.box(style=if solid { lc_step_solid } else { lc_step }, id~, fn() {
    if busy {
      @sf.spinner(c, size=lc_spin, arc=ink) |> ignore
    }
    c.text(label, style=if solid { lc_step_words_solid } else { lc_step_words }) |> ignore
    if external {
      @sf.icon(c, "arrow-up-right", size=lc_icon, color=ink) |> ignore
    }
  })
  |> ignore
  id != 0 && c.clicked(id)
}

///|
/// A login under way, for one who may finish it (ActiveCard): what the person does now by its step (or, while its agent
/// answers the command or it is checked, how it stands), then the step's own button. One whose page gives a code to
/// paste back is its own (PasteSteps).
fn login_active(c : @ui.Ctx, core : Core, station : String, l : Json?, relay : Bool) -> Unit {
  let id = text(l, "id")
  let url = text(l, "url")
  if flag(l, "paste") && url != "" {
    login_paste(c, core, station, l)
    return
  }
  // checking what came back (the browser's callback): nothing left for the person but to wait
  let step = if flag(l, "waiting") || text(l, "state") == "verifying" { "" } else { text(l, "step") }
  let domain = match text(l, "domain") {
    "" => ""
    d => @sf.t("web-main.logins.domain", args=[("domain", d)])
  }
  let pressed = logins_here.pressed.get(id).unwrap_or(false)
  let code = text(l, "code")
  match step {
    "device" if code != "" => {
      login_said(c, @sf.t("web-main.logins.device", args=[("domain", text(l, "domain"))]))
      login_code(c, core, code)
      // one press: the code copied first, then its page; the code stays on show for a clipboard that refused it
      if login_step(c, "login-main/" + id, @sf.t("web-main.logins.copyOpen"), !pressed) {
        logins_here.pressed[id] = true
        c.copy_text(code)
        login_open(core, match text(l, "codeUrl") {
          "" => url
          u => u
        })
      }
    }
    // a page that cannot take the browser's callback: said here, the page's host all the same
    "loopback" if !relay => {
      login_said(c, @sf.t("web-main.logins.needsDesktop"), last=domain == "")
      if domain != "" {
        login_said(c, domain, last=true)
      }
    }
    "loopback" => {
      let opened = flag(l, "listening")
      if opened {
        login_said(c, @sf.t("web-main.logins.waitingBrowser"), busy=true)
      } else if text(l, "relayText") != "" {
        login_said(c, text(l, "relayText"), red=true)
        if domain != "" {
          login_said(c, domain)
        }
      } else if domain != "" {
        login_said(c, domain)
      }
      let busy = @settings.is_doing(core, ["machineLogin.open"], [("station", station), ("id", id)])
      let label = @sf.t(if opened { "web-main.logins.openAgain" } else { "web-main.logins.signIn" })
      if login_step(c, "login-main/" + id, label, !opened, busy~) {
        login_relay(c, core, station, id, text(l, "title"))
      }
    }
    "open" if url != "" => {
      if domain != "" {
        login_said(c, domain)
      }
      if login_step(c, "login-main/" + id, @sf.t("web-main.logins.signIn"), !pressed) {
        logins_here.pressed[id] = true
        login_open(core, url)
      }
    }
    _ => login_said(c, text(l, "statusText"), busy=true, last=true)
  }
}

///|
/// A login's page, opened in the browser.
fn login_open(core : Core, url : String) -> Unit {
  if url != "" && !@ui.open_tab(url) {
    (core.say)(@sf.t("android-misc.link.cantOpen"))
  }
}

///|
/// A loopback login's browser, on this device (useRelay), the app held up meanwhile: the core listens for the browser's callback (not on the
/// station's own machine: the browser comes back there by itself), then answers the page to open; this device's port
/// taken is said on the card (the core's `relayText`), nothing opened.
fn login_relay(c : @ui.Ctx, core : Core, station : String, id : String, title : String) -> Unit {
  let here = this_machine() == station
  c.tell("login-open/" + id, fn() {
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
  })
}

///|
/// The device code, large enough to read and copy by eye (CardCode): pressed, it is copied (nothing opened), said so.
fn login_code(c : @ui.Ctx, core : Core, code : String) -> Unit {
  let id = c.id("login-code/" + code)
  if c.clicked(id) {
    c.copy_text(code)
    (core.say)(@sf.t("web-main.logins.codeCopied"))
  }
  c.cursor(id, Hand)
  c.box(style=lc_code_room, id~, label=@sf.t("web-main.logins.copyCode") + " " + code, fn() {
    c.rich([@ui.span(code, mono=true)], style=lc_code) |> ignore
  })
  |> ignore
}

///|
/// The field a login's code is pasted in, by login (kept across frames).
fn login_field(id : String) -> @ui.Field {
  match logins_here.fields.get(id) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      logins_here.fields[id] = f
      f
    }
  }
}

///|
/// A login whose page gives a code to paste back (PasteSteps): where to sign in and what to bring back, then 打开登录页
/// (solid until pressed here or a code is in) and the field, 完成 at its end once a code is in (Enter too); sent, the
/// code stays and 完成 turns while it is checked.
fn login_paste(c : @ui.Ctx, core : Core, station : String, l : Json?) -> Unit {
  let p = @sf.theme().p
  let id = text(l, "id")
  let sending = @settings.is_doing(core, ["machineLogin.answer"], [("station", station), ("id", id)])
  let checking = text(l, "state") == "verifying"
  let busy = sending || checking
  let opened = logins_here.pressed.get(id).unwrap_or(false)
  let typed = logins_here.typed.get(id).unwrap_or(false)
  login_said(c, if checking {
    text(l, "statusText")
  } else {
    match text(l, "domain") {
      "" => text(l, "statusText")
      d => @sf.t("web-main.logins.pasteLead", args=[("domain", d)])
    }
  })
  if login_step(c, "login-paste-open/" + id, @sf.t("web-main.logins.openPage"), !opened && !typed && !busy, external=true) {
    logins_here.pressed[id] = true
    login_open(core, text(l, "url"))
  }
  let send = fn(code : String) {
    c.tell("login-answer/" + id, fn() {
      @settings.act(core, @sf.t("web-main.logins.answerWhat"), "machineLogin.answer", {
        "station": Json::string(station),
        "id": Json::string(id),
        "text": Json::string(code),
      })
    })
  }
  c.box(style=lc_paste, fn() {
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
        field=login_field(id),
      )
      words = r.text.trim(chars=" \n").to_string()
      logins_here.typed[id] = words != ""
      match r.submitted {
        Some(sent) if sent.trim(chars=" \n").to_string() != "" && !busy => send(sent.trim(chars=" \n").to_string())
        _ => ()
      }
    })
    |> ignore
    if words != "" || busy {
      let go = if busy { 0 } else { c.id("login-paste-go/" + id) }
      if go != 0 && c.clicked(go) {
        send(words)
      }
      c.cursor(go, Hand)
      c.box(style=lc_done, id=go, fn() {
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

///|
/// The card (card): under the agent's message as a decision's options are, as wide as what it holds and at least 360
/// where there is the room (login_card: no wider than where it is), 8 in all round, its parts 2 apart, on the ink at 5%; its corner its
/// padding and its × pill's; the accent at 10% when it is the one a link pointed to.
// kept across runs: a value (no field of it changes)
let lc_card : @ui.Style = @ui.style(
  max_w=Full,
  p=@sf.inset_room,
  gap=S0_5,
  radius=@sf.login_card_corner,
  bg=A(Fg, O5),
  align=AStart,
)

///|
/// Where it is: all of the column's width, 8 under what is above it (the card in it as wide as it says).
// kept across runs: a value (no field of it changes)
let lc_room : @ui.Style = @ui.css("w=Full pt=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let lc_card_marked : @ui.Style = lc_card.then(@ui.css("bg=A(Accent,O10)"))

///|
/// Ended (ended: Decisions.css.ts settledLine): 12 on 18 in the subtle ink; failed, red.
// kept across runs: a value (no field of it changes)
let lc_ended : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle)

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
// kept across runs: a value (no field of it changes)
let lc_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L5)

///|
/// 取消 (PanelIconButton): 24, round, its ground under the pointer.
// kept across runs: a value (no field of it changes)
let lc_cancel : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// A line of how it stands (cardStatus): 12 on 18, grey, 10 in, a spinner 6 before it; last, 10 over the card's foot.
// kept across runs: a value (no field of it changes)
let lc_said : @ui.Style = @ui.css("row px=S2_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let lc_said_last : @ui.Style = lc_said.then(@ui.css("pb=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let lc_said_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let lc_said_red : @ui.TextStyle = lc_said_words.then(@ui.text_style(color=Danger))

///|
/// The device code (cardCode): 10 in, 4 over and under; its words the heading's size, semibold, in the code face.
// kept across runs: a value (no field of it changes)
let lc_code_room : @ui.Style = @ui.css("px=S2_5 py=S1")

///|
// kept across runs: a value (no field of it changes)
let lc_code : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, wrap=false)

///|
/// A step's button (cardStep): the card's width, 32 high, 8 under what is above it, 12 in, its corner the card's less
/// its padding; the ink at 5% (10% under the pointer), solid (the primary's) while it is the next thing to do; its words
/// 13 medium, a spinner or ↗ 6 beside them.
// kept across runs: a value (no field of it changes)
let lc_step : @ui.Style = @ui.css(
  "row w=Full h=S8 mt=S2 px=S3 gap=S1_5 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=A(Fg,O10)}",
)

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid : @ui.Style = lc_step.then(@ui.css("bg=Primary hovered{bg=A(Primary,O80)}"))

///|
// kept across runs: a value (no field of it changes)
let lc_step_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let lc_step_words_solid : @ui.TextStyle = lc_step_words.then(@ui.text_style(color=OnPrimary))

///|
/// The code pasted back (cardPaste): the card's width, 32 high, 6 under the step, 12 in on the left and 4 on the right,
/// on the canvas, its corner the step's; 完成 at its end (cardPasteDone): 24 high, 12 in, solid, its corner the field's
/// less 4, its words 12 medium.
// kept across runs: a value (no field of it changes)
let lc_paste : @ui.Style = @ui.css("row w=Full h=S8 mt=S1_5 pl=S3 pr=S1 gap=S1 radius=Inner bg=Bg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let lc_paste_words : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let lc_done : @ui.Style = @ui.css("row h=S6 px=S3 radius=Inner bg=Primary align=ACenter justify=JCenter hovered{bg=A(Primary,O80)}")

///|
// kept across runs: a value (no field of it changes)
let lc_done_spin : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let lc_done_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=OnPrimary, wrap=false)

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
