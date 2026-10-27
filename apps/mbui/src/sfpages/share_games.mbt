// The card to share's game looks (2026-10-27 用户：「平面贵平面，平面也能做骚，比如经典游戏的风格」「整一点经典的东西进去」
// 「比如用 Minecraft 的风格用方块堆砌想要的体素字出来」「搞十个不同类型的」): each the screen of a kind of game everyone
// has played, its number in that game's own type (share_type.mbt), saying of the `fleet` view what that screen would.
// The words games print on their screens (SCORE, HIGH SCORE, INSERT COIN, HP) are part of the picture, in English as
// they are on those screens; what is said of the person's work is in their language.

///|
/// What these looks read of the fleet: the first kind's share (or, none read, the chats at work) and what leads it and
/// what it is of; the chats at work; the week's figures.
priv struct Said {
  first : Json?
  number : String
  lead : String
  of : String
  chats : Int
  chats_text : String
  where_ : String
  tasks : String
  tasks_per : String
  week : Array[(String, String)]
  week_title : String
  today : Array[(String, String)]
  today_title : String
  quota : Array[Json]
  days : Array[Json]
  at : String
}

///|
fn said_of(fleet : Json?) -> Said {
  let quota = items(fleet, "quota")
  let first = if quota.length() > 0 { Some(quota[0]) } else { None }
  let week = field(fleet, "week")
  {
    first,
    number: if first is Some(_) { text(first, "usedText") } else { count(fleet, "chats").to_string() },
    lead: if first is Some(_) { text(first, "lead") } else { "" },
    of: if first is Some(_) { text(first, "of") } else { text(fleet, "chatsText") },
    chats: count(fleet, "chats"),
    chats_text: text(fleet, "chatsText"),
    where_: text(fleet, "where"),
    tasks: text(fleet, "tasksText"),
    tasks_per: text(fleet, "tasksPer"),
    week: span_stats(week),
    week_title: text(week, "title"),
    today: span_stats(field(fleet, "today")),
    today_title: text(field(fleet, "today"), "title"),
    quota,
    days: items(week, "days"),
    at: text(fleet, "at"),
  }
}

///|
/// A figure of the week's (`i`: the chats archived, the tokens, the spend), "" where there is none.
fn week_value(s : Said, i : Int) -> String {
  if i < s.week.length() {
    s.week[i].1
  } else {
    ""
  }
}

// ── 掌机 ───────────────────────────────────────────────────────────────────

///|
/// 掌机: a handheld's green screen, its four greens; the share in its dot matrix, a falling-blocks game's panel beside
/// the well (LEVEL the chats at work, LINES the week's chats archived, the week's spend), each day's chats archived a
/// stack of its blocks in the well; PRESS START, still.fail's line.
fn pocket_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_pocket_ground, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() { code_words(c, "still.fail", pocket_title) }) |> ignore
      code_words(c, s.at, pocket_small)
    })
    |> ignore
    c.box(style=pocket_screen, fn() {
      if s.lead != "" {
        c.text(s.lead, style=pocket_words) |> ignore
      }
      dot_words(c, s.number, @sf.share_dot_cell, @sf.share_dot_gap, @sf.share_pocket_ink) |> ignore
      c.text(s.of, style=pocket_words) |> ignore
    })
    |> ignore
    c.box(style=pocket_play, fn() {
      pocket_well(c, s.days)
      c.box(style=pocket_panel, fn() {
        pocket_stat(c, "LEVEL", s.chats.to_string())
        pocket_stat(c, "LINES", week_value(s, 0))
        pocket_stat(c, "SCORE", week_value(s, 2))
      })
      |> ignore
    })
    |> ignore
    c.box(style=pocket_foot, fn() {
      code_words(c, "PRESS START", pocket_title)
      c.text(@sf.t("web-main.stations.shareTagline"), style=pocket_small_words) |> ignore
    })
    |> ignore
  })
}

///|
/// A line of the panel: what it is over its figure, in a sunk box.
fn pocket_stat(c : @ui.Ctx, key : String, value : String) -> Unit {
  c.box(style=pocket_stat_box, fn() {
    code_words(c, key, pocket_small)
    code_words(c, value, pocket_value)
  })
  |> ignore
}

