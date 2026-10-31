// Pictures checked: a renderer's lines (chk lines PNG), its shapes (chk shapes PNG), Android's round page (chk views-round LOG PNG)

///|
fn picture(path : String) -> @png.Picture? {
  match @png.read(path) {
    Ok(p) => Some(p)
    Err(e) => {
      say(e)
      None
    }
  }
}

///|
fn rgb_text(c : (Int, Int, Int)) -> String {
  "(\{c.0}, \{c.1}, \{c.2})"
}

///|
fn near_max(c : (Int, Int, Int), want : (Int, Int, Int), tol : Int) -> Bool {
  (c.0 - want.0).abs() <= tol && (c.1 - want.1).abs() <= tol && (c.2 - want.2).abs() <= tol
}

///|
fn num_text(x : Double) -> String {
  if x == x.floor() && x.abs() < 1.0e15 {
    x.to_int64().to_string()
  } else {
    x.to_string()
  }
}

///|
/// Whether a renderer draws lines (scene.mbt's kind 10) as they are: the picture of
/// src/kitdemo/gallery/dl_print_wbtest.mbt's lines_shown (160 by 160 at scale 2, on white) drawn by it. Its horizontal
/// line is the same as the rounded rect of the same shape drawn 40 under it (each pixel's channels within 3) but where
/// the rect's ends ease into its edges, its
/// slanted line and its arc are inked along their middles and not off them, its half drawn line ends halfway, and its
/// box turned 30° clockwise about its top left is drawn turned so (scene.mbt 32-34: the renderer turns it).
fn lines(args : Array[String]) -> Int {
  if args.length() != 1 {
    @sys.eprintln("chk lines PNG")
    return 2
  }
  let path = args[0]
  let pic = match picture(path) {
    Some(p) => p
    None => return 1
  }
  let tol = 3
  let s = 2 // the picture's scale
  if pic.w != 160 * s || pic.h != 160 * s {
    say("lines check: \{path}: \{pic.w}x\{pic.h}, not \{160 * s}x\{160 * s}")
    return 1
  }
  let at = fn(x : Double, y : Double) {
    pic.rgb((x * s.to_double()).to_int(), (y * s.to_double()).to_int())
  }
  let bad = []
  // the line against the rounded rect 40 under it, row by row over the band they are in; but where the rect, a
  // capsule, eases into its long edges (from 0.3 to 2 of its radius in from either tip, mbui's capsule_ease) and the
  // line's round cap does not
  let mut worst = 0
  let eases = fn(x : Int) {
    let from_tip = @cmp.minimum(x - 16 * s, 104 * s - x).to_double()
    from_tip > 0.3 * 4.0 * s.to_double() && from_tip < 2.0 * 4.0 * s.to_double()
  }
  for y in (12 * s)..<(28 * s) {
    for x in 0..<(160 * s) {
      if eases(x) {
        continue
      }
      let a = pic.rgb(x, y)
      let b = pic.rgb(x, y + 40 * s)
      worst = @cmp.maximum(
        worst,
        @cmp.maximum((a.0 - b.0).abs(), @cmp.maximum((a.1 - b.1).abs(), (a.2 - b.2).abs())),
      )
    }
  }
  if worst > tol {
    bad.push(
      "the line 8 wide is not the rounded rect of its shape: a channel \{worst} apart (at most \{tol})",
    )
  }
  let blue = (0x15, 0x59, 0xC4)
  let white = (0xFF, 0xFF, 0xFF)
  let near = fn(c, want) { near_max(c, want, tol) }
  // the slanted line, (20, 90) to (60, 130), 6 wide: inked along its middle, white 5 off it on either side
  for k in 1..<10 {
    let x = (20 + 4 * k).to_double()
    let y = (90 + 4 * k).to_double()
    if !near(at(x + 0.25, y + 0.25), blue) {
      bad.push(
        "the slanted line is not inked at (\{num_text(x)}, \{num_text(y)}): \{rgb_text(at(x, y))}",
      )
    }
    for sg in [1.0, -1.0] {
      if !near(at(x + sg * 5.0 * 0.7071 + 0.25, y - sg * 5.0 * 0.7071 + 0.25), white) {
        bad.push(
          "the slanted line is inked 5 off its middle at (\{num_text(x)}, \{num_text(y)})",
        )
      }
    }
  }
  // the arc about (120, 120), radius 20, 3 wide, from 3 o'clock through 6, 9 to 12: inked on the circle there, not
  // in the quarter it leaves out, nor at its middle
  let rad = fn(d : Double) { d * @math.PI / 180.0 }
  for deg in [20.0, 90.0, 160.0, 200.0, 250.0] {
    let a = rad(deg)
    let x = 120.0 + 20.0 * @math.cos(a)
    let y = 120.0 + 20.0 * @math.sin(a)
    if !near(at(x, y), blue) {
      bad.push("the arc is not inked at \{num_text(deg)}°: \{rgb_text(at(x, y))}")
    }
  }
  let a = rad(315.0)
  if !near(at(120.0 + 20.0 * @math.cos(a), 120.0 + 20.0 * @math.sin(a)), white) {
    bad.push("the arc is inked in the quarter it leaves out (315°)")
  }
  if !near(at(120.0, 120.0), white) {
    bad.push("the arc's middle is inked")
  }
  // the half drawn line, (20, 150) to (80, 150) of (140, 150)
  if !near(at(50.0, 150.0), blue) {
    bad.push("the half drawn line is not inked halfway along what is drawn of it")
  }
  if !near(at(90.0, 150.0), white) || !near(at(130.0, 150.0), white) {
    bad.push("the half drawn line is inked past its half")
  }
  // the box 20 by 20 at (70, 85) turned 30° clockwise about (70, 85): red where its own points are taken, white
  // just outside its sides (and so where they would be turned the other way)
  let red = (0xFF, 0x3B, 0x30)
  let c = @math.cos(rad(30.0))
  let sn = @math.sin(rad(30.0))
  let turned = fn(u : Double, v : Double) { (70.0 + c * u - sn * v, 85.0 + sn * u + c * v) }
  for u in [3.0, 10.0, 17.0] {
    for v in [3.0, 10.0, 17.0] {
      let (tx, ty) = turned(u, v)
      if !near(at(tx, ty), red) {
        bad.push(
          "the turned box is not drawn at its own (\{num_text(u)}, \{num_text(v)}), turned: (\{tx}, \{ty}) \{rgb_text(at(tx, ty))}",
        )
      }
    }
  }
  for uv in [(-3.0, 10.0), (23.0, 10.0), (10.0, -3.0), (10.0, 23.0), (17.0, -3.0), (-3.0, 17.0)] {
    let (tx, ty) = turned(uv.0, uv.1)
    if !near(at(tx, ty), white) {
      bad.push(
        "the turned box is drawn off its side, at its own (\{num_text(uv.0)}, \{num_text(uv.1)}) turned: (\{tx}, \{ty})",
      )
    }
  }
  if bad.length() > 0 {
    say("lines check: \{path}:\n  " + bad.join("\n  "))
    return 1
  }
  say(
    "lines check: \{path}: the line is the rounded rect of its shape (a channel \{worst} apart at most), the slanted line, the arc, the half line and the turned box drawn where they are",
  )
  0
}

