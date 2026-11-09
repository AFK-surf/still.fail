///|
/// Shapes the lines of shape.txt beside the suite ("font file<TAB>text") and prints them as hb-shape does with
/// --no-glyph-names, to compare with HarfBuzz.
test "shape debug" {
  let dir = suite_dir()
  let list = @skiatest.read_file(dir + "shape.txt")
  if list.length() == 0 {
    return
  }
  let text = @utf8.decode(list) catch { _ => "" }
  for line in text.split("\n") {
    let parts = line.to_string().split("\t").map(fn(s) { s.to_string() }).to_array()
    if parts.length() < 2 {
      continue
    }
    guard @font.Face::parse(@skiatest.read_file(dir + "fonts/" + parts[0]), 0) is Some(face) else { continue }
    let buffer = @shape.Buffer::new()
    let s = parts[1]
    let bytes = @utf8.encode(s)
    let mut byte = 0
    for c in s {
      buffer.push(c.to_int(), byte)
      byte += @utf8.encode(c.to_string()).length()
    }
    ignore(bytes)
    if parts.length() > 2 && parts[2] == "rtl" {
      buffer.set_direction(RightToLeft)
    }
    @shape.shape(@shape.ShapeFont::new(face), buffer, [])
    let infos = buffer.glyph_infos()
    let pos = buffer.glyph_positions()
    let sb = StringBuilder::new()
    sb.write_string("SHAPE [")
    for i in 0..<infos.length() {
      if i > 0 {
        sb.write_string("|")
      }
      sb.write_string("\{infos[i].glyph_id}=\{infos[i].cluster}")
      if pos[i].x_offset != 0 || pos[i].y_offset != 0 {
        sb.write_string("@\{pos[i].x_offset},\{pos[i].y_offset}")
      }
      sb.write_string("+\{pos[i].x_advance}")
    }
    sb.write_string("]")
    println(sb.to_string())
  }
}

///|
/// Prints the outlines of glyphs.txt's glyphs ("font file<TAB>glyph ids") as the Rust dumper does.
test "outline debug" {
  let dir = suite_dir()
  let list = @skiatest.read_file(dir + "glyphs.txt")
  if list.length() == 0 {
    return
  }
  let text = @utf8.decode(list) catch { _ => "" }
  for line in text.split("\n") {
    let parts = line.to_string().split("\t").map(fn(s) { s.to_string() }).to_array()
    if parts.length() < 2 {
      continue
    }
    let path = if parts[0].has_prefix("/") { parts[0] } else { dir + "fonts/" + parts[0] }
    guard @font.Face::parse(@skiatest.read_file(path), 0) is Some(face) else { continue }
    for g in parts[1].split(" ") {
      let mut id = 0
      for ch in g {
        id = id * 10 + (ch.to_int() - 0x30)
      }
      let sb = StringBuilder::new()
      match face.outline(id) {
        Some(cmds) =>
          for c in cmds {
            match c {
              MoveTo(x, y) => sb.write_string("M\{x},\{y} ")
              LineTo(x, y) => sb.write_string("L\{x},\{y} ")
              QuadTo(a, b, x, y) => sb.write_string("Q\{a},\{b},\{x},\{y} ")
              CubicTo(a, b, c, d, x, y) => sb.write_string("C\{a},\{b},\{c},\{d},\{x},\{y} ")
              Close => sb.write_string("Z ")
            }
          }
        None => ()
      }
      println("GLYPH \{id} \{sb.to_string()}")
    }
  }
}
