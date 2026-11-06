// A draw list names clusters in the host that shaped its words. Another host may group those words differently
// (for example, fi can be one cluster). Before producing frames for this renderer, ask it for its own text replies,
// then give those replies to the Tester. This records requests from one or more draw lists at the same scale; it
// never uses the old cluster number to choose a glyph. TEXTREC is the format of ui/textrec.mbt.

///|
fn record_text(text : String) -> Unit {
  let requests : Map[String, (Double, Int, Int, Bool, String)] = {}
  let mut scale = 0.0
  for v in text.split("\n") {
    let line = v.to_owned()
    let t = line.split(" ").map(fn(x) { x.to_owned() }).to_array()
    if t.length() >= 4 && t[0] == "window" {
      let next = num(t[3])
      if next <= 0.0 || (scale > 0.0 && next != scale) {
        say("mbui-render: text recording requires one positive scale")
        return
      }
      scale = next
    } else if t.length() >= 7 && t[0] == "glyph" {
      let words = quoted(line)
      let size = num(t[2])
      let keyed = num(t[5]) < 0.0
      if size <= 0.0 || words == "" {
        say("mbui-render: text recording requires named glyphs")
        return
      }
      let key = "\{t[2]}|\{t[3]}|\{t[4]}|\{keyed}|\{words}"
      requests[key] = (size, num(t[3]).to_int(), num(t[4]).to_int(), keyed, words)
    }
  }
  if scale <= 0.0 || requests.is_empty() {
    say("mbui-render: text recording has no requests")
    return
  }
  init_offscreen(1.0, 1.0, scale)
  let metrics = FixedArray::make(6, 0.0)
  let shaped = FixedArray::make(4096, 0.0)
  let glyph = FixedArray::make(8, 0.0)
  let fonts : Map[String, Bool] = {}
  let glyphs : Map[Int, Bool] = {}
  let numbers = fn(a : FixedArray[Double], n : Int) -> Json {
    let out : Array[Json] = []
    for i in 0..<n { out.push(Json::number(a[i])) }
    Json::array(out)
  }
  let record_glyph = fn(key : Int) {
    if key >= 0 && !glyphs.contains(key) {
      glyphs[key] = true
      @hostapi.glyph(key, glyph)
      let reply : Json = { "g": Json::number(key.to_double()), "r": numbers(glyph, 7) }
      say("TEXTREC " + reply.stringify())
    }
  }
  requests.each(fn(_, request) {
    let (size, weight, style, keyed, words) = request
    let font = "\{size}|\{weight}|\{style}"
    let args : Array[Json] = [Json::number(size), Json::number(weight.to_double()), Json::number(style.to_double())]
    if !fonts.contains(font) {
      fonts[font] = true
      @hostapi.font_metrics(size, weight, style, metrics)
      let reply : Json = { "m": Json::array(args.copy()), "r": numbers(metrics, 6) }
      say("TEXTREC " + reply.stringify())
    }
    let record_key = fn(part : String) {
      let key = @hostapi.text_key(part, size, weight, style)
      let keyed_args = args.copy()
      keyed_args.push(Json::string(part))
      let reply : Json = { "k": Json::array(keyed_args), "r": Json::number(key.to_double()) }
      say("TEXTREC " + reply.stringify())
      record_glyph(key)
    }
    if keyed {
      record_key(words)
    } else {
      let shaped_args = args.copy()
      shaped_args.push(Json::string(words))
      let n = @hostapi.shape(words, size, weight, style, shaped)
      let reply : Json = { "s": Json::array(shaped_args), "r": numbers(shaped, n * 4) }
      say("TEXTREC " + reply.stringify())
      for i in 0..<n { record_glyph(shaped[i * 4 + 3].to_int()) }
      // Android can leave a ligature's continuation as -2. ui/text.mbt then asks for the joined piece by text_key;
      // record that real reply too, so the Tester can make the same request after reading the raw shape reply.
      let mut i = 0
      while i < n {
        if shaped[i * 4 + 3].to_int() != -2 {
          i = i + 1
          continue
        }
        let mut end = i + 1
        while end < n && shaped[end * 4 + 3].to_int() == -2 { end = end + 1 }
        if i == 0 || shaped[(i - 1) * 4 + 3] < 0.0 {
          for k in i..<end {
            let start = shaped[k * 4].to_int()
            record_key(words.unsafe_substring(start~, end=start + shaped[k * 4 + 1].to_int()))
          }
        } else {
          let last = (end - 1) * 4
          record_key(words.unsafe_substring(start=shaped[(i - 1) * 4].to_int(),
            end=shaped[last].to_int() + shaped[last + 1].to_int()))
        }
        i = end
      }
    }
  })
  say("mbui-render: text recorded")
}