///|
/// The well: each day a column, its chats archived a stack of blocks from the foot (as tall as its share of the
/// busiest day's: 10 at most, 1 at least), each block the handheld's (its darkest round it, its lightest inside, its
/// middle in the middle).
fn pocket_well(c : @ui.Ctx, days : Array[Json]) -> Unit {
  let cell = @sf.share_pocket_block
  let rows = 10
  let w = 7.0 * cell
  let h = rows.to_double() * cell
  let (outer, light, middle) = (StringBuilder(), StringBuilder(), StringBuilder())
  for i, d in days {
    if i >= 7 {
      break
    }
    let n = dmax(1.0, (number(Some(d), "share") * rows.to_double()).round()).to_int()
    for k in 0..<n {
      let x = i.to_double() * cell
      let y = h - (k + 1).to_double() * cell
      outer.write_string(rect_d(x, y, cell, cell))
      light.write_string(rect_d(x + cell * 0.12, y + cell * 0.12, cell * 0.76, cell * 0.76))
      middle.write_string(rect_d(x + cell * 0.3, y + cell * 0.3, cell * 0.4, cell * 0.4))
    }
  }
  c.box(style=pocket_well_box, fn() {
    @sf.vector(
      c,
      "pocket-well/" + days.map(fn(d) { number(Some(d), "share").to_string() }).join(","),
      {
        w,
        h,
        layers: [
          fill_layer(outer, @sf.share_pocket_ink),
          fill_layer(light, @sf.share_pocket_light),
          fill_layer(middle, @sf.share_pocket_mid),
        ],
      },
      w,
    )
    |> ignore
  })
  |> ignore
}

// ── 方块 ───────────────────────────────────────────────────────────────────

