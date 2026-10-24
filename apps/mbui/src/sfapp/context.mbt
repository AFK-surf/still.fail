// An agent's context by hand, between turns (ember apps/android chat/screens/AgentSheet.kt ContextEntry, openContext):
// its context's tile in the agent's card opens a sheet that compacts it (its chat is told when it is done) or clears it
// (asked first in a sheet of its own, PageParts.kt confirm): its next message starts a new session.

///|
/// What is under way or failed of `call` on `key`'s session (the core's doing, as AppState.isDoing has it).
fn context_key(call : String, station : String, key : String) -> String {
  call + "/" + station + "/" + key
}

///|
/// What can be done to its context from its tile (AgentSheet.kt ContextEntry): opens it; under way or failed, said
/// where the tile's › is; `compacts`: it can be compacted.
priv struct ContextTile {
  open : () -> Unit
  busy : Bool
  failed : Bool
  compacts : Bool
}

///|
/// The card's entry for its context (canCompact, canClear), none when nothing can be done to it.
fn context_entry(c : @ui.Ctx, r : ChatRef, key : String, s : Json?) -> ContextTile? {
  if !flag(s, "canCompact") && !flag(s, "canClear") {
    return None
  }
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  Some({
    open: fn() { open_sheet(c, ContextOf(r, key)) },
    busy: doing(compacting) || doing(clearing),
    failed: failed_lately(c, compacting) || failed_lately(c, clearing),
    compacts: flag(s, "canCompact"),
  })
}

///|
/// Its tile's name: that it can be compacted said once the context is filling up (amber or red), not before.
fn context_tile_label(entry : ContextTile?, level : String) -> String {
  match entry {
    Some(e) if e.compacts && (level == "amber" || level == "red") => tr("web-mobile.agent.contextCompactable")
    _ => tr("android-chat.agent.context")
  }
}

///|
/// A tile's name under its figure (12/16, muted); its context's ending in › when something can be done to it, or a
/// spinner, or the failure's mark.
fn context_tile_name(c : @ui.Ctx, name : String, open : ContextTile?) -> Unit {
  match open {
    None => c.text(name, style=tile_name) |> ignore
    Some(o) =>
      c.box(style=tile_name_row, fn() {
        c.text(name, style=tile_name) |> ignore
        if o.busy || o.failed {
          @settings.doing_mark(c, o.busy, if o.failed { Some("") } else { None })
        } else {
          @sf.icon(c, "chevron-right", size=11.0, color=@sf.theme().p.muted) |> ignore
        }
      })
      |> ignore
  }
}

///|
/// What can be done to its context by hand (AgentSheet.kt openContext), in the card's place: compacted, or cleared
/// (asked first in a sheet of its own).
fn context_sheet(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  let s = field(agent_json((src.topic)("chat", chat_params(r)).value, key), "session")
  sheet_frame(c, "context", c.height * 0.34, fit=true, fn() {
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
  sheet_frame(c, "clear-context", c.height * 0.36, fit=true, fn() {
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
/// A tile's name (AgentSheet.kt AgentTiles: 12/16, muted), and its name with its › side by side.
// kept across runs: a value (no field of it changes)
let tile_name : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_name_row : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
/// The sheet that asks (PageParts.kt confirm): 20 in from its sides, its words muted (14/20), its buttons at the end.
// kept across runs: a value (no field of it changes)
let clear_context_body : @ui.Style = @ui.css("w=Full px=S5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let clear_context_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let clear_context_actions : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")
