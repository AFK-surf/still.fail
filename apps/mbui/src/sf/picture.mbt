// Pictures as still.fail's Android app has them (drawable_data.mbt: its vector drawables, the station glyphs): mbui's
// @pixels.Vector, drawn by the GPU as shapes (@ui.vector_shapes) at the size they show at, or made into pixels on the
// CPU (@pixels.Vector::rgba) for a picture to hand on.

///|
/// `d` drawn `w` wide (its height as its viewport's) by the GPU (mbui's Ctx::shapes), its shapes kept by `key`, its
/// curves cut fine enough for the screen's pixels.
fn draw_drawable(c : @ui.Ctx, key : String, d : @pixels.Vector, w : Double, tint : Int64?) -> Int {
  let h = w * d.h / d.w
  // (its curves cut as fine as it is drawn: a shot's own pixels a point where it is in one)
  let sc = c.drawn_scale()
  let drawn = match pictures_made.get((key, w, sc, tint)) {
    Some(m) => m
    None => {
      let tk = match tint {
        Some(t) => t.to_string()
        None => "-"
      }
      let m = {
        shapes: @ui.vector_shapes(d, w, sc, tint?=tint),
        name: "sf/pic/\{key}/\{w}/\{sc}/\{tk}",
      }
      pictures_made[(key, w, sc, tint)] = m
      m
    }
  }
  c.shapes(drawn.shapes, w=Px(w), h=Px(h), name=drawn.name)
}

///|
/// A picture made by the app (`d`: its viewport and its paths, each in its own colours) drawn `w` wide by the GPU, its
/// shapes kept by `key`, which says what it is made of (the same picture each time it is asked for by it).
pub fn vector(c : @ui.Ctx, key : String, d : @pixels.Vector, w : Double) -> Int {
  draw_drawable(c, "made/" + key, d, w, None)
}

///|
/// The picture `name` drawn `px` pixels wide (as tall as it is for that), in its own colours or all in `tint`: its
/// width, height and pixels (RGBA, straight, rows from the top), to make another picture with; None when there is no
/// such picture.
pub fn drawable_pixels(name : String, px : Int, tint? : Int64) -> (Int, Int, FixedArray[Byte])? {
  match drawables.get(name) {
    Some(d) => {
      let ph = (px.to_double() * d.h / d.w).round().to_int()
      let ph = if ph < 1 { 1 } else { ph }
      Some((px, ph, d.rgba(px, ph, tint?=tint)))
    }
    None => None
  }
}

///|
/// Whether the app has the picture `name` (its drawable's name: maker_openai,
/// illus_sign_in…).
pub fn has_drawable(name : String) -> Bool {
  drawables.contains(name)
}

///|
/// The picture `name` drawn `w` wide (as tall as it is for that), in its own
/// colours (a maker's mark, an illustration: their colours asked no contrast,
/// @ui's own_colours) or all in `tint`.
/// How tall drawable `name` is drawn `w` wide (`drawable`'s; as wide as tall when there is none so named).
pub fn drawable_height(name : String, w : Double) -> Double {
  match drawables.get(name) {
    Some(d) => w * d.h / d.w
    None => w
  }
}

///|
/// Drawable `name`'s picture (None: there is none so named), for a node of the window's tree to draw (View::picture).
pub fn drawable_vector(name : String) -> @pixels.Vector? {
  drawables.get(name)
}

///|
pub fn drawable(c : @ui.Ctx, name : String, w : Double, tint? : Int64) -> Int {
  match drawables.get(name) {
    Some(d) => {
      let b = draw_drawable(c, name, d, w, tint)
      if tint is None {
        c.own_colours(b)
      }
      b
    }
    None => c.box(w=Px(w), h=Px(w), fn() {  })
  }
}

///|
/// Marks drawn in one colour, the page's ink (Parts.kt MONO); the others in
/// their own.
let mono_makers : Array[String] = [
  "anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter",
  "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface",
  "nvidia", "baseten", "dsh", "cursor", "devin", "hermes",
]

