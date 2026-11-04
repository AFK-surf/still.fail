// A chat being read for the first time: the same made-up messages as chat_messages_sample, made once as the
// message nodes that will replace them. The waiting presenter turns their words and pictures into bones; their
// rows follow the page's width and the bar's room without making another message or asking the core anything.

///|
/// The first read of chat `r`, under its bar: a failed read says why above the still sample; a read in progress
/// breathes. `top` is the first row's place, `bar` the room in which no error pill may stand.
pub fn chat_waiting_node(parent : @view.View, src : Source, r : ChatRef, top : () -> Double, bar : () -> Double) -> Unit {
  parent.padding(By(fn() { (0.0, bar(), 0.0, 0.0) })) |> ignore
  @sf.waiting_node(parent, fn(sample) {
    chat_messages_sample_node(sample, fn() { top() - bar() })
  }, error=fn() {
    match @sfbase.view_of_chat(src, r).2 {
      Some(e) => @sf.t("android-chat.chat.unreadable", args=[("error", text(Some(e), "message"))])
      None => ""
    }
  })
}

///|
pub fn chat_messages_sample_node(parent : @view.View, top : () -> Double) -> Unit {
  parent.box(fn(column) {
    column.min_width(Is(Some(0.0))).shrink(Is(0.0)) |> ignore
    let room = column.width_context()
    column.lends(chat_row_width, room) |> ignore
    let width = fn() { room.now().unwrap_or(column.window().0) }
    let narrow = fn() { width() <= chat_narrow_w }
    let side = fn() { row_side_in(width()) }
    let view = @sfbase.chat_view_made({ "title": Json::string(""), "messages": [] })
    let here = fn() -> MessageHere {
      { station: "", session: "", view, go: None, inline: narrow(), gutter: side(), list: None, core: None }
    }
    column.box(fn(space) { space.height(By(fn() { Some(top()) })).shrink(Is(0.0)) |> ignore }) |> ignore
    for i, sample in sample_messages {
      let (mine, lines) = sample
      let words = lines.map(@sf.sample_words)
      let said = @sfbase.message_of({
        "ts": Json::string("sample/" + i.to_string()),
        "authorKind": Json::string(if mine { "person" } else { "agent" }),
        "mine": Json::boolean(mine),
        "text": Json::string(words.join("\n\n")),
        "md": Json::array(words.map(fn(w) { Json::array([Json::string("p"), Json::array([Json::string(w)])]) })),
        "by": { "name": Json::string(@sf.sample_words(if mine { 2 } else { 6 })), "maker": { "id": "anthropic" } },
        "time": { "createdAt": { "ago": Json::string(@sf.sample_words(3)), "full": "" } },
      })
      column.box(fn(row) {
        row
        .min_width(Is(Some(0.0)))
        .shrink(Is(0.0))
        |> ignore
        room.bind(row, By(fn() { (@sf.native_on(), @sf.native_side(), native_row_inset()) }), fn(w, native) {
          let (on, on_side, inset) = native
          let narrow = w <= chat_narrow_w
          let start = if narrow { if on { inset } else { row_side_narrow } }
            else if on { dense_row_side } else { dmax(row_side_least, (w - chat_column_w) / 2.0) }
          let over = if i == 0 { 0.0 } else if narrow { list_gap_narrow } else { list_gap }
          let trailing = if on_side { inset } else { start }
          row.padding(Is((start, over, trailing, 0.0))) |> ignore
        })
        message_row_node(row, @sfbase.sample_source, here, fn() { said }, width)
      })
      |> ignore
    }
  })
  |> ignore
}
