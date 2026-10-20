// What a host answers of pictures and PDFs, kept with its text (textrec.mbt) and given again under a Tester: how large a
// picture decodes (from its bytes or its source, at the size asked), how many pages a PDF has and how large each is,
// how large a page drawn is. So a screen with pictures a Tester draws is the host's, to the instance, as its text is.
//
// The lines (TEXTREC, as the text's: MBUI_TEXT_RECORD=1):
//   {"ib":[bytes,length,px],"r":[w,h,ow,oh]}       a picture handed over as bytes (their FNV-1a, hex), decoded at px
//   {"is":[source,px],"r":[w,h,ow,oh]}             a picture by its source
//   {"pn":[bytes,length],"r":pages}                a PDF's pages
//   {"ps":[bytes,length,page],"r":[w,h]}           a page's size (points)
//   {"pi":[bytes,length,page,px],"r":[w,h,ow,oh]}  a page drawn at px
//   {"wa":[text,offset],"r":[start,end]}           the system's word of `text` around `offset` (UTF-16; -1 -1: none)

///|
/// What is being recorded of the host's answers, by its ids: what each picture asked is (its line's head), each PDF.
struct HostRec {
  images : Map[Int, Json]
  pdfs : Map[Int, (String, Int)]
}

///|
fn HostRec::new() -> HostRec {
  { images: {}, pdfs: {} }
}

///|
/// Bytes as one number (FNV-1a, 64 bits), in hex: what names a picture or a PDF handed over by its bytes.
fn bytes_name(data : Bytes) -> String {
  let mut h = -3750763034362895579L
  for b in data {
    h = (h ^ b.to_int64()) * 1099511628211L
  }
  let hex = "0123456789abcdef"
  let sb = StringBuilder()
  for k in 0..<16 {
    let d = ((h >> ((15 - k) * 4)) & 15L).to_int()
    sb.write_char(hex[d].unsafe_to_char())
  }
  sb.to_string()
}

///|
/// A picture asked of the host, to be recorded once it is decoded (its id, its line's head).
fn rec_image_asked(id : Int, head : Json) -> Unit {
  if text_recording() {
    g().host_rec.images[id] = head
  }
}

///|
/// A picture the host has decoded: its sizes recorded, once.
fn rec_image_ready(id : Int, out : FixedArray[Double]) -> Unit {
  if text_recording() {
    match g().host_rec.images.get(id) {
      Some(head) => {
        g().host_rec.images.remove(id)
        let line : Json = match head {
          Object(m) => {
            let o = Map::from_array(m.to_array())
            o["r"] = nums(out, 4)
            Json::object(o)
          }
          _ => head
        }
        text_say(line.stringify(), line)
      }
      None => ()
    }
  }
}

///|
/// The kept answers of pictures and PDFs, by their lines' heads ("ib|…", "is|…", "pn|…", "ps|…", "pi|…").
fn host_answers_of(lines : String) -> Map[String, Json] {
  let out : Map[String, Json] = {}
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
    for kind in ["ib", "is", "pn", "ps", "pi", "wa"] {
      match (m.get(kind), m.get("r")) {
        (Some(head), Some(r)) => out[kind + "|" + head.stringify()] = r
        _ => ()
      }
    }
  }
  out
}

///|
/// The kept answer for `kind` asked with `head`, if a Tester has kept text and it has this; what it lacks is said
/// (Tester::text_missing).
fn kept_answer(kind : String, head : Json) -> Json? {
  guard text_table.val is Some(t) else { return None }
  let key = kind + "|" + head.stringify()
  match t.answers.get(key) {
    Some(r) => Some(r)
    None => {
      text_lacks(t, "host " + key)
      None
    }
  }
}

///|
/// A kept picture's four sizes (w, h, ow, oh).
fn kept_sizes(r : Json?) -> (Double, Double, Double, Double)? {
  match r {
    Some(Array([Number(w, ..), Number(h, ..), Number(ow, ..), Number(oh, ..), ..])) => Some((w, h, ow, oh))
    _ => None
  }
}
