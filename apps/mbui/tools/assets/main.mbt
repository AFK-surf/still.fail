// The files the app carries in its code (a Bytes literal each: fonts, the formulas' outlines) written out as files, for
// the browser's build, which fetches them beside its script rather than carrying them in it (a literal there is a
// list of numbers: three and a half times the bytes, and slow to parse). What the page gives the app as it starts
// (still.fail's web/src/mbui/core.ts: `globalThis.__mbassets`), each package's *_js.mbt reads by the same name.
//
//   scripts/assets <app module> <out dir>       writes each into <out dir>

///|
/// Each file: where its literal is (from the app module), the literal's name, and the file's name.
let carried : Array[(String, String, String)] = [
  ("src/sf/font_assets.mbt", "code_face_ttf", "jetbrains_mono.ttf"),
  ("src/sf/math_glyphs.mbt", "math_glyphs_gz", "math_glyphs.gz"),
  ("src/sfbase/inter_face.mbt", "inter_gz", "inter.ttf.gz"),
  ("src/sfbase/share_face.mbt", "share_400_gz", "share_400.gz"),
  ("src/sfbase/share_face.mbt", "share_600_gz", "share_600.gz"),
]

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("assets: " + why)
  @sys.exit(1)
}

///|
fn hex(c : Int) -> Int {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    c - 'a'.to_int() + 10
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// The bytes of `let <name> : Bytes = b"…"` in `text`: its characters as they are, `\xHH` a byte (what the files'
/// writers use for every byte not printable ASCII, and for `"` and `\`); None where there is none or it is not so.
fn literal(text : String, name : String) -> Bytes? {
  let head = "let " + name + " : Bytes = b\""
  let at = match text.find(head) {
    Some(i) => i + head.length()
    None => return None
  }
  let out = @buffer.new()
  let mut i = at
  let n = text.length()
  while i < n {
    let c = text.code_unit_at(i).to_int()
    if c == '"'.to_int() {
      return Some(out.to_bytes())
    }
    if c == '\\'.to_int() {
      if i + 3 >= n || text.code_unit_at(i + 1).to_int() != 'x'.to_int() {
        return None
      }
      let h = hex(text.code_unit_at(i + 2).to_int())
      let l = hex(text.code_unit_at(i + 3).to_int())
      if h < 0 || l < 0 {
        return None
      }
      out.write_byte((h * 16 + l).to_byte())
      i = i + 4
    } else if c >= 0x20 && c < 0x7f {
      out.write_byte(c.to_byte())
      i = i + 1
    } else {
      return None
    }
  }
  None
}

///|
fn main {
  let args = @env.args()
  if args.length() != 3 {
    fail("scripts/assets <app module> <out dir>")
    return
  }
  let (module, dir) = (args[1], args[2])
  @sys.makedirs(dir)
  for c in carried {
    let (file, name, out) = c
    let text = match @sys.read_text(@sys.join(module, file)) {
      Some(t) => t
      None => {
        fail("no " + file)
        return
      }
    }
    match literal(text, name) {
      Some(b) =>
        if !@sys.write_bytes(@sys.join(dir, out), b) {
          fail("could not write " + out)
          return
        } else {
          @sys.println_out("\{out} \{b.length()}")
        }
      None => {
        fail("no literal " + name + " in " + file)
        return
      }
    }
  }
}
