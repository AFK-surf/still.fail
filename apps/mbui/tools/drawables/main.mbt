// still.fail's pictures for mbui: this app's vector drawables (apps/mbui/android's res/drawable: still.fail's mark and
// its illustrations, design/brand; the model makers' marks, Slack's and Feishu's), the station glyphs of
// design/station-icons, and the apps' launcher icons (apps/mbui/android: launcher_face on launcher_bg, the middle 72 of
// its 108 as a launcher shows it; still.fail mbui's, still.fail's and youdid.wtf's colours), into
// src/sf/drawable_data.mbt as mbui's @pixels.Vector (path strings), which src/sf/picture.mbt draws.
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
  // the programs a station logs in to (its 登录's rows: web/public/tools)
  "tool_azure", "tool_claude", "tool_cloudflare", "tool_cursor", "tool_devin", "tool_docker", "tool_firebase",
  "tool_github", "tool_google_cloud", "tool_kubernetes", "tool_netlify", "tool_npm", "tool_openai", "tool_python",
  "tool_stripe", "tool_supabase", "tool_terraform", "tool_vercel",
  // the stations' pages (src/sfapp/settings/stations.mbt): a station asleep
  "illus_station_offline", "illus_station_offline_dark",
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
  match root.kids.iter().find_first(fn(e) { e.tag == "vector" || e.tag == "svg" }) {
    Some(v) => v
    None => {
      fail("no <vector> or <svg>")
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
/// An app's icon as a launcher shows it, `name` in the table: its ground (launcher_bg), its mark (launcher_face, in the
/// colours read last), the middle 72 of the 108.
fn launcher(line : (String) -> Unit, name : String, face : String?) -> Unit {
  match face {
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
      write_drawable(line, name, 72.0, 72.0, layers)
    }
    None => fail("no launcher_face.xml")
  }
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
  let own_drawables = @sys.join(repo, "apps/mbui/android/app/src/main/res/drawable")
  let out = StringBuilder()
  let line = fn(s : String) {
    out.write_string(s)
    out.write_char('\n')
  }
  line("// Generated by scripts/drawables from apps/mbui/android (res/drawable, its launcher) and design/station-icons: do not edit.")
  line("")
  line("///|")
  line("let drawables : Map[String, @pixels.Vector] = {")
  for name in drawables {
    let xml = match @sys.read_text(@sys.join(own_drawables, name + ".xml")) {
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
  // the apps' icons, as a launcher shows them: its ground, its mark, the middle 72 of the 108; still.fail mbui's
  // (launcher_icon), still.fail's and youdid.wtf's (their colours over its)
  let src = @sys.join(repo, "apps/mbui/android/app/src")
  for app in [("launcher_icon", ""), ("launcher_icon_stable", "stable"), ("launcher_icon_beta", "beta")] {
    read_colors(@sys.read_text(@sys.join(src, "main/res/values/launcher.xml")).unwrap_or(""))
    if app.1 != "" {
      read_colors(@sys.read_text(@sys.join(src, app.1 + "/res/values/launcher.xml")).unwrap_or(""))
    }
    // an app's own face where it has one (youdid.wtf's, under its tape), else the one they share
    let own = if app.1 == "" { None } else { @sys.read_text(@sys.join(src, app.1 + "/res/drawable/launcher_face.xml")) }
    let face = match own {
      Some(_) => own
      None => @sys.read_text(@sys.join(src, "main/res/drawable/launcher_face.xml"))
    }
    launcher(line, app.0, face)
  }
  line("}")
  line("")
  let dir = @sys.join(repo, "design/station-icons")
  let manifest = @json.parse(@sys.read_text(@sys.join(dir, "manifest.json")).unwrap_or("")) catch {
    _ => { fail("no station icon manifest"); return }
  }
  guard manifest is Array(items) else { fail("station icon manifest is not an array"); return }
  line("///|")
  line("/// Station SVGs: emoji|stroked paths|filled paths, read by glyph_paths.")
  line("let station_glyphs : Map[String, String] = {")
  for item in items {
    guard item is Object(m) else { fail("invalid station icon entry"); return }
    guard m.get("name") is Some(String(name)) else { fail("station icon has no name"); return }
    guard m.get("emoji") is Some(String(emoji)) else {
      fail("invalid station icon manifest entry"); return
    }
    let source = @sys.read_text(@sys.join(dir, name + ".svg")).unwrap_or("")
    let (lines, dots) = svg_glyph(source)
    line("  \{mbt_str(name)}: \{mbt_str(emoji + "|" + lines.join(";") + "|" + dots.join(";"))},")
  }
  line("}")
  @sys.out(out.to_string())
}

///|
/// The station SVG vocabulary is the same as tools/icons: paths, circles and rounded rectangles.
fn svg_glyph(source : String) -> (Array[String], Array[String]) {
  let root = parse(source)
  let lines = []
  let dots = []
  for el in root.kids {
    // Reuse the drawable number reader on SVG attributes.
    let numeric : El = { tag: el.tag, attrs: {}, kids: [] }
    for k, v in el.attrs { numeric.attrs["android:" + k] = v }
    let d = match el.tag {
      "path" => el.attrs.get("d").unwrap_or("")
      "circle" => {
        let x = num(numeric, "cx", 0.0)
        let y = num(numeric, "cy", 0.0)
        let r = num(numeric, "r", 0.0)
        "M\{x - r} \{y}a\{r} \{r} 0 1 0 \{2.0 * r} 0a\{r} \{r} 0 1 0 \{-2.0 * r} 0Z"
      }
      "rect" => {
        let x = num(numeric, "x", 0.0)
        let y = num(numeric, "y", 0.0)
        let w = num(numeric, "width", 0.0)
        let h = num(numeric, "height", 0.0)
        let r = num(numeric, "rx", 0.0)
        "M\{x + r} \{y}h\{w - 2.0 * r}a\{r} \{r} 0 0 1 \{r} \{r}v\{h - 2.0 * r}a\{r} \{r} 0 0 1 \{-r} \{r}h\{2.0 * r - w}a\{r} \{r} 0 0 1 \{-r} \{-r}v\{2.0 * r - h}a\{r} \{r} 0 0 1 \{r} \{-r}Z"
      }
      _ => { fail("unsupported station SVG element: " + el.tag); "" }
    }
    if el.attrs.get("fill").unwrap_or(root.attrs.get("fill").unwrap_or("black")) != "none" {
      dots.push(d)
    }
    if el.attrs.get("stroke").unwrap_or(root.attrs.get("stroke").unwrap_or("none")) != "none" {
      lines.push(d)
    }
  }
  (lines, dots)
}
