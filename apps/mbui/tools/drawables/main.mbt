// still.fail's pictures for mbui: this app's vector drawables, with legacy marks and illustrations from
// apps/android/shared/src/main/res/drawable (the model makers' marks, Slack's, still.fail's own mark) and the
// station glyphs of its ui/Icons.kt (StationIcons), and this app's own launcher icon (apps/mbui/android: launcher_face
// on launcher_bg, the middle 72 of its 108 as a launcher shows it), into src/sf/drawable_data.mbt as mbui's
// @pixels.Vector (path strings), which src/sf/picture.mbt draws.
//
//   scripts/drawables <repository> > src/sf/drawable_data.mbt
//
// Each drawable is its viewport and its paths in order, each with its fill (0xRRGGBBAA, 0 none), its stroke and stroke
// width, the even-odd rule, and the transform of the groups it is in (scale, then translate).

///|
/// What Home, sign-in and the station marks use.
let drawables : Array[String] = [
  "maker_anthropic", "maker_openai", "maker_deepseek", "maker_qwen", "maker_zhipu", "maker_gemini", "maker_kimi", "maker_minimax",
  "maker_xai", "maker_mistral", "maker_xiaomi", "maker_ant_ling", "maker_openrouter", "maker_vercel", "maker_cloudflare",
  "maker_azure", "maker_groq", "maker_together", "maker_fireworks", "maker_cerebras", "maker_huggingface", "maker_nvidia",
  "maker_baseten", "maker_dsh", "maker_cursor", "maker_devin", "maker_hermes", "slack", "feishu", "stillfail_mark", "stillfail_mark_dark",
  "illus_sign_in", "illus_sign_in_dark", "illus_new_chat", "illus_new_chat_dark", "illus_no_station", "illus_no_station_dark",
  "illus_no_profile", "illus_no_profile_dark",
  // the stations' pages (src/sfapp/settings/stations.mbt): the buddy's faces, a station asleep
  "buddy_idle", "buddy_idle_dark", "buddy_working", "buddy_working_dark", "buddy_offline", "buddy_offline_dark", "illus_station_offline",
  "illus_station_offline_dark",
]

///|
/// An element of a drawable's XML: its tag, its attributes (as written: android:pathData), what is in it.
priv struct El {
  tag : String
  attrs : Map[String, String]
  kids : Array[El]
}

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("drawables: " + why)
  @sys.exit(1)
}

///|
fn unescape(s : String) -> String {
  s.replace_all(old="&lt;", new="<").replace_all(old="&gt;", new=">").replace_all(old="&quot;", new="\"").replace_all(old="&apos;", new="'").replace_all(
    old="&amp;",
    new="&",
  )
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\n' || c == '\t' || c == '\r'
}