///|
/// (Android) the round page pictured (MBUI_VIEWCHECK=hold: left on the screen once placed): at each of its four
/// corners, just inside its rect but outside its round, the canvas's ground (the view cut there, and its hole as
/// round: no square corner of the page, nothing of what is under the canvas); a little further in, the page. And the
/// two tall pages under it (viewcheck.mbt view_check_tall, view_check_grow: their content told 40,000 points tall, more
/// device pixels, the second once it has loaded): where each is seen as last told, near its top, its middle and its
/// bottom, its band of green, the part of it there
fn views_round(args : Array[String]) -> Int {
  if args.length() != 2 {
    @sys.eprintln("chk views-round LOG PNG")
    return 2
  }
  let mut page : Array[Double]? = None
  // (the tall pages, by id: each as last told)
  let talls : Map[String, Array[Double]] = Map::new()
  for line in text_lines(@sys.read_text(args[0]).unwrap_or("")) {
    match line.find("VIEWTOLD ") {
      Some(i) => {
        let ws = split_ws(line.view(start_offset=i + 9).to_string())
        if ws.length() >= 10 {
          let p = ws[1:10].to_array().map(fn(x) { double_of_signed(x) })
          if p[8] > 0.0 {
            page = Some(p)
          }
          if p[3] >= 40000.0 {
            talls[ws[0]] = p
          }
        }
      }
      None => ()
    }
  }
  let page = match page {
    Some(p) => p
    None => {
      say("views contract (android): no round view told (VIEWTOLD with a radius)")
      return 1
    }
  }
  let pic = match picture(args[1]) {
    Some(p) => p
    None => return 1
  }
  let px = fn(x : Double, y : Double) { pic.rgb(x.to_int(), y.to_int()) }
  let near = fn(a : (Int, Int, Int), b : (Int, Int, Int)) {
    (a.0 - b.0).abs() + (a.1 - b.1).abs() + (a.2 - b.2).abs() <= 24
  }
  let mut x = page[0]
  let mut y = page[1]
  let vw = page[2]
  let vh = page[3]
  let r = page[8]
  let grey = (0x88, 0x88, 0x88)
  // (the picture is the screen's, the app's place its window's: moved by where the window is, found by the page's
  // own straight edges, the middle of its top and of its left, which its round leaves as they are)
  let mut fy = -1
  for j in 0..<pic.h {
    if near(px(x + vw / 2.0, j.to_double()), grey) {
      fy = j
      break
    }
  }
  if fy < 0 {
    say("views contract (android): the page not found in the picture")
    return 1
  }
  let dy = fy.to_double() - y
  let mut fx = -1
  for k in 0..<pic.w {
    if near(px(k.to_double(), y + dy + vh / 2.0), grey) {
      fx = k
      break
    }
  }
  if fx < 0 {
    say("views contract (android): the page not found in the picture")
    return 1
  }
  let dx = fx.to_double() - x
  x = x + dx
  y = y + dy
  let ground = px(x - 4.0, y + vh / 2.0)
  let bad = []
  if !near(px(x + vw / 2.0, y + vh / 2.0), grey) {
    bad.push("the page not shown (its middle \{rgb_text(px(x + vw / 2.0, y + vh / 2.0))})")
  }
  let corners = [
    ("top left", x, y, 1.0, 1.0),
    ("top right", x + vw - 1.0, y, -1.0, 1.0),
    ("bottom left", x, y + vh - 1.0, 1.0, -1.0),
    ("bottom right", x + vw - 1.0, y + vh - 1.0, -1.0, -1.0),
  ]
  for cn in corners {
    let (name, cx, cy, sx, sy) = cn
    let out = px(cx + sx * 2.0, cy + sy * 2.0)
    let inside = px(cx + sx * r, cy + sy * r)
    if !near(out, ground) {
      bad.push(
        "\{name}: \{rgb_text(out)} just inside the rect, outside the round, not the ground \{rgb_text(ground)}",
      )
    }
    if !near(inside, grey) {
      bad.push("\{name}: \{rgb_text(inside)} inside the round, not the page")
    }
  }
  if talls.length() != 2 {
    bad.push("\{talls.length()} tall pages told (VIEWTOLD 40,000 or more tall), not 2")
  }
  for id, t in talls {
    // (where it is seen: its clip, moved as the round page was)
    let green = (0x00, 0xaa, 0x00)
    let mx = (t[4] + t[6]) / 2.0 + dx
    for probe in [("near its top", t[5] + 3.0), ("in its middle", (t[5] + t[7]) / 2.0), ("near its bottom", t[7] - 3.0)] {
      let (name, ty) = probe
      let seen = px(mx, ty + dy)
      if !near(seen, green) {
        bad.push("the tall page \{id} \{name}: \{rgb_text(seen)}, not its band of green \{rgb_text(green)}")
      }
    }
  }
  if bad.length() > 0 {
    say("views contract (android): its round corners, the tall pages: " + bad.join("; "))
    return 1
  }
  say(
    "views contract (android): the page's four corners round (\{num_text(r)} px), the ground outside them, the page inside; each tall page's part seen where it is seen",
  )
  0
}

