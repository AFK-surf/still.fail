// Logging a station in to the command-line tools its agents use (docs/remote-login.md), as a card (ember apps/android
// shared/screens/LoginCards.kt LoginCard): in a chat under the agent's message, on 奏, on the station page while it is
// under way (settings' StationLogins, through Core's login_card). Its title with 取消 as its × in the card's corner;
// what the person does now by its step — a device code shown large with 复制并打开, a page to open, a loopback login's
// page once the core listens for its callback, a page whose code is pasted back (PasteSteps) — each step's button the
// card's width, solid while it is the next thing to do; while its agent answers the command or it is being checked, how
// it stands. Ended, one line saying how. What it shows is the core's (`machineLogins`, `machineLogin`); what is done goes
// through its calls (`machineLogin.open`, `.answer`, `.cancel`), under way on its button.

///|
/// The steps pressed here, by login (a plain grey button once pressed: the eye on to what follows), and whether a code
/// is typed in its field.
priv struct LoginPressed {
  pressed : Map[String, Bool]
  typed : Map[String, Bool]
  fields : Map[String, @ui.Field]
}

///|
let login_pressed : LoginPressed = { pressed: {}, typed: {}, fields: {} }

///|
/// As at the start (tests).
fn login_cards_reset() -> Unit {
  login_pressed.pressed.clear()
  login_pressed.typed.clear()
  login_pressed.fields.clear()
}

///|
/// Ended: one quiet line (13 on 19), failed in red, 2 under what is above it.
// kept across runs: a value (no field of it changes)
let login_ended_room : @ui.Style = @ui.style(pt=SPx)


///|
/// The card: 6 under what is above it, as wide as what it holds and at least 280 (LoginCard's widthIn: its step buttons
/// fill that), 8 in all round, its parts 2 apart, on the chip's grey (the accent at 12% when it is the one a link
/// pointed to), its corner a pill's half and its padding (22).
// kept across runs: a value (no field of it changes)
let login_card_room : @ui.Style = @ui.style(w=Full, pt=S1_5, align=AStart)

///|
/// The card's least width (LoginCard: widthIn(min = 280.dp)).
// kept across runs: a value (no field of it changes)
let login_card_min_w : @ui.Len = Fixed(280.0)

///|
// kept across runs: a value (no field of it changes)
let login_card_box : @ui.Style = @ui.style(min_w=login_card_min_w, p=S2, gap=S0_5, radius=Xl3, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let login_card_marked : @ui.Style = login_card_box.then(@ui.style(bg=A(Accent, O10)))

///|
/// Its title and its × in a row, the × in the card's top corner.
// kept across runs: a value (no field of it changes)
let login_head : @ui.Style = @ui.style(row=true, w=Full, align=AStart)

///|
/// Its title (15 on 21, medium, the ink), 10 in from the card's padding and 10 down: as wide as its words (a card
/// hugging what it holds measures them so).
// kept across runs: a value (no field of it changes)
let login_title_room : @ui.Style = @ui.style(px=S2_5, pt=S2_5)

///|
// kept across runs: a value (no field of it changes)
let login_title_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Medium, color=Fg)

///|
/// 取消 as the card's ×: a pill's size (28), round, pressed the ink at 5% under it.
// kept across runs: a value (no field of it changes)
let login_cancel : @ui.Style = @ui.style(
  w=S7,
  h=S7,
  radius=Full,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=A(Fg, O5)),
)

///|
/// A line of how it stands or what to do (13 on 19, grey; red what is off), 10 in, a spinner 6 before it.
// kept across runs: a value (no field of it changes)
let login_said : @ui.Style = @ui.style(row=true, px=S2_5, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let login_said_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L4_75)

///|
// kept across runs: a value (no field of it changes)
let login_said_red : @ui.TextStyle = login_said_words.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let login_said_under : @ui.Style = login_said.then(@ui.style(pb=S2_5))

///|
/// The device code (22 on 29, semibold, the code face's), 10 in, 4 over and under; pressed, copied.
// kept across runs: a value (no field of it changes)
let login_code_room : @ui.Style = @ui.style(px=S2_5, py=S1)

///|
// kept across runs: a value (no field of it changes)
let login_code_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// A step's button (StepButton): the card's width, 8 under what is above it, a thumb's height (44), its corner the
/// card's less its padding; solid (the ink, its words the paper's) while it is the next thing to do, else the ink at
/// 5%; its words 15 semibold, a spinner or ↗ 6 beside them.
// kept across runs: a value (no field of it changes)
let login_step_room : @ui.Style = @ui.style(w=Full, pt=S2)

