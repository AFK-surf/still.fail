// The model panel's contents as retained nodes. The presenter supplies their lifetime, anchor and close action.

///|
/// A panel keeps its own navigation and the last pick. That pick stops following the core when the panel closes, so a
/// save cannot rearrange the contents while they leave.
priv struct TripleNodePanel {
  pick : @signals.Signal[Json?]
  field : @ui.Field
  all : @signals.Signal[Bool]
  kind : @signals.Signal[String]
  serial : Ref[Int]
  tips_at : Ref[@view.View?]
  tips : @sf.TipLayer
  pick_anchor : Ref[(String, @view.View) -> Unit]
}

///|
fn triple_node_panel_state(page : Json?) -> TripleNodePanel {
  let tips_at : Ref[@view.View?] = Ref(None)
  {
    pick: @signals.signal(page, same=fn(_, _) { false }),
    field: @ui.Field::new(),
    all: @signals.signal(false),
    kind: @signals.signal(""),
    serial: Ref(0),
    tips_at,
    tips: @sf.TipLayer::new(fn() { tips_at.val }),
    pick_anchor: Ref(fn(_, _) {  }),
  }
}

///|
fn triple_node_follow_pick(parent : @view.View, state : TripleNodePanel, src : Source, station : String, of : String) -> Unit {
  parent.reacts(fn() {
    @sf.presenting() |> ignore
    (src.topic)("pick", pick_params(station, of)).value
  }, fn(value) {
    if (state.serial.val == 0 || @sf.presented_open_of(state.serial.val)) && value is Some(_) {
      state.pick.set(value)
    }
  })
}

