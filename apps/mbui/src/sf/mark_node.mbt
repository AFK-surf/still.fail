// A person's round picture and a station's or a workspace's mark (avatar.mbt's avatar, picture.mbt's station_mark) as
// nodes of the window's tree, made once: what they show followed as what they are of changes, a picture asked for on the
// time on top of the page they are on (its stack's entry's, `stint`); a face's shown at once once it is decoded at the
// size it is drawn, its initial till then; a mark's faded in as an old view's picture is, its emoji till it comes; a
// GIF that moves going through its frames as what draws pictures has it (ui's moving_key).

///|
/// A person, round (avatar's, as a node) in `parent`, `size` across: `picture` (an image's key, "" while it comes or
/// without one) once it is decoded at the size it is shown, at once; their initial on their colour (by `id`) until
/// then, and for good when it cannot be decoded. Each as it changes.
#callsite(autofill(loc))
pub fn avatar_node(
  parent : @view.View,
  id : () -> String,
  name : () -> String,
  picture : () -> String,
  size : Double,
  loc~ : SourceLoc,
) -> Unit {
  let half = size / 2.0
  parent.box(made_for=loc, fn(d) {
    let px = fn() { size * d.pixel_scale() }
    // (its picture's node made only once it is decoded: its decode asked here, nothing drawn of it asking it before)
    let decoded = fn() {
      let p = picture()
      if p == "" {
        return false
      }
      d.image_ask(p, px())
      d.image_ready(p, px())
    }
    d
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .radius(Is(1.0e6))
    // (what it holds in its middle, both ways: avatar_disc's)
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { avatar_color(id()) }))
    |> ignore
    d.show(decoded, fn(p) {
      // (covering it, at once: avatar's picture, as Compose draws the bitmap it was handed)
      p
      .width(Is(Some(size)))
      .height(Is(Some(size)))
      .radius(Is(half))
      .image(By(fn() { Some((picture(), "", 8192)) }))
      .image_covers(Is(true))
      |> ignore
    })
    d.show(fn() { !decoded() }, fn(l) {
      l
      .words(By(fn() { initial(name()) }))
      .words_look(Is({ size: half, weight: 600, line: half, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }))
      .ink(Is(face_ink))
      |> ignore
    })
  })
  |> ignore
}

///|
/// A station's or a workspace's mark (station_mark's, as a node) in `parent`, `size` across: its `icon` first, a glyph
/// (glyph:<name>, glyph:<name>:<colour>, in that colour, else `tint`) or a picture put up (its address: its bytes the
/// core's, asked for on `stint` as the page's time on top is, a GIF among them moving; or a data URL), covering its
/// square, its corners a quarter of it round; else, and while that picture comes, its emoji. Each as it changes.
#callsite(autofill(loc))
pub fn station_mark_node(
  parent : @view.View,
  emoji : () -> String,
  icon : () -> String,
  size : Double,
  tint : () -> Int64,
  stint : () -> Int,
  loc~ : SourceLoc,
) -> Unit {
  // (which it shows: a glyph's paths, a picture's key, its emoji, nothing)
  let glyph = fn() -> (String, Array[String], Array[String], String)? {
    let i = icon()
    guard i.has_prefix("glyph:") else { return None }
    let rest = i.exact_view(start=6).to_owned()
    let (name, colour) = match rest.find(":") {
      Some(k) => (rest.exact_view(end=k).to_owned(), rest.exact_view(start=k + 1).to_owned())
      None => (rest, "")
    }
    glyph_paths(name).map(fn(p) { (name, p.0, p.1, colour) })
  }
  let picture = fn() -> (String, Bool) {
    let i = icon()
    if glyph() is Some(_) {
      return ("", false)
    }
    if i.has_prefix("https://") || i.has_prefix("http://") {
      let key = (picture_of.val)(i, stint())
      if key != "" {
        return (key, true)
      }
    }
    (data_image(i), false)
  }
  parent.box(made_for=loc, fn(m) {
    m.show(fn() { glyph() is Some(_) }, fn(g) {
      g.width(Is(Some(size))).height(Is(Some(size))) |> ignore
      g
      .shapes(By(fn() {
        match glyph() {
          Some((_, lines, dots, colour)) => {
            let layers : Array[@pixels.VectorPath] = []
            for d in lines {
              layers.push({ d, fill: 0L, stroke: 0x000000FFL, width: 1.75, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 })
            }
            for d in dots {
              layers.push({ d, fill: 0x000000FFL, stroke: 0L, width: 0.0, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 })
            }
            let color = glyph_color(colour, theme().dark).unwrap_or(tint())
            let drawing : @pixels.Vector = { w: 24.0, h: 24.0, layers }
            @ui.vector_shapes(drawing, size, g.pixel_scale(), tint=color)
          }
          None => []
        }
      }))
      .drawn_as(By(fn() { "sf/pic/glyph/" + glyph().map(fn(x) { x.0 }).unwrap_or("") }))
      |> ignore
    })
    m.show(fn() { picture().0 != "" }, fn(p) {
      // (covering its square, an address's and a data URL's alike, and faded in as it is decoded: an old view's
      // picture's way, station_mark's)
      p
      .width(Is(Some(size)))
      .height(Is(Some(size)))
      .radius(Is(size * 0.24))
      .image(By(fn() { Some((picture().0, "", 8192)) }))
      .image_covers(Is(true))
      .image_fades(Is(true))
      |> ignore
    })
    m.show(fn() { glyph() is None && picture().0 == "" && emoji() != "" }, fn(e) {
      // (as wide as it is set: a mark keeps its natural width, Windows' wider emoji too)
      e
      .width(By(fn() {
        e.words_redone() |> ignore
        Some(@ui.text_advance(emoji(), size=node_sp(e, size * 0.9)))
      }))
      .words(By(emoji))
      .words_look(Is({ size: size * 0.9, weight: 400, line: size, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }))
      .ink(By(fn() { @ui.tree_theme().fg }))
      // (on the baseline the app's own face gives it, whatever face its words are in, where lines are set as the web
      // sets them: station_mark's)
      .offset(By(fn() {
        if @ui.web_lines_on() {
          e.words_redone() |> ignore
          let (line, words) = (node_sp(e, size), node_sp(e, size * 0.9))
          (0.0, @ui.line_baseline(line, size=words, em=mark_em) - @ui.line_baseline(line, size=words))
        } else {
          (0.0, 0.0)
        }
      }))
      |> ignore
    })
  })
  |> ignore
}

