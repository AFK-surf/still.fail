// 千恋＊万花's looks of the card to share (2026-11-02 用户：「在 still.fail 的 token 使用分享界面做几个千恋万花主题的」「需要有
// 巧思，有意思一点」「做 20 种吧…可爱的风格、体现美丽女角色的风格、各女主角为主的风格等等，都要有」「有几个要融入 ciallo 的梗」
// 「要体现出是那种真的老吃家的老玩家感觉，很懂这个游戏」, then of the 34 drawn 「都做进去就行了」): fan looks of 柚子社's visual
// novel《千恋＊万花》(2016), offered after still.fail's own in the looks' strip (share_looks). Each says the `fleet` view
// in the game's things and its heroines' voices (the week's chats archived a fortune slip's number, the top model's
// tokens a sword's length, the chats at work an inn's guests tonight), over a picture drawn for it: still.fail's own,
// never the game's art, kept on still.fail's site and had through the core (senren_art_file), the card handed out once they are here. Each look is
// its own function, in the file of its kind (share_senren_*.mbt), and a line of share_looks; what they share is here.

///|
/// A look's picture `art` as a file of the looks (@sfbase.looks_file: had from still.fail's site through the core, kept
/// on the device), each drawing under its number (a file had is never had again: a picture drawn anew goes under the
/// next); while the look is drawn small (the looks' strip, senren_small), its small one, a quarter as wide.
fn senren_art_file(art : String) -> String {
  senren_drawn.to_string() + "/" + art + (if senren_small.val { ".small.webp" } else { ".webp" })
}

///|
/// The pictures a look drew as it was drawn last (senren_drawing), by file (senren_art_file): those it waits for.
// kept across runs: set only while a look is drawn (senren_drawing), and put back
let senren_drew : Ref[Array[String]?] = Ref(None)

///|
/// `draw` as it draws a look, and the files of the looks it needs (its pictures as it drew them: senren_drew; the
/// whole share face's), each asked of the core the first time (@sfbase.looks_file), given as a picture once here.
fn senren_drawing(src : Source, draw : () -> Int) -> (Int, Array[String]) {
  let was = senren_drew.val
  let drew : Array[String] = []
  senren_drew.val = Some(drew)
  let b = draw()
  senren_drew.val = was
  let files : Array[String] = []
  for file in drew {
    if !files.contains(file) {
      files.push(file)
      @sfbase.looks_file(src, file, fn(bytes) { @ui.add_image(senren_art_key(file), bytes) }) |> ignore
    }
  }
  (b, files)
}

///|
/// The key a file of the looks' pictures is shown by, once it is here (`mem:`: nothing until then).
fn senren_art_key(file : String) -> String {
  "mem:share-looks/" + file
}

///|
/// Which drawing of the pictures (and of the face the looks' words are in: @sfbase.share_face_whole) is had
/// (web/public/share-looks/<n>/).
let senren_drawn : Int = 1

///|
/// What each of these looks' keys starts with.
let senren_prefix : String = "senren-"

///|
/// Whether the look being drawn is drawn small, in the looks' strip (sr_box as box 0: share_looks.mbt look_tile): its
/// pictures had small, not thirty of them whole for tiles 72 wide.
// kept across runs: set only while a look is drawn small, and put back
let senren_small : Ref[Bool] = Ref(false)

///|
/// A line of share_looks for 千恋＊万花's look `key`, drawn by `draw`, its picture `art`. On the stage and handed out, the
/// card said to be a picture (Role Image), named by its look and its figures: what it draws is the game's things in
/// their own corners, grounds and inks, a drawing of something else, not the theme's (the corners', gaps' and
/// contrast's rules leave it to itself, as they leave 终端's palette). Drawn small in the looks' strip (look_tile:
/// look_tile_now), its picture alone as the card's top, small: not thirty cards laid out and drawn each frame for tiles
/// 72 wide.
fn senren(key : String, art : String, draw : (@ui.Ctx, Json?, Int, Bool) -> Int) -> ShareLook {
  {
    key,
    group: "senren",
    draw: fn(c, fleet, id, flat) {
      // (its tile in the strip: what is handed out, box 0 too (share_card_open's shot), is the card)
      if look_tile_now.val {
        let was = senren_small.val
        senren_small.val = true
        let b = sr_box(c, id, true, senren_tile_ground, fn() {
          sr_art(c, art, @sf.share_w_most, senren_tile_h, at=0.0) |> ignore
        })
        senren_small.val = was
        return b
      }
      let b = draw(c, fleet, id, flat)
      let args = sr_args(fleet)
      args.push(("name", @sf.t("web-main.stations.shareLook." + key)))
      c.semantics(b, Image, label=sr_plain("web-main.stations.shareSenren.picture", args))
      b
    },
  }
}

