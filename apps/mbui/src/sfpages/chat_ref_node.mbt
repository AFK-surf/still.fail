// The retained composer's reference menu owns only its display and keys. Reference parsing, search caching and
// inserting a chosen mark use the same paths as the old composer.

///|
priv struct RefOffer {
  query : String
  topic : @sfbase.Topic
  chats : Array[Json]
  at : (Int, String)?
  before : String
  after : String
}

///|
fn ref_words_node(p : @view.View, words : () -> String, style : @ui.TextStyle) -> @view.View {
  p.box(fn(v) {
    v.words(By(words)).words_look(By(fn() { @ui.style_words(style) })).ink(By(fn() { @ui.style_ink(style) })) |> ignore
  })
}

///|
fn ref_menu_node(
  owner : @view.View,
  cap : @view.View,
  field_node : @view.View,
  src : Source,
  spec : () -> ComposerSpec,
  w : Writing,
  active : () -> Bool,
) -> (Int, Int) -> Bool {
  // (none offered again is nothing new, what reads it not told: each edit works it out anew, mostly to none. One offered
  // is told each time, what it holds no value to compare)
  let offer : @signals.Signal[RefOffer?] = @signals.signal(None, same=fn(a, b) { a is None && b is None })
  // ref_found remembers search answers. That work belongs to this effect, never a property read during layout.
  owner.owns(@signals.effect(fn() {
    let found = ref_found(src, spec(), w, active() && field_node.focused())
    let at = @sfbase.refs_at(w.key)
    let text = w.field.text()
    let caret = w.field.selection().1
    offer.set(found.map(fn(f) {
      { query: f.0, topic: f.1, chats: f.2, at,
        before: match at { Some((start, _)) if start < text.length() => text.view(end_offset=start + 1).to_string(); _ => "" },
        after: if caret >= 0 && caret <= text.length() { text.view(start_offset=caret).to_string() } else { "" } }
    }))
  })) |> ignore
  let offered = fn() -> RefOffer? {
    match offer.get() {
      Some(o) if active() && !spec().locked && @sfbase.refs_at(w.key) == o.at &&
        @sfbase.refs_still_at(w.field, o.at, o.before, o.after) => Some(o)
      _ => None
    }
  }
  let pick = fn(x : Json) -> Bool {
    guard offered() is Some(_) else { return false }
    let item = @sfbase.chat_item(x)
    @sfbase.refs_pick_now(src, w.key, w.field, workspace_of(spec().station), item.station, item.id, item.title, fn(why) {
      toast_later(@sf.t("web-main.composer.refFailed", args=[("title", item.title), ("error", why)]))
    })
    true
  }
  let rows : Map[String, @view.View] = {}
  let row_key = fn(x : Json) { let item = @sfbase.chat_item(x); item.station + "\t" + item.id }
  let layer = @sf.popup_root_node(owner)
  layer.show(fn() { offered() is Some(_) }, fn(p) {
    let held = Ref(@signals.untracked(fn() { offered().unwrap() }))
    p.owns(@signals.effect(fn() { match offered() { Some(o) => held.val = o; None => () } })) |> ignore
    let data = fn() { offer.get().unwrap_or(held.val) }
    let look = @motion.presence_node(p, initial=false, enter=@kit.pop_in, exit=@kit.pop_out)
    // (as wide as the composer's box, laid out after it: View::laid_after; beside it as it is placed)
    p.laid_after(fn() { (0.0, 0.0, Some(cap.laid_size().0), None) })
    .beside(cap.id(), side=Top, along=Start, offset=ref_menu_off)
    .max_height(By(fn() { Some(dmin(ref_menu_max, p.window().1 - 16.0)) }))
    .padding(Is((@sf.panel_pad, @sf.panel_pad, @sf.panel_pad, @sf.panel_pad)))
    .radius(By(fn() { @ui.tree_theme().corner(@sf.ref_menu_corner) }))
    .glass(By(fn() { Some(@sf.glass_floating()) }))
    .shadow(By(fn() { (8.0, 4.0, @sf.theme().p.shadow) }))
    .alpha(By(fn() { look().alpha })).scale(By(fn() { look().sx }), about=FromBeside)
    .hides(By(fn() { p.leaving() })).presses(By(fn() { !p.leaving() })).on_press(fn() {  })
    .says(By(fn() { Some(@view.said(Group, label=@sf.t("web-main.chatRef.title"))) })) |> ignore
    let first_down = @signals.untracked(fn() { p.window_downs() })
    p.reacts(fn() { p.window_downs() }, fn(down) {
      if down != first_down && !p.leaving() {
        let inside = fn(v : @view.View) {
          match v.window_down_here() {
            Some((x, y)) => { let (_, _, width, height) = v.placed_now(); x >= 0.0 && y >= 0.0 && x < width && y < height }
            None => false
          }
        }
        if !inside(cap) && !inside(p) { @sfbase.refs_close(w.key) }
      }
    })
    p.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), for_field=field_node.id(), fn(body) {
      body.alpha(By(fn() { look().words })) |> ignore
      body.box(fn(head) {
        head.row(Is(true)).gap(Is(6.0)).padding(Is((10.0, 6.0, 10.0, 4.0))) |> ignore
        ref_words_node(head, fn() { @sf.t("web-main.chatRef.title") }, ref_head_words) |> ignore
        head.show(fn() { data().query != "" }, fn(q) { ref_words_node(q, fn() { data().query }, ref_query) |> ignore })
      }) |> ignore
      body.pick(fn() { let d = data(); if d.topic.value is None { if d.topic.error is None { 0 } else { 1 } } else if d.chats.is_empty() { 2 } else { 3 } }, fn(state, kind) {
        if kind != 3 {
          state.padding(Is((10.0, 6.0, 10.0, 6.0))) |> ignore
          if kind == 0 { @sf.wait_line_node(state, fn() { @sf.t("common.reading") }) |> ignore }
          else { ref_words_node(state, fn() {
            if kind == 1 { @sf.t("web-main.chatRef.update", args=[("app", "still.fail")]) }
            else { @sf.t(if data().query != "" { "web-main.chatRef.noMatch" } else { "web-main.chatRef.none" }) }
          }, ref_empty_words) |> ignore }
        } else {
          state.each(fn() { data().chats }, row_key, fn(row, value) {
            let key = @signals.untracked(fn() { row_key(value.get()) })
            rows[key] = row
            row.owns(fn() { rows.remove(key) }) |> ignore
            let chosen = fn() { data().chats.get(@sfbase.refs_active_now(w.key, data().chats.length())).map(row_key) == Some(key) }
            let item = fn() { @sfbase.chat_item(value.get()) }
            row.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle)))
            .padding(Is((10.0, @sf.menu_row_over, 10.0, @sf.menu_row_over)))
            .min_height(By(fn() { Some(@sf.theme().rows.pick) }))
            .radius(By(fn() { @ui.tree_theme().corner(@sf.ref_item_corner) }))
            .ground(By(fn() { if chosen() { @sf.theme().p.hover } else { 0L } }))
            .presses(Is(true)).on_press(fn() { pick(value.get()) |> ignore })
            .on_pointer_moved(fn() {
              if row.pointed() {
                match data().chats.search_by(fn(x) { row_key(x) == key }) {
                  Some(i) => @sfbase.refs_active(w.key, data().chats.length(), to=i) |> ignore
                  None => ()
                }
              }
            })
            .says(By(fn() { Some(@view.said(Button, label=item().title, selected=chosen())) })) |> ignore
            row.box(fn(logo) {
              logo.width(Is(Some(16.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
              logo.show(fn() { item().agents.length() > 0 }, fn(mark) {
                @sf.maker_mark_node(mark, fn() { item().agents.get(0).map(fn(a) { a.maker }).unwrap_or("") },
                  fn() { item().agents.get(0).map(fn(a) { a.runtime }).unwrap_or("") }, ref_logo_size) |> ignore
              })
            }) |> ignore
            row.box(fn(title) {
              title.row(Is(true)).grow(Is(1.0)).min_width(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
              ref_words_node(title, fn() { item().title }, ref_title).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              title.show(fn() { text(Some(value.get()), "outside") != "" || flag(Some(value.get()), "otherStation") }, fn(chip) {
                chip.row(Is(true)).margin(Is((4.0, 0.0, 0.0, 0.0))).padding(Is((6.0, 1.0, 6.0, 1.0)))
                .gap(Is(1.0)).lines_up(Is(Some(Middle))).radius(Is(10000.0)).ground(By(fn() { @sf.theme().p.hover })) |> ignore
                let outside = fn() { text(Some(value.get()), "outside") }
                chip.pick(fn() { outside() != "" }, fn(mark, other) {
                  if other { @sf.workspace_badge_node(mark, outside, fn() { text(Some(value.get()), "outsideEmoji") }, fn() { text(Some(value.get()), "outsideIcon") }, ref_chip_icon) }
                  else { @sf.station_mark_node(mark, fn() { item().station_emoji }, fn() { item().station_icon }, ref_chip_icon, fn() { @sf.theme().p.muted }, fn() { 0 }) }
                })
                ref_words_node(chip, fn() { if outside() != "" { outside() } else { item().station_name } }, ref_chip_words) |> ignore
              })
            }) |> ignore
            ref_words_node(row, fn() { item().ago }, ref_time) |> ignore
          })
        }
      })
    }) |> ignore
  }, leave=@kit.pop_out_ms)
  fn(code, mods) {
    guard offered() is Some(o) else { return false }
    if code == @ui.key_escape { @sfbase.refs_close(w.key); return true }
    if mods != 0 || o.chats.is_empty() { return false }
    if code == @ui.key_code_up || code == @ui.key_code_down {
      let i = @sfbase.refs_active(w.key, o.chats.length(), by=if code == @ui.key_code_up { -1 } else { 1 })
      match (rows.get(row_key(o.chats[i])), @ui.view_tree()) {
        (Some(row), Some(tree)) => tree.show_in_sight(row.id())
        _ => ()
      }
      true
    } else if code == @ui.key_code_enter || code == @ui.key_tab {
      pick(o.chats[@sfbase.refs_active_now(w.key, o.chats.length())])
    } else { false }
  }
}