///|
/// A selectable model row, kept by model id. The checkbox is its own neighbouring target and never also picks the row.
fn triple_node_models(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  state : TripleNodePanel,
  models : () -> Array[Json],
  saved : String,
  close : () -> Unit,
  likes? : Bool = false,
  starred? : Bool = false,
  reveal? : () -> Bool = fn() { false },
) -> Unit {
  parent.each(models, fn(o) { text(Some(o), "model") }, fn(slot, model) {
    let o = fn() { Some(model.get()) }
    let id = fn() { text(o(), "model") }
    let picked = fn() { text(state.pick.get(), "option") == id() }
    slot.row(Is(true)).gap(Is(if likes { 4.0 } else { 0.0 })).lines_up(Is(Some(Middle))) |> ignore
    if likes {
      slot.box(fn(hit) {
        hit.width(By(fn() { Some(if @sf.theme().touch { 44.0 } else { 36.0 }) }))
        .min_height(By(fn() { Some(if @sf.theme().touch { 44.0 } else { 36.0 }) }))
        .lines_up(Is(Some(Middle))).lies_along(Is(Middle))
        .says(By(fn() {
          Some(@view.said(Checkbox, label=@sf.t("web-main.model.likeModel", args=[("model", text(o(), "name"))]),
            check=if flag(o(), "liked") { On } else { Off }))
        })) |> ignore
        @sf.presses_node(hit, fn() { triple_like(src, station, of, id(), !flag(o(), "liked")) })
        hit.focusable(Is(true), keys=@view.focus_space) |> ignore
        hit.box(fn(box) {
          box.width(Is(Some(triple_box_side))).height(Is(Some(triple_box_side)))
          .radius(Is(6.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
          .ground(By(fn() { if flag(o(), "liked") { @ui.tree_theme().primary } else { @ui.tree_theme().bg } }))
          .edge(By(fn() {
            let t = @ui.tree_theme()
            (1.0, if flag(o(), "liked") { t.primary } else if hit.pointed() { t.field_hover } else { t.border })
          })) |> ignore
          box.show(fn() { flag(o(), "liked") }, fn(check) {
            @sf.icon_node(check, "check", 12.0, By(fn() { @ui.tree_theme().on_primary })) |> ignore
          })
          box.show(fn() { hit.focus_shown() }, fn(ring) {
            let out = fn() { @ui.tree_theme().focus_gap + @ui.tree_theme().focus_w }
            ring.over(Is(true)).margin(By(fn() { (-out(), -out(), -out(), -out()) }))
            .radius(By(fn() { 6.0 + out() })).edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) })) |> ignore
          })
        }) |> ignore
      }) |> ignore
    }
    slot.box(fn(row) {
      @sf.style_node(row, fn() { triple_option_style }, in_row=true)
      row.grow(Is(1.0)).min_width(Is(Some(0.0))).min_height(By(fn() { Some(@sf.theme().rows.pick) }))
      .ground(By(fn() { if picked() || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
      .says(By(fn() { Some(@view.said(Button, label=text(o(), "name"), selected=picked())) })) |> ignore
      @sf.presses_node(row, fn() { triple_choose_model(src, station, of, state.pick.get(), o(), saved, close) })
      @sf.tip_node(state.tips, row, fn() {
        items(o(), "ids").filter_map(fn(i) { if i is String(s) { Some(s) } else { None } }).join("\n")
      }) |> ignore
      @sf.maker_mark_node(row, fn() { text(field(o(), "maker"), "id") }, fn() {
        match items(o(), "runtimes").get(0) {
          Some(String(r)) => r
          _ => text(field(state.pick.get(), "value"), "runtime")
        }
      }, 14.0) |> ignore
      row.box(fn(names) {
        names.grow(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(1.0)) |> ignore
        names.box(fn(line) {
          line.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).min_width(Is(Some(0.0))) |> ignore
          @sf.words_node(line, fn() { text(o(), "name") }, fn() { if picked() { triple_row_picked } else { triple_row_name } }) |> ignore
          line.show(fn() { text(o(), "usualText") != "" }, fn(usual) {
            @sf.words_node(usual, fn() { text(o(), "usualText") }, fn() { triple_usual })
            .shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          })
        }) |> ignore
        names.show(fn() { text(field(o(), "spent"), "text") != "" }, fn(spent) {
          @sf.words_node(spent, fn() { text(field(o(), "spent"), "text") }, fn() { triple_note }) |> ignore
        })
      }) |> ignore
      row.show(fn() { field(o(), "fromStation") is Some(Object(_)) }, fn(from) {
        let station = fn() { field(o(), "fromStation") }
        from.pick(fn() { text(station(), "icon") != "" || text(station(), "emoji") != "" }, fn(mark, has_mark) {
          if has_mark {
            @sf.station_mark_node(mark, fn() { text(station(), "emoji") }, fn() { text(station(), "icon") },
              14.0, fn() { @sf.theme().p.muted }, fn() { 0 })
            @sf.tip_node(state.tips, mark, fn() { text(o(), "fromText") }, within=true) |> ignore
          } else {
            @sf.words_node(mark, fn() { text(station(), "name") }, fn() { triple_note_cut }) |> ignore
          }
        })
      })
      if starred {
        @sf.icon_node(row, "star-fill", triple_star_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      }
      row.box(fn(check) {
        check.width(Is(Some(14.0))).lines_up(Is(Some(Middle))) |> ignore
        check.show(picked, fn(mark) { @sf.icon_node(mark, "check", 14.0, By(fn() { @sf.theme().p.accent })) |> ignore })
      }) |> ignore
      if @signals.untracked(fn() { reveal() && picked() }) {
        row.once_laid_out(fn() {
          match @ui.view_tree() {
            Some(tree) => tree.show_in_sight(row.id())
            None => ()
          }
        })
      }
    }) |> ignore
  })
}

///|
fn triple_node_row(
  parent : @view.View,
  label : () -> String,
  on : () -> Bool,
  press : () -> Unit,
  lead? : String = "",
  trail_icon? : String = "",
  check? : Bool = true,
) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { triple_option_style })
    row.min_height(By(fn() { Some(@sf.theme().rows.pick) }))
    .ground(By(fn() { if on() || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=label(), selected=on())) })) |> ignore
    @sf.presses_node(row, press)
    if lead != "" { @sf.icon_node(row, lead, 14.0, By(fn() { @sf.theme().p.muted })) |> ignore }
    let words = @sf.words_node(row, label, fn() { if on() { triple_picked } else { triple_words } })
    if trail_icon == "" { words.grow(Is(1.0)) |> ignore }
    if trail_icon != "" { @sf.icon_node(row, trail_icon, 14.0, By(fn() { @sf.theme().p.muted })) |> ignore }
    if check {
      row.box(fn(room) {
        room.width(Is(Some(14.0))) |> ignore
        room.show(on, fn(mark) { @sf.icon_node(mark, "check", 14.0, By(fn() { @sf.theme().p.accent })) |> ignore })
      }) |> ignore
    }
  }) |> ignore
}

///|
fn triple_node_series(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  state : TripleNodePanel,
  data : () -> TripleModels,
  sheet : () -> Bool,
  saved : String,
  close : () -> Unit,
) -> Unit {
  let scroll = @view.Scroll::new()
  parent.max_height(By(fn() { Some(if sheet() { dmax(parent.window().1, triple_list_h) } else { triple_list_h }) }))
  .shrink(Is(1.0)).min_height(Is(Some(0.0)))
  .scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(list) {
    list.gap(Is(1.0)) |> ignore
    list.each(fn() { data().series }, fn(s) { s.0 }, fn(group, series) {
      group.show(fn() { data().series.length() > 1 }, fn(head) {
        @sf.style_node(head, fn() { triple_head_box })
        @sf.words_node(head, fn() { series.get().0 }, fn() { triple_head }) |> ignore
      })
      triple_node_models(group, src, station, of, state, fn() { series.get().1 }, saved, close,
        likes=true, reveal=fn() { !data().searching })
    })
    list.show(fn() { data().listed.is_empty() }, fn(empty) {
      @sf.style_node(empty, fn() { triple_empty })
      @sf.words_node(empty, fn() { @sf.t("web-main.model.noMatch") }, fn() { triple_muted }) |> ignore
    })
  })
  .clips(By(fn() { scroll.goes() })).bounds_input(By(fn() { scroll.goes() })) |> ignore
}

