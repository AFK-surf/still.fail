// What settings' 共享调试 shows of the person's own lock (`adbShare`'s `personal`): the grants from before signatures to
// confirm, and how this device is approved by a device on it (a code it shows, typed in here). To people it is no lock
// of its own: 安全模式, 受信任设备 and 批准 (the user, 2026-11-10); its own page of before, under 安全, is gone and its
// link opens 共享调试. Its devices are 安全's, which takes one off (2026-11-11: 共享调试's list of them went).

///|
/// The grants from before signatures, one tap (and the person asked once) from lending again: where there are any.
fn confirm_row(c : @ui.Ctx, core : Core, view : Json?, blocks : Array[() -> Unit], keys : Array[String]) -> Unit {
  let n = count(view, "toConfirm")
  if n == 0 {
    return
  }
  keys.push("confirm")
  blocks.push(fn() {
    // (what it is for under its title as wide as the card, 确认 at its foot as the page's step has it: not beside them,
    // 2026-11-06 左子健: 不要 title 和 description 都被右边操作给挤压)
    let doing = is_doing(core, ["adb.personalConfirm"], [])
    card(c, foot=UiCapsule, fn() {
      c.box(style=personal_confirm_box, fn() {
        @sf.card_lines(c, fill("android-misc.personal.toConfirm", [("n", n.to_string())]), note=tr("android-misc.personal.toConfirm.note"))
        @sf.card_foot(c, fn() {
          @sf.button(c, tr("android-misc.personal.confirm"), key="personal-confirm-do", tone=Primary, busy=doing, disabled=doing, on_press=fn() {
            act(core, tr("android-misc.personal.confirm"), "adb.personalConfirm", obj([]))
          })
        })
      })
      |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let personal_confirm_box : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
/// Joining the lock `p`, as far as it got: looking for a device on it; where to read the code and the code's boxes
/// (six, on a keypad); what stopped it. `at`: this place's key. `centred`: its words in the middle, as 共享调试's
/// page of that step alone has them (adb_lock_first).
fn personal_join(c : @ui.Ctx, core : Core, p : Json?, at : String, centred? : Bool = false) -> Unit {
  let note = if centred { personal_note_centred } else { @sf.ask_note }
  let pair = field(p, "pair")
  let state = text(pair, "state")
  match state {
    "code" | "wrong" | "checking" => {
      let names = match field(pair, "showing") {
        Some(Array(a)) => a.filter_map(fn(n) { if n is String(s) { Some(s) } else { None } })
        _ => []
      }
      let looks = if names.is_empty() { tr("android-misc.personal.code") } else { fill("android-misc.personal.codeOn", [("device", names.join("、"))]) }
      c.text(if state == "wrong" { text(pair, "error") } else { looks }, style=note) |> ignore
      gap(c, 12.0)
      let typed = c.code_field(
        "personal-code/" + at,
        wrong=state == "wrong",
        enabled=state != "checking",
        color=c.color(Fg),
        disabled_color=c.color(Muted),
        edge=c.color(@sf.code_edge),
        next_edge=c.color(Fg),
        wrong_edge=c.color(Danger),
      )
      if typed is Some(code) {
        (core.call)("adb.personalCode", obj([("code", str(code))]), fn(r) {
          if r is Err(_) {
            c.clear_code_field("personal-code/" + at)
          }
        })
      }
      if text(pair, "untilText") != "" {
        gap(c, 12.0)
        c.text(text(pair, "untilText"), style=note) |> ignore
      }
    }
    "none" => c.text(tr("android-misc.personal.none.found"), style=note) |> ignore
    "failed" => c.text(text(pair, "error"), style=note) |> ignore
    _ => c.text(tr("android-misc.personal.finding"), style=note) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let personal_note_centred : @ui.TextStyle = @sf.ask_note.then(@ui.text_style(center=true))
