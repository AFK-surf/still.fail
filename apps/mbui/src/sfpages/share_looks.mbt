// The looks the card to share can be drawn in (2026-10-27 用户：「再搞几版骚气的分享图片模板，让用户可以选择」「结构不用都
// 一致，信息甚至都不用一样」「为视觉服务」), chosen under it on its stage (share_looks_pick), the choice kept on the device
// (the prefs' `shareLook`). Each is its own picture, saying of the `fleet` view what serves it, as it serves it: the
// night (stations_now.mbt night_look, all of it), 大字报 (one number as large as the picture holds, still.fail's orange
// to its edges, a line under it), 小票 (a till's receipt: each day a line of the chats archived, the week's spend its
// total, a barcode) and 终端 (a fetch run in a terminal: still.fail's mark beside who it is, a line a figure, the
// palette). Each 360 wide as it is (@sf.share_w_most), nothing cut short, the same in either theme, as a poster is. The
// code face only for what a till or a terminal prints in it (figures, dates, keys, the command): words of Chinese in
// it stand a cell apart (「9  个对话」), so what is said is in the face of words.

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
    "terminal" => (@sf.share_terminal_ground, @sf.share_orange, @sf.share_terminal_dim, @sf.share_terminal_dim)
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
/// 大字报: one number, as large as the picture holds, on still.fail's orange to its edges, in the night's black: what
/// leads the first kind's share over it, what it is of under it; then the chats at work now, large, and where; still.fail
/// large at its foot (what is passed on says whose it is), its line beside the time. Nothing used: the chats at work
/// are its number, the tasks across devices its line.
fn poster_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let spent = items(fleet, "spent")
  look_box(c, id, flat, @sf.share_poster_ground, fn() {
    c.box(style=poster_inner, fn() {
      c.box(style=poster_hero, fn() {
        if spent.length() > 0 {
          let first = Some(spent[0])
          let used = text(first, "tokensText")
          let scale = if used.length() > 4 { @sf.share_poster_number_less } else { @sf.share_poster_number_scale }
          c.text(text(first, "lead"), style=poster_words) |> ignore
          c.rich([@ui.span(used, scale~)], style=poster_number) |> ignore
          c.text(text(first, "of"), style=poster_words) |> ignore
          if text(first, "modelsText") != "" {
            c.text(text(first, "modelsText"), style=poster_small) |> ignore
          }
        } else {
          c.rich([@ui.span(count(fleet, "chats").to_string(), scale=@sf.share_poster_number_scale)], style=poster_number)
          |> ignore
          c.text(text(fleet, "chatsText"), style=poster_words) |> ignore
        }
      })
      |> ignore
      c.box(style=poster_more, fn() {
        if spent.length() > 0 {
          c.text(text(fleet, "chatsText"), style=poster_big) |> ignore
          c.text(text(fleet, "where"), style=poster_small) |> ignore
        } else if text(fleet, "tasksText") != "" {
          c.text(text(fleet, "tasksText"), style=poster_big) |> ignore
          c.text(text(fleet, "tasksPer"), style=poster_small) |> ignore
        }
      })
      |> ignore
      // (the foot at the picture's foot, however tall what is over it)
      c.box(style=poster_rest, fn() {  }) |> ignore
      c.box(style=poster_foot, fn() {
        c.text("still.fail", style=poster_brand) |> ignore
        c.box(style=pic_head, fn() {
          c.box(style=pic_grow, fn() { c.text(@sf.t("web-main.stations.shareTagline"), style=poster_small) |> ignore })
          |> ignore
          c.text(text(fleet, "at"), style=poster_small) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

// ── 小票 ───────────────────────────────────────────────────────────────────

///|
/// 小票: a till's receipt of the agents' week, on its paper. Read down: still.fail and when, in its middle; each day a
/// line, its chats archived at its end (today's date in the orange); the chats archived and the tokens read as its
/// subtotals; each kind of account a line (its accounts, its tokens and cost); between double dashes the week's spend,
/// large, its total; a barcode made of what it says, still.fail's line under it.
fn receipt_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let spent = items(fleet, "spent")
  let week = field(fleet, "week")
  let stats = span_stats(week)
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
    let days = items(week, "days")
    if days.length() > 0 {
      c.box(style=receipt_items, fn() {
        for d in days {
          let d = Some(d)
          c.box(style=pic_other, fn() {
            code_words(c, text(d, "label"), if flag(d, "today") { receipt_today } else { receipt_code_line })
            c.box(style=pic_grow, fn() {  }) |> ignore
            code_words(c, text(d, "value"), receipt_value)
          })
          |> ignore
        }
      })
      |> ignore
      dashes(c)
    }
    // the subtotals: the week's figures but its spend (its total)
    if stats.length() > 1 {
      c.box(style=receipt_items, fn() {
        for x in stats[:stats.length() - 1] {
          receipt_item(c, x.0, x.1, true)
        }
      })
      |> ignore
    }
    if spent.length() > 0 {
      c.box(style=receipt_items, fn() {
        for q in spent {
          let q = Some(q)
          receipt_item(c, text(q, "name") + " ×" + count(q, "accounts").to_string(), text(q, "lineText"), false)
          if text(q, "modelsText") != "" {
            c.text(text(q, "modelsText"), style=receipt_models) |> ignore
          }
        }
      })
      |> ignore
    }
    match stats {
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
/// An item of the receipt: what it is (`strong`: in the ink, else dimmer), its figure at the line's end.
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
/// 终端: still.fail fetched in a terminal, as a system's fetch says what it runs on. Its window's dots and title; the
/// command; still.fail's mark large (its white face, the terminal being dark) beside who and when; a line a figure, its key in the code
/// face in the orange: each kind's tokens, the chats at work, the devices, the tasks across devices, the week's chats
/// archived, tokens and spend; the palette; the prompt again, its cursor.
fn terminal_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let spent = items(fleet, "spent")
  let stats = span_stats(field(fleet, "week"))
  look_box(c, id, flat, @sf.share_terminal_ground, fn() {
    c.box(style=term_bar, fn() {
      for _ in 0..<3 {
        c.box(style=term_dot, fn() {  }) |> ignore
      }
      c.box(style=pic_grow, fn() { code_words(c, "still.fail — zsh", term_title) }) |> ignore
    })
    |> ignore
    prompt(c, "still.fail fetch")
    c.box(style=term_who, fn() {
      @sf.drawable(c, "stillfail_mark_dark", term_mark) |> ignore
      c.box(style=term_who_words, fn() {
        c.rich(
          [@ui.span("agents", mono=true, color=@sf.share_orange), @ui.span("@", mono=true), @ui.span("still.fail", mono=true, color=@sf.share_orange)],
          style=term_line_bold,
        )
        |> ignore
        c.box(style=term_rule, fn() {  }) |> ignore
        code_words(c, text(fleet, "at"), term_dim)
      })
      |> ignore
    })
    |> ignore
    c.box(style=term_block, fn() {
      for k, q in spent {
        let q = Some(q)
        // (its tokens and cost under it, as the tasks' average under them: on its line a long name was cut short)
        term_key_line(c, if k == 0 { "accounts" } else { "" }, text(q, "name") + " ×" + count(q, "accounts").to_string(), "")
        term_key_line(c, "", text(q, "lineText"), "")
        if text(q, "modelsText") != "" {
          term_key_line(c, "", text(q, "modelsText"), "")
        }
      }
      term_key_line(c, "chats", text(fleet, "chatsText"), "")
      term_key_line(c, "devices", text(fleet, "where"), "")
      if text(fleet, "tasksText") != "" {
        term_key_line(c, "tasks", text(fleet, "tasksText"), "")
        term_key_line(c, "", text(fleet, "tasksPer"), "")
      }
      for i, x in stats {
        if i < term_week_keys.length() {
          term_key_line(c, term_week_keys[i], x.1, "")
        }
      }
    })
    |> ignore
    c.box(style=term_palette, fn() {
      for ink in @sf.share_terminal_palette {
        c.box(style=term_swatch.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
      }
    })
    |> ignore
    c.box(style=term_prompt_row, fn() {
      code_words(c, "~ $", term_prompt)
      c.box(style=term_cursor, fn() {  }) |> ignore
    })
    |> ignore
  })
}

///|
/// The keys of the week's figures, in their order (the chats archived, the tokens read, what was spent).
// kept across runs: a table, never written
let term_week_keys : Array[String] = ["archived", "tokens", "spent"]

///|
/// A line of the fetch: its key in the orange in a column of its own ("" none: the line goes on the one before), what
/// it is, and after it `more` in the ink's weight.
fn term_key_line(c : @ui.Ctx, key : String, words : String, more : String) -> Unit {
  c.box(style=term_key_row, fn() {
    c.box(style=term_key_box, fn() { code_words(c, key, term_key) }) |> ignore
    c.box(style=term_value_box, fn() {
      c.text(words, style=term_value) |> ignore
      if more != "" {
        code_words(c, more, term_more)
      }
    })
    |> ignore
  })
  |> ignore
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
/// Its parts far apart (40), the number's group, the line's, the foot's; as tall as a portrait's three to four.
// kept across runs: a value (no field of it changes)
let poster_inner : @ui.Style = @ui.css("w=Full gap=S10 py=S3").then(@ui.style(min_h=@sf.share_poster_least_h))

///|
/// What is left of its height, between the line and the foot.
// kept across runs: a value (no field of it changes)
let poster_rest : @ui.Style = @ui.style(h=@sf.grow)

///|
/// What leads its number, the number, what it is of: one under another, tight.
// kept across runs: a value (no field of it changes)
let poster_hero : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let poster_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_poster_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let poster_number : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=Tighter, color=Data(@sf.share_poster_ink), wrap=false)

///|
/// The line under the number: what it says large, where under it.
// kept across runs: a value (no field of it changes)
let poster_more : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let poster_big : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=Tight, color=Data(@sf.share_poster_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let poster_small : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_poster_dim), w=Full)

///|
/// Its foot: still.fail large over its line and the time.
// kept across runs: a value (no field of it changes)
let poster_foot : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let poster_brand : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Tighter, color=Data(@sf.share_poster_ink), wrap=false)

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
let receipt_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_dim), w=Cut, wrap=false)

///|
/// A kind's models under its line, smaller, cut short past it.
// kept across runs: a value (no field of it changes)
let receipt_models : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_receipt_dim), w=Cut, wrap=false)

///|
/// A day's date (today's in the orange).
// kept across runs: a value (no field of it changes)
let receipt_code_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_today : @ui.TextStyle = receipt_code_line.then(@ui.text_style(weight=Bold, color=Data(@sf.share_receipt_orange)))

///|
// kept across runs: a value (no field of it changes)
let receipt_value : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
/// Its total: large, in the ink.
// kept across runs: a value (no field of it changes)
let receipt_total : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
/// A line of dashes: as many, as wide as the receipt shares them, 4 apart.
// kept across runs: a value (no field of it changes)
let receipt_dashes : @ui.Style = @ui.css("row w=Full gap=S1")

///|
let receipt_dash_count : Int = 30

///|
// kept across runs: a value (no field of it changes)
let receipt_dash : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_receipt_dash_h, bg=Data(@sf.share_receipt_rule))

///|
/// Two lines of dashes, 2 apart.
// kept across runs: a value (no field of it changes)
let receipt_double : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its foot: the barcode over still.fail's line, in its middle.
// kept across runs: a value (no field of it changes)
let receipt_foot : @ui.Style = @ui.css("w=Full gap=S2 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let receipt_code : @ui.Style = @ui.css("row h=S12 justify=JCenter")

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
/// Its window's bar: three dots 6 apart, its title after them.
// kept across runs: a value (no field of it changes)
let term_bar : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let term_dot : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full").then(@ui.style(bg=Data(@sf.share_terminal_dot)))

///|
// kept across runs: a value (no field of it changes)
let term_title : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_terminal_dim), wrap=false)

///|
/// still.fail's mark beside who and when, 16 apart, in the middle of each other's height.
// kept across runs: a value (no field of it changes)
let term_who : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter py=S2")

///|
/// The mark: still.fail's own face (design/brand), as tall as the who and when beside it with room to spare.
let term_mark : Double = 56.0

///|
// kept across runs: a value (no field of it changes)
let term_who_words : @ui.Style = @ui.css("gap=S1_5").then(@ui.style(w=@sf.grow))

///|
/// The rule under who it is, as a fetch draws it: the grey thinned.
// kept across runs: a value (no field of it changes)
let term_rule : @ui.Style = @ui.style(w=Full, h=@sf.share_receipt_dash_h, bg=Data(@sf.share_terminal_cell))

///|
/// Its lines, 6 apart.
// kept across runs: a value (no field of it changes)
let term_block : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let term_line_bold : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_terminal_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let term_dim : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_dim), w=Full)

