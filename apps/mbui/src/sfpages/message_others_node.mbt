// Someone else's message as nodes of the window's tree, made once (message.mbt's others_message, sent_elsewhere, their
// styles the same): its picture out in the margin before its words (inline: over its head's start), its head (name,
// where it went, time), what it says under it. Not here yet: its picture held under the pane's top as a long one
// scrolls past (the old one's c.stick: the list's, to come), its ⋯ menu and the card over its picture and name, its
// files (message_files.mbt), coming out of its agent's picture (emit).

///|
/// Someone else's message (others_message's) in `v`: its picture (`avatar`, made in its room) out in the margin, held
/// over the row (inline: over its head's start, 3 down); its head (`name`; where it went, `route`, after it, or on a
/// line of its own under the head while inline; its time); `body` under them, 4 apart. Inline as `here` says as it
/// changes. The row's node.
fn message_others_node(
  v : @view.View,
  here : MessageNodeHere,
  time : () -> Stamp?,
  avatar : (@view.View) -> Unit,
  name : (@view.View) -> Unit,
  route : ((@view.View) -> Unit)?,
  body : (@view.View) -> Unit,
) -> @view.View {
  v.box(fn(row) {
    @sf.style_node(row, fn() { msg_row })
    row.box(fn(col) {
      @sf.style_node(col, fn() { msg_main })
      col.box(fn(head) {
        @sf.style_node(head, fn() { if (here.inline)() { msg_head_inline } else { msg_head } })
        name(head)
        match route {
          // (at once: the list's width says the arrangement, and what the window or the sidebar does to the width is
          // no motion of its own; nothing comes or goes)
          Some(r) => head.show(fn() { !(here.inline)() }, r, at_once=true)
          None => ()
        }
        message_time_node(head, here.tips, time)
      })
      |> ignore
      match route {
        Some(r) =>
          // (at once, as over the head: an arrangement by the list's width, not a coming or a going)
          col.show(here.inline, at_once=true, fn(l) {
            @sf.style_node(l, fn() { msg_route_line })
            // (as far under the head as keeps the time's room and the place's whole, one over the other)
            l.margin(Is((0.0, route_line_down(), 0.0, 0.0))) |> ignore
            r(l)
          })
        None => ()
      }
      body(col)
    })
    |> ignore
    // (over the row, at its start: out in the margin, or over the head's start where inline)
    row.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      layer.box(fn(av) {
        @sf.style_node(av, fn() { if (here.inline)() { msg_avatar_inline } else { msg_avatar_room } })
        avatar(av)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What an agent of the chat said in Slack (or Feishu, or another chat) rather than here, or a person's message there it
/// was given (sent_elsewhere's), as `s` says as it changes, in `v`: drawn as a message of theirs, that place's mark on
/// the picture's corner and, after the name, where it went or came from, red where sending it failed; its words as
/// Markdown. In its row's room (message_row_frame_node: `key`, its list's Entry::id `s:<key>`; `side`, `top`; `over`).
fn sent_elsewhere_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  s : () -> Elsewhere,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  message_row_frame_node(v, key, side, top, over~, fn(m) { sent_elsewhere_body(m, src, here, s) })
}

///|
/// What was said elsewhere (sent_elsewhere's) in `v`, its row's room round it: sent_elsewhere_node's.
fn sent_elsewhere_body(v : @view.View, src : Source, here : MessageNodeHere, s : () -> Elsewhere) -> Unit {
  let surface = fn() {
    match s().place {
      Some(p) => p.surface
      None => "slack"
    }
  }
  let agent = fn() {
    let e = s()
    if e.received { "" } else { message_agent_of(here, e.by.agent) }
  }
  message_others_node(
    v,
    here,
    fn() { s().time },
    fn(av) {
      av.pick(fn() { s().received }, fn(a, received) {
        if received {
          a.box(fn(p) {
            @sf.style_node(p, fn() { person_avatar_room })
            person_avatar_node(p, src, here, fn() { s().by.name }, fn() { s().by.name }, fn() { s().by.picture })
            place_corner_node(p, surface)
          })
          |> ignore
        } else {
          agent_avatar_node(a, fn() { s().by.maker }, fn() { s().by.runtime }, fn() {
            if surface() == "feishu" { "feishu" } else { "slack" }
          })
        }
      })
    },
    fn(h) { message_name_node(h, src, here, fn() { s().by.name }, agent, fn() { "" }) },
    Some(fn(r) { elsewhere_route_node(r, s) }),
    fn(b) {
      @sf.markdown_node(b, fn() { s().text }, size=fn() { body_size }, on_link=fn(h) { open_link(h) }) |> ignore
    },
  )
  |> ignore
}

///|
/// How far apart the middles of a head's time and of the place on the line of its own under it (inline) stand, laid
/// out with nothing between them, at the default size of words: half the head's line (24), the column's gap (4), half
/// the place (20). Larger words only set them further apart.
let route_line_apart : Double = head_line_h / 2.0 + 4.0 + 10.0

///|
/// How much further down an inline head's line of where it went goes, so that its place and the time over it each
/// have a press's least room (@ui.room_least: a keyboard and mouse's 36, a finger's 44) neither cutting the other's
/// (the old view's had 31 and 32: the coordinator, 2026-11-11).
fn route_line_down() -> Double {
  let d = @ui.room_least() - route_line_apart
  if d > 0.0 { d } else { 0.0 }
}
