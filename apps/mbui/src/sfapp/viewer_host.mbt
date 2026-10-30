// The app's reader and player (src/sf reader.mbt, player.mbt): what they ask of the page told them as the app builds
// (@sf.set_viewer_host, as the web's web/src/viewer/whole.ts): how far its bars reach in, its
// sheets, what a link in a text's Markdown opens, the reader's layout in the core's prefs (`prefs.reader`, the same on every page that reads), the core
// reading a text for the reader (`reader.book`, `reader.text`) and finding words in it (`reader.search`).

///|
/// What the app gives its viewers over `src`.
fn viewer_host_of(c : @ui.Ctx, src : Source) -> @sf.ViewerHost {
  {
    // (in every tier: a tablet's status bar and navigation bar are over the viewer as a phone's are)
    room: fn() { (status_top(), nav_foot()) },
    // a phone's: the drive's reader sheet (drive_parts.mbt dv_sheet_frame)
    sheet: Some(fn(c, s) {
      dv_sheet_frame(
        c,
        s.title,
        c.height * s.height,
        s.body,
        closing=s.closing,
        reader=true,
        close=s.close,
        gone=s.gone,
        trailing=s.trailing,
      )
    }),
    keep: fn(name, mime, bytes) { keep_bytes(c, name, mime, bytes) },
    say: fn(words) { say(c, words) },
    on_link: open_link,
    reader_style: fn() { reader_prefs(src) },
    set_reader_style: fn(change) { reader_put(src, change) },
    read_book: fn(text, markdown, done) { read_book(src, text, markdown, done) },
    search_book: fn(id, query, done) {
      (src.call)("reader.search", { "id": Json::number(id.to_double()), "query": Json::string(query) }, fn(res) {
        done(
          match res {
            Ok(found) =>
              items(Some(found), "at").map(fn(j) {
                match j {
                  Number(n, ..) => n.to_int()
                  _ => 0
                }
              })
            Err(_) => []
          },
        )
      })
    },
  }
}

///|
/// A text read by the core as a reader shows it (`reader.book`, the text's UTF-8 beside the call; the text as joined,
/// `reader.text`, where joining changed it): its book.
fn read_book(src : Source, decoded : String, markdown : Bool, done : (Result[@sf.ReadBook, String]) -> Unit) -> Unit {
  let ready = fn(words : String, book : Json) {
    let b = Some(book)
    done(
      Ok({
        id: number(b, "id").to_int(),
        text: words,
        wrapped: number(b, "wrapped").to_int(),
        chapters: items(b, "chapters").map(fn(ch) { { title: text(Some(ch), "title"), offset: number(Some(ch), "offset").to_int() } }),
        heads: items(b, "heads").map(fn(h) {
          match h {
            Number(n, ..) => n.to_int()
            _ => 0
          }
        }),
        md: items(b, "md"),
      }),
    )
  }
  (src.call_bytes)(
    "reader.book",
    { "markdown": Json::boolean(markdown), "tree": Json::boolean(markdown) },
    @utf8.encode(decoded),
    fn(res) {
      match res {
        Ok(book) if flag(Some(book), "joined") =>
          (src.read_bytes)("reader.text", { "id": Json::number(number(Some(book), "id")) }, fn(t) {
            match t {
              Ok((_, bytes)) => ready(@utf8.decode_lossy(bytes[:]), book)
              Err(e) => done(Err(dv_error(e)))
            }
          })
        Ok(book) => ready(decoded, book)
        Err(e) => done(Err(dv_error(e)))
      }
    },
  )
}

///|
/// The reader's layout as the prefs keep it, as changed here until they say.
let reader_set : @sf.LiveMap[String, Json] = @sf.LiveMap::new()

///|
/// How the reader lays text out (the core fills in what is not kept): size 12–32, the lines' height 1.2–2.4 of it,
/// the margin 8–44, the face, the indent, the paper.
fn reader_prefs(src : Source) -> @sf.ReaderStyle {
  let kept = field((src.topic)("prefs", {}).value, "reader")
  let get = fn(k : String) -> Json? {
    match reader_set.get(k) {
      Some(v) => Some(v)
      None => field(kept, k)
    }
  }
  let num = fn(k : String, lo : Double, hi : Double, d : Double) -> Double {
    match get(k) {
      Some(Number(n, ..)) => dmin(hi, dmax(lo, n))
      _ => d
    }
  }
  let word = fn(k : String, d : String) -> String {
    match get(k) {
      Some(String(s)) => s
      _ => d
    }
  }
  let d = @sf.reader_style_default
  let (size_lo, size_hi) = @sf.reader_sizes
  let (line_lo, line_hi) = @sf.reader_lines
  let (margin_lo, margin_hi) = @sf.reader_margins
  {
    size: num("size", size_lo.to_double(), size_hi.to_double(), d.size.to_double()).to_int(),
    line: num("line", line_lo, line_hi, d.line),
    margin: num("margin", margin_lo.to_double(), margin_hi.to_double(), d.margin.to_double()).to_int(),
    face: word("face", d.face),
    indent: match get("indent") {
      Some(False) => false
      _ => true
    },
    paper: word("paper", d.paper),
  }
}

///|
/// One setting of the layout changed: shown at once, kept by the core (`prefs.set {reader: {field: value}}`).
fn reader_put(src : Source, change : @sf.ReaderStyleChange) -> Unit {
  let (k, v) = match change {
    Size(n) => ("size", Json::number(n.to_double()))
    Line(x) => ("line", Json::number(x))
    Margin(n) => ("margin", Json::number(n.to_double()))
    Face(s) => ("face", Json::string(s))
    Indent(b) => ("indent", Json::boolean(b))
    Paper(s) => ("paper", Json::string(s))
  }
  reader_set[k] = v
  let o : Map[String, Json] = Map([])
  o[k] = v
  (src.call)("prefs.set", Json::object({ "reader": Json::object(o) }), fn(_) {  })
}
