// The looks the card to share can be drawn in (2026-10-27 用户：「再搞几版骚气的分享图片模板，让用户可以选择」), chosen
// under it on its stage (share_looks_pick), the choice kept on the device (the prefs' `shareLook`): the night
// (stations_now.mbt night_look, as it was), 大字报 (still.fail's orange to its edges, its number as large as the
// picture holds), 小票 (a till's receipt of what the agents did, in the code face) and 终端 (a terminal's run of a
// command that says it). Each says what the night says, from the same `fleet` view, laid out its own way, 360 wide as
// it is (@sf.share_w_most), nothing cut short; each the same in either theme, as a poster is. The code face only for
// what a till or a terminal prints in it (figures, dates, the command): words of Chinese in it stand a cell apart
// (「9  个对话」), so what is said is in the face of words.

///|
/// The looks, in the order they are offered.
// kept across runs: a table, never written
let share_looks : Array[String] = ["night", "poster", "receipt", "terminal"]

///|
/// The look chosen (the prefs' `shareLook`; none kept, or one this build does not know: the night).
fn share_look(src : Source) -> String {
  let kept = text((src.topic)("prefs", Map::new()).value, "shareLook")
  if share_looks.contains(kept) {
    kept
  } else {
    "night"
  }
}

///|
/// Under the picture, over its buttons: each look a small picture of it, its name under it, the chosen one ringed; a
/// press on another draws the card in it at once and keeps it the device's (`prefs.set`).
fn share_looks_pick(c : @ui.Ctx, src : Source) -> Unit {
  let now = share_look(src)
  c.box(style=looks_row, fn() {
    for look in share_looks {
      let id = c.id("share-card/look/" + look)
      let on = look == now
      let name = @sf.t("web-main.stations.shareLook." + look)
      let b = c.box(style=looks_item, id~, fn() {
        c.box(style=if on { looks_ring_on } else { looks_ring }, fn() { look_tile(c, look) }) |> ignore
        c.text(name, style=if on || c.lit(id) { looks_name_on } else { looks_name }) |> ignore
      })
      c.semantics(b, Button, id~, label=name, selected=on)
      if c.clicked(id) && !on {
        (src.call)("prefs.set", { "shareLook": Json::string(look) }, fn(_) {  })
      }
    }
  })
  |> ignore
}