///|
/// A line: its key's column, what it is beside it, by their first lines.
// kept across runs: a value (no field of it changes)
let term_key_row : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let term_key_box : @ui.Style = @ui.style(w=@sf.share_terminal_key_w)

///|
// kept across runs: a value (no field of it changes)
let term_key : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
/// What it is, and its more after it, 8 apart, taking the rest of the line.
// kept across runs: a value (no field of it changes)
let term_value_box : @ui.Style = @ui.css("row gap=S2 align=ACenter").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let term_value : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_ink), w=Cut, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let term_more : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_terminal_ink), wrap=false)

///|
/// The palette: its colours side by side, as wide as the line shares them, 16 high.
// kept across runs: a value (no field of it changes)
let term_palette : @ui.Style = @ui.css("row w=Full pt=S2")

///|
// kept across runs: a value (no field of it changes)
let term_swatch : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_terminal_cursor_h)

///|
// kept across runs: a value (no field of it changes)
let term_prompt : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
/// The prompt at its end: its cursor after it, 6 apart.
// kept across runs: a value (no field of it changes)
let term_prompt_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its cursor: a block of the orange, as a terminal's.
// kept across runs: a value (no field of it changes)
let term_cursor : @ui.Style = @ui.style(w=@sf.share_terminal_cursor_w, h=@sf.share_terminal_cursor_h, bg=Data(@sf.share_orange))
