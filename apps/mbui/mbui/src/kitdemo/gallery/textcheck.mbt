// The text's contract: a host's kept text (a run's TEXTREC lines) asked of the
// host's text system again and compared, answer by answer. MBUI_TEXTCHECK=NAME on a real host: every metrics, shaping,
// whole-word key and glyph box asked again, in the order the run asked them first (so the glyph keys the host hands
// out come in the same order; where a glyph goes in the atlas is not the host's to say: hostapi's atlas.mbt), each
// answer written as the run's log writes it (its JSON) and compared to what was kept, to the character: the same
// numbers to the last bit the log keeps. Each that differs is logged
// (TEXTCHECK differs …), then `TEXTCHECK done NAME: N answers, K differ` and the app ends: 0 all the same, 1 not.
// Pictures' and PDFs' answers (hostrec) are not text: skipped, and counted.

///|
/// One kept answer asked again: what the line asked (its head, as its JSON) and what the host answers now, as JSON;
/// None: not a text answer.
fn ask_again(m : Map[String, Json]) -> (String, Json)? {
  let args = fn(j : Json?) -> (Double, Int, Int, String)? {
    match j {
      Some(Array([Number(size, ..), Number(weight, ..), Number(style, ..), .. rest])) => {
        let text = match rest {
          [String(t), ..] => t
          _ => ""
        }
        Some((size, weight.to_int(), style.to_int(), text))
      }
      _ => None
    }
  }
  let nums = fn(a : FixedArray[Double], n : Int) -> Json {
    let out : Array[Json] = []
    for i in 0..<n {
      out.push(Json::number(a[i]))
    }
    Json::array(out)
  }
  match (m.get("m"), m.get("s"), m.get("k"), m.get("g")) {
    (Some(head), _, _, _) =>
      match args(Some(head)) {
        Some((size, weight, style, _)) => {
          // (a run kept before hosts said the Han font's two and whole pixels: the numbers it kept)
          let kept = match m.get("r") {
            Some(Array(r)) => r.length()
            _ => 6
          }
          let out = FixedArray::make(6, 0.0)
          @hostapi.font_metrics(size, weight, style, out)
          Some(("m " + head.stringify(), nums(out, if kept < 6 { kept } else { 6 })))
        }
        None => None
      }
    (_, Some(head), _, _) =>
      match args(Some(head)) {
        Some((size, weight, style, text)) => {
          let kept = match m.get("r") {
            Some(Array(r)) => r.length()
            _ => 0
          }
          let cap = if kept > text.length() * 4 + 16 { kept } else { text.length() * 4 + 16 }
          let out = FixedArray::make(cap, 0.0)
          let k = @hostapi.shape(text, size, weight, style, out)
          Some(("s " + head.stringify(), nums(out, k * 4)))
        }
        None => None
      }
    (_, _, Some(head), _) =>
      match args(Some(head)) {
        Some((size, weight, style, text)) =>
          Some(("k " + head.stringify(), Json::number(@hostapi.text_key(text, size, weight, style).to_double())))
        None => None
      }
    (_, _, _, Some(Number(key, ..) as head)) => {
      let out = FixedArray::make(7, 0.0)
      @hostapi.glyph(key.to_int(), out)
      // (its place, which a run kept before its atlas was the app's said: not compared)
      match m.get("r") {
        Some(Array([Number(u, ..), Number(v, ..), ..])) => {
          out[0] = u
          out[1] = v
        }
        _ => ()
      }
      Some(("g " + head.stringify(), nums(out, 7)))
    }
    _ => None
  }
}