///|
/// The mark of the company that made a model (Parts.kt MakerIcon): the core's
/// `maker` id when there is a mark for it, else its runtime's maker's
/// (codex: OpenAI's, dsh its own, grok xAI's, Cursor's and Devin's their own, else Anthropic's).
pub fn maker_mark(
  c : @ui.Ctx,
  maker : String,
  runtime : String,
  size : Double,
) -> Int {
  let known = maker != "" &&
    drawables.contains("maker_" + maker.replace_all(old="-", new="_"))
  let id = if known {
    maker
  } else {
    match runtime {
      "codex" => "openai"
      "dsh" => "dsh"
      "grok" => "xai"
      "cursor" => "cursor"
      "devin" => "devin"
      "hermes" => "hermes"
      _ => "anthropic"
    }
  }
  let tint = if mono_makers.contains(id) { Some(theme().p.text) } else { None }
  drawable(c, "maker_" + id.replace_all(old="-", new="_"), size, tint?=tint)
}

///|
/// A program a station logs in to (the core's `MachineLoginTool.mark`; the web's MachineLogins.tsx ToolMark): its
/// maker's mark in its colours, those whose colour is black in the page's ink; a terminal's where it has none.
pub fn tool_mark(c : @ui.Ctx, mark : String, size : Double) -> Unit {
  let name = "tool_" + mark.replace_all(old="-", new="_")
  if mark == "" || !drawables.contains(name) {
    station_mark(c, "", "glyph:terminal", size, theme().p.muted)
    return
  }
  let tint = if ink_tools.contains(mark) { Some(theme().p.text) } else { None }
  drawable(c, name, size, tint?=tint) |> ignore
}

///|
/// The tools' marks drawn in the page's ink (black ones: white in the dark).
let ink_tools : Array[String] = ["github", "cursor", "vercel", "openai", "devin"]

///|
/// Slack's mark (a chat that came from Slack).
pub fn slack_mark(c : @ui.Ctx, size : Double) -> Int {
  drawable(c, "slack", size)
}

///|
/// Feishu's mark (a Feishu connect, SlackMark's "feishu").
pub fn feishu_mark(c : @ui.Ctx, size : Double) -> Int {
  drawable(c, "feishu", size)
}

///|
/// The station glyphs' colours a station may give its glyph (glyph:<name>:<colour>), light and dark.
pub fn glyph_color(name : String, dark : Bool) -> Int64? {
  let light = match name {
    "red" => 0xBC4945FFL
    "orange" => 0xB75400FFL
    "amber" => 0xA16700FFL
    "green" => 0x0E8C41FFL
    "teal" => 0x008A8DFFL
    "blue" => 0x2D74CAFFL
    "purple" => 0x835CBEFFL
    "pink" => 0xB24981FFL
    _ => return None
  }
  if !dark {
    return Some(light)
  }
  Some(
    match name {
      "red" => 0xFB9890FFL
      "orange" => 0xF5A06FFFL
      "amber" => 0xE0AE57FFL
      "green" => 0x7CCD8EFFL
      "teal" => 0x3BCFCFFFL
      "blue" => 0x82BAFFFFL
      "purple" => 0xC3A5F9FFL
      _ => 0xF197C2FFL
    },
  )
}

///|
/// A picture put up by its address (on the page's time on top `stint`: Ctx::page_stint) as an image's key once it is
/// here ("" until then): the app's (its core's `picture`), said as it starts; until then the address itself, which
/// the host loads.
// kept across runs: the app says it as its view is built, the same function every run
pub let picture_of : Ref[(String, Int) -> String] = Ref(fn(url, _) { url })

///|
/// A picture given inline (a data URL: a station's icon put up, a web page's icon and picture in a link's card), as an
/// image of the app's own to draw by its key, made once; "" for what is no data URL (an address, drawn as it is).
pub fn data_image(url : String) -> String {
  guard url.has_prefix("data:image/") else { return "" }
  match url.find("base64,") {
    Some(i) => {
      // (named as the stations' were before: what is drawn is said by its key)
      let key = "mem:sf/station/\{url.length()}/\{@ui.stable_hash(url)}"
      if !made.contains(key) {
        made[key] = true
        @ui.add_image(key, @codec.from_base64(url.view(start_offset=i + 7).to_owned()))
      }
      key
    }
    None => ""
  }
}

