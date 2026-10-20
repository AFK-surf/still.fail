// The text's contract (docs/determinism.md): a host's kept text (a run's TEXTREC lines, textrec_NAME.mbt) asked of the
// host's text system again and compared, answer by answer. MBUI_TEXTCHECK=NAME on a real host: every metrics, shaping,
// whole-word key and glyph box asked again, in the order the run asked them first (so the glyph keys and atlas places
// the host hands out come in the same order), each answer written as the run's log writes it (its JSON) and compared to
// what was kept, to the character: the same numbers to the last bit the log keeps. Each that differs is logged
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
          let out = FixedArray::make(3, 0.0)
          @host.font_metrics(size, weight, style, out)
          Some(("m " + head.stringify(), nums(out, 3)))
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
          let k = @host.shape(text, size, weight, style, out)
          Some(("s " + head.stringify(), nums(out, k * 4)))
        }
        None => None
      }
    (_, _, Some(head), _) =>
      match args(Some(head)) {
        Some((size, weight, style, text)) =>
          Some(("k " + head.stringify(), Json::number(@host.text_key(text, size, weight, style).to_double())))
        None => None
      }
    (_, _, _, Some(Number(key, ..) as head)) => {
      let out = FixedArray::make(7, 0.0)
      @host.glyph(key.to_int(), out)
      Some(("g " + head.stringify(), nums(out, 7)))
    }
    _ => None
  }
}

///|
/// The kept run `name`'s text asked again (above): how many answers, how many differ, how many skipped.
fn text_check(name : String) -> (Int, Int, Int) {
  guard kept_run(name) is Some(run) else {
    @host.log("TEXTCHECK no kept run \"\{name}\" (src/kitdemo/textrec_runs.mbt)")
    return (0, 1, 0)
  }
  let mut asked = 0
  let mut differ = 0
  let mut skipped = 0
  for v in run.split("\n") {
    let line = v.to_owned()
    guard line.find("TEXTREC ") is Some(i) else { continue }
    let j = @json.parse(line.view(start_offset=i + 8).to_owned()) catch {
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
          @host.log("TEXTCHECK differs \{what}: kept \{kept}, now \{now}")
        }
      }
      None => skipped += 1
    }
  }
  (asked, differ, skipped)
}

///|
/// Whether the check ran already (it runs once, in the first frame's build, the host's text system up by then).
let text_checked : Ref[Bool] = Ref(false)

///|
/// MBUI_TEXTCHECK=NAME: the check, then the app's end (its code: whether every answer was the same).
fn text_check_run(c : @ui.Ctx, name : String) -> Unit {
  if !text_checked.val {
    text_checked.val = true
    let (asked, differ, skipped) = text_check(name)
    @host.log("TEXTCHECK done \{name}: \{asked} answers, \{differ} differ, \{skipped} skipped")
    @host.exit(if differ == 0 && asked > 0 { 0 } else { 1 })
  }
  c.text("TEXTCHECK \{name}") |> ignore
}