///|
fn triple_node_kinds(parent : @view.View, state : TripleNodePanel, data : () -> TripleModels, sheet : () -> Bool) -> Unit {
  let scroll = @view.Scroll::new()
  parent.max_height(By(fn() { Some(if sheet() { dmax(parent.window().1, triple_list_h) } else { triple_list_h }) }))
  .shrink(Is(1.0)).min_height(Is(Some(0.0)))
  .scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(list) {
    list.each(fn() { data().kinds }, fn(k) { text(Some(k), "id") }, fn(slot, maker) {
      let k = fn() { Some(maker.get()) }
      let id = fn() { text(k(), "id") }
      slot.box(fn(row) {
        @sf.style_node(row, fn() { triple_option_style })
        row.min_height(By(fn() { Some(@sf.theme().rows.pick) }))
        .ground(By(fn() { if (data().kind_open && id() == data().kind) || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
        .says(By(fn() { Some(@view.said(Button, label=text(k(), "title"), selected=data().kind_open && id() == data().kind)) })) |> ignore
        @sf.presses_node(row, fn() { state.kind.set(id()) })
        @sf.maker_mark_node(row, id, fn() { "" }, 14.0) |> ignore
        @sf.words_node(row, fn() { text(k(), "title") }, fn() { if data().kind_open && id() == data().kind { triple_picked } else { triple_words } })
        .grow(Is(1.0)) |> ignore
        @sf.words_node(row, fn() {
          match field(k(), "count") { Some(Number(n, ..)) => n.to_int().to_string(); _ => "" }
        }, fn() { triple_usual }) |> ignore
      }) |> ignore
    })
  })
  .clips(By(fn() { scroll.goes() })).bounds_input(By(fn() { scroll.goes() })) |> ignore
}

///|
/// The first level keeps recent models and starred models separate; the all-models level groups by maker and series.
fn triple_node_catalog(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  state : TripleNodePanel,
  sheet : () -> Bool,
  up : () -> Bool,
  saved : String,
  close : () -> Unit,
) -> Unit {
  let computed = @signals.computed(fn(_) {
    triple_models(state.pick.get(), state.field.text(), state.all.get(), state.kind.get(), sheet())
  }, same=fn(_, _) { false })
  let data = fn() { computed.get() }
  parent.pick(fn() { data().all }, fn(part, all) {
    if all {
      part.show(fn() { !data().searching && ((sheet() && state.kind.get() != "" && data().kinds.length() > 1) || !data().near.is_empty() || !data().liked.is_empty()) }, fn(back) {
        triple_node_row(back, fn() {
          if sheet() && state.kind.get() != "" && data().kinds.length() > 1 {
            text(data().kinds.iter().find_first(fn(k) { text(Some(k), "id") == data().kind }), "title")
          } else {
            @sf.t("web-main.model.allModels")
          }
        }, fn() { false }, fn() {
          if sheet() && state.kind.get() != "" { state.kind.set("") } else { state.all.set(false) }
        }, lead="chevron-left", check=false)
      })
      part.pick(fn() { if data().searching || data().kinds.length() < 2 { 0 } else if sheet() { 1 } else { 2 } }, fn(body, which) {
        match which {
          0 => triple_node_series(body, src, station, of, state, data, sheet, saved, close)
          1 => body.pick(fn() { state.kind.get() == "" }, fn(level, makers) {
            if makers { triple_node_kinds(level, state, data, sheet) }
            else { triple_node_series(level, src, station, of, state, data, sheet, saved, close) }
          })
          _ => {
            body.row(Is(true)).gap(Is(6.0)) |> ignore
            body.box(fn(kinds) {
              kinds.width(Is(Some(192.0))) |> ignore
              triple_node_kinds(kinds, state, data, sheet)
            }) |> ignore
            body.box(fn(rule) { rule.width(Is(Some(1.0))).ground(By(fn() { @sf.theme().p.line })) |> ignore }) |> ignore
            body.box(fn(models) {
              models.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              triple_node_series(models, src, station, of, state, data, sheet, saved, close)
            }) |> ignore
          }
        }
      })
    } else {
      part.gap(Is(12.0)) |> ignore
      let recent = fn(into : @view.View) {
        into.show(fn() { !data().near.is_empty() }, fn(group) {
          group.gap(Is(1.0)) |> ignore
          triple_node_models(group, src, station, of, state, fn() { if up() { data().near.rev() } else { data().near } }, saved, close,
            reveal=fn() { !data().searching })
        })
      }
      let liked = fn(into : @view.View) {
        into.show(fn() { !data().liked.is_empty() }, fn(group) {
          group.gap(Is(1.0)) |> ignore
          triple_node_models(group, src, station, of, state, fn() { if up() { data().liked.rev() } else { data().liked } }, saved, close,
            starred=true, reveal=fn() { !data().searching })
        })
      }
      let all_row = fn(into : @view.View) {
        triple_node_row(into, fn() { @sf.t("web-main.model.allModels") }, fn() { false }, fn() { state.all.set(true) }, check=false, trail_icon="chevron-right")
      }
      part.pick(fn() { (sheet(), up(), items(state.pick.get(), "efforts").length() > 0) }, fn(order, layout) {
        let (is_sheet, upwards, has_effort) = layout
        order.gap(Is(12.0)) |> ignore
        let scroll_rows = fn(into : @view.View, rows : (@view.View) -> Unit) {
          into.box(fn(room) {
            let scroll = @view.Scroll::new()
            room.max_height(By(fn() { Some(if is_sheet { dmax(room.window().1, triple_list_h) } else { triple_list_h }) }))
            .shrink(Is(1.0)).min_height(Is(Some(0.0)))
            .scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(list) {
              list.gap(Is(12.0)) |> ignore
              rows(list)
            }).clips(By(fn() { scroll.goes() })).bounds_input(By(fn() { scroll.goes() })) |> ignore
          }) |> ignore
        }
        if is_sheet {
          // Recent models stay next to the settings while favourites and the way to all models scroll on a short sheet.
          let apart = fn(into : @view.View) {
            scroll_rows(into, fn(list) {
              if upwards { all_row(list); liked(list) } else { liked(list); all_row(list) }
            })
          }
          if upwards { apart(order); recent(order) } else { recent(order); apart(order) }
        } else if has_effort || !upwards {
          scroll_rows(order, fn(list) { recent(list); liked(list) })
          all_row(order)
        } else {
          all_row(order)
          scroll_rows(order, fn(list) { liked(list); recent(list) })
        }
      })
    }
  })
  parent.box(fn(layer) {
    layer.over(Is(true)) |> ignore
    state.tips_at.val = Some(layer)
  }) |> ignore
}

///|
fn triple_node_search(parent : @view.View, state : TripleNodePanel) -> Unit {
  parent.show(fn() { items(state.pick.get(), "options").length() > 8 }, fn(slot) {
    slot.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    slot.box(fn(line) {
      let editor : Ref[@view.View?] = Ref(None)
      line.row(Is(true)).height(Is(Some(@sf.menu_row_min))).padding(Is((12.0, 0.0, 12.0, 0.0)))
      .gap(Is(8.0)).lines_up(Is(Some(Middle))).radius(Is(10000.0))
      .ground(By(fn() {
        @ui.tree_theme().color(if line.pointed() || (editor.val is Some(input) && input.focused()) { TintStrong } else { Tint })
      })) |> ignore
      @sf.icon_node(line, "search", triple_find_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      editor.val = Some(@ui.field(line, state.field, placeholder_by=fn() { @sf.t("web-main.model.search") },
        line=@sf.theme().t.ui_line, max_lines=1, enter_sends=true,
        size_by=fn() { @sf.theme().t.ui }, colors_by=fn() {
          let t = @ui.tree_theme()
          (t.fg, t.subtle, t.accent)
        })
      .grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))))
    }) |> ignore
  })
}

