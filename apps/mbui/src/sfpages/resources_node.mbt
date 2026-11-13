// What still.fail uses of a station's machine (resources.mbt's, as nodes of a page made once, from its styles): a
// station's page's 进程 and the line its overview says it in. What is chosen in it (whose, how, the column sorted by,
// the groups open) is rs_shown's, by station, followed as it changes.

///|
/// Its 进程 (station_processes', online): what is counted over the page, then the body; nothing read yet, its bones.
fn resources_node(p : @view.View, core : Core, here : () -> Here, address : String) -> Unit {
  let v = fn() { resources_of(core, here(), address) }
  p.box(fn(k) {
    @sf.style_node(k, fn() { rs_processes })
    @sf.words_node(k, fn() { @sf.t("web-pages.stations.processesLead") }, fn() { st_memory }) |> ignore
    k.pick(fn() { v() is Some(Object(_)) }, fn(b, read) {
      if read {
        resources_body_node(b, core, address, v)
      } else {
        @sf.waiting_node(b, fn(w) {
          @sf.style_node(w, fn() { rs_page })
          rs_figures_node(w, core.quiet(), "sample", fn() { Some(rs_sample_view()) })
        })
      }
    })
  })
  |> ignore
}

///|
/// The body (resources_body's): empty, a wait (or that there is nothing to see); else its totals, the choice of whose
/// and of how, the table; how it is read under either.
fn resources_body_node(b : @view.View, core : Core, address : String, v : () -> Json?) -> Unit {
  // (0: seen; 1: nothing yet, read; 2: nothing to see)
  let state = fn() {
    let now = v()
    if !flag(now, "empty") {
      0
    } else {
      let wait = field(now, "wait")
      if flag(wait, "reading") || items(wait, "failing").length() > 0 { 1 } else { 2 }
    }
  }
  b.pick(state, fn(r, k) {
    @sf.style_node(r, fn() { rs_page })
    match k {
      0 => rs_figures_node(r, core, address, v)
      1 => @sf.waiting_node(r, fn(w) { rs_figures_node(w, core.quiet(), "sample", fn() { Some(rs_sample_view()) }) })
      _ => @sf.words_node(r, fn() { @sf.t("web-main.resources.none") }, fn() { rs_empty }) |> ignore
    }
    rs_foot_node(r, v, k == 0)
  })
}

///|
/// What is seen of the machine (rs_figures_of's): its totals in pairs, the choice of whose and of how on a line apart
/// at its ends, the table.
fn rs_figures_node(r : @view.View, core : Core, address : String, v : () -> Json?) -> Unit {
  let tiles = fn() { items(v(), "tiles") }
  r.box(fn(ts) {
    @sf.style_node(ts, fn() { rs_tiles })
    ts.wraps(Is(Some(rs_flow_lines))) |> ignore
    ts.each(fn() { Array::makei((tiles().length() + 1) / 2, fn(k) { k }) }, fn(k) { k }, fn(pair, k) {
      let k = k.untracked()
      @sf.style_node(pair, fn() { rs_tile_pair }, in_row=true)
      // (never narrower than its tiles at their least, so a pair without the room on its line goes under the other)
      pair
      .shrink(Is(0.0))
      .min_width(By(fn() {
        let n = @cmp.minimum(2, tiles().length() - k * 2).to_double()
        Some(n * rs_tile_least + dmax(n - 1.0, 0.0) * rs_tile_gap)
      }))
      |> ignore
      for i in (k * 2)..<(k * 2 + 2) {
        pair.show(fn() { i < tiles().length() }, fn(t) {
          // (as wide as a tile is at least, so a pair that has not the room on its line goes under the other: rs_tile_box's)
          t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(rs_tile_least))) |> ignore
          rs_tile_node(t, fn() { tiles().get(i) })
        })
      }
    })
  })
  |> ignore
  let shown = fn() { rs_shown_of(address) }
  r.box(fn(bar) {
    @sf.style_node(bar, fn() { rs_bar })
    bar.wraps(Is(Some(rs_flow_lines))) |> ignore
    let keys = fn() { ["all"] + items(v(), "kinds").map(fn(k) { text(Some(k), "key") }) }
    bar.box(fn(slot) {
      @sf.segmented_node(
        slot,
        fn() { [@sf.t("web-main.resources.all")] + items(v(), "kinds").map(fn(k) { text(Some(k), "label") }) },
        fn() { keys().search(shown().kind).unwrap_or(0) },
        fn(i) {
          match keys().get(i) {
            Some(kind) => rs_shown[address] = { ..rs_shown_of(address), kind: kind }
            None => ()
          }
        },
      )
    })
    |> ignore
    bar.box(fn(slot) {
      @sf.segmented_node(
        slot,
        fn() { [@sf.t("web-main.resources.grouped"), @sf.t("web-main.resources.flat")] },
        fn() { if shown().flat { 1 } else { 0 } },
        fn(i) { rs_shown[address] = { ..rs_shown_of(address), flat: i == 1 } },
      )
    })
    |> ignore
  })
  |> ignore
  let groups = fn() {
    let kind = shown().kind
    items(v(), "groups").filter(fn(g) { kind == "all" || text(Some(g), "kind") == kind })
  }
  r.pick(fn() { shown().flat }, fn(t, flat) { rs_table_node(t, core, address, groups, fn() { rs_columns_of(v()) }, flat) })
}

