// The card to share of the workspace's agents at work (2026-10-26 用户：「需要有一个地方可以显示当前多少个 chat 正在工作，
// 有利于 app 传播」「hover 这个出一个卡片」「有个复制图片应该就行」), opened from the rail's Station place's card
// (rail_cards.mbt) and the Station page's first card. The card to share: a
// picture of the agents at work on the person's stations, copied whole to paste where others see it (a chat, a post):
// a poster (the `fleet` view): the subscriptions' weekly quota used as rings, today and the last 7 days, the chats at
// work now, still.fail's line (no QR code: 2026-10-26 用户「不用放 still fail 的二维码」); 复制图片 under it puts what is
// drawn of it on the clipboard.

// ── the card to share ────────────────────────────────────────────────────

///|
/// The card to share of workspace `w`'s agents at work, opened by nothing (a dialog; a sheet to a finger): the picture
/// (share_picture), under it 复制图片, or on a phone (iOS, Android) 保存到相册: a phone keeps pictures in its photo
/// album, where a post or a chat picks them from (2026-10-26 用户：「手机上能复制图片吗？」「是不是应该是下载」「保存」).
pub fn share_card_open(src : Source, w : Workspace) -> Unit {
  @sf.panel(
    @sf.t("web-main.stations.shareCard"),
    fn(c, _) { share_picture(c, src, w) },
    from=Unanchored,
    // (a dialog as wide as one of two columns wants: the poster lies its stations three a line in it)
    wide=true,
    // (its title said as it is drawn, in the language then)
    live=fn() { (@sf.t("web-main.stations.shareCard"), "", "") },
    foot=fn(c, _) {
      let (label, icon) = picture_out_way()
      if @sf.button(c, label, key="share-card/copy", tone=Primary, icon~) {
        let picture = c.id(share_picture_key)
        // (once the frame's builds are over: the picture as the last frame drew it, read back by the host's renderer)
        c.tell("share-card/copy", fn() {
          match c.drawn_pixels(picture, inset=pic_copy_in) {
            @ui.PixelsRead(pw, ph, rgba) => picture_out(c, Some(@pixels.png(pw, ph, unpremultiplied(rgba))))
            _ => picture_out(c, None)
          }
        })
      }
    },
  )
}

///|
/// The picture's key: what is copied is what was drawn of it.
let share_picture_key : String = "share-card/picture"