///|
fn triple_node_efforts(parent : @view.View, src : Source, station : String, of : String, state : TripleNodePanel) -> Unit {
  let pick = fn() { state.pick.get() }
  let current = fn() {
    match text(field(pick(), "draft"), "effort") {
      "" => text(pick(), "effortDefault")
      e => e
    }
  }
  parent.each(fn() { items(pick(), "efforts").filter_map(fn(e) { if e is String(e) { Some(e) } else { None } }) }, fn(e) { e }, fn(slot, effort) {
    let selected = fn() { current() == effort.get() }
    slot.box(fn(row) {
      @sf.style_node(row, fn() { triple_option_style })
      row.min_height(By(fn() { Some(@sf.theme().rows.pick) }))
      .ground(By(fn() { if selected() || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
      .says(By(fn() { Some(@view.said(Radio, label=effort_text(effort.get()), check=if selected() { On } else { Off })) })) |> ignore
      @sf.presses_node(row, fn() { pick_save(src, station, of, { "effort": Json::string(effort.get()) }) })
      @sf.words_node(row, fn() { effort_text(effort.get()) }, fn() { if selected() { triple_picked } else { triple_words } })
      .grow(Is(1.0)) |> ignore
      row.box(fn(check) {
        check.width(Is(Some(14.0))) |> ignore
        check.show(selected, fn(mark) { @sf.icon_node(mark, "check", 14.0, By(fn() { @sf.theme().p.accent })) |> ignore })
      }) |> ignore
    }) |> ignore
  })
}

///|
/// A panel control whose action opens another pick; its anchor is the actual node the person pressed.
fn triple_node_setting(
  parent : @view.View,
  title : () -> String,
  value : () -> String,
  open : (@view.View) -> Unit,
  runtime? : () -> String,
  value_style? : () -> @ui.TextStyle = fn() { triple_who_name },
  requested? : () -> Bool,
  accepted? : () -> Unit = fn() {  },
  made? : (@view.View) -> Unit = fn(_) {  },
) -> Unit {
  parent.box(fn(row) {
    row.row(Is(true)).height(By(fn() { Some(@sf.button_height()) })).padding(Is((10.0, 0.0, 10.0, 0.0)))
    .gap(Is(4.0)).lines_up(Is(Some(Middle))).radius(Is(10000.0))
    .ground(By(fn() { if @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=value())) })) |> ignore
    @sf.presses_node(row, fn() { open(row) })
    made(row)
    match requested {
      Some(read) => row.reacts(read, fn(asked) { if asked { accepted(); open(row) } })
      None => ()
    }
    @sf.words_node(row, title, fn() { triple_who_lead }) |> ignore
    match runtime {
      Some(read) => @sf.maker_mark_node(row, fn() { "" }, read, triple_pick_mark) |> ignore
      None => ()
    }
    @sf.words_node(row, value, value_style) |> ignore
  }) |> ignore
}

///|
/// A sheet puts effort and runtime on full-width rows, with the values and their picker affordances aligned.
fn triple_node_sheet_setting(
  parent : @view.View,
  title : () -> String,
  value : () -> String,
  head_width : () -> Double,
  open : (@view.View) -> Unit,
  runtime? : () -> String,
  made? : (@view.View) -> Unit = fn(_) {  },
) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { triple_option_style })
    row.min_height(By(fn() { Some(@sf.theme().rows.pick) })).gap(Is(12.0))
    .ground(By(fn() { if @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=value())) })) |> ignore
    @sf.presses_node(row, fn() { open(row) })
    made(row)
    row.box(fn(head) {
      head.width(By(fn() { Some(head_width()) })) |> ignore
      @sf.words_node(head, title, fn() { triple_head }) |> ignore
    }) |> ignore
    row.box(fn(current) {
      current.row(Is(true)).gap(Is(6.0)).grow(Is(1.0)).lines_up(Is(Some(Middle))) |> ignore
      match runtime {
        Some(read) => @sf.maker_mark_node(current, fn() { "" }, read, triple_pick_mark) |> ignore
        None => ()
      }
      @sf.words_node(current, value, fn() { triple_words }) |> ignore
    }) |> ignore
    @sf.icon_node(row, "chevron-down", triple_pick_chevron, By(fn() { @sf.theme().p.muted })) |> ignore
  }) |> ignore
}

