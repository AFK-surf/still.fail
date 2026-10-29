// A device not yet confirmed in the workspace's safe mode (its lock): what it shows in the workspace's place
// (cloud/Security.tsx SecurityWaiting, mobile/Security.tsx SecurityWaitingScreen; docs/workspace-lock.md「新设备」).
// Every station of a locked workspace refuses such a device, so its chats would only say they are offline. Nothing is
// asked by itself (the person who will compare the codes asks: 发送批准请求, the core's `lock.pair`); the core finds the
// person's trusted devices, one of them shows a code, it is typed here into six boxes (`lock.pairCode`), and how that
// goes is the lock's `me.pair` (finding, code, checking, wrong, none, failed, done). The shell puts it in the page's
// place while the lock's `me.waiting` says so (@settings.lock_waiting).

///|
/// The page, in the box it is given (the library's waiting page): the shield, 等待批准, what it waits for, then the
/// steps (pair_steps).
pub fn lock_wait_page(c : @ui.Ctx, core : Core, here : @settings.Here) -> Unit {
  @sf.waiting_page(
    c,
    "shield-check",
    @sf.t("web-pages.security.waitingTitle"),
    @sf.t("web-pages.security.waitingLead", args=[("name", here.name)]),
    fn() { pair_steps(c, core, here.workspace) },
  )
}

///|
/// Asking to be confirmed, and the code typed (PairSteps): on the waiting page and on 设置 › 安全. Typing (a trusted
/// device shows a code): 输入… over the six boxes, then 正在核对 (turning), or how many tries are left in red, until when
/// the code holds and 重新获取安全码; finding
/// one, turning; else what is so (none found, why it failed, not asked yet), 发送批准请求 under it (`in_card`: last on
/// a page's card, in its foot corner, concentric with it: @sf.foot_reach).
pub fn pair_steps(c : @ui.Ctx, core : Core, ws : String, in_card? : Bool = false) -> Unit {
  let lock = (core.topic)("lock", { "workspace": Json::string(ws) }).value
  let me = field(lock, "me")
  let pair = field(me, "pair")
  let state = text(pair, "state")
  let on = [("workspace", ws)]
  let asking = @settings.is_doing(core, ["lock.pair"], on)
  let checking = @settings.is_doing(core, ["lock.pairCode"], on) || state == "checking"
  let note = fn(words : String, turning : Bool) {
    c.box(style=lock_note, fn() {
      if turning {
        @sf.spinner(c, size=lock_spin) |> ignore
      }
      c.text(words, style=lock_note_words) |> ignore
    })
    |> ignore
  }
  if state == "code" || state == "wrong" || state == "checking" {
    note(@sf.t("web-pages.security.pairEnter"), false)
    let key = "lock-code/" + ws
    // six boxes, three and three (CodeEntry), handed on once a code is typed; refused, they empty for the next try
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
      (core.call)("lock.pairCode", { "workspace": Json::string(ws), "code": Json::string(code) }, fn(r) {
        if r is Err(_) {
          c.clear_code_field(key)
        }
      })
    }
    if checking {
      note(@sf.t("web-pages.security.pairChecking"), true)
    } else {
      if state == "wrong" {
        c.text(@sf.t("web-pages.security.pairWrong", args=[("n", count(pair, "left").to_string())]), style=lock_failed)
        |> ignore
      }
      // how long the code holds (14:05 前有效), and a new one asked for at any time: the code gone or not read in time,
      // nothing to type before asking again (2026-10-30)
      match text(pair, "untilText") {
        "" => ()
        until => note(until, false)
      }
      c.box(style=if in_card { lock_actions.then(@sf.foot_reach(@sf.button_height())) } else { lock_actions }, fn() {
        if @sf.button(c, @sf.t("web-pages.security.pairAgain"), key="lock-pair-again/" + ws, tone=Ghost) {
          c.clear_code_field(key)
          @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairAgain"), [])
        }
      })
      |> ignore
    }
  } else if state == "finding" || asking {
    note(@sf.t("web-pages.security.pairFinding"), true)
  } else {
    match (state, text(me, "failed")) {
      ("none", _) => note(@sf.t("web-pages.security.pairNone"), false)
      ("failed", _) => c.text(text(pair, "error"), style=lock_failed) |> ignore
      (_, "") =>
        note(
          @sf.t(if flag(me, "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" }),
          false,
        )
      (_, failed) =>
        c.text(@sf.t("web-pages.security.requestFailed", args=[("error", failed)]), style=lock_failed) |> ignore
    }
    // (actions: its row, the button as wide as its words)
    c.box(style=if in_card { lock_actions.then(@sf.foot_reach(@sf.button_height())) } else { lock_actions }, fn() {
      if @sf.button(c, @sf.t("web-pages.security.request"), key="lock-pair/" + ws, tone=Primary) {
        @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.request"), [])
      }
    })
    |> ignore
  }
}

///|
/// What is so (waitingNote: a turning ring 8 before it, muted, the meta's size); why it failed (waitingFailed: red).
// kept across runs: a value (no field of it changes)
let lock_note : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let lock_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let lock_failed : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Danger, center=true)

///|
let lock_spin : Double = 12.0

///|
/// 发送批准请求's row (actions: 10 apart).
// kept across runs: a value (no field of it changes)
let lock_actions : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")
