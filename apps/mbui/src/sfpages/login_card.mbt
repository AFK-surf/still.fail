// A station's login to a command-line tool its agents use, as a card, the one on every screen (ember
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
/// What was pressed here, by login (a step's button plain grey once pressed: the eye on to what follows), whether a code
/// is typed in its field, and the field.
priv struct LoginsHere {
  pressed : Map[String, Bool]
  typed : Map[String, Bool]
  fields : Map[String, @ui.Field]
  /// how many times what was pressed or typed changed: what draws it (an old view in a tree, built again only as what
  /// it reads changes) follows
  said : @signals.Signal[Int]
}

///|
let logins_here : LoginsHere = { pressed: {}, typed: {}, fields: {}, said: @signals.signal(0) }

///|
/// What was pressed or typed here changed: told what draws it.
fn logins_said() -> Unit {
  logins_here.said.set(@signals.untracked(fn() { logins_here.said.get() }) + 1)
}

///|
/// As at the start (tests).
pub fn login_cards_reset() -> Unit {
  logins_here.pressed.clear()
  logins_here.typed.clear()
  logins_here.fields.clear()
  st_logins_open.clear()
}

///|
/// Login `id` of `station` as its card; one the core does not know (ended long ago) draws nothing, the message's words
/// say it. `marked`: the one a link pointed to (its ground the accent, faint).
pub fn login_card(c : @ui.Ctx, core : Core, station : String, id : String, marked? : Bool = false) -> Unit {
  logins_here.said.get() |> ignore
  let l = match (core.topic)("machineLogin", { "station": Json::string(station), "id": Json::string(id) }).value {
    Some(Object(_)) as v => v
    _ => return
  }
  // signed in while its card is in view, felt as something done; failed, as something refused (feel.mbt)
  @sfbase.felt_change(c, "login-done/" + station + "/" + id, text(l, "state") == "done", Confirm)
  @sfbase.felt_change(c, "login-failed/" + station + "/" + id, text(l, "state") == "failed", Reject)
  // ended: one quiet line, as an answered decision's (已在 willow 上登录 gh), failed in red; no card
  if !flag(l, "active") {
    let words = match text(l, "endedText") {
      "" => text(l, "title") + " · " + text(l, "statusText")
      s => s
    }
    c.text(words, style=if text(l, "state") == "failed" { lc_ended_failed } else { lc_ended }) |> ignore
    return
  }
  let all = (core.topic)("machineLogins", { "station": Json::string(station) }).value
  c.box(style=lc_room, fn() {
    c.box(style=if marked { lc_card_marked } else { lc_card }, fn() {
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
/// A step left of something under an agent's message, as a login's card looks (its ground, its title, a line under it),
/// the whole card the way to it (`go`), a › in its corner where a login's × is: an approved phone's pairing with its
/// station (decision.mbt phone_ask_card). Quiet as the cards beside it are, no button of its own (2026-10-30, user: a
/// card with a solid button was 「明显有点过大了，而且好像不是很搭风格」).
pub fn step_card(c : @ui.Ctx, key : String, title : String, line : String, go : () -> Unit) -> Unit {
  let x = c.id(key)
  if c.clicked(x) {
    go()
  }
  c.box(style=lc_room, fn() {
    let b = c.box(style=lc_card_step, id=x, fn() {
      c.box(style=lc_head, fn() {
        c.box(style=lc_title_room, fn() { c.text(title, style=lc_title) |> ignore }) |> ignore
        c.box(style=lc_cancel, fn() { @sf.icon(c, "chevron-right", size=lc_icon, color=@sf.theme().p.muted) |> ignore }) |> ignore
      })
      |> ignore
      login_said(c, line, last=true)
    })
    c.semantics(b, Button, id=x, label=title)
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
fn login_step(
  c : @ui.Ctx,
  key : String,
  label : String,
  solid : Bool,
  busy? : Bool = false,
  external? : Bool = false,
  more? : Array[(String, () -> Unit)] = [],
  last? : Bool = true,
) -> Bool {
  let p = @sf.theme().p
  let id = if busy { 0 } else { c.id(key) }
  let ink = if solid { p.on_primary } else { p.text }
  let step = fn(style : @ui.Style) {
    c.box(style~, id~, fn() {
      if busy {
        @sf.spinner(c, size=lc_spin, arc=ink) |> ignore
      }
      c.text(label, style=if solid { lc_step_words_solid } else { lc_step_words }) |> ignore
      if external {
        @sf.icon(c, "arrow-up-right", size=lc_icon, color=ink) |> ignore
      }
    })
    |> ignore
  }
  let foot = fn(style : @ui.Style) { if last { style.then(lc_foot_reach) } else { style } }
  if more.is_empty() {
    step(foot(if solid { lc_step_solid } else { lc_step }))
  } else {
    // the other ways of doing the step, seldom used, in a ⋯ at the row's end (docs/ui-panels.md: what is used least
    // goes into the row's ⋯)
    c.box(style=foot(lc_step_row), fn() {
      step(if solid { lc_step_solid_in_row } else { lc_step_in_row })
      let mid = c.id(key + "/more")
      let what = @sf.t("common.login.otherWays")
      let b = c.box(style=lc_more, id=mid, fn() { @sf.icon(c, "more", size=lc_icon, color=p.text) |> ignore })
      c.semantics(b, Button, id=mid, label=what)
      if c.clicked(mid) {
        @sf.menu(more.map(fn(w) { Some(@sf.menu_item_of(w.0, w.1)) }), from=Of(mid), along=End)
      }
    })
    |> ignore
  }
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
  // the same step in the station's own browser, for the ⋯ beside the step's button
  let elsewhere = match login_station_way(core, station, l) {
    Some(way) => [way]
    None => []
  }
  match step {
    "device" if code != "" => {
      login_said(c, @sf.t("web-main.logins.device", args=[("domain", text(l, "domain"))]))
      login_code(c, core, code)
      // one press: the code copied first, then its page; the code stays on show for a clipboard that refused it
      if login_step(c, "login-main/" + id, @sf.t("web-main.logins.copyOpen"), !pressed, more=elsewhere) {
        @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
          logins_here.pressed[id] = true
          logins_said()
          @ui.current().copy_text(code)
          login_open(core, match text(l, "codeUrl") {
            "" => url
            u => u
          })
        })
      }
    }
    // this device cannot take the browser's callback (a web page), or its port was taken just now: the station's
    // browser, which can, is the step (this device's again in its ⋯), else what is wrong is said; the page's host all
    // the same
    "loopback" if elsewhere.length() > 0 && (!relay || text(l, "relayText") != "") => {
      if text(l, "relayText") != "" && relay {
        login_said(c, text(l, "relayText"), red=true)
      }
      if domain != "" {
        login_said(c, domain)
      }
      let busy = @settings.is_doing(core, ["machineLogin.browser"], [("station", station), ("id", id)])
      let again = if relay {
        [(@sf.t("web-main.logins.signIn"), fn() {
          @settings.confirm_claude_auth(text(l, "name") == "claude", fn() { login_relay(@ui.current(), core, station, id, text(l, "title")) })
        })]
      } else {
        []
      }
      if login_step(c, "login-station/" + id, text(l, "browserText"), true, busy~, more=again) {
        (elsewhere[0].1)()
      }
    }
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
      if login_step(c, "login-main/" + id, label, !opened, busy~, more=elsewhere) {
        @settings.confirm_claude_auth(text(l, "name") == "claude", fn() { login_relay(@ui.current(), core, station, id, text(l, "title")) })
      }
    }
    "open" if url != "" => {
      if domain != "" {
        login_said(c, domain)
      }
      if login_step(c, "login-main/" + id, @sf.t("web-main.logins.signIn"), !pressed, more=elsewhere) {
        @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
          logins_here.pressed[id] = true
          logins_said()
          login_open(core, url)
        })
      }
    }
    _ => login_said(c, text(l, "statusText"), busy=true, last=true)
  }
}

///|
/// The step in the station's own browser (`machineLogin.browser`), where the station has one: what it is called (在 … 的
/// 浏览器中打开, or 回到 … 的浏览器 while its tab is open) and what does it: its page opened in a tab there (the one open,
/// if it is), whose view opens here and goes back by itself once the login ends; a loopback's callback comes back to the
/// command there, nothing relayed or pasted.
fn login_station_way(core : Core, station : String, l : Json?) -> (String, () -> Unit)? {
  if !flag(l, "browser") || text(l, "browserText") == "" {
    return None
  }
  let id = text(l, "id")
  let label = text(l, "browserText")
  Some(
    (
      label,
      fn() {
        @settings.confirm_claude_auth(text(l, "name") == "claude" && text(l, "screen") == "", fn() {
          @ui.current().tell("login-station/" + id, fn() {
            @settings.act(core, label, "machineLogin.browser", { "station": Json::string(station), "id": Json::string(id) }, then=fn(v) {
              (core.open_screen)(station, text(Some(v), "screen"))
            })
          })
        })
      },
    ),
  )
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
/// keyboard goes, the code stays and 完成 turns while it is checked.
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
  let elsewhere = match login_station_way(core, station, l) {
    Some(way) => [way]
    None => []
  }
  if login_step(c, "login-paste-open/" + id, @sf.t("web-main.logins.openPage"), !opened && !typed && !busy, external=true, more=elsewhere, last=false) {
    @settings.confirm_claude_auth(text(l, "name") == "claude", fn() {
      logins_here.pressed[id] = true
      logins_said()
      login_open(core, text(l, "url"))
    })
  }
  // sent, nothing is left to type: the keyboard goes (the code stays in the field as it is checked)
  let send = fn(code : String) {
    c.blur()
    c.tell("login-answer/" + id, fn() {
      // (sent, nothing is left to type: the keyboard goes, the code staying in the field as it is checked)
    @ui.current().blur()
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
      logins_said()
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
/// where there is the room (minWidth: min(100%, 360px)), 560 at most and never wider than where it is (min(100%,
/// 560px), as a vault item's card: not drawn across a wide chat's column), 8 in all round, its parts 2
/// apart, on the ink at 5%; its corner its padding and its × pill's; the accent at 10% when it is the one a link
/// pointed to.
// kept across runs: a value (no field of it changes)
let lc_card : @ui.Style = @ui.style(
  w=Cut,
  min_w=@sf.login_card_least,
  max_w=@sf.login_card_most,
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
/// A step's card (step_card): pressed as a whole, lit under a pointer.
// kept across runs: a value (no field of it changes)
let lc_card_step : @ui.Style = lc_card.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let lc_card_marked : @ui.Style = lc_card.then(@ui.css("bg=A(Accent,O10)"))

///|
/// Ended (ended: Decisions.css.ts settledLine): 12 on 18 in the subtle ink; failed, red.
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
/// How far past the card's padding 取消 stands (lc_cancel), and its side (S6).
let lc_cancel_off : Double = @sf.capsule_in(@sf.card_corner, lc_cancel_side) - @sf.corner_inset

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
/// its padding; the ink at 5% (the pointer's over it, docs/ui-panels.md 悬停), solid (the primary's, a step towards
/// the page under the pointer) while it is the next thing to do; its words 13 medium, a spinner or ↗ 6 beside them.
// kept across runs: a value (no field of it changes)
let lc_step : @ui.Style = @ui.css(
  "row w=Full h=S8 mt=S2 px=S3 gap=S1_5 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}",
).then(@ui.style(mx=@sf.room_of(-lc_step_reach)))

///|
/// How far past the card's padding a step's button (a capsule 32 high, in the card's foot corners where it is last, a
/// pasted code's field so: lc_paste) reaches,
/// to stand concentric with them (capsule_in: 8.87 in, the card's padding 10).
let lc_step_reach : Double = @sf.corner_inset - @sf.capsule_in(@sf.card_corner, 32.0)

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid : @ui.Style = lc_step.then(@ui.css("bg=Primary hovered{bg=Over(Primary, A(Bg, O15))}"))

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
let lc_step_in_row : @ui.Style = lc_step.then(@ui.css("mt=S0 mx=S0 mb=S0"))

///|
// kept across runs: a value (no field of it changes)
let lc_step_solid_in_row : @ui.Style = lc_step_solid.then(@ui.css("mt=S0 mx=S0 mb=S0"))

///|
// kept across runs: a value (no field of it changes)
let lc_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}")

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
/// Login `id` of `station` as its card (login_card's) as nodes of the window's tree, in `parent`, what it shows the
/// core's as it changes: ended, one quiet line saying how (failed in red); under way, its title with 取消 as its × in
/// the card's corner, what the person does now by its step and the step's own button (login_active_node); where this
/// device may not finish it, how it stands. One the core does not know draws nothing.
pub fn login_card_node(parent : @view.View, core : Core, station : String, id : String) -> Unit {
  let l = fn() -> Json? {
    match (core.topic)("machineLogin", { "station": Json::string(station), "id": Json::string(id) }).value {
      Some(Object(_)) as v => v
      _ => None
    }
  }
  let all = fn() { (core.topic)("machineLogins", { "station": Json::string(station) }).value }
  // signed in while its card shows, felt as something done; failed, as something refused
  let state = fn() { text(l(), "state") }
  parent.reacts(state, fn(now) {
    if now == "done" {
      @ui.haptic(Confirm)
    } else if now == "failed" {
      @ui.haptic(Reject)
    }
  })
  parent.pick(fn() {
    match l() {
      None => 0
      Some(_) as v if !flag(v, "active") => 1
      _ => if flag(all(), "canLogin") { 2 } else { 3 }
    }
  }, fn(p, which) {
    match which {
      1 =>
        p.box(fn(w) {
          let style = fn() { if state() == "failed" { lc_ended_failed } else { lc_ended } }
          w
          .words(By(fn() {
            match text(l(), "endedText") {
              "" => text(l(), "title") + " · " + text(l(), "statusText")
              s => s
            }
          }))
          .words_look(By(fn() { @ui.style_words(style()) }))
          .ink(By(fn() { @ui.style_ink(style()) }))
          |> ignore
        })
        |> ignore
      2 | 3 =>
        p.box(fn(room) {
          // (lc_room's Full width: the card's least width is bounded by the message column, not its own content)
          room.width_share(Is(1.0)).min_width(Is(Some(0.0)))
          .padding(Is((0.0, 8.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
          room.box(fn(card) {
            card
            // (min(100%, 360px) to min(100%, 560px): said within where it is, not read back from its size)
            .min_width_within(Is(Some(360.0)))
            .max_width_within(Is(Some(560.0)))
            .padding(Is((@sf.corner_inset, @sf.corner_inset, @sf.corner_inset, @sf.corner_inset)))
            .gap(Is(2.0))
            .radius(Is(@sf.card_corner))
            .ground(By(fn() { @sf.alpha(@sf.theme().p.text, 0.05) }))
            |> ignore
            if which == 2 {
              card.box(fn(head) {
                head.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Start))) |> ignore
                login_title_node(head, fn() { text(l(), "title") })
                login_cancel_node(head, core, station, id)
              })
              |> ignore
              login_active_node(card, core, station, l, fn() { flag(all(), "canRelay") })
            } else {
              login_title_node(card, fn() { text(l(), "title") })
              login_said_node(card, fn() { text(l(), "statusText") }, last=true)
            }
          })
          |> ignore
        })
        |> ignore
      _ => ()
    }
  })
}

///|
/// A login card's title (lc_title_room's): 10 in and 10 down, the row's.
fn login_title_node(parent : @view.View, title : () -> String) -> Unit {
  parent.box(fn(t) {
    t.grow(Is(1.0)).min_width(Is(Some(0.0))).padding(Is((10.0, 10.0, 10.0, 0.0))) |> ignore
    t.box(fn(w) {
      w.words(By(title)).words_look(By(fn() { @ui.style_words(lc_title) })).ink(By(fn() { @ui.style_ink(lc_title) })) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// 取消 as the card's × (login_cancel's): 24, round, lit under the pointer, in the card's top end corner; turning while
/// it is under way.
fn login_cancel_node(parent : @view.View, core : Core, station : String, id : String) -> Unit {
  let busy = fn() { @settings.is_doing(core, ["machineLogin.cancel"], [("station", station), ("id", id)]) }
  let what = @sf.t("web-main.logins.cancelWhat")
  parent.box(fn(x) {
    x
    .width(Is(Some(lc_cancel_side)))
    .height(Is(Some(lc_cancel_side)))
    .radius(Is(lc_cancel_side / 2.0))
    .margin(Is((0.0, lc_cancel_off, lc_cancel_off, 0.0)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { if !busy() && x.pointed() { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=what)) }))
    |> ignore
    @sf.presses_node(x, on=fn() { !busy() }, fn() {
      @settings.act(core, what, "machineLogin.cancel", { "station": Json::string(station), "id": Json::string(id) })
    })
    x.pick(busy, fn(i, b) {
      if b {
        @sf.spinner_node(i, size=lc_spin) |> ignore
      } else {
        @sf.icon_node(i, "close", lc_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// A line of how it stands or what to do (login_said's): 12 on 18, grey (red where `red`), 10 in, a spinner 6 before it
/// while `busy`; `last`, 10 over the card's foot.
fn login_said_node(
  parent : @view.View,
  words : () -> String,
  red? : () -> Bool = fn() { false },
  busy? : () -> Bool = fn() { false },
  last? : Bool = false,
) -> Unit {
  parent.box(fn(s) {
    s.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).padding(Is((10.0, 0.0, 10.0, if last { 10.0 } else { 0.0 }))) |> ignore
    s.show(busy, fn(b) { @sf.spinner_node(b, size=lc_spin) |> ignore })
    s.box(fn(w) {
      let style = fn() { if red() { lc_said_red } else { lc_said_words } }
      w.words(By(words)).words_look(By(fn() { @ui.style_words(style()) })).ink(By(fn() { @ui.style_ink(style()) })) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A step's button (login_step's) in `parent`: the card's width, 32 high, 8 under what is above it, round as the card
/// less its padding; on the ink at 5% (lit under the pointer), solid while it is the next thing to do; a spinner while
/// it is under way, ↗ for a page opened elsewhere; the other ways of doing the step in a ⋯ beside it. `last`: reaching
/// the card's foot as its sides.
fn login_step_node(
  parent : @view.View,
  label : () -> String,
  solid : () -> Bool,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
  external? : Bool = false,
  more? : () -> Array[(String, () -> Unit)] = fn() { [] },
  last? : Bool = true,
) -> Unit {
  let reach = lc_step_reach
  parent.box(fn(row) {
    row
    .row(Is(true))
    .gap(Is(6.0))
    .lines_up(Is(Some(Middle)))
    .margin(Is((-reach, 8.0, -reach, if last { -reach } else { 0.0 })))
    |> ignore
    row.box(fn(b) {
      let ink = fn() { if solid() { @sf.theme().p.on_primary } else { @sf.theme().p.text } }
      b
      .grow(Is(1.0))
      .row(Is(true))
      .height(Is(Some(32.0)))
      .padding(Is((12.0, 0.0, 12.0, 0.0)))
      .gap(Is(6.0))
      .radius(Is(@sf.row_corner))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() {
        let p = @sf.theme().p
        let hot = !busy() && b.pointed()
        if solid() {
          if hot { @sf.mix(p.bg, 0.15, p.primary) } else { p.primary }
        } else if hot {
          p.hover
        } else {
          @sf.alpha(p.text, 0.05)
        }
      }))
      .says(By(fn() { Some(@view.said(Button, label=label())) }))
      |> ignore
      @sf.presses_node(b, on=fn() { !busy() }, press)
      b.show(busy, fn(s) { @sf.spinner_node(s, size=lc_spin, arc=ink) |> ignore })
      b.box(fn(w) {
        let style = fn() { if solid() { lc_step_words_solid } else { lc_step_words } }
        w.words(By(label)).words_look(By(fn() { @ui.style_words(style()) })).ink(By(fn() { @ui.style_ink(style()) })) |> ignore
      })
      |> ignore
      if external {
        @sf.icon_node(b, "arrow-up-right", lc_icon, By(ink)) |> ignore
      }
    })
    |> ignore
    // (the other ways of doing the step, seldom used, in a ⋯ at the row's end)
    row.show(fn() { !more().is_empty() }, fn(m) {
      let what = @sf.t("common.login.otherWays")
      m
      .width(Is(Some(32.0)))
      .height(Is(Some(32.0)))
      .radius(Is(@sf.row_corner))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() { if m.pointed() { @sf.theme().p.hover } else { @sf.alpha(@sf.theme().p.text, 0.05) } }))
      .says(Is(Some(@view.said(Button, label=what))))
      |> ignore
      // (the presenters' menu: from the foot on a small screen, beside it on the others)
      @sf.presses_node(m, fn() {
        // (beside where it is on screen as it is pressed)
        let at : @sf.Beside = match m.shown_rect() {
          Some((x, y, w, h)) => @sf.Beside::At(x, y, w, h)
          None => @sf.at_point(0.0, 0.0)
        }
        @sf.menu(more().map(fn(w) { Some(@sf.menu_item_of(w.0, w.1)) }), from=at, along=End)
      })
      @sf.icon_node(m, "more", lc_icon, By(fn() { @sf.theme().p.text })) |> ignore
    })
  })
  |> ignore
}

///|
/// A login under way (login_active's) in `card`: what the person does now by its step (or, while its agent answers
/// the command or it is checked, how it stands), then the step's own button; one whose page gives a code to paste back
/// its own (login_paste_node). Made again as its step changes.
fn login_active_node(card : @view.View, core : Core, station : String, l : () -> Json?, relay : () -> Bool) -> Unit {
  let id = text(@signals.untracked(l), "id")
  let url = fn() { text(l(), "url") }
  let domain = fn() {
    match text(l(), "domain") {
      "" => ""
      d => @sf.t("web-main.logins.domain", args=[("domain", d)])
    }
  }
  let pressed = fn() {
    logins_here.said.get() |> ignore
    logins_here.pressed.get(id).unwrap_or(false)
  }
  let press = fn() {
    logins_here.pressed[id] = true
    logins_said()
  }
  // the same step in the station's own browser, for the ⋯ beside the step's button
  let elsewhere = fn() -> Array[(String, () -> Unit)] {
    let now = l()
    if !flag(now, "browser") || text(now, "browserText") == "" {
      return []
    }
    let label = text(now, "browserText")
    [
      (
        label,
        fn() {
          let current = l()
          @settings.confirm_claude_auth(text(current, "name") == "claude" && text(current, "screen") == "", fn() {
            @settings.act(core, label, "machineLogin.browser", { "station": Json::string(station), "id": Json::string(id) }, then=fn(v) {
              (core.open_screen)(station, text(Some(v), "screen"))
            })
          })
        },
      ),
    ]
  }
  let step = fn() {
    let now = l()
    if flag(now, "paste") && url() != "" {
      return "paste"
    }
    // checking what came back: nothing left for the person but to wait
    let s = if flag(now, "waiting") || text(now, "state") == "verifying" { "" } else { text(now, "step") }
    match s {
      "device" if text(now, "code") != "" => "device"
      "loopback" if elsewhere().length() > 0 && (!relay() || text(now, "relayText") != "") => "loopback-station"
      "loopback" if !relay() => "loopback-none"
      "loopback" => "loopback"
      "open" if url() != "" => "open"
      _ => ""
    }
  }
  card.pick(step, fn(s, which) {
    match which {
      "paste" => login_paste_node(s, core, station, l)
      "device" => {
        login_said_node(s, fn() { @sf.t("web-main.logins.device", args=[("domain", text(l(), "domain"))]) })
        // the code, large enough to read and copy by eye: pressed, copied, said so
        s.box(fn(code) {
          code
          .padding(Is((10.0, 4.0, 10.0, 4.0)))
          .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.logins.copyCode") + " " + text(l(), "code"))) }))
          |> ignore
          @sf.presses_node(code, fn() {
            @ui.clipboard_set(text(l(), "code"))
            (core.say)(@sf.t("web-main.logins.codeCopied"))
          })
          code.box(fn(w) {
            w
            .words_runs(By(fn() { [@ui.span(text(l(), "code"), mono=true)] }))
            .words_look(By(fn() { @ui.style_words(lc_code) }))
            .ink(By(fn() { @ui.style_ink(lc_code) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
        // one press: the code copied first, then its page
        login_step_node(s, fn() { @sf.t("web-main.logins.copyOpen") }, fn() { !pressed() }, fn() {
          let current = l()
          let code = text(current, "code")
          let page = match text(current, "codeUrl") {
            "" => text(current, "url")
            u => u
          }
          @settings.confirm_claude_auth(text(current, "name") == "claude", fn() {
            press()
            @ui.clipboard_set(code)
            login_open(core, page)
          })
        }, more=elsewhere)
      }
      "loopback-station" => {
        s.show(fn() { text(l(), "relayText") != "" && relay() }, fn(r) {
          login_said_node(r, fn() { text(l(), "relayText") }, red=fn() { true })
        })
        s.show(fn() { domain() != "" }, fn(d) { login_said_node(d, domain) })
        let busy = fn() { @settings.is_doing(core, ["machineLogin.browser"], [("station", station), ("id", id)]) }
        login_step_node(s, fn() { text(l(), "browserText") }, fn() { true }, fn() {
          match elsewhere().get(0) {
            Some(w) => (w.1)()
            None => ()
          }
        }, busy~, more=fn() {
          if relay() {
            [(@sf.t("web-main.logins.signIn"), fn() {
              let current = l()
              @settings.confirm_claude_auth(text(current, "name") == "claude", fn() { login_relay_now(core, station, id, text(current, "title")) })
            })]
          } else {
            []
          }
        })
      }
      "loopback-none" => {
        login_said_node(s, fn() { @sf.t("web-main.logins.needsDesktop") }, last=@signals.untracked(domain) == "")
        s.show(fn() { domain() != "" }, fn(d) { login_said_node(d, domain, last=true) })
      }
      "loopback" => {
        let opened = fn() { flag(l(), "listening") }
        s.pick(fn() {
          if opened() {
            1
          } else if text(l(), "relayText") != "" {
            2
          } else if domain() != "" {
            3
          } else {
            0
          }
        }, fn(lead, k) {
          match k {
            1 => login_said_node(lead, fn() { @sf.t("web-main.logins.waitingBrowser") }, busy=fn() { true })
            2 => {
              login_said_node(lead, fn() { text(l(), "relayText") }, red=fn() { true })
              lead.show(fn() { domain() != "" }, fn(d) { login_said_node(d, domain) })
            }
            3 => login_said_node(lead, domain)
            _ => ()
          }
        })
        let busy = fn() { @settings.is_doing(core, ["machineLogin.open"], [("station", station), ("id", id)]) }
        login_step_node(s, fn() { @sf.t(if opened() { "web-main.logins.openAgain" } else { "web-main.logins.signIn" }) }, fn() {
          !opened()
        }, fn() {
          let current = l()
          @settings.confirm_claude_auth(text(current, "name") == "claude", fn() { login_relay_now(core, station, id, text(current, "title")) })
        }, busy~, more=elsewhere)
      }
      "open" => {
        s.show(fn() { domain() != "" }, fn(d) { login_said_node(d, domain) })
        login_step_node(s, fn() { @sf.t("web-main.logins.signIn") }, fn() { !pressed() }, fn() {
          let current = l()
          @settings.confirm_claude_auth(text(current, "name") == "claude", fn() {
            press()
            login_open(core, text(current, "url"))
          })
        }, more=elsewhere)
      }
      _ => login_said_node(s, fn() { text(l(), "statusText") }, busy=fn() { true }, last=true)
    }
  })
}

///|
/// A loopback login's browser on this device (login_relay's), asked at once: the app held up meanwhile, the core
/// listening for the browser's callback, then its page opened.
fn login_relay_now(core : Core, station : String, id : String, title : String) -> Unit {
  let here = this_machine() == station
  @ui.hold_words(
    channel=@sf.t("web-main.logins.title"),
    title=if title == "" { @sf.t("web-main.logins.title") } else { title },
    body=@sf.t("web-main.logins.waitingBrowser"),
  )
  (core.call)("machineLogin.open", { "station": Json::string(station), "id": Json::string(id), "here": Json::boolean(here) }, fn(r) {
    match r {
      Ok(v) => login_open(core, text(Some(v), "url"))
      Err(e) if text(Some(e), "code") == "port_taken" => ()
      Err(e) =>
        (core.say)(@sf.t("android-misc.act.failed", args=[("what", @sf.t("web-main.logins.openWhat")), ("error", error_words(e))]))
    }
  })
}

///|
/// A login whose page gives a code to paste back (login_paste's) in `s`: where to sign in and what to bring back, then
/// 打开登录页 (solid until pressed here or a code is in) and the field, 完成 at its end once a code is in (Enter too); sent,
/// 完成 turns while it is checked.
fn login_paste_node(s : @view.View, core : Core, station : String, l : () -> Json?) -> Unit {
  let id = text(@signals.untracked(l), "id")
  let field = login_field(id)
  let sending = fn() { @settings.is_doing(core, ["machineLogin.answer"], [("station", station), ("id", id)]) }
  let checking = fn() { text(l(), "state") == "verifying" }
  let busy = fn() { sending() || checking() }
  let opened = fn() {
    logins_here.said.get() |> ignore
    logins_here.pressed.get(id).unwrap_or(false)
  }
  let words = fn() { field.text().trim(chars=" \n").to_string() }
  login_said_node(s, fn() {
    if checking() {
      text(l(), "statusText")
    } else {
      match text(l(), "domain") {
        "" => text(l(), "statusText")
        d => @sf.t("web-main.logins.pasteLead", args=[("domain", d)])
      }
    }
  })
  let elsewhere = fn() -> Array[(String, () -> Unit)] {
    let now = l()
    if !flag(now, "browser") || text(now, "browserText") == "" {
      return []
    }
    let label = text(now, "browserText")
    [
      (
        label,
        fn() {
          let current = l()
          @settings.confirm_claude_auth(text(current, "name") == "claude" && text(current, "screen") == "", fn() {
            @settings.act(core, label, "machineLogin.browser", { "station": Json::string(station), "id": Json::string(id) }, then=fn(v) {
              (core.open_screen)(station, text(Some(v), "screen"))
            })
          })
        },
      ),
    ]
  }
  login_step_node(s, fn() { @sf.t("web-main.logins.openPage") }, fn() { !opened() && words() == "" && !busy() }, fn() {
    let current = l()
    @settings.confirm_claude_auth(text(current, "name") == "claude", fn() {
      logins_here.pressed[id] = true
      logins_said()
      login_open(core, text(current, "url"))
    })
  }, external=true, more=elsewhere, last=false)
  let send = fn() {
    let code = @signals.untracked(words)
    if code == "" || @signals.untracked(busy) {
      return
    }
    // (sent, nothing is left to type: the keyboard goes, the code staying in the field as it is checked)
    @ui.current().blur()
    @settings.act(core, @sf.t("web-main.logins.answerWhat"), "machineLogin.answer", {
      "station": Json::string(station),
      "id": Json::string(id),
      "text": Json::string(code),
    })
  }
  s.box(fn(p) {
    p
    .row(Is(true))
    .height(Is(Some(32.0)))
    .margin(Is((-lc_step_reach, 6.0, -lc_step_reach, -lc_step_reach)))
    .padding(Is((12.0, 0.0, 4.0, 0.0)))
    .gap(Is(4.0))
    .radius(Is(@sf.row_corner))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { @sf.theme().p.bg }))
    |> ignore
    p.box(fn(fw) {
      // (the room 完成 leaves, whatever its placeholder's width)
      fw.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      @ui.field(
        fw,
        field,
        placeholder=@sf.t("web-main.logins.pasteCode"),
        font_size=lc_paste_size,
        line=lc_paste_line,
        max_lines=1,
        enter_sends=true,
        color=@sf.theme().p.text,
        placeholder_color=@sf.theme().p.muted,
        caret_color=@sf.theme().p.accent,
        submitted=fn(_) { send() },
      )
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    p.show(fn() { words() != "" || busy() }, fn(d) {
      d
      .row(Is(true))
      .height(Is(Some(24.0)))
      .padding(Is((12.0, 0.0, 12.0, 0.0)))
      .radius(Is(dmax(0.0, @sf.row_corner - 4.0)))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() {
        let pl = @sf.theme().p
        if !busy() && d.pointed() { @sf.mix(pl.bg, 0.15, pl.primary) } else { pl.primary }
      }))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.logins.finish"))) }))
      |> ignore
      @sf.presses_node(d, on=fn() { !busy() }, send)
      // busy: a spinner over its word, as wide as before
      d.box(fn(w) {
        w
        .words(By(fn() { @sf.t("web-main.logins.finish") }))
        .words_look(By(fn() { @ui.style_words(lc_done_words) }))
        .ink(By(fn() { @ui.style_ink(lc_done_words) }))
        .alpha(By(fn() { if busy() { 0.0 } else { 1.0 } }))
        |> ignore
      })
      |> ignore
      d.show(busy, fn(sp) {
        sp.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
        @sf.spinner_node(sp, size=lc_spin, arc=fn() { @sf.theme().p.on_primary }) |> ignore
      })
    })
  })
  |> ignore
}

///|
/// A step left of something under an agent's message (step_card's) as nodes of the window's tree in `parent`: a
/// login's card's look, its title and a line under it, the whole card the way to it (`go`), a › in its corner where a
/// login's × is; lit under the pointer.
pub fn step_card_node(parent : @view.View, title : () -> String, line : () -> String, go : () -> Unit) -> Unit {
  parent.box(fn(room) {
    room.padding(Is((0.0, 8.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
    room.box(fn(card) {
      card
      // (min(100%, 360px) to min(100%, 560px), within where it is: lc_card's)
      .min_width_within(Is(Some(360.0)))
      .max_width_within(Is(Some(560.0)))
      .padding(Is((@sf.corner_inset, @sf.corner_inset, @sf.corner_inset, @sf.corner_inset)))
      .gap(Is(2.0))
      .radius(Is(@sf.card_corner))
      .ground(By(fn() { if card.pointed() { @sf.theme().p.hover } else { @sf.alpha(@sf.theme().p.text, 0.05) } }))
      .says(By(fn() { Some(@view.said(Button, label=title())) }))
      |> ignore
      @sf.presses_node(card, go)
      card.box(fn(head) {
        head.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Start))) |> ignore
        login_title_node(head, title)
        head.box(fn(m) {
          m
          .width(Is(Some(lc_cancel_side)))
          .height(Is(Some(lc_cancel_side)))
          .margin(Is((0.0, lc_cancel_off, lc_cancel_off, 0.0)))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          |> ignore
          @sf.icon_node(m, "chevron-right", lc_icon, By(fn() { @sf.theme().p.muted })) |> ignore
        })
        |> ignore
      })
      |> ignore
      login_said_node(card, line, last=true)
    })
    |> ignore
  })
  |> ignore
}
