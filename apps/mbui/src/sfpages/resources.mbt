// What still.fail uses of a station's machine, as Activity Monitor says it (ember web/src/Resources.tsx ResourcesBody,
// Resources.css.ts; the core's `resources` view, client/core-ts/src/views/resources.ts): a station's page's 进程, and
// the line its overview says it in (StationCards.tsx Uses). Its totals with the last minutes' line under each, whose
// uses what (a chat, the agents, the desktop app, the station) grouped or every process flat, sorted by a column, a
// chat's process ended from its row (asked first). Laid out by its own width: the totals four in a row or two over
// two; the table's columns each as wide as its widest figure, so its rows line up, and where its names would have too
// little room beside them (a phone's), each row's names on a line over its figures.

///|
/// The core's `resources` view of the workspace in view, for station `address` (read, the station looking often,
/// while shown).
fn resources_of(core : Core, here : Here, address : String) -> Json? {
  (core.topic)("resources", { "scope": str(here.workspace), "station": str(address) }).value
}

///|
/// The columns (ALL), each by its key: what it sorts by, the figure it says.
// kept across runs: a table, never written
let rs_columns : Array[(String, String)] = [
  ("cpu", "cpuText"),
  ("memory", "memoryText"),
  ("net", "netText"),
  ("disk", "diskText"),
]

///|
/// The columns shown: the network's and the disk's only where some station reads them (columnsOf).
fn rs_columns_of(v : Json?) -> Array[(String, String)] {
  rs_columns.filter(fn(k) { (k.0 != "net" || flag(v, "net")) && (k.0 != "disk" || flag(v, "disk")) })
}

///|
/// What the page shows, by station: the kind of whose (all, or a ResourceKind's key), every process flat or grouped,
/// the column sorted by, the groups open.
priv struct RsShown {
  mut kind : String
  mut flat : Bool
  mut by : String
  open : Map[String, Bool]
  mut opened : Bool
}

///|
// kept across runs: said as a station's 进程 is first shown; station_page_reset empties it
let rs_shown : Map[String, RsShown] = {}

///|
fn rs_shown_of(address : String) -> RsShown {
  match rs_shown.get(address) {
    Some(s) => s
    None => {
      let s = { kind: "all", flat: false, by: "cpu", open: {}, opened: false }
      rs_shown[address] = s
      s
    }
  }
}

///|
/// A use's figure by column key.
fn rs_use(u : Json?, key : String) -> Double {
  number(u, key)
}