///|
/// The XML's root element: its elements and their attributes, what else it has (its declaration, comments, words)
/// passed over.
fn parse(xml : String) -> El {
  let cs = xml.to_array()
  let n = cs.length()
  let root : El = { tag: "", attrs: {}, kids: [] }
  let stack = [root]
  let mut i = 0
  let starts = fn(at : Int, s : String) {
    let t = s.to_array()
    if at + t.length() > n {
      return false
    }
    for k in 0..<t.length() {
      if cs[at + k] != t[k] {
        return false
      }
    }
    true
  }
  let find = fn(at : Int, s : String) {
    let mut k = at
    while k < n && !starts(k, s) {
      k = k + 1
    }
    k
  }
  while i < n {
    if cs[i] != '<' {
      i = i + 1
      continue
    }
    if starts(i, "<!--") {
      i = find(i, "-->") + 3
    } else if starts(i, "<?") {
      i = find(i, "?>") + 2
    } else if starts(i, "</") {
      i = find(i, ">") + 1
      if stack.length() > 1 {
        stack.pop() |> ignore
      }
    } else {
      // <tag a="v" …> or …/>
      let mut k = i + 1
      let name = StringBuilder()
      while k < n && !is_space(cs[k]) && cs[k] != '>' && cs[k] != '/' {
        name.write_char(cs[k])
        k = k + 1
      }
      let el : El = { tag: name.to_string(), attrs: {}, kids: [] }
      let mut closed = false
      while k < n && cs[k] != '>' {
        if cs[k] == '/' {
          closed = true
          k = k + 1
        } else if is_space(cs[k]) {
          k = k + 1
        } else {
          let key = StringBuilder()
          while k < n && cs[k] != '=' && !is_space(cs[k]) && cs[k] != '>' {
            key.write_char(cs[k])
            k = k + 1
          }
          while k < n && cs[k] != '"' && cs[k] != '\'' && cs[k] != '>' {
            k = k + 1
          }
          if k < n && (cs[k] == '"' || cs[k] == '\'') {
            let q = cs[k]
            k = k + 1
            let v = StringBuilder()
            while k < n && cs[k] != q {
              v.write_char(cs[k])
              k = k + 1
            }
            k = k + 1
            el.attrs[key.to_string()] = unescape(v.to_string())
          }
        }
      }
      i = k + 1
      stack[stack.length() - 1].kids.push(el)
      if !closed {
        stack.push(el)
      }
    }
  }
  match root.kids.iter().find_first(fn(e) { e.tag == "vector" }) {
    Some(v) => v
    None => {
      fail("no <vector>")
      root
    }
  }
}

///|
fn attr(el : El, name : String) -> String? {
  el.attrs.get("android:" + name)
}

///|
fn num(el : El, name : String, default : Double) -> Double {
  match attr(el, name) {
    Some(v) => {
      // (a number as JSON writes one: what Android's attributes are)
      let j = @json.parse(if v.has_prefix(".") { "0" + v } else if v.has_prefix("-.") { "-0" + v.view(start_offset=1).to_owned() } else { v }) catch {
        _ => Json::null()
      }
      match j {
        Number(n, ..) => n
        _ => {
          fail("not a number: \{name}=\{v}")
          default
        }
      }
    }
    None => default
  }
}

///|
fn hex(s : String) -> Int64 {
  let mut v = 0L
  for c in s {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - 48
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 87
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 55
    } else {
      fail("not a colour's digit: \{c}")
      0
    }
    v = v * 16L + d.to_int64()
  }
  v
}

///|
/// The colours named in apps/mbui/android's res/values/launcher.xml (`@color/name`), as written.
// kept across runs: read once as the tool starts (main), then only read
let named_colors : Map[String, String] = {}

///|
/// The `<color name="…">#…</color>` of a resources file.
fn read_colors(xml : String) -> Unit {
  for part in xml.split("<color name=\"") {
    match part.find("\">") {
      Some(i) => {
        let name = part.view(end_offset=i).to_owned()
        let rest = part.view(start_offset=i + 2)
        match rest.find("<") {
          Some(j) => named_colors[name] = rest.view(end_offset=j).to_owned()
          None => ()
        }
      }
      None => ()
    }
  }
}

///|
/// A colour as written (#RRGGBB, #AARRGGBB, or one named, @color/name) as 0xRRGGBBAA; none or transparent 0.
fn color(v : String?) -> Int64 {
  match v {
    None => 0L
    Some("@android:color/transparent") => 0L
    Some(s) if s.has_prefix("@color/") =>
      match named_colors.get(s.view(start_offset=7).to_owned()) {
        Some(c) => color(Some(c))
        None => {
          fail("colour \{s}")
          0L
        }
      }
    Some(s) => {
      let h = if s.has_prefix("#") { s.view(start_offset=1).to_owned() } else { s }
      if h.length() == 6 {
        hex(h + "FF")
      } else if h.length() == 8 {
        hex(h.view(start_offset=2).to_owned() + h.view(end_offset=2).to_owned())
      } else {
        fail("colour \{s}")
        0L
      }
    }
  }
}

///|
priv struct Layer {
  d : String
  fill : Int64
  stroke : Int64
  width : Double
  even_odd : Bool
  sx : Double
  sy : Double
  tx : Double
  ty : Double
}

