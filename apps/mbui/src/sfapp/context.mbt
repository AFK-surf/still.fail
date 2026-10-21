// An agent's context by hand, between turns (ember apps/android chat/screens/AgentSheet.kt ContextRow, openContext): one
// row in the agent's card, how full it is, opening a sheet that compacts it (its chat is told when it is done) or clears
// it (asked first in a sheet of its own, PageParts.kt confirm): its next message starts a new session.

///|
/// What is under way or failed of `call` on `key`'s session (the core's doing, as AppState.isDoing has it).
fn context_key(call : String, station : String, key : String) -> String {
  call + "/" + station + "/" + key
}

///|
/// The card's row for its context (canCompact, canClear; AgentSheet.kt ContextRow): how full it is (`used`), and a tap
/// opens what can be done to it; under way a spinner, failed its mark.
fn context_row(c : @ui.Ctx, r : ChatRef, key : String, s : Json?, used : String) -> Unit {
  if !flag(s, "canCompact") && !flag(s, "canClear") {
    return
  }
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  let busy = doing(compacting) || doing(clearing)
  let failed = failed_lately(c, compacting) || failed_lately(c, clearing)
  if info_row(c, if busy { "" } else { "agent/context" }, fn() {
      c.text(tr("web-pages.chat.context"), style=context_label) |> ignore
      c.box(style=context_used_box, fn() { c.text(used, style=context_used) |> ignore }) |> ignore
      if busy || failed {
        @settings.doing_mark(c, busy, if failed { Some("") } else { None })
      } else {
        chevron(c)
      }
    }) {
    open_sheet(c, ContextOf(r, key))
  }
}

///|
/// What can be done to its context by hand (AgentSheet.kt openContext), in the card's place: compacted, or cleared
/// (asked first in a sheet of its own).
fn context_sheet(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  let s = field(agent_json((src.topic)("chat", chat_params(r)).value, key), "session")
  sheet_frame(c, "context", c.height * 0.34, fn() {
    sheet_head(c, tr("web-pages.chat.context"))
    if flag(s, "canCompact") &&
      @settings.pick_row(c, "context/compact", tr("web-pages.chat.compact"), sub=tr("web-mobile.agent.compactSub")) {
      close_sheet(c)
      let params : Json = { "station": Json::string(r.station), "key": Json::string(key) }
      // told once the frame's builds are over, not while this one builds
      c.after_build("context/compact", fn() {
        act(src, tr("web-pages.chat.compact"), context_key("session.compact", r.station, key), "session.compact", params, done=tr("web-mobile.agent.compacting"))
      })
    }
    if flag(s, "canClear") &&
      @settings.pick_row(c, "context/clear", tr("web-pages.chat.clear"), sub=tr("web-mobile.agent.clearSub"), color=@sf.theme().p.red) {
      open_sheet(c, ClearContext(r, key))
    }
  })
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
/// The row's name (muted) and how full it is (the ink), the rest of the row the latter's (AgentSheet.kt ContextRow: 14).
// kept across runs: a value (no field of it changes)
let context_label : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let context_used : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let context_used_box : @ui.Style = @ui.style(w=Full)

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
