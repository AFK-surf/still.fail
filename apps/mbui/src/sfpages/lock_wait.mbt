// A device not yet confirmed in the workspace's safe mode (its lock): what it shows in the workspace's place
// .
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
  // the devices it dials (the core's rows: 2026-11-05, 「到底是哪个设备会弹出来呀？」) on a quiet card, `caption` over
  // it where it says any: a device to a row, its mark (a phone, a computer), which machine, under that its app and
  // when it was last used, or that it shows the code now
  let devices = fn(caption : String, list : Array[Json]) {
    if list.is_empty() {
      return
    }
    c.box(style=lock_devices, fn() {
      if caption != "" {
        note(caption, false)
      }
      c.box(style=lock_devices_card, fn() {
        for d in list {
          let d = Some(d)
          c.box(style=lock_device, fn() {
            @sf.icon(c, lock_device_icon(d), size=lock_device_glyph, color=@sf.theme().p.muted) |> ignore
            c.box(style=@sf.pg_row_words, fn() {
              c.text(text(d, "nameText"), style=lock_device_name) |> ignore
              match text(d, "noteText") {
                "" => ()
                words => c.text(words, style=lock_device_note) |> ignore
              }
            })
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
  if state == "code" || state == "wrong" || state == "checking" {
    note(@sf.t("web-pages.security.pairEnter"), false)
    devices("", dialled.filter(fn(d) { flag(Some(d), "showing") }))
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
      c.box(style=if in_card { lock_actions.then(@sf.foot_reach(@sf.button_height())) } else { lock_actions }, fn() {
        @sf.card_foot_words(on=in_card, fn() {
          @sf.button(c, @sf.t("web-pages.security.pairAgain"), key="lock-pair-again/" + ws, tone=Ghost, on_press=fn() {
            c.clear_code_field(key)
            @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairAgain"), [])
          }) |> ignore
        })
      })
      |> ignore
    }
  } else if state == "finding" || asking {
    note(@sf.t("web-pages.security.pairFinding"), true)
    devices(text(pair, "approversText"), dialled)
    // asked again while it looks: the person opened a trusted device and nothing came up, so it looks again now
    // rather than once its dials run out (2026-11-06 the user: 「直接加个没收到重新申请的按钮」)
    if !asking {
      c.box(style=if in_card { lock_actions.then(@sf.foot_reach(@sf.button_height())) } else { lock_actions }, fn() {
        @sf.card_foot_words(on=in_card, fn() {
          @sf.button(c, @sf.t("web-pages.security.pairRetry"), key="lock-pair-retry/" + ws, tone=Ghost, on_press=fn() {
            @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairRetry"), [])
          }) |> ignore
        })
      })
      |> ignore
    }
  } else {
    match state {
      "none" => {
        note(@sf.t("web-pages.security.pairNone"), false)
        // (which they are: its note has said to open one)
        devices("", dialled)
      }
      "failed" => c.text(text(pair, "error"), style=lock_failed) |> ignore
      _ =>
        note(
          @sf.t(if flag(me, "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" }),
          false,
        )
    }
    // (actions: its row, the button as wide as its words)
    c.box(style=if in_card { lock_actions.then(@sf.foot_reach(@sf.button_height())) } else { lock_actions }, fn() {
      @sf.card_foot_words(on=in_card, fn() {
        @sf.button(c, @sf.t("web-pages.security.request"), key="lock-pair/" + ws, tone=Primary, on_press=fn() {
          @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.request"), [])
        }) |> ignore
      })
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
/// The trusted devices it dials: what to do with them (its note's words) 10 over their card, as wide as the steps.
// kept across runs: a value (no field of it changes)
let lock_devices : @ui.Style = @ui.css("w=Full gap=S2_5 align=ACenter")

///|
/// Their card: a quiet ground over whatever it is on (the page, 设置 › 安全's card), 16 and 12 in, its rows 12 apart;
/// as wide as its rows, no wider than the steps (lock_devices_most, and the room there is).
// kept across runs: a value (no field of it changes)
let lock_devices_card : @ui.Style = @ui.css("px=S4 py=S3 gap=S3 radius=Xl bg=Tint").then(@ui.style(max_w=Fixed(lock_devices_most)))

///|
let lock_devices_most : Double = 412.0

///|
/// A device's row: its mark, 12, its two lines, from the card's start.
// kept across runs: a value (no field of it changes)
let lock_device : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
/// Which machine it is, and what is said of it under that.
// kept across runs: a value (no field of it changes)
let lock_device_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let lock_device_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

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
