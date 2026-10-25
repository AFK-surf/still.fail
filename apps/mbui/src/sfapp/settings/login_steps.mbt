// What the person does in the browser for a profile's sign-in under way (Profiles.kt LoginSteps): open the page and
// paste the code back (Claude, Devin), copy the code and open the page (Codex, Grok), or only open the page and confirm
// there (Cursor). Each step's button solid until it is pressed (LoginCards.kt StepButton), the code's field with 完成 in
// its end once a code is in (CodeField); the last of them in the card's foot corners, so all of them capsules a
// settings button high, reaching past the card's words to its foot's inset (parts.mbt Foot's Capsule: foot_across),
// 完成 a capsule concentric in the field's end. Where the station has a browser of its own, the same page opened there
// (its tab's view opened here, gone back from as the sign-in ends; Claude's comes back to its command there, with no
// code to paste), seldom used: in a ⋯ at the end of the page's button.

///|
/// A step's button (StepButton): the card's foot's width, 8 under what is over it, a settings button high, solid (the
/// ink, the page's colour on it) until pressed, else the ink at 6%; its words 15 semibold, ↗ after them when it opens
/// a page.
// kept across runs: a value (no field of it changes)
let step_room : @ui.Style = @ui.css("w=Full pt=S2").then(foot_across)

///|
// kept across runs: a value (no field of it changes)
let step_button : @ui.Style = @ui.css("row w=Full gap=S1_5 radius=Full bg=Tint align=ACenter justify=JCenter").then(@ui.style(h=Fixed(settings_button_h)))

///|
// kept across runs: a value (no field of it changes)
let step_button_solid : @ui.Style = step_button.then(@ui.css("bg=Fg"))

///|
// kept across runs: a value (no field of it changes)
let step_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let step_words_solid : @ui.TextStyle = step_words.then(@ui.text_style(color=Bg))

///|
/// What a step says (13 on 19 lines, muted).
// kept across runs: a value (no field of it changes)
let step_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4_75, color=Muted, w=Full)

///|
/// The device code's box: the card's foot's width (as its buttons), on the chips' grey, 10 in, the code in its middle;
/// a block of the ladder's.
// kept across runs: a value (no field of it changes)
let code_box : @ui.Style = @ui.css("w=Full py=S2_5 bg=Neutral align=ACenter").then(@ui.style(radius=@sf.row_radius)).then(foot_across)

///|
/// The code pasted back (CodeField): the card's foot's width, 6 under the step over it, a capsule a settings button
/// high, on the chips' grey (on the card's white), 14 in on the left, 完成 concentric in its end.
// kept across runs: a value (no field of it changes)
let code_field_room : @ui.Style = @ui.css("w=Full pt=S1_5").then(foot_across)

///|
// kept across runs: a value (no field of it changes)
let code_field : @ui.Style = @ui.css("row w=Full pl=S3_5 gap=S1_5 radius=Full bg=Neutral align=ACenter").then(@ui.style(h=Fixed(settings_button_h), pr=@sf.capsule_end_room(settings_button_h, code_finish_h)))

///|
// kept across runs: a value (no field of it changes)
let code_field_words : @ui.Style = @ui.css("w=Full")

///|
/// 完成 in the field's end: a capsule 30 high, solid, 14 in each side.
// kept across runs: a value (no field of it changes)
let code_finish : @ui.Style = @ui.css("row px=S3_5 radius=Full bg=Fg align=ACenter justify=JCenter").then(@ui.style(h=Fixed(code_finish_h)))

///|
let code_finish_h : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let code_finish_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Bg, wrap=false)

