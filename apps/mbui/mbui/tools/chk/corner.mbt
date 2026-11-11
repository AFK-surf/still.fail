// The renderers' corners from one copy: src/host/corner.sl into src/host/corner_sl.h and web/host.js

///|
let corner_begin : String = "// corner.sl begin (scripts/chk corner-sl: not edited here)"

///|
let corner_end : String = "// corner.sl end"

///|
fn corner_header(lines : Array[String]) -> String {
  let out = [
    "// src/host/corner.sl as a C string (scripts/chk corner-sl makes it: edit corner.sl, then run it). The shaders",
    "// write float2; GLSL's take it with `#define float2 vec2` and `#define float4 vec4` before it.",
    "#define MB_CORNER_SL \\",
  ]
  for l in lines {
    let esc = l.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
    out.push("  \"\{esc}\\n\" \\")
  }
  out.push("  \"\"")
  out.join("\n") + "\n"
}

///|
/// Where w is in s from `from` on, -1 when not
fn find_in(s : Array[Char], w : String, from : Int) -> Int {
  let cs = w.to_array()
  let mut i = from
  while i + cs.length() <= s.length() {
    let mut ok = true
    for k, c in cs {
      if s[i + k] != c {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
    i += 1
  }
  -1
}

///|
/// The last c in s before `before`, -1 when none
fn rfind_char(s : Array[Char], c : Char, before : Int) -> Int {
  let mut i = before - 1
  while i >= 0 && s[i] != c {
    i -= 1
  }
  i
}

///|
fn chars(s : Array[Char], i : Int, j : Int) -> String {
  String::from_array(s[i:j])
}

///|
fn corner_web(text : String, lines : Array[String]) -> String? {
  let t = text.to_array()
  let a = find_in(t, corner_begin, 0)
  if a < 0 {
    return None
  }
  let b = find_in(t, corner_end, a)
  if b < 0 {
    return None
  }
  let start = rfind_char(t, '\n', a) + 1
  let indent = chars(t, start, a)
  let body = StringBuilder()
  for l in lines {
    if l == "" {
      body.write_string("\n")
    } else {
      body.write_string(indent + l + "\n")
    }
  }
  Some(
    chars(t, 0, a + corner_begin.to_array().length()) +
    "\n" +
    indent +
    "#define float2 vec2\n" +
    indent +
    "#define float4 vec4\n" +
    body.to_string() +
    indent +
    chars(t, b, t.length()),
  )
}

///|
/// The numbers written in `s`, in order: what is no part of a name, comments left out.
fn numbers_in(s : String) -> Array[String] {
  let t = s.to_array()
  let out = []
  let mut i = 0
  while i < t.length() {
    let c = t[i]
    if c == '/' && i + 1 < t.length() && t[i + 1] == '/' {
      while i < t.length() && t[i] != '\n' {
        i += 1
      }
    } else if c >= '0' && c <= '9' {
      let at = i
      while i < t.length() && ((t[i] >= '0' && t[i] <= '9') || t[i] == '.') {
        i += 1
      }
      out.push(chars(t, at, i))
    } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
      while i < t.length() &&
        ((t[i] >= 'a' && t[i] <= 'z') || (t[i] >= 'A' && t[i] <= 'Z') || (t[i] >= '0' && t[i] <= '9') || t[i] == '_') {
        i += 1
      }
    } else {
      i += 1
    }
  }
  out
}

///|
/// The text in `s` from `head` to `tail` after it, "" when not there
fn span_of(s : String, head : String, tail : String) -> String {
  let t = s.to_array()
  let a = find_in(t, head, 0)
  if a < 0 {
    return ""
  }
  let b = find_in(t, tail, a)
  if b < 0 {
    ""
  } else {
    chars(t, a + head.to_array().length(), b)
  }
}

///|
/// What smooth.mbt and corner.sl each write out (two languages, no way to share them) whose numbers differ, by name.
fn numbers_unlike(mbt : String, sl : String) -> Array[String] {
  let bad = []
  let pairs = [
    ("smoothness", "pub fn smoothness(", "\n}\n", "float mb_smoothness(", "\n}\n"),
    ("capsule_room", "fn capsule_room(", "\n}\n", "float mb_capsule_room(", "\n}\n"),
    ("capsule_ease", "fn capsule_ease(", "\n}\n", "float mb_capsule_ease(", "\n}\n"),
    ("smooth_a", "fn smooth_a(", "\n}\n", "float A =", ";"),
    ("smooth_b", "fn smooth_b(", "\n}\n", "float B =", ";"),
  ]
  for p in pairs {
    let a = numbers_in(span_of(mbt, p.1, p.2))
    let b = numbers_in(span_of(sl, p.3, p.4))
    if a.length() == 0 || a != b {
      bad.push(p.0)
    }
  }
  bad
}

///|
fn corner_sl(args : Array[String]) -> Int {
  let r = root()
  let src_path = @sys.join(r, "src/host/corner.sl")
  let header_path = @sys.join(r, "src/host/corner_sl.h")
  let web_path = @sys.join(r, "web/host.js")
  let src = match @sys.read_text(src_path) {
    Some(s) => s
    None => {
      say("chk: no src/host/corner.sl")
      return 1
    }
  }
  let mut body = src
  while body.has_suffix("\n") {
    body = body.exact_view(end=body.length() - 1).to_owned()
  }
  let lines = body.split("\n").map(fn(l) { l.to_owned() }).to_array()
  // (web/host.js holds it in a template literal: no backquote, no ${)
  for i, l in lines {
    if l.contains("`") || l.contains("${") {
      say(
        "src/host/corner.sl: a backquote or ${ on line \{i + 1}, which would end web/host.js's shader",
      )
      return 1
    }
  }
  let want_h = corner_header(lines)
  let js = @sys.read_text(web_path).unwrap_or("")
  let want_js = match corner_web(js, lines) {
    Some(w) => w
    None => {
      say("web/host.js: no corner.sl marks")
      return 1
    }
  }
  if args.contains("--check") {
    let bad = []
    if @sys.read_text(header_path) != Some(want_h) {
      bad.push("src/host/corner_sl.h")
    }
    if js != want_js {
      bad.push("web/host.js")
    }
    let unlike = numbers_unlike(
      @sys.read_text(@sys.join(r, "src/paint/smooth.mbt")).unwrap_or(""),
      @sys.read_text(src_path).unwrap_or(""),
    )
    if unlike.length() > 0 {
      say("smooth.mbt and corner.sl differ in the numbers of: " + unlike.join(", "))
      return 1
    }
    if bad.length() > 0 {
      say(
        "not what src/host/corner.sl makes (run scripts/chk corner-sl): " +
        bad.join(", "),
      )
      return 1
    }
    say("corner.sl: the renderers' copies are its")
    return 0
  }
  let _ = @sys.write_text(header_path, want_h)
  let _ = @sys.write_text(web_path, want_js)
  0
}
