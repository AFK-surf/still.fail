// still.fail's own icons (design/icons, drawn for still.fail by astra) for the web: web/ui/src/icons.tsx (React
// components), with the icons a station can have (design/station-icons, in the order of its manifest.json, each with
// the emoji kept beside it for older clients and the words it is found by). The SVGs are the one source. (Once
// scripts/icons.py, which wrote the Kotlin app's ui/Icons.kt too: that app is frozen since 2026-10-23, and the mbui
// app draws its icons from design/icons itself.)
//
//   scripts/icons <repository>            writes web/ui/src/icons.tsx
//   scripts/icons <repository> --check    fails, naming it, when the file is not what the SVGs make

///|
/// One of an icon's drawn elements: its tag (path, circle or rect), its attributes in their order, and whether it is
/// filled (a dot) rather than stroked.
priv struct El {
  tag : String
  attrs : Array[(String, String)]
  filled : Bool
}

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("icons: " + why)
  @sys.exit(1)
}

///|
/// Where `sub` is in `s` from `from` on, or -1.
fn index_of(s : String, sub : String, from : Int) -> Int {
  let n = s.length()
  let m = sub.length()
  let mut i = from
  while i + m <= n {
    let mut j = 0
    while j < m && s.unsafe_charcode_at(i + j) == sub.unsafe_charcode_at(j) {
      j += 1
    }
    if j == m {
      return i
    }
    i += 1
  }
  -1
}