///|
/// A step's button: true on the frame after it was pressed. `more`: other ways of doing the step, seldom used, in a ⋯
/// at its end (docs/ui-panels.md: what is used least goes into the row's ⋯): a round one as high, on the grey.
fn step_button_of(
  c : @ui.Ctx,
  key : String,
  label : String,
  solid : Bool,
  external? : Bool = false,
  more? : Array[(String, () -> Unit)] = [],
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(style=if more.is_empty() { step_room } else { step_room_row }, fn() {
    c.box(style=if solid { step_button_solid } else { step_button }, id~, fn() {
      c.text(label, style=if solid { step_words_solid } else { step_words }) |> ignore
      if external {
        @sf.icon(c, "arrow-up-right", size=step_icon, color=if solid { t.p.bg } else { t.p.text }) |> ignore
      }
      // LoginCards.kt StepButton: its ripple in its words' colour (ripple(color = ink))
      @motion.ripple(c, id, settings_button_h / 2.0, ink=@sf.alpha(if solid { t.p.bg } else { t.p.text }, 0.1))
    })
    |> ignore
    if !more.is_empty() {
      let mid = c.id(key + "/more")
      let b = c.box(style=step_more, id=mid, fn() {
        @sf.icon(c, "more", size=step_icon, color=t.p.text) |> ignore
        @motion.ripple(c, mid, settings_button_h / 2.0, ink=@sf.alpha(t.p.text, 0.1))
      })
      c.semantics(b, Button, id=mid, label=@sf.t("common.login.otherWays"))
      if c.clicked(mid) {
        @sf.menu(more.map(fn(w) { Some(@sf.menu_item_of(w.0, w.1)) }), from=Of(mid), along=End)
      }
    }
  })
  |> ignore
  c.clicked(id)
}

///|
/// A step's button with its ⋯ (step_button_of's `more`): side by side, 6 apart.
// kept across runs: a value (no field of it changes)
let step_room_row : @ui.Style = step_room.then(@ui.css("row gap=S1_5 align=ACenter"))

///|
// kept across runs: a value (no field of it changes)
let step_more : @ui.Style = @ui.css("radius=Full bg=Tint align=ACenter justify=JCenter").then(@ui.style(w=Fixed(settings_button_h), h=Fixed(settings_button_h)))

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
/// browser; or, where its job says the station has one (`browser`), to the station's own (`in_station`: the station's
/// name, and what opens it there, given what it is called).
fn login_steps(
  c : @ui.Ctx,
  core : Core,
  k : String,
  job : Json?,
  provider : String,
  send : (String) -> Unit,
  in_station? : (String, (String) -> Unit),
) -> Unit {
  let t = @sf.theme()
  let state = text(job, "state")
  let url = text(job, "url")
  let user_code = text(job, "userCode")
  let copied = login_state.copied.get(k).unwrap_or(false)
  // the same page in the station's browser (回到 … while its tab is open), in the ⋯ of the page's button
  let elsewhere = match in_station {
    Some((name, open)) if flag(job, "browser") => {
      let label = fill(if text(job, "screen") != "" { "common.login.backToStation" } else { "common.login.openInStation" }, [("station", name)])
      [(label, fn() { open(label) })]
    }
    _ => []
  }
  if job is None || state == "starting" {
    wait_line(c, fill("android-settings.login.making", [("provider", provider)]))
  } else if state == "verifying" {
    wait_line(c, tr("android-settings.login.finishing"))
  } else if state == "done" {
    wait_line(c, tr("android-settings.login.adding"))
  } else if state == "needs_approval" && url != "" && user_code == "" {
    // no code: the page only asks to confirm (Cursor's)
    c.text(tr("android-settings.login.cursorNote"), style=step_note) |> ignore
    if step_button_of(c, "login-open", tr("android-settings.login.openPage"), !copied, external=true, more=elsewhere) {
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
        more=elsewhere,
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
    if step_button_of(c, "login-open", tr("android-settings.login.openPage"), !copied && !typed, external=true, more=elsewhere) {
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
            // LoginCards.kt: its ripple in the page's colour (ripple(color = C.bg))
            @motion.ripple(c, go, code_finish_h / 2.0, ink=@sf.alpha(@sf.theme().p.bg, 0.1))
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
let step_error : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)
