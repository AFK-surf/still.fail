// An agent's context by hand, between turns (openContext):
// its context's tile in the agent's card opens, a step further in from the card (the card closed for it: the
// presenters' step, its back key back to the card), what compacts it (its chat is told when it is done) or clears it
// (asked first in a sheet of its own): its next message starts a new session.

///|
/// What is under way or failed of `call` on `key`'s session (the core's doing, as AppState.isDoing has it).
fn context_key(call : String, station : String, key : String) -> String {
  call + "/" + station + "/" + key
}

///|
/// What can be done to its context from its tile: opens it; under way or failed, said
/// where the tile's › is; `compacts`: it can be compacted.
priv struct ContextTile {
  open : () -> Unit
  busy : Bool
  failed : Bool
  compacts : Bool
}

///|
/// The card's entry for its context (canCompact, canClear), none when nothing can be done to it; opened, the card
/// closed (`close`) for it, a step further in from it.
fn context_entry(c : @ui.Ctx, src : Source, r : ChatRef, key : String, s : Json?, close : () -> Unit) -> ContextTile? {
  if !flag(s, "canCompact") && !flag(s, "canClear") {
    return None
  }
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  Some({
    open: fn() {
      close()
      open_context(src, r, key)
    },
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
/// What can be done to its context by hand, the library's panel (nodes of the window's tree, made once as it opens:
/// @sf.panel_nodes): compacted, or cleared (asked first: @sf.confirm); each row there while its session says it can.
fn open_context(src : Source, r : ChatRef, key : String) -> Unit {
  @sf.panel_nodes(tr("web-pages.chat.context"), from=Unanchored, fn(v, close) {
    let s = fn() { field(agent_json(src.topic("chat", chat_params(r)).get().value, key), "session") }
    let params = fn() -> Json { { "station": Json::string(r.station), "key": Json::string(key) } }
    v.show(fn() { flag(s(), "canCompact") }, fn(row) {
      @sf.choice_row_node(
        row,
        fn() { tr("web-pages.chat.compact") },
        fn() { false },
        note=fn() { tr("web-mobile.agent.compactSub") },
        press=fn() {
          close()
          act(src, tr("web-pages.chat.compact"), context_key("session.compact", r.station, key), "session.compact", params(), done=tr("web-mobile.agent.compacting"))
        },
      )
    })
    v.show(fn() { flag(s(), "canClear") }, fn(row) {
      @sf.choice_row_node(
        row,
        fn() { tr("web-pages.chat.clear") },
        fn() { false },
        note=fn() { tr("web-mobile.agent.clearSub") },
        ink=fn() { @sf.theme().p.red },
        press=fn() {
          close()
          // asked first: the row shows it under way, a failure said by a toast
          @sf.confirm(tr("web-pages.chat.clearConfirm"), tr("web-pages.chat.clearBody"), tr("web-pages.chat.clear"), danger=true, fn() {
            @ui.haptic(Confirm)
            act(src, tr("web-pages.chat.clear"), context_key("session.clear", r.station, key), "session.clear", params())
          })
        },
      )
    })
  })
}

///|
/// A tile's name (muted), and its name with its › side by side.
// kept across runs: a value (no field of it changes)
let tile_name : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_name_row : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

