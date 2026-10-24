// Pictures as still.fail's Android app has them (drawable_data.mbt: its vector drawables, the station glyphs): mbui's
// @pixels.Vector, drawn by the GPU as shapes (@ui.vector_shapes) at the size they show at, or made into pixels on the
// CPU (@pixels.Vector::rgba) for a picture to hand on.

///|
/// `d` drawn `w` wide (its height as its viewport's) by the GPU (mbui's Ctx::shapes), its shapes kept by `key`, its
/// curves cut fine enough for the screen's pixels.
fn draw_drawable(c : @ui.Ctx, key : String, d : @pixels.Vector, w : Double, tint : Int64?) -> Int {
  let h = w * d.h / d.w
  let tk = match tint {
    Some(t) => t.to_string()
    None => "-"
  }
  let k = "pic/\{key}/\{w}/\{c.scale}/\{tk}"
  let shapes = match shapes_made.get(k) {
    Some(s) => s
    None => {
      let s = @ui.vector_shapes(d, w, c.scale, tint?=tint)
      shapes_made[k] = s
      s
    }
  }
  c.shapes(shapes, w=Px(w), h=Px(h), name="sf/" + k)
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
/// colours or all in `tint`.
pub fn drawable(c : @ui.Ctx, name : String, w : Double, tint? : Int64) -> Int {
  match drawables.get(name) {
    Some(d) => draw_drawable(c, name, d, w, tint)
    None => c.box(w=Px(w), h=Px(w), fn() {  })
  }
}

///|
/// Marks drawn in one colour, the page's ink (Parts.kt MONO); the others in
/// their own.
let mono_makers : Array[String] = [
  "anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter",
  "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface",
  "nvidia", "baseten", "dsh", "cursor", "devin",
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
      _ => "anthropic"
    }
  }
  let tint = if mono_makers.contains(id) { Some(theme().p.text) } else { None }
  drawable(c, "maker_" + id.replace_all(old="-", new="_"), size, tint?=tint)
}

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
    "teal" => 0x008D90FFL
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
    match station_glyphs.get(name) {
      Some((_, lines, dots)) => {
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
  if icon.has_prefix("data:image/") {
    match icon.find("base64,") {
      Some(i) => {
        let key = "mem:sf/station/\{icon.length()}/\{@ui.stable_hash(icon)}"
        if !made.contains(key) {
          made[key] = true
          @ui.add_image(key, @codec.from_base64(icon.view(start_offset=i + 7).to_owned()))
        }
        c.image(key, w=Px(size), h=Px(size), radius=size * 0.24, bg=0L, still~) |> ignore
        return
      }
      None => ()
    }
  }
  if emoji != "" {
    c.text(emoji, size=size * 0.9, wrap=false, line=size) |> ignore
    return
  }
  // none of its own: `none`'s icon, if given (Parts.kt StationMark's `none`)
  match none {
    Some(n) => icon_named(c, n, size, tint) |> ignore
    None => ()
  }
}

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
/// A station's mark (StationMark), or where it has none a computer's: this machine's a monitor, another's a server.
pub fn station_icon(c : @ui.Ctx, emoji : String, icon_name : String, size : Double, tint : Int64, here? : Bool = false) -> Unit {
  if has_station_mark(emoji, icon_name) {
    station_mark(c, emoji, icon_name, size, tint)
  } else {
    icon(c, if here { "monitor" } else { "server" }, size~, color=tint) |> ignore
  }
}