///|
/// Whether a station has anything to be shown by (`station_mark` draws
/// nothing for it otherwise).
pub fn has_station_mark(emoji : String, icon : String) -> Bool {
  emoji != "" || icon != ""
}

///|
/// A station where it is named (Parts.kt StationMark): its `icon` first, a
/// glyph (glyph:<name>, glyph:<name>:<colour>, in that colour, else `tint`)
/// or a picture put up (its address, or a data URL); else its emoji.
pub fn station_mark(
  c : @ui.Ctx,
  emoji : String,
  icon : String,
  size : Double,
  tint : Int64,
  none? : String,
  still? : Bool = false,
) -> Unit {
  if icon.has_prefix("glyph:") {
    let rest = icon.view(start_offset=6).to_owned()
    let (name, colour) = match rest.find(":") {
      Some(i) =>
        (
          rest.view(end_offset=i).to_owned(),
          rest.view(start_offset=i + 1).to_owned(),
        )
      None => (rest, "")
    }
    match glyph_paths(name) {
      Some((lines, dots)) => {
        let layers : Array[@pixels.VectorPath] = []
        for d in lines {
          layers.push({
            d,
            fill: 0L,
            stroke: 0x000000FFL,
            width: 1.75,
            even_odd: false,
            sx: 1.0,
            sy: 1.0,
            tx: 0.0,
            ty: 0.0,
          })
        }
        for d in dots {
          layers.push({
            d,
            fill: 0x000000FFL,
            stroke: 0L,
            width: 0.0,
            even_odd: false,
            sx: 1.0,
            sy: 1.0,
            tx: 0.0,
            ty: 0.0,
          })
        }
        let color = glyph_color(colour, theme().dark).unwrap_or(tint)
        draw_drawable(c, "glyph/" + name, { w: 24.0, h: 24.0, layers }, size, Some(color))
        |> ignore
        return
      }
      None => ()
    }
  }
  // a picture still.fail cloud keeps (cloud/src/icons.ts), by its address: its bytes the core's (`picture`, as
  // Parts.kt rememberStationPicture), so a GIF among them moves (mbui's gif.mbt); its emoji (below) while it comes
  if icon.has_prefix("https://") || icon.has_prefix("http://") {
    let key = (picture_of.val)(icon, c.page_stint())
    if key != "" {
      c.image(key, w=Px(size), h=Px(size), fit=FitCover, radius=size * 0.24, bg=0L, still~) |> ignore
      return
    }
  }
  match data_image(icon) {
    "" => ()
    key => {
      c.image(key, w=Px(size), h=Px(size), radius=size * 0.24, bg=0L, still~) |> ignore
      return
    }
  }
  if emoji != "" {
    // A mark keeps its natural width, including Windows' wider emoji. A column's
    // one-line text is otherwise capped to its slot and replaced by an ellipsis.
    let width = @ui.text_advance(emoji, size=c.sp(size * 0.9))
    // On the baseline the app's own face gives it, whatever face its words are in: a taller one chosen (思源黑体's
    // ascent 1.16) set it lower in its line, under the marks beside it.
    let ty = if @ui.web_lines_on() {
      let (line, words) = (c.sp(size), c.sp(size * 0.9))
      @ui.line_baseline(line, size=words, em=mark_em) - @ui.line_baseline(line, size=words)
    } else {
      0.0
    }
    let draw = fn() { c.text(emoji, size=size * 0.9, wrap=false, line=size, w=Px(width)) |> ignore }
    if ty == 0.0 {
      draw()
    } else {
      c.box(ty~, draw) |> ignore
    }
    return
  }
  // none of its own: `none`'s icon, if given (Parts.kt StationMark's `none`)
  match none {
    Some(n) => icon_named(c, n, size, tint) |> ignore
    None => ()
  }
}

