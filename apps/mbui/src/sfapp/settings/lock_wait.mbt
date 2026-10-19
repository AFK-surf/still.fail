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
  // (a column a phone's width at most, in the middle: on a desktop's window too)
  let col = c.width - 56.0
  let col = if col > 420.0 { 420.0 } else if col < 0.0 { 0.0 } else { col }
  c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
  c.box(w=Px(col), gap=14.0, align=ACenter, fn() {
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
      let key = "lock-code/" + ws
      // six digits in six boxes, three and three (Security.kt CodeField), handed on once a code typed
      let typed = c.code_field(
        key,
        wrong=state == "wrong",
        enabled=!checking,
        color=t.p.text,
        disabled_color=t.p.muted,
        edge=@sf.alpha(t.p.text, 0.18),
        next_edge=t.p.text,
        wrong_edge=t.p.red,
      )
      if typed is Some(code) {
        (core.call)("lock.pairCode", obj([("workspace", str(ws)), ("code", str(code))]), fn(r) {
          wake()
          // a code refused: the boxes empty for the next try
          if r is Err(_) {
            c.clear_code_field(key)
          }
        })
      }
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
  })
  |> ignore
}

///|
fn note_center(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.text(words, size=12.0, color=t.p.subtle, line=18.0, w=Fill(1.0), center=true) |> ignore
}
