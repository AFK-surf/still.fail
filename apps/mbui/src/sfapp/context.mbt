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
  let t = @sf.theme()
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  // neither while one is under way
  let either = doing(compacting) || doing(clearing)
  let row = fn(name : String, call_key : String, label : String) -> Bool {
    let busy = doing(call_key)
    let failed = failed_lately(c, call_key)
    info_row(c, if either { "" } else { "agent/" + name }, fn() {
      c.box(w=Fill(1.0), fn() {
        c.text(label, size=14.0, color=t.p.text, wrap=false) |> ignore
      })
      |> ignore
      if busy || failed {
        @settings.doing_mark(c, busy, if failed { Some("") } else { None })
      }
    })
  }
  let params = { "station": Json::string(r.station), "key": Json::string(key) }
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
  let t = @sf.theme()
  sheet_frame(c, "clear-context", c.height * 0.36, fn() {
    sheet_head(c, tr("web-pages.chat.clearConfirm"))
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      c.text(tr("web-pages.chat.clearBody"), size=14.0, color=t.p.muted, line=20.0) |> ignore
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
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
