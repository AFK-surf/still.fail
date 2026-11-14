// 用量 made once (usage_page's, narrow: a small screen's) as nodes of the window's tree: its title with the days and
// 分享卡片 at its line's end, then what was spent as the core's `usage` view says it, as the old page lays it out.

///|
/// Words of `style` at a line's start growing to what the line leaves them (a style's w=grow: from nothing, cut short
/// where the line has not the room).
fn ug_grow_words(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> @view.View {
  @sf.words_node(parent, words, fn() { style })
  .grow(Is(1.0))
  .basis(Is(Some(0.0)))
  .shrink(Is(1.0))
  .min_width(Is(Some(0.0)))
  .allow_ellipsis(Is(true))
  // (where even their ellipsis has not the room, that drawn past them, as an old view's words filling their share are)
  .ellipsis_past(Is(true))
}

///|
/// A card of the page's (ug_card: its words 20 in and 20 apart, round as a card (Xl3), on the card's ground; `rows`:
/// its last row's ground as far from its foot as from its sides, ug_card_rows), `body` on it.
fn ug_card_node(parent : @view.View, body : (@view.View) -> Unit, rows? : Bool = false) -> Unit {
  parent.box(fn(k) {
    k
    .padding(Is((@sf.card_pad, @sf.card_pad, @sf.card_pad, if rows { @sf.corner_inset } else { @sf.card_pad })))
    .gap(Is(ug_card_gap))
    .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
    .ground(By(fn() { @ui.tree_theme().color(Card) }))
    |> ignore
    body(k)
  })
  |> ignore
}

///|
/// ug_card's gap (S5), ug_body's (S4).
let ug_card_gap : Double = 20.0

///|
let ug_body_gap : Double = 16.0

///|
/// How it is counted (usage_notes'): the core's notes, then its basis, 4 apart, the meta's subtle.
fn usage_notes_node(parent : @view.View, v : () -> Json?) -> Unit {
  parent.box(fn(n) {
    n.gap(Is(4.0)) |> ignore
    n.each(
      fn() {
        let lines = strings(v(), "notes")
        lines.push(text(v(), "basis"))
        lines.filter(fn(l) { l != "" }).mapi(fn(i, l) { (i, l) })
      },
      fn(l) { l.0 },
      fn(row, l) { @sf.words_node(row, fn() { l.get().1 }, fn() { ug_note }) |> ignore },
    )
  })
  |> ignore
}

///|
/// Nothing spent (usage_body's none: its card, the words in its middle 28 over and under).
fn usage_none_node(parent : @view.View) -> Unit {
  ug_card_node(parent, fn(k) {
    k.box(fn(b) {
      b.padding(Is((0.0, 28.0, 0.0, 28.0))).lines_up(Is(Some(Middle))) |> ignore
      @sf.words_node(b, fn() { @sf.t("web-main.usage.none") }, fn() { ug_empty }) |> ignore
    })
    |> ignore
  })
}

///|
/// A row's corner on a card (InnerOr(Xl2)): concentric with the card's, @sf.corner_inset in, where the theme's ranges
/// let it be; else its own (Xl2).
fn ug_row_corner() -> Double {
  let t = @ui.tree_theme()
  @ui.CornerOf::Follow(@ui.CornerOf::Own(t.corner(Xl3)), @sf.corner_inset, t.corner(Xl2)).radius(@ui.tree_corner_roots_now())
}

///|
/// Four-dimensional spending breakdown card (`对话 | 人 | 模型 | 账号`): replaces the old chats-only card so people,
/// models, and accounts have full ranked lists with cost, subtitle, share, and progress bar; deleted chats are
/// aggregated into a single summary row at the bottom.
fn usage_ranks_node(parent : @view.View, core : Core, v : () -> Json?) -> Unit {
  let rank_keys = ["chats", "people", "models", "profiles"]
  let rank_labels = fn() { ["对话", "人", "模型", "账号"] }
  let all_items = fn() {
    let rk = usage_pick.rank.get()
    let raw = match items(v(), "lists").search_by(fn(l) { text(Some(l), "key") == rk }) {
      Some(i) => items(Some(items(v(), "lists")[i]), "items")
      None => []
    }
    if rk != "chats" {
      raw
    } else {
      let active : Array[Json] = []
      let mut del_count = 0
      let mut del_share = 0.0
      for it in raw {
        let title = text(Some(it), "title")
        let key = text(Some(it), "key")
        if title == "已删除的对话" && field(Some(it), "chat") is None && key != "deleted/all" {
          del_count = del_count + 1
          del_share = del_share + number(Some(it), "share")
        } else {
          active.push(it)
        }
      }
      if del_count > 0 {
        let pct = (del_share * 100.0).to_int().to_string() + "%"
        active.push({
          "key": Json::string("deleted/agg"),
          "title": Json::string("已删除的对话（\{del_count} 个）"),
          "sub": Json::string("历史已清理的对话汇总"),
          "costText": Json::string(""),
          "share": Json::number(del_share),
          "shareText": Json::string(pct),
        })
      }
      active
    }
  }
  parent.show(fn() { items(v(), "lists").length() > 0 }, fn(at) {
    ug_card_node(at, rows=true, fn(k) {
      k.box(fn(head) {
        head.gap(Is(12.0)) |> ignore
        @sf.words_node(head, fn() { "花费明细" }, fn() { ug_card_title }) |> ignore
        head.box(fn(bar) {
          bar.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
          @sf.segmented_node(
            bar,
            rank_labels,
            fn() { rank_keys.search(usage_pick.rank.get()).unwrap_or(0) },
            fn(i) {
              match rank_keys.get(i) {
                Some(rk) => {
                  usage_pick.rank.set(rk)
                  usage_pick.all.set(false)
                }
                None => ()
              }
            },
          )
        })
        |> ignore
      })
      |> ignore
      // (out across its room to @sf.corner_inset from its edges, their words in line with its title: ug_rows)
      // (a breakdown in another's place, as a tab's: one pick by the breakdown, its rows going as one with it, never
      // each row of one going as the other's come, which a press saw change twice: switches_still's settings-usage)
      k.pick(fn() { usage_pick.rank.get() }, fn(ranked, rk) {
        ranked.box(fn(rows) {
        let out = @sf.corner_inset - @sf.card_pad
        rows.margin(Is((out, 0.0, out, 0.0))) |> ignore
        rows.each(
          fn() {
            let all = all_items()
            if usage_pick.all.get() { all } else { all.iter().take(ug_first).collect() }
          },
          fn(it) { rk + "/" + text(Some(it), "key") },
          fn(row, it) { usage_rank_row_node(row, core, fn() { rk }, fn() { Some(it.get()) }) },
        )
        rows.show(fn() { all_items().length() > ug_first }, fn(m) {
          m.box(fn(b) {
            let words = fn() {
              if usage_pick.all.get() {
                @sf.t("web-main.fold")
              } else {
                @sf.t("web-main.usage.showAll", args=[("n", all_items().length().to_string())])
              }
            }
            b
            .padding(Is((@sf.card_pad - @sf.corner_inset, 8.0, @sf.card_pad - @sf.corner_inset, 8.0)))
            .radius(By(ug_row_corner))
            .ground(By(fn() { if b.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
            .says(By(fn() { Some(@view.said(Button, label=words())) }))
            |> ignore
            @sf.presses_node(b, fn() { usage_pick.all.set(!usage_pick.all.untracked()) })
            @sf.words_node(b, words, fn() { if @sf.lit_node(b) { ug_more_lit } else { ug_more_words } }) |> ignore
          })
          |> ignore
        })
        })
        |> ignore
      })
    })
  })
}

///|
/// A row in the spending breakdown card: first line has title on the left and cost on the right; second line has
/// subtitle on the left and percentage share on the right; third line is the share bar.
fn usage_rank_row_node(parent : @view.View, core : Core, rank_key : () -> String, it : () -> Json?) -> Unit {
  let chat = fn() { field(it(), "chat") }
  let item_key = fn() { text(it(), "key") }
  let is_deleted = fn() { item_key().has_prefix("deleted/") }
  let opens_chat = fn() { rank_key() == "chats" && !is_deleted() && (chat() is Some(Object(_)) || item_key().contains("/")) }
  let filters_only = fn() { rank_key() != "chats" && item_key() != "" }
  let interactive = fn() { opens_chat() || filters_only() }
  parent.box(fn(r) {
    r
    .padding(Is((@sf.card_pad - @sf.corner_inset, 8.0, @sf.card_pad - @sf.corner_inset, 8.0)))
    .gap(Is(6.0))
    .radius(By(ug_row_corner))
    .ground(By(fn() { if interactive() && r.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    |> ignore
    @sf.presses_node(r, on=interactive, fn() {
      @signals.untracked(fn() {
        if opens_chat() {
          (core.open_chat)(text(chat(), "station"), text(chat(), "session"), text(it(), "title"))
        } else if filters_only() {
          let rk = rank_key()
          let ik = item_key()
          let cur = usage_pick.only.get()
          usage_pick.only.set(if cur == (rk, ik) { ("", "") } else { (rk, ik) })
        }
      })
    })
    r.says(By(fn() {
      if opens_chat() {
        Some(@view.said(Link, label=text(it(), "title")))
      } else if filters_only() {
        Some(@view.said(Button, label=text(it(), "title")))
      } else {
        None
      }
    })) |> ignore
    let lit = fn() { interactive() && (@sf.lit_node(r) || (filters_only() && usage_pick.only.get() == (rank_key(), item_key()))) }
    ug_line_node(r, fn(l) {
      ug_grow_words(l, fn() { text(it(), "title") }, ug_row_title).words_look(By(fn() {
        @ui.style_words(if lit() { ug_row_title_lit } else if is_deleted() { ug_row_sub } else { ug_row_title })
      })).ink(By(fn() { @ui.style_ink(if lit() { ug_row_title_lit } else if is_deleted() { ug_row_sub } else { ug_row_title }) }))
      |> ignore
      @sf.words_node(l, fn() { text(it(), "costText") }, fn() { ug_cost }) |> ignore
    })
    let row_sub = fn() -> String {
      let base = text(it(), "sub")
      let tm = text(it(), "topModel")
      let tok = text(it(), "tokensText")
      let parts : Array[String] = []
      if base != "" {
        parts.push(base)
      }
      if tm != "" && !base.contains(tm) {
        parts.push(tm)
      }
      if tok != "" && !base.contains("token") {
        parts.push(if tok.contains("token") { tok } else { tok + " token" })
      }
      parts.join(" · ")
    }
    ug_line_node(r, fn(l) {
      ug_grow_words(l, row_sub, ug_row_sub) |> ignore
      @sf.words_node(l, fn() { text(it(), "shareText") }, fn() { ug_line_end }) |> ignore
    })
    usage_track_node(r, fn() { number(it(), "share") })
  })
  |> ignore
}

///|
/// A line of a row (ug_line): what it holds side by side across it, 12 apart, across their middle.
fn ug_line_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(l) {
    l.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
    make(l)
  })
  |> ignore
}

///|
/// A share's bar (usage_track's): 4 high, round, on the tint; the share in the accent (1% at least for one spent at all).
fn usage_track_node(parent : @view.View, share : () -> Double) -> Unit {
  let k = fn() {
    let s = share()
    if s <= 0.0 { 0.0 } else { @cmp.minimum(1.0, @cmp.maximum(0.01, s)) }
  }
  parent.box(fn(t) {
    t
    .row(Is(true))
    .height(Is(Some(4.0)))
    .radius(Is(1.0e6))
    .ground(By(fn() { @ui.tree_theme().color(TintStrong) }))
    .clips(Is(true))
    |> ignore
    t.show(fn() { k() > 0.0 }, fn(p) {
      p
      .grow(By(k))
      .basis(Is(Some(0.0)))
      .radius(Is(1.0e6))
      .ground(By(fn() { @ui.tree_theme().color(Accent) }))
      |> ignore
    })
    t.show(fn() { k() < 1.0 }, fn(p) { p.grow(By(fn() { 1.0 - k() })).basis(Is(Some(0.0))) |> ignore })
  })
  |> ignore
}

///|
/// What was spent in all (usage_overview's), on a card: its head (what its figure is, active filter chips inline, and
/// the way to the prices at its end), the cost large and its change against the days before on the left with compact
/// secondary metrics (input tokens + cache hit rate, output tokens, calls) on the right; once something was spent,
/// the days' parts named with their costs and what they are split by, and the days' bars with Y-axis scale.
fn usage_overview_node(parent : @view.View, core : Core, v : () -> Json?, chart : () -> Json?, press : UsagePress, tips? : @sf.TipLayer) -> Unit {
  let shown_v = fn() { if v() is Some(_) { v() } else { chart() } }
  let cost = fn() {
    match items(v(), "tiles").get(0) {
      Some(t) => Some(t)
      None => None
    }
  }
  parent.show(fn() { items(chart(), "tiles").length() > 0 }, fn(at) {
    ug_card_node(at, fn(k) {
      k.box(fn(h) {
        h.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))).wraps(Is(Some(8.0))) |> ignore
        ug_grow_words(h, fn() {
          let shown = shown_v()
          let period = text(shown, "period")
          let label = match items(shown, "tiles").get(0) { Some(t) => text(Some(t), "label"); None => "" }
          if period == "" { label } else { label + " · " + period }
        }, ug_hero_label) |> ignore
        usage_prices_link_node(h, core)
      })
      |> ignore
      k.box(fn(f) {
        f.row(Is(true)).gap(Is(20.0)).lines_up(Is(Some(End))).wraps(Is(Some(12.0))) |> ignore
        f.box(fn(left) {
          left.row(Is(true)).grow(Is(1.0)).basis(Is(Some(160.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(12.0)).lines_up(Is(Some(End))).wraps(Is(Some(8.0))) |> ignore
          @sf.words_node(left, fn() { if v() is None { "…" } else { text(cost(), "value") } }, fn() { ug_hero_value }) |> ignore
          left.show(fn() { text(cost(), "change") != "" }, fn(c) {
            c.row(Is(true)).gap(Is(4.0)).padding(Is((0.0, 0.0, 0.0, 6.0))).lines_up(Is(Some(Middle))) |> ignore
            @sf.words_node(c, fn() { text(cost(), "change") }, fn() { ug_change }) |> ignore
            @sf.words_node(c, fn() { text(v(), "versus") }, fn() { ug_change_versus }) |> ignore
          })
        })
        |> ignore
        f.show(fn() { items(shown_v(), "tiles").length() >= 4 }, fn(right) {
          right.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(16.0)).padding(Is((0.0, 0.0, 0.0, 2.0))).lines_up(Is(Some(Start))).wraps(Is(Some(10.0))) |> ignore
          for idx in [2, 3, 1] {
            right.box(fn(m) {
              let tile = fn() { items(shown_v(), "tiles").get(idx) }
              m.shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
              @sf.words_node(m, fn() { text(tile(), "value") }, fn() { ug_tile_value })
              |> ignore
              @sf.words_node(m, fn() {
                let lbl = text(tile(), "label")
                let sub = text(tile(), "sub")
                if sub != "" { lbl + " (" + sub + ")" } else { lbl }
              }, fn() { ug_tile_label })
              .shrink(Is(1.0))
              .min_width(Is(Some(0.0)))
              .allow_ellipsis(Is(true))
              |> ignore
            })
            |> ignore
          }
        })
      })
      |> ignore
      k.show(fn() { !flag(chart(), "empty") && items(chart(), "daily").length() > 0 }, fn(s) {
        // (each the card's own, as far apart as what is on it)
        s.gap(Is(ug_card_gap)) |> ignore
        usage_split_node(s, chart, press)
        usage_chart_node(s, chart, v)
      })
      usage_narrowed_node(k, v, chart, tips?)
    })
  })
}

///|
/// 查看价目表 → (usage_prices_link's): muted, the words' ink under the hand; pressed, the prices the cost is counted at.
fn usage_prices_link_node(parent : @view.View, core : Core) -> Unit {
  parent.box(fn(b) {
    b
    .shrink(Is(1.0))
    .padding(Is((8.0, 4.0, 8.0, 4.0)))
    .says(By(fn() { Some(@view.said(Link, label=@sf.t("web-main.usage.costPrices"))) }))
    |> ignore
    @sf.presses_node(b, fn() { (core.push)(UsagePrices(usage_pick.days.untracked())) })
    @sf.words_node(b, fn() { @sf.t("web-main.usage.seePrices") }, fn() { if @sf.lit_node(b) { ug_prices_lit } else { ug_prices_words } })
    |> ignore
  })
  |> ignore
}

///|
/// The days' bars' parts named (with each part's cost) and what they are split by (`按人 | 按模型 | 按账号`).
fn usage_split_node(parent : @view.View, v : () -> Json?, press : UsagePress) -> Unit {
  let lists = fn() { items(v(), "lists") }
  let choices = fn() {
    ["people", "models", "profiles"].filter(fn(k) {
      lists().iter().any(fn(l) { text(Some(l), "key") == k && items(Some(l), "parts").length() > 0 })
    })
  }
  let split_labels = fn() {
    choices().map(fn(k) {
      match lists().search_by(fn(l) { text(Some(l), "key") == k }) {
        Some(i) => text(Some(lists()[i]), "title")
        None => k
      }
    })
  }
  let series_cost = fn(pv : Json?) -> String {
    let direct = text(pv, "costText")
    if direct != "" {
      return direct
    }
    let split = text(v(), "split")
    let key = text(pv, "key")
    if key == "" {
      return ""
    }
    match lists().search_by(fn(l) { text(Some(l), "key") == split }) {
      Some(i) => {
        let its = items(Some(lists()[i]), "items")
        match its.search_by(fn(it) { text(Some(it), "key") == key }) {
          Some(j) => text(Some(its[j]), "costText")
          None => ""
        }
      }
      None => ""
    }
  }
  parent.box(fn(line) {
    line.row(Is(true)).gap(Is(12.0)).wraps(Is(Some(10.0))).lines_up(Is(Some(Middle))) |> ignore
    line.box(fn(legend) {
      legend.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).row(Is(true)).gap(Is(14.0)).wraps(Is(Some(8.0))).lines_up(Is(Some(Middle))) |> ignore
      legend.each(
        fn() { items(v(), "series").mapi(fn(i, s) { (i, s) }) },
        fn(p) { p.0 },
        fn(it, p) {
          let pv = fn() { Some(p.get().1) }
          let key = fn() { text(pv(), "key") }
          let split = fn() { text(v(), "split") }
          let selected = fn() { key() != "" && usage_pick.only.get() == (split(), key()) }
          let can_pick = fn() { key() != "" }
          {
            it
            .row(Is(true))
            .gap(Is(6.0))
            .padding(Is((0.0, 4.0, 0.0, 4.0)))
            .lines_up(Is(Some(Middle)))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            .says(By(fn() {
              if can_pick() {
                let word = if selected() { "web-main.usage.onlyOff" } else { "web-main.usage.only" }
                Some(@view.said(Button, label=@sf.t(word, args=[("name", text(pv(), "name"))])))
              } else {
                None
              }
            }))
            |> ignore
            @sf.presses_node(it, on=can_pick, fn() {
              @signals.untracked(fn() {
                if can_pick() {
                  usage_pick.only.set(if selected() { ("", "") } else { (split(), key()) })
                  usage_pick.all.set(false)
                }
              })
            })
            it.box(fn(d) {
              d
              .width(Is(Some(8.0)))
              .height(Is(Some(8.0)))
              .radius(Is(1.0e6))
              .ground(By(fn() {
                if usage_chart_only(v()) != "" && !selected() { @ui.tree_theme().color(TintStrong) } else { usage_series_ink(items(v(), "series"), p.get().0) }
              }))
              |> ignore
            })
            |> ignore
            @sf.words_node(it, fn() { text(pv(), "name") }, fn() {
              if selected() || (can_pick() && @sf.lit_node(it)) { ug_legend_lit } else { ug_legend_words }
            })
            |> ignore
            it.show(fn() { series_cost(pv()) != "" }, fn(c) {
              @sf.words_node(c, fn() { series_cost(pv()) }, fn() { ug_legend_cost }) |> ignore
            })
          }
        },
      )
    })
    |> ignore
    line.show(fn() { choices().length() > 1 }, fn(s) {
      @sf.segmented_node(
        s,
        split_labels,
        fn() {
          let shown = match press.pressed.get() {
            Some((_, k)) if k != "" => k
            _ => text(v(), "split")
          }
          choices().search(shown).unwrap_or(0)
        },
        fn(i) {
          match @signals.untracked(choices).get(i) {
            Some(k) => (press.press)(usage_pick.days.untracked(), k)
            None => ()
          }
        },
      )
    })
  })
  |> ignore
}

///|
/// Each day's cost as a bar on the days' foot (usage_chart's): the day seen alone in full, the others on the tint (all
/// in full with none), what the most spent day spent over its bar (the one seen alone's, with one); a day pressed seen
/// alone, pressed again all of them again; a finger slid across the days lets go on the one it ends on. Each day's
/// name under its bar, the one seen alone's in the accent's words.
fn usage_chart_node(parent : @view.View, v : () -> Json?, filtered : () -> Json?) -> Unit {
  let daily = fn() { items(v(), "daily") }
  let many = fn() { flag(v(), "many") }
  let gap = fn() { if many() { 2.0 } else { 6.0 } }
  // The selected view knows whether its own cost was unpriced; the unfiltered parts do not.
  let shown_day = fn(d : Json?) -> Json? {
    if usage_chart_only(v()) == "" {
      d
    } else {
      let days = items(filtered(), "daily")
      match days.search_by(fn(one) { text(Some(one), "day") == text(d, "day") }) {
        Some(i) => Some(days[i])
        None => None
      }
    }
  }
  let shown_cost = fn(d : Json?) {
    number(shown_day(d), "cost")
  }
  let shown_cost_text = fn(d : Json?) {
    text(shown_day(d), "costText")
  }
  let days : Map[String, @view.View] = Map([])
  let press = fn(key : String) {
    let now = usage_pick.day.untracked()
    usage_pick.day.set(if now == key { "" } else { key })
  }
  // the day nearest a finger's x, by where the days are laid out
  let under = fn(x : Double) -> String {
    let mut best = ""
    let mut off = 0.0
    for d in @signals.untracked(daily) {
      let key = text(Some(d), "day")
      match days.get(key) {
        Some(n) => {
          let (cx, _, cw, _) = n.rect()
          let g = (x - (cx + cw / 2.0)).abs()
          if best == "" || g < off {
            best = key
            off = g
          }
        }
        None => ()
      }
    }
    best
  }
  let said = fn() {
    let shown = usage_pick.day.get()
    if shown != "" {
      shown
    } else {
      let mut peak = ""
      let mut most = 0.0
      for d in daily() {
        if shown_cost(Some(d)) > most {
          most = shown_cost(Some(d))
          peak = text(Some(d), "day")
        }
      }
      peak
    }
  }
  parent.box(fn(area) {
    area
    .row(Is(true))
    .gap(Is(8.0))
    .gesture(
      @ui.touch_slop(),
      tap=fn(d) {
        let k = under(d.wx)
        if k != "" {
          press(k)
        }
      },
      drag=fn(d) {
        if d.kind == Up {
          let k = under(d.wx)
          if k != "" {
            usage_pick.day.set(k)
          }
        }
      },
    )
    |> ignore
    area.show(fn() { area.window().0 >= 380.0 }, fn(scale) {
      let top_val = fn() { number(v(), "top").to_int() }
      scale.height(Is(Some(@sf.usage_plot))).lies_along(Is(Between)).shrink(Is(0.0)) |> ignore
      @sf.words_node(scale, fn() { "$" + top_val().to_string() }, fn() { ug_scale_label }) |> ignore
      @sf.words_node(scale, fn() { "$" + (top_val() / 2).to_string() }, fn() { ug_scale_label }) |> ignore
      @sf.words_node(scale, fn() { "$0" }, fn() { ug_scale_label }) |> ignore
    })
    area.box(fn(col) {
      col.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      col.box(fn(row) {
        row.row(Is(true)).height(Is(Some(@sf.usage_plot))).gap(By(gap)) |> ignore
        row.each(daily, fn(d) { text(Some(d), "day") }, fn(day, d) {
          let dv = fn() { Some(d.get()) }
          let key = fn() { text(dv(), "day") }
          {
            days[@signals.untracked(key)] = day
            day
            .grow(Is(1.0))
            .basis(Is(Some(0.0)))
            .min_width(Is(Some(0.0)))
            // (as high as the plot, what is said over its bar past its top where they are taller: its own least none)
            .min_height(Is(Some(0.0)))
            .lies_along(Is(End))
            .says(By(fn() { Some(@view.said(Button, label=text(dv(), "label") + " " + shown_cost_text(dv()))) }))
            .focusable(Is(true))
            .on_press(fn() { press(@signals.untracked(key)) })
            .takes(fn(_, _, _) { [] })
            |> ignore
            usage_bar_node(day, v, dv, fn() {
              let shown = usage_pick.day.get()
              shown == "" || key() == shown
            }, fn() { if key() == said() { shown_cost_text(dv()) } else { "" } })
          }
        })
      })
      |> ignore
      col.box(fn(b) { b.height(Is(Some(1.0))).ground(By(fn() { @ui.tree_theme().color(Line) })) |> ignore }) |> ignore
      col.box(fn(labels) {
        labels.row(Is(true)).padding(Is((0.0, 6.0, 0.0, 0.0))).gap(By(gap)) |> ignore
        labels.each(daily, fn(d) { text(Some(d), "day") }, fn(cell, d) {
          cell.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
          cell.box(fn(room) {
            // (as wide as the widest date, never wider: an old view's one-line words in a column, capped at its width)
            room.width(Is(Some(48.0))) |> ignore
            room.box(fn(m) {
              m.row(Is(true)).lies_along(Is(Middle)) |> ignore
              @sf.words_node(m, fn() { text(Some(d.get()), "tick") }, fn() {
                let shown = usage_pick.day.get()
                if shown != "" && text(Some(d.get()), "day") == shown { ug_label_on } else { ug_label }
              })
              .shrink(Is(1.0))
              .min_width(Is(Some(0.0)))
              .allow_ellipsis(Is(true))
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A day's bar (usage_bar's): as high as its share of the scale's top, 24 wide at most (as wide as its day with many),
/// round at its top: its parts stacked in their colours, the first at its foot; a day not shown on the tint. `said`
/// over it.
fn usage_bar_node(parent : @view.View, v : () -> Json?, d : () -> Json?, on : () -> Bool, said : () -> String) -> Unit {
  let top = fn() { number(v(), "top") }
  let cost = fn() { number(d(), "cost") }
  let h = fn() { @sf.usage_plot * @cmp.minimum(1.0, cost() / top()) }
  parent.show(fn() { top() > 0.0 && cost() > 0.0 }, fn(at) {
    // (as high as what it holds, past the day's top where that is taller: never squeezed)
    at.shrink(Is(0.0)) |> ignore
    // (each in the day's middle across it: ug_day's align=ACenter)
    // (never wider than the day: an old view's one-line words in a column, capped at its width)
    at.show(fn() { said() != "" }, fn(s) { ug_centered_words(s, said, ug_peak) })
    at.box(fn(m) {
      m.row(Is(true)).lies_along(Is(Middle)) |> ignore
      m.box(fn(bar) {
      let many = fn() { flag(v(), "many") }
      bar
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      .height(By(fn() { Some(h()) }))
      .max_width(By(fn() { if many() { None } else { Some(24.0) } }))
      .radius(By(fn() { @ui.tree_theme().corner(if many() { Sm } else { Base }) }))
      .clips(Is(true))
      .ground(By(fn() { if on() { 0L } else { @ui.tree_theme().color(TintStrong) } }))
      |> ignore
      bar.show(on, fn(parts) {
        // (as high as the bar, its parts sharing it)
        parts.grow(Is(1.0)) |> ignore
        let shares = fn() { numbers(d(), "shares") }
        parts.show(fn() { shares().length() == 0 }, fn(p) {
          p.grow(Is(1.0)).ground(By(fn() { @ui.tree_theme().color(Accent) })) |> ignore
        })
        // (the last first, down to the first at its foot)
        parts.each(
          fn() {
            let s = shares()
            let out = []
            for k = s.length() - 1; k >= 0; k = k - 1 {
              if s[k] > 0.0 {
                out.push((k, s[k]))
              }
            }
            out
          },
          fn(p) { p.0 },
          fn(part, p) {
            part
            .grow(By(fn() { p.get().1 }))
            .basis(Is(Some(0.0)))
            .min_height(Is(Some(0.0)))
            .ground(By(fn() {
              let series = items(v(), "series")
              let only = usage_chart_only(v())
              if only != "" && (p.get().0 >= series.length() || text(Some(series[p.get().0]), "key") != only) {
                @ui.tree_theme().color(TintStrong)
              } else {
                usage_series_ink(series, p.get().0)
              }
            }))
            |> ignore
          },
        )
      })
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What the page is narrowed to (usage_narrowed's): each a chip that takes it off, 8 apart, inline in the overview
/// card's header: the one seen alone (只看 林), the day (只看 10/5).
fn usage_narrowed_node(parent : @view.View, v : () -> Json?, chart : () -> Json?, tips? : @sf.TipLayer) -> Unit {
  let only = fn() { usage_pick.only.get().0 != "" }
  let day = fn() { usage_pick.day.get() != "" }
  parent.show(fn() { only() || day() }, fn(at) {
    let out = @sf.card_corner - @sf.small_corner - @sf.card_pad
    at.box(fn(chips) {
      chips.row(Is(true)).gap(Is(8.0)).wraps(Is(Some(8.0))).margin(Is((out, 0.0, 0.0, out))) |> ignore
      chips.show(only, fn(s) {
        let name = fn() {
          let (list, key) = usage_pick.only.get()
          let parts = items(chart(), "series")
          match parts.search_by(fn(p) { list == text(chart(), "split") && text(Some(p), "key") == key }) {
            Some(i) => text(Some(parts[i]), "name")
            None => text(field(v(), "only"), "title")
          }
        }
        @sf.chip_node(
          s,
          fn() { @sf.t("web-main.usage.only", args=[("name", name())]) },
          fn() { usage_pick.only.set(("", "")) },
          icon="close",
          said=fn() { @sf.t("web-main.usage.onlyOff", args=[("name", name())]) },
          tips?,
        )
        |> ignore
      })
      chips.show(day, fn(s) {
        let name = fn() {
          let days = items(chart(), "daily")
          match days.search_by(fn(d) { text(Some(d), "day") == usage_pick.day.get() }) {
            Some(i) => text(Some(days[i]), "name")
            None => text(v(), "period")
          }
        }
        @sf.chip_node(
          s,
          fn() { @sf.t("web-main.usage.only", args=[("name", name())]) },
          fn() { usage_pick.day.set("") },
          icon="close",
          said=fn() { @sf.t("web-main.usage.onlyOff", args=[("name", name())]) },
          tips?,
        )
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// The page's body under its head: for `7 天` / `30 天`, the period overview + daily trend card first, then the
/// 4-tab spending breakdown card (`对话 | 人 | 模型 | 账号`), then basis notes; for `累计`, the clean all-time summary
/// & 12-month heatmap card.
fn usage_body_node(
  parent : @view.View,
  core : Core,
  v : () -> Json?,
  chart : () -> Json?,
  error : () -> Json?,
  page_w : () -> Double,
  press : UsagePress,
  tips? : @sf.TipLayer,
) -> Unit {
  let details_pending = fn() { flag(v(), "detailsPreparing") || flag(chart(), "detailsPreparing") }
  parent.box(fn(b) {
    b.gap(Is(ug_body_gap)) |> ignore
    b.pick(fn() { usage_pick.summary.get() }, fn(body, is_sum) {
      if is_sum {
        usage_summary_node(body, chart, page_w, tips?)
      } else {
        body.gap(Is(ug_body_gap)) |> ignore
        body.show(details_pending, fn(at) {
          let sample = fn() { Some(usage_sample()) }
          @sf.waiting_node(at, fn(s) {
            s.box(fn(details) {
              details.gap(Is(ug_body_gap)) |> ignore
              usage_overview_node(details, core.quiet(), sample, sample, press)
              usage_none_node(details)
            }) |> ignore
          }, note=fn() { { reading: true, text: @sf.t("common.reading"), failing: [] } })
        })
        body.show(fn() { !details_pending() }, fn(at) { usage_overview_node(at, core, v, chart, press, tips?) })
        body.show(fn() { v() is None && error() is Some(_) }, fn(p) {
          @sf.words_node(p, fn() { @sf.t("web-pages.settings.usage.failed", args=[("error", error_text(error().unwrap()))]) }, fn() { ug_failed }) |> ignore
        })
        body.show(fn() { v() is Some(_) && !details_pending() }, fn(q) {
          q.pick(fn() { flag(v(), "empty") }, fn(p, empty) {
            if empty {
              let wait = fn() { field(v(), "wait") }
              p.pick(fn() { flag(wait(), "reading") || failing_of(wait()).length() > 0 }, fn(q, waits) {
                if waits {
                  @sf.waiting_node(q, fn(s) { usage_none_node(s) }, note=fn() {
                    { reading: flag(wait(), "reading"), text: "", failing: failing_of(wait()) }
                  })
                } else {
                  usage_none_node(q)
                }
              })
            } else {
              usage_ranks_node(p, core, v)
            }
          })
        })
        usage_notes_node(body, v)
      }
    })
  })
  |> ignore
}

///|
/// What the workspace's agents did since counting began (usage_summary's), on a card where the core says it: in a
/// column 760 at most in the card's middle, 24 apart, its title, its figures side by side (as many to a line as have 96
/// across, 16 apart, in lines), the year, each device's work and where the chats came from (side by side where they
/// have the room), when it is as of, what is missing.
fn usage_summary_node(parent : @view.View, v : () -> Json?, page_w : () -> Double, tips? : @sf.TipLayer) -> Unit {
  let sv = fn() { field(v(), "summary") }
  parent.show(fn() { sv() is Some(Object(_)) }, fn(at) {
    ug_card_node(at, fn(k) {
      // (as wide as the card leaves it up to its most, in its middle: ug_sum's w=Full max_w)
      k.box(fn(mid) {
        mid.row(Is(true)).lies_along(Is(Middle)) |> ignore
      mid.box(fn(sum) {
        sum.grow(Is(1.0)).basis(Is(Some(0.0))).max_width(Is(Some(760.0))).gap(Is(24.0)) |> ignore
        sum.box(fn(figs) {
          figs.row(Is(true)).gap(Is(16.0)).wraps(Is(Some(16.0))).lies_along(Is(Middle)) |> ignore
          figs.each(fn() { items(sv(), "figures").iter().take(3).collect().mapi(fn(i, f) { (i, f) }) }, fn(p) { p.0 }, fn(f, p) {
              f.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(96.0))).gap(Is(2.0)) |> ignore
              ug_centered_words(f, fn() { text(Some(p.get().1), "value") }, ug_figure_value)
              ug_centered_words(f, fn() { text(Some(p.get().1), "label") }, ug_figure_label)
          })
        })
        |> ignore
        usage_year_node(sum, fn() { field(sv(), "activity") }, fn() { if page_w() < 600.0 { 26 } else { 52 } }, tips?)
        sum.box(fn(lists) {
          lists.row(Is(true)).gap(Is(32.0)).wraps(Is(Some(32.0))).lines_up(Is(Some(Start))) |> ignore
          lists.box(fn(n) { usage_named_node(n, fn() { field(sv(), "stations") }) }) |> ignore
          lists.show(fn() { field(sv(), "places") is Some(Object(_)) }, fn(n) {
            usage_named_node(n, fn() { field(sv(), "places") })
          })
        })
        |> ignore
        sum.show(fn() { text(sv(), "partial") != "" }, fn(s) {
          @sf.words_node(s, fn() { text(sv(), "partial") }, fn() { ug_note }) |> ignore
        })
      })
      |> ignore
      })
      |> ignore
    })
  })
}

///|
/// A list of the summary's (usage_named's) as node `n` of a line's: its title, each its name muted at the line's start
/// (cut short where its line has not the room) and its value at its end; 240 across at least, growing to what its
/// line leaves it.
fn usage_named_node(n : @view.View, lv : () -> Json?) -> Unit {
  {
    n.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(240.0))).gap(Is(8.0)) |> ignore
    @sf.words_node(n, fn() { text(lv(), "title") }, fn() { ug_named_title }) |> ignore
    n.each(fn() { items(lv(), "items").mapi(fn(i, it) { (i, it) }) }, fn(p) { p.0 }, fn(slot, p) {
      ug_line_node(slot, fn(l) {
        ug_grow_words(l, fn() { text(Some(p.get().1), "name") }, ug_named_name) |> ignore
        // (giving way after its name has, to nothing, where the line has not the room: cut short, as the old view's
        // one line beside it comes down as a last resort)
        @sf.words_node(l, fn() { text(Some(p.get().1), "value") }, fn() { ug_named_value })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .allow_ellipsis(Is(true))
        |> ignore
      })
    })
  }
}

///|
/// The year (usage_year's): its title and how long over it, how it is drawn at the title's end (by day, by week, their
/// running total) where it is drawn more than one way; the last `weeks()` of its 52 a column each, Sunday's row first,
/// each row its day's name first; by day each a square in its level's colour, a day after today none; by week or their
/// running total each week a bar of its rows from the foot; each month's name over the week its first days are in
/// (none where its weeks have not the room); under it the levels from less to more, or what a column is. 12 apart.
fn usage_year_node(parent : @view.View, av : () -> Json?, weeks : () -> Int, tips? : @sf.TipLayer) -> Unit {
  let views = fn() { strings(av(), "views").iter().take(2).collect() }
  let shown = fn() { if usage_pick.year.get() < views().length() { usage_pick.year.get() } else { 0 } }
  let first = fn() { 52 - weeks() }
  let faint = fn() { @sf.alpha(@sf.theme().p.text, if @sf.theme().dark { 0.14 } else { 0.18 }) }
  let ink = fn(level : Int) -> Int64 {
    let p = @sf.theme().p
    match level {
      0 => faint()
      1 => @sf.alpha(p.accent, 0.22)
      2 => @sf.alpha(p.accent, 0.42)
      3 => @sf.alpha(p.accent, 0.68)
      _ => p.accent
    }
  }
  parent.box(fn(y) {
    y.gap(Is(12.0)) |> ignore
    ug_line_node(y, fn(l) {
      l.box(fn(h) {
        h.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(1.0)) |> ignore
        @sf.words_node(h, fn() { text(av(), "title") }, fn() { ug_named_title }) |> ignore
        ug_grow_words(h, fn() { text(av(), "sub") }, ug_named_name) |> ignore
      })
      |> ignore
      l.show(fn() { views().length() > 1 }, fn(s) { @sf.segmented_node(s, views, shown, fn(k) { usage_pick.year.set(k) }) })
    })
    // the grid: the months' names, then a row a weekday, 2 apart
    y.box(fn(grid) {
      grid.gap(Is(2.0)) |> ignore
      ug_grid_row_node(grid, fn(r) {
        r.box(fn(lead) { lead.width(Is(Some(20.0))) |> ignore }) |> ignore
        r.each(
          fn() {
            let starts = items(av(), "months").filter(fn(m) { number(Some(m), "week").to_int() >= first() })
            let out : Array[(String, Int, String)] = []
            let lead = match starts.get(0) {
              Some(m) => number(Some(m), "week").to_int() - first()
              None => 52 - first()
            }
            if lead > 0 {
              out.push(("lead", lead, ""))
            }
            for i, m in starts {
              let from = number(Some(m), "week").to_int()
              let until = match starts.get(i + 1) {
                Some(n) => number(Some(n), "week").to_int()
                None => 52
              }
              out.push((from.to_string(), until - from, text(Some(m), "label")))
            }
            out
          },
          fn(m) { m.0 },
          fn(b, m) {
            // (14 high, or as its name's line where the system's size of words draws it higher: a least, which its
            // words push open)
            b.grow(By(fn() { m.get().1.to_double() })).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).min_height(Is(Some(14.0))).clips(Is(true)) |> ignore
            b.show(fn() { m.get().2 != "" }, fn(w) {
              // (none where its weeks have not the room for it: the year's last month, its first week only)
              w.words(By(fn() { m.get().2 })).words_look(Is(@ui.style_words(ug_grid_label))).ink(By(fn() { @ui.style_ink(ug_grid_label) })).shorter(Is([""]))
              |> ignore
            })
          },
        )
      })
      for row in 0..<7 {
        ug_grid_row_node(grid, fn(r) {
          r.box(fn(lead) {
            lead.width(Is(Some(20.0))) |> ignore
            // (Monday's, Wednesday's and Friday's, as GitHub's: a name a row is taller than the rows)
            @sf.words_node(lead, fn() {
              let weekdays = strings(av(), "weekdays")
              if shown() == 0 && row % 2 == 1 && row < weekdays.length() { weekdays[row] } else { "" }
            }, fn() { ug_grid_label })
            |> ignore
          })
          |> ignore
          r.each(fn() { Array::makei(weeks(), fn(i) { first() + i }) }, fn(w) { w }, fn(cell, w) {
              cell
              .grow(Is(1.0))
              .basis(Is(Some(0.0)))
              .min_width(Is(Some(0.0)))
              .aspect(Is(1.0))
              .radius(By(fn() { @ui.tree_theme().corner(Sm) }))
              .ground(By(fn() {
                let wk = w.get()
                if shown() == 0 {
                  let cells = numbers(av(), "cells")
                  let k = wk * 7 + row
                  let l = if k < cells.length() { cells[k].to_int() } else { -1 }
                  if l < 0 { 0L } else { ink(l) }
                } else {
                  let bars = numbers(av(), if shown() == 1 { "weekly" } else { "cumulative" })
                  let h = if wk < bars.length() { bars[wk].to_int() } else { 0 }
                  if 7 - row <= h { @sf.theme().p.accent } else { 0L }
                }
              }))
              |> ignore
              // (what it is, said as the pointer rests on it: a day's date and tokens; by week, its week's, the whole
              // column)
              match tips {
                Some(t) =>
                  @sf.tip_node(t, cell, fn() {
                    let k = if shown() == 0 { w.get() * 7 + row } else { w.get() }
                    let all = strings(av(), if shown() == 0 {
                      "tips"
                    } else if shown() == 1 {
                      "weekTips"
                    } else {
                      "runningTips"
                    })
                    all.get(k).unwrap_or("")
                  }, side=Top, within=true)
                  |> ignore
                None => ()
              }
          })
        })
      }
    })
    |> ignore
    y.pick(fn() { shown() == 0 }, fn(p, by_day) {
      if by_day {
        p.box(fn(leg) {
          leg.row(Is(true)).gap(Is(2.0)).lines_up(Is(Some(Middle))) |> ignore
          @sf.words_node(leg, fn() { text(av(), "less") }, fn() { ug_grid_label }) |> ignore
          for l in 0..<5 {
            leg.box(fn(c) {
              c
              .width(Is(Some(10.0)))
              .height(Is(Some(10.0)))
              .radius(By(fn() { @ui.tree_theme().corner(Sm) }))
              .ground(By(fn() { ink(l) }))
              |> ignore
            })
            |> ignore
          }
          @sf.words_node(leg, fn() { text(av(), "more") }, fn() { ug_grid_label }) |> ignore
        })
        |> ignore
        p.show(fn() { strings(av(), "captions").get(0).unwrap_or("") != "" }, fn(c) {
          @sf.words_node(c, fn() { strings(av(), "captions")[0] }, fn() { ug_grid_label }) |> ignore
        })
      } else {
        p.show(fn() { shown() < strings(av(), "captions").length() }, fn(c) {
          @sf.words_node(c, fn() { strings(av(), "captions").get(shown()).unwrap_or("") }, fn() { ug_grid_label }) |> ignore
        })
      }
    })
  })
  |> ignore
}

///|
/// A row of the year's grid (ug_grid_row): what it holds side by side, 2 apart, across their middle.
fn ug_grid_row_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(r) {
    r.row(Is(true)).gap(Is(2.0)).lines_up(Is(Some(Middle))) |> ignore
    make(r)
  })
  |> ignore
}

///|
/// A choice of the page's pressed, its days or its split (usage_node's): what was pressed, `pressed` (its days and split;
/// None none), shown by the choices from the press till what the page reads for it is answered; `press` presses one.
priv struct UsagePress {
  pressed : @signals.Signal[(Int, String)?]
  press : (Int, String) -> Unit
}

///|
/// 用量 (UsageSettings, UsageScreen) made once as nodes (page_node, laid out by the `width` its frame gives it, narrow
/// where none is given): its title, at its line's end 分享卡片 once something was spent and the days (7 or 30); the
/// core's view once read (usage_body_node), what failed while it is not, a wait till then (the view made up, in its
/// bones, nothing of the core's asked for it). What it says of itself told `said`; what is said of what the pointer
/// rests on in the frame's layer of tips over the window where it gives one (`tips`), else in its own over the page.
/// Its days or its split pressed, what the page reads for them is asked of `src` (usage_reads) and the page stays as it
/// is, the choice showing what was pressed; what it reads is switched to them whole in the frame that is answered, in
/// the press's where it is already (sfbase's switch_answered): never its bones for a choice pressed. What it reads
/// (usage_pick: the days kept while the page is) changes only then; another choice pressed, or the page left, gives the
/// wait up, the choice back on what is shown.
pub fn usage_node(
  v : @view.View,
  core : Core,
  src : Source,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  bar_actions? : ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
) -> Unit {
  // (what is said of what the pointer rests on: the frame's, over the window; else in a layer of its own past the
  // page's list, which cuts what it holds to it)
  let tips_at : Ref[@view.View?] = Ref(None)
  let own_tips = tips is None
  let tips = match tips {
    Some(t) => t
    None => @sf.TipLayer::new(fn() { tips_at.val })
  }
  // (how wide the page is: the frame's where it gives one, else the window's (a phone's page): half the year's
  // weeks where it is narrower than 600, as the old view's were by the width it was drawn in)
  let page_w = match width {
    Some(w) => w
    None => fn() { v.window().0 }
  }
  let topic_of = fn(ask : (String, Map[String, Json])) { (core.topic)(ask.0, ask.1).get() }
  // (each read as it reads it, saying so where a choice pressed handed it what it asked: sfbase's shown_read)
  let read_of = fn(ask : (String, Map[String, Json])) {
    let r = topic_of(ask)
    @sfbase.shown_read(usage_shown_at)
    r
  }
  let read = fn() {
    read_of(usage_ask(here(), usage_pick.days.get(), usage_pick.split.get(), only=usage_pick.only.get(), day=usage_pick.day.get()))
  }
  let value = fn() { read().value }
  // Keep the chart's unfiltered view subscribed while the selected totals and chats are read.
  let chart_ask = fn() { usage_ask(here(), usage_pick.days.get(), usage_pick.split.get()) }
  let chart_read = fn() { read_of(chart_ask()) }
  let chart = fn() { chart_read().value }
  // (a choice pressed and what waits for what it reads: one at a time)
  let pressed : @signals.Signal[(Int, String)?] = @signals.signal(None)
  let waiting : Ref[@sfbase.PressWait?] = Ref(None)
  let press = fn(days : Int, split : String) {
    @signals.untracked(fn() {
      guard pressed.get() != Some((days, split)) else { return }
      // (the one pressed before: waited for no more, the choice back on what is shown)
      match waiting.val {
        Some(w) => {
          waiting.val = None
          w.give_up()
        }
        None => ()
      }
      let shown_days = usage_pick.days.get()
      let shown_split = usage_pick.split.get()
      // (what the page shows pressed: nothing to ask; the core's choice of split pressed as it says it)
      if days == shown_days && (split == shown_split || (shown_split == "" && split == text(topic_of(chart_ask()).value, "split"))) {
        pressed.set(None)
        return
      }
      // (another day's span lets the day seen alone go; another split the part seen alone)
      let day = if days == shown_days { usage_pick.day.get() } else { "" }
      let only = if split == shown_split { usage_pick.only.get() } else { ("", "") }
      pressed.set(Some((days, split)))
      let w = @sfbase.switch_answered(
        src,
        usage_reads(here(), days, split, only, day),
        usage_shown_at,
        fn() {
          usage_pick.days.set(days)
          usage_pick.split.set(split)
          usage_pick.only.set(only)
          usage_pick.day.set(day)
          pressed.set(None)
        },
        let_go=fn() {
          if pressed.untracked() == Some((days, split)) {
            pressed.set(None)
          }
        },
      )
      if w.waiting() {
        waiting.val = Some(w)
      }
    })
  }
  let choice : UsagePress = { pressed, press }
  // (at its title's line's end; where a frame's bar names it, in that bar, as tall as its days' choice stands there)
  let actions = fn(l : @view.View) {
    // (the card to share of the agents' week, once something was spent, before the days)
    l.show(fn() { value() is Some(_) && !flag(value(), "empty") }, fn(s) {
      @sf.icon_button_node(s, "share", fn() { @sf.t("web-main.stations.shareCard") }, fn() { (core.share_card)() }, tips~) |> ignore
    })
    @sf.segmented_node(
      l,
      head=true,
      fn() {
        [
          @sf.t("web-main.usage.days", args=[("n", "7")]),
          @sf.t("web-main.usage.days", args=[("n", "30")]),
          "累计",
        ]
      },
      fn() {
        if usage_pick.summary.get() {
          2
        } else {
          let days = match pressed.get() {
            Some((d, _)) => d
            None => usage_pick.days.get()
          }
          if days == 30 { 1 } else { 0 }
        }
      },
      fn(k) {
        if k == 2 {
          usage_pick.summary.set(true)
        } else {
          usage_pick.summary.set(false)
          press(usage_days_choices[k], usage_pick.split.untracked())
        }
      },
    )
  }
  match bar_actions {
    Some(f) => f(actions, @sf.segmented_node_height)
    None => ()
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.settings.usage.title") },
    fn() { ["body"] },
    fn(b, _) {
      b.pick(
        fn() {
          match (chart(), chart_read().error) {
            (Some(_), _) => 0
            (None, Some(_)) => 1
            (None, None) => 2
          }
        },
        fn(p, state) {
          match state {
            0 => usage_body_node(p, core, value, chart, fn() { read().error }, page_w, choice, tips~)
            1 =>
              @sf.words_node(p, fn() {
                match chart_read().error {
                  Some(e) => @sf.t("web-pages.settings.usage.failed", args=[("error", error_text(e))])
                  None => ""
                }
              }, fn() { ug_failed })
              |> ignore
            _ => {
              let quiet = core.quiet()
              let sample = fn() { Some(usage_sample()) }
              @sf.waiting_node(p, fn(s) { usage_body_node(s, quiet, sample, sample, fn() { None }, page_w, choice) })
            }
          }
        },
      )
    },
    on_back~,
    frame~,
    about=fn() { @sf.t("web-pages.settings.usage.lead") },
    said?,
    width?,
    tips~,
    actions~,
  )
  if own_tips {
    tips_at.val = Some(v.box(fn(l) { l.over(Is(true)) |> ignore }))
  }
}

///|
/// What failed as the page says it (usage_page's, in every look: a list's note in red).
// kept across runs: a value (no field of it changes)
let ug_failed : @ui.TextStyle = @sf.wide_list_note.then(@ui.text_style(color=Danger))

///|
/// Words on one line in the middle of a column across it, never wider than it: cut short at its width where they are
/// wider (an old view's one-line words in a column, capped at its width).
fn ug_centered_words(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> Unit {
  parent.box(fn(m) {
    m.row(Is(true)).lies_along(Is(Middle)) |> ignore
    @sf.words_node(m, words, fn() { style }).shrink(Is(1.0)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
  })
  |> ignore
}


///|
/// 价目表 (UsagePricesSettings, UsagePricesScreen) made once as nodes of the window's tree (page_node, laid out by the
/// `width` its frame gives it, narrow where none is given): each station's prices on a card of its own, its name, what
/// its prices are, and a table of its models and their rates (@sf.table_node, as a message's table is drawn), 20 past
/// the card's words either side to its corner's inset; none, said; while they are read, a made-up station's card in
/// its bones (no core asked for it); the core's `usage` view at `days` read as it changes. What it says of itself told
/// `said`.
pub fn usage_prices_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  days : Int,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let topic = fn() { (core.topic)("usage", { "scope": str(here().workspace), "days": Json::number(days.to_double()) }).get() }
  let tables = fn() { items(topic().value, "prices") }
  let merged_table = fn() -> Json? {
    let ts = tables()
    if ts.length() == 0 {
      return None
    }
    let seen : Array[String] = []
    let merged_rows : Array[Json] = []
    let mut note = ""
    for t in ts {
      let n = text(Some(t), "note")
      if note == "" && items(Some(t), "rows").length() > 0 && n != "" {
        note = n
      }
      for r in items(Some(t), "rows") {
        let m = text(Some(r), "model")
        if m != "" && !seen.contains(m) {
          seen.push(m)
          merged_rows.push(r)
        }
      }
    }
    if note == "" {
      note = "每百万 token 的美元折算单价，取自各服务商公开 API 价格"
    }
    Some({
      "station": Json::string("模型折算单价"),
      "note": Json::string(note),
      "rows": Json::array(merged_rows),
    })
  }
  let wait = fn() { field(topic().value, "wait") }
  let blocks = fn() {
    match topic().value {
      None => ["waiting"]
      Some(_) =>
        if tables().length() == 0 && (flag(wait(), "reading") || failing_of(wait()).length() > 0) {
          ["read"]
        } else if tables().length() == 0 {
          ["none"]
        } else {
          ["unified"]
        }
    }
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.settings.prices.title") },
    blocks,
    fn(b, key) {
      match key {
        "waiting" =>
          @sf.waiting_node(b, fn(s) { up_card_node(s, fn() { Some(up_sample()) }, tree=fn() { Some(up_sample_tree()) }) }, error=fn() {
            match topic().error {
              Some(e) => @sf.t("web-pages.settings.prices.failed", args=[("error", @settings.error_text(e))])
              None => ""
            }
          })
        "read" =>
          @sf.waiting_node(b, fn(s) { up_card_node(s, fn() { Some(up_sample()) }, tree=fn() { Some(up_sample_tree()) }) }, note=fn() {
            let failing = failing_of(wait())
            { reading: failing.length() == 0, text: "", failing }
          })
        "none" => @sf.page_none_node(b, fn() { @sf.t("web-main.usage.noPrices") })
        _ => up_card_node(b, merged_table)
      }
    },
    on_back~,
    frame~,
    lead=fn() { @sf.t("web-pages.settings.prices.lead") },
    said?,
    width?,
  )
}

///|
/// A station's prices (`tv`) on a card of its own (price_card's): its name, what its prices are, and a table of its
/// models and their rates, as a message's table is drawn; none of its models used, said.
fn up_card_node(parent : @view.View, tv : () -> Json?, tree? : () -> Json? = fn() { None }) -> Unit {
  @sf.page_card_node(parent, fn(k) {
    @sf.words_node(k, fn() { text(tv(), "station") }, fn() { up_station }) |> ignore
    @sf.words_node(k, fn() { text(tv(), "note") }, fn() { @sf.wide_list_note }) |> ignore
    k.show(fn() { items(tv(), "rows").length() == 0 }, fn(n) {
      @sf.words_node(n, fn() { @sf.t("web-main.usage.noModelUsage") }, fn() { @sf.wide_list_note }) |> ignore
    })
    k.show(fn() { items(tv(), "rows").length() > 0 }, fn(t) {
      // (at the card's foot: as far past the card's words under it as its scroll reaches to either side,
      // up_table_across)
      t.margin(Is((0.0, 0.0, 0.0, @sf.corner_inset - @sf.card_pad))) |> ignore
      let tree_fn = fn() {
        match tree() {
          Some(x) => Some(x)
          None => up_tree(tv())
        }
      }
      @sf.table_node(t, fn() { up_markdown(tv()) }, bleed=@sf.card_pad - @sf.corner_inset, tree=tree_fn)
    })
  })
}

///|
fn up_tree(tv : Json?) -> Json? {
  let rows = items(tv, "rows")
  if rows.length() == 0 {
    return None
  }
  let cell = fn(s : String) { Json::array([Json::string("td"), Json::array([Json::string(s)])]) }
  let row = fn(cells : Array[String]) { Json::array([Json::string("tr"), Json::array(cells.map(cell))]) }
  let head = [@sf.t("web-main.model.models")]
  head.append(items(Some(rows[0]), "rates").map(fn(r) { text(Some(r), "label") }))
  let trs = [row(head)]
  for r in rows {
    let cells = [text(Some(r), "model")]
    cells.append(items(Some(r), "rates").map(fn(x) { text(Some(x), "value") }))
    trs.push(row(cells))
  }
  Some(Json::array([Json::array([Json::string("table"), Json::array(trs)])]))
}

///|
/// A station's prices' table as Markdown (price_card's): its model, then each rate; the head the first row's rates'
/// labels.
fn up_markdown(tv : Json?) -> String {
  let rows = items(tv, "rows")
  if rows.length() == 0 {
    return ""
  }
  let head = [@sf.t("web-main.model.models")]
  head.append(items(Some(rows[0]), "rates").map(fn(r) { text(Some(r), "label") }))
  let line = fn(cells : Array[String]) { "| " + cells.map(fn(x) { x.replace_all(old="|", new="\\|") }).join(" | ") + " |" }
  let md = [line(head), line(head.map(fn(_) { "---" }))]
  for r in rows {
    let cells = [text(Some(r), "model")]
    cells.append(items(Some(r), "rates").map(fn(x) { text(Some(x), "value") }))
    md.push(line(cells))
  }
  md.join("\n")
}

///|
/// A made-up station's table as the core would read it (prices_sample's): its head and its four rows, each cell's words
/// made up, for its card in a page's bones (nothing asked of the core).
fn up_sample_tree() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let cell = fn(n : Int) { Json::array([Json::string("td"), Json::array([w(n)])]) }
  let row = fn(first : Int) { Json::array([Json::string("tr"), Json::array([cell(first), cell(3), cell(3), cell(3)])]) }
  let table = Json::array([Json::string("table"), Json::array([row(3)] + [6, 8, 5, 7].map(row))])
  Json::array([table])
}

///|
/// A made-up station's prices (prices_sample's), for its card in a page's bones.
fn up_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let rows = [6, 8, 5, 7].map(fn(n) {
    Json::object({ "model": w(n), "rates": Json::array([0, 1, 2].map(fn(_) { Json::object({ "label": w(3), "value": w(4) }) })) })
  })
  { "station": w(4), "note": w(18), "rows": Json::array(rows) }
}
