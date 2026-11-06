// 个人锁 (docs/personal-lock.md), a page of settings' 安全: which devices of the person's sign for them, on any app (a phone
// or a computer alike: what lets one allow a chat's request for their phone). What it has to say comes on the core's
// `adbShare`.

///|
pub fn personal_lock_page(c : @ui.Ctx, core : Core) -> Unit {
  let view = (core.topic)("adbShare", Map([])).value
  c.box(style=adb_whole, fn() {
    nav_bar(c, core, tr("android-misc.personal.back"), tr("android-misc.personal.heading"), about=tr("android-misc.personal.about"))
    scroll_page(c, "personal-lock/", [fn() { gap(c, 12.0) }, fn() { personal_card(c, core, field(view, "personal")) }, fn() { gap(c, 30.0) }], keys=["head", "lock", "foot"], moves=true, continuity=fn(_) { view is Some(_) })
  })
  |> ignore
}

///|
/// The lock as this device has it: the devices on it, or how this one joins it. What joins is proved by the code another
/// device on it shows.
fn personal_card(c : @ui.Ctx, core : Core, view : Json?) -> Unit {
  let doing = is_doing(core, ["adb.personalJoin", "adb.personalCode", "adb.personalRemove", "adb.personalForget", "adb.personalRestart"], [])
  let say_row = fn(title : String, note : String) {
    list_row(c, fn() { c.box(style=fill_words, fn() { row_lines(c, title, note, wrap_sub=true) }) |> ignore }) |> ignore
  }
  let ask_restart = fn() {
    if @sf.link_row(c, "personal-restart", tr("android-misc.personal.restart"), note=tr("android-misc.personal.restart.note"), lacks=false) && !doing {
      act(core, tr("android-misc.personal.restart"), "adb.personalRestart", obj([]))
    }
  }
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
              act(core, tr("android-misc.personal.remove"), "adb.personalRemove", obj([("key", str(key))]))
            }
          })
          |> ignore
        }
      "outside" => {
        let pair = field(view, "pair")
        let state = text(pair, "state")
        match state {
          "finding" | "checking" => say_row(tr("android-misc.personal.outside"), tr("android-misc.personal.finding"))
          "code" | "wrong" => {
            say_row(tr("android-misc.personal.outside"), if state == "wrong" { text(pair, "error") } else { tr("android-misc.personal.code") })
            if @sf.link_row(c, "personal-code", tr("android-misc.personal.code"), note=text(pair, "untilText"), lacks=true) {
              ask(tr("android-misc.personal.code"), "", "000000", tr("android-misc.personal.join"), fn(code) {
                act(core, tr("android-misc.personal.code"), "adb.personalCode", obj([("code", str(code))]))
              })
            }
          }
          _ => {
            let note = match state {
              "none" => tr("android-misc.personal.none.found")
              "failed" => text(pair, "error")
              _ => tr("android-misc.personal.outside.note")
            }
            if @sf.link_row(c, "personal-join", tr("android-misc.personal.join"), note~, lacks=true) && !doing {
              act(core, tr("android-misc.personal.join"), "adb.personalJoin", obj([]))
            }
            ask_restart()
          }
        }
      }
      "replaced" => {
        say_row(tr("android-misc.personal.replaced"), tr("android-misc.personal.replaced.note"))
        if @sf.link_row(c, "personal-forget", tr("android-misc.personal.forget"), lacks=false) && !doing {
          act(core, tr("android-misc.personal.forget"), "adb.personalForget", obj([]))
        }
      }
      _ => say_row(tr("android-misc.personal.heading"), tr("android-misc.personal.none"))
    }
  })
}