///|
/// The picture shared, a poster of what the agents did (the `fleet` view; 2026-10-26 用户：「改成 xx 个 xx 订阅账号的 xx% 周额度，
/// 分天和周统计，还有当前 chat 数量」「不要小机器人」「这玩意儿是会超过 100% 的」「不如归档 chat 多少个」): on warm paper with a
/// peach light on it, the same in either theme. still.fail's mark and name and when it is; the subscriptions' weekly
/// quota used as rings, a kind each (Activity's rings: each the share of all its accounts' weeks, 489% of six 0.815 of
/// it; 「489% 就是 4.89 个号的周额度」), beside them the first kind's said round its share large (用 6 个 Claude 订阅账号
/// 消耗了 | 489% | 的周额度), each other kind a line under it; today and the last 7 days side by side (the chats
/// archived, what was spent), each day's chats archived a bar under them (today's orange, each day's date under its
/// bar); the chats at work now, a dot before them, and the tasks agents ran across devices over the 7 days (how many,
/// how many a chat on average), the devices' icon before them; still.fail's line. With no quota read: the chats at
/// work large in its place. Laid out narrower than pic_narrow_most (a phone's sheet): what leads the share over the
/// rings, the rings and the number smaller, today over the last 7 days, the lines smaller, all closer.
fn share_picture(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let fleet = (src.topic)("fleet", { "scope": Json::string(w.id) }).value
  let quota = items(fleet, "quota")
  let picture = c.id(share_picture_key)
  // (as wide as it is laid out; the window's width until it is)
  let narrow = match c.laid_size(picture) {
    Some((pw, _)) if pw > 0.0 => pw < pic_narrow_most
    _ => c.width < pic_narrow_most
  }
  c.box(style=if narrow { pic_box_narrow } else { pic_box }, id=picture, fn() {
    c.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
      @sf.glow_ground(c, @sf.share_paper, pic_lights, pic_aspect, radius=pic_corner)
    })
    |> ignore
    c.box(style=pic_head, fn() {
      @sf.drawable(c, "stillfail_mark", pic_mark) |> ignore
      c.box(style=pic_grow, fn() {
        c.rich([@ui.span("still"), @ui.span(".fail", color=@sf.share_orange_ink)], style=pic_brand) |> ignore
      })
      |> ignore
      c.text(text(fleet, "at"), style=pic_at) |> ignore
    })
    |> ignore
    if quota.length() > 0 {
      // the first kind's said round its share, a sentence read down (用 6 个 Claude 订阅账号消耗了 | 489% | 的周额度:
      // 2026-10-26 用户「你要么这么说"是用 x 个账号消耗了 xxx% 的周额度"」), what leads it over the rings and the share
      // in a narrow picture (beside them it has no room there)
      let first = Some(quota[0])
      if narrow {
        c.text(text(first, "lead"), style=pic_unit) |> ignore
      }
      c.box(style=pic_hero, fn() {
        pic_rings(c, quota, narrow)
        c.box(style=pic_hero_words, fn() {
          if !narrow {
            c.text(text(first, "lead"), style=pic_unit) |> ignore
          }
          // (in its ring's colour; smaller in a narrow picture, as wide as 489% is beside the rings there)
          let color = ring_color(0)
          let number = if narrow { pic_number_narrow } else { pic_number }
          c.text(text(first, "usedText"), style=number.then(@ui.text_style(color=Data(color)))) |> ignore
          c.text(text(first, "of"), style=pic_unit) |> ignore
          if !narrow {
            pic_other_kinds(c, quota)
          }
        })
        |> ignore
      })
      |> ignore
      if narrow {
        pic_other_kinds(c, quota)
      }
    } else {
      c.box(style=pic_hero, fn() {
        c.text(count(fleet, "chats").to_string(), style=pic_number.then(@ui.text_style(color=Data(@sf.share_orange)))) |> ignore
        c.box(style=pic_hero_words, fn() { c.text(text(fleet, "chatsText"), style=pic_unit) |> ignore }) |> ignore
      })
      |> ignore
    }
    match (field(fleet, "today"), field(fleet, "week")) {
      (Some(Object(_)) as today, Some(Object(_)) as week) => {
        c.box(style=if narrow { pic_spans_narrow } else { pic_spans }, fn() {
          pic_span(c, today)
          pic_span(c, week)
        })
        |> ignore
        pic_bars(c, week, narrow)
      }
      _ => ()
    }
    // the chats at work now (with the quota large: said here), the tasks chats ran on other stations over the week
    let tasks = text(fleet, "tasksText")
    if quota.length() > 0 || tasks != "" {
      c.box(style=pic_lines, fn() {
        if quota.length() > 0 {
          pic_line(c, fn() { c.box(style=pic_live_dot, fn() {  }) |> ignore }, text(fleet, "chatsText"), text(fleet, "where"), narrow, false)
        }
        if tasks != "" {
          pic_line(c, fn() { @sf.icon(c, "devices", size=pic_mark_side, color=@sf.share_ink) |> ignore }, tasks, text(fleet, "tasksPer"), narrow, narrow)
        }
      })
      |> ignore
    }
    c.text(@sf.t("web-main.stations.shareTagline"), style=pic_tagline) |> ignore
  })
  |> ignore
}

