// Where a draft is copied stays beside send through the composer's changes of shape. Its chooser keeps its rows
// and focus while several threads are ticked; each action reads the current core value.

///|
fn cc_mark_node(parent : @view.View, via : () -> String) -> Unit {
  parent.box(fn(mark) {
    mark.width(Is(Some(14.0))).height(Is(Some(14.0)))
    .picture(By(fn() { @sf.drawable_vector(if via() == "feishu" { "feishu" } else { "slack" }) })) |> ignore
  }) |> ignore
}

///|
fn composer_note_node(parent : @view.View, note : () -> Array[(String, String)]) -> @view.View {
  parent.box(fn(p) {
    // (where send's row has not the room for all of them, the names cut, softly: each is in 抄送's menu, ticked)
    p.row(Is(true)).gap(Is(8.0)).padding(Is((8.0, 0.0, 8.0, 0.0))).lines_up(Is(Some(Middle)))
    .cuts(Is(true)).min_width(Is(Some(0.0))).cuts_softly(Is(true))
    .laid_nowhere(By(fn() { note().is_empty() })) |> ignore
    p.each(fn() { note().mapi(fn(i, n) { (i, n) }) }, fn(n) { n.0 }, fn(item, n) {
      item.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))).cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
      cc_mark_node(item, fn() { n.get().1.0 })
      item.box(fn(w) {
        w.cuts(Is(true)).min_width(Is(Some(0.0))).words(By(fn() { n.get().1.1 })).words_look(By(fn() { @ui.style_words(cc_words) }))
        .ink(By(fn() { @sf.theme().p.muted })) |> ignore
      }) |> ignore
    })
  })
}

///|
fn cc_chooser_node(parent : @view.View, src : Source, r : ChatRef, view : () -> ChatView?) -> Unit {
  let choices = fn() { view().map(fn(v) { v.cc }).unwrap_or([]) }
  parent.show(fn() { view().map(fn(v) { v.thread is Some(_) && !v.cc.is_empty() }).unwrap_or(false) }, fn(p) {
    let open = fn() { composing.cc_open.get() }
    p.owns(fn() { composing.cc_open.set(false) }) |> ignore
    let button = p.box(fn(b) {
      let lit = fn() { open() || b.pointed() || b.pressed() || b.focus_shown() }
      b.row(Is(true)).height(Is(Some(28.0))).padding(Is((8.0, 0.0, 8.0, 0.0))).gap(Is(6.0))
      .lines_up(Is(Some(Middle))).radius(By(fn() { @ui.tree_theme().corner(Lg) }))
      .ground(By(fn() { if lit() { @sf.theme().p.hover } else { 0L } }))
      .presses(Is(true)).focusable(Is(true))
      .on_press(fn() { composing.cc_open.set(!open()) })
      .says(By(fn() {
        Some(@view.said(Button, label=([@sf.t("web-main.composer.ccLabel")] + choices().filter(fn(o) { o.on }).map(fn(o) { o.place })).join(" "), expanded=open()))
      })) |> ignore
      b.box(fn(w) {
        w.words(By(fn() { @sf.t("web-main.composer.ccLabel") })).words_look(By(fn() { @ui.style_words(cc_words) }))
        .ink(By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
      }) |> ignore
      @sf.icon_node(b, "chevron-down", 12.0, By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
    })
    let popup = @sf.popup_root_node(button)
    @sf.menu_node(popup, open, fn(_) { button }, fn() {
      choices().map(fn(o) {
        Some(@sf.menu_item_of(o.place, fn() {
          match view() {
            Some({ thread: Some(thread), .. }) => {
              (src.call)("chat.cc", { "station": Json::string(r.station), "thread": Json::number(thread),
                "to": Json::number(o.thread), "on": Json::boolean(!o.on) }, fn(_) {  })
            }
            _ => ()
          }
        }, chosen=o.on))
      })
    }, "", End, 6.0, false, true,
      fn(item) { if choices().length() <= 1 { composing.cc_open.set(false) }; (item.select)() },
      fn() { composing.cc_open.set(false) }, side=Top, keep_open=fn() { choices().length() > 1 }, check_end=true, multiple=true,
      min_w=@sf.chooser_menu_w, mark_node=fn(m, i) {
        cc_mark_node(m, fn() { choices().get(i).map(fn(o) { o.via }).unwrap_or("") })
      })
  })
}
