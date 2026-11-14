// A message's pictures and videos as nodes drawn as the old view's message_files draws them, state by state: its
// grounds, its pictures (where, how big, which part of them, how opaque) and its words, each the same at the same
// moment (its pictures before they are here and once they are, one sent from here, one in the middle of coming, one
// that cannot be had and one its station could not be reached for, a tall one cut to its top, a thin one letterboxed,
// a video with its still and without).

///|
/// The moment both are looked at (any while past a picture's way in and its pill's).
let cmp_at : Double = 2400.0

///|
/// How long after it is asked a still or a picture sent from here is decoded (on no frame rate's frames).
let cmp_decode : Double = 137.0

///|
/// What a state is: its file, how its picture is answered (`answer`: None never), how far it has said it has come.
priv struct CmpState {
  name : String
  a : Attachment
  answer : Result[(Json, Bytes?), Json]?
  coming : Json?
  sent : String
}

///|
fn cmp_picture(name : String, w : Double, h : Double, thumbhash? : String = "") -> Attachment {
  attachment_of({
    "name": Json::string(name),
    "path": Json::string("/w/uploads/" + name),
    "size": 12345.0,
    "owner": "ag",
    "width": Json::number(w),
    "height": Json::number(h),
    "thumbhash": Json::string(thumbhash),
    "duration": 42000.0,
  })
}

///|
/// Its picture come from its station, `w` × `h` (a PNG's head: what its size is read from).
fn cmp_here_bytes(w : Int, h : Int) -> Result[(Json, Bytes?), Json] {
  let be = fn(n : Int) { [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF] }
  let head = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52] + be(w) + be(h) + [8, 6, 0, 0, 0]
  Ok((Json::object({}), Some(Bytes::from_array(head.map(fn(i) { i.to_byte() })))))
}

///|
fn cmp_states() -> Array[CmpState] {
  let hash = "1QcSHQRnh493V4dIh4eXh1h4kJUI"
  [
    { name: "waiting", a: cmp_picture("waiting.png", 800.0, 600.0), answer: None, coming: None, sent: "" },
    { name: "likeness", a: cmp_picture("likeness.png", 800.0, 600.0, thumbhash=hash), answer: None, coming: None, sent: "" },
    { name: "here", a: cmp_picture("here.png", 800.0, 600.0, thumbhash=hash), answer: Some(cmp_here_bytes(800, 600)), coming: None, sent: "" },
    {
      name: "coming",
      a: cmp_picture("coming.png", 800.0, 600.0),
      answer: None,
      coming: Some({ "loaded": 35.0, "total": 100.0 }),
      sent: "",
    },
    {
      name: "coming-bytes",
      a: cmp_picture("bytes.png", 800.0, 600.0),
      answer: None,
      coming: Some({ "loaded": 35000.0 }),
      sent: "",
    },
    {
      name: "unreached",
      a: cmp_picture("unreached.png", 800.0, 600.0),
      answer: Some(Err({ "code": "mesh", "message": "unreachable" })),
      coming: None,
      sent: "",
    },
    { name: "none", a: cmp_picture("none.png", 800.0, 600.0), answer: Some(Ok((Json::object({}), None))), coming: None, sent: "" },
    // (a tall one and a thin one as sent from here: their pictures of their own sizes, where a Tester's host decodes
    // any bytes a station sends as 400 × 300)
    {
      name: "tall",
      a: { ..cmp_picture("tall.png", 300.0, 3000.0), upload: "u-tall" },
      answer: None,
      coming: None,
      sent: "cmp/tall-picked.png",
    },
    {
      name: "thin",
      a: { ..cmp_picture("thin.png", 2000.0, 20.0), upload: "u-thin" },
      answer: None,
      coming: None,
      sent: "cmp/thin-picked.png",
    },
    {
      name: "sent",
      a: { ..cmp_picture("sent.png", 800.0, 600.0), upload: "u-sent" },
      answer: None,
      coming: None,
      sent: "cmp/sent-picked.png",
    },
    { name: "video", a: cmp_picture("clip.mp4", 1280.0, 720.0), answer: None, coming: None, sent: "" },
    { name: "video-none", a: cmp_picture("none.mp4", 1280.0, 720.0), answer: None, coming: None, sent: "" },
  ]
}

///|
/// The source of a state: its pictures asked through images of their own, each asking kept in `asks` (answered as the
/// state says once the first frame is drawn), a video's still from its station (none for video-none).
fn cmp_src(s : CmpState, asks : Array[() -> Unit]) -> Source {
  let images = @sfbase.ChatImages::new()
  {
    ..files_src(),
    file: fn(station, key, name) {
      images.get(station, @sfbase.file_image_id(station, key, name), "mem:cmp/" + name, fn(heard, done) {
        asks.push(fn() {
          match s.coming {
            Some(c) => heard(c)
            None => ()
          }
          match s.answer {
            Some(r) => done(r)
            None => ()
          }
        })
      })
    },
    poster: fn(_, _, name) { if name == "clip.mp4" { "cmp/still.png" } else { "" } },
    images,
  }
}

