// The card to share of the workspace's agents at work (2026-10-26 用户：「需要有一个地方可以显示当前多少个 chat 正在工作，
// 有利于 app 传播」「hover 这个出一个卡片」「有个复制图片应该就行」), opened from the rail's Station place's card
// (rail_cards.mbt) and the Station page's first card. The card to share: a
// picture of the agents at work on the person's stations, copied whole to paste where others see it (a chat, a post):
// a poster (the `fleet` view): the tokens each kind of account used as rings, today and the last 7 days, the chats at
// work now, still.fail's line (no QR code: 2026-10-26 用户「不用放 still fail 的二维码」); 复制图片 under it puts it on the
// clipboard, drawn apart as sharp on any screen (Ctx::take_shot at share_scale).

// ── the card to share ────────────────────────────────────────────────────

///|
/// The card to share of workspace `w`'s agents at work, opened by nothing, on a stage of its own on every screen (a
/// panel's `stage`: the picture alone in the window's middle over the night, no dialog round it: 2026-10-26 用户「分享的
/// 弹窗有点丑，感觉应该给分享特制一个逼格高点的」): the picture (share_picture), under it 关闭 and 复制图片, or on a phone
/// (iOS, Android) 保存到相册: a phone keeps pictures in its photo album, where a post or a chat picks them from
/// (2026-10-26 用户：「手机上能复制图片吗？」「是不是应该是下载」「保存」).
pub fn share_card_open(src : Source, w : Workspace) -> Unit {
  @sf.panel(
    @sf.t("web-main.stations.shareCard"),
    fn(c, _) {
      share_picture(c, src, w)
      // what is handed out: the same poster drawn apart, all of it, its ground to its edges (Ctx::shot)
      c.shot(share_shot, @sf.share_w_most, fn() { share_poster(c, src, w, 0, flat=true) |> ignore })
    },
    from=Unanchored,
    // (as large as the picture while the window has the room; past it, the picture drawn smaller: @sf.whole_fitted)
    stage=true,
    // the looks it can be drawn in, over its buttons (share_looks.mbt)
    above=fn(c) { share_looks_pick(c, src) },
    // (its title said as it is drawn, in the language then)
    live=fn() { (@sf.t("web-main.stations.shareCard"), "", "") },
    foot=fn(c, _) {
      let (label, icon) = @sf.picture_out_way()
      if @sf.button(c, label, key="share-card/copy", tone=Primary, icon~) {
        c.take_shot(share_shot, fn(png) { picture_out(c, png) |> ignore }, scale=share_scale)
      }
    },
  )
}

///|
/// The picture's key, as the panel fits it in.
let share_picture_key : String = "share-card/picture"

///|
/// The picture handed out (Ctx::shot).
let share_shot : String = "share-card/shot"

///|
/// How many pixels a point the picture handed out has, whatever the screen it is shared from (1080 across): as sharp
/// from a screen of one pixel a point as from a phone's three (2026-10-26 用户「现在做」, of the picture as sharp
/// everywhere).
let share_scale : Double = 3.0

///|
/// The picture shared, a poster of what the agents did (the `fleet` view; 2026-10-26 用户：「改成 xx 个 xx 订阅账号的 xx% 周额度，
/// 分天和周统计，还有当前 chat 数量」「不要小机器人」「这玩意儿是会超过 100% 的」「不如归档 chat 多少个」): on night, the same in
/// either theme (@sf.share_ground: 「分享卡片的颜色搞高级点」), and laid out one way whatever it is seen on (a portrait poster
/// @sf.share_w_most wide: 「分享图片不应该分电脑和手机…按最合理的布局生成」), seen whole in the panel, drawn smaller where the
/// window has not the room for it (@sf.whole_fitted): what is copied is all of it, as it is laid out everywhere. Read down: still.fail's name (its dot orange) and when it is; what leads the first kind's share (用 6 个 Claude
/// 订阅账号消耗了, its ring's dot before it); the tokens each kind of account used over the 7 days as rings, a kind each
/// (Activity's rings: each its share of all kinds' tokens; 2026-10-29 用户「只算 token 和价格」, where it was a week's
/// quota), beside them the first kind's first model's tokens large, the model and what they would cost (2.1 亿 | Opus 5.5 |
/// token，折合 $1,420); each other model a line with its own, each other kind a line over its models (no kind's models
/// added up: 2026-10-30 用户「按模型分开写 token 和钱」); today over the last 7 days (the
/// chats archived, what was spent), each day's chats archived a bar under them (today's orange, each day's date under
/// its bar); the chats at work now, a dot before them, and the tasks agents ran across devices over the 7 days (how
/// many, and under it how many a chat on average), the devices' icon before them; still.fail's line. With nothing
/// used: the chats at work large in its place.
fn share_picture(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  @sf.whole_fitted(c, share_picture_key, c.id(share_picture_key), @sf.share_w_most, fn(whole) {
    share_poster(c, src, w, whole)
  })
}