///|
/// Its 进程 (Processes): what still.fail uses of the machine; offline, a line saying it cannot be seen.
fn station_processes(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Array[() -> Unit] {
  let address = text(s, "station")
  if !flag(s, "online") {
    return [fn() { c.text(@sf.t("web-pages.stations.processesOffline"), style=st_memory) |> ignore }]
  }
  [
    fn() {
      c.box(style=rs_processes, fn() {
        c.text(@sf.t("web-pages.stations.processesLead"), style=st_memory) |> ignore
        match resources_of(core, here, address) {
          Some(Object(_)) as v => resources_body(c, core, address, v)
          _ => @sf.waiting(c, fn() { c.box(style=rs_page, fn() { rs_sample(c, core) }) |> ignore })
        }
      })
      |> ignore
    },
  ]
}

///|
/// The body (ResourcesBody): nothing read yet, a wait (or that there is nothing to see) and how it is read; else its
/// totals, the choice of whose and of how, the table, how it is read.
fn resources_body(c : @ui.Ctx, core : Core, address : String, v : Json?) -> Unit {
  let shown = rs_shown_of(address)
  c.box(style=rs_page, fn() {
    if flag(v, "empty") {
      let wait = field(v, "wait")
      if flag(wait, "reading") || items(wait, "failing").length() > 0 {
        @sf.waiting(c, fn() { rs_sample(c, core) })
      } else {
        c.text(@sf.t("web-main.resources.none"), style=rs_empty) |> ignore
      }
      rs_foot(c, v, false)
      return
    }
    rs_figures_of(c, core, address, v, shown)
    rs_foot(c, v, true)
  })
  |> ignore
}

///|
/// What is seen of the machine (`v`): its totals, the choice of whose and of how, the table.
fn rs_figures_of(c : @ui.Ctx, core : Core, address : String, v : Json?, shown : RsShown) -> Unit {
  // (four in a row, or two over two where four have not the room: in pairs that go on in lines, never three and one,
  // as the usage page's)
  let tiles = items(v, "tiles")
  c.box(style=rs_tiles, flow=true, fn() {
    for k in 0..<((tiles.length() + 1) / 2) {
      c.box(style=rs_tile_pair, keep=true, fn() {
        for i in (k * 2)..<@cmp.minimum(k * 2 + 2, tiles.length()) {
          rs_tile(c, address, Some(tiles[i]))
        }
      })
      |> ignore
    }
  })
  |> ignore
  // whose and how, on a line, apart at its ends
  c.box(style=rs_bar, flow=true, fn() {
    let kinds = items(v, "kinds")
    let keys = ["all"] + kinds.map(fn(k) { text(Some(k), "key") })
    let labels = [@sf.t("web-main.resources.all")] + kinds.map(fn(k) { text(Some(k), "label") })
    let at = keys.search(shown.kind).unwrap_or(0)
    let picked = @sf.segmented(c, "resources-kind/" + address, labels, at)
    if picked != at {
      shown.kind = keys[picked]
    }
    let how = @sf.segmented(
      c,
      "resources-flat/" + address,
      [@sf.t("web-main.resources.grouped"), @sf.t("web-main.resources.flat")],
      if shown.flat { 1 } else { 0 },
    )
    shown.flat = how == 1
  })
  |> ignore
  let groups = items(v, "groups").filter(fn(g) { shown.kind == "all" || text(Some(g), "kind") == shown.kind })
  let columns = rs_columns_of(v)
  if shown.flat {
    rs_flat(c, core, address, groups, columns, shown)
  } else {
    rs_grouped(c, core, address, groups, columns, shown)
  }
}

///|
/// What is seen of the machine while it is read (the library's Waiting, in its bones): the totals and a table of
/// made-up processes, as rs_figures_of draws them.
fn rs_sample(c : @ui.Ctx, core : Core) -> Unit {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let use = fn(k : Double) -> Json { { "cpu": Json::number(k), "memory": Json::number(k * 2.0) } }
  let group = fn(i : Int, n : Int, k : Double, processes : Array[Int]) -> Json {
    {
      "key": Json::string("sample" + i.to_string()),
      "title": w(n),
      "kindText": w(2),
      "use": use(k),
      "processes": Json::array(
        processes.mapi(fn(j, m) {
          Json::object({
            "key": Json::string("sample" + i.to_string() + "/" + j.to_string()),
            "name": w(m),
            "pid": Json::number((j + 1).to_double()),
            "use": use(k / 2.0),
          })
        }),
      ),
    }
  }
  let v : Json = {
    "tiles": Json::array(["cpu", "memory", "net", "disk"].map(fn(k) { Json::object({ "key": Json::string(k), "label": w(2), "sub": w(4), "value": w(4) }) })),
    "kinds": [{ "key": "a", "label": w(2) }, { "key": "b", "label": w(2) }],
    "groups": [group(0, 8, 30.0, [6, 9, 5]), group(1, 6, 20.0, [7]), group(2, 10, 10.0, [8])],
  }
  rs_figures_of(c, core.quiet(), "sample", Some(v), rs_shown_of("sample"))
}

///|
/// A total, said, with the last minutes' line under it (Tile, Spark).
fn rs_tile(c : @ui.Ctx, address : String, tv : Json?) -> Unit {
  let t = @sf.theme()
  let key = text(tv, "key")
  c.box(style=rs_tile_box, fn() {
    c.box(style=rs_tile_head, fn() {
      c.text(text(tv, "label"), style=rs_tile_label) |> ignore
      c.text(text(tv, "sub"), style=rs_tile_sub) |> ignore
    })
    |> ignore
    c.text(text(tv, "value"), style=rs_tile_value) |> ignore
    // the line as wide as the tile, read back as it is laid out
    let id = c.id("resources-spark/" + address + "/" + key)
    let w = match c.laid_size(id) {
      Some((w, _)) => w
      None => 0.0
    }
    let ink = match key {
      "cpu" => t.p.accent
      "memory" => t.p.blue
      "net" => t.p.green
      "disk" => t.p.warn_ink
      _ => t.p.muted
    }
    c.box(style=rs_spark, id~, fn() {
      if w > 0.0 {
        c.shapes(rs_spark_shapes(number_list(tv, "points"), w, ink), w=Px(w), h=Px(rs_spark_h)) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The figures of `key` of `v`, as numbers.
fn number_list(v : Json?, key : String) -> Array[Double] {
  items(v, key).filter_map(fn(x) {
    match x {
      Number(n, ..) => Some(n)
      _ => None
    }
  })
}

///|
/// The last minutes' line `w` wide (Spark: the most at 2 under its top, the line 1.25 wide, the ground under it the ink
/// at 14%); none for fewer than two points.
fn rs_spark_shapes(points : Array[Double], w : Double, ink : Int64) -> Array[@ui.Shape] {
  if points.length() < 2 {
    return []
  }
  let most = points.fold(init=0.0, fn(m, p) { if p > m { p } else { m } })
  let most = if most > 0.0 { most } else { 1.0 }
  let line : Array[Double] = []
  for i, p in points {
    line.push(i.to_double() / (points.length() - 1).to_double() * w)
    line.push(rs_spark_h - p / most * (rs_spark_h - rs_spark_top))
  }
  let ground = line.copy()
  ground.push(w)
  ground.push(rs_spark_h)
  ground.push(0.0)
  ground.push(rs_spark_h)
  [
    @ui.shape_of([(ground, true)], fill=@sf.alpha(ink, rs_spark_ground)),
    @ui.shape_of([(line, false)], stroke=ink, width=rs_spark_line),
  ]
}

///|
/// How the table is laid out in its width: each figure's column as wide as the widest it says (its head, every row's
/// figure, a group's processes' too, open or not), so its rows line up as a table's and none moves as a group opens;
/// `stacked`, each row's names on a line of their own over its figures, where beside the figures they would have less
/// than rs_name_least each; `share`, the sorted column's share before its figures, left out where the figures' line
/// has not the room for it.
priv struct RsLayout {
  widths : Array[Double]
  stacked : Bool
  share : Bool
}

///|
/// The layout of table `id` (as wide as it is laid out: read back) for `rows` (each row's use, and whether its sorted
/// figure is said bold), with `names` columns of names first.
fn rs_layout(
  c : @ui.Ctx,
  id : Int,
  rows : Array[(Json?, Bool)],
  columns : Array[(String, String)],
  by : String,
  names : Int,
) -> RsLayout {
  let room = match c.laid_size(id) {
    Some((w, _)) => w
    None => c.width
  }
  // (their words as drawn: the system's size of words applied, a figure's digits tabular)
  let head = c.sp(c.text_size(Xs).0)
  let figure = c.sp(c.text_size(Sm).0)
  let widths = columns.map(fn(col) {
    let sorted = col.0 == by
    let name = @sf.t("web-main.resources.column." + col.0)
    let mut widest = @ui.text_advance(if sorted { name + " ↓" } else { name }, size=head, weight=500)
    for r in rows {
      let weight = if sorted && r.1 { 600 } else { 400 }
      widest = dmax(widest, @ui.text_advance(text(r.0, col.1), size=figure, weight~, style=@hostapi.style_tabular))
    }
    widest + 2.0 * c.space(S2)
  })
  let share_w = c.space(S9) + c.space(S2)
  let sorted = columns.search_by(fn(col) { col.0 == by })
  let figures = widths.fold(init=0.0, fn(s, w) { s + w }) + (if sorted is Some(_) { share_w } else { 0.0 })
  let left = room - figures - c.space(S8)
  let beside = left >= c.space(rs_name_least) * names.to_double()
  let share = left >= 0.0
  match sorted {
    Some(k) if share => widths[k] = widths[k] + share_w
    _ => ()
  }
  { widths, stacked: !beside, share }
}

///|
/// Column `k`'s cell: as wide as its column; under its row's names (stacked), the line over it apart enough; `shared`,
/// the share at its start, the figure at its end (the shares one under another, as bars of a chart).
fn rs_column(lay : RsLayout, k : Int, under? : Bool = false, shared? : Bool = false) -> @ui.Style {
  let s = rs_number_cell.then(@ui.style(min_w=Fixed(lay.widths[k])))
  let s = if under { s.then(rs_number_under) } else { s }
  if shared {
    s.then(rs_number_shared)
  } else {
    s
  }
}

///|
/// A row of the table (rs_line) as it is laid out: its names, its figures and its end on one line; stacked, its names
/// on a line of their own and its figures under them, under their heads, its end beside both.
fn rs_table_row(c : @ui.Ctx, lay : RsLayout, style : @ui.Style, id : Int, names : () -> Unit, figures : () -> Unit, end : () -> Unit) -> Int {
  rs_line(c, style, id, fn() {
    if lay.stacked {
      c.box(style=rs_stack, fn() {
        c.box(style=rs_row, names) |> ignore
        c.box(style=rs_figures_line, figures) |> ignore
      })
      |> ignore
    } else {
      names()
      figures()
    }
    end()
  })
}

///|
/// The columns' heads (Heads): the first ones' (none stacked: the names have a line of their own), then each
/// column's, sorting by itself (the most first), the end's room.
fn rs_heads(
  c : @ui.Ctx,
  address : String,
  first : Array[String],
  columns : Array[(String, String)],
  shown : RsShown,
  lay : RsLayout,
) -> Unit {
  rs_line(c, if lay.stacked { rs_head_row_stacked } else { rs_head_row }, 0, fn() {
    if !lay.stacked {
      for i, h in first {
        c.box(style=if i == 0 { rs_name_cell } else { rs_whose_cell }, fn() { c.text(h, style=rs_head) |> ignore })
        |> ignore
      }
    }
    for k, col in columns {
      let id = c.id("resources-by/" + address + "/" + col.0)
      if c.clicked(id) {
        shown.by = col.0
      }
      let on = col.0 == shown.by
      let name = @sf.t("web-main.resources.column." + col.0)
      let words = if on { name + " ↓" } else { name }
      let b = c.box(style=rs_column(lay, k), id~, fn() {
        c.text(words, style=if on || c.hovered(id) { rs_head_on } else { rs_head }) |> ignore
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.resources.by", args=[("column", name)]))
    }
    c.box(style=rs_end_cell, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A row's figures (Figures), each in its column: the sorted column's bold, with how much of the most it is before it
/// where the layout has room for it; `plain`, none so.
fn rs_figures(
  c : @ui.Ctx,
  u : Json?,
  columns : Array[(String, String)],
  by : String,
  most : Double,
  lay : RsLayout,
  plain? : Bool = false,
) -> Unit {
  for k, col in columns {
    let strong = !plain && col.0 == by
    let shared = strong && lay.share
    c.box(style=rs_column(lay, k, under=lay.stacked, shared~), fn() {
      if shared {
        let part = if most > 0.0 { @cmp.minimum(1.0, rs_use(u, by) / most) } else { 0.0 }
        c.box(style=rs_share, fn() {
          if part > 0.0 {
            c.box(style=rs_share_fill.then(@ui.style(w=Grow(part))), fn() {  }) |> ignore
          }
          let rest = 1.0 - part
          if rest > 0.0 {
            c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
          }
        })
        |> ignore
      }
      c.text(text(u, col.1), style=if strong { rs_figure_strong } else { rs_figure }) |> ignore
    })
    |> ignore
  }
}

///|
/// Whose a chat's row is: its chat opened from its title, where it has one.
fn rs_title(c : @ui.Ctx, core : Core, key : String, g : Json?, style : @ui.TextStyle) -> Unit {
  let chat = field(g, "chat")
  let thread = match field(chat, "thread") {
    Some(Number(n, ..)) => n.to_int64().to_string()
    _ => ""
  }
  let session = if thread != "" { thread } else { text(chat, "session") }
  if chat is Some(Object(_)) && session != "" {
    let id = c.id("resources-chat/" + key)
    if c.clicked(id) {
      (core.open_chat)(text(chat, "station"), session, text(g, "title"))
    }
    // (underlined under the pointer: chatLink)
    c.box(style=rs_title_box, id~, fn() {
      c.rich([@ui.span(text(g, "title"), underline=c.hovered(id))], style~) |> ignore
    })
    |> ignore
  } else {
    c.text(text(g, "title"), style~) |> ignore
  }
}

///|
/// Whose uses what (Grouped), the most of the column sorted by first, each opening to its processes (the first open at
/// first).
fn rs_grouped(c : @ui.Ctx, core : Core, address : String, groups : Array[Json], columns : Array[(String, String)], shown : RsShown) -> Unit {
  let by = shown.by
  let sorted = groups.copy()
  sorted.sort_by(fn(a, b) { rs_use(field(Some(b), "use"), by).compare(rs_use(field(Some(a), "use"), by)) })
  if !shown.opened {
    shown.opened = true
    match groups {
      [g, ..] => shown.open[text(Some(g), "key")] = true
      [] => ()
    }
  }
  let most = sorted.fold(init=0.0, fn(m, g) { @cmp.maximum(m, rs_use(field(Some(g), "use"), by)) })
  // (a group's figures bold, its processes' plain)
  let rows : Array[(Json?, Bool)] = []
  for g in groups {
    rows.push((field(Some(g), "use"), true))
    for p in items(Some(g), "processes") {
      rows.push((field(Some(p), "use"), false))
    }
  }
  let table = c.id("resources-table/" + address)
  let lay = rs_layout(c, table, rows, columns, by, 1)
  c.box(style=rs_table, id=table, taps=false, fn() {
    rs_heads(c, address, [@sf.t("web-main.resources.column.name")], columns, shown, lay)
    for g in sorted {
      let gv = Some(g)
      let key = text(gv, "key")
      let on = shown.open.get(key).unwrap_or(false)
      let id = c.id("resources-group/" + address + "/" + key)
      if c.clicked(id) {
        if on {
          shown.open.remove(key)
        } else {
          shown.open[key] = true
        }
      }
      let b = rs_table_row(
        c,
        lay,
        rs_group_row,
        id,
        fn() {
          c.box(style=rs_name_cell, fn() {
            c.box(style=rs_name, fn() {
              @sf.icon(c, if on { "chevron-down" } else { "chevron-right" }, size=rs_toggle, color=@sf.theme().p.subtle)
              |> ignore
              rs_title(c, core, key, gv, rs_name_text)
              let meta = join([text(gv, "kindText"), items(gv, "processes").length().to_string()], " · ")
              c.text(meta, style=rs_meta) |> ignore
            })
            |> ignore
          })
          |> ignore
        },
        fn() { rs_figures(c, field(gv, "use"), columns, by, most, lay) },
        fn() { c.box(style=rs_end_cell, fn() {  }) |> ignore },
      )
      c.semantics(b, Button, id~, expanded=on)
      if on {
        let ps = items(gv, "processes").copy()
        ps.sort_by(fn(a, b) { rs_use(field(Some(b), "use"), by).compare(rs_use(field(Some(a), "use"), by)) })
        for p in ps {
          let pv = Some(p)
          let rid = c.id("resources-row/" + address + "/" + text(pv, "key"))
          rs_table_row(
            c,
            lay,
            rs_row,
            rid,
            fn() {
              c.box(style=rs_process_cell, fn() {
                c.text(text(pv, "name"), style=rs_process_name) |> ignore
                c.text(number(pv, "pid").to_int().to_string(), style=rs_meta) |> ignore
              })
              |> ignore
            },
            fn() { rs_figures(c, field(pv, "use"), columns, by, most, lay, plain=true) },
            fn() { rs_end(c, core, address, pv, gv, rid) },
          )
          |> ignore
        }
      }
    }
  })
  |> ignore
}

///|
/// Every process, with whose it is (Flat), the most of the column sorted by first.
fn rs_flat(c : @ui.Ctx, core : Core, address : String, groups : Array[Json], columns : Array[(String, String)], shown : RsShown) -> Unit {
  let by = shown.by
  let rows : Array[(Json, Json)] = []
  for g in groups {
    for p in items(Some(g), "processes") {
      rows.push((p, g))
    }
  }
  rows.sort_by(fn(a, b) { rs_use(field(Some(b.0), "use"), by).compare(rs_use(field(Some(a.0), "use"), by)) })
  let most = rows.fold(init=0.0, fn(m, r) { @cmp.maximum(m, rs_use(field(Some(r.0), "use"), by)) })
  let table = c.id("resources-table/" + address)
  let lay = rs_layout(c, table, rows.map(fn(r) { (field(Some(r.0), "use"), true) }), columns, by, 2)
  c.box(style=rs_table, id=table, taps=false, fn() {
    rs_heads(c, address, [@sf.t("web-main.resources.column.process"), @sf.t("web-main.resources.column.whose")], columns, shown, lay)
    for r in rows {
      let pv = Some(r.0)
      let gv = Some(r.1)
      let rid = c.id("resources-row/flat/" + address + "/" + text(pv, "key"))
      rs_table_row(
        c,
        lay,
        rs_row,
        rid,
        fn() {
          c.box(style=rs_name_cell, fn() {
            c.box(style=rs_name, fn() {
              c.text(text(pv, "name"), style=rs_cell_words) |> ignore
              c.text(number(pv, "pid").to_int().to_string(), style=rs_meta) |> ignore
            })
            |> ignore
          })
          |> ignore
          c.box(style=rs_whose_cell, fn() { rs_title(c, core, "flat/" + text(pv, "key"), gv, rs_whose) }) |> ignore
        },
        fn() { rs_figures(c, field(pv, "use"), columns, by, most, lay) },
        fn() { rs_end(c, core, address, pv, gv, rid) },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// A row of the table (tr), set apart from the next by its room (no line under it: only a menu's parts are set apart
/// by one); a row's least height at least (@sf.row_least_h: a press's room, its heads and its rows pressed).
fn rs_line(c : @ui.Ctx, style : @ui.Style, id : Int, body : () -> Unit) -> Int {
  c.box(style=style.then(@sf.row_least_h()), id~, body)
}

///|
/// Its row's end (EndCell): a way to end the process where it may be ended (a chat's, not its agent's own), asked first.
fn rs_end(c : @ui.Ctx, core : Core, address : String, pv : Json?, gv : Json?, row : Int) -> Unit {
  c.box(style=rs_end_cell, fn() {
    let key = "resources-end/" + address + "/" + text(pv, "key")
    // seen as its row is pointed at or it is reached by the keys (end: opacity 0 till then), always to a finger: what a
    // pointer over a thing shows (@sf.pointed_or_finger)
    let seen = @sf.pointed_or_finger(c, c.hovered(row) || c.lit(c.id(key)))
    if flag(pv, "endable") && seen {
      let name = text(pv, "name")
      if @sf.icon_button(
          c,
          "stop",
          key~,
          size=rs_end_size,
          label=@sf.t("web-main.resources.endLabel", args=[("name", name)]),
        ) {
        let pid = number(pv, "pid")
        @sf.confirm(
          @sf.t("web-main.resources.endTitle", args=[("name", name), ("pid", pid.to_int().to_string())]),
          @sf.t("web-main.resources.endBody", args=[("chat", text(gv, "title"))]),
          @sf.t("web-main.resources.end"),
          danger=true,
          fn() {
            let session = text(gv, "session")
            if session == "" {
              return
            }
            (core.call)(
              "process.end",
              obj([("station", str(text(gv, "station"))), ("pid", Json::number(pid)), ("session", str(session))]),
              fn(r) {
                match r {
                  Ok(_) => (core.say)(@sf.t("web-main.resources.ended", args=[("name", name)]))
                  Err(e) => (core.say)(@sf.t("web-main.resources.endFailed", args=[("name", name), ("error", error_text(e))]))
                }
              },
            )
          },
        )
      }
    }
  })
  |> ignore
}

///|
/// How often it is read, what is missing, how it is counted (Foot).
fn rs_foot(c : @ui.Ctx, v : Json?, basis : Bool) -> Unit {
  c.box(style=rs_foot_box, fn() {
    let every = number(v, "everyMs")
    if every > 0.0 {
      c.text(@sf.t("web-main.resources.every", args=[("n", (every / 1000.0).round().to_int().to_string())]), style=rs_foot_words)
      |> ignore
    }
    for n in items(v, "notes") {
      match n {
        String(w) => c.text(w, style=rs_foot_words) |> ignore
        _ => ()
      }
    }
    if basis {
      c.text(text(v, "basis"), style=rs_foot_words) |> ignore
    }
  })
  |> ignore
}

///|
/// What still.fail uses of the machine (Uses): a quiet line, the whole of it opening its 进程; the network's figure where
/// the station reads it.
fn station_uses(c : @ui.Ctx, address : String, uv : Json?) -> Unit {
  let t = @sf.theme()
  let u = field(uv, "use")
  let id = c.id("station-uses/" + address)
  if c.clicked(id) {
    @settings.station_parts[address] = "processes"
  }
  let lit = c.hovered(id)
  let b = c.box(style=rs_uses, id~, fn() {
    c.text(@sf.t("web-pages.stations.uses", args=[("name", "still.fail")]), style=if lit { rs_uses_lit } else { rs_uses_words })
    |> ignore
    c.box(style=rs_uses_figures, flow=true, fn() {
      let figure = fn(label : String, value : String) {
        c.rich([@ui.span(label + " "), @ui.span(value, weight=500, color=t.p.text)], style=rs_uses_words) |> ignore
      }
      figure("CPU", text(u, "cpuText"))
      figure(@sf.t("web-main.resources.column.memory"), text(u, "memoryText"))
      if flag(uv, "net") {
        figure(@sf.t("web-main.resources.column.net"), text(u, "netText"))
      }
    })
    |> ignore
    @sf.icon(c, "chevron-right", size=rs_uses_chevron, color=if lit { t.p.text } else { t.p.muted }) |> ignore
  })
  c.semantics(b, Link, id~, label=@sf.t("web-pages.stations.uses", args=[("name", "still.fail")]))
}

// ── styles (Resources.css.ts; StationCards.css.ts uses) ────────────────

///|
/// Its 进程 (processes): the line on what is counted over the page, 16 apart.
// kept across runs: a value (no field of it changes)
let rs_processes : @ui.Style = @ui.css("w=Full gap=S4")

///|
/// The body (page): 14 apart.
// kept across runs: a value (no field of it changes)
let rs_page : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
/// Nothing to see (empty): in the middle, 28 over and under.
// kept across runs: a value (no field of it changes)
let rs_empty : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, center=true, w=Full)

///|
/// The totals (tiles): in pairs on a line, 8 apart along it and between the lines.
// kept across runs: a value (no field of it changes)
let rs_tiles : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// Two of the totals side by side, sharing what their line has.
// kept across runs: a value (no field of it changes)
let rs_tile_pair : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2)

///|
/// A total (tile): 10 down, 12 in, 8 up; 2 apart; the card's corner on the card's ground. 144 at least: its figure
/// whole at its longest (↓ 1023 KB/s), its label beside the start of what is under it.
// kept across runs: a value (no field of it changes)
let rs_tile_box : @ui.Style = @ui.style(w=@sf.grow, min_w=S36, px=S3, pt=S2_5, pb=S2, gap=S0_5, radius=Xl3, bg=Card)

///|
/// Its label and what is under it, at its ends (tileHead).
// kept across runs: a value (no field of it changes)
let rs_tile_head : @ui.Style = @ui.css("row w=Full gap=S2 justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let rs_tile_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// (tileSub: subtle, cut at its end)
// kept across runs: a value (no field of it changes)
let rs_tile_sub : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false, w=Cut)

///|
/// Its figure (tileValue: the title's 16, 600).
// kept across runs: a value (no field of it changes)
let rs_tile_value : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false)

///|
/// The line's room (spark: as wide as the tile, 26 high, 2 under the figure).
// kept across runs: a value (no field of it changes)
let rs_spark : @ui.Style = @ui.css("w=Full pt=S0_5")

///|
let rs_spark_h : Double = 26.0

///|
/// How far under the line's room its most stands (the viewBox's 26 - 24).
let rs_spark_top : Double = 2.0

///|
let rs_spark_line : Double = 1.25

///|
/// The ground under the line: the ink at 14%.
let rs_spark_ground : Double = 0.14

///|
/// The choice of whose and of how, apart at its ends, 8 apart, 4 under the totals (bar).
// kept across runs: a value (no field of it changes)
let rs_bar : @ui.Style = @ui.css("row w=Full pt=S1 gap=S2 justify=JBetween align=ACenter")

///|
/// The table: its rows, each a line under it.
// kept across runs: a value (no field of it changes)
let rs_table : @ui.Style = @ui.css("w=Full")

///|
/// A row (cell's 6 by 8, a line under it).
// kept across runs: a value (no field of it changes)
let rs_row : @ui.Style = @ui.css("row w=Full align=ACenter")


///|
/// The heads' row; stacked, only the figures' heads and the end's room, at the row's end over them.
// kept across runs: a value (no field of it changes)
let rs_head_row : @ui.Style = rs_row

///|
// kept across runs: a value (no field of it changes)
let rs_head_row_stacked : @ui.Style = rs_row.then(@ui.css("justify=JEnd"))

///|
/// A stacked row's names and figures: what its row leaves beside its end, its two lines under each other.
// kept across runs: a value (no field of it changes)
let rs_stack : @ui.Style = @ui.style(w=@sf.grow, min_w=S0)

///|
/// A stacked row's figures, at its end under their heads.
// kept across runs: a value (no field of it changes)
let rs_figures_line : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
/// Beside the figures, the least each column of names keeps (a chat's title its first words, what it is and how many
/// processes after it); with less the row is stacked.
// kept across runs: a value (no field of it changes)
let rs_name_least : @ui.Space = S40

///|
/// A group's row: the page's hover under the pointer.
// kept across runs: a value (no field of it changes)
let rs_group_row : @ui.Style = rs_row.then(@ui.css("hovered{bg=Hover}"))

///|
/// The first column: what is left of the row's width, 6 by 8 in.
// kept across runs: a value (no field of it changes)
let rs_name_cell : @ui.Style = @ui.style(w=@sf.grow, min_w=S0, px=S2, py=S1_5)

///|
/// A process under its group: its name under its group's (processName: past the chevron and its gap).
// kept across runs: a value (no field of it changes)
let rs_process_cell : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S0, pl=S7, pr=S2, py=S1_5, gap=S1_5, align=ACenter)

///|
/// Whose a process is (whose: about 200 at most).
// kept across runs: a value (no field of it changes)
let rs_whose_cell : @ui.Style = @ui.css("w=Cut max_w=S48 px=S2 py=S1_5")

///|
/// A figure's column: at its end.
// kept across runs: a value (no field of it changes)
let rs_number_cell : @ui.Style = @ui.css("row px=S2 py=S1_5 gap=S2 align=ACenter justify=JEnd")

///|
/// Under a stacked row's names: nothing over it but their line's own 6 under them.
// kept across runs: a value (no field of it changes)
let rs_number_under : @ui.Style = @ui.css("pt=S0")

///|
/// The sorted column's cell with its share: the share at its start, the figure at its end.
// kept across runs: a value (no field of it changes)
let rs_number_shared : @ui.Style = @ui.css("justify=JBetween")

///|
/// The row's end (endCell: 32, 2 by 4 in).
// kept across runs: a value (no field of it changes)
let rs_end_cell : @ui.Style = @ui.css("row w=S8 px=S1 py=S0_5 justify=JEnd")

///|
let rs_end_size : Double = 24.0

///|
/// A name with what it is after it, 6 apart (name).
// kept across runs: a value (no field of it changes)
let rs_name : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
let rs_toggle : Double = 14.0

///|
/// A chat's title, opening it: cut short where its row has less room (its words with an ellipsis).
// kept across runs: a value (no field of it changes)
let rs_title_box : @ui.Style = @ui.css("w=Cut")


///|
/// A head (head: the meta's 12, 500, muted).
// kept across runs: a value (no field of it changes)
let rs_head : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
/// The column sorted by, and one under the pointer (sorted).
// kept across runs: a value (no field of it changes)
let rs_head_on : @ui.TextStyle = rs_head.then(@ui.text_style(color=Fg))

///|
/// A group's name (nameText: 500, cut at its end).
// kept across runs: a value (no field of it changes)
let rs_name_text : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let rs_cell_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// A process under its group (process: muted).
// kept across runs: a value (no field of it changes)
let rs_process_name : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// Whose (whose: muted, cut at its end).
// kept across runs: a value (no field of it changes)
let rs_whose : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// What it is, its pid (meta: subtle, the meta's 12).
// kept across runs: a value (no field of it changes)
let rs_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// A figure (number: tabular, on one line).
// kept across runs: a value (no field of it changes)
let rs_figure : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, tabular=true)

///|
// kept across runs: a value (no field of it changes)
let rs_figure_strong : @ui.TextStyle = rs_figure.then(@ui.text_style(weight=Semibold))

///|
/// How much of the most (share: 36 by 4, round, the line's grey; its fill the accent).
// kept across runs: a value (no field of it changes)
let rs_share : @ui.Style = @ui.css("row w=S9 h=S1 radius=Full bg=Line clip")

///|
// kept across runs: a value (no field of it changes)
let rs_share_fill : @ui.Style = @ui.css("h=Full bg=Accent")

///|
/// How it is read (foot): 4 apart, the meta's 12, subtle.
// kept across runs: a value (no field of it changes)
let rs_foot_box : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let rs_foot_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, w=Full)

///|
/// The line (uses: 14 apart, muted, the text's under the pointer).
// kept across runs: a value (no field of it changes)
let rs_uses : @ui.Style = @ui.css("row w=Full gap=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let rs_uses_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, tabular=true)

///|
// kept across runs: a value (no field of it changes)
let rs_uses_lit : @ui.TextStyle = rs_uses_words.then(@ui.text_style(color=Fg))

///|
/// Its figures: what is left of the line, 14 apart, wrapping (usesFigures).
// kept across runs: a value (no field of it changes)
let rs_uses_figures : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S0, gap=S3_5)

///|
let rs_uses_chevron : Double = 14.0
