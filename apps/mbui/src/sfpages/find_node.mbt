// The chat's find bar, made once. Its Field and result controls live as long as the bar; a new query calls the same
// core search as find.mbt after the last key's typing interval. Closing or moving to another chat cancels that call.

///|
/// A chat's find bar (find_bar's layout and actions) in its header, with tips over that page. Its field's node.
pub fn find_bar_node(parent : @view.View, src : Source, r : ChatRef, thread : Double,
  list : FindList, tips : @sf.TipLayer) -> @view.View {
  let key = chat_key(r)
  let field_node : Ref[@view.View?] = Ref(None)
  parent.box(fn(bar) {
    bar.row(Is(true)).gap(Is(@ui.Space::px(S2))).lines_up(Is(Some(Middle))) |> ignore
    let look = @motion.presence_node(bar, initial=false, enter=@kit.tip_in, exit=@kit.tip_in)
    bar.alpha(By(fn() { look().alpha })) |> ignore
    bar.show(fn() { finding.found.get().map_or(false, fn(f) { !f.whole }) }, fn(note) {
      note.max_width(Is(Some(find_field_w))).clips(Is(true)) |> ignore
      find_meta_node(note, fn() {
        match finding.found.get() {
          Some(f) => if finding.bringing.get() {
            @sf.t("web-main.find.bringing", args=[("held", f.held.to_string())])
          } else {
            @sf.t("web-main.find.partial", args=[("held", f.held.to_string()), ("of", f.of.to_string())])
          }
          None => ""
        }
      })
    })
    bar.box(fn(capsule) {
      capsule.row(Is(true)).width(Is(Some(find_field_w))).min_width(Is(Some(find_field_least)))
      .height(Is(Some(find_field_h))).radius(Is(find_field_h / 2.0))
      .padding(Is((@ui.Space::px(S3), 0.0, @ui.Space::px(@sf.capsule_end_room(find_field_h, find_button_w)), 0.0)))
      .gap(Is(@ui.Space::px(S0_5))).lines_up(Is(Some(Middle)))
      .ground(By(fn() { @sf.theme().p.raised })).edge(By(fn() { (1.0, @sf.theme().p.line) })) |> ignore
      let close = fn() { (list.forget)(); find_close() }
      let input = @ui.field(capsule, finding.field,
        placeholder_by=fn() { @sf.t("web-main.find.placeholder") }, font_size=14.0, line=20.0,
        max_lines=1, enter_sends=true,
        colors_by=fn() { let p = @sf.theme().p; (p.text, p.muted, p.accent) },
        keys=fn(code, mods) {
          if code == @ui.key_code_enter && (mods == 0 || mods == @ui.mod_shift_key) {
            find_move(src, key, list, if mods == @ui.mod_shift_key { -1 } else { 1 })
            true
          } else if code == @ui.key_escape {
            close()
            true
          } else { false }
        })
      input.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
      field_node.val = Some(input)
      let due : Ref[() -> Unit] = Ref(fn() { })
      input.reacts(fn() { finding.field.text() }, fn(typed) {
        (due.val)()
        let query = typed.replace_all(old="\n", new="")
        if query != typed { finding.field.set(query) }
        finding.query = query
        guard query != finding.asked.get() else { return }
        let ask = fn() {
          if find_chat() == key && finding.field.text() == query {
            find_ask(src, r.station, thread, key, list, query)
          }
        }
        if query.trim(chars=" ").is_empty() { ask() } else {
          due.val = input.at_moment(input.cause_at() + find_typing_ms, ask)
        }
      })
      input.owns(fn() { (due.val)() }) |> ignore
      capsule.show(fn() {
        let (at, total) = find_position()
        finding.found.get() is Some(_) && !(finding.bringing.get() && total == 0) && !(total > 0 && at == 0)
      }, fn(count) {
        count.padding(Is((@ui.Space::px(S1_5), 0.0, @ui.Space::px(S1_5), 0.0))) |> ignore
        find_meta_node(count, fn() {
          let (at, total) = find_position()
          if total > 0 { "\{at}/\{total}" } else { @sf.t("web-main.find.none") }
        })
      })
      capsule.box(fn(buttons) {
        buttons.row(Is(true)).gap(By(fn() { @sf.keys_apart(size=find_button_w) })) |> ignore
        let enabled = fn() { finding.total.get() > 0 }
        find_button_node(buttons, "chevron-up", fn() { @sf.t("web-main.find.prev") }, enabled,
          fn() { find_move(src, key, list, -1) }, tips)
        find_button_node(buttons, "chevron-down", fn() { @sf.t("web-main.find.next") }, enabled,
          fn() { find_move(src, key, list, 1) }, tips)
        find_button_node(buttons, "close", fn() { @sf.t("web-main.find.close") }, fn() { true }, close, tips)
      }) |> ignore
    }) |> ignore
  }) |> ignore
  field_node.val.unwrap()
}

///|
fn find_meta_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(text) {
    text.words(By(words)).words_look(By(fn() { @ui.style_words(find_meta) }))
    .ink(By(fn() { @ui.style_ink(find_meta) })) |> ignore
  }) |> ignore
}

///|
fn find_button_node(parent : @view.View, icon : String, label : () -> String,
  enabled : () -> Bool, press : () -> Unit, tips : @sf.TipLayer) -> Unit {
  parent.box(fn(button) {
    button.width(Is(Some(find_button_w))).height(Is(Some(find_button_w))).radius(Is(find_button_w / 2.0))
    .lines_up(Is(Some(Middle))).lies_along(Is(Middle)).points(Is(true))
    .ground(By(fn() { if enabled() && button.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .alpha(By(fn() { if enabled() { 1.0 } else { 0.5 } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    @sf.presses_node(button, fn() { if enabled() { press() } })
    button.presses(By(enabled)).focusable(By(enabled)) |> ignore
    @sf.icon_node(button, icon, 16.0, By(fn() { @sf.theme().p.text })) |> ignore
    @sf.tip_node(tips, button, label, side=Bottom) |> ignore
  }) |> ignore
}
