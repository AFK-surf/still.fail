// Pairing steps shared by the waiting page and the security page's card.

///|
/// Pair with a trusted device in the current workspace. A new workspace gets its own input and callbacks; a late
/// answer cannot clear the new workspace's field. In a card, the last button reaches its foot corners.
pub fn pair_steps_node(
  parent : @view.View,
  core : () -> Core,
  workspace : () -> String,
  in_card? : Bool = false,
) -> Unit {
  parent.pick(workspace, fn(col, ws) {
    col.width_share(Is(1.0)).gap(Is(@ui.Space::px(S3_5))) |> ignore
    if !in_card { col.lines_up(Is(Some(Middle))) |> ignore }
    let me = fn() { field(((core()).topic)("lock", { "workspace": Json::string(ws) }).value, "me") }
    let pair = fn() { field(me(), "pair") }
    let state = fn() { text(pair(), "state") }
    let on = [("workspace", ws)]
    let asking = fn() { @settings.is_doing(core(), ["lock.pair"], on) }
    let checking = fn() { @settings.is_doing(core(), ["lock.pairCode"], on) || state() == "checking" }
    // The field stays the same while code, wrong and checking replace one another.
    let step = fn() {
      let s = state()
      if s == "code" || s == "wrong" || s == "checking" {
        0
      } else if s == "finding" || asking() {
        1
      } else {
        2
      }
    }
    col.pick(step, fn(part, which) {
      part.width_share(Is(1.0)).gap(Is(@ui.Space::px(S3_5))) |> ignore
      if !in_card { part.lines_up(Is(Some(Middle))) |> ignore }
      if which == 0 {
        lock_note_node(part, fn() { @sf.t("web-pages.security.pairEnter") }, false)
        let code = @ui.CodeField::new()
        let attempt = Ref(0)
        @ui.code_field_node(
          part,
          code,
          fn(value) {
            attempt.val += 1
            let sent = attempt.val
            ((core()).call)("lock.pairCode", { "workspace": Json::string(ws), "code": Json::string(value) }, fn(r) {
              if r is Err(_) && part.alive() && sent == attempt.val && code.text() == value {
                code.clear()
              }
            })
          },
          wrong=fn() { state() == "wrong" },
          enabled=fn() { !checking() },
          color=fn() { @ui.tree_theme().color(Fg) },
          disabled_color=fn() { @ui.tree_theme().color(Muted) },
          edge=fn() { @ui.tree_theme().color(@sf.code_edge) },
          next_edge=fn() { @ui.tree_theme().color(Fg) },
          wrong_edge=fn() { @ui.tree_theme().color(Danger) },
        )
        |> ignore
        part.show(checking, fn(s) {
          lock_note_node(s, fn() { @sf.t("web-pages.security.pairChecking") }, true)
        })
        part.show(fn() { !checking() }, fn(s) {
          s.gap(Is(@ui.Space::px(S3_5))) |> ignore
          if !in_card { s.lines_up(Is(Some(Middle))) |> ignore }
          s.show(fn() { state() == "wrong" }, fn(e) {
            @sf.words_node(e, fn() {
              match text(pair(), "error") {
                "" => @sf.t("web-pages.security.pairWrong", args=[("n", count(pair(), "left").to_string())])
                words => words
              }
            }, fn() { lock_failed }).words_centered(Is(true))
            |> ignore
          })
          s.show(fn() { text(pair(), "untilText") != "" }, fn(u) {
            lock_note_node(u, fn() { text(pair(), "untilText") }, false)
          })
          lock_action_node(s, in_card, fn() { @sf.t("web-pages.security.pairAgain") }, Ghost, fn() {
            attempt.val += 1
            code.clear()
            @settings.lock_call(core(), ws, "pair", @sf.t("web-pages.security.pairAgain"), [])
          })
        })
      } else if which == 1 {
        lock_note_node(part, fn() { @sf.t("web-pages.security.pairFinding") }, true)
        part.show(fn() { !asking() }, fn(s) {
          lock_action_node(s, in_card, fn() { @sf.t("web-pages.security.pairRetry") }, Ghost, fn() {
            @settings.lock_call(core(), ws, "pair", @sf.t("web-pages.security.pairRetry"), [])
          })
        })
      } else {
        part.show(fn() { state() == "failed" }, fn(e) {
          @sf.words_node(e, fn() { text(pair(), "error") }, fn() { lock_failed }).words_centered(Is(true)) |> ignore
        })
        part.show(fn() { state() != "failed" }, fn(n) {
          lock_note_node(n, fn() {
            match state() {
              "none" => @sf.t("web-pages.security.pairNone")
              _ => @sf.t(if flag(me(), "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" })
            }
          }, false)
        })
        lock_action_node(part, in_card, fn() { @sf.t("web-pages.security.request") }, Primary, fn() {
          @settings.lock_call(core(), ws, "pair", @sf.t("web-pages.security.request"), [])
        })
      }
    })
  })
}

///|
/// A last action reaches a card's foot; on the waiting page it stays in the centred column.
fn lock_action_node(parent : @view.View, in_card : Bool, label : () -> String, tone : @sf.Tone, press : () -> Unit) -> Unit {
  if in_card {
    @sf.ask_buttons_node(parent, fn(row) { @sf.button_node(row, label, press, tone~, at_foot=true) |> ignore }) |> ignore
  } else {
    parent.box(fn(row) {
      row.row(Is(true)).gap(Is(@ui.Space::px(S2_5))).lines_up(Is(Some(Middle))) |> ignore
      @sf.button_node(row, label, press, tone~) |> ignore
    })
    |> ignore
  }
}

///|
/// A muted note, with a turning ring before it while the lock is working.
fn lock_note_node(parent : @view.View, words : () -> String, turning : Bool) -> Unit {
  parent.box(fn(row) {
    row.row(Is(true)).gap(Is(@ui.Space::px(S2))).lines_up(Is(Some(Middle))) |> ignore
    if turning { @sf.spinner_node(row, size=lock_spin) |> ignore }
    @sf.words_node(row, words, fn() { lock_note_words }).words_centered(Is(true)) |> ignore
  })
  |> ignore
}