///|
/// 方块: a voxel game's sky, the share stood up in its blocks (grass on dirt), what leads it and what it is of over and
/// under it; the rest said in the game's tooltip (its night and violet rim: the chats at work in white, where in grey,
/// the tasks across devices in yellow, the week's spend in aqua); a row of grass at its foot.
fn blocks_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_blocks_sky, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() { c.text("still.fail", style=blocks_brand) |> ignore }) |> ignore
      c.text(s.at, style=blocks_small) |> ignore
    })
    |> ignore
    if s.lead != "" {
      c.text(s.lead, style=blocks_words) |> ignore
    }
    c.box(style=blocks_hero, fn() {
      block_words(c, s.number, @sf.share_block_cell, @sf.share_block_deep, @sf.share_grass_inks) |> ignore
    })
    |> ignore
    c.text(s.of, style=blocks_words) |> ignore
    c.box(style=blocks_tip, fn() {
      c.box(style=blocks_tip_inner, fn() {
        c.text(s.chats_text, style=blocks_tip_name) |> ignore
        c.text(s.where_, style=blocks_tip_grey) |> ignore
        if s.tasks != "" {
          c.text(s.tasks, style=blocks_tip_gold) |> ignore
        }
        match s.week {
          [.., (label, value)] => c.text(label + " " + value, style=blocks_tip_aqua) |> ignore
          _ => ()
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=blocks_ground, fn() {
      block_row(c, @sf.share_ground_blocks, @sf.share_block_cell * 2.0, @sf.share_block_deep * 2.0, @sf.share_grass_inks)
      |> ignore
    })
    |> ignore
    c.text(@sf.t("web-main.stations.shareTagline"), style=blocks_small) |> ignore
  })
}

// ── 街机 ───────────────────────────────────────────────────────────────────

///|
/// 街机: an arcade's high-score screen: its night; HIGH SCORE over the share in the dot matrix, its
/// shadow under it; the table of the best (each kind of subscription a row: its rank, its share, its name and
/// accounts, each row the next of the screen's colours); the chats at work as the players; INSERT COIN.
fn arcade_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_arcade_ground, fn() {
    c.box(style=arcade_head, fn() {
      code_words(c, "HIGH SCORE", arcade_red)
      dot_words(c, s.number, @sf.share_dot_cell, @sf.share_dot_gap, @sf.share_arcade_white, shade=@sf.share_arcade_shade)
      |> ignore
      if s.lead != "" {
        c.text(s.lead + " " + s.number + " " + s.of, style=arcade_center) |> ignore
      }
    })
    |> ignore
    c.box(style=arcade_table, fn() {
      c.box(style=arcade_row, fn() {
        c.box(style=arcade_rank, fn() { code_words(c, "RANK", arcade_cyan) }) |> ignore
        c.box(style=arcade_score, fn() { code_words(c, "SCORE", arcade_cyan) }) |> ignore
        c.box(style=pic_grow, fn() { code_words(c, "NAME", arcade_cyan) }) |> ignore
      })
      |> ignore
      for k, q in s.quota {
        if k >= 5 {
          break
        }
        let q = Some(q)
        let ink = @sf.share_arcade_rows[k % @sf.share_arcade_rows.length()]
        let style = arcade_cell.then(@ui.text_style(color=Data(ink)))
        let name_style = arcade_name.then(@ui.text_style(color=Data(ink)))
        c.box(style=arcade_row, fn() {
          c.box(style=arcade_rank, fn() { code_words(c, arcade_ranks[k], style) }) |> ignore
          c.box(style=arcade_score, fn() { code_words(c, text(q, "usedText"), style) }) |> ignore
          c.box(style=pic_grow, fn() {
            c.text(text(q, "name") + " ×" + count(q, "accounts").to_string(), style=name_style) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=arcade_foot, fn() {
      c.rich([@ui.span("PLAYERS ", mono=true, color=@sf.share_arcade_yellow), @ui.span(s.chats_text)], style=arcade_center)
      |> ignore
      code_words(c, "INSERT COIN", arcade_coin)
      c.text("© still.fail  ·  " + @sf.t("web-main.stations.shareTagline"), style=arcade_small) |> ignore
    })
    |> ignore
  })
}

///|
/// The ranks of the table.
// kept across runs: a table, never written
let arcade_ranks : Array[String] = ["1ST", "2ND", "3RD", "4TH", "5TH"]

// ── RPG ────────────────────────────────────────────────────────────────────

///|
/// RPG: an old role-playing game's status window: its night, a white double rim round each window; the party's name and
/// level (the chats at work), each kind of subscription a member, its share as HP's bar; GOLD the week's spend; a
/// message window saying what the agents did, its arrow; a menu of what to do next, the arrow at the first.
fn rpg_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_rpg_ground, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() { code_words(c, "still.fail", rpg_title) }) |> ignore
      code_words(c, s.at, rpg_small)
    })
    |> ignore
    rpg_window(c, fn() {
      c.box(style=pic_head, fn() {
        c.box(style=pic_grow, fn() { code_words(c, "AGENTS", rpg_title) }) |> ignore
        code_words(c, "LV \{s.chats}", rpg_gold)
      })
      |> ignore
      for k, q in s.quota {
        if k >= 3 {
          break
        }
        let q = Some(q)
        c.box(style=rpg_member, fn() {
          c.box(style=pic_head, fn() {
            c.box(style=pic_grow, fn() {
              c.text(text(q, "name") + " ×" + count(q, "accounts").to_string(), style=rpg_words) |> ignore
            })
            |> ignore
            code_words(c, "HP " + text(q, "usedText"), rpg_value)
          })
          |> ignore
          let filled : @ui.Len = Pct(dmin(1.0, dmax(0.0, number(q, "share"))) * 100.0)
          c.box(style=rpg_bar, fn() { c.box(style=rpg_fill.then(@ui.style(w=filled)), fn() {  }) |> ignore }) |> ignore
        })
        |> ignore
      }
      c.box(style=pic_head, fn() {
        c.box(style=pic_grow, fn() { code_words(c, "GOLD", rpg_gold) }) |> ignore
        code_words(c, week_value(s, 2), rpg_value)
      })
      |> ignore
    })
    rpg_window(c, fn() {
      if s.lead != "" {
        c.text("▶ " + s.lead + " " + s.number + " " + s.of + "！", style=rpg_words) |> ignore
      }
      if s.tasks != "" {
        c.text("▶ " + s.tasks + "！", style=rpg_words) |> ignore
      }
      c.text("▶ " + s.chats_text + "……", style=rpg_words) |> ignore
    })
    rpg_window(c, fn() {
      c.box(style=rpg_menu, fn() {
        code_words(c, "▶ FIGHT", rpg_title)
        code_words(c, "ITEM", rpg_value)
        code_words(c, "MAGIC", rpg_value)
        code_words(c, "RUN", rpg_value)
      })
      |> ignore
    })
    c.text(@sf.t("web-main.stations.shareTagline"), style=rpg_small_words) |> ignore
  })
}

