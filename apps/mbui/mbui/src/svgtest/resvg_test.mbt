// resvg's own tests (crates/resvg/tests): each SVG drawn 300 wide and compared with resvg's picture, a pixel counting
// as different where a channel of it, alpha divided out, is off by more than 1 (tests/integration/main.rs).

///|
fn suite_dir() -> String {
  for d in ["src/svgtest/resvg/", "svgtest/resvg/", "mbui/src/svgtest/resvg/"] {
    if @skiatest.read_file(d + "index.txt").length() > 0 {
      return d
    }
  }
  ""
}

///|
fn demultiplied(p : @skia.Pixmap) -> FixedArray[Byte] {
  let out = FixedArray::make(p.width * p.height * 4, b'\x00')
  for i in 0..<(p.width * p.height) {
    let a = p.data[i * 4 + 3].to_int()
    let ad = a.to_double() / 255.0
    for k in 0..<3 {
      let c = p.data[i * 4 + k].to_int().to_double()
      let v = c / ad + 0.5
      let b = if v.is_nan() { 0 } else if v >= 255.0 { 255 } else { v.to_int() }
      out[i * 4 + k] = b.to_byte()
    }
    out[i * 4 + 3] = a.to_byte()
  }
  out
}

///|
/// How many pixels differ (get_diff).
fn pixel_diff(ew : Int, eh : Int, e : FixedArray[Byte], aw : Int, ah : Int, a : FixedArray[Byte]) -> Int {
  let w = if ew > aw { ew } else { aw }
  let h = if eh > ah { eh } else { ah }
  let mut n = 0
  for y in 0..<h {
    for x in 0..<w {
      let in_e = x < ew && y < eh
      let in_a = x < aw && y < ah
      if in_e && in_a {
        let ie = (y * ew + x) * 4
        let ia = (y * aw + x) * 4
        if e[ie + 3].to_int() == 0 && a[ia + 3].to_int() == 0 {
          continue
        }
        let mut diff = false
        for k in 0..<4 {
          let d = e[ie + k].to_int() - a[ia + k].to_int()
          if d > 1 || d < -1 {
            diff = true
          }
        }
        if diff {
          n += 1
        }
      } else {
        n += 1
      }
    }
  }
  n
}

///|
test "resvg suite" {
  let dir = suite_dir()
  if dir == "" {
    println("SVGTEST no suite")
    return
  }
  let index = @utf8.decode(@skiatest.read_file(dir + "index.txt")) catch { _ => "" }
  let only = @skiatest.read_file(dir + "only.txt")
  let only = if only.length() > 0 { @utf8.decode(only) catch { _ => "" } } else { "" }
  let fonts = @font.FontDb::new()
  let font_list = @utf8.decode(@skiatest.read_file(dir + "fonts.txt")) catch { _ => "" }
  for f in font_list.split("\n") {
    let f = f.trim(chars=" \r").to_string()
    if f != "" {
      fonts.load_font_data(@skiatest.read_file(dir + "fonts/" + f))
    }
  }
  fonts.set_serif_family("Noto Serif")
  fonts.set_sans_serif_family("Noto Sans")
  fonts.set_cursive_family("Yellowtail")
  fonts.set_fantasy_family("Sedgwick Ave Display")
  fonts.set_monospace_family("Noto Mono")
  let mut passed = 0
  let mut total = 0
  for line in index.split("\n") {
    let name = line.trim(chars=" \r").to_string()
    if name == "" || (only != "" && !only.contains(name)) {
      continue
    }
    total += 1
    let svg = @utf8.decode(@skiatest.read_file(dir + name + ".svg")) catch { _ => "" }
    let opt = { ..@svg.Options::default(), fonts, read_file: fn(f) {
        let b = @skiatest.read_file(dir + name.rev_find("/").map(fn(i) { name.view(end_offset=i + 1).to_string() }).unwrap_or("") + f)
        if b.length() > 0 { Some(b) } else { None }
      } }
    let expected = @skiatest.decode_png(@skiatest.read_file(dir + name + ".png"))
    let result = match (@svg.render_svg_to_width(svg, 300, opt), expected) {
      (Some(p), Some((ew, eh, e))) => pixel_diff(ew, eh, e, p.width, p.height, demultiplied(p))
      (None, _) => -1
      (_, None) => -2
    }
    if result == 0 {
      passed += 1
    }
    println("SVGTEST \{name} \{result}")
  }
  println("SVGTEST passed \{passed} of \{total}")
}
