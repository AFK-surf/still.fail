// The desktop's chat's side panel is sfdesk's (panel.mbt), as its page and bar are (chat_page.mbt): what this package
// asks of it goes through the names below (its messages open an agent's history beside the chat), and what the panel
// shows of this package's (panel_parts).

///|
/// A chat's key among the frame's own: its station and session.
fn side_key(r : ChatRef) -> String {
  @sfdesk.chat_key(r)
}

///|
/// The chat's side panel's tabs, in their order, and the one in front (sfdesk/panel.mbt).
fn side_of(v : ChatView) -> (Array[String], String) {
  @sfdesk.side_of(v)
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
/// The change asked of the core alone, the panel told nothing (sfdesk's side_ask).
fn side_ask(r : ChatRef, action : String, tab : String?) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_ask(src, r, action, tab)
    None => ()
  }
}

///|
/// An agent's history pressed, or the chat's files: in front, closed; else opened in front (sfdesk's side_toggle).
fn side_toggle(r : ChatRef, tab : String) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_toggle(src, r, tab)
    None => ()
  }
}

///|
/// What the side panel shows of this package's beside chat `r`: an agent's history's steps (history.mbt), a letter as
/// the chat draws a message, a link opened as the chat opens one.
fn panel_parts(c : @ui.Ctx, src : Source, r : ChatRef) -> @sfdesk.PanelParts {
  {
    steps: fn(key) { history_steps(c, src, r, key, None) },
    message: fn(m) {
      match view_of_chat(src, r) {
        (Some(v), _, _) =>
          said(c, src, { station: r.station, session: r.session, view: v }, message_of(m), [], decide=false)
        _ => ()
      }
    },
    link: fn(href) { open_link(href) },
  }
}
