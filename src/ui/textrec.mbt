// A host's text answered once and kept (what its system says of fonts, how it shapes words, the glyphs' keys and
// boxes), then given again under a Tester: the laid-out tree and what is drawn are then the host's own, to the
// instance, with no window, no GPU and no font system. So a screen's frames are compared as data (frames.mbt) on any
// machine for each host, and only the renderers themselves draw pixels.
//
//   MBUI_TEXT_RECORD=1   on a real host: each answer, once, on the log as TEXTREC {…}
//   Tester::new(text=)   a test's fake host answers from those lines; what they lack is said (text_missing)
//
// The lines: {"m":[size,weight,style],"r":[ascent,descent,line]}, {"s":[size,weight,style,text],"r":[clusters…]}
// (start, length, advance, key: four numbers each), {"k":[size,weight,style,text],"r":key}, {"g":key,"r":[box…]}.

///|
priv struct TextTable {
  metrics : Map[String, Array[Double]]
  shapes : Map[String, Array[Double]]
  keys : Map[String, Int]
  glyphs : Map[Int, Array[Double]]
  missing : Array[String]
}

///|
/// A Tester's kept text (Tester::new's `text`), None: the fake host's own made-up metrics.
let text_table : Ref[TextTable?] = Ref::new(None)

///|
/// Recording (MBUI_TEXT_RECORD=1): -1 not asked yet, 0 no, 1 yes; what was said already.
let text_rec : Ref[Int] = Ref::new(-1)

///|
let text_said : Map[String, Bool] = Map([])

///|
fn text_recording() -> Bool {
  if text_rec.val < 0 {
    text_rec.val = if @host.env("MBUI_TEXT_RECORD") == "1" { 1 } else { 0 }
  }
  text_rec.val == 1
}

///|
fn style_key(size : Double, weight : Int, style : Int) -> String {
  "\{size}|\{weight}|\{style}"
}

///|
fn nums(a : FixedArray[Double], n : Int) -> Json {
  let out : Array[Json] = []
  for i in 0..<n {
    out.push(Json::number(a[i]))
  }
  Json::array(out)
}

///|
fn text_say(key : String, line : Json) -> Unit {
  if !text_said.contains(key) {
    text_said[key] = true
    @host.log("TEXTREC " + line.stringify())
  }
}

///|
fn rec_metrics(size : Double, weight : Int, style : Int, out : FixedArray[Double]) -> Unit {
  if text_recording() {
    let args : Json = [Json::number(size), Json::number(weight.to_double()), Json::number(style.to_double())]
    text_say("m" + style_key(size, weight, style), { "m": args, "r": nums(out, 3) })
  }
}

///|
fn rec_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
  k : Int,
) -> Unit {
  if text_recording() {
    let args : Json = [
      Json::number(size),
      Json::number(weight.to_double()),
      Json::number(style.to_double()),
      Json::string(text),
    ]
    text_say("s" + style_key(size, weight, style) + "|" + text, { "s": args, "r": nums(out, k * 4) })
  }
}

///|
fn rec_key(text : String, size : Double, weight : Int, style : Int, key : Int) -> Unit {
  if text_recording() {
    let args : Json = [
      Json::number(size),
      Json::number(weight.to_double()),
      Json::number(style.to_double()),
      Json::string(text),
    ]
    text_say("k" + style_key(size, weight, style) + "|" + text, {
      "k": args,
      "r": Json::number(key.to_double()),
    })
  }
}

///|
fn rec_glyph(key : Int, out : FixedArray[Double]) -> Unit {
  if text_recording() {
    text_say("g\{key}", { "g": Json::number(key.to_double()), "r": nums(out, 7) })
  }
}

///|
fn json_nums(j : Json?) -> Array[Double] {
  match j {
    Some(Array(a)) =>
      a.map(fn(v) {
        match v {
          Number(d, ..) => d
          _ => 0.0
        }
      })
    _ => []
  }
}

