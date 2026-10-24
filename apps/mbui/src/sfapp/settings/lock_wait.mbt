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
  let ws = here.workspace
  let lock = (core.topic)("lock", { "workspace": str(ws) }).value
  let me = field(lock, "me")
  // (a column a phone's width at most, in the middle: on a desktop's window too; over the navigation bar,
  // SecurityWaitingScreen's windowInsetsPadding(navigationBars))
  c.box(style=lock_room, fn() { c.box(style=lock_page, fn() {
    c.box(style=lock_column, fn() {
      @sf.icon(c, "shield-check", size=c.space(S11), color=c.color(Fg)) |> ignore
      c.text(tr("web-pages.security.waitingTitle"), style=@sf.title.then(@sf.centered)) |> ignore
      c.text(fill("web-pages.security.waitingLead", [("name", here.name)]), style=@sf.lead.then(@sf.centered))
      |> ignore
      pair_steps(c, core, ws)
      // this device's own code: what its approver sees listed (the lock's `me.code`)
      let code = text(me, "code")
      if code != "" {
        c.box(style=@sf.beside, fn() {
          c.text(tr("web-pages.security.thisDevice"), style=@sf.meta.then(@sf.one_line)) |> ignore
          mono(c, code, style=@sf.code.then(@sf.strong).then(@sf.quiet))
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  bar_room_gap(c, nav_foot.val) })
  |> ignore
}

///|
/// The waiting page's column: what it says one under another, centred, a little apart.
// kept across runs: a value (no field of it changes)
let lock_column : @ui.Style = @sf.phone_column.then(@ui.style(gap=S3_5, align=ACenter))

///|
fn note_center(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=@sf.note.then(@sf.centered)) |> ignore
}

///|
fn error_center(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=@sf.error_note.then(@sf.centered)) |> ignore
}

///|
/// The page and the navigation bar's room under it.
// kept across runs: a value (no field of it changes)
let lock_room : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// The page: a phone's width, in the middle of what is over the navigation bar.
// kept across runs: a value (no field of it changes)
let lock_page : @ui.Style = @sf.phone_page.then(@ui.style(h=@sf.grow))

///|
/// Asking to be confirmed (or, in the lock without signing, made a trusted device) and the code typed (Security.kt
/// PairSteps): on the waiting page and on 设置 › 安全.
pub fn pair_steps(c : @ui.Ctx, core : Core, ws : String) -> Unit {
  let lock = (core.topic)("lock", { "workspace": str(ws) }).value
  let me = field(lock, "me")
  let pair = field(me, "pair")
  let state = text(pair, "state")
  let on = [("workspace", ws)]
  let asking = is_doing(core, ["lock.pair"], on)
  let checking = is_doing(core, ["lock.pairCode"], on) || state == "checking"
  let typing = state == "code" || state == "wrong" || state == "checking"
  if typing {
    note_center(c, tr("web-pages.security.pairEnter"))
    let key = "lock-code/" + ws
    // six digits in six boxes, three and three (Security.kt CodeField), handed on once a code typed
    let typed = c.code_field(
      key,
      wrong=state == "wrong",
      enabled=!checking,
      color=c.color(Fg),
      disabled_color=c.color(Muted),
      edge=c.color(@sf.code_edge),
      next_edge=c.color(Fg),
      wrong_edge=c.color(Danger),
    )
    if typed is Some(code) {
      (core.call)("lock.pairCode", obj([("workspace", str(ws)), ("code", str(code))]), fn(r) {
        // a code refused: the boxes empty for the next try
        if r is Err(_) {
          c.clear_code_field(key)
        }
      })
    }
    if checking {
      wait_line(c, tr("web-pages.security.pairChecking"))
    } else if state == "wrong" {
      error_center(c, fill("web-pages.security.pairWrong", [("n", count(pair, "left").to_string())]))
    }
  } else if state == "finding" || asking {
    wait_line(c, tr("web-pages.security.pairFinding"))
  } else {
    match (state, text(me, "failed")) {
      ("none", _) => note_center(c, tr("web-pages.security.pairNone"))
      ("failed", _) => error_center(c, text(pair, "error"))
      (_, "") =>
      note_center(
        c,
        tr(if flag(me, "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" }),
      )
      (_, failed) => error_center(c, fill("web-pages.security.requestFailed", [("error", failed)]))
    }
    if wide_button(c, "lock-pair/" + ws, tr("web-pages.security.request"), true) {
      lock_call(core, ws, "pair", tr("web-pages.security.request"), [])
    }
  }
}