///|
/// The poster (share_picture) as box `id`: round as a card, or `flat` (handed out: its ground to its edges), in the look
/// chosen under it (share_look: the night's here, the others' share_looks.mbt).
fn share_poster(c : @ui.Ctx, src : Source, w : Workspace, id : Int, flat? : Bool = false) -> Int {
  let fleet = (src.topic)("fleet", { "scope": Json::string(w.id) }).value
  match share_look(src) {
    "poster" => poster_look(c, fleet, id, flat)
    "receipt" => receipt_look(c, fleet, id, flat)
    "terminal" => terminal_look(c, fleet, id, flat)
    _ => night_look(c, fleet, id, flat)
  }
}

///|
/// The night's look: still.fail's own colours, the kinds' tokens as rings.
fn night_look(c : @ui.Ctx, fleet : Json?, id : Int, flat : Bool) -> Int {
  let spent = items(fleet, "spent")
  c.box(style=if flat { pic_box_flat } else { pic_box }, id~, fn() {
    c.box(style=pic_head, fn() {
      c.box(style=pic_grow, fn() {
        c.rich([@ui.span("still"), @ui.span(".", color=@sf.share_orange), @ui.span("fail")], style=pic_brand) |> ignore
      })
      |> ignore
      c.text(text(fleet, "at"), style=pic_at) |> ignore
    })
    |> ignore
    if spent.length() > 0 {
      // the first kind's said round its first model's tokens, a sentence read down (用 6 个 Claude 订阅账号消耗了 | 2.1 亿 |
      // Opus 5.5 | token，折合 $1,420: 2026-10-26 用户「你要么这么说"是用 x 个账号消耗了 xxx% 的周额度"」, then 「只算 token 和价格」), what leads
      // it over the rings and the tokens
      let first = Some(spent[0])
      let top = items(first, "models").get(0)
      pic_lead(c, first)
      c.box(style=pic_hero, fn() {
        pic_rings(c, spent)
        c.box(style=pic_hero_words, fn() {
          c.text(text(top, "tokensText"), style=pic_number) |> ignore
          // (the model a line of its own: with what they would cost after it, a line too long beside the rings)
          c.text(text(top, "name"), style=pic_unit) |> ignore
          c.text(text(top, "of"), style=pic_unit) |> ignore
        })
        |> ignore
      })
      |> ignore
      pic_models(c, spent)
    } else {
      c.box(style=pic_hero, fn() {
        c.text(count(fleet, "chats").to_string(), style=pic_number) |> ignore
        c.box(style=pic_hero_words, fn() { c.text(text(fleet, "chatsText"), style=pic_unit) |> ignore }) |> ignore
      })
      |> ignore
    }
    match (field(fleet, "today"), field(fleet, "week")) {
      (Some(Object(_)) as today, Some(Object(_)) as week) => {
        c.box(style=pic_spans, fn() {
          pic_span(c, today)
          pic_span(c, week)
        })
        |> ignore
        pic_bars(c, week)
      }
      _ => ()
    }
    // the chats at work now (with the tokens large: said here), the tasks chats ran on other stations over the week
    let tasks = text(fleet, "tasksText")
    if spent.length() > 0 || tasks != "" {
      c.box(style=pic_lines, fn() {
        if spent.length() > 0 {
          pic_line(c, fn() { c.box(style=pic_live_dot, fn() {  }) |> ignore }, text(fleet, "chatsText"), text(fleet, "where"), false)
        }
        if tasks != "" {
          pic_line(c, fn() { @sf.icon(c, "devices", size=pic_mark_side, color=@sf.share_ink) |> ignore }, tasks, text(fleet, "tasksPer"), true)
        }
      })
      |> ignore
    }
    c.text(@sf.t("web-main.stations.shareTagline"), style=pic_tagline) |> ignore
  })
}

