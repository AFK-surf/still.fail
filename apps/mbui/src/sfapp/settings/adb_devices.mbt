// What settings' 共享调试 shows of the person's own lock (`adbShare`'s `personal`): the devices that approve phone
// debugging, each other one removed here (asked first); the grants from before signatures to confirm; and how this
// device is approved by one of them (a code it shows, typed in here). To people it is no lock of its own: 安全模式,
// 受信任设备 and 批准 (the user, 2026-11-10); its own page of before, under 安全, is gone and its link opens 共享调试.

///|
/// The devices that approve phone debugging, of each account whose lock this device is on (`personal`'s `member`):
/// a header (its email where there are several), a row each with its name, 这台设备 on this one's, 移除 on every
/// other's, which asks first (as 安全's removing a device does: remove_dialog).
fn adb_devices(c : @ui.Ctx, core : Core, view : Json?, blocks : Array[() -> Unit], keys : Array[String]) -> Unit {
  let mine = items(view, "personal").filter(fn(l) { text(Some(l), "standing") == "member" })
  for lock in mine {
    let p = Some(lock)
    let sub = text(p, "sub")
    keys.push("devices-heading/" + sub)
    blocks.push(fn() {
      section_header(c, if mine.length() > 1 { text(p, "email") } else { tr("android-misc.adb.devices") }, start=S6)
    })
    keys.push("devices/" + sub)
    blocks.push(fn() { adb_devices_card(c, core, p) })
  }
}

///|
/// The devices on the lock `p` this device is on, a row each.
fn adb_devices_card(c : @ui.Ctx, core : Core, p : Json?) -> Unit {
  let said = str(text(p, "sub"))
  let doing = is_doing(core, ["adb.personalRemove"], [])
  list_card(c, fn() {
    for d in items(p, "devices") {
      let d = Some(d)
      let key = text(d, "key")
      let me = flag(d, "me")
      let name = if text(d, "label") == "" { tr("android-misc.personal.me") } else { text(d, "label") }
      list_row(c, key="personal/" + key, fn() {
        c.box(style=fill_words, fn() {
          row_lines(c, name, if me { tr("android-misc.personal.me") } else { "" }, wrap_sub=true)
        })
        |> ignore
        if !me {
          @sf.button(c, tr("android-misc.personal.remove"), key="personal-remove/" + key, tone=Ghost, busy=doing, disabled=doing, on_press=fn() {
            @sf.confirm(
              fill("web-pages.security.removeTitle", [("name", name)]),
              tr("android-misc.adb.devices.removeBody"),
              tr("web-pages.security.remove"),
              danger=true,
              fn() { act(core, tr("android-misc.personal.remove"), "adb.personalRemove", obj([("sub", said), ("key", str(key))])) },
            )
          })
        }
      })
      |> ignore
    }
  })
}

///|
/// The grants from before signatures, one tap (and the person asked once) from lending again: where there are any.
fn confirm_row(c : @ui.Ctx, core : Core, view : Json?, blocks : Array[() -> Unit], keys : Array[String]) -> Unit {
  let n = count(view, "toConfirm")
  if n == 0 {
    return
  }
  keys.push("confirm")
  blocks.push(fn() {
    // (what it is for under its title as wide as the card, 确认 at its foot as 本机设置's step has it: not beside them,
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
