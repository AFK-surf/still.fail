// What the person does in the browser for a profile's sign-in under way (Profiles.kt LoginSteps): open the page and
// paste the code back (Claude, Devin), copy the code and open the page (Codex, Grok), or only open the page and confirm
// there (Cursor). Each step's button solid until it is pressed (LoginCards.kt StepButton), the code's field with 完成 in
// its end once a code is in (CodeField); all of them reaching the card's corners, concentric with it (Profiles.kt
// CODE_BOX_CORNER: concentric(card_pad + 38 / 2, card_pad), 23, the scale's 22; 完成 6 in, 17, the scale's 16).

///|
/// A step's button (StepButton): the card's width, 8 under what is over it, 44 high, solid (the ink, the page's colour
/// on it) until pressed, else the ink at 6%; its words 15 semibold, ↗ after them when it opens a page.
// kept across runs: a value (no field of it changes)
let step_room : @ui.Style = @ui.style(w=Full, pt=S2)

///|
// kept across runs: a value (no field of it changes)
let step_button : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=S11,
  gap=S1_5,
  radius=Xl3,
  bg=Tint,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=TintStrong),
)

///|
// kept across runs: a value (no field of it changes)
let step_button_solid : @ui.Style = step_button.then(@ui.style(bg=Fg, pressed=@ui.patch(bg=Over(Fg, A(Bg, O15)))))

///|
// kept across runs: a value (no field of it changes)
let step_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let step_words_solid : @ui.TextStyle = step_words.then(@ui.text_style(color=Bg))

///|
/// What a step says (13 on 19 lines, muted).
// kept across runs: a value (no field of it changes)
let step_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L4_75, color=Muted, w=Full)

///|
/// The device code's box: the card's width, on the chips' grey, 14 by 10 in, the code in its middle.
// kept across runs: a value (no field of it changes)
let code_box : @ui.Style = @ui.style(w=Full, px=S3_5, py=S2_5, radius=Xl3, bg=Neutral, align=ACenter)

///|
/// The code pasted back (CodeField): the card's width, 6 under the step over it, 44 high, on the chips' grey (on the
/// card's white), 14 in on the left and 6 on the right.
// kept across runs: a value (no field of it changes)
let code_field_room : @ui.Style = @ui.style(w=Full, pt=S1_5)

///|
// kept across runs: a value (no field of it changes)
let code_field : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=S11,
  pl=S3_5,
  pr=S1_5,
  gap=S1_5,
  radius=Xl3,
  bg=Neutral,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let code_field_words : @ui.Style = @ui.style(w=Full)

///|
/// 完成 in the field's end: 32 high, solid, 14 in each side.
// kept across runs: a value (no field of it changes)
let code_finish : @ui.Style = @ui.style(
  row=true,
  h=S8,
  px=S3_5,
  radius=Xl1_5,
  bg=Fg,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=Over(Fg, A(Bg, O15))),
)

///|
// kept across runs: a value (no field of it changes)
let code_finish_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Bg, wrap=false)