///|
/// A line under the days: its mark (in a square of its own, the lines' words starting together), what it says, and
/// more of it after a dot, dimmer; `apart`, the more under it (a line as long as the tasks' is broken inside a word on
/// one line: 「…312 个任」「务」).
fn pic_line(c : @ui.Ctx, mark : () -> Unit, words : String, more : String, apart : Bool) -> Unit {
  c.box(style=if apart { pic_live_apart } else { pic_live }, fn() {
    c.box(style=pic_mark_box, mark) |> ignore
    if apart {
      c.box(style=pic_line_words, fn() {
        c.text(words, style=pic_line_lead) |> ignore
        c.text(more, style=pic_line_more) |> ignore
      })
      |> ignore
    } else {
      c.rich([@ui.span(words, weight=700), @ui.span("  ·  " + more, color=@sf.share_dim)], style=pic_line_one)
      |> ignore
    }
  })
  |> ignore
}

///|
/// The colour of the ring of kind `k` (in the core's order), the last one's past them.
fn ring_color(k : Int) -> Int64 {
  @sf.share_rings[if k < @sf.share_rings.length() { k } else { @sf.share_rings.length() - 1 }]
}

///|
/// What leads the first kind's share (用 6 个 Claude 订阅账号消耗了), its ring's dot before it as each other kind's line has
/// (the share under it in white, as the second ring is: the dot says whose it is).
fn pic_lead(c : @ui.Ctx, first : Json?) -> Unit {
  c.box(style=pic_lead_row, fn() {
    c.box(style=pic_lead_dot, fn() {  }) |> ignore
    c.text(text(first, "lead"), style=pic_unit) |> ignore
  })
  |> ignore
}

