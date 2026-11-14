// A device not yet confirmed in the workspace's safe mode (its lock): what it shows in the workspace's place
// .
// Every station of a locked workspace refuses such a device, so its chats would only say they are offline. Nothing is
// asked by itself (the person who will compare the codes asks: 发送批准请求, the core's `lock.pair`); the core finds the
// person's trusted devices, one of them shows a code, it is typed here into six boxes (`lock.pairCode`), and how that
// goes is the lock's `me.pair` (finding, code, checking, wrong, none, failed, done). The shell puts it in the page's
// place while the lock's `me.waiting` says so, or its `me.needsAppText` (a web page nobody can approve there, which
// says only that: @settings.lock_waiting).

///|
/// The page, in the box it is given (the library's waiting page): the shield, 等待批准, what it waits for, then the
/// steps (pair_steps).
pub fn lock_wait_page(c : @ui.Ctx, core : Core, here : @settings.Here) -> Unit {
  // (a web page nobody can approve here: 请先安装客户端 and the core's words alone, lock_wait_node's)
  let needs = @settings.lock_needs_app(core, here.workspace)
  @sf.waiting_page(
    c,
    "shield-check",
    @sf.t(if needs != "" { "web-pages.security.needsAppTitle" } else { "web-pages.security.waitingTitle" }),
    if needs != "" { needs } else { @sf.t("web-pages.security.waitingLead", args=[("name", here.name)]) },
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
  let lock = (core.topic)("lock", { "workspace": Json::string(ws) }).get().value
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
  // a web page nobody can approve here (the core's `me.needsAppText`, the page's lead): nothing to ask (no one could
  // answer)
  if text(me, "needsAppText") != "" {
    return
  }
  // the devices it dials (the core's rows: 2026-11-05, 「到底是哪个设备会弹出来呀？」) on a quiet card under the step's
  // action, a device to a row, its mark (a phone, a computer) and which machine (the user, #4213, 2026-11-10: fewer
  // words, and under the buttons, which matter more and are never pushed out by it); on 设置 › 安全's card its rows
  // alone, from where the card's words start (a ground of their own in its foot corner would not follow it)
  let devices = fn(list : Array[Json]) {
    if list.is_empty() {
      return
    }
    c.box(style=if in_card { lock_devices_carded } else { lock_devices }, fn() {
      c.box(style=if in_card { lock_devices_rows } else { lock_devices_card }, fn() {
        for d in list {
          let d = Some(d)
          c.box(style=lock_device, fn() {
            @sf.icon(c, lock_device_icon(d), size=lock_device_glyph, color=@sf.theme().p.muted) |> ignore
            c.box(style=@sf.pg_row_words, fn() { c.text(text(d, "nameText"), style=lock_device_name) |> ignore })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  }
  let dialled = items(pair, "approvers")
  // (a step's action, its row, the button as wide as its words, then the devices the step is about; `in_card` the
  // row reaches the card's foot corner where it is last, and only its sides, the words where the card's are, where the
  // devices come under it)
  let action = fn(list : Array[Json], button : () -> Unit) {
    let reach = if !in_card {
      lock_actions
    } else if list.is_empty() {
      lock_actions.then(@sf.foot_reach(@sf.button_height()))
    } else {
      lock_actions.then(@sf.over_foot_reach(@sf.button_height()))
    }
    c.box(style=reach, fn() { @sf.card_foot_words(on=in_card, button) }) |> ignore
    devices(list)
  }
  let showing = dialled.filter(fn(d) { flag(Some(d), "showing") })
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
        match r {
          Err(_) => c.clear_code_field(key)
          // (approved, but no station took it yet: its sentence said, the code cleared)
          Ok(v) if @settings.pending_said(v) != "" => {
            c.clear_code_field(key)
            (core.say)(@settings.pending_said(v))
          }
          Ok(_) => ()
        }
      })
    }
    if checking {
      note(@sf.t("web-pages.security.pairChecking"), true)
      devices(showing)
    } else {
      if state == "wrong" {
        // what the core says of it (the device showing the code may be gone); a core of before says nothing
        let said = match text(pair, "error") {
          "" => @sf.t("web-pages.security.pairWrong", args=[("n", count(pair, "left").to_string())])
          words => words
        }
        c.text(said, style=lock_failed) |> ignore
      }
      // how long the code holds (14:05 前有效), and a new one asked for at any time: the code gone or not read in time,
      // nothing to type before asking again (2026-10-30)
      match text(pair, "untilText") {
        "" => ()
        until => note(until, false)
      }
      // (which of them show it)
      action(showing, fn() {
        @sf.button(c, @sf.t("web-pages.security.pairAgain"), key="lock-pair-again/" + ws, tone=Ghost, on_press=fn() {
          c.clear_code_field(key)
          @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairAgain"), [])
        }) |> ignore
      })
    }
  } else if state == "finding" || asking {
    note(@sf.t("web-pages.security.pairFinding"), true)
    // asked again while it looks: the person opened a trusted device and nothing came up, so it looks again now
    // rather than once its dials run out (2026-11-06 the user: 「直接加个没收到重新申请的按钮」)
    if asking {
      devices(dialled)
    } else {
      action(dialled, fn() {
        @sf.button(c, @sf.t("web-pages.security.pairRetry"), key="lock-pair-retry/" + ws, tone=Ghost, on_press=fn() {
          @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairRetry"), [])
        }) |> ignore
      })
    }
  } else {
    match state {
      "none" => note(@sf.t("web-pages.security.pairNone"), false)
      "failed" => c.text(text(pair, "error"), style=lock_failed) |> ignore
      _ =>
        note(
          @sf.t(if flag(me, "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" }),
          false,
        )
    }
    // (none found: which they are, its note having said to open one)
    action(if state == "none" { dialled } else { [] }, fn() {
      @sf.button(c, @sf.t("web-pages.security.request"), key="lock-pair/" + ws, tone=Primary, on_press=fn() {
        @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.request"), [])
      }) |> ignore
    })
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
/// The trusted devices it dials: their card's place, in the middle under the step's action.
// kept across runs: a value (no field of it changes)
let lock_devices : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// On 设置 › 安全's card: from where the card's words start.
// kept across runs: a value (no field of it changes)
let lock_devices_carded : @ui.Style = @ui.css("w=Full align=AStart")

///|
/// Their card: a quiet ground over whatever it is on (the page, 设置 › 安全's card), 16 and 12 in, its rows 12 apart;
/// as wide as its rows, no wider than the steps (lock_devices_most, and the room there is).
// kept across runs: a value (no field of it changes)
let lock_devices_card : @ui.Style = @ui.css("px=S4 py=S3 gap=S3 radius=Xl bg=Tint").then(@ui.style(max_w=Fixed(lock_devices_most)))

///|
/// On 设置 › 安全's card: the rows, no ground of their own.
// kept across runs: a value (no field of it changes)
let lock_devices_rows : @ui.Style = @ui.css("gap=S3")

///|
let lock_devices_most : Double = 412.0

///|
/// A device's row: its mark, 12, which machine it is, from the card's start.
// kept across runs: a value (no field of it changes)
let lock_device : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let lock_device_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
let lock_device_glyph : Double = 18.0

///|
/// A device's mark by what the core says it is (LockApprover `kind`): a phone, else a computer.
fn lock_device_icon(d : Json?) -> String {
  if text(d, "kind") == "phone" {
    "phone"
  } else {
    "monitor"
  }
}

///|
/// 发送批准请求's row (actions: 10 apart).
// kept across runs: a value (no field of it changes)
let lock_actions : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")
