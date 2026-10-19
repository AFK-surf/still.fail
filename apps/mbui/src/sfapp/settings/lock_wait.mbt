// A device not yet confirmed in the workspace's safe mode (its lock): what it shows instead of the workspace's chats
// (settings/Security.kt LockGate, SecurityWaitingScreen; docs/workspace-lock.md「新设备」). Every station of a locked
// workspace refuses such a device, so its Home would only say they are offline. Nothing is asked by itself (the person
// who will compare the codes asks: 「发送批准请求」, the core's `lock.pair`); the core finds the person's trusted
// devices, one of them shows a code, it is typed here into six boxes (`lock.pairCode`), and how that goes is the
// lock's `me.pair` (finding, code, checking, wrong, none, failed, done). Also said: this device's own code, as the
// approving side lists it.

///|
/// Whether this device waits to be confirmed in the workspace's lock (the lock's `me.waiting`).
pub fn lock_waiting(core : Core, ws : String) -> Bool {
  let lock = (core.topic)("lock", { "workspace": str(ws) }).value
  flag(field(lock, "me"), "waiting")
}

///|
/// What the code field has typed (the boxes' digits), by workspace.
let typed_code : Map[String, String] = {}

///|
/// The code fields given the keys once, as they first showed (the keyboard up for them, as Android's).
let code_focused : Map[String, Bool] = {}

///|
/// The page shown in the workspace's place while this device waits (SecurityWaitingScreen).
pub fn lock_wait_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let ws = here.workspace
  let lock = (core.topic)("lock", { "workspace": str(ws) }).value
  let me = field(lock, "me")
  let pair = field(me, "pair")
  let state = text(pair, "state")
  let on = [("workspace", ws)]
  let asking = is_doing(core, ["lock.pair"], on)
  let checking = is_doing(core, ["lock.pairCode"], on) || state == "checking"
  let typing = state == "code" || state == "wrong" || state == "checking"
  c.box(w=Fill(1.0), h=Fill(1.0), padx=28.0, gap=14.0, align=ACenter, justify=JCenter, fn() {
    @sf.icon(c, "shield-check", size=44.0, color=t.p.text) |> ignore
    c.text(tr("web-pages.security.waitingTitle"), size=22.0, weight=700, color=t.p.text, line=28.0, w=Fill(1.0), center=true) |> ignore
    c.text(
      fill("web-pages.security.waitingLead", [("name", here.name)]),
      size=15.0,
      color=t.p.subtle,
      line=22.0,
      w=Fill(1.0), center=true,
    )
    |> ignore
    if typing {
      note_center(c, tr("web-pages.security.pairEnter"))
      code_field(c, ws, state == "wrong", !checking, fn(code) {
        (core.call)(
          "lock.pairCode",
          obj([("workspace", str(ws)), ("code", str(code))]),
          fn(r) {
            wake()
            if r is Err(_) {
              typed_code[ws] = ""
              c.set_editor_text("lock-code/" + ws, "")
            }
          },
        )
      })
      if checking {
        wait_line(c, tr("web-pages.security.pairChecking"))
      } else if state == "wrong" {
        c.text(
          fill("web-pages.security.pairWrong", [("n", count(pair, "left").to_string())]),
          size=12.0,
          color=t.p.red,
          line=18.0,
          w=Fill(1.0), center=true,
        )
        |> ignore
      }
    } else if state == "finding" || asking {
      wait_line(c, tr("web-pages.security.pairFinding"))
    } else {
      match (state, text(me, "failed")) {
        ("none", _) => note_center(c, tr("web-pages.security.pairNone"))
        ("failed", _) =>
          c.text(text(pair, "error"), size=12.0, color=t.p.red, line=18.0, w=Fill(1.0), center=true) |> ignore
        (_, "") => note_center(c, tr("web-pages.security.notAsked"))
        (_, failed) =>
          c.text(
            fill("web-pages.security.requestFailed", [("error", failed)]),
            size=12.0,
            color=t.p.red,
            line=18.0,
            w=Fill(1.0), center=true,
          )
          |> ignore
      }
      if wide_button(c, "lock-pair/" + ws, tr("web-pages.security.request"), true) {
        lock_call(core, ws, "pair", tr("web-pages.security.request"), [])
      }
    }
    // this device's own code: what its approver sees listed (the lock's `me.code`)
    let code = text(me, "code")
    if code != "" {
      c.box(dir=Row, gap=8.0, align=ACenter, fn() {
        c.text(tr("web-pages.security.thisDevice"), size=13.0, color=t.p.muted, line=18.0, wrap=false) |> ignore
        mono(c, code, size=13.0, weight=600, color=t.p.muted)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn note_center(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.text(words, size=12.0, color=t.p.subtle, line=18.0, w=Fill(1.0), center=true) |> ignore
}

///|
/// Six digits in six boxes, three and three (Security.kt CodeField): the field under them takes the typing (digits
/// only, six at most); the sixth hands the code on at once.
fn code_field(c : @ui.Ctx, ws : String, wrong : Bool, enabled : Bool, done : (String) -> Unit) -> Unit {
  let t = @sf.theme()
  let key = "lock-code/" + ws
  let value = typed_code.get(ws).unwrap_or("")
  c.box(align=ACenter, fn() {
    c.box(dir=Row, gap=8.0, align=ACenter, fn() {
      let chars = value.to_array()
      for i in 0..<6 {
        if i == 3 {
          c.box(w=Px(8.0), fn() {  }) |> ignore
        }
        let next = enabled && c.editor_focused(key) && i == (if chars.length() < 5 { chars.length() } else { 5 })
        let edge = if wrong && value == "" {
          t.p.red
        } else if next {
          t.p.text
        } else {
          @sf.alpha(t.p.text, 0.18)
        }
        c.box(w=Px(42.0), h=Px(52.0), radius=12.0, border=1.0, border_color=edge, align=ACenter, justify=JCenter, fn() {
          if i < chars.length() {
            mono(c, chars[i].to_string(), size=24.0, weight=600, color=if enabled { t.p.text } else { t.p.muted })
          }
        })
        |> ignore
      }
    })
    |> ignore
    // the field itself over the boxes, its words unseen: a tap there gives it the keys
    c.layer(fn() {
      let r = c.editor(
        key,
        font_size=24.0,
        max_lines=1,
        plain=true,
        line=52.0,
        color=0x00000000L,
        placeholder_color=0x00000000L,
        caret_color=0x00000000L,
        enter_sends=true,
      )
      if !code_focused.contains(key) {
        code_focused[key] = true
        c.focus_editor(key)
      }
      if enabled {
        let digits = StringBuilder()
        let mut n = 0
        for ch in r.text {
          if ch >= '0' && ch <= '9' && n < 6 {
            digits.write_char(ch)
            n += 1
          }
        }
        let d = digits.to_string()
        if d != r.text {
          c.set_editor_text(key, d)
        }
        if d != value {
          typed_code[ws] = d
          if d.length() == 6 {
            done(d)
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}