///|
/// Its paths, in order, each with the transform of the groups it is in: p' = (p · g_s + g_t) · s + t.
fn walk(el : El, sx : Double, sy : Double, tx : Double, ty : Double, out : Array[Layer]) -> Unit {
  for ch in el.kids {
    if ch.tag == "group" {
      if attr(ch, "rotation") is Some(_) || attr(ch, "pivotX") is Some(_) || attr(ch, "pivotY") is Some(_) {
        fail("a group turned or pivoted: not handled")
      }
      let gsx = num(ch, "scaleX", 1.0)
      let gsy = num(ch, "scaleY", 1.0)
      let gtx = num(ch, "translateX", 0.0)
      let gty = num(ch, "translateY", 0.0)
      walk(ch, sx * gsx, sy * gsy, gtx * sx + tx, gty * sy + ty, out)
    } else if ch.tag == "path" {
      let d = attr(ch, "pathData").unwrap_or("")
      out.push({
        d: d.split(" ").flat_map(fn(w) { w.split("\n") }).flat_map(fn(w) { w.split("\t") }).filter(fn(w) { w != "" }).map(fn(w) {
          w.to_owned()
        }).to_array().join(" "),
        fill: color(attr(ch, "fillColor")),
        stroke: color(attr(ch, "strokeColor")),
        width: num(ch, "strokeWidth", 0.0),
        even_odd: attr(ch, "fillType") == Some("evenOdd"),
        sx,
        sy,
        tx,
        ty,
      })
    }
  }
}

///|
/// A number as the generated file writes it: to 4 places, its zeros after the point dropped, a point always.
fn fmt(v : Double) -> String {
  let n = (v.abs() * 10000.0).round().to_int64()
  let ip = n / 10000L
  let fp = n % 10000L
  let s = StringBuilder()
  if v < 0.0 && n != 0L {
    s.write_char('-')
  }
  s.write_string(ip.to_string())
  s.write_char('.')
  if fp == 0L {
    s.write_char('0')
  } else {
    let mut f = fp.to_string()
    while f.length() < 4 {
      f = "0" + f
    }
    while f.has_suffix("0") {
      f = f.view(end_offset=f.length() - 1).to_owned()
    }
    s.write_string(f)
  }
  s.to_string()
}

///|
fn mbt_str(s : String) -> String {
  "\"" + s.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") + "\""
}

///|
fn hex8(v : Int64) -> String {
  let digits = "0123456789ABCDEF"
  let s = StringBuilder()
  for k = 7; k >= 0; k = k - 1 {
    s.write_char(digits[((v >> (k * 4)) & 15L).to_int()].unsafe_to_char())
  }
  s.to_string()
}