///|
/// What the Tester drew last: its rects, its pictures, its words, each a line, sorted.
fn cmp_drawn(t : @ui.Tester) -> Array[String] {
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let out = []
  for r in t.drawn_rects() {
    out.push("rect \{r2(r.0)},\{r2(r.1)} \{r2(r.2)}x\{r2(r.3)} \{r.4}")
  }
  for i in t.drawn_images() {
    out.push("image " + i.map(r2).map(fn(x) { x.to_string() }).join(","))
  }
  for w in t.words() {
    out.push("words \{w.0}@\{r2(w.1)},\{r2(w.2)} \{r2(w.3)}x\{r2(w.4)} a\{r2(w.5)}")
  }
  for s in t.drawn_shapes() {
    out.push("shape \{r2(s.0)},\{r2(s.1)} \{r2(s.2)}x\{r2(s.3)} \{s.4} \{s.5}")
  }
  out.sort()
  out
}

///|
/// A state drawn old (`old`: message_files in a column 390 wide) or as nodes, looked at cmp_at.
fn cmp_seen(s : CmpState, old : Bool) -> (Array[String], Double, Array[Double]) {
  let asks = []
  let src = cmp_src(s, asks)
  // (shown once the Tester is made, the pictures it reads said to decode a while after they are asked)
  let list : @signals.Signal[Array[Attachment]] = @signals.signal([])
  let pictures = [
    ("mem:cmp/" + s.a.name, s.a.width.to_int(), s.a.height.to_int()),
    ("cmp/still.png", 1280, 720),
  ]
  if s.sent != "" {
    pictures.push((s.sent, s.a.width.to_int(), s.a.height.to_int()))
  }
  let t = if old {
    @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          c.box(style=@ui.style(w=Fixed(390.0)), fn() { message_files(c, src, files_here(), list.get(), false, by=None) })
          |> ignore
        })
      },
      w=430.0,
      h=400.0,
      platform=0,
      images=pictures,
    )
  } else {
    @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
      },
      tree=fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        let col = root.box(fn(v) { v.width(Is(Some(390.0))) |> ignore })
        let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
        let tips = @sf.TipLayer::new(fn() { Some(popup) })
        message_files_node(col, src, tips, files_place(), fn() { list.get() }, fn() { false }, fn() { None }, "")
      },
      w=430.0,
      h=400.0,
      platform=0,
      images=pictures,
    )
  }
  t.decode_after("cmp/still.png", cmp_decode)
  if s.sent != "" {
    t.decode_after(s.sent, cmp_decode)
    @sfbase.sent_picture_kept("upload\u{1}" + s.a.upload, s.sent)
  }
  list.set([s.a])
  t.draw()
  for ask in asks {
    ask()
  }
  // (looked at once both are at rest: the old one's way in starts at the frame it is drawn decoded, a node's at the
  // moment its host says it is, an intended difference: image_reveal_node's)
  t.run_for(cmp_at - t.time())
  t.run_for(@sf.reveal_ms + cmp_at)
  // (the frame at that moment drawn whole: one where nothing moves draws nothing anew)
  t.draw()
  (cmp_drawn(t), t.time(), t.drawn_images().map(fn(i) { i[8] }))
}

///|
test "a message's pictures and videos as nodes drawn as the old view draws them, state by state, at the same moment" {
  let differ = []
  for s in cmp_states() {
    let (old, at, old_alpha) = cmp_seen(s, true)
    let (new, new_at, new_alpha) = cmp_seen(s, false)
    // (what is compared is drawn: a picture where one is here, its words where it says any)
    let pictured = ["likeness", "here", "tall", "thin", "sent", "video"].contains(s.name)
    assert_eq(new_alpha.length() > 0, pictured, msg="\{s.name}: \{Repr(new_alpha)}")
    // an intended difference (the coordinator of the migration, 2026-11-11): a likeness waiting breathes as all of
    // what stands in for a picture does (the user, 2026-10-30), where the old view's breath (Ctx::cycle_look) took no
    // picture's instances and left it whole; all else of it the same
    let (old, new) = if s.name == "likeness" {
      assert_eq(at, new_at)
      let p = at / @sf.breath_ms
      let f = p - p.floor()
      let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
      let breath = 1.0 - 0.5 * @ui.Ease::InOut.at(way)
      assert_eq(old_alpha, [1.0], msg="the old view's likeness: whole")
      assert_true(
        new_alpha.length() == 1 && (new_alpha[0] - breath).abs() < 0.01 && breath < 0.99,
        msg="the node's likeness breathing: \{Repr(new_alpha)}, wanted \{breath}",
      )
      // (its picture where it is, as big, the same part of it: all of it but how opaque)
      let unbreathed = fn(l : Array[String]) {
        l.map(fn(x) {
          match (x.has_prefix("image "), x.rev_find(",")) {
            (true, Some(i)) => x.exact_view(end=i).to_owned()
            _ => x
          }
        })
      }
      (unbreathed(old), unbreathed(new))
    } else {
      (old, new)
    }
    if old != new {
      let only_old = old.filter(fn(x) { !new.contains(x) })
      let only_new = new.filter(fn(x) { !old.contains(x) })
      differ.push("\{s.name}:\n  old's alone:\n    \{only_old.join("\n    ")}\n  node's alone:\n    \{only_new.join("\n    ")}")
    }
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}