///|
/// The retained model panel body. How it opens a subordinate picker belongs to the presenter, not the list.
fn triple_node_body(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  state : TripleNodePanel,
  sheet : () -> Bool,
  up : () -> Bool,
  saved : String,
  close : () -> Unit,
  open_pick : (String, @view.View) -> Unit,
) -> Unit {
  triple_node_follow_pick(parent, state, src, station, of)
  let pick = fn() { state.pick.get() }
  let all = fn() { triple_models(pick(), state.field.text(), state.all.get(), state.kind.get(), sheet()).all }
  let effort = fn() {
    match text(field(pick(), "draft"), "effort") {
      "" => text(pick(), "effortDefault")
      e => e
    }
  }
  let runtime = fn() { text(field(pick(), "draft"), "runtime") }
  parent.show(fn() { pick() is None }, fn(wait) {
    @sf.waiting_node(wait, fn(bones) {
      let sample = triple_node_panel_state(Some(triple_sample()))
      triple_node_catalog(bones, @sfbase.sample_source, station, of, sample, sheet, up, "", fn() {  })
    })
  })
  parent.show(fn() { pick() is Some(_) }, fn(body) {
    body.box(fn(content) {
      content.row(By(fn() { !sheet() })).gap(Is(8.0)) |> ignore
      content.box(fn(models) {
        models.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        // This header and its input stay mounted while the sheet becomes an anchored panel or vice versa.
        models.box(fn(head) {
          head.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0)) |> ignore
          head.show(fn() { !sheet() }, fn(title) {
            @sf.words_node(title, fn() { @sf.t("android-chat.new.model") }, fn() { triple_picked }).grow(Is(1.0)) |> ignore
          })
          triple_node_search(head, state)
        }) |> ignore
        models.pick(fn() { (sheet(), up()) }, fn(part, layout) {
          let (is_sheet, upwards) = layout
          let head_width = fn() {
            part.words_redone() |> ignore
            let c = @ui.current()
            let across = Ref(0.0)
            // Retained words use the tree's theme; a binding may run outside the old frame's themed build.
            c.with_theme(@ui.tree_theme(), fn() {
              across.val = dmax(c.words_across(@sf.t("web-main.model.effort"), triple_head),
                c.words_across(@sf.t("web-main.model.runtime"), triple_head)).ceil()
            })
            across.val
          }
          let how = fn(into : @view.View) {
            into.show(fn() {
              !all() && (items(pick(), "efforts").length() > 0 ||
                (!flag(pick(), "runtimeFixed") && items(pick(), "runtimes").length() > 1))
            }, fn(tray) {
              @sf.style_node(tray, fn() { if upwards { triple_tray } else { triple_tray_first } })
              tray.show(fn() { items(pick(), "efforts").length() > 0 }, fn(row) {
                triple_node_sheet_setting(row, fn() { @sf.t("web-main.model.effort") }, fn() { effort_text(effort()) }, head_width,
                  fn(at) { open_pick("effort", at) }, made=fn(at) { (state.pick_anchor.val)("effort", at) })
              })
              tray.show(fn() { !flag(pick(), "runtimeFixed") && items(pick(), "runtimes").length() > 1 }, fn(row) {
                triple_node_sheet_setting(row, fn() { @sf.t("web-main.model.runtime") }, fn() { @settings.runtime_label(runtime()) }, head_width,
                  fn(at) { open_pick("runtime", at) }, runtime=runtime, made=fn(at) { (state.pick_anchor.val)("runtime", at) })
              })
            })
          }
          if is_sheet && !upwards { how(part) }
          triple_node_catalog(part, src, station, of, state, sheet, up, saved, close)
          if is_sheet && upwards { how(part) }
        })
      }) |> ignore
      content.show(fn() { !sheet() && !all() && items(pick(), "efforts").length() > 0 }, fn(efforts) {
        (state.pick_anchor.val)("effort", efforts)
        efforts.box(fn(head) {
          @sf.words_node(head, fn() { @sf.t("web-main.model.effort") }, fn() { triple_picked }) |> ignore
        }) |> ignore
        triple_node_efforts(efforts, src, station, of, state)
      })
    }) |> ignore
    body.show(fn() { field(pick(), "borrow") is Some(Object(_)) }, fn(note) {
      @sf.style_node(note, fn() { triple_borrow })
      @sf.words_node(note, fn() {
        let borrow = field(pick(), "borrow")
        if flag(borrow, "allowed") { text(borrow, "note") } else { text(borrow, "why") }
      }, fn() { triple_note }) |> ignore
    })
  })
}