///|
// kept across runs: a value (no field of it changes)
let login_step : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=S11,
  gap=S1_5,
  radius=Inner,
  bg=A(Fg, O5),
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=A(Fg, O10)),
)

///|
// kept across runs: a value (no field of it changes)
let login_step_solid : @ui.Style = login_step.then(@ui.style(bg=Fg, pressed=@ui.patch(bg=Over(Fg, A(Bg, O15)))))

///|
// kept across runs: a value (no field of it changes)
let login_step_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let login_step_words_solid : @ui.TextStyle = login_step_words.then(@ui.text_style(color=Bg))

///|
/// The code pasted back (CodeField): the card's width, 6 under the step above, 44 high, on the surface, 14 in on the
/// left and 6 on the right; 完成 at its end once a code is in, 32 high, solid, its corner the field's less 6.
// kept across runs: a value (no field of it changes)
let login_field_room : @ui.Style = @ui.style(w=Full, pt=S1_5)

///|
// kept across runs: a value (no field of it changes)
let login_field : @ui.Style = @ui.style(row=true, w=Full, h=S11, pl=S3_5, pr=S1_5, gap=S1_5, radius=Inner, bg=Surface, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let login_field_words : @ui.Style = @ui.style(w=Full)

///|
// kept across runs: a value (no field of it changes)
let login_finish : @ui.Style = @ui.style(
  row=true,
  h=S8,
  px=S3_5,
  radius=Inner,
  bg=Fg,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=Over(Fg, A(Bg, O15))),
)

///|
// kept across runs: a value (no field of it changes)
let login_finish_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Bg, wrap=false)