///|
/// The kept run `name`'s text asked again (above): how many answers, how many differ, how many skipped.
fn text_check(name : String) -> (Int, Int, Int) {
  guard kept_run(name) is Some(run) else {
    @hostapi.log("TEXTCHECK no kept run \"\{name}\" (src/kitdemo/gallery/textrec_runs.mbt)")
    return (0, 1, 0)
  }
  let mut asked = 0
  let mut differ = 0
  let mut skipped = 0
  for v in run.split("\n") {
    let line = v.to_owned()
    guard line.find("TEXTREC ") is Some(i) else { continue }
    let j = @json.parse(line.exact_view(start=i + 8).to_owned()) catch {
      _ => {
        skipped += 1
        continue
      }
    }
    guard j is Object(m) else { continue }
    match ask_again(m) {
      Some((what, now)) => {
        asked += 1
        // the kept answer as the log writes it (parsed and written again: the same text the run wrote)
        let kept = match m.get("r") {
          Some(r) => r.stringify()
          None => ""
        }
        // the answer now, written and read back as the kept one was
        let now = (try @json.parse(now.stringify()) catch {
          _ => now
        }).stringify()
        if kept != now {
          differ += 1
          @hostapi.log("TEXTCHECK differs \{what}: kept \{kept}, now \{now}")
        }
      }
      None => skipped += 1
    }
  }
  (asked, differ, skipped)
}

///|
/// A composer's mark (`@[…]` drawn with a zero width space in each bracket's place) at the end of its words, and one
/// within them, shaped by the host: each zero width character advances none, the last letter some, and all of it as
/// far as the same words without them. Asked of Core Text (macOS), which answers 0 as the offset of a zero width space
/// that ends the line: the mark's last letter at no width and its closing space as wide as the line, a caret after it
/// twice as far as the words go (#4738, 2026-11-08). By sizes, not points: true at any font, any system. Not asked of
/// the other hosts (not found so there). Each that is not so logged (TEXTCHECK zero-width …); how many.
fn zero_width_check() -> Int {
  guard @ui.platform() == 0 else { return 0 }
  let zw = fn(ch : Char) { ch == '\u{200B}' || ch == '\u{200C}' || ch == '\u{200D}' || ch == '\u{2060}' || ch == '\u{FEFF}' }
  let shaped = fn(text : String) -> Array[(Int, Int, Double)] {
    let out = FixedArray::make(text.length() * 4 + 16, 0.0)
    let k = @hostapi.shape(text, 14.0, 400, 0, out)
    Array::makei(k, fn(i) { (out[i * 4].to_int(), out[i * 4 + 1].to_int(), out[i * 4 + 2]) })
  }
  let wide = fn(cs : Array[(Int, Int, Double)]) { cs.fold(init=0.0, fn(w, c) { w + c.2 }) }
  let mut bad = 0
  for text in ["\u{200B}@RoboTwin 四卡实验规划\u{200B}", "看 \u{200B}@首页\u{200B} 吧"] {
    let cs = shaped(text)
    let bare = text.iter().filter(fn(ch) { !zw(ch) }).collect()
    let plain = wide(shaped(String::from_array(bare)))
    let all = wide(cs)
    let said : Array[String] = []
    if (all - plain).abs() > 0.5 {
      said.push("it goes \{all}, the words without its zero width characters \{plain}")
    }
    let mut last = -1
    for i, c in cs {
      let ch = text.exact_view(start=c.0, end=c.0 + c.1)
      if ch.iter().all(zw) {
        if c.2 != 0.0 {
          said.push("a zero width character at \{c.0} goes \{c.2}")
        }
      } else {
        last = i
      }
    }
    if last >= 0 && cs[last].2 <= 0.0 {
      said.push("its last letter (at \{cs[last].0}) goes none")
    }
    if said.length() > 0 {
      bad += 1
      @hostapi.log("TEXTCHECK zero-width \{Json::string(text).stringify()}: " + said.join("; "))
    }
  }
  bad
}

///|
/// Whether the check ran already (it runs once, in the first frame's build, the host's text system up by then).
let text_checked : Ref[Bool] = Ref(false)

///|
/// MBUI_TEXTCHECK=NAME: the check, then the app's end (its code: whether every answer was the same).
pub fn text_check_run(c : @ui.Ctx, name : String) -> Unit {
  if !text_checked.val {
    text_checked.val = true
    let (asked, differ, skipped) = text_check(name)
    let differ = differ + zero_width_check()
    @hostapi.log("TEXTCHECK done \{name}: \{asked} answers, \{differ} differ, \{skipped} skipped")
    @hostapi.exit(if differ == 0 && asked > 0 { 0 } else { 1 })
  }
  c.text("TEXTCHECK \{name}") |> ignore
}