///|
fn triple_node_foot(
  parent : @view.View,
  state : TripleNodePanel,
  sheet : () -> Bool,
  open_pick : (String, @view.View) -> Unit,
  borrow : () -> Unit,
  me? : String = "",
) -> Unit {
  let pick = fn() { state.pick.get() }
  let draft = fn() { field(pick(), "draft") }
  parent.show(fn() { pick() is Some(_) }, fn(foot) {
    foot.row(Is(true)).gap(Is(4.0)).wraps(Is(Some(4.0))).lines_up(Is(Some(Middle))) |> ignore
    triple_node_setting(foot, fn() { @sf.t("web-main.model.account") }, fn() {
      if text(draft(), "profile") != "" { text(pick(), "who") } else { @sf.t("web-main.model.auto") }
    }, fn(at) { open_pick("account", at) }, value_style=fn() {
      match text(pick(), "whoLevel") { "amber" => triple_amber_sm; "red" => triple_red_sm; _ => triple_who_name }
    }, requested=fn() { me != "" && triple.accounts_asked.get() == me }, accepted=fn() { triple.accounts_asked.set("") },
      made=fn(at) { (state.pick_anchor.val)("account", at) })
    foot.show(fn() { !sheet() && !flag(pick(), "runtimeFixed") && items(pick(), "runtimes").length() > 1 }, fn(room) {
      room.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      room.box(fn(rule) { @sf.style_node(rule, fn() { triple_foot_rule }) }) |> ignore
      triple_node_setting(room, fn() { @sf.t("web-main.model.runtime") }, fn() { @settings.runtime_label(text(draft(), "runtime")) },
        fn(at) { open_pick("runtime", at) }, runtime=fn() { text(draft(), "runtime") }, made=fn(at) { (state.pick_anchor.val)("runtime", at) })
    })
    foot.show(fn() { flag(pick(), "fastAvailable") }, fn(room) {
      room.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      room.box(fn(rule) { @sf.style_node(rule, fn() { triple_foot_rule }) }) |> ignore
      triple_node_setting(room, fn() { @sf.t("web-main.model.speed") }, fn() {
        match field(draft(), "fast") {
          Some(True) => "Fast"
          Some(False) => @sf.t("web-main.model.standard")
          _ => if flag(pick(), "fastPlan") { "Fast" } else { @sf.t("web-main.model.standard") }
        }
      }, fn(at) { open_pick("fast", at) }, made=fn(at) { (state.pick_anchor.val)("fast", at) })
    })
    foot.show(fn() { !items(pick(), "contexts").is_empty() }, fn(room) {
      room.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      room.box(fn(rule) { @sf.style_node(rule, fn() { triple_foot_rule }) }) |> ignore
      triple_node_setting(room, fn() { @sf.t("web-main.model.context") }, fn() {
        let now = text(pick(), "contextNow")
        text(items(pick(), "contexts").iter().find_first(fn(c) { text(Some(c), "id") == now }), "text")
      }, fn(at) { open_pick("context", at) }, made=fn(at) { (state.pick_anchor.val)("context", at) })
    })
    foot.show(fn() { field(pick(), "borrow") is Some(Object(_)) }, fn(room) {
      @sf.button_node(room, fn() { text(field(pick(), "borrow"), "action") }, borrow, tone=Primary,
        disabled=fn() { !flag(field(pick(), "borrow"), "allowed") }) |> ignore
    })
  })
}