///|
/// A login as its card shows it; a login the core does not know draws nothing. `marked`: the one a link pointed to.
fn login_card(c : @ui.Ctx, src : Source, station : String, id : String, marked? : Bool = false) -> Unit {
  let topic = (src.topic)("machineLogin", { "station": Json::string(station), "id": Json::string(id) })
  let l = match topic.value {
    Some(Object(_)) as v => v
    _ => return
  }
  // ended: one quiet line, as an answered decision's (已在 studio 上登录 gh), failed in red; no card
  if !flag(l, "active") {
    let words = match text(l, "endedText") {
      "" => text(l, "title") + " · " + text(l, "statusText")
      s => s
    }
    c.box(style=login_ended_room, fn() { login_ended_line(c, words, text(l, "state") == "failed") }) |> ignore
    return
  }
  let all = (src.topic)("machineLogins", { "station": Json::string(station) })
  c.box(style=login_card_room, fn() {
    c.box(style=if marked { login_card_marked } else { login_card_box }, fn() {
      if flag(all.value, "canLogin") {
        c.box(style=login_head, fn() {
          c.box(style=login_title_room, fn() { c.text(text(l, "title"), style=login_title_words) |> ignore }) |> ignore
          // (the title as wide as its words, the card as wide as they and its least: the × at its corner)
          c.spacer()
          login_cancel_button(c, src, station, id)
        })
        |> ignore
        login_active(c, src, station, l, flag(all.value, "canRelay"))
      } else {
        c.box(style=login_title_room, fn() { c.text(text(l, "title"), style=login_title_words) |> ignore }) |> ignore
        login_said_line(c, text(l, "statusText"), under=true)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// 取消, as the card's ×.
fn login_cancel_button(c : @ui.Ctx, src : Source, station : String, id : String) -> Unit {
  let t = @sf.theme()
  let key = "login-cancel/" + station + "/" + id
  let busy = doing(key)
  let cancel = if busy { 0 } else { c.id("login-cancel/" + id) }
  if cancel != 0 && c.clicked(cancel) {
    act(src, tr("web-main.logins.cancelWhat"), key, "machineLogin.cancel", {
      "station": Json::string(station),
      "id": Json::string(id),
    })
  }
  c.box(style=login_cancel, id=cancel, fn() {
    if busy {
      @sf.spinner(c, size=12.0) |> ignore
    } else {
      @sf.icon(c, "close", size=14.0, color=t.p.muted) |> ignore
    }
  })
  |> ignore
}

///|
/// A line of how it stands or what to do (Said).
fn login_said_line(c : @ui.Ctx, words : String, red? : Bool = false, busy? : Bool = false, under? : Bool = false) -> Unit {
  c.box(style=if under { login_said_under } else { login_said }, fn() {
    if busy {
      @sf.spinner(c, size=12.0) |> ignore
    }
    c.text(words, style=if red { login_said_red } else { login_said_words }) |> ignore
  })
  |> ignore
}

///|
/// A step's button (StepButton): true on the frame after it was pressed.
fn login_step_button(c : @ui.Ctx, key : String, label : String, solid : Bool, busy? : Bool = false, external? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = if busy { 0 } else { c.id(key) }
  let ink = if solid { t.p.bg } else { t.p.text }
  c.box(style=login_step_room, fn() {
    c.box(style=if solid { login_step_solid } else { login_step }, id~, fn() {
      if busy {
        @sf.spinner(c, size=12.0, arc=ink) |> ignore
      }
      c.text(label, style=if solid { login_step_words_solid } else { login_step_words }) |> ignore
      if external {
        @sf.icon(c, "arrow-up-right", size=16.0, color=ink) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  id != 0 && c.clicked(id)
}

///|
/// A login under way, for one who may finish it (ActiveCard): what the person does now by its step, then the step's
/// own button. One whose page gives a code to paste back is its own (PasteSteps).
fn login_active(c : @ui.Ctx, src : Source, station : String, l : Json?, relay : Bool) -> Unit {
  let id = text(l, "id")
  let url = text(l, "url")
  if flag(l, "paste") && url != "" {
    login_paste_steps(c, src, station, l)
    return
  }
  // checking what came back (the browser's callback): nothing left for the person but to wait
  let step = if flag(l, "waiting") || text(l, "state") == "verifying" { "" } else { text(l, "step") }
  let open_key = "login-open/" + station + "/" + id
  let opening = doing(open_key)
  let domain = match text(l, "domain") {
    "" => ""
    d => fill("web-main.logins.domain", [("domain", d)])
  }
  // its one button solid while it is the thing to do, a plain grey one once pressed here
  let pressed = login_pressed.pressed.get(id).unwrap_or(false)
  let code = text(l, "code")
  match step {
    "device" if code != "" => {
      login_said_line(c, fill("web-main.logins.device", [("domain", text(l, "domain"))]))
      login_code(c, code)
      // one press: the code copied first, then its page; the code stays on show for a clipboard that refused it
      if login_step_button(c, "login-main/" + id, tr("web-main.logins.copyOpen"), !pressed) {
        login_pressed.pressed[id] = true
        c.copy_text(code)
        login_open_page(c, match text(l, "codeUrl") {
          "" => url
          u => u
        })
      }
    }
    "loopback" if !relay => {
      login_said_line(c, tr("web-main.logins.needsDesktop"))
      if domain != "" {
        login_said_line(c, domain)
      }
    }
    "loopback" => {
      let listening = flag(l, "listening")
      if listening {
        login_said_line(c, tr("web-main.logins.waitingBrowser"), busy=true)
      } else if text(l, "relayText") != "" {
        login_said_line(c, text(l, "relayText"), red=true)
        if domain != "" {
          login_said_line(c, domain)
        }
      } else if domain != "" {
        login_said_line(c, domain)
      }
      if login_step_button(
          c,
          "login-main/" + id,
          tr(if listening { "web-main.logins.openAgain" } else { "web-main.logins.signIn" }),
          !listening,
          busy=opening,
        ) {
        login_relay(src, station, l, open_key)
      }
    }
    "open" if url != "" => {
      if domain != "" {
        login_said_line(c, domain)
      }
      if login_step_button(c, "login-main/" + id, tr("web-main.logins.signIn"), !pressed) {
        login_pressed.pressed[id] = true
        login_open_page(c, url)
      }
    }
    _ => login_said_line(c, text(l, "statusText"), busy=true)
  }
}

///|
/// A page of the login's opened in a browser's tab over the app (LoginPages.open: a Custom Tab).
fn login_open_page(c : @ui.Ctx, url : String) -> Unit {
  if url != "" && !@ui.open_tab(url) {
    say(c, tr("android-misc.link.cantOpen"))
  }
}

///|
/// The device code, large enough to read and copy by eye (CardCode); pressed, it is copied (nothing opened), said so.
fn login_code(c : @ui.Ctx, code : String) -> Unit {
  let id = c.id("login-code/" + code)
  if c.clicked(id) {
    c.copy_text(code)
    say(c, tr("web-main.logins.codeCopied"))
  }
  c.box(style=login_code_room, id~, fn() {
    c.rich([@ui.span(code, mono=true)], style=login_code_words) |> ignore
  })
  |> ignore
}

///|
/// A loopback login's browser, on this device (relay): the core listens for the browser's callback first, the app held
/// up while it does by a notice saying which login it waits for (LoginRelay.kt: its title), then the page opens; this
/// device's port taken is said on the card (`relayText`), nothing opened.
fn login_relay(src : Source, station : String, l : Json?, open_key : String) -> Unit {
  @ui.hold_words(
    channel=tr("web-main.logins.title"),
    title=match text(l, "title") {
      "" => tr("web-main.logins.title")
      s => s
    },
    body=tr("web-main.logins.waitingBrowser"),
  )
  act(
    src,
    tr("web-main.logins.openWhat"),
    open_key,
    "machineLogin.open",
    { "station": Json::string(station), "id": Json::string(text(l, "id")), "here": Json::boolean(false) },
    ok=fn(v) {
      let u = text(Some(v), "url")
      if u != "" && !@ui.open_tab(u) {
        toast_later(tr("android-misc.link.cantOpen"))
      }
    },
  )
}

///|
/// The field a login's code is typed in, by login (kept across frames).
fn login_field_of(id : String) -> @ui.Field {
  match login_pressed.fields.get(id) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      login_pressed.fields[id] = f
      f
    }
  }
}

///|
/// A login whose page gives a code to paste back (PasteSteps): where to sign in and what to bring back, then 打开登录页
/// (solid until pressed here or a code is in) and the field, 完成 at its end once a code is in; sent, the code stays
/// and 完成 turns while it is checked (正在确认登录).
fn login_paste_steps(c : @ui.Ctx, src : Source, station : String, l : Json?) -> Unit {
  let t = @sf.theme()
  let id = text(l, "id")
  let answer_key = "login-answer/" + station + "/" + id
  let sending = doing(answer_key)
  let checking = text(l, "state") == "verifying"
  let busy = sending || checking
  let opened = login_pressed.pressed.get(id).unwrap_or(false)
  let typed = login_pressed.typed.get(id).unwrap_or(false)
  login_said_line(c, if checking {
    text(l, "statusText")
  } else {
    match text(l, "domain") {
      "" => text(l, "statusText")
      d => fill("web-main.logins.pasteLead", [("domain", d)])
    }
  })
  if login_step_button(c, "login-paste-open/" + id, tr("web-main.logins.openPage"), !opened && !typed && !busy, external=true) {
    login_pressed.pressed[id] = true
    login_open_page(c, text(l, "url"))
  }
  let field = login_field_of(id)
  c.box(style=login_field_room, fn() {
    c.box(style=login_field, fn() {
      let mut words = ""
      c.box(style=login_field_words, fn() {
        let r = c.editor(
          "login-paste/" + id,
          placeholder=tr("web-main.logins.pasteCode"),
          font_size=15.0,
          line=21.0,
          max_lines=1,
          plain=true,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          enter_sends=true,
          field~,
        )
        words = r.text.trim(chars=" \n").to_string()
        login_pressed.typed[id] = words != ""
        // the keyboard's Done too
        match r.submitted {
          Some(sent) if sent.trim(chars=" \n").to_string() != "" && !busy =>
            login_answer(src, station, id, sent.trim(chars=" \n").to_string(), answer_key)
          _ => ()
        }
      })
      |> ignore
      if words != "" || busy {
        let go = if busy { 0 } else { c.id("login-paste-go/" + id) }
        if go != 0 && c.clicked(go) {
          login_answer(src, station, id, words, answer_key)
        }
        c.box(style=login_finish, id=go, fn() {
          if busy {
            @sf.spinner(c, size=12.0, arc=t.p.bg) |> ignore
          } else {
            c.text(tr("web-main.logins.finish"), style=login_finish_words) |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The code sent (`machineLogin.answer`).
fn login_answer(src : Source, station : String, id : String, words : String, key : String) -> Unit {
  act(src, tr("web-main.logins.answerWhat"), key, "machineLogin.answer", {
    "station": Json::string(station),
    "id": Json::string(id),
    "text": Json::string(words),
  })
}
