// 个人锁 (docs/personal-lock.md), a page of settings' 安全: which devices of the person's sign for them, on any app (a phone
// or a computer alike). Joining it is one step wherever it comes up (`personal_join`: a request's card too); this page is
// where the devices are seen and taken off. What it has to say comes on the core's `adbShare`.

///|
pub fn personal_lock_page(c : @ui.Ctx, core : Core) -> Unit {
  let view = (core.topic)("adbShare", Map([])).value
  let locks = items(view, "personal")
  c.box(style=adb_whole, fn() {
    nav_bar(c, core, tr("android-misc.personal.back"), tr("android-misc.personal.heading"), about=tr("android-misc.personal.about"))
    let blocks : Array[() -> Unit] = [fn() { gap(c, 12.0) }]
    let keys = ["head"]
    confirm_row(c, core, view, blocks, keys)
    for lock in locks {
      let p = Some(lock)
      keys.push("lock/" + text(p, "sub"))
      blocks.push(fn() {
        if locks.length() > 1 {
          section_header(c, text(p, "email"), start=S6)
        }
        personal_card(c, core, p)
      })
    }
    keys.push("foot")
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "personal-lock/", blocks, keys~, moves=true, continuity=fn(_) { view is Some(_) })
  })
  |> ignore
}

///|
/// The lock of account `sub`, of `adbShare`'s `personal`.
fn personal_of(view : Json?, sub : String) -> Json? {
  items(view, "personal").iter().find_first(fn(p) { text(Some(p), "sub") == sub })
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
    list_card(c, fn() {
      let doing = is_doing(core, ["adb.personalConfirm"], [])
      list_row(c, key="personal-confirm", fn() {
        c.box(style=fill_words, fn() { row_lines(c, fill("android-misc.personal.toConfirm", [("n", n.to_string())]), tr("android-misc.personal.toConfirm.note"), wrap_sub=true) })
        |> ignore
        if @sf.button(c, tr("android-misc.personal.confirm"), key="personal-confirm-do", tone=Primary, busy=doing, disabled=doing) {
          act(core, tr("android-misc.personal.confirm"), "adb.personalConfirm", obj([]))
        }
      })
      |> ignore
    })
  })
}

///|
/// Joining the lock `p`, as far as it got: looking for a device on it; where to read the code and the code's boxes
/// (six, on a keypad); what stopped it. `at`: this place's key.
fn personal_join(c : @ui.Ctx, core : Core, p : Json?, at : String) -> Unit {
  let pair = field(p, "pair")
  let state = text(pair, "state")
  match state {
    "code" | "wrong" | "checking" => {
      let names = match field(pair, "showing") {
        Some(Array(a)) => a.filter_map(fn(n) { if n is String(s) { Some(s) } else { None } })
        _ => []
      }
      let looks = if names.is_empty() { tr("android-misc.personal.code") } else { fill("android-misc.personal.codeOn", [("device", names.join("、"))]) }
      c.text(if state == "wrong" { text(pair, "error") } else { looks }, style=@sf.ask_note) |> ignore
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
        c.text(text(pair, "untilText"), style=@sf.ask_note) |> ignore
      }
    }
    "none" => c.text(tr("android-misc.personal.none.found"), style=@sf.ask_note) |> ignore
    "failed" => c.text(text(pair, "error"), style=@sf.ask_note) |> ignore
    _ => c.text(tr("android-misc.personal.finding"), style=@sf.ask_note) |> ignore
  }
}

///|
/// The lock as this device has it: the devices on it, or how this one joins it.
fn personal_card(c : @ui.Ctx, core : Core, view : Json?) -> Unit {
  let sub = text(view, "sub")
  let doing = is_doing(core, ["adb.personalJoin", "adb.personalCode", "adb.personalRemove", "adb.personalForget", "adb.personalRestart"], [])
  let said = str(sub)
  list_card(c, fn() {
    match text(view, "standing") {
      "member" =>
        for d in items(view, "devices") {
          let d = Some(d)
          let key = text(d, "key")
          let me = flag(d, "me")
          let name = text(d, "label")
          list_row(c, key="personal/" + key, fn() {
            c.box(style=fill_words, fn() {
              row_lines(c, if name == "" { tr("android-misc.personal.me") } else { name }, if me { tr("android-misc.personal.me") } else { "" }, wrap_sub=true)
            })
            |> ignore
            if !me && @sf.button(c, tr("android-misc.personal.remove"), key="personal-remove/" + key, tone=Ghost, busy=doing, disabled=doing) {
              act(core, tr("android-misc.personal.remove"), "adb.personalRemove", obj([("sub", said), ("key", str(key))]))
            }
          })
          |> ignore
        }
      "outside" => {
        let state = text(field(view, "pair"), "state")
        if state == "" || state == "none" || state == "failed" || state == "done" {
          if @sf.link_row(c, "personal-join/" + sub, tr("android-misc.personal.join"), note=if state == "" { tr("android-misc.personal.outside.note") } else { "" }, lacks=true) && !doing {
            (core.call)("adb.personalJoin", obj([("sub", said)]), fn(_) {  })
          }
        }
        if state != "" && state != "done" {
          list_row(c, key="personal-pair/" + sub, fn() {
            c.box(style=fill_words, fn() { personal_join(c, core, view, sub) }) |> ignore
          })
          |> ignore
        }
        // (no device of theirs to be found: only then)
        if state == "none" || state == "failed" {
          if @sf.link_row(c, "personal-restart/" + sub, tr("android-misc.personal.restart"), note=tr("android-misc.personal.restart.note"), lacks=false) && !doing {
            act(core, tr("android-misc.personal.restart"), "adb.personalRestart", obj([("sub", said)]))
          }
        }
      }
      "replaced" => {
        list_row(c, key="personal-replaced/" + sub, fn() {
          c.box(style=fill_words, fn() { row_lines(c, tr("android-misc.personal.replaced"), tr("android-misc.personal.replaced.note"), wrap_sub=true) }) |> ignore
        })
        |> ignore
        if @sf.link_row(c, "personal-forget/" + sub, tr("android-misc.personal.forget"), lacks=false) && !doing {
          act(core, tr("android-misc.personal.forget"), "adb.personalForget", obj([("sub", said)]))
        }
      }
      _ =>
        list_row(c, key="personal-none/" + sub, fn() {
          c.box(style=fill_words, fn() { row_lines(c, tr("android-misc.personal.heading"), tr("android-misc.personal.none"), wrap_sub=true) }) |> ignore
        })
        |> ignore
    }
  })
}
