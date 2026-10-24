// The desktop's chat's side panel is sfdesk's (panel.mbt), as its page and bar are (chat_page.mbt): what this package
// asks of it goes through the names below (its messages open an agent's history beside the chat).

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
/// What the desktop's messages (sfdesk/message.mbt) draw that is this package's: the file preview (preview.mbt) and
/// the thumbnails it flies from, a video's still, a picture sent from here, a visualization (viz.mbt), a link opened
/// and its menu, a station's screens' cards (screen_links.mbt).
fn desk_chat_parts() -> @sfbase.ChatParts {
  {
    open_file: fn(station, owner, a, thread, session) {
      open_preview(station, owner, a, steps=InChat(thread, session))
    },
    thumb: fn(c, id, node, radius, letterbox) { note_thumb(c, id, node, radius, letterbox~) },
    thumb_shows,
    video_still: fn(c, src, station, owner, a, thumb) {
      match pv_frames.get(thumb) {
        Some((k, _)) => k
        None =>
          match (src.poster)(station, owner, base_name(a.path)) {
            "!" => first_frame(c, src, station, owner, a, thumb)
            k => k
          }
      }
    },
    sent_picture,
    viz: viz_file_of,
    viz_open: fn(station, session, owner, a) { viz_open_full(a.name, station, owner, a.path, session, linked=true) },
    mermaid: viz_mermaid_block,
    link_held,
    screens: fn(c, src, key) { Some(screen_links(c, src, key)) },
    open_link,
    pick: fn(c, ts, author, role, words, fill, body) { pickable(c, ts, author, role, words, fill, body) },
    in_front: app_in_front,
  }
}
