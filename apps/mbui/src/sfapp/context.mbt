// An agent's context by hand, between turns (ember apps/android chat/screens/AgentSheet.kt ContextRow): its rows in the
// agent's card, compacting it (its chat is told when it is done) and clearing it (asked first in a sheet of its own,
// PageParts.kt confirm): its next message starts a new conversation.

///|
/// What is under way or failed of `call` on `key`'s session (the core's doing, as AppState.isDoing has it).
fn context_key(call : String, station : String, key : String) -> String {
  call + "/" + station + "/" + key
}

///|
/// The card's rows for its context (canCompact, canClear): its words; under way a spinner, failed its mark.
fn context_rows(c : @ui.Ctx, src : Source, r : ChatRef, key : String, s : Json?) -> Unit {
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  // neither while one is under way
  let either = doing(compacting) || doing(clearing)
  let row = fn(name : String, call_key : String, label : String) -> Bool {
    let busy = doing(call_key)
    let failed = failed_lately(c, call_key)
    info_row(c, if either { "" } else { "agent/" + name }, fn() {
      c.box(style=context_label_box, fn() { c.text(label, style=context_label) |> ignore }) |> ignore
      if busy || failed {
        @settings.doing_mark(c, busy, if failed { Some("") } else { None })
      }
    })
  }
  let params : Json = { "station": Json::string(r.station), "key": Json::string(key) }
  if flag(s, "canCompact") && row("compact", compacting, tr("web-pages.chat.compact")) {
    // told once the frame's builds are over, not while this one builds
    c.after_build("context/compact", fn() {
      act(src, tr("web-pages.chat.compact"), compacting, "session.compact", params, done=tr("web-mobile.agent.compacting"))
    })
  }
  if flag(s, "canClear") && row("clear", clearing, tr("web-pages.chat.clear")) {
    open_sheet(c, ClearContext(r, key))
  }
}

///|
/// Asks before its context is cleared (PageParts.kt confirm, with `what`): the sheet goes as it is answered, the row
/// shows it under way, a failure said by a toast.
fn clear_context_sheet(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  sheet_frame(c, "clear-context", c.height * 0.36, fn() {
    sheet_head(c, tr("web-pages.chat.clearConfirm"))
    c.box(style=clear_context_body, fn() {
      c.text(tr("web-pages.chat.clearBody"), style=clear_context_words) |> ignore
      c.box(style=clear_context_actions, fn() {
        if sheet_button(c, "clear-context/cancel", tr("common.cancel"), false, true) {
          close_sheet(c)
        }
        if sheet_button(c, "clear-context/clear", tr("web-pages.chat.clear"), true, true) {
          close_sheet(c)
          c.after_build("context/clear", fn() {
            act(
              src,
              tr("web-pages.chat.clear"),
              context_key("session.clear", r.station, key),
              "session.clear",
              { "station": Json::string(r.station), "key": Json::string(key) },
            )
          })
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A row's words, the rest of the row theirs (AgentSheet.kt ContextRow: 14, the ink).
// kept across runs: a value (no field of it changes)
let context_label : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let context_label_box : @ui.Style = @ui.style(w=Full)

///|
/// The sheet that asks (PageParts.kt confirm): 20 in from its sides, its words muted (14/20), its buttons at the end.
// kept across runs: a value (no field of it changes)
let clear_context_body : @ui.Style = @ui.style(w=Full, px=S5, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let clear_context_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let clear_context_actions : @ui.Style = @ui.style(row=true, w=Full, pt=S1_5, pb=S6, gap=S2, justify=JEnd)