///|
/// A number as the log writes it: a sign, digits, a point and digits
fn double_of_signed(s : String) -> Double {
  if s.has_prefix("-") {
    -double_of(s.view(start_offset=1).to_string()).unwrap_or(0.0)
  } else {
    double_of(s).unwrap_or(0.0)
  }
}

///|
/// Whether a renderer draws shapes (scene.mbt's kind 11) as they are: the picture of
/// src/kitdemo/gallery/dl_print_wbtest.mbt's shapes_shown (160 by 160 at scale 2, on white) drawn by it. Its squares
/// are filled round their holes and not in them (the nonzero rule with the hole's outline going back, the even-odd
/// one), its line is inked along its middle and not 5 off it, its disc inside its circle and not outside it.
fn shapes(args : Array[String]) -> Int {
  if args.length() != 1 {
    @sys.eprintln("chk shapes PNG")
    return 2
  }
  let path = args[0]
  let pic = match picture(path) {
    Some(p) => p
    None => return 1
  }
  let tol = 3
  let s = 2 // the picture's scale
  if pic.w != 160 * s || pic.h != 160 * s {
    say("shapes check: \{path}: \{pic.w}x\{pic.h}, not \{160 * s}x\{160 * s}")
    return 1
  }
  let at = fn(x : Double, y : Double) {
    pic.rgb((x * s.to_double()).to_int(), (y * s.to_double()).to_int())
  }
  let red = (0xFF, 0x3B, 0x30)
  let blue = (0x15, 0x59, 0xC4)
  let white = (0xFF, 0xFF, 0xFF)
  let bad = []
  let want = fn(what : String, x : Double, y : Double, c : (Int, Int, Int)) {
    if !near_max(at(x, y), c, tol) {
      bad.push("\{what} at (\{num_text(x)}, \{num_text(y)}): \{rgb_text(at(x, y))}, not \{rgb_text(c)}")
    }
  }
  for p in [(15.0, 15.0), (15.0, 40.0), (40.0, 15.0), (65.0, 65.0), (40.0, 25.0)] {
    want("the red square is not filled", p.0, p.1, red)
  }
  for p in [(40.0, 40.0), (33.0, 33.0), (47.0, 47.0), (5.0, 40.0), (75.0, 40.0)] {
    want("the red square is filled in its hole or outside it", p.0, p.1, white)
  }
  for p in [(95.0, 15.0), (95.0, 40.0), (145.0, 65.0), (120.0, 25.0)] {
    want("the blue square (even-odd) is not filled", p.0, p.1, blue)
  }
  for p in [(120.0, 40.0), (113.0, 33.0), (155.0, 40.0)] {
    want("the blue square (even-odd) is filled in its hole or outside it", p.0, p.1, white)
  }
  for p in [(15.0, 100.0), (40.0, 100.0), (70.0, 100.0), (70.0, 125.0), (70.0, 148.0)] {
    want("the line is not inked along its middle", p.0, p.1, blue)
  }
  for p in [(40.0, 105.0), (40.0, 95.0), (65.0, 125.0), (75.0, 125.0)] {
    want("the line is inked 5 off its middle", p.0, p.1, white)
  }
  for p in [(120.0, 125.0), (120.0, 103.0), (98.0, 125.0), (138.0, 140.0)] {
    want("the disc is not filled", p.0, p.1, red)
  }
  for p in [(120.0, 97.0), (148.0, 125.0), (142.0, 147.0)] {
    want("the disc is filled outside its circle", p.0, p.1, white)
  }
  for b in bad {
    say("shapes check: " + b)
  }
  if bad.is_empty() {
    say("shapes check: \{path}: its shapes drawn as they are")
    0
  } else {
    1
  }
}