///|
/// A workspace before its name where it is named among other words (workspace_badge's, as a node) in `parent`: its
/// mark `size` across (station_mark_node's, in the ink; a picture of it asked for on `stint`), else its `name`'s first
/// letter, semibold and muted in a meta's size (part of the mark: at its size whatever the system's size of words,
/// mark_words_node), in a square as large. Each as it changes.
#callsite(autofill(loc))
pub fn workspace_badge_node(
  parent : @view.View,
  name : () -> String,
  emoji : () -> String,
  icon : () -> String,
  size : Double,
  stint? : () -> Int = fn() { 0 },
  loc~ : SourceLoc,
) -> Unit {
  let marked = fn() { has_station_mark(emoji(), icon()) }
  parent.box(made_for=loc, fn(b) {
    // (one in the other's place, in a line of words: at once)
    b.show(marked, at_once=true, fn(m) { station_mark_node(m, emoji, icon, size, fn() { theme().p.text }, stint) })
    b.show(fn() { !marked() }, at_once=true, fn(tile) {
      style_node(tile, fn() { workspace_badge_tile })
      tile.width(Is(Some(size))).height(Is(Some(size))) |> ignore
      mark_words_node(tile, fn() { initial(name()) }, fn() { workspace_badge_letter }) |> ignore
    })
  })
  |> ignore
}

///|
/// A thing's mark (tile_avatar's, as a node: a repository, a project) in `parent`, `size` across, a rounded square
/// (`corner` its own where it stands in a row's corner, else a tile's .3 of its side): `picture` (a data URL of its own,
/// its favicon or touch icon) once it is decoded at the size it is shown, covering it; else its `name`'s initial on a
/// colour of its own by `id` (its repository's address), as a face's is, part of the mark (at its size whatever the
/// system's size of words: mark_words_node's way). Each as it changes.
#callsite(autofill(loc))
pub fn tile_avatar_node(
  parent : @view.View,
  id : () -> String,
  name : () -> String,
  picture : () -> String,
  size : Double,
  corner? : Double,
  loc~ : SourceLoc,
) -> Unit {
  let half = size / 2.0
  let corner = corner.unwrap_or(size * 0.3)
  parent.box(made_for=loc, words_as_said=true, fn(d) {
    let key = fn() { data_image(picture()) }
    // (its picture's node made only once it is decoded: its decode asked here, nothing drawn of it asking it before)
    let decoded = fn() {
      let k = key()
      if k == "" {
        return false
      }
      d.image_ask(k, size * d.pixel_scale())
      d.image_ready(k, size * d.pixel_scale())
    }
    d
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .radius(Is(corner))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { if decoded() { transparent_ground } else { avatar_color(id()) } }))
    |> ignore
    d.show(decoded, at_once=true, fn(p) {
      p
      .width(Is(Some(size)))
      .height(Is(Some(size)))
      .radius(Is(corner))
      .image(By(fn() { Some((key(), "", 8192)) }))
      .image_covers(Is(true))
      |> ignore
    })
    d.show(fn() { !decoded() }, at_once=true, fn(l) {
      l
      .words(By(fn() { initial(name()) }))
      .words_look(Is({ size: half, weight: 600, line: half, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }))
      .ink(Is(face_ink))
      |> ignore
    })
  })
  |> ignore
}