///|
fn json_args(j : Json?) -> (String, String)? {
  match j {
    Some(Array([Number(size, ..), Number(weight, ..), Number(style, ..), .. rest])) => {
      let text = match rest {
        [String(t), ..] => t
        _ => ""
      }
      Some((style_key(size, weight.to_int(), style.to_int()), text))
    }
    _ => None
  }
}

///|
/// The kept text in `lines` (MBUI_TEXT_RECORD's TEXTREC lines, or the bare JSON of each), for a Tester (its `text`).
fn text_table_of(lines : String) -> TextTable {
  let t : TextTable = {
    metrics: Map([]),
    shapes: Map([]),
    keys: Map([]),
    glyphs: Map([]),
    missing: [],
  }
  for v in lines.split("\n") {
    let line = v.to_owned()
    let start = match line.find("TEXTREC ") {
      Some(i) => i + 8
      None => if line.has_prefix("{") { 0 } else { continue }
    }
    let j = @json.parse(line.view(start_offset=start).to_owned()) catch {
      _ => continue
    }
    guard j is Object(m) else { continue }
    match (m.get("m"), m.get("s"), m.get("k"), m.get("g")) {
      (Some(_), _, _, _) =>
        match json_args(m.get("m")) {
          Some((sk, _)) => t.metrics[sk] = json_nums(m.get("r"))
          None => ()
        }
      (_, Some(_), _, _) =>
        match json_args(m.get("s")) {
          Some((sk, text)) => t.shapes[sk + "|" + text] = json_nums(m.get("r"))
          None => ()
        }
      (_, _, Some(_), _) =>
        match (json_args(m.get("k")), m.get("r")) {
          (Some((sk, text)), Some(Number(key, ..))) => t.keys[sk + "|" + text] = key.to_int()
          _ => ()
        }
      (_, _, _, Some(Number(key, ..))) => t.glyphs[key.to_int()] = json_nums(m.get("r"))
      _ => ()
    }
  }
  t
}

///|
/// What the kept text (Tester::new's `text`) did not have that the view asked of it, once each: "metrics 15|400|0",
/// "shape 15|400|0|words", "key …", "glyph N".
pub fn Tester::text_missing(self : Tester) -> Array[String] {
  ignore(self)
  match text_table.val {
    Some(t) => t.missing.copy()
    None => []
  }
}

///|
fn text_lacks(t : TextTable, what : String) -> Unit {
  if !t.missing.contains(what) {
    t.missing.push(what)
  }
}

///|
/// The kept answer for the font metrics, if a Tester has kept text: true when it answered.
fn kept_metrics(size : Double, weight : Int, style : Int, out : FixedArray[Double]) -> Bool {
  guard text_table.val is Some(t) else { return false }
  let sk = style_key(size, weight, style)
  match t.metrics.get(sk) {
    Some(r) => {
      for i in 0..<r.length() {
        out[i] = r[i]
      }
      true
    }
    None => {
      text_lacks(t, "metrics " + sk)
      false
    }
  }
}

///|
/// The kept shaping of `text` (its clusters' count), if a Tester has kept text and it has this.
fn kept_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int? {
  guard text_table.val is Some(t) else { return None }
  let key = style_key(size, weight, style) + "|" + text
  match t.shapes.get(key) {
    Some(r) if r.length() <= out.length() => {
      for i in 0..<r.length() {
        out[i] = r[i]
      }
      Some(r.length() / 4)
    }
    _ => {
      text_lacks(t, "shape " + key)
      None
    }
  }
}

///|
fn kept_key(text : String, size : Double, weight : Int, style : Int) -> Int? {
  guard text_table.val is Some(t) else { return None }
  let key = style_key(size, weight, style) + "|" + text
  match t.keys.get(key) {
    Some(k) => Some(k)
    None => {
      text_lacks(t, "key " + key)
      None
    }
  }
}

///|
fn kept_glyph(key : Int, out : FixedArray[Double]) -> Bool {
  guard text_table.val is Some(t) else { return false }
  match t.glyphs.get(key) {
    Some(r) => {
      for i in 0..<r.length() {
        out[i] = r[i]
      }
      true
    }
    None => {
      text_lacks(t, "glyph \{key}")
      false
    }
  }
}
