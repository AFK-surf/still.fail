// The sizes of pictures placed by Markdown, as a message's owner asks for them. This is made from the same
// Markdown tree and the same row and cell rules that lay the pictures out; it does not ask a row for its layout.

///|
/// A message owner holds its Markdown reading while it needs the places of pictures that entered the window. This
/// remains independent of the rows made to measure or draw that message.
pub struct MdPictureReading {
  priv text : String
  priv tree : Json?
  priv mut held : Bool
}

///|
/// Start following a message's Markdown at the cause that needs its pictures, not while laying out its row.
pub fn md_picture_reading(text : String, tree : Json?) -> MdPictureReading {
  let held = text != "" && tree is None
  if held {
    md_read_by(text, 1)
    md_ask(text)
  }
  { text, tree, held }
}

///|
/// Whether the core's reading is still coming. A watch that reads this is told when that answer arrives.
pub fn MdPictureReading::waiting(self : MdPictureReading) -> Bool {
  if self.held { md_answer(self.text).get() |> ignore }
  md_node_laying(self.text, self.tree)
}

///|
/// Let this owner go once it has used the answer or no longer needs it.
pub fn MdPictureReading::stop(self : MdPictureReading) -> Unit {
  if self.held {
    self.held = false
    md_read_by(self.text, -1)
  }
}

///|
/// The spans of a paragraph's images, in order, each row holding as many as fit at its least height.
fn md_picture_row_spans(ratios : Array[Double], room : Double) -> Array[(Int, Int)] {
  if ratios.is_empty() { return [] }
  let out : Array[(Int, Int)] = []
  let mut from = 0
  let mut used = 0.0
  for i, ratio in ratios {
    let w = ratio * image_row_least + (if i > from { image_row_gap } else { 0.0 })
    if i > from && used + w > room {
      out.push((from, i))
      from = i
      used = ratio * image_row_least
    } else {
      used += w
    }
  }
  out.push((from, ratios.length()))
  out
}

///|
/// A table cell made entirely of placed images, by name and clamped width over height. Any other cell is words.
fn md_cell_picture_names(cell : Array[MdInline], ratio : (String) -> Double?) -> Array[(String, Double)]? {
  let out : Array[(String, Double)] = []
  for x in cell {
    match x {
      Text(t) if t.trim(chars=" \n\t").to_string() == "" => ()
      SoftBreak | HardBreak => ()
      Image(src, _) => {
        let name = file_name_of(src)
        match ratio(name) {
          Some(r) => out.push((name, dmax(dmin(r, 4.0), 0.25)))
          None => return None
        }
      }
      _ => return None
    }
  }
  if out.is_empty() { None } else { Some(out) }
}

///|
/// Where the Markdown tree places each picture, and the width of its room there. `fills` is true for pictures in a
/// row or table cell; a picture drawn by itself is at most as wide as its own image box. The same file can occur in
/// more than one place, each of its rooms returned. `placed` names the message's files, `ratio` its placed images.
pub fn md_picture_places(
  text : String,
  tree : Json?,
  width : Double,
  size : Double,
  ratio : (String) -> Double?,
  placed : (String) -> Bool,
) -> Array[(String, Double, Bool)] {
  let out : Array[(String, Double, Bool)] = []
  fn blocks(bs : Array[MdBlock], room : Double) -> Unit {
    for b in bs {
      match b {
        Paragraph(xs) => {
          let parts = md_parts_of(xs)
          if parts.length() == 1 {
            match parts[0] {
              Link(href, _, _) => {
                let name = file_name_of(href)
                if placed(name) { out.push((name, room, false)) }
              }
              _ => ()
            }
          }
          let images : Array[(String, Double)] = []
          let mut all_images = parts.length() > 1
          for x in parts {
            match x {
              Image(src, _) => {
                let name = file_name_of(src)
                match ratio(name) {
                  Some(r) => images.push((name, r))
                  None => all_images = false
                }
              }
              _ => all_images = false
            }
          }
          if all_images {
            let ratios = images.map(fn(im) { im.1 })
            for (from, until) in md_picture_row_spans(ratios, room) {
              let mut all = 0.0
              for i in from..<until { all += ratios[i] }
              let h = if all <= 0.0 { 0.0 } else {
                dmin(image_row_most, (room - image_row_gap * (until - from - 1).to_double()) / all)
              }
              for i in from..<until { out.push((images[i].0, (images[i].1 * h).floor(), true)) }
            }
          } else {
            for x in xs {
              match x {
                Image(src, _) => {
                  let name = file_name_of(src)
                  if placed(name) { out.push((name, room, false)) }
                }
                _ => ()
              }
            }
          }
        }
        Quote(inner) => blocks(inner, dmax(0.0, room - md_quote_bar - md_quote_in))
        List(l) => {
          let marker = if l.ordered {
            dmax(md_marker_w, @ui.text_advance("\{l.start + l.items.length() - 1}.", size=@ui.current().sp(size)) + md_marker_gap)
          } else { md_marker_w }
          for item in l.items {
            let task = if item.task is Some(_) { @ui.current().sp(task_room) } else { 0.0 }
            blocks(item.blocks, dmax(0.0, room - marker - task))
          }
        }
        Table(t) => {
          let cells = [t.head] + t.rows
          for row in cells {
            for cell in row {
              match md_cell_picture_names(cell, ratio) {
                Some(images) => for im in images { out.push((im.0, cell_image_width(im.1), true)) }
                None => ()
              }
            }
          }
        }
        _ => ()
      }
    }
  }
  blocks(md_node_blocks(text, tree), dmax(0.0, width))
  out
}