///|
fn is_space(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

///|
fn is_name(c : Int) -> Bool {
  (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x3A || c == 0x5F
}

///|
/// An SVG's drawn elements in order (its <svg> and comments passed over); one of another kind fails it.
fn elements(name : String, text : String) -> Array[El] {
  let out : Array[El] = []
  let n = text.length()
  let mut i = 0
  while i < n {
    let lt = index_of(text, "<", i)
    if lt < 0 {
      break
    }
    if index_of(text, "<!--", lt) == lt {
      let end = index_of(text, "-->", lt + 4)
      if end < 0 {
        fail("\{name}: a comment not closed")
        return out
      }
      i = end + 3
      continue
    }
    let next = if lt + 1 < n { text.unsafe_charcode_at(lt + 1) } else { 0 }
    if next == 0x2F || next == 0x3F || next == 0x21 {
      // a closing tag, the XML declaration, a doctype
      let gt = index_of(text, ">", lt)
      i = if gt < 0 { n } else { gt + 1 }
      continue
    }
    let mut j = lt + 1
    while j < n && is_name(text.unsafe_charcode_at(j)) {
      j += 1
    }
    let tag = text.unsafe_substring(start=lt + 1, end=j)
    let attrs : Array[(String, String)] = []
    while true {
      while j < n && is_space(text.unsafe_charcode_at(j)) {
        j += 1
      }
      if j >= n {
        fail("\{name}: <\{tag}> not closed")
        return out
      }
      let c = text.unsafe_charcode_at(j)
      if c == 0x3E || c == 0x2F {
        break
      }
      let k0 = j
      while j < n && is_name(text.unsafe_charcode_at(j)) {
        j += 1
      }
      let key = text.unsafe_substring(start=k0, end=j)
      if key == "" || j >= n || text.unsafe_charcode_at(j) != 0x3D {
        fail("\{name}: <\{tag}>'s attributes are not as an SVG has them")
        return out
      }
      j += 1
      let q = if j < n { text.unsafe_charcode_at(j) } else { 0 }
      if q != 0x22 && q != 0x27 {
        fail("\{name}: <\{tag}> \{key}= not quoted")
        return out
      }
      let close = index_of(text, if q == 0x22 { "\"" } else { "'" }, j + 1)
      if close < 0 {
        fail("\{name}: <\{tag}> \{key} not closed")
        return out
      }
      attrs.push((key, text.unsafe_substring(start=j + 1, end=close)))
      j = close + 1
    }
    let gt = index_of(text, ">", j)
    i = if gt < 0 { n } else { gt + 1 }
    if tag == "svg" {
      continue
    }
    if tag != "path" && tag != "circle" && tag != "rect" {
      fail("\{name}: <\{tag}> is not drawn here")
      return out
    }
    let filled = attrs.iter().any(fn(a) { a.0 == "fill" && a.1 == "currentColor" })
    out.push({ tag, attrs, filled })
  }
  out
}

///|
/// The element as JSX: what draws it (its path, centre, radius, box, corners), filled in the colour it sits in when
/// it is a dot.
fn jsx(e : El) -> String {
  let keep = ["d", "cx", "cy", "r", "x", "y", "width", "height", "rx", "ry"]
  let parts = e.attrs.filter(fn(a) { keep.contains(a.0) }).map(fn(a) { "\{a.0}=\"\{a.1}\"" })
  let mut attrs = parts.join(" ")
  if e.filled {
    attrs = attrs + " fill=\"currentColor\" stroke=\"none\""
  }
  "<\{e.tag} \{attrs} />"
}

///|
/// `agent-reply` as `AgentReply`.
fn pascal(name : String) -> String {
  let out = StringBuilder()
  for part in name.split("-") {
    let p = part.to_owned()
    for i, c in p {
      let code = c.to_int()
      if i == 0 && code >= 0x61 && code <= 0x7A {
        out.write_char(Int::unsafe_to_char(code - 32))
      } else if i > 0 && code >= 0x41 && code <= 0x5A {
        out.write_char(Int::unsafe_to_char(code + 32))
      } else {
        out.write_char(c)
      }
    }
  }
  out.to_string()
}

///|
/// Small letters of ASCII's (what the picker matches words against).
fn lower(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    let code = c.to_int()
    out.write_char(if code >= 0x41 && code <= 0x5A { Int::unsafe_to_char(code + 32) } else { c })
  }
  out.to_string()
}

///|
fn text_of(v : Json?) -> String {
  match v {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// The file the SVGs make.
fn web(icons : Array[(String, Array[El])], stations : Array[(String, String, Array[El], String)]) -> String {
  let lines : Array[String] = [
    "// Generated by apps/mbui/scripts/icons (tools/icons) from design/icons (still.fail's own icons, drawn for it by astra): do not edit.",
    "import type { SVGProps } from \"react\";", "", "/** An icon's props: its size (px), its line's weight, and whatever an <svg> takes. */",
    "export type IconProps = Omit<SVGProps<SVGSVGElement>, \"ref\"> & { size?: number | string; strokeWidth?: number | string };",
    "", "export function Svg({ size = 24, strokeWidth = 1.75, children, ...rest }: IconProps & { children: React.ReactNode }) {",
    "  return (", "    <svg xmlns=\"http://www.w3.org/2000/svg\" width={size} height={size} viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\"",
    "      strokeWidth={strokeWidth} strokeLinecap=\"round\" strokeLinejoin=\"round\" aria-hidden=\"true\" {...rest}>",
    "      {children}", "    </svg>", "  );", "}", "",
  ]
  for icon in icons {
    let (name, els) = icon
    lines.push("export function \{pascal(name)}(props: IconProps) {")
    lines.push("  return <Svg {...props}>\{els.map(jsx).join("")}</Svg>;")
    lines.push("}")
    lines.push("")
  }
  lines.push("/** Every icon by its name in design/icons, as the core names them (activity rows). */")
  lines.push("export const ICONS: Record<string, (props: IconProps) => React.JSX.Element> = {")
  for icon in icons {
    lines.push("  \"\{icon.0}\": \{pascal(icon.0)},")
  }
  lines.push("};")
  lines.push("")
  for s in stations {
    let (name, _, els, _) = s
    lines.push("function Station\{pascal(name)}(props: IconProps) {")
    lines.push("  return <Svg {...props}>\{els.map(jsx).join("")}</Svg>;")
    lines.push("}")
    lines.push("")
  }
  lines.push(
    "/** The icons a station can have (design/station-icons), in the picker's order, each with the emoji kept beside it for older clients and the words it is found by. */",
  )
  lines.push(
    "export const STATION_ICONS: readonly { emoji: string; name: string; words: string; Icon: (props: IconProps) => React.JSX.Element }[] = [",
  )
  for s in stations {
    let (name, emoji, _, found) = s
    lines.push("  { emoji: \"\{emoji}\", name: \"\{name}\", words: \"\{found}\", Icon: Station\{pascal(name)} },")
  }
  lines.push("];")
  lines.push("")
  lines.join("\n")
}

///|
/// `a` against `b` a character at a time, a name that is the other's start first.
fn lexical(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let d = a.unsafe_charcode_at(i) - b.unsafe_charcode_at(i)
    if d != 0 {
      return d
    }
  }
  a.length() - b.length()
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    @sys.eprintln("scripts/icons <repository> [--check]")
    @sys.exit(2)
    return
  }
  let repo = argv[1]
  let check = argv.contains("--check")
  let source = @sys.join(repo, "design/icons")
  let names = @sys.list_dir(source).filter(fn(n) { n.has_suffix(".svg") })
  // (by the name's characters in turn, as a file's name sorts: String's own order puts the shorter first)
  names.sort_by(lexical)
  let icons : Array[(String, Array[El])] = []
  for n in names {
    let stem = n.unsafe_substring(start=0, end=n.length() - 4)
    icons.push((stem, elements(n, @sys.read_text(@sys.join(source, n)).unwrap_or(""))))
  }
  let station_dir = @sys.join(repo, "design/station-icons")
  let manifest = @sys.read_text(@sys.join(station_dir, "manifest.json")).unwrap_or("")
  let stations : Array[(String, String, Array[El], String)] = []
  match (try Some(@json.parse(manifest)) catch { _ => None }) {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(m) => {
            let name = text_of(m.get("name"))
            let words = lower(name.replace_all(old="-", new=" ") + " " + text_of(m.get("zh")))
            let file = name + ".svg"
            stations.push(
              (name, text_of(m.get("emoji")), elements(file, @sys.read_text(@sys.join(station_dir, file)).unwrap_or("")), words),
            )
          }
          _ => fail("design/station-icons/manifest.json: an entry not an object")
        }
      }
    _ => fail("design/station-icons/manifest.json is not a JSON array")
  }
  let text = web(icons, stations)
  let out = @sys.join(repo, "web/ui/src/icons.tsx")
  if check {
    if @sys.read_text(out) != Some(text) {
      fail("icons are not what design/icons makes: run apps/mbui/scripts/icons <repository> (web/ui/src/icons.tsx)")
    }
    return
  }
  if !@sys.write_text(out, text) {
    fail("\{out} not written")
  }
}