///|
/// A drawable as the generated table has it: its viewport, its paths in order.
fn write_drawable(line : (String) -> Unit, name : String, w : Double, h : Double, layers : Array[Layer]) -> Unit {
  line("  \"\{name}\": {")
  line("    w: \{fmt(w)},")
  line("    h: \{fmt(h)},")
  line("    layers: [")
  for l in layers {
    line("      {")
    line("        d: \{mbt_str(l.d)},")
    line("        fill: 0x\{hex8(l.fill)}L,")
    line("        stroke: 0x\{hex8(l.stroke)}L,")
    line("        width: \{fmt(l.width)},")
    line("        even_odd: \{if l.even_odd { "true" } else { "false" }},")
    line("        sx: \{fmt(l.sx)},")
    line("        sy: \{fmt(l.sy)},")
    line("        tx: \{fmt(l.tx)},")
    line("        ty: \{fmt(l.ty)},")
    line("      },")
  }
  line("    ],")
  line("  },")
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    @sys.eprintln("scripts/drawables <repository> > src/sf/drawable_data.mbt")
    @sys.exit(2)
    return
  }
  let repo = argv[1]
  let res = @sys.join(repo, "apps/android/shared/src/main/res/drawable")
  let own_drawables = @sys.join(repo, "apps/mbui/android/app/src/main/res/drawable")
  let icons = @sys.join(repo, "apps/android/shared/src/main/kotlin/fail/still/android/ui/Icons.kt")
  let out = StringBuilder()
  let line = fn(s : String) {
    out.write_string(s)
    out.write_char('\n')
  }
  line("// Generated by scripts/drawables from apps/android (res/drawable, ui/Icons.kt) and apps/mbui/android (its launcher): do not edit.")
  line("")
  line("///|")
  line("let drawables : Map[String, @pixels.Vector] = {")
  for name in drawables {
    // New marks belong to this app; the frozen Kotlin app supplies the legacy artwork only.
    let source = match @sys.read_text(@sys.join(own_drawables, name + ".xml")) {
      Some(x) => Some(x)
      None => @sys.read_text(@sys.join(res, name + ".xml"))
    }
    let xml = match source {
      Some(x) => x
      None => {
        fail("no \{name}.xml")
        ""
      }
    }
    let root = parse(xml)
    let layers = []
    walk(root, 1.0, 1.0, 0.0, 0.0, layers)
    write_drawable(line, name, num(root, "viewportWidth", 24.0), num(root, "viewportHeight", 24.0), layers)
  }
  // this app's own icon, as a launcher shows it: its ground, its face, the middle 72 of the 108
  let own = @sys.join(repo, "apps/mbui/android/app/src/main/res")
  read_colors(@sys.read_text(@sys.join(own, "values/launcher.xml")).unwrap_or(""))
  match @sys.read_text(@sys.join(own, "drawable/launcher_face.xml")) {
    Some(xml) => {
      let layers : Array[Layer] = [
        {
          d: "M0 0H108V108H0Z",
          fill: color(Some("@color/launcher_bg")),
          stroke: 0L,
          width: 0.0,
          even_odd: false,
          sx: 1.0,
          sy: 1.0,
          tx: -18.0,
          ty: -18.0,
        },
      ]
      walk(parse(xml), 1.0, 1.0, -18.0, -18.0, layers)
      write_drawable(line, "launcher_icon", 72.0, 72.0, layers)
    }
    None => fail("no launcher_face.xml")
  }
  line("}")
  line("")
  // StationGlyph("desktop", "🖥️", "words", icon("desktop", listOf("…", "…"), listOf("…")))
  let text = @sys.read_text(icons).unwrap_or("")
  let body = match text.find("object StationIcons") {
    Some(i) => text.view(start_offset=i).to_owned()
    None => {
      fail("Icons.kt has no StationIcons")
      ""
    }
  }
  let glyph = @re.Regex::new(
    "StationGlyph\\(\"([^\"]+)\", \"([^\"]*)\", \"[^\"]*\", icon\\(\"[^\"]+\", listOf\\(((?:\"[^\"]*\"(?:, )?)*)\\), listOf\\(((?:\"[^\"]*\"(?:, )?)*)\\)\\)\\)",
  ) catch {
    _ => {
      fail("the glyphs' pattern")
      return
    }
  }
  let quoted = @re.Regex::new("\"([^\"]*)\"") catch {
    _ => {
      fail("the quoted pattern")
      return
    }
  }
  let found = glyph.find_all(body)
  let said = body.split("StationGlyph(\"").count() - 1
  if found.length() != said {
    fail("Icons.kt StationIcons: \{found.length()} glyphs read of \{said}")
  }
  line("///|")
  line("/// The station glyphs (StationIcons): each its emoji, its lines (1.75 strokes) and its dots (fills), as one text:")
  line("/// \"emoji|line;line|dot;dot\", read when it is drawn (glyph_paths).")
  // (text, not a tuple of arrays: as those, 570 KB of start-up code compiled on every build, 2026-10-24)
  line("let station_glyphs : Map[String, String] = {")
  for m in found {
    let ls = quoted.findall(m.get(3))
    let ds = quoted.findall(m.get(4))
    line("  \{mbt_str(m.get(1))}: \{mbt_str(m.get(2) + "|" + ls.join(";") + "|" + ds.join(";"))},")
  }
  line("}")
  @sys.out(out.to_string())
}
