// What still.fail uses of a station's machine, as Activity Monitor says it (ember web/src/Resources.tsx ResourcesBody,
// Resources.css.ts; the core's `resources` view, client/core-ts/src/views/resources.ts): a station's page's 进程, and
// the line its overview says it in (StationCards.tsx Uses). Its totals with the last minutes' line under each, whose
// uses what (a chat, the agents, the desktop app, the station) grouped or every process flat, sorted by a column, a
// chat's process ended from its row (asked first).

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
          _ => @sf.waiting(c, shape=Cards)
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
        @sf.waiting(c, shape=Cards, count=2)
      } else {
        c.text(@sf.t("web-main.resources.none"), style=rs_empty) |> ignore
      }
      rs_foot(c, v, false)
      return
    }
    c.box(style=rs_tiles, fn() {
      for tile in items(v, "tiles") {
        rs_tile(c, address, Some(tile))
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
    rs_foot(c, v, true)
  })
  |> ignore
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
/// The columns' heads (Heads): the first ones', then each column's, sorting by itself (the most first), the end's room.
fn rs_heads(c : @ui.Ctx, address : String, first : Array[String], columns : Array[(String, String)], shown : RsShown) -> Unit {
  rs_line(c, rs_head_row, 0, fn() {
    for i, h in first {
      c.box(style=if i == 0 { rs_name_cell } else { rs_whose_cell }, fn() { c.text(h, style=rs_head) |> ignore })
      |> ignore
    }
    for col in columns {
      let id = c.id("resources-by/" + address + "/" + col.0)
      c.cursor(id, Hand)
      if c.clicked(id) {
        shown.by = col.0
      }
      let on = col.0 == shown.by
      let name = @sf.t("web-main.resources.column." + col.0)
      let words = if on { name + " ↓" } else { name }
      let b = c.box(style=rs_number_cell, id~, fn() {
        c.text(words, style=if on || c.hovered(id) { rs_head_on } else { rs_head }) |> ignore
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.resources.by", args=[("column", name)]))
    }
    c.box(style=rs_end_cell, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A row's figures (Figures): the sorted column's bold, with how much of the most it is before it; `plain`, none so.
fn rs_figures(c : @ui.Ctx, u : Json?, columns : Array[(String, String)], by : String, most : Double, plain? : Bool = false) -> Unit {
  for col in columns {
    let strong = !plain && col.0 == by
    c.box(style=rs_number_cell, fn() {
      if strong {
        let k = if most > 0.0 { @cmp.minimum(1.0, rs_use(u, by) / most) } else { 0.0 }
        c.box(style=rs_share, fn() {
          if k > 0.0 {
            c.box(style=rs_share_fill.then(@ui.style(w=Grow(k))), fn() {  }) |> ignore
          }
          let rest = 1.0 - k
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
    c.cursor(id, Hand)
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
  c.box(style=rs_table, fn() {
    rs_heads(c, address, [@sf.t("web-main.resources.column.name")], columns, shown)
    for g in sorted {
      let gv = Some(g)
      let key = text(gv, "key")
      let on = shown.open.get(key).unwrap_or(false)
      let id = c.id("resources-group/" + address + "/" + key)
      c.cursor(id, Hand)
      if c.clicked(id) {
        if on {
          shown.open.remove(key)
        } else {
          shown.open[key] = true
        }
      }
      let b = rs_line(c, rs_group_row, id, fn() {
        c.box(style=rs_name_cell, fn() {
          c.box(style=rs_name, fn() {
            @sf.icon(c, if on { "chevron-down" } else { "chevron-right" }, size=rs_toggle, color=@sf.theme().p.subtle) |> ignore
            rs_title(c, core, key, gv, rs_name_text)
            let meta = join([text(gv, "kindText"), items(gv, "processes").length().to_string()], " · ")
            c.text(meta, style=rs_meta) |> ignore
          })
          |> ignore
        })
        |> ignore
        rs_figures(c, field(gv, "use"), columns, by, most)
        c.box(style=rs_end_cell, fn() {  }) |> ignore
      })
      c.semantics(b, Button, id~, expanded=on)
      if on {
        let ps = items(gv, "processes").copy()
        ps.sort_by(fn(a, b) { rs_use(field(Some(b), "use"), by).compare(rs_use(field(Some(a), "use"), by)) })
        for p in ps {
          let pv = Some(p)
          let rid = c.id("resources-row/" + address + "/" + text(pv, "key"))
          rs_line(c, rs_row, rid, fn() {
            c.box(style=rs_process_cell, fn() {
              c.text(text(pv, "name"), style=rs_process_name) |> ignore
              c.text(number(pv, "pid").to_int().to_string(), style=rs_meta) |> ignore
            })
            |> ignore
            rs_figures(c, field(pv, "use"), columns, by, most, plain=true)
            rs_end(c, core, address, pv, gv, rid)
          })
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
  c.box(style=rs_table, fn() {
    rs_heads(c, address, [@sf.t("web-main.resources.column.process"), @sf.t("web-main.resources.column.whose")], columns, shown)
    for r in rows {
      let pv = Some(r.0)
      let gv = Some(r.1)
      let rid = c.id("resources-row/flat/" + address + "/" + text(pv, "key"))
      rs_line(c, rs_row, rid, fn() {
        c.box(style=rs_name_cell, fn() {
          c.box(style=rs_name, fn() {
            c.text(text(pv, "name"), style=rs_cell_words) |> ignore
            c.text(number(pv, "pid").to_int().to_string(), style=rs_meta) |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(style=rs_whose_cell, fn() { rs_title(c, core, "flat/" + text(pv, "key"), gv, rs_whose) }) |> ignore
        rs_figures(c, field(pv, "use"), columns, by, most)
        rs_end(c, core, address, pv, gv, rid)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A row of the table (tr), the line under it (cell's border-bottom).
fn rs_line(c : @ui.Ctx, style : @ui.Style, id : Int, body : () -> Unit) -> Int {
  let b = c.box(style~, id~, body)
  c.box(style=rs_rule, fn() {  }) |> ignore
  b
}

///|
/// Its row's end (EndCell): a way to end the process where it may be ended (a chat's, not its agent's own), asked first.
fn rs_end(c : @ui.Ctx, core : Core, address : String, pv : Json?, gv : Json?, row : Int) -> Unit {
  c.box(style=rs_end_cell, fn() {
    let key = "resources-end/" + address + "/" + text(pv, "key")
    // seen as its row is pointed at or it is reached by the keys (end: opacity 0 till then); on a touch screen, always
    let seen = @sf.touch_system() || c.hovered(row) || c.lit(c.id(key))
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
  c.cursor(id, Hand)
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
let rs_empty : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, center=true, w=Full)

///|
/// The totals (tiles): equal columns, 8 apart.
// kept across runs: a value (no field of it changes)
let rs_tiles : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A total (tile): 10 down, 12 in, 8 up; 2 apart; the card's corner on the card's ground.
// kept across runs: a value (no field of it changes)
let rs_tile_box : @ui.Style = @ui.style(w=@sf.grow, min_w=S0, px=S3, pt=S2_5, pb=S2, gap=S0_5, radius=Xl3, bg=Card)

///|
/// Its label and what is under it, at its ends (tileHead).
// kept across runs: a value (no field of it changes)
let rs_tile_head : @ui.Style = @ui.css("row w=Full gap=S2 justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let rs_tile_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// (tileSub: subtle, cut at its end)
// kept across runs: a value (no field of it changes)
let rs_tile_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false, w=Cut)

///|
/// Its figure (tileValue: the title's 16, 600).
// kept across runs: a value (no field of it changes)
let rs_tile_value : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, wrap=false)

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
/// The line under a row.
// kept across runs: a value (no field of it changes)
let rs_rule : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
/// The heads' row.
// kept across runs: a value (no field of it changes)
let rs_head_row : @ui.Style = rs_row

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
let rs_head : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Muted, wrap=false)

///|
/// The column sorted by, and one under the pointer (sorted).
// kept across runs: a value (no field of it changes)
let rs_head_on : @ui.TextStyle = rs_head.then(@ui.text_style(color=Fg))

///|
/// A group's name (nameText: 500, cut at its end).
// kept across runs: a value (no field of it changes)
let rs_name_text : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let rs_cell_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=Cut)

///|
/// A process under its group (process: muted).
// kept across runs: a value (no field of it changes)
let rs_process_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Cut)

///|
/// Whose (whose: muted, cut at its end).
// kept across runs: a value (no field of it changes)
let rs_whose : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Cut)

///|
/// What it is, its pid (meta: subtle, the meta's 12).
// kept across runs: a value (no field of it changes)
let rs_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
/// A figure (number: tabular, on one line).
// kept across runs: a value (no field of it changes)
let rs_figure : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, tabular=true)

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
let rs_foot_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, w=Full)

///|
/// The line (uses: 14 apart, muted, the text's under the pointer).
// kept across runs: a value (no field of it changes)
let rs_uses : @ui.Style = @ui.css("row w=Full gap=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let rs_uses_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, tabular=true)

///|
// kept across runs: a value (no field of it changes)
let rs_uses_lit : @ui.TextStyle = rs_uses_words.then(@ui.text_style(color=Fg))

///|
/// Its figures: what is left of the line, 14 apart, wrapping (usesFigures).
// kept across runs: a value (no field of it changes)
let rs_uses_figures : @ui.Style = @ui.style(row=true, w=@sf.grow, min_w=S0, gap=S3_5)

///|
let rs_uses_chevron : Double = 14.0
