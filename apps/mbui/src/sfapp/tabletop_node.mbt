// The recent chats under the fold: the same chat rows as Home and the sidebar, kept by their chat. The fold and
// keyboard give their column its room; a press replaces this chat, a swipe archives the row as in any chat list.

///|
fn recent_list_node(parent : @view.View, src : Source, w : Workspace, stint : () -> Int) -> Unit {
  let read = fn() { chats_of(src, w.id, "all") }
  // (the window's layer for its tips, made as the first shows: popup_root_lazy)
  let popup = @sf.popup_root_lazy(parent)
  let tips = @sf.TipLayer::new(fn() { Some(popup()) })
  let waiting = fn() {
    match read().0 {
      None => true
      Some(v) => v.days.is_empty() && v.note.map(fn(n) { n.reading || !n.failing.is_empty() }).unwrap_or(false)
    }
  }
  parent.pick(waiting, fn(content, waits) {
    if waits {
      @sf.waiting_node(content, fn(sample) {
        recent_rows_node(sample, @sfbase.sample_source, fn() { Array::makei(recent_sample, @sfpages.sample_chat) },
          fn() { "agents" }, fn() { None }, tips, stint)
      }, error=fn() { read().1.unwrap_or("") }, note=fn() {
        match read().0.bind(fn(v) { v.note }) {
          Some(n) => { reading: n.reading, text: n.text.unwrap_or(tr("common.reading")), failing: n.failing }
          None => { reading: true, text: tr("common.reading"), failing: [] }
        }
      })
    } else {
      let items = fn() {
        let out : Array[ChatItem] = []
        match read().0 {
          Some(v) => for d in v.days { for it in d.items { if out.length() < recent_chats_most { out.push(it) } } }
          None => ()
        }
        out
      }
      content.show(fn() { items().is_empty() }, fn(empty) {
        @sf.words_node(empty, fn() { tr("android-misc.wide.empty") }, fn() { recent_empty }) |> ignore
      })
      recent_rows_node(content, src, items, fn() { read().0.map(fn(v) { v.leading }).unwrap_or("agents") },
        fn() { Some(app.nav.top()) }, tips, stint)
    }
  })
}

///|
fn recent_rows_node(parent : @view.View, src : Source, items : () -> Array[ChatItem], lead : () -> String,
  top : () -> Page?, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  parent.box(fn(rows) {
    @sf.style_node(rows, fn() { recent_rows })
    rows.pick(lead, fn(list, lead) {
      list.each(fn() { items().map(row_name) }, fn(key) { key }, fn(row, key) {
        let first = @signals.untracked(fn() { items().iter().find_first(fn(it) { row_name(it) == key.get() }).unwrap() })
        let item = fn() { items().iter().find_first(fn(it) { row_name(it) == key.get() }).unwrap_or(first) }
        let here = fn() { match top() { Some(Chat(r)) => row_is(item(), r); _ => false } }
        @sf.style_node(row, fn() { if here() { recent_row_here } else { recent_row } })
        @sfpages.chat_row_node(row, src, tips, item, lead, fn() { false }, Whole, stint, found=true, opened=fn(r) {
          if !@signals.untracked(here) { open_in_place(Chat(r)) }
        }) |> ignore
      })
    })
  }) |> ignore
}