///|
/// How far the app's own face (Inter 4.001, the wide frame's words with none chosen: sfbase's inter_face.mbt) reaches
/// above and below its baseline, shares of its size (its 1984 and 494 of 2048): where a station's emoji stands in its
/// line (station_mark).
// kept across runs: a value (no field of it changes)
let mark_em : (Double, Double) = (1984.0 / 2048.0, 494.0 / 2048.0)

///|
/// A workspace before its name where it is named among other words (a list's row, a chip, a heading; the web's
/// WorkspaceMark.tsx WorkspaceBadge): its mark `size` across (station_mark), else its first letter, semibold and muted
/// in a meta's size, in a square as large (no ground of its own, as the workspaces' rows have it: in a rounded row's
/// corner a tile would have to be concentric with it). A GIF holds its first frame unless `still` is false (the
/// workspace in use).
pub fn workspace_badge(
  c : @ui.Ctx,
  name : String,
  emoji : String,
  icon : String,
  size : Double,
  still? : Bool = true,
) -> Unit {
  if has_station_mark(emoji, icon) {
    station_mark(c, emoji, icon, size, theme().p.text, still~)
    return
  }
  let tile = workspace_badge_tile.then(@ui.style(w=Fixed(size), h=Fixed(size)))
  c.box(style=tile, fn() {
    c.text(initial(name), style=workspace_badge_letter) |> ignore
  })
  |> ignore
}

///|
/// A workspace's letter's square (workspace_badge): what it holds in its middle.
// kept across runs: a value (no field of it changes)
let workspace_badge_tile : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// Its letter: a meta's size, semibold, muted, on one line.
// kept across runs: a value (no field of it changes)
let workspace_badge_letter : @ui.TextStyle = @ui.text_style(size=Meta, leading=Font, weight=Semibold, color=Muted, wrap=false)

///|
/// Icon `name` (`icon`, where a parameter of that name hides it).
fn icon_named(c : @ui.Ctx, name : String, size : Double, color : Int64) -> Int {
  icon(c, name, size~, color~)
}

///|
/// Line art on a `vw` × `vh` grid, its paths stroked `width` wide with round ends and joins, nothing filled (a link's
/// card's mark, ScreenLinks.kt tile): drawn `w` wide (as tall as its grid is for that) in `tint`, kept by `key` for
/// each size and tint.
pub fn line_art(
  c : @ui.Ctx,
  key : String,
  paths : Array[String],
  vw : Double,
  vh : Double,
  width : Double,
  w : Double,
  tint : Int64,
) -> Int {
  let layers : Array[@pixels.VectorPath] = []
  for d in paths {
    layers.push({ d, fill: 0L, stroke: 0x000000FFL, width, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 })
  }
  draw_drawable(c, "art/" + key, { w: vw, h: vh, layers }, w, Some(tint))
}

///|
/// A popover's arrow, pointing up at what it is from (StationUpdate.kt: 14 across, 7 up, in the popover's colour; a
/// pixel more under it, into the popover).
// kept across runs: a value (no field of it changes)
let popover_arrow_shape : @pixels.Vector = {
  w: 14.0,
  h: 8.0,
  layers: [
    {
      d: "M 0 8 L 7 0 L 14 8 Z",
      fill: 0x000000FFL,
      stroke: 0x00000000L,
      width: 0.0,
      even_odd: false,
      sx: 1.0,
      sy: 1.0,
      tx: 0.0,
      ty: 0.0,
    },
  ],
}