///|
/// The choices in a subordinate runtime, effort, speed or context picker. Each saves immediately, as the old pick does.
fn triple_node_pick_body(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  state : TripleNodePanel,
  which : String,
  close : () -> Unit,
) -> Unit {
  let pick = fn() { state.pick.get() }
  let draft = fn() { field(pick(), "draft") }
  let choices = fn() -> Array[(String, String)] {
    match which {
      "runtime" => items(pick(), "runtimes").filter_map(fn(r) {
        if r is String(r) { Some((r, @settings.runtime_label(r))) } else { None }
      })
      "effort" => items(pick(), "efforts").filter_map(fn(e) {
        if e is String(e) { Some((e, effort_text(e))) } else { None }
      })
      "fast" => [("standard", @sf.t("web-main.model.standard")), ("fast", "Fast")]
      "context" => items(pick(), "contexts").map(fn(c) { (text(Some(c), "id"), text(Some(c), "text")) })
      _ => []
    }
  }
  let current = fn() {
    match which {
      "runtime" => text(draft(), "runtime")
      "effort" => match text(draft(), "effort") { "" => text(pick(), "effortDefault"); e => e }
      "fast" => match field(draft(), "fast") {
        Some(True) => "fast"
        Some(False) => "standard"
        _ => if flag(pick(), "fastPlan") { "fast" } else { "standard" }
      }
      "context" => text(pick(), "contextNow")
      _ => ""
    }
  }
  parent.each(choices, fn(choice) { choice.0 }, fn(slot, choice) {
    let selected = fn() { choice.get().0 == current() }
    slot.box(fn(row) {
      @sf.style_node(row, fn() { triple_option_style })
      row.min_height(By(fn() { Some(@sf.theme().rows.pick) }))
      .ground(By(fn() { if selected() || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
      .says(By(fn() { Some(@view.said(Radio, label=choice.get().1, check=if selected() { On } else { Off })) })) |> ignore
      @sf.presses_node(row, fn() {
        let value = choice.get().0
        let patch : Map[String, Json] = match which {
          "runtime" => { "runtime": Json::string(value) }
          "effort" => { "effort": if value == "" { Json::null() } else { Json::string(value) } }
          "fast" => { "fast": Json::boolean(value == "fast") }
          "context" => { "context": if value == "" { Json::null() } else { Json::string(value) } }
          _ => {}
        }
        close()
        if !patch.is_empty() { pick_save(src, station, of, patch) }
      })
      row.box(fn(words) {
        words.grow(Is(1.0)) |> ignore
        @sf.words_node(words, fn() { choice.get().1 }, fn() { if selected() { triple_picked } else { triple_words } }) |> ignore
        words.show(fn() { which == "fast" && choice.get().0 == "fast" }, fn(note) {
          @sf.words_node(note, fn() { @sf.t("web-main.model.fastNote") }, fn() { triple_note }) |> ignore
        })
      }) |> ignore
      row.box(fn(check) {
        check.width(Is(Some(14.0))) |> ignore
        check.show(selected, fn(mark) { @sf.icon_node(mark, "check", 14.0, By(fn() { @sf.theme().p.accent })) |> ignore })
      }) |> ignore
    }) |> ignore
  })
}

///|
fn triple_node_accounts(parent : @view.View, src : Source, station : String, of : String, state : TripleNodePanel, close : () -> Unit) -> Unit {
  let pick = fn() { state.pick.get() }
  let current = fn() { text(field(pick(), "draft"), "profile") }
  parent.show(fn() { text(pick(), "dropped") != "" }, fn(note) {
    @sf.words_node(note, fn() { text(pick(), "dropped") }, fn() { triple_amber_sm }) |> ignore
  })
  parent.box(fn(auto) {
    auto.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
    auto.box(fn(select) {
      select.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      triple_node_row(select, fn() { @sf.t("web-main.model.auto") }, fn() { current() == "" }, fn() {
        pick_save(src, station, of, { "profile": Json::null() })
        close()
      })
      select.show(fn() { text(pick(), "autoNote") != "" }, fn(note) {
        @sf.words_node(note, fn() { text(pick(), "autoNote") }, fn() { triple_note_cut }) |> ignore
      })
    }) |> ignore
    auto.show(fn() { text(pick(), "repick") != "" }, fn(slot) {
      let key = "pick.repick/" + station + "/" + of
      @sf.button_node(slot, fn() { text(pick(), "repick") }, fn() {
        act(src, text(pick(), "repick"), key, "pick.repick", Json::object(pick_params(station, of)), ok=fn(r) {
          match text(Some(r), "said") { "" => (); said => toast_later(said) }
        })
      }, busy=fn() { doing(key) }) |> ignore
    })
  }) |> ignore
  parent.each(fn() { items(pick(), "accounts") }, fn(account) { text(Some(account), "id") }, fn(slot, account) {
    let a = fn() { Some(account.get()) }
    let id = fn() { text(a(), "id") }
    slot.box(fn(row) {
      @sf.style_node(row, fn() { triple_option_style })
      row.min_height(By(fn() { Some(@sf.theme().rows.pick) }))
      .ground(By(fn() { if current() == id() || @sf.lit_node(row) { @sf.theme().p.hover } else { 0L } }))
      .says(By(fn() { Some(@view.said(Button, label=text(a(), "name"), selected=current() == id())) })) |> ignore
      @sf.presses_node(row, fn() { pick_save(src, station, of, { "profile": Json::string(id()) }); close() })
      row.box(fn(words) {
        words.grow(Is(1.0)).gap(Is(1.0)) |> ignore
        @sf.words_node(words, fn() { text(a(), "name") }, fn() { if current() == id() { triple_picked } else { triple_words } }) |> ignore
        words.show(fn() { text(field(a(), "quotaLine"), "text") != "" }, fn(quota) {
          @sf.words_node(quota, fn() { text(field(a(), "quotaLine"), "text") }, fn() {
            match text(field(a(), "quotaLine"), "level") { "amber" => triple_amber_sm; "red" => triple_red_sm; _ => triple_note }
          }) |> ignore
        })
      }) |> ignore
      row.box(fn(check) {
        check.width(Is(Some(14.0))) |> ignore
        check.show(fn() { current() == id() }, fn(mark) { @sf.icon_node(mark, "check", 14.0, By(fn() { @sf.theme().p.accent })) |> ignore })
      }) |> ignore
    }) |> ignore
  })
}

///|
fn triple_node_borrow_body(parent : @view.View, state : TripleNodePanel) -> Unit {
  parent.each(fn() { items(field(state.pick.get(), "borrow"), "lines").mapi(fn(i, line) { (i, line) }) }, fn(line) { line.0 }, fn(slot, line) {
    @sf.words_node(slot, fn() { if line.get().1 is String(words) { words } else { "" } }, fn() { confirm_line }) |> ignore
  })
}

///|
fn triple_node_borrow_foot(parent : @view.View, src : Source, station : String, of : String, state : TripleNodePanel, close : () -> Unit) -> Unit {
  let key = "pick.borrow/" + station + "/" + of
  let borrow = fn() { field(state.pick.get(), "borrow") }
  parent.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).lies_along(Is(End)) |> ignore
  @sf.button_node(parent, fn() { @sf.t("common.cancel") }, close, tone=Ghost) |> ignore
  @sf.button_node(parent, fn() { text(borrow(), "action") }, fn() {
    act(src, text(borrow(), "action"), key, "pick.borrow", Json::object(pick_params(station, of)),
      done=@sf.t("web-main.model.borrowed"), ok=fn(_) { close() })
  }, tone=Primary, busy=fn() { doing(key) }, disabled=fn() { !flag(borrow(), "allowed") }) |> ignore
}
