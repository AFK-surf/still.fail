// The desktop's chat's side panel is sfdesk's (panel.mbt), as its page and bar are (chat_page.mbt): what this package
// asks of it goes through the names below (its messages open an agent's history beside the chat).

///|
/// A chat's key among the frame's own: its station and session.
fn side_key(r : ChatRef) -> String {
  @sfdesk.chat_key(r)
}

///|
/// Chat `r`'s tabs as its view has them now.
fn side_now(r : ChatRef) -> (Array[String], String) {
  match link_src.val {
    Some(src) => @sfdesk.side_now(src, r)
    None => ([], "")
  }
}

///|
/// Chat `r`'s tabs changed by the core, the panel told first whether any will be open (sfdesk's side_change).
fn side_change(r : ChatRef, action : String, tab : String?) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_change(src, r, action, tab)
    None => ()
  }
}

///|
/// What the desktop's messages (sfdesk/message.mbt) draw that is this package's: a visualization (viz.mbt).
fn desk_chat_parts() -> @sfbase.ChatParts {
  {
    viz: viz_file_of,
    viz_open: fn(station, session, owner, a) { viz_open_full(a.name, station, owner, a.path, session, linked=true) },
    mermaid: viz_mermaid_block,
  }
}