///|
/// A line under the days: its mark (in a square of its own, the lines' words starting together), what it says, and
/// more of it after a dot, dimmer; in a narrow picture smaller, and `apart`, the more under it (a line as long as the
/// tasks' is broken inside a word there: 「…312 个任」「务」).
fn pic_line(c : @ui.Ctx, mark : () -> Unit, words : String, more : String, narrow : Bool, apart : Bool) -> Unit {
  c.box(style=if apart { pic_live_narrow } else { pic_live }, fn() {
    c.box(style=pic_mark_box, mark) |> ignore
    if apart {
      c.box(style=pic_line_words, fn() {
        c.text(words, style=pic_line_lead) |> ignore
        c.text(more, style=pic_line_more) |> ignore
      })
      |> ignore
    } else {
      c.rich([@ui.span(words, weight=700), @ui.span("  ·  " + more, color=@sf.share_dim)], style=if narrow {
        pic_line_narrow
      } else {
        pic_live_words
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The colour of the ring of kind `k` (in the quota's order), the last one's past them.
fn ring_color(k : Int) -> Int64 {
  @sf.share_rings[if k < @sf.share_rings.length() { k } else { @sf.share_rings.length() - 1 }]
}

///|
/// Each kind but the first, a line: its colour's dot, the same sentence round its share (用 2 个 ChatGPT 订阅账号消耗了
/// 17% 的周额度), the share in ink.
fn pic_other_kinds(c : @ui.Ctx, quota : Array[Json]) -> Unit {
  if quota.length() < 2 {
    return
  }
  c.box(style=@sf.full_width, fn() {
    for k, q in quota {
      if k == 0 {
        continue
      }
      let q = Some(q)
      c.box(style=pic_other, fn() {
        c.box(style=pic_key_dot.then(@ui.style(bg=Data(ring_color(k)))), fn() {  }) |> ignore
        c.rich(
          [
            @ui.span(text(q, "lead") + " ", color=@sf.share_dim),
            @ui.span(text(q, "usedText"), weight=700),
            @ui.span(" " + text(q, "of"), color=@sf.share_dim),
          ],
          style=pic_other_words,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The rings: a kind of subscription each, from the outside in (as many as there are colours), as much of each drawn as
/// its accounts' weeks used (the core's `share`: @sf.rings); smaller in a narrow picture.
fn pic_rings(c : @ui.Ctx, quota : Array[Json], narrow : Bool) -> Unit {
  let rings : Array[(Double, Int64)] = []
  for k, q in quota {
    if k >= @sf.share_rings.length() {
      break
    }
    rings.push((number(Some(q), "share"), ring_color(k)))
  }
  @sf.rings(c, rings, if narrow { pic_rings_side_narrow } else { pic_rings_side }, pic_ring_w, pic_ring_gap, pic_track_alpha)
  |> ignore
}

///|
/// A span of days (today, the last 7) on a white card: its title, then each figure over what it is.
fn pic_span(c : @ui.Ctx, span : Json?) -> Unit {
  c.box(style=pic_span_box, fn() {
    c.text(text(span, "title"), style=pic_span_title) |> ignore
    c.box(style=pic_stats, fn() {
      for x in items(span, "stats") {
        let x = Some(x)
        c.box(style=pic_stat, fn() {
          c.text(text(x, "value"), style=pic_stat_value) |> ignore
          c.text(text(x, "label"), style=pic_stat_label) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Each day's chats archived a bar, as tall as its share of the most on a day (4 at least: a day with none still seen), today's
/// orange, its date under it; closer in a narrow picture.
fn pic_bars(c : @ui.Ctx, week : Json?, narrow : Bool) -> Unit {
  c.box(style=if narrow { pic_bars_row_narrow } else { pic_bars_row }, fn() {
    for d in items(week, "days") {
      let d = Some(d)
      let h = dmax(pic_bar_least, number(d, "share") * pic_bars_h)
      let today = flag(d, "today")
      c.box(style=pic_day, fn() {
        c.box(style=pic_bar_room, fn() {
          c.box(style=pic_bar.then(@ui.style(h=Fixed(h), bg=Data(if today { @sf.share_orange } else { @sf.share_bar }))), fn() {  })
          |> ignore
        })
        |> ignore
        c.text(text(d, "label"), style=if today { pic_day_today } else { pic_day_label }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The picture: 28 in (past its corner: what is at its edges stands clear of it), its parts 16 apart, round as a card,
/// on warm paper (what is drawn on it seen against that), its light over it clipped to it.
// kept across runs: a value (no field of it changes)
let pic_box : @ui.Style = @ui.css("w=Full p=S7 gap=S4 radius=Xl3 clip").then(@ui.style(bg=Data(@sf.share_paper)))

///|
/// Narrower than this (as laid out: a phone's sheet, 350 or so), the picture is laid out narrow: what is beside the
/// rings, and today's and the last 7 days' figures side by side, need about this much.
let pic_narrow_most : Double = 520.0

///|
/// A narrow one: 20 in (nothing at its corners but words: the corners' rule asks nothing of them), its parts 12 apart.
// kept across runs: a value (no field of it changes)
let pic_box_narrow : @ui.Style = @ui.css("w=Full p=S5 gap=S3 radius=Xl3 clip").then(@ui.style(bg=Data(@sf.share_paper)))

///|
/// Its corner (Xl3's), its light's picture's.
let pic_corner : Double = 24.0

///|
/// What is copied of the picture: its rectangle this far in from each side, its round corners (24) left out of it, so
/// the picture copied is its ground to its edges.
let pic_copy_in : Double = 8.0

///|
/// The light's picture made in a poster's proportion (4 by 5), stretched over the picture whatever it holds.
let pic_aspect : Double = 0.8

///|
/// A peach light at its top right, a warm sun's at its foot left.
// kept across runs: a table, never written
let pic_lights : Array[@sf.Glow] = [
  { x: 0.95, y: 0.05, r: 0.9, color: @sf.share_glow_peach },
  { x: 0.05, y: 1.0, r: 0.8, color: @sf.share_glow_sun },
]

///|
// kept across runs: a value (no field of it changes)
let pic_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
let pic_mark : Double = 22.0

///|
// kept across runs: a value (no field of it changes)
let pic_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let pic_brand : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_at : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_dim), wrap=false)

///|
/// The rings and their words beside them, in the middle of each other's height.
// kept across runs: a value (no field of it changes)
let pic_hero : @ui.Style = @ui.css("row w=Full gap=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pic_hero_words : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=@sf.grow))

///|
/// The rings: 128 across, each 12 wide, 4 apart; their tracks the colour at 30%.
let pic_rings_side : Double = 128.0

///|
/// A narrow picture's: 88 across, as tall as the share and what it is of beside them.
let pic_rings_side_narrow : Double = 88.0

///|
let pic_ring_w : Double = 12.0

///|
let pic_ring_gap : Double = 4.0

///|
let pic_track_alpha : Int64 = 0x4DL


///|
/// The number, as large as a picture's one number is (the scale's past its words', Xl7 72), drawn tight.
// kept across runs: a value (no field of it changes)
let pic_number : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=Tight, color=Data(@sf.share_ink), wrap=false)

///|
/// A narrow picture's: Xl6 (60).
// kept across runs: a value (no field of it changes)
let pic_number_narrow : @ui.TextStyle = pic_number.then(@ui.text_style(size=Xl6))

///|
// kept across runs: a value (no field of it changes)
let pic_unit : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Data(@sf.share_ink), w=Full)

///|
/// Another kind's line.
// kept across runs: a value (no field of it changes)
let pic_other : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let pic_key_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let pic_other_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_ink), w=Full)

///|
/// Today and the last 7 days, side by side, 10 apart.
// kept across runs: a value (no field of it changes)
let pic_spans : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStretch")

///|
/// A narrow picture's: one over the other, each as wide as the picture.
// kept across runs: a value (no field of it changes)
let pic_spans_narrow : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStretch")

///|
/// A span: a white card, 12 in, round, raised a little; its title over its figures.
// kept across runs: a value (no field of it changes)
let pic_span_box : @ui.Style = @ui.css("p=S3 gap=S2 radius=Xl shadow=Sm").then(@ui.style(w=@sf.grow, bg=Data(@sf.share_card)))

///|
// kept across runs: a value (no field of it changes)
let pic_span_title : @ui.TextStyle = @ui.text_style(size=Caption, weight=Medium, color=Data(@sf.share_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_stats : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let pic_stat : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_value : @ui.TextStyle = @ui.text_style(size=Ui, weight=Bold, color=Data(@sf.share_ink), wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_label : @ui.TextStyle = @ui.text_style(size=Caption, color=Data(@sf.share_dim), wrap=false, w=Cut)

///|
/// The days' bars side by side, 8 apart, each its date under it.
// kept across runs: a value (no field of it changes)
let pic_bars_row : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A narrow picture's, 6 apart: each date as wide as it is under its bar.
// kept across runs: a value (no field of it changes)
let pic_bars_row_narrow : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pic_day : @ui.Style = @ui.style(w=@sf.grow, gap=S1, align=ACenter)

///|
/// A bar's room: as tall as the busiest day's, its bar standing on its foot.
// kept across runs: a value (no field of it changes)
let pic_bar_room : @ui.Style = @ui.css("w=Full justify=JEnd").then(@ui.style(h=Fixed(pic_bars_h)))

///|
let pic_bars_h : Double = 40.0

///|
let pic_bar_least : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let pic_bar : @ui.Style = @ui.css("w=Full radius=Sm")

///|
// kept across runs: a value (no field of it changes)
let pic_day_label : @ui.TextStyle = @ui.text_style(size=Caption, color=Data(@sf.share_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_day_today : @ui.TextStyle = @ui.text_style(size=Caption, weight=Bold, color=Data(@sf.share_orange_ink), wrap=false)

///|
/// The lines under the days (the chats at work, the tasks run across devices), 8 apart.
// kept across runs: a value (no field of it changes)
let pic_lines : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// A line: its mark, what it says.
// kept across runs: a value (no field of it changes)
let pic_live : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// A narrow picture's: its mark by its first line.
// kept across runs: a value (no field of it changes)
let pic_live_narrow : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// A narrow picture's words: what it says over the more of it, Meta's (13).
// kept across runs: a value (no field of it changes)
let pic_line_words : @ui.Style = @ui.css("gap=S0_5").then(@ui.style(w=@sf.grow))

///|
/// A narrow picture's line on one line, Meta's (13).
// kept across runs: a value (no field of it changes)
let pic_line_narrow : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pic_line_lead : @ui.TextStyle = @ui.text_style(size=Meta, weight=Bold, color=Data(@sf.share_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pic_line_more : @ui.TextStyle = @ui.text_style(size=Meta, color=Data(@sf.share_dim), w=Full)

///|
/// A line's mark: a dot (the chats at work), the devices' icon (the tasks across devices), in a square 16 across.
// kept across runs: a value (no field of it changes)
let pic_mark_box : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
let pic_mark_side : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let pic_live_dot : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full").then(@ui.style(bg=Data(@sf.share_orange)))

///|
// kept across runs: a value (no field of it changes)
let pic_live_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Data(@sf.share_ink), w=Full)

///|
/// Its foot: still.fail's line.
// kept across runs: a value (no field of it changes)
let pic_tagline : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Data(@sf.share_ink), wrap=false)