///|
/// A step's button: true on the frame after it was pressed.
fn step_button_of(c : @ui.Ctx, key : String, label : String, solid : Bool, external? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(style=step_room, fn() {
    c.box(style=if solid { step_button_solid } else { step_button }, id~, fn() {
      c.text(label, style=if solid { step_words_solid } else { step_words }) |> ignore
      if external {
        @sf.icon(c, "arrow-up-right", size=step_icon, color=if solid { t.p.bg } else { t.p.text }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// ↗ after a step's words (16).
let step_icon : Double = 16.0

///|
/// The device code's size (22) and its line (28).
let device_code_size : Double = 22.0

///|
let device_code_line : Double = 28.0

///|
/// What the person does in the browser for a sign-in under way (Profiles.kt LoginSteps), `k` the profile's key: its
/// states' waiting lines, and while it waits on the person, its steps. The page is handed to `open_link`: the system's
/// browser.
fn login_steps(c : @ui.Ctx, core : Core, k : String, job : Json?, provider : String, send : (String) -> Unit) -> Unit {
  let t = @sf.theme()
  let state = text(job, "state")
  let url = text(job, "url")
  let user_code = text(job, "userCode")
  let copied = login_state.copied.get(k).unwrap_or(false)
  if job is None || state == "starting" {
    wait_line(c, fill("android-settings.login.making", [("provider", provider)]))
  } else if state == "verifying" {
    wait_line(c, tr("android-settings.login.finishing"))
  } else if state == "done" {
    wait_line(c, tr("android-settings.login.adding"))
  } else if state == "needs_approval" && url != "" && user_code == "" {
    // no code: the page only asks to confirm (Cursor's)
    c.text(tr("android-settings.login.cursorNote"), style=step_note) |> ignore
    if step_button_of(c, "login-open", tr("android-settings.login.openPage"), !copied, external=true) {
      login_state.copied[k] = true
      (core.open_link)(url)
    }
  } else if state == "needs_approval" && url != "" {
    c.box(style=code_box, fn() {
      mono(c, user_code, size=device_code_size, line=device_code_line)
    })
    |> ignore
    c.text(
      match provider {
        "OpenCode" => tr("android-settings.login.opencodeNote")
        "Kimi" => tr("android-settings.login.kimiNote")
        "Grok" => tr("android-settings.login.grokNote")
        _ => fill("android-settings.login.codexNote", [("app", "still.fail")])
      },
      style=step_note,
    )
    |> ignore
    // OpenCode's and Kimi's pages have the code in their address: only compared there, not copied
    let filled = provider == "OpenCode" || provider == "Kimi"
    if step_button_of(
        c,
        "login-open",
        tr(
          if filled {
            "android-settings.login.openPage"
          } else if copied {
            "android-settings.login.reopen"
          } else {
            "android-settings.login.copyOpen"
          },
        ),
        !copied,
        external=filled,
      ) {
      if !filled {
        c.copy_text(user_code)
      }
      login_state.copied[k] = true
      (core.open_link)(url)
    }
  } else if state == "needs_code" && url != "" {
    // what to do said once, then its two steps in the order they are done, the next one solid: its page, then the
    // code it gives in the field (完成 in its end)
    c.text(
      fill(if provider == "Devin" { "android-settings.login.step1ShortDevin" } else { "android-settings.login.step1Short" }, [
        ("app", "still.fail"),
      ]),
      style=step_note,
    )
    |> ignore
    let key = "login-code/" + k
    let field = field_of(key)
    let typed = field.text().trim(chars=" \n").to_owned() != ""
    if step_button_of(c, "login-open", tr("android-settings.login.openPage"), !copied && !typed, external=true) {
      login_state.copied[k] = true
      (core.open_link)(url)
    }
    c.box(style=code_field_room, fn() {
      c.box(style=code_field, fn() {
        let mut code = ""
        c.box(style=code_field_words, fn() {
          let r = c.editor(
            key,
            placeholder=tr("android-settings.login.pasteCode"),
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
          code = r.text.trim(chars=" \n").to_owned()
          // the keyboard's Done too
          match r.submitted {
            Some(sent) if sent.trim(chars=" \n").to_owned() != "" => {
              login_state.error.remove(k)
              field.set("")
              send(sent.trim(chars=" \n").to_owned())
            }
            _ => ()
          }
        })
        |> ignore
        if code != "" {
          let go = c.id("login-finish")
          if c.clicked(go) {
            login_state.error.remove(k)
            field.set("")
            c.blur()
            send(code)
          }
          c.box(style=code_finish, id=go, fn() {
            c.text(tr("android-settings.login.finishShort"), style=code_finish_words) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    match login_state.error.get(k) {
      Some(e) => c.box(style=code_field_room, fn() { c.text(e, style=step_error) |> ignore }) |> ignore
      None => ()
    }
  }
}

///|
/// What went wrong with the code sent, in red, 6 under the field.
// kept across runs: a value (no field of it changes)
let step_error : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, w=Full)