///|
/// A look's tile's ground, under its picture while it is on its way.
let senren_tile_ground : Int64 = 0x1B1430FFL

///|
/// How tall a look's picture is drawn for its tile: as tall as the tile shows of a card 360 wide (72 by 96).
let senren_tile_h : Double = 480.0

///|
/// A 穗织画报 cover's look (sr_gahou, one drawing over each heroine's table) as a line of share_looks draws it.
fn sr_gahou_of(look : String) -> (@ui.Ctx, Json?, Int, Bool) -> Int {
  fn(c, fleet, id, flat) { sr_gahou(c, look, fleet, id, flat) }
}

// ── what the looks share ─────────────────────────────────────────────────

///|
/// The card as box `id` in `ground`, its parts laid out by `inner` from its very edges (a look pads its own: most lay a
/// picture to the edges): round as a card on the stage, or `flat` (handed out: its ground to its edges).
fn sr_box(c : @ui.Ctx, id : Int, flat : Bool, ground : Int64, inner : () -> Unit) -> Int {
  c.box(style=(if flat { sr_box_flat } else { sr_box_round }).then(@ui.style(bg=Data(ground))), id~, inner)
}

///|
/// The card, as wide as the picture (@sf.share_w_most), clipped round as a card, its edge a hairline on the stage.
// kept across runs: a value (no field of it changes)
let sr_box_round : @ui.Style = @ui.css("w=Full radius=Xl3 clip border=B1").then(@ui.style(border_color=Data(@sf.stage_edge)))

///|
// kept across runs: a value (no field of it changes)
let sr_box_flat : @ui.Style = sr_box_round.then(@ui.css("radius=Sharp border=B0"))

///|
/// Picture `art` `w` by `h` points, cut to that with its vertical crop at `at` (0 its top, 1 its foot); nothing under
/// it while it is on its way (the card's ground shows), no fade: a picture handed out is drawn whole (Ctx::shot waits).
fn sr_art(c : @ui.Ctx, art : String, w : Double, h : Double, at? : Double = 0.5) -> Int {
  let file = senren_art_file(art)
  if senren_drew.val is Some(drew) {
    drew.push(file)
  }
  c.image(senren_art_key(file), w=Px(w), h=Px(h), fit=FitCoverAt(at), bg=0L, fade=false)
}

///|
/// Words in the card's own face (霞鹜文楷 with EB Garamond: @sfbase.share_face_given), as every look's are.
fn sr_words(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.rich([@ui.span(words)], style~, face=@sfbase.share_face_given()) |> ignore
}

///|
/// Words in the card's face from runs (`@ui.span`s: a figure in another colour, larger, bolder).
fn sr_rich(c : @ui.Ctx, runs : Array[@ui.Run], style : @ui.TextStyle) -> Unit {
  c.rich(runs, style~, face=@sfbase.share_face_given()) |> ignore
}

///|
/// The words of `key` with its `{name}`s put in from `args`, as runs: the words as they are, each name's figure in `hi`
/// (`scale` its size, bolder): 「主人！这七天你烧掉了 {tokens} token」, the 2.1 亿 in the look's own colour.
fn sr_said(key : String, args : Array[(String, String)], hi : Int64, scale? : Double = 1.0) -> Array[@ui.Run] {
  let whole = @sf.t(key)
  let runs : Array[@ui.Run] = []
  let mut rest = whole
  while true {
    match rest.find("{") {
      None => break
      Some(i) => {
        let after = rest.exact_view(start=i + 1).to_owned()
        match after.find("}") {
          None => break
          Some(j) => {
            let name = after.exact_view(end=j).to_owned()
            if i > 0 {
              runs.push(@ui.span(rest.exact_view(end=i).to_owned()))
            }
            let value = match args.iter().find_first(fn(a) { a.0 == name }) {
              Some(a) => a.1
              None => "{" + name + "}"
            }
            runs.push(@ui.span(value, color=hi, weight=700, scale~))
            rest = after.exact_view(start=j + 1).to_owned()
          }
        }
      }
    }
  }
  if rest != "" {
    runs.push(@ui.span(rest))
  }
  runs
}