///|
/// The models but the one said large, one line each (its name, its tokens and cost at the line's end in ink), past where
/// the dots are: the first kind's under it; then each other kind a line as its ring's key (its colour's dot, its name,
/// its accounts dimmer), its models under it. One model's tokens are not another's, so no kind adds its models' up
/// (2026-10-30 用户「按模型分开写 token 和钱」). One line each whatever its name: said as a sentence, a name long enough
/// broke it, a character on a line of its own (2026-10-26 用户：「这里折行了不太好看」); a name too long for its line cut
/// short, nothing else.
fn pic_models(c : @ui.Ctx, spent : Array[Json]) -> Unit {
  if spent.length() < 2 && items(Some(spent[0]), "models").length() < 2 {
    return
  }
  c.box(style=pic_models_box, fn() {
    for k, q in spent {
      let q = Some(q)
      if k > 0 {
        c.box(style=pic_other, fn() {
          c.box(style=pic_key_dot.then(@ui.style(bg=Data(ring_color(k)))), fn() {  }) |> ignore
          c.text(text(q, "name"), style=pic_key_name) |> ignore
          c.text(text(q, "accountsText"), style=pic_key_accounts) |> ignore
        })
        |> ignore
      }
      for i, m in items(q, "models") {
        if k == 0 && i == 0 {
          continue
        }
        let m = Some(m)
        c.box(style=pic_model, fn() {
          c.box(style=pic_key_dot, fn() {  }) |> ignore
          c.text(text(m, "name"), style=pic_key_name) |> ignore
          c.box(style=pic_grow, fn() {  }) |> ignore
          c.text(text(m, "lineText"), style=pic_key_share) |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// The rings: a kind of account each, from the outside in (as many as there are colours), as much of each drawn as its
/// share of all kinds' tokens (the core's `share`: @sf.rings).
fn pic_rings(c : @ui.Ctx, spent : Array[Json]) -> Unit {
  let rings : Array[(Double, Int64)] = []
  for k, q in spent {
    if k >= @sf.share_rings.length() {
      break
    }
    rings.push((number(Some(q), "share"), ring_color(k)))
  }
  @sf.rings(c, rings, pic_rings_side, pic_track_alpha, most=@sf.share_rings.length())
  |> ignore
}

///|
/// A span of days (today, the last 7) on a card: its title, then each figure over what it is.
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
/// orange, its date under it.
fn pic_bars(c : @ui.Ctx, week : Json?) -> Unit {
  c.box(style=pic_bars_row, fn() {
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
/// The picture: as wide as @sf.whole_fitted lays it out (@sf.share_w_most), 20 in (nothing at its corners but words: the
/// corners' rule asks nothing of them), its parts 12 apart, round as a card, on night (what is drawn on it seen against
/// that), its edge a hairline (@sf.stage_edge: on the stage's night, where it ends).
// kept across runs: a value (no field of it changes)
let pic_box : @ui.Style = @ui.css("w=Full p=S5 gap=S3 radius=Xl3 clip border=B1").then(
  @ui.style(bg=Data(@sf.share_ground), border_color=Data(@sf.stage_edge)),
)

///|
/// The picture handed out: its ground to its edges.
// kept across runs: a value (no field of it changes)
let pic_box_flat : @ui.Style = pic_box.then(@ui.css("radius=Sharp border=B0"))

///|
// kept across runs: a value (no field of it changes)
let pic_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pic_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let pic_brand : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_at : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_dim), wrap=false)

///|
/// The rings and their words beside them, in the middle of each other's height.
// kept across runs: a value (no field of it changes)
let pic_hero : @ui.Style = @ui.css("row w=Full gap=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pic_hero_words : @ui.Style = @ui.css("gap=S1").then(@ui.style(w=@sf.grow))

///|
/// The rings: 88 across, as tall as the share and what it is of beside them, the room for every kind's (each 10 wide, 2
/// apart, the hole 10 round: @sf.rings); their tracks the colour at 22%, as seen on the night.
let pic_rings_side : Double = 88.0

///|
let pic_track_alpha : Int64 = 0x38L

///|
/// The number, as large as a picture's one number is (the scale's past its words', Xl6 60: 170% beside the rings too),
/// drawn tight.
// kept across runs: a value (no field of it changes)
let pic_number : @ui.TextStyle = @ui.text_style(size=Xl6, weight=Bold, tracking=Tight, color=Data(@sf.share_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_unit : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Data(@sf.share_ink), w=Full)

///|
/// The first kind's lead: its dot, its words.
// kept across runs: a value (no field of it changes)
let pic_lead_row : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// Its dot, the first ring's colour (@sf.share_rings' first is the orange).
// kept across runs: a value (no field of it changes)
let pic_lead_dot : @ui.Style = pic_key_dot.then(@ui.style(bg=Data(@sf.share_orange)))

///|
/// Another kind's line.
// kept across runs: a value (no field of it changes)
let pic_other : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let pic_key_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
/// A key's name, cut short where its line has not the room for it; its accounts after it, dimmer; its share in ink.
// kept across runs: a value (no field of it changes)
let pic_key_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_ink), w=Cut, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_key_accounts : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_dim), wrap=false)

///|
/// The models' lines, one under another (a kind's line further from those over it: pic_other's top).
// kept across runs: a value (no field of it changes)
let pic_models_box : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// A model's line, where its kind's name starts (past a dot's room).
// kept across runs: a value (no field of it changes)
let pic_model : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pic_key_share : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_ink), wrap=false)

///|
/// Today over the last 7 days, 10 apart, each as wide as the picture.
// kept across runs: a value (no field of it changes)
let pic_spans : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStretch")

///|
/// A span: a card of the white barely, 12 in, round; its title over its figures.
// kept across runs: a value (no field of it changes)
let pic_span_box : @ui.Style = @ui.css("p=S3 gap=S2 radius=Xl").then(@ui.style(w=@sf.grow, bg=Data(@sf.share_card)))

///|
// kept across runs: a value (no field of it changes)
let pic_span_title : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Data(@sf.share_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pic_stats : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let pic_stat : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_value : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Data(@sf.share_ink), wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pic_stat_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_dim), wrap=false, w=Cut)

///|
/// The days' bars side by side, 6 apart, each its date under it, as wide as it is.
// kept across runs: a value (no field of it changes)
let pic_bars_row : @ui.Style = @ui.css("row w=Full gap=S1_5")

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
let pic_day_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_dim), wrap=false)

///|
/// Today's date: in the orange, as heavy as the others (bold, 10/26 was wider than a 360 phone's day: 「10/…」).
// kept across runs: a value (no field of it changes)
let pic_day_today : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_orange), wrap=false)

///|
/// The lines under the days (the chats at work, the tasks run across devices), 8 apart.
// kept across runs: a value (no field of it changes)
let pic_lines : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// A line: its mark, what it says.
// kept across runs: a value (no field of it changes)
let pic_live : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// A line with the more under it: its mark by its first line.
// kept across runs: a value (no field of it changes)
let pic_live_apart : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// Its words: what it says over the more of it, Meta's (13).
// kept across runs: a value (no field of it changes)
let pic_line_words : @ui.Style = @ui.css("gap=S0_5").then(@ui.style(w=@sf.grow))

///|
/// A line on one line, Meta's (13).
// kept across runs: a value (no field of it changes)
let pic_line_one : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pic_line_lead : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let pic_line_more : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_dim), w=Full)

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
/// Its foot: still.fail's line, said quietly (the white thinned).
// kept across runs: a value (no field of it changes)
let pic_tagline : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Data(@sf.share_dim), wrap=false)