///|
/// The arrow of a popover (14 by 8) in `tint`.
pub fn popover_arrow(c : @ui.Ctx, tint : Int64) -> Int {
  draw_drawable(c, "popover-arrow", popover_arrow_shape, popover_arrow_shape.w, Some(tint))
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// A station's mark (StationMark), or where it has none keyboard and mouse's: this machine's a monitor, another's a server.
pub fn station_icon(c : @ui.Ctx, emoji : String, icon_name : String, size : Double, tint : Int64, here? : Bool = false) -> Unit {
  if has_station_mark(emoji, icon_name) {
    station_mark(c, emoji, icon_name, size, tint)
  } else {
    icon(c, if here { "monitor" } else { "server" }, size~, color=tint) |> ignore
  }
}

///|
/// Station glyph `name`'s lines and dots, from its text in drawable_data.mbt ("emoji|line;line|dot;dot"), read the
/// first time it is asked for.
fn glyph_paths(name : String) -> (Array[String], Array[String])? {
  if glyphs_read.get(name) is Some(g) {
    return Some(g)
  }
  guard station_glyphs.get(name) is Some(text) else { return None }
  let parts = text.split("|").map(fn(p) { p.to_string() }).to_array()
  let paths = fn(i : Int) -> Array[String] {
    if i < parts.length() && parts[i] != "" {
      parts[i].split(";").map(fn(p) { p.to_string() }).to_array()
    } else {
      []
    }
  }
  let g = (paths(1), paths(2))
  glyphs_read[name] = g
  Some(g)
}

///|
let glyphs_read : Map[String, (Array[String], Array[String])] = {}

///|
/// Whose service a profile runs on (ProviderLogo; Parts.kt ProviderMark): OpenCode's square, a listed provider's maker
/// (`mark`; the plug where there is none), else Anthropic, xAI, Cursor, Devin, Hermes or OpenAI by its runtime (`kind`
/// the profile's access: an API provider's, OpenCode Go's, Anthropic's API).
pub fn provider_logo(c : @ui.Ctx, runtime : String, kind : String, size : Double, mark : String) -> Unit {
  let t = theme()
  if kind == "opencode-go" || mark == "opencode" {
    // (OpenCodeMark: a frame half as wide as its size and two thirds as high)
    c.box(style=logo_room.then(@ui.style(w=Fixed(size), h=Fixed(size))), fn() {
      c.box(style=opencode_frame.then(@ui.style(w=Fixed(size * opencode_w), h=Fixed(size * opencode_h))), fn() {  })
      |> ignore
    })
    |> ignore
    return
  }
  // (a profile of the environment's own keys: the sliders)
  if kind == "env" {
    icon(c, "sliders", size~, color=t.p.text) |> ignore
    return
  }
  let maker = if kind == "api-provider" {
    mark
  } else if runtime == "claude" || kind == "anthropic-api" {
    "anthropic"
  } else {
    match runtime {
      "grok" => "xai"
      "cursor" => "cursor"
      "devin" => "devin"
      "hermes" => "hermes"
      _ => "openai"
    }
  }
  if maker == "" || !has_drawable("maker_" + maker.replace_all(old="-", new="_")) {
    icon(c, "plug", size~, color=t.p.text) |> ignore
  } else {
    maker_mark(c, maker, runtime, size) |> ignore
  }
}

///|
/// OpenCode's mark: a frame in the words' ink, half as wide as the mark and two thirds as high.
let opencode_w : Double = 0.5

///|
let opencode_h : Double = 0.6667

///|
// kept across runs: a value (no field of it changes)
let opencode_frame : @ui.Style = @ui.css("border=B1_5 border_color=Fg")

///|
// kept across runs: a value (no field of it changes)
let logo_room : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// Rings one inside another (Activity's), `side` across, with the room for `most` of them (as many as are ever drawn
/// there: fewer stand where those would, the outer ones): each as wide as the hole they leave in their middle is round
/// (ring_hole), ring_apart of that from the next, so the innermost is a ring still (2026-10-26 用户 of three in 88,
/// each 12: 「最里面的那个圆点不对吧」, the third a disc, its share a dot), from the outside in: each its track all round in
/// its colour at `track` (an alpha, 0-255), and as much of it as its share drawn round from its top in its colour, round
/// at its ends; a share past 1 (two accounts' quota past one's) goes round again over it, each turn past the first
/// deeper (ring_turn_keep), the last whole one under what is left of it.
pub fn rings(c : @ui.Ctx, shares : Array[(Double, Int64)], side : Double, track : Int64, most~ : Int) -> Int {
  let mid = side / 2.0
  let n = (if most > 1 { most } else { 1 }).to_double()
  let width = mid / (n + ring_hole + ring_apart * (n - 1.0))
  let gap = width * ring_apart
  let layers : Array[@pixels.VectorPath] = []
  let keys : Array[String] = []
  for k, ring in shares {
    let (share, color) = ring
    let share = if share < 0.0 { 0.0 } else { share }
    keys.push("\{share}/\{color}")
    let r = mid - width / 2.0 - k.to_double() * (width + gap)
    if r <= 0.0 {
      break
    }
    let path = fn(d : String, stroke : Int64) -> @pixels.VectorPath {
      { d, fill: 0L, stroke, width, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 }
    }
    // turn `t` (0 the first): its colour, deeper past the first
    let turn = fn(t : Int) -> Int64 {
      let mut keep = 1.0
      for _ in 0..<t {
        keep = keep * ring_turn_keep
      }
      mix(color, keep, 0x000000FFL)
    }
    let circle = "M \{mid - r} \{mid} A \{r} \{r} 0 1 1 \{mid + r} \{mid} A \{r} \{r} 0 1 1 \{mid - r} \{mid}"
    layers.push(path(circle, (color & 0xFFFFFF00L) | (track & 0xFFL)))
    let whole = share.floor()
    let rest = share - whole
    if whole >= 1.0 {
      layers.push(path(circle, turn(whole.to_int() - 1)))
    }
    if rest > 0.0 {
      let a = rest * 2.0 * @math.PI
      let (x, y) = (mid + r * @dmath.sin(a), mid - r * @dmath.cos(a))
      let large = if rest > 0.5 { 1 } else { 0 }
      layers.push(path("M \{mid} \{mid - r} A \{r} \{r} 0 \{large} 1 \{x} \{y}", turn(whole.to_int())))
    }
  }
  vector(c, "rings/\{side}/\{width}/\{gap}/\{track}/" + keys.join(","), { w: side, h: side, layers }, side)
}

///|
/// The hole in the middle of rings (rings): round as far as a ring is wide (Activity's: three rings, the hole as wide
/// as one).
let ring_hole : Double = 1.0

///|
/// How far apart rings are (rings): this much of one's width.
let ring_apart : Double = 0.2


///|
/// A picture of the app's (`name`, drawable_data's) as an icon for the system's bars (@hostapi.NavItem `icon`:
/// icon_data's groups on a 24 grid, in the one ink the system tints it with): each path's fill a shape of its pieces
/// (`7`, by the even-odd rule where it is), each stroke its lines, each at its colour's alpha (`4 a 0`); "" for none.
pub fn drawable_icon(name : String) -> String {
  guard drawables.get(name) is Some(d) else { return "" }
  let k = 24.0 / dmax(d.w, d.h)
  let out = StringBuilder()
  let num = fn(x : Double) { ((x * 1000.0).round() / 1000.0).to_string() }
  for l in d.layers {
    let colour = if l.fill != 0L { l.fill } else { l.stroke }
    out.write_string("4 \{num((colour & 0xFFL).to_double() / 255.0)} 0 ")
    for sub in l.outlines(k, 4.0) {
      let (pts, closed) = sub
      let kind = if l.fill != 0L {
        7
      } else if closed {
        1
      } else {
        0
      }
      let width = if l.fill != 0L {
        if l.even_odd { 1.0 } else { 0.0 }
      } else {
        l.width * k
      }
      out.write_string("\{kind} \{num(width)} \{pts.length() / 2}")
      for v in pts {
        out.write_string(" " + num(v))
      }
      out.write_string(" ")
    }
  }
  out.to_string().trim_end(chars=" ").to_string()
}

///|
/// An agent's maker's mark (maker_mark's) as an icon for the system's bars (drawable_icon).
pub fn maker_icon(maker : String, runtime : String) -> String {
  let known = maker != "" && drawables.contains("maker_" + maker.replace_all(old="-", new="_"))
  let id = if known {
    maker
  } else {
    match runtime {
      "codex" => "openai"
      "dsh" => "dsh"
      "grok" => "xai"
      "cursor" => "cursor"
      "devin" => "devin"
      "hermes" => "hermes"
      _ => "anthropic"
    }
  }
  drawable_icon("maker_" + id.replace_all(old="-", new="_"))
}