///|
/// The words of `key` with its `{name}`s put in from `args`, as one string (what a picture is named by).
fn sr_plain(key : String, args : Array[(String, String)]) -> String {
  let mut out = @sf.t(key)
  for a in args {
    out = out.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  out
}

///|
/// still.fail's name (its dot orange), in `ink`.
fn sr_brand(c : @ui.Ctx, style : @ui.TextStyle) -> Unit {
  sr_rich(c, [@ui.span("still"), @ui.span(".", color=@sf.share_orange), @ui.span("fail")], style)
}

///|
/// The figures a look says, by name, from the `fleet` view: what `sr_said`'s `{names}` are put in from. `top` the first
/// kind's first model (its name, tokens, cost), `lead` its accounts (用 6 个 Claude 订阅账号), the week's and today's.
fn sr_args(fleet : Json?) -> Array[(String, String)] {
  let spent = items(fleet, "spent")
  let first = spent.get(0)
  let top = items(first, "models").get(0)
  let week = span_stats(field(fleet, "week"))
  let today = span_stats(field(fleet, "today"))
  let stat = fn(s : Array[(String, String)], i : Int) { if i < s.length() { s[i].1 } else { "" } }
  [
    ("model", text(top, "name")),
    ("tokens", text(top, "tokensText")),
    ("cost", text(top, "costText")),
    ("accounts", count(first, "accounts").to_string()),
    ("kind", text(first, "name")),
    ("chats", count(fleet, "chats").to_string()),
    ("archived", stat(week, 0)),
    ("weekTokens", stat(week, 1)),
    ("weekCost", stat(week, 2)),
    ("todayArchived", stat(today, 0)),
    ("todayCost", stat(today, 1)),
    ("at", text(fleet, "at")),
    ("devices", count(fleet, "devices").to_string()),
    ("tasks", count(fleet, "tasks").to_string()),
    ("tasksPer", sr_num(text(fleet, "tasksPer"))),
    ("days", sr_days(fleet).filter(fn(d) { d.3 > 0.0 }).length().to_string()),
  ]
}

///|
/// One figure of sr_args by name ("" for none).
fn sr_arg(args : Array[(String, String)], name : String) -> String {
  match args.iter().find_first(fn(a) { a.0 == name }) {
    Some(a) => a.1
    None => ""
  }
}

///|
/// The first number in `words` (「近 7 天 agent 跨设备执行了 312 个任务」: 312; 「今天用了 3 台设备」: 3), "" for none: what the
/// view says only in a sentence, said alone.
fn sr_num(words : String) -> String {
  let buf = StringBuilder()
  for ch in words {
    if (ch >= '0' && ch <= '9') || (ch == '.' && buf.to_string() != "") {
      buf.write_char(ch)
    } else if buf.to_string() != "" {
      break
    }
  }
  let n = buf.to_string()
  if n.has_suffix(".") {
    n.exact_view(end=n.length() - 1).to_owned()
  } else {
    n
  }
}

///|
/// Every kind's models one after another, the most tokens first in each kind (the kinds in the view's order): each its
/// name, tokensText, costText, lineText, and its kind's name.
fn sr_models(fleet : Json?) -> Array[(String, String, String, String, String)] {
  let out = []
  for q in items(fleet, "spent") {
    let q = Some(q)
    for m in items(q, "models") {
      let m = Some(m)
      out.push((text(m, "name"), text(m, "tokensText"), text(m, "costText"), text(m, "lineText"), text(q, "name")))
    }
  }
  out
}

///|
/// The week's days, each its date (10/27), its chats archived (as said: 5 个; and the number alone: 5), its share of the
/// most on a day (0 to 1) and whether it is today.
fn sr_days(fleet : Json?) -> Array[(String, String, String, Double, Bool)] {
  items(field(fleet, "week"), "days").map(fn(d) {
    let d = Some(d)
    (text(d, "label"), text(d, "value"), sr_num(text(d, "value")), number(d, "share"), flag(d, "today"))
  })
}