///|
/// A look's small picture: its ground, its dot, a line of its words and a shorter one dimmer.
fn look_tile(c : @ui.Ctx, look : String) -> Unit {
  let (ground, ink, dim, dot) = match look {
    "poster" => (@sf.share_poster_ground, @sf.share_poster_ink, @sf.share_poster_dim, @sf.share_poster_ink)
    "receipt" => (@sf.share_receipt_ground, @sf.share_receipt_ink, @sf.share_receipt_dim, @sf.share_receipt_orange)
    "terminal" => (@sf.share_terminal_ground, @sf.share_terminal_ink, @sf.share_terminal_dim, @sf.share_orange)
    _ => (@sf.share_ground, @sf.share_ink, @sf.share_dim, @sf.share_orange)
  }
  c.box(style=@sf.share_look_tile.then(@ui.style(bg=Data(ground))), fn() {
    c.box(style=tile_inner, fn() {
      c.box(style=tile_dot.then(@ui.style(bg=Data(dot))), fn() {  }) |> ignore
      c.box(style=tile_line.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
      c.box(style=tile_short.then(@ui.style(bg=Data(dim))), fn() {  }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The card as box `id`, in `ground`: round as a card on the stage, or `flat` (handed out: its ground to its edges).
fn look_box(c : @ui.Ctx, id : Int, flat : Bool, ground : Int64, inner : () -> Unit) -> Int {
  c.box(style=(if flat { pic_box_flat } else { pic_box }).then(@ui.style(bg=Data(ground))), id~, inner)
}

///|
/// Words in the code face.
fn code_words(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.rich([@ui.span(words, mono=true)], style~) |> ignore
}

///|
/// A span's figures, each its value and what it is (today's, the last 7 days').
fn span_stats(span : Json?) -> Array[(String, String)] {
  items(span, "stats").map(fn(x) { (text(Some(x), "label"), text(Some(x), "value")) })
}

// ── 大字报 ─────────────────────────────────────────────────────────────────

///|
/// 大字报: still.fail's orange to its edges, in the night's black. Read down: still.fail (all of it the black: a white
/// dot was 3.1 to 1 on the orange) and when; what
/// leads the first kind's share, the share as large as the picture holds, what it is of; each kind a meter, as much
/// of it filled as its accounts' weeks used (the ring's share), its name, accounts and share over it; the days in a
/// band of the black (today, the last 7, each day's chats archived a bar, today's the orange); the chats at work, the
/// tasks across devices; still.fail's line, large.
fn poster_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let quota = items(fleet, "quota")
  look_box(c, id, flat, @sf.share_poster_ground, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() {
        c.text("still.fail", style=poster_brand) |> ignore
      })
      |> ignore
      c.text(text(fleet, "at"), style=poster_at) |> ignore
    })
    |> ignore
    c.box(style=poster_hero, fn() {
      if quota.length() > 0 {
        let first = Some(quota[0])
        let used = text(first, "usedText")
        c.text(text(first, "lead"), style=poster_words) |> ignore
        let scale = if used.length() > 4 { @sf.share_poster_number_less } else { @sf.share_poster_number_scale }
        c.rich([@ui.span(used, scale~)], style=poster_number) |> ignore
        c.text(text(first, "of"), style=poster_words) |> ignore
      } else {
        c.rich([@ui.span(count(fleet, "chats").to_string(), scale=@sf.share_poster_number_scale)], style=poster_number)
        |> ignore
        c.text(text(fleet, "chatsText"), style=poster_words) |> ignore
      }
    })
    |> ignore
    if quota.length() > 0 {
      c.box(style=poster_meters, fn() {
        for q in quota {
          let q = Some(q)
          c.box(style=poster_meter, fn() {
            c.box(style=pic_other, fn() {
              c.text(text(q, "name"), style=poster_key_name) |> ignore
              c.text(text(q, "accountsText"), style=poster_key_dim) |> ignore
              c.box(style=pic_grow, fn() {  }) |> ignore
              c.text(text(q, "usedText"), style=poster_key_share) |> ignore
            })
            |> ignore
            let filled : @ui.Len = Pct(dmin(1.0, dmax(0.0, number(q, "share"))) * 100.0)
            c.box(style=poster_track, fn() {
              c.box(style=poster_fill.then(@ui.style(w=filled)), fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    match (field(fleet, "today"), field(fleet, "week")) {
      (Some(Object(_)) as today, Some(Object(_)) as week) =>
        c.box(style=poster_band, fn() {
          for span in [today, week] {
            c.box(style=poster_span, fn() {
              c.text(text(span, "title"), style=poster_band_title) |> ignore
              c.box(style=pic_stats, fn() {
                for x in span_stats(span) {
                  c.box(style=pic_stat, fn() {
                    c.text(x.1, style=poster_band_value) |> ignore
                    c.text(x.0, style=poster_band_label) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
            })
            |> ignore
          }
          day_bars(c, week, @sf.share_bar, @sf.share_orange, pic_day_label, pic_day_today)
        })
        |> ignore
      _ => ()
    }
    let tasks = text(fleet, "tasksText")
    c.box(style=pic_lines, fn() {
      if quota.length() > 0 {
        c.rich([@ui.span(text(fleet, "chatsText"), weight=700), @ui.span("  ·  " + text(fleet, "where"))], style=poster_line)
        |> ignore
      }
      if tasks != "" {
        c.text(tasks, style=poster_line_bold) |> ignore
        c.text(text(fleet, "tasksPer"), style=poster_line) |> ignore
      }
    })
    |> ignore
    c.text(@sf.t("web-main.stations.shareTagline"), style=poster_tagline) |> ignore
  })
}

///|
/// Each day's chats archived a bar (as tall as its share of the busiest day's, pic_bar_least at least), in `bar`,
/// today's in `today`, its date under it.
fn day_bars(
  c : @ui.Ctx,
  week : Json?,
  bar : Int64,
  today : Int64,
  label : @ui.TextStyle,
  today_label : @ui.TextStyle,
) -> Unit {
  c.box(style=pic_bars_row, fn() {
    for d in items(week, "days") {
      let d = Some(d)
      let h = dmax(pic_bar_least, number(d, "share") * pic_bars_h)
      let on = flag(d, "today")
      c.box(style=pic_day, fn() {
        c.box(style=pic_bar_room, fn() {
          c.box(style=pic_bar.then(@ui.style(h=Fixed(h), bg=Data(if on { today } else { bar }))), fn() {  }) |> ignore
        })
        |> ignore
        c.text(text(d, "label"), style=if on { today_label } else { label }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

// ── 小票 ───────────────────────────────────────────────────────────────────

///|
/// 小票: a till's receipt of the agents' week, in the code face on its paper. Read down: still.fail and when, in its
/// middle; each kind of subscription a line (its name and accounts, its share at the line's end); today's and the last
/// 7 days' figures as a receipt's items (what, then how much at the line's end); each day's chats archived a bar; the
/// chats at work and the tasks across devices; between double dashes the last 7 days' spend, large, as its total; a
/// barcode made of what it says, still.fail's line under it.
fn receipt_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let quota = items(fleet, "quota")
  let week = field(fleet, "week")
  look_box(c, id, flat, @sf.share_receipt_ground, fn() {
    c.box(style=receipt_head, fn() {
      c.rich(
        [@ui.span("still", mono=true), @ui.span(".", mono=true, color=@sf.share_receipt_orange), @ui.span("fail", mono=true)],
        style=receipt_brand,
      )
      |> ignore
      code_words(c, text(fleet, "at"), receipt_dim)
    })
    |> ignore
    dashes(c)
    if quota.length() > 0 {
      c.box(style=receipt_items, fn() {
        for q in quota {
          let q = Some(q)
          receipt_item(c, text(q, "name") + " ×" + count(q, "accounts").to_string(), text(q, "usedText"), true)
        }
      })
      |> ignore
      dashes(c)
    }
    match (field(fleet, "today"), week) {
      (Some(Object(_)) as today, Some(Object(_))) => {
        for span in [today, week] {
          c.box(style=receipt_items, fn() {
            c.text(text(span, "title"), style=receipt_title) |> ignore
            for x in span_stats(span) {
              receipt_item(c, x.0, x.1, false)
            }
          })
          |> ignore
        }
        day_bars(c, week, @sf.share_receipt_rule, @sf.share_receipt_orange, receipt_day, receipt_day_today)
        dashes(c)
      }
      _ => ()
    }
    c.box(style=receipt_items, fn() {
      c.text(text(fleet, "chatsText"), style=receipt_line_bold) |> ignore
      c.text(text(fleet, "where"), style=receipt_line) |> ignore
      let tasks = text(fleet, "tasksText")
      if tasks != "" {
        c.text(tasks, style=receipt_line_bold) |> ignore
        c.text(text(fleet, "tasksPer"), style=receipt_line) |> ignore
      }
    })
    |> ignore
    // the total: the last 7 days' spend (their figures' last), between double dashes
    match span_stats(week) {
      [.., (label, value)] => {
        c.box(style=receipt_double, fn() {
          dashes(c)
          dashes(c)
        })
        |> ignore
        c.box(style=pic_other, fn() {
          c.text(label, style=receipt_title) |> ignore
          c.box(style=pic_grow, fn() {  }) |> ignore
          code_words(c, value, receipt_total)
        })
        |> ignore
        c.box(style=receipt_double, fn() {
          dashes(c)
          dashes(c)
        })
        |> ignore
      }
      _ => ()
    }
    c.box(style=receipt_foot, fn() {
      barcode(c, text(fleet, "at") + text(fleet, "chatsText") + text(fleet, "tasksText"))
      c.text(@sf.t("web-main.stations.shareTagline"), style=receipt_tagline) |> ignore
    })
    |> ignore
  })
}

///|
/// An item of the receipt: what it is, its figure at the line's end (`strong`: in the ink's weight).
fn receipt_item(c : @ui.Ctx, what : String, value : String, strong : Bool) -> Unit {
  c.box(style=pic_other, fn() {
    c.text(what, style=if strong { receipt_name } else { receipt_line }) |> ignore
    c.box(style=pic_grow, fn() {  }) |> ignore
    code_words(c, value, receipt_value)
  })
  |> ignore
}

///|
/// A torn line of dashes across the receipt.
fn dashes(c : @ui.Ctx) -> Unit {
  c.box(style=receipt_dashes, fn() {
    for _ in 0..<receipt_dash_count {
      c.box(style=receipt_dash, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A barcode of `words`: a bar for each of its characters, as wide as its code says (1 to 3), as far from the next.
fn barcode(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=receipt_code, fn() {
    let mut n = 0
    for ch in words {
      if n >= receipt_code_most {
        break
      }
      let k = ch.to_int()
      let w = (k % 3 + 1).to_double()
      let gap = (k / 3 % 2 + 1).to_double()
      c.box(style=receipt_bar.then(@ui.style(w=Fixed(w))), fn() {  }) |> ignore
      c.box(style=@ui.style(w=Fixed(gap)), fn() {  }) |> ignore
      n = n + 1
    }
  })
  |> ignore
}

// ── 终端 ───────────────────────────────────────────────────────────────────

///|
/// 终端: a terminal's window, a command run in it that answers what the night says, in the code face. Read down: its
/// window's three dots and its title; the prompt and the command, when as a comment; each kind its name and accounts,
/// a meter of 20 cells as much of it filled as its accounts' weeks used (the first's in the orange), its share; today's
/// and the last 7 days' figures, each a section (its title in brackets) of a line a figure; each day's chats archived
/// a column of cells, today's the orange; the
/// chats at work, the tasks across devices, each after an arrow; the prompt again, its cursor; still.fail's line as a
/// comment.
fn terminal_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let quota = items(fleet, "quota")
  look_box(c, id, flat, @sf.share_terminal_ground, fn() {
    c.box(style=term_bar, fn() {
      for _ in 0..<3 {
        c.box(style=term_dot, fn() {  }) |> ignore
      }
      c.box(style=pic_grow, fn() { code_words(c, "still.fail — zsh", term_title) }) |> ignore
    })
    |> ignore
    c.box(style=term_block, fn() {
      prompt(c, "still.fail fleet --week")
      code_words(c, "# " + text(fleet, "at"), term_dim)
    })
    |> ignore
    for k, q in quota {
      let q = Some(q)
      c.box(style=term_block, fn() {
        c.box(style=pic_other, fn() {
          c.text(text(q, "name"), style=term_name) |> ignore
          c.text(text(q, "accountsText"), style=term_dim) |> ignore
        })
        |> ignore
        c.box(style=term_meter_row, fn() {
          let filled = (dmin(1.0, dmax(0.0, number(q, "share"))) * term_cells.to_double()).round().to_int()
          c.box(style=term_meter, fn() {
            for i in 0..<term_cells {
              let ink = if i >= filled {
                @sf.share_terminal_cell
              } else if k == 0 {
                @sf.share_orange
              } else {
                @sf.share_terminal_ink
              }
              c.box(style=term_cell.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
            }
          })
          |> ignore
          code_words(c, text(q, "usedText"), if k == 0 { term_share_first } else { term_share })
        })
        |> ignore
      })
      |> ignore
    }
    match (field(fleet, "today"), field(fleet, "week")) {
      (Some(Object(_)) as today, Some(Object(_)) as week) => {
        for span in [today, week] {
          c.box(style=term_block, fn() {
            c.rich([@ui.span("[", mono=true), @ui.span(text(span, "title")), @ui.span("]", mono=true)], style=term_section)
            |> ignore
            for x in span_stats(span) {
              c.box(style=pic_other, fn() {
                c.text(x.0, style=term_key) |> ignore
                c.box(style=pic_grow, fn() {  }) |> ignore
                code_words(c, x.1, term_share)
              })
              |> ignore
            }
          })
          |> ignore
        }
        term_days(c, week)
      }
      _ => ()
    }
    c.box(style=term_block, fn() {
      arrow(c, text(fleet, "chatsText"), text(fleet, "where"))
      let tasks = text(fleet, "tasksText")
      if tasks != "" {
        arrow(c, tasks, text(fleet, "tasksPer"))
      }
    })
    |> ignore
    c.box(style=term_block, fn() {
      c.box(style=term_prompt_row, fn() {
        code_words(c, "~ $", term_prompt)
        c.box(style=term_cursor, fn() {  }) |> ignore
      })
      |> ignore
      c.rich([@ui.span("# ", mono=true), @ui.span(@sf.t("web-main.stations.shareTagline"))], style=term_dim) |> ignore
    })
    |> ignore
  })
}

///|
/// The prompt and what is typed after it.
fn prompt(c : @ui.Ctx, command : String) -> Unit {
  c.rich(
    [@ui.span("~ ", mono=true, color=@sf.share_terminal_dim), @ui.span("$ ", mono=true, color=@sf.share_orange), @ui.span(command, mono=true)],
    style=term_line_bold,
  )
  |> ignore
}

///|
/// A line of the answer after an arrow: what it says, the more of it under it, dimmer.
fn arrow(c : @ui.Ctx, words : String, more : String) -> Unit {
  c.box(style=term_arrow_row, fn() {
    code_words(c, "→", term_prompt)
    c.box(style=pic_line_words, fn() {
      c.text(words, style=term_line_bold) |> ignore
      c.text(more, style=term_dim) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Each day's chats archived a column of cells from its foot (one at least), today's the orange, its date under it.
fn term_days(c : @ui.Ctx, week : Json?) -> Unit {
  c.box(style=pic_bars_row, fn() {
    for d in items(week, "days") {
      let d = Some(d)
      let on = flag(d, "today")
      let filled = dmax(1.0, (number(d, "share") * term_day_cells.to_double()).round()).to_int()
      c.box(style=pic_day, fn() {
        c.box(style=term_column, fn() {
          for i in 0..<term_day_cells {
            let lit = term_day_cells - i <= filled
            let ink = if !lit {
              @sf.share_terminal_cell
            } else if on {
              @sf.share_orange
            } else {
              @sf.share_terminal_dim
            }
            c.box(style=term_day_cell.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
          }
        })
        |> ignore
        code_words(c, text(d, "label"), if on { term_day_today } else { term_day })
      })
      |> ignore
    }
  })
  |> ignore
}

// ── the picker's styles ──────────────────────────────────────────────────

///|
/// The looks side by side, 12 apart, in the stage's middle.
// kept across runs: a value (no field of it changes)
let looks_row : @ui.Style = @ui.css("row gap=S3 justify=JCenter")

///|
/// A look: its small picture over its name, 6 apart, as wide as its name or its ring.
// kept across runs: a value (no field of it changes)
let looks_item : @ui.Style = @ui.css("gap=S1_5 align=ACenter")

///|
/// The ring round a small picture: none but the chosen one's (the white), as far out either way.
// kept across runs: a value (no field of it changes)
let looks_ring : @ui.Style = @ui.style(p=@sf.share_look_in, radius=@sf.share_look_ring, border=B1_5, border_color=Clear)

///|
// kept across runs: a value (no field of it changes)
let looks_ring_on : @ui.Style = looks_ring.then(@ui.style(border_color=Data(@sf.share_ink)))

///|
/// Its name: the white thinned, the white chosen or under the hand.
// kept across runs: a value (no field of it changes)
let looks_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let looks_name_on : @ui.TextStyle = looks_name.then(@ui.text_style(color=Data(@sf.share_ink)))

///|
/// A small picture's insides: its dot, its line, its shorter line, 6 in, 4 apart.
// kept across runs: a value (no field of it changes)
let tile_inner : @ui.Style = @ui.css("w=Full p=S1_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tile_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let tile_line : @ui.Style = @ui.css("w=Full h=S1 radius=Sm")

///|
// kept across runs: a value (no field of it changes)
let tile_short : @ui.Style = @ui.css("w=S4 h=S1 radius=Sm")

// ── 大字报's ────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let poster_brand : @ui.TextStyle = pic_brand.then(@ui.text_style(color=Data(@sf.share_poster_ink)))

///|
// kept across runs: a value (no field of it changes)
let poster_at : @ui.TextStyle = pic_at.then(@ui.text_style(color=Data(@sf.share_poster_dim)))

///|
/// What leads its number, the number, what it is of: one under another, tight.
// kept across runs: a value (no field of it changes)
let poster_hero : @ui.Style = @ui.css("w=Full gap=S0_5 pt=S2")

///|
// kept across runs: a value (no field of it changes)
let poster_words : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_poster_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let poster_number : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=Tighter, color=Data(@sf.share_poster_ink), wrap=false)

///|
/// The meters, 10 apart.
// kept across runs: a value (no field of it changes)
let poster_meters : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// A meter: its line over its track, 4 apart.
// kept across runs: a value (no field of it changes)
let poster_meter : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let poster_key_name : @ui.TextStyle = pic_key_name.then(@ui.text_style(weight=Bold, color=Data(@sf.share_poster_ink)))

///|
// kept across runs: a value (no field of it changes)
let poster_key_dim : @ui.TextStyle = pic_key_accounts.then(@ui.text_style(color=Data(@sf.share_poster_dim)))

///|
// kept across runs: a value (no field of it changes)
let poster_key_share : @ui.TextStyle = pic_key_share.then(@ui.text_style(color=Data(@sf.share_poster_ink)))

///|
/// Its track: 10 high, the black thinned; what is filled of it the black.
// kept across runs: a value (no field of it changes)
let poster_track : @ui.Style = @ui.css("row w=Full h=S2_5 radius=Sm clip").then(@ui.style(bg=Data(@sf.share_poster_track)))

///|
// kept across runs: a value (no field of it changes)
let poster_fill : @ui.Style = @ui.css("h=Full radius=Sm").then(@ui.style(bg=Data(@sf.share_poster_ink)))

///|
/// The days' band: the black, 16 in, round as the night's cards; today over the last 7 days over the bars, 12 apart.
// kept across runs: a value (no field of it changes)
let poster_band : @ui.Style = @ui.css("w=Full p=S4 gap=S3 radius=Xl").then(@ui.style(bg=Data(@sf.share_poster_ink)))

///|
// kept across runs: a value (no field of it changes)
let poster_span : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let poster_band_title : @ui.TextStyle = pic_span_title.then(@ui.text_style(color=Data(@sf.share_orange)))

///|
// kept across runs: a value (no field of it changes)
let poster_band_value : @ui.TextStyle = pic_stat_value

///|
// kept across runs: a value (no field of it changes)
let poster_band_label : @ui.TextStyle = pic_stat_label

///|
// kept across runs: a value (no field of it changes)
let poster_line : @ui.TextStyle = pic_line_one.then(@ui.text_style(color=Data(@sf.share_poster_ink)))

///|
// kept across runs: a value (no field of it changes)
let poster_line_bold : @ui.TextStyle = pic_line_lead.then(@ui.text_style(color=Data(@sf.share_poster_ink)))

///|
/// Its foot: still.fail's line large, in the black.
// kept across runs: a value (no field of it changes)
let poster_tagline : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, tracking=Tight, color=Data(@sf.share_poster_ink), w=Full)

// ── 小票's ──────────────────────────────────────────────────────────────────

///|
/// Its head: still.fail over when, in its middle.
// kept across runs: a value (no field of it changes)
let receipt_head : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter pt=S2")

///|
// kept across runs: a value (no field of it changes)
let receipt_brand : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_dim : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_receipt_dim), wrap=false)

///|
/// A group of its items, 4 apart.
// kept across runs: a value (no field of it changes)
let receipt_items : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let receipt_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_ink), w=Cut, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let receipt_line_bold : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let receipt_value : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
/// Its total: large, in the ink.
// kept across runs: a value (no field of it changes)
let receipt_total : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_day : @ui.TextStyle = pic_day_label.then(@ui.text_style(color=Data(@sf.share_receipt_dim)))

///|
// kept across runs: a value (no field of it changes)
let receipt_day_today : @ui.TextStyle = pic_day_label.then(@ui.text_style(color=Data(@sf.share_receipt_orange)))

///|
/// A line of dashes: as many, as wide as the receipt shares them, 4 apart, a point and a half high.
// kept across runs: a value (no field of it changes)
let receipt_dashes : @ui.Style = @ui.css("row w=Full gap=S1")

///|
let receipt_dash_count : Int = 30

///|
// kept across runs: a value (no field of it changes)
let receipt_dash : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_receipt_dash_h, bg=Data(@sf.share_receipt_rule))

///|
/// Two lines of dashes, 3 apart.
// kept across runs: a value (no field of it changes)
let receipt_double : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its foot: the barcode over still.fail's line, in its middle.
// kept across runs: a value (no field of it changes)
let receipt_foot : @ui.Style = @ui.css("w=Full gap=S2 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let receipt_code : @ui.Style = @ui.css("row h=S10 justify=JCenter")

///|
/// At most this many bars (the receipt's width holds them).
let receipt_code_most : Int = 64

///|
// kept across runs: a value (no field of it changes)
let receipt_bar : @ui.Style = @ui.style(h=Full, bg=Data(@sf.share_receipt_ink))

///|
// kept across runs: a value (no field of it changes)
let receipt_tagline : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_receipt_dim), wrap=false)

// ── 终端's ──────────────────────────────────────────────────────────────────

///|
/// Its window's bar: three dots 6 apart, its title in the middle of what is left.
// kept across runs: a value (no field of it changes)
let term_bar : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let term_dot : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full").then(@ui.style(bg=Data(@sf.share_terminal_dot)))

///|
// kept across runs: a value (no field of it changes)
let term_title : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_terminal_dim), center=true, w=Full, wrap=false)

///|
/// A block of its lines, 4 apart (the blocks the card's 12).
// kept across runs: a value (no field of it changes)
let term_block : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let term_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let term_line_bold : @ui.TextStyle = term_line.then(@ui.text_style(weight=Bold))

///|
// kept across runs: a value (no field of it changes)
let term_dim : @ui.TextStyle = term_line.then(@ui.text_style(color=Data(@sf.share_terminal_dim)))

///|
/// What a figure is, before it on its line.
// kept across runs: a value (no field of it changes)
let term_key : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_dim), wrap=false)

///|
/// A span's title, as a section of a config: in the orange.
// kept across runs: a value (no field of it changes)
let term_section : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let term_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_terminal_ink), w=Cut, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let term_prompt : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
/// A meter and its share after it, 8 apart.
// kept across runs: a value (no field of it changes)
let term_meter_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let term_meter : @ui.Style = @ui.css("row gap=S0_5").then(@ui.style(w=@sf.grow))

///|
let term_cells : Int = 20

///|
// kept across runs: a value (no field of it changes)
let term_cell : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_terminal_cell_h)

///|
// kept across runs: a value (no field of it changes)
let term_share : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_terminal_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let term_share_first : @ui.TextStyle = term_share.then(@ui.text_style(color=Data(@sf.share_orange)))

///|
/// A day's column of cells: 8, 2 apart, standing on its foot.
// kept across runs: a value (no field of it changes)
let term_column : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
let term_day_cells : Int = 8

///|
// kept across runs: a value (no field of it changes)
let term_day_cell : @ui.Style = @ui.style(w=Full, h=@sf.share_terminal_day_cell_h)

///|
// kept across runs: a value (no field of it changes)
let term_day : @ui.TextStyle = pic_day_label.then(@ui.text_style(color=Data(@sf.share_terminal_dim)))

///|
// kept across runs: a value (no field of it changes)
let term_day_today : @ui.TextStyle = pic_day_label.then(@ui.text_style(color=Data(@sf.share_orange)))

///|
/// An arrow and its line's words, 8 apart, by their first line.
// kept across runs: a value (no field of it changes)
let term_arrow_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// The prompt at its end: its cursor after it, 6 apart.
// kept across runs: a value (no field of it changes)
let term_prompt_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its cursor: a block of the orange, as a terminal's.
// kept across runs: a value (no field of it changes)
let term_cursor : @ui.Style = @ui.style(w=@sf.share_terminal_cursor_w, h=@sf.share_terminal_cursor_h, bg=Data(@sf.share_orange))