///|
/// A total, said, with the last minutes' line under it (rs_tile's), the line as wide as the tile is laid out.
fn rs_tile_node(t : @view.View, tv : () -> Json?) -> Unit {
  t.box(fn(b) {
    @sf.style_node(b, fn() { rs_tile_box })
    b.box(fn(h) {
      @sf.style_node(h, fn() { rs_tile_head })
      @sf.words_node(h, fn() { text(tv(), "label") }, fn() { rs_tile_label }) |> ignore
      @sf.words_node(h, fn() { text(tv(), "sub") }, fn() { rs_tile_sub }) |> ignore
    })
    |> ignore
    @sf.words_node(b, fn() { text(tv(), "value") }, fn() { rs_tile_value }) |> ignore
    b.box(fn(s) {
      @sf.style_node(s, fn() { rs_spark })
      // (drawn across the room it is given)
      s.by_room(fn(line, room) {
        line
        .height(Is(Some(rs_spark_h)))
        .shapes(By(fn() {
          let w = room.width()
          if w > 0.0 {
            rs_spark_shapes(number_list(tv(), "points"), w, rs_spark_ink(text(tv(), "key")))
          } else {
            []
          }
        }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row of the table (rs_grouped's, rs_flat's), by what it is: a group (its key), a process under its group (the
/// group's key and its), a process flat (its group's key and its).
#derive(Eq, Hash)
priv enum RsRow {
  RsGroup(String)
  RsUnder(String, String)
  RsFlat(String, String)
}

///|
/// The table (rs_grouped's, `flat` rs_flat's): its heads, then its rows, the most of the column sorted by first; laid
/// out by how wide it is given to be (rs_layout_of, by its room: View::by_room).
fn rs_table_node(
  t : @view.View,
  core : Core,
  address : String,
  groups : () -> Array[Json],
  columns : () -> Array[(String, String)],
  flat : Bool,
) -> Unit {
  let by = fn() { rs_shown_of(address).by }
  let group_of = fn(key : String) { groups().iter().find_first(fn(g) { text(Some(g), "key") == key }) }
  let process_of = fn(gkey : String, key : String) {
    items(group_of(gkey), "processes").iter().find_first(fn(p) { text(Some(p), "key") == key })
  }
  let use_of = fn(j : Json?) { rs_use(field(j, "use"), by()) }
  let most = fn() {
    if flat {
      groups().fold(init=0.0, fn(m, g) { items(Some(g), "processes").fold(init=m, fn(m, p) { @cmp.maximum(m, use_of(Some(p))) }) })
    } else {
      groups().fold(init=0.0, fn(m, g) { @cmp.maximum(m, use_of(Some(g))) })
    }
  }
  let rows = fn() {
    let out : Array[RsRow] = []
    if flat {
      let all : Array[(Json, String)] = []
      for g in groups() {
        for p in items(Some(g), "processes") {
          all.push((p, text(Some(g), "key")))
        }
      }
      all.sort_by(fn(a, b) { use_of(Some(b.0)).compare(use_of(Some(a.0))) })
      for r in all {
        out.push(RsFlat(r.1, text(Some(r.0), "key")))
      }
    } else {
      let shown = rs_shown_of(address)
      let gs = groups()
      let sorted = gs.copy()
      sorted.sort_by(fn(a, b) { use_of(Some(b)).compare(use_of(Some(a))) })
      for g in sorted {
        let key = text(Some(g), "key")
        out.push(RsGroup(key))
        if rs_open(shown, gs, key) {
          let ps = items(Some(g), "processes").copy()
          ps.sort_by(fn(a, b) { use_of(Some(b)).compare(use_of(Some(a))) })
          for p in ps {
            out.push(RsUnder(key, text(Some(p), "key")))
          }
        }
      }
    }
    out
  }
  // (its heads and rows by how wide it is given to be, laid out in that same layout)
  t.by_room(fn(table, room) {
    @sf.style_node(table, fn() { rs_table })
    // (every figure it says, a group's processes' too, open or not: none moves as a group opens)
    let lay = @signals.computed(fn(_) {
      let th = @ui.tree_theme()
      let figures : Array[(Json?, Bool)] = []
      for g in groups() {
        if !flat {
          figures.push((field(Some(g), "use"), true))
        }
        for p in items(Some(g), "processes") {
          figures.push((field(Some(p), "use"), flat))
        }
      }
      rs_layout_of(
        room.width(),
        @sf.node_sp(table, th.text_size(Xs).0),
        @sf.node_sp(table, th.text_size(Sm).0),
        figures,
        columns(),
        by(),
        if flat { 2 } else { 1 },
      )
    })
    let lay = fn() { lay.get() }
    rs_heads_node(table, address, flat, columns, lay)
    table.each(rows, fn(r) { r }, fn(row, r) {
      let r = r.untracked()
      match r {
        RsGroup(key) => {
          let g = fn() { group_of(key) }
          let on = fn() { rs_open(rs_shown_of(address), groups(), key) }
          rs_row_node(
            row,
            lay,
            group=true,
            press=fn() { rs_open_or_shut(address, groups(), key) },
            said=fn() { Some(@view.said(Button, label=text(g(), "title"), expanded=on())) },
            fn(n) {
              n.box(fn(cell) {
                @sf.style_node(cell, fn() { rs_name_cell }, in_row=true)
                cell.box(fn(name) {
                  @sf.style_node(name, fn() { rs_name })
                  @sf.icon_node(
                    name,
                    if @signals.untracked(on) { "chevron-down" } else { "chevron-right" },
                    rs_toggle,
                    By(fn() { @sf.theme().p.subtle }),
                    name_now=fn() { if on() { "chevron-down" } else { "chevron-right" } },
                  )
                  |> ignore
                  rs_title_node(name, core, g, rs_name_text)
                  @sf.words_node(
                    name,
                    fn() { join([text(g(), "kindText"), items(g(), "processes").length().to_string()], " · ") },
                    fn() { rs_meta },
                  )
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            },
            fn(f) { rs_figures_node_of(f, fn() { field(g(), "use") }, columns, by, most, lay, false) },
            fn(_) {  },
          )
        }
        RsUnder(gkey, key) => {
          let p = fn() { process_of(gkey, key) }
          rs_row_node(
            row,
            lay,
            fn(n) {
              n.box(fn(cell) {
                @sf.style_node(cell, fn() { rs_process_cell }, in_row=true)
                @sf.words_node(cell, fn() { text(p(), "name") }, fn() { rs_process_name }) |> ignore
                @sf.words_node(cell, fn() { number(p(), "pid").to_int().to_string() }, fn() { rs_meta }) |> ignore
              })
              |> ignore
            },
            fn(f) { rs_figures_node_of(f, fn() { field(p(), "use") }, columns, by, most, lay, true) },
            fn(e) { rs_end_node(e, core, p, fn() { group_of(gkey) }, row) },
          )
        }
        RsFlat(gkey, key) => {
          let p = fn() { process_of(gkey, key) }
          let g = fn() { group_of(gkey) }
          rs_row_node(
            row,
            lay,
            fn(n) {
              n.box(fn(cell) {
                @sf.style_node(cell, fn() { rs_name_cell }, in_row=true)
                cell.box(fn(name) {
                  @sf.style_node(name, fn() { rs_name })
                  @sf.words_node(name, fn() { text(p(), "name") }, fn() { rs_cell_words }) |> ignore
                  @sf.words_node(name, fn() { number(p(), "pid").to_int().to_string() }, fn() { rs_meta }) |> ignore
                })
                |> ignore
              })
              |> ignore
              n.box(fn(cell) {
                @sf.style_node(cell, fn() { rs_whose_cell }, in_row=true)
                rs_title_node(cell, core, g, rs_whose)
              })
              |> ignore
            },
            fn(f) { rs_figures_node_of(f, fn() { field(p(), "use") }, columns, by, most, lay, false) },
            fn(e) { rs_end_node(e, core, p, g, row) },
          )
        }
      }
    })
  })
  |> ignore
}

///|
/// A row of the table (rs_table_row's, rs_line's) in `row`: its names, its figures and its end on one line; stacked,
/// its names on a line of their own and its figures under them, its end beside both; a row's least height at least.
/// `group`: lit under the pointer, pressed (`press`), read out as `said` says.
fn rs_row_node(
  row : @view.View,
  lay : () -> RsLayout,
  group? : Bool = false,
  press? : () -> Unit,
  said? : () -> @view.Said?,
  names : (@view.View) -> Unit,
  figures : (@view.View) -> Unit,
  end : (@view.View) -> Unit,
) -> Unit {
  @sf.style_node(row, fn() { rs_row.then(@sf.row_least_h()) })
  match press {
    Some(f) => @sf.presses_node(row, f)
    None => ()
  }
  match said {
    Some(s) => row.says(By(s)) |> ignore
    None => ()
  }
  if group {
    row
    .radius(Is(@sf.row_corner))
    .ground(By(fn() { if @sf.lit_node(row) { @ui.tree_theme().color(Hover) } else { 0L } }))
    |> ignore
  }
  row.pick(fn() { lay().stacked }, fn(r, stacked) {
    r.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
    if stacked {
      r.box(fn(s) {
        @sf.style_node(s, fn() { rs_stack }, in_row=true)
        s.box(fn(n) {
          @sf.style_node(n, fn() { rs_row })
          names(n)
        })
        |> ignore
        s.box(fn(f) {
          @sf.style_node(f, fn() { rs_figures_line })
          figures(f)
        })
        |> ignore
      })
      |> ignore
    } else {
      names(r)
      figures(r)
    }
  })
  row.box(fn(e) {
    @sf.style_node(e, fn() { rs_end_cell }, in_row=true)
    end(e)
  })
  |> ignore
}

///|
/// The columns' heads (rs_heads'): the names' first (none stacked: the names have a line of their own), then each
/// column's, sorting by itself as it is pressed, lit under the pointer; the end's room.
fn rs_heads_node(
  table : @view.View,
  address : String,
  flat : Bool,
  columns : () -> Array[(String, String)],
  lay : () -> RsLayout,
) -> Unit {
  table.box(fn(h) {
    @sf.style_node(h, fn() { (if lay().stacked { rs_head_row_stacked } else { rs_head_row }).then(@sf.row_least_h()) })
    h.show(fn() { !lay().stacked }, fn(first) {
      first.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
      let heads = if flat {
        ["web-main.resources.column.process", "web-main.resources.column.whose"]
      } else {
        ["web-main.resources.column.name"]
      }
      for i, key in heads {
        first.box(fn(cell) {
          @sf.style_node(cell, fn() { if i == 0 { rs_name_cell } else { rs_whose_cell } }, in_row=true)
          @sf.words_node(cell, fn() { @sf.t(key) }, fn() { rs_head }) |> ignore
        })
        |> ignore
      }
    })
    h.each(fn() { columns().mapi(fn(k, col) { (k, col.0) }) }, fn(c) { c.1 }, fn(cell, c) {
      let col = c.untracked().1
      let k = fn() { c.get().0 }
      let on = fn() { rs_shown_of(address).by == col }
      let name = fn() { @sf.t("web-main.resources.column." + col) }
      @sf.style_node(cell, fn() { rs_column(lay(), k()) }, in_row=true)
      @sf.presses_node(cell, fn() { rs_shown[address] = { ..rs_shown_of(address), by: col } })
      cell.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.resources.by", args=[("column", name())]))) })) |> ignore
      @sf.words_node(cell, fn() { if on() { name() + " ↓" } else { name() } }, fn() {
        if on() || @sf.lit_node(cell) {
          rs_head_on
        } else {
          rs_head
        }
      })
      |> ignore
    })
    h.box(fn(e) { @sf.style_node(e, fn() { rs_end_cell }, in_row=true) }) |> ignore
  })
  |> ignore
}

///|
/// A row's figures (rs_figures'), each in its column: the sorted column's bold, with how much of the most it is
/// before it where the layout has room for it; `plain`, none so.
fn rs_figures_node_of(
  f : @view.View,
  u : () -> Json?,
  columns : () -> Array[(String, String)],
  by : () -> String,
  most : () -> Double,
  lay : () -> RsLayout,
  plain : Bool,
) -> Unit {
  f.each(fn() { columns().mapi(fn(k, col) { (k, col) }) }, fn(c) { c.1.0 }, fn(cell, c) {
    let key = c.untracked().1.0
    let strong = fn() { !plain && key == by() }
    let shared = fn() { strong() && lay().share }
    @sf.style_node(cell, fn() { rs_column(lay(), c.get().0, under=lay().stacked, shared=shared()) }, in_row=true)
    cell.show(shared, fn(s) {
      // (the room the figure leaves, the share at its start: rs_number_shared's JBetween, the share at the cell's start
      // and the figure at its end)
      s.grow(Is(1.0)) |> ignore
      let part = fn() {
        let m = most()
        if m > 0.0 { @cmp.minimum(1.0, rs_use(u(), by()) / m) } else { 0.0 }
      }
      s.box(fn(bar) {
        @sf.style_node(bar, fn() { rs_share }, in_row=true)
        bar.box(fn(x) {
          @sf.style_node(x, fn() { rs_share_fill }, in_row=true)
          x.grow(By(part)).basis(Is(Some(0.0))) |> ignore
        })
        |> ignore
        bar.box(fn(x) { x.grow(By(fn() { 1.0 - part() })).basis(Is(Some(0.0))) |> ignore }) |> ignore
      })
      |> ignore
    })
    @sf.words_node(cell, fn() { text(u(), c.get().1.1) }, fn() { if strong() { rs_figure_strong } else { rs_figure } })
    |> ignore
  })
}

///|
/// Whose a row is (rs_title's): a chat's, its chat opened from its title, underlined under the pointer, cut short where
/// its row has less room; else its title.
fn rs_title_node(p : @view.View, core : Core, g : () -> Json?, style : @ui.TextStyle) -> Unit {
  let chat = fn() { field(g(), "chat") }
  let session = fn() { text(chat(), "session") }
  p.pick(fn() { chat() is Some(Object(_)) && session() != "" }, fn(x, link) {
    x.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
    if link {
      @sf.presses_node(x, fn() { (core.open_chat)(text(chat(), "station"), session(), text(g(), "title")) })
      x.says(By(fn() { Some(@view.said(Link, label=text(g(), "title"))) })) |> ignore
      x.box(fn(w) {
        w
        .words_runs(By(fn() { [@ui.span(text(g(), "title"), underline=@sf.lit_node(x))] }))
        .words_look(Is(@ui.style_words(style)))
        .ink(By(fn() { @ui.style_ink(style) }))
        .cuts(Is(true))
        .min_width(Is(Some(0.0)))
        .allow_ellipsis(Is(true))
        |> ignore
      })
      |> ignore
    } else {
      @sf.words_node(x, fn() { text(g(), "title") }, fn() { style }) |> ignore
    }
  })
}

///|
/// Its row's end (rs_end's): a way to end the process where it may be ended, asked first: a stop of its own for the
/// keyboard (Tab reaches it, no row taking the focus), said by what it ends (结束 …); seen as its row is pointed at or
/// it has the focus (clear till then), always where the hand is a finger (more_held: no pointer hovers).
fn rs_end_node(e : @view.View, core : Core, p : () -> Json?, g : () -> Json?, row : @view.View) -> Unit {
  e.show(fn() { flag(p(), "endable") }, fn(x) {
    let name = fn() { text(p(), "name") }
    let b = @sf.icon_button_node(x, "stop", fn() { @sf.t("web-main.resources.endLabel", args=[("name", name())]) }, fn() {
      let name = name()
      let pid = number(p(), "pid")
      let gv = g()
      @sf.confirm(
        @sf.t("web-main.resources.endTitle", args=[("name", name), ("pid", pid.to_int().to_string())]),
        @sf.t("web-main.resources.endBody", args=[("chat", text(gv, "title"))]),
        @sf.t("web-main.resources.end"),
        danger=true,
        fn() { rs_end_now(core, gv, pid, name) },
      )
    }, size=rs_end_size)
    x.alpha(By(fn() { if @sf.more_held() || @sf.lit_in_node(row) || @sf.lit_node(b) { 1.0 } else { 0.0 } })) |> ignore
  })
}

///|
/// How it is read, what is missing, how it is counted (rs_foot's).
fn rs_foot_node(r : @view.View, v : () -> Json?, basis : Bool) -> Unit {
  r.box(fn(f) {
    @sf.style_node(f, fn() { rs_foot_box })
    f.show(fn() { number(v(), "everyMs") > 0.0 }, fn(x) {
      @sf.words_node(
        x,
        fn() { @sf.t("web-main.resources.every", args=[("n", (number(v(), "everyMs") / 1000.0).round().to_int().to_string())]) },
        fn() { rs_foot_words },
      )
      |> ignore
    })
    let notes = fn() {
      items(v(), "notes").filter_map(fn(n) {
        match n {
          String(w) => Some(w)
          _ => None
        }
      })
    }
    f.each(fn() { notes().mapi(fn(i, _) { i }) }, fn(i) { i }, fn(x, i) {
      let i = i.untracked()
      @sf.words_node(x, fn() { notes().get(i).unwrap_or("") }, fn() { rs_foot_words }) |> ignore
    })
    if basis {
      @sf.words_node(f, fn() { text(v(), "basis") }, fn() { rs_foot_words }) |> ignore
    }
  })
  |> ignore
}

///|
/// What still.fail uses of the machine (station_uses'): a quiet line, the whole of it opening its 进程; its name beside
/// its figures where the line has the room for all of them, else over them; the network's figure where the station
/// reads it.
fn station_uses_node(p : @view.View, address : String, uv : () -> Json?) -> Unit {
  let name = fn() { @sf.t("web-pages.stations.uses", args=[("name", "still.fail")]) }
  p.box(fn(b) {
    @sf.style_node(b, fn() { rs_uses })
    @sf.presses_node(b, fn() { @settings.station_parts[address] = "processes" })
    b.says(By(fn() { Some(@view.said(Link, label=name())) })) |> ignore
    let lit = fn() { @sf.lit_node(b) }
    let figures = fn(f : @view.View) {
      let u = fn() { field(uv(), "use") }
      let figure = fn(label : () -> String, value : () -> String) {
        f.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(label() + " "), @ui.span(value(), weight=500, color=@sf.theme().p.text)] }))
          .words_look(Is(@ui.style_words(rs_uses_words)))
          .ink(By(fn() { @ui.style_ink(rs_uses_words) }))
          |> ignore
        })
        |> ignore
      }
      figure(fn() { "CPU" }, fn() { text(u(), "cpuText") })
      figure(fn() { @sf.t("web-main.resources.column.memory") }, fn() { text(u(), "memoryText") })
      f.show(fn() { flag(uv(), "net") }, fn(x) {
        x.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(@sf.t("web-main.resources.column.net") + " "), @ui.span(text(u(), "netText"), weight=500, color=@sf.theme().p.text)] }))
          .words_look(Is(@ui.style_words(rs_uses_words)))
          .ink(By(fn() { @ui.style_ink(rs_uses_words) }))
          |> ignore
        })
        |> ignore
      })
    }
    // (the line beside its name left out of its row where it has not the room, the one under it there only then:
    // View::drops)
    b.box(fn(ways) {
      @sf.style_node(ways, fn() { rs_uses_ways }, in_row=true)
      ways.fits(Is(true)) |> ignore
      ways.box(fn(beside) {
        @sf.style_node(beside, fn() { rs_uses_beside }, in_row=true)
        beside.drops(Is(1)) |> ignore
        @sf.words_node(beside, name, fn() { if lit() { rs_uses_lit } else { rs_uses_words } }) |> ignore
        beside.box(fn(f) {
          @sf.style_node(f, fn() { rs_uses_one_line }, in_row=true)
          figures(f)
        })
        |> ignore
      })
      |> ignore
      ways.box(fn(over) {
        @sf.style_node(over, fn() { rs_uses_over }, in_row=true)
        over.drops(Is(-1)) |> ignore
        @sf.words_node(over, name, fn() { if lit() { rs_uses_lit } else { rs_uses_words } }) |> ignore
        over.box(fn(f) {
          @sf.style_node(f, fn() { rs_uses_figures })
          f.wraps(Is(Some(rs_uses_gap))) |> ignore
          figures(f)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    @sf.icon_node(b, "chevron-right", rs_uses_chevron, By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } }))
    |> ignore
  })
  |> ignore
}

///|
/// A total's tile at its narrowest (rs_tile_box's min_w=S36).
let rs_tile_least : Double = @ui.Space::S36.px()

///|
/// A pair's tiles apart (rs_tile_pair's gap=S2).
let rs_tile_gap : Double = @ui.Space::S2.px()