///|
/// A window of the game: the white rim, the night, the white again, what it holds in it.
fn rpg_window(c : @ui.Ctx, inner : () -> Unit) -> Unit {
  c.box(style=rpg_rim, fn() { c.box(style=rpg_inside, inner) |> ignore }) |> ignore
}

// ── 扫雷 ───────────────────────────────────────────────────────────────────

///|
/// 扫雷: a window of the old desktop: its blue title bar (still.fail.exe), its grey raised and sunk edges; the counter's
/// red seven segments for the share, the face that won between counters, the time's counter the chats at work; a field
/// of squares opened (each day's chats archived its figure, in the game's colours); what was said under it.
fn mines_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_mines_desk, fn() {
    c.text("still.fail", style=mines_desk_words) |> ignore
    raised(c, fn() {
      c.box(style=mines_title, fn() {
        c.box(style=pic_grow, fn() { c.text("still.fail.exe", style=mines_title_words) |> ignore }) |> ignore
        c.text("_ □ ×", style=mines_title_words) |> ignore
      })
      |> ignore
      c.box(style=mines_menu, fn() {
        c.text("Game", style=mines_menu_words) |> ignore
        c.text("Help", style=mines_menu_words) |> ignore
      })
      |> ignore
      sunk(c, fn() {
        c.box(style=mines_counters, fn() {
          c.box(style=mines_led, fn() {
            segment_figures(c, s.number, @sf.share_segment_h, @sf.share_led_on, @sf.share_led_off, count=3) |> ignore
          })
          |> ignore
          c.box(style=mines_face_box, fn() { raised(c, fn() { c.own_colours(c.text("😎", style=mines_face)) }) }) |> ignore
          c.box(style=mines_led, fn() {
            segment_figures(c, s.chats.to_string(), @sf.share_segment_h, @sf.share_led_on, @sf.share_led_off, count=3)
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      sunk(c, fn() {
        c.box(style=mines_field, fn() {
          for i, d in s.days {
            if i >= 7 {
              break
            }
            let n = digits_of(text(Some(d), "value"))
            let ink = @sf.share_mines_figures[(n - 1).abs() % @sf.share_mines_figures.length()]
            c.box(style=mines_square, fn() {
              c.text(n.to_string(), style=mines_figure.then(@ui.text_style(color=Data(ink)))) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      c.box(style=mines_said, fn() {
        if s.lead != "" {
          c.text(s.lead + " " + s.number + " " + s.of, style=mines_words) |> ignore
        }
        c.text(s.chats_text + "  ·  " + s.where_, style=mines_words) |> ignore
      })
      |> ignore
    })
    c.text(@sf.t("web-main.stations.shareTagline"), style=mines_desk_words) |> ignore
  })
}

///|
/// The number at the head of `words` (5 of 5 个), 0 with none.
fn digits_of(words : String) -> Int {
  let mut n = 0
  for ch in words {
    if ch >= '0' && ch <= '9' {
      n = n * 10 + (ch.to_int() - '0'.to_int())
    } else if n > 0 {
      break
    }
  }
  n
}

///|
/// The old desktop's raised edge: white over and left, its shadow's grey under and right, the grey inside.
fn raised(c : @ui.Ctx, inner : () -> Unit) -> Unit {
  c.box(style=bevel_dark_after, fn() {
    c.box(style=bevel_light_before, fn() { c.box(style=bevel_face, inner) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// Its sunk edge: the shadow's grey over and left, white under and right.
fn sunk(c : @ui.Ctx, inner : () -> Unit) -> Unit {
  c.box(style=bevel_light_after, fn() {
    c.box(style=bevel_dark_before, fn() { c.box(style=bevel_face, inner) |> ignore }) |> ignore
  })
  |> ignore
}

// ── 成就 ───────────────────────────────────────────────────────────────────

///|
/// 成就: a console's achievement come up: its night and its trophy's gold; ACHIEVEMENT UNLOCKED over what was done
/// (what leads the share, the share, what it is of), its score the week's spend; under it the rest unlocked so far,
/// each a line with its mark (the tasks across devices, the chats at work, the week's chats archived).
fn trophy_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let s = said_of(fleet)
  look_box(c, id, flat, @sf.share_trophy_ground, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() { c.text("still.fail", style=trophy_brand) |> ignore }) |> ignore
      c.text(s.at, style=trophy_small) |> ignore
    })
    |> ignore
    c.box(style=trophy_toast, fn() {
      // (the emoji in their own colours, as a picture's)
      c.box(style=trophy_medal, fn() { c.own_colours(c.text("🏆", style=trophy_cup)) }) |> ignore
      c.box(style=trophy_words_box, fn() {
        c.text(@sf.t("web-main.stations.shareAchievement"), style=trophy_gold) |> ignore
        c.text(if s.lead != "" { s.lead + " " + s.number + " " + s.of } else { s.number + " " + s.of }, style=trophy_words)
        |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=trophy_hero, fn() {
      dot_words(c, s.number, @sf.share_dot_cell, @sf.share_dot_gap, @sf.share_trophy_gold) |> ignore
      code_words(c, "G " + week_value(s, 2), trophy_score)
    })
    |> ignore
    c.box(style=trophy_list, fn() {
      if s.tasks != "" {
        trophy_line(c, "🔗", s.tasks)
      }
      trophy_line(c, "⚡", s.chats_text)
      if s.week.length() > 0 {
        trophy_line(c, "📦", s.week[0].0 + " " + s.week[0].1)
      }
    })
    |> ignore
    c.text(@sf.t("web-main.stations.shareTagline"), style=trophy_small) |> ignore
  })
}

///|
/// An achievement under it: its mark, what it is.
fn trophy_line(c : @ui.Ctx, mark : String, words : String) -> Unit {
  c.box(style=trophy_row, fn() {
    c.box(style=trophy_mark, fn() { c.own_colours(c.text(mark, style=trophy_mark_words)) }) |> ignore
    c.text(words, style=trophy_words) |> ignore
  })
  |> ignore
}

// ── 掌机's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let pocket_title : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_pocket_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pocket_small : @ui.TextStyle = @ui.text_style(size=Xs, weight=Bold, color=Data(@sf.share_pocket_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pocket_small_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_pocket_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pocket_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_pocket_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pocket_value : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_pocket_ink), wrap=false)

///|
/// The screen: its lighter green inside the darkest's rim, 16 in, its lines 8 apart.
// kept across runs: a value (no field of it changes)
let pocket_screen : @ui.Style = @ui.css("w=Full p=S4 gap=S2 border=B2").then(
  @ui.style(bg=Data(@sf.share_pocket_light), border_color=Data(@sf.share_pocket_ink)),
)

///|
/// The well and its panel side by side, 12 apart, standing on their foot.
// kept across runs: a value (no field of it changes)
let pocket_play : @ui.Style = @ui.css("row w=Full gap=S3 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let pocket_well_box : @ui.Style = @ui.css("p=S1 border=B2").then(@ui.style(border_color=Data(@sf.share_pocket_ink)))

///|
// kept across runs: a value (no field of it changes)
let pocket_panel : @ui.Style = @ui.css("gap=S2").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let pocket_stat_box : @ui.Style = @ui.css("w=Full p=S2 gap=S0_5 border=B2").then(
  @ui.style(bg=Data(@sf.share_pocket_light), border_color=Data(@sf.share_pocket_ink)),
)

///|
// kept across runs: a value (no field of it changes)
let pocket_foot : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter")

// ── 方块's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let blocks_brand : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_blocks_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let blocks_small : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_blocks_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let blocks_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_blocks_ink), w=Full)

///|
/// The share's blocks, in the middle, room over and under them.
// kept across runs: a value (no field of it changes)
let blocks_hero : @ui.Style = @ui.css("w=Full align=ACenter py=S2")

///|
/// The tooltip: its violet rim round its night, 2 thick, 12 in.
// kept across runs: a value (no field of it changes)
let blocks_tip : @ui.Style = @ui.css("w=Full p=S0_5").then(@ui.style(bg=Data(@sf.share_tip_rim)))

///|
// kept across runs: a value (no field of it changes)
let blocks_tip_inner : @ui.Style = @ui.css("w=Full p=S3 gap=S1").then(@ui.style(bg=Data(@sf.share_tip_ground)))

///|
// kept across runs: a value (no field of it changes)
let blocks_tip_name : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let blocks_tip_grey : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_tip_grey), w=Full)

///|
// kept across runs: a value (no field of it changes)
let blocks_tip_gold : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_tip_gold), w=Full)

///|
// kept across runs: a value (no field of it changes)
let blocks_tip_aqua : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_tip_aqua), w=Full)

///|
/// A row of grass at its foot.
// kept across runs: a value (no field of it changes)
let blocks_ground : @ui.Style = @ui.css("w=Full align=ACenter")

// ── 街机's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let arcade_head : @ui.Style = @ui.css("w=Full gap=S3 align=ACenter pt=S2")

///|
// kept across runs: a value (no field of it changes)
let arcade_red : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_arcade_red), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let arcade_cyan : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_arcade_cyan), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let arcade_center : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_arcade_white), center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let arcade_small : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_arcade_dim), center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let arcade_coin : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_arcade_yellow), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let arcade_cell : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let arcade_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, w=Cut, wrap=false)

///|
/// The table: its rows 8 apart.
// kept across runs: a value (no field of it changes)
let arcade_table : @ui.Style = @ui.css("w=Full gap=S2 py=S2")

///|
// kept across runs: a value (no field of it changes)
let arcade_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let arcade_rank : @ui.Style = @ui.style(w=@sf.share_arcade_rank_w)

///|
// kept across runs: a value (no field of it changes)
let arcade_score : @ui.Style = @ui.style(w=@sf.share_arcade_score_w)

///|
// kept across runs: a value (no field of it changes)
let arcade_foot : @ui.Style = @ui.css("w=Full gap=S2 align=ACenter")

// ── RPG's ──────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let rpg_title : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rpg_gold : @ui.TextStyle = @ui.text_style(size=Base, weight=Bold, color=Data(@sf.share_rpg_gold), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rpg_value : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rpg_small : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_rpg_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rpg_small_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_rpg_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let rpg_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_white), w=Full)

///|
/// A window: the white rim 2 thick, 2 of the night inside it, then the white's second line, 12 in.
// kept across runs: a value (no field of it changes)
let rpg_rim : @ui.Style = @ui.css("w=Full p=S0_5 border=B2 radius=Lg").then(
  @ui.style(border_color=Data(@sf.share_white), bg=Data(@sf.share_rpg_ground)),
)

///|
// kept across runs: a value (no field of it changes)
let rpg_inside : @ui.Style = @ui.css("w=Full p=S3 gap=S2 border=B1 radius=Md").then(@ui.style(border_color=Data(@sf.share_white)))

///|
// kept across runs: a value (no field of it changes)
let rpg_member : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// HP's bar: its track the white thinned, filled the green.
// kept across runs: a value (no field of it changes)
let rpg_bar : @ui.Style = @ui.css("row w=Full h=S2 clip").then(@ui.style(bg=Data(@sf.share_rpg_track)))

///|
// kept across runs: a value (no field of it changes)
let rpg_fill : @ui.Style = @ui.css("h=Full").then(@ui.style(bg=Data(@sf.share_rpg_hp)))

///|
// kept across runs: a value (no field of it changes)
let rpg_menu : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter")

// ── 扫雷's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let mines_desk_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let mines_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_black), w=Full)

///|
// kept across runs: a value (no field of it changes)
let mines_menu_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_black), wrap=false)

///|
/// The face's button: as wide as the face.
// kept across runs: a value (no field of it changes)
let mines_face_box : @ui.Style = @ui.css("w=S12")

///|
// kept across runs: a value (no field of it changes)
let mines_title_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mines_face : @ui.TextStyle = @ui.text_style(size=Xl2, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mines_figure : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, center=true, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mines_title : @ui.Style = @ui.css("row w=Full px=S1_5 py=S1 gap=S2 align=ACenter").then(
  @ui.style(bg=Data(@sf.share_mines_title)),
)

///|
// kept across runs: a value (no field of it changes)
let mines_menu : @ui.Style = @ui.css("row w=Full px=S1_5 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let mines_counters : @ui.Style = @ui.css("row w=Full p=S1_5 justify=JBetween align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let mines_led : @ui.Style = @ui.css("p=S1").then(@ui.style(bg=Data(@sf.share_black)))

///|
// kept across runs: a value (no field of it changes)
let mines_field : @ui.Style = @ui.css("row w=Full p=S1 gap=S0_5")

///|
/// An opened square: the grey a hairline darker round it, its figure in the middle.
// kept across runs: a value (no field of it changes)
let mines_square : @ui.Style = @ui.css("h=S10 border=B0_5 align=ACenter justify=JCenter").then(
  @ui.style(w=@sf.grow, border_color=Data(@sf.share_bevel_dark)),
)

///|
// kept across runs: a value (no field of it changes)
let mines_said : @ui.Style = @ui.css("w=Full p=S1_5 gap=S1")

///|
/// The edges: the darker or the lighter round 2 of two sides, the grey's face inside.
// kept across runs: a value (no field of it changes)
let bevel_dark_after : @ui.Style = @ui.css("w=Full pr=S0_5 pb=S0_5").then(@ui.style(bg=Data(@sf.share_bevel_dark)))

///|
// kept across runs: a value (no field of it changes)
let bevel_light_before : @ui.Style = @ui.css("w=Full pl=S0_5 pt=S0_5").then(@ui.style(bg=Data(@sf.share_white)))

///|
// kept across runs: a value (no field of it changes)
let bevel_light_after : @ui.Style = @ui.css("w=Full pr=S0_5 pb=S0_5").then(@ui.style(bg=Data(@sf.share_white)))

///|
// kept across runs: a value (no field of it changes)
let bevel_dark_before : @ui.Style = @ui.css("w=Full pl=S0_5 pt=S0_5").then(@ui.style(bg=Data(@sf.share_bevel_dark)))

///|
// kept across runs: a value (no field of it changes)
let bevel_face : @ui.Style = @ui.css("w=Full p=S0_5 gap=S1").then(@ui.style(bg=Data(@sf.share_bevel_face)))

// ── 成就's ─────────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let trophy_brand : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_white), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let trophy_small : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_trophy_dim), w=Full)

///|
// kept across runs: a value (no field of it changes)
let trophy_gold : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_trophy_gold), w=Full)

///|
// kept across runs: a value (no field of it changes)
let trophy_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_white), w=Full)

///|
// kept across runs: a value (no field of it changes)
let trophy_cup : @ui.TextStyle = @ui.text_style(size=Xl2, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let trophy_score : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_trophy_gold), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let trophy_mark_words : @ui.TextStyle = @ui.text_style(size=Base, wrap=false)

///|
/// The achievement come up: a capsule of the darker night, the trophy at its start.
// kept across runs: a value (no field of it changes)
let trophy_toast : @ui.Style = @ui.css("row w=Full p=S2 gap=S3 align=ACenter radius=Full").then(
  @ui.style(bg=Data(@sf.share_trophy_toast)),
)

///|
// kept across runs: a value (no field of it changes)
let trophy_medal : @ui.Style = @ui.css("w=S12 h=S12 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let trophy_words_box : @ui.Style = @ui.css("gap=S0_5").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let trophy_hero : @ui.Style = @ui.css("w=Full gap=S3 align=ACenter py=S3")

///|
// kept across runs: a value (no field of it changes)
let trophy_list : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let trophy_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let trophy_mark : @ui.Style = @ui.css("w=S8 h=S8 align=ACenter justify=JCenter")
