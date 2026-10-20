// Every call to the platform goes through here, so tests can swap in a fake
// host: no window, no GPU, deterministic text metrics and a clock the test
// advances.

///|
struct FakeHost {
  mut time : Double
  /// the time of day (ms since 1970) at its clock's 0: what @ui.wall_ms says is it plus the clock (Tester::set_wall)
  mut wall : Double
  /// device pixels a point, as a host's window has them (2: a Retina screen; a recording host's, Tester::new(scale=))
  mut scale : Double
  mut wants : Bool
  mut wake : Double
  mut instances : Int
  mut ime_active : Bool
  mut ime_text : String
  mut ime_sel : (Int, Int)
  mut ime_rect : (Double, Double, Double, Double)
  mut clipboard : String
  // whether the app takes back (a page to go back to), as last told
  mut back_on : Bool
  // the system it plays (as @host.platform: 0 macOS, 1 iOS, 2 Android)
  platform : Int
  // the system asks for less transparency (glass drawn solid)
  mut reduce_transparency : Bool
  // the person's setting for motion: reduced (Tester::set_reduce_motion; or the environment's MBUI_REDUCE_MOTION=1)
  mut reduce_motion : Bool
  logs : Array[String]
  // images: sources the test made up, with their size in pixels; loads
  // asked for (source, max_px); decodes, ready from the next frame on
  image_sizes : Map[String, (Int, Int)]
  image_loads : Array[(String, Int)]
  images : Map[Int, FakeImage]
  // what bold adds to a cluster's advance, in ems (0 by default: weight
  // changes nothing)
  mut bold : Double
  // native views: what was asked of them, a line each ("open 1 video/mp4", "place 1 0 0 390 220 shown"…)
  views : Array[String]
  mut view_ids : Int
  /// the views' readiness as the host's event told it (1 ready, -1 failed); not here: not yet
  view_ready : Map[Int, Int]
  /// what the host does for the app is done by itself at the next frame (Tester::new's `finish`); else the test says
  /// when (Tester::finish, finish_all)
  auto_finish : Bool
  /// what it finished, in that order ((kind, id))
  finished : Array[(Int, Int)]
  /// what its sites say, oldest first (Tester::site_says), as a site view's host would (view_site_next)
  site : Array[String]
  /// the pointer's shape as last told (desktop.mbt), and how often the window was asked to be dragged
  mut cursor : Int
  mut window_drags : Int
  /// the URLs handed to the system (Ctx::open_url), oldest first
  opened : Array[String]
  /// what the app reads of where it runs (hostread.mbt): the system dark, the window's buttons in the app's top row,
  /// the environment, the build's version code
  mut dark : Bool
  mut inset : Bool
  env : Map[String, String]
  app_version : Int
  /// the system's notifications the app shows, oldest first (notify.mbt), and the one tapped, not yet taken
  notices : Array[Notice]
  mut notice_opened : String
  /// what the system lets the app show ("granted", "denied", "ask", "unknown": Tester::set_notice_permission), what
  /// the person answers when asked (None: never), how often the app asked, and the answer due: from the frame after it
  mut notice_perm : String
  mut notice_reply : Bool?
  mut notice_asks : Int
  mut notice_due : (Bool, Int)?
  /// the PDFs opened, by their ids: their bytes' name and length (what their kept answers are by)
  pdfs : Map[Int, (String, Int)]
  /// what the system's pickers give (Tester::picks), what was asked of them (files.mbt), the files kept on the device
  picks : Array[@host.Picked]
  pick_asks : Array[FakePick]
  keeps : Array[FakeKeep]
  /// what its players ask of the app's bytes, not taken yet (Tester::view_reads), and what the app gave (hostmedia.mbt)
  reads : Array[FakeRead]
  mut read_ids : Int
  read_answers : Array[(Int, Int, Int, Double)]
  /// a player's state as the test set it (Tester::set_player): view_info's ten numbers
  players : Map[Int, FixedArray[Double]]
  /// what another app shares in (Tester::share_in), from the frame after it was told; its files' bytes
  mut share : (String, Int)?
  share_files : Array[Bytes]
  /// the marks drawn onto images (draw_marks' JSON), oldest first, and the frame each was asked in
  marks : Array[(String, Int)]
  /// the PNG each drawing of marks gives (Tester::marks_make: what the next is to give, else one clear pixel)
  marks_out : Array[Bytes]
  mut marks_next : Bytes?
  /// what the app handed to the system's share sheet (@ui.share), oldest first
  shares : Array[(String, String, String, Bytes)]
  /// what a real host said of its views as a run recorded it (Tester::view_said): a video's frames' times, by (view,
  /// what) (view_text), and the frames grabbed, by view, oldest first (view_still)
  view_texts : Map[(Int, Int), String]
  view_stills : Map[Int, Array[Bytes]]
  /// how each view stood as the run recorded the host's saying it (view_info: its state and ten numbers)
  view_infos : Map[Int, (Int, FixedArray[Double])]
  /// a site view's page as the run recorded the host's saying it (view_site_state's JSON), by view; and the bodies of
  /// the requests its page made, by (view, request) (view_site_body)
  site_states : Map[Int, String]
  site_bodies : Map[(Int, Int), Bytes]
}

///|
priv struct FakeImage {
  mut state : Int
  w : Double
  h : Double
  ow : Double
  oh : Double
}

///|
fn fake_image_sized(f : FakeHost, w : Double, h : Double, ow : Double, oh : Double) -> Int {
  let id = f.images.length() + 1
  f.wants = true
  f.images[id] = { state: if ow > 0.0 { 0 } else { -1 }, w, h, ow, oh }
  id
}

///|
fn fake_image(f : FakeHost, ow : Int, oh : Int, max_px : Int) -> Int {
  let k = if ow > oh { max_px.to_double() / ow.to_double() } else { max_px.to_double() / oh.to_double() }
  let k = if k > 1.0 { 1.0 } else { k }
  let id = f.images.length() + 1
  // the decode will be done by the next frame, which it asks for
  f.wants = true
  f.images[id] = {
    state: if ow > 0 { 0 } else { -1 },
    w: (ow.to_double() * k).round(),
    h: (oh.to_double() * k).round(),
    ow: ow.to_double(),
    oh: oh.to_double(),
  }
  id
}

///|
// kept across runs: each Tester::new sets its own fake host, before it resets the rest
let fake : Ref[FakeHost?] = { val: None }

///|
fn h_now() -> Double {
  match fake.val {
    Some(f) => f.time
    None => @host.now()
  }
}

///|
fn h_wall_ms() -> Double {
  match fake.val {
    Some(f) => f.wall + f.time
    None => @host.wall_ms()
  }
}

///|
/// When the input event being handled happened (the host's, else now).
fn h_event_time() -> Double {
  match fake.val {
    Some(f) => f.time
    None => {
      let t = @host.event_time()
      if t >= 0.0 {
        t
      } else {
        @host.now()
      }
    }
  }
}

///|
fn h_platform() -> Int {
  match fake.val {
    Some(f) => f.platform
    None => {
      if host_platform.val < 0 {
        host_platform.val = @host.platform()
      }
      host_platform.val
    }
  }
}

///|
/// The host's system, asked once.
// kept across runs: the real host's system (asked once): a Tester never reads it (h_platform answers its fake's)
let host_platform : Ref[Int] = { val: -1 }

///|
fn h_request_frame() -> Unit {
  match fake.val {
    Some(f) => f.wants = true
    None => @host.request_frame()
  }
}

///|
/// The host's next frame asked for what moves on by the clock (a motion going on, a cycle shown): a Tester's host owes
/// no frame at this moment for it (its time goes by run_for).
fn h_request_frame_on() -> Unit {
  match fake.val {
    Some(_) => ()
    None => @host.request_frame()
  }
}

///|
fn h_wake_after(ms : Double) -> Unit {
  match fake.val {
    Some(f) =>
      if f.wake < 0.0 || f.time + ms < f.wake {
        f.wake = f.time + ms
      }
    None => @host.wake_after(ms)
  }
}

///|
fn h_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  match fake.val {
    Some(_) if kept_metrics(size, weight, style, out) => ()
    Some(_) => {
      out[0] = size * 0.8
      out[1] = size * 0.2
      out[2] = (size * 1.42).round()
    }
    None => {
      @host.font_metrics(size, weight, style, out)
      rec_metrics(size, weight, style, out)
    }
  }
}

///|
/// Fake shaping: one cluster per extended grapheme cluster, as real hosts
/// make them; Latin half an em wide (0.6 in the code face), everything else
/// a full em.
fn h_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  match fake.val {
    Some(_) if kept_shape(text, size, weight, style, out) is Some(k) => k
    Some(f) => {
      let n = text.length()
      let cap = out.length() / 4
      let mut i = 0
      let mut k = 0
      while i < n && k < cap {
        let c = text.at(i).to_int()
        let len = @text.next_grapheme(text, i) - i
        let adv = if c == 10 {
          0.0
        } else if c < 0x2E80 {
          if (style & @host.style_mono) != 0 {
            size * 0.6
          } else {
            size * 0.5
          }
        } else {
          size
        }
        let adv = if weight >= 600 && c != 10 { adv + size * f.bold } else { adv }
        out[k * 4] = i.to_double()
        out[k * 4 + 1] = len.to_double()
        out[k * 4 + 2] = adv
        // U+E000 plays a ligature's second letter: drawn as part of the cluster before it (unless shaped with no
        // ligatures)
        out[k * 4 + 3] = if c == 32 || c == 10 {
          -1.0
        } else if c == 0xE000 && k > 0 && (style & @host.style_no_ligatures) == 0 {
          -2.0
        } else {
          c.to_double()
        }
        i = i + len
        k = k + 1
      }
      k
    }
    None => {
      let k = @host.shape(text, size, weight, style, out)
      rec_shape(text, size, weight, style, out, k)
      k
    }
  }
}

///|
/// The key of `text` drawn as one piece (a word of a joining script).
fn h_text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  match fake.val {
    Some(_) if kept_key(text, size, weight, style) is Some(k) => k
    Some(_) => text.at(0).to_int()
    None => {
      let k = @host.text_key(text, size, weight, style)
      rec_key(text, size, weight, style, k)
      k
    }
  }
}

///|
fn h_glyph(key : Int, out : FixedArray[Double]) -> Unit {
  match fake.val {
    Some(_) if kept_glyph(key, out) => ()
    Some(_) => {
      // a glyph box per cluster, so painting is exercised
      out[0] = 0.0
      out[1] = 0.0
      out[2] = 6.0
      out[3] = 10.0
      out[4] = 0.0
      out[5] = -10.0
      out[6] = if key >= 0x1F000 { 1.0 } else { 0.0 }
    }
    None => {
      @host.glyph(key, out)
      rec_glyph(key, out)
    }
  }
}

///|
fn h_atlas_generation() -> Int {
  match fake.val {
    Some(_) => 0
    None => @host.atlas_generation()
  }
}

///|
fn h_present(buf : FixedArray[Double], count : Int) -> Unit {
  match fake.val {
    Some(f) => f.instances = count
    None => {
      let (r, gg, b) = g().clear
      @host.present(buf, count, r, gg, b)
    }
  }
}

///|
fn h_reduce_transparency() -> Bool {
  match fake.val {
    Some(f) => f.reduce_transparency
    None => @host.reduce_transparency() || h_env("MBUI_GLASS") == "solid"
  }
}

///|
fn h_gpu_ms() -> Double {
  match fake.val {
    Some(_) => -1.0
    None => @host.gpu_ms()
  }
}

///|
fn h_set_ime(
  active : Bool,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  text : String,
  a : Int,
  b : Int,
) -> Unit {
  match fake.val {
    Some(f) => {
      f.ime_active = active
      f.ime_text = text
      f.ime_sel = (a, b)
      f.ime_rect = (x, y, w, h)
    }
    None => @host.set_ime(active, x, y, w, h, text, a, b)
  }
}

///|
fn h_clipboard_set(s : String) -> Unit {
  match fake.val {
    Some(f) => f.clipboard = s
    None => @host.clipboard_set(s)
  }
}

///|
/// The word of `text` around `off` as the host's word boundaries have it, (-1, -1) where it has none (the fake host:
/// words.mbt's own).
fn h_word_at(text : String, off : Int) -> (Int, Int) {
  let head : Json = [Json::string(text), Json::number(off.to_double())]
  match fake.val {
    // under a Tester over a host's kept text: the host's word, as it said it (a word it did not say: the test is told,
    // Tester::text_missing, and gets none of its own made up in its place); with no kept text: this one's own
    Some(_) =>
      match text_table.val {
        Some(_) =>
          match kept_answer("wa", head) {
            Some(Array([Number(s, ..), Number(e, ..), ..])) => (s.to_int(), e.to_int())
            _ => (-1, -1)
          }
        None => (-1, -1)
      }
    None => {
      let (s, e) = @host.word_at(text, off)
      if text_recording() {
        let line : Json = { "wa": head, "r": [Json::number(s.to_double()), Json::number(e.to_double())] }
        text_say("wa|" + head.stringify(), line)
      }
      (s, e)
    }
  }
}

///|
/// A URL handed to the system (its browser, or the app it belongs to); the fake host keeps it (Tester::opened).
fn h_open_url(url : String) -> Bool {
  match fake.val {
    Some(f) => {
      f.opened.push(url)
      true
    }
    None => @host.open_url(url)
  }
}

///|
fn h_back_enabled(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.back_on = on
    None => @host.back_enabled(on)
  }
}

// What the app waits on from the host (effect.mb's outside, src/effect/outside.mbt): an image or a PDF's page
// decoding, a native view until it is ready (a page loaded, a video's first frame), what the system's pickers give, the
// gallery read, marks drawn onto an image, a video's frame grabbed, an update downloading (the kinds below, named as
// the hosts name them). Each is a ticket of the window's runtime, ended by the host's event for it (@host.set_outside:
// kind, id, state) or when the app lets it go or takes it; a run to a declared moment keeps its clock still while any
// is (@host.frame_awaiting). A host that sends no such events (set_outside answers false) gets no tickets. An answer
// the host tells (a pick, the gallery read, marks drawn, a frame grabbed, an update's word) asks for a frame: what it
// brings is read as the next frame builds, not looked for frame after frame. Where a ticket of these ends: on a host,
// at its event (or as the app takes the answer, if it read it first); under a Tester, whose fake host tells no event,
// as the app takes the answer (Pick::files, MarkedImage::made, NativeView::grabbed): both are when the host's work for
// it is over.

///|
/// An image or a PDF's page decoded (its image's id).
let outside_image = 1

///|
/// A native view ready (its view's id), or (state 0) waiting on the app's answer.
let outside_view = 2

///|
/// What the system's pickers give (@host.Pick's id).
let outside_pick = 3

///|
/// The gallery's photos read (@host.GalleryRead's id).
let outside_gallery = 4

///|
/// Marks drawn onto an image (@host.MarkedImage's id).
let outside_marks = 5

///|
/// A video's frame grabbed (its view's id).
let outside_grab = 6

///|
/// An update downloading (id 1): state 0 each time how it goes changes, while the host works at it; 1 once the host
/// works at it no more (handed to the installer, waiting on the person's leave), -1 failed.
let outside_update = 7

///|
let outside_tickets : Map[Int64, Int] = Map::new()

///|
let outside_told : Ref[Bool] = { val: false }

///|
fn outside_key(kind : Int, id : Int) -> Int64 {
  (kind.to_int64() << 32) | id.to_int64()
}

///|
fn outside_start(kind : Int, id : Int, what : String) -> Unit {
  if id > 0 && (outside_told.val || fake.val is Some(_)) {
    outside_tickets[outside_key(kind, id)] = runtime().outside_start(what)
  }
}

///|
fn outside_end(kind : Int, id : Int) -> Unit {
  let k = outside_key(kind, id)
  match outside_tickets.get(k) {
    Some(t) => {
      outside_tickets.remove(k)
      runtime().outside_end(t)
    }
    None => ()
  }
}

///|
/// The native views the host said were ready (or failed): their work is the host's no more, whatever is asked after.
let views_told : Map[Int, Bool] = Map::new()

///|
/// The host's event: what it did for the app is done (`state`: 1 done, -1 failed), or (a view, 0) it waits on the
/// app now: the bytes a player reads, a site's answer. Until the app answers, the host does nothing for it.
fn on_outside(kind : Int, id : Int, state : Int) -> Unit {
  if kind == outside_update {
    // (how it goes changed: held while the host works at it)
    if state == 0 {
      if !outside_tickets.contains(outside_key(kind, id)) {
        outside_start(kind, id, "an update downloading")
      }
    } else {
      outside_end(kind, id)
    }
    h_request_frame()
    return
  }
  if kind == outside_view && state != 0 {
    views_told[id] = true
  }
  // a picture decoded: its sizes recorded now (hostrec.mbt), drawn or not (one never drawn is still asked of a Tester)
  if kind == outside_image && state == 1 && fake.val is None && text_recording() {
    let out = FixedArray::make(4, 0.0)
    if @host.image_info(id, out) == 1 {
      rec_image_ready(id, out)
    }
  }
  outside_end(kind, id)
  // an answer brought (what was picked, read, drawn, grabbed): read as the next frame builds
  if kind == outside_pick || kind == outside_gallery || kind == outside_marks || kind == outside_grab {
    h_request_frame()
  }
}

///|
/// The app answered what a view waits on (a read, a site's request): the host's again, until ready or it asks more.
fn outside_answered(id : Int) -> Unit {
  if !views_told.contains(id) && !outside_tickets.contains(outside_key(outside_view, id)) {
    outside_start(outside_view, id, "view \{id} (after the app's answer)")
  }
}

///|
fn h_log(s : String) -> Unit {
  match fake.val {
    Some(f) => f.logs.push(s)
    None => @host.log(s)
  }
}

///|
fn h_image_load(src : String, max_px : Int) -> Int {
  let head : Json = [Json::string(src), Json::number(max_px.to_double())]
  let id = match fake.val {
    Some(f) => {
      f.image_loads.push((src, max_px))
      // as the host decoded it, when kept with the text; else as the test made it up (Tester::new's images)
      let id = match (f.image_sizes.get(src), text_table.val) {
        (None, Some(_)) =>
          match kept_sizes(kept_answer("is", head)) {
            Some((w, h, ow, oh)) => fake_image_sized(f, w, h, ow, oh)
            None => fake_image(f, 0, 0, max_px)
          }
        (sized, _) => {
          let (w, h) = sized.unwrap_or((0, 0))
          fake_image(f, w, h, max_px)
        }
      }
      // one it does not know failed at once: nothing of it is left to wait for
      match f.images.get(id) {
        Some(im) if im.state < 0 => return id
        _ => ()
      }
      id
    }
    None => {
      let id = @host.image_load(src, max_px)
      rec_image_asked(id, { "is": head })
      id
    }
  }
  outside_start(outside_image, id, "image \{id} \{src}")
  id
}

///|
/// Bytes handed over for `src` (Ctx::image_bytes, add_image) decoded: its wait on outside named by `src` too, as a
/// picture loaded by its source is ("image N (B bytes) SRC": a scripted run's `decoded SRC`).
fn h_image_load_bytes(data : Bytes, max_px : Int, src : String) -> Int {
  let head : Json = [
    Json::string(bytes_name(data)),
    Json::number(data.length().to_double()),
    Json::number(max_px.to_double()),
  ]
  let id = match fake.val {
    Some(f) => {
      f.image_loads.push(("bytes:\{data.length()}", max_px))
      // as the host decoded these bytes, when kept with the text; else a made-up 400 × 300
      match (text_table.val, kept_sizes(kept_answer("ib", head))) {
        (Some(_), Some((w, h, ow, oh))) => fake_image_sized(f, w, h, ow, oh)
        _ => fake_image(f, 400, 300, max_px)
      }
    }
    None => {
      let id = @host.image_load_bytes(data, max_px)
      rec_image_asked(id, { "ib": head })
      id
    }
  }
  outside_start(outside_image, id, "image \{id} (\{data.length()} bytes) \{src}")
  id
}

///|
fn h_image_info(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    Some(f) =>
      match f.images.get(id) {
        Some(im) => {
          if im.state == 1 {
            out[0] = im.w
            out[1] = im.h
            out[2] = im.ow
            out[3] = im.oh
          }
          im.state
        }
        None => -1
      }
    None => {
      let st = @host.image_info(id, out)
      if st == 1 {
        rec_image_ready(id, out)
      }
      st
    }
  }
}

///|
fn h_image_free(id : Int) -> Unit {
  outside_end(outside_image, id)
  match fake.val {
    Some(f) => f.images.remove(id)
    None => @host.image_free(id)
  }
}

// Native views (native.mbt): the fake host has views of every kind, ready at once, 10 s long and 640 × 360, that
// never ask to read; it notes what is asked of them (FakeHost.views).

///|
/// A native view's kind by name (native.mbt): video (audio, its type audio/…), web (a page), site.
fn view_kind_name(kind : Int, arg : String) -> String {
  match kind {
    1 => if arg.has_prefix("audio/") { "audio" } else { "video" }
    2 => "web"
    3 => "site"
    _ => "kind \{kind}"
  }
}

///|
fn h_view_open(kind : Int, arg : String) -> Int {
  let id = match fake.val {
    Some(f) => {
      f.view_ids += 1
      f.views.push("open \{f.view_ids} \{kind} \{arg.length()}")
      f.view_ids
    }
    None => @host.view_open(kind, arg)
  }
  outside_start(outside_view, id, "view \{id} (kind \{kind}, \{view_kind_name(kind, arg)})")
  id
}

///|
fn h_view_place(
  id : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  cx0 : Double,
  cy0 : Double,
  cx1 : Double,
  cy1 : Double,
  shown : Bool,
) -> Unit {
  match fake.val {
    Some(f) =>
      f.views.push(
        "place \{id} \{x} \{y} \{w} \{h} in \{cx0} \{cy0} \{cx1} \{cy1}" +
        (if shown { "" } else { " hidden" }),
      )
    None => @host.view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, shown)
  }
}

///|
fn h_view_close(id : Int) -> Unit {
  outside_end(outside_view, id)
  views_told.remove(id)
  match fake.val {
    Some(f) => f.views.push("close \{id}")
    None => @host.view_close(id)
  }
}

///|
fn h_view_control(id : Int, op : Int, value : Double) -> Unit {
  match fake.val {
    Some(f) => f.views.push("control \{id} \{op} \{value}")
    None => @host.view_control(id, op, value)
  }
}

///|
fn h_view_info(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    // as the run recorded the host's saying it (Tester::view_said)
    Some(f) if f.view_infos.get(id) is Some((state, at)) => {
      for i in 0..<10 {
        out[i] = at[i]
      }
      state
    }
    // a test that says when views are ready: not yet, until it does
    Some(f) if !f.auto_finish && f.view_ready.get(id).unwrap_or(0) != 1 => {
      for i in 0..<10 {
        out[i] = 0.0
      }
      f.view_ready.get(id).unwrap_or(0)
    }
    Some(f) if f.players.get(id) is Some(p) => {
      for i in 0..<10 {
        out[i] = p[i]
      }
      1
    }
    Some(_) => {
      out[0] = 10000.0
      out[1] = 0.0
      out[2] = 0.0
      out[3] = 640.0
      out[4] = 360.0
      out[5] = 0.0
      out[6] = 1.0
      out[7] = 0.0
      out[8] = 0.0
      out[9] = 0.0
      ignore(id)
      1
    }
    None => {
      let state = @host.view_info(id, out)
      view_info_told(id, state, out)
      state
    }
  }
}

///|
fn h_view_site_next(id : Int) -> String {
  match fake.val {
    Some(f) => {
      ignore(id)
      if f.site.length() > 0 {
        f.site.remove(0)
      } else {
        ""
      }
    }
    None => {
      let e = @host.view_site_next(id)
      // (what the page asked of its host, on a run's record: Tester::view_said gives it again)
      if e != "" {
        site_told(id, e)
      }
      e
    }
  }
}

///|
/// A site view's page's event (a request, one let go, a link left by: view_site_next's JSON), told to the app's
/// tracer and the tape as `{"site":{"view":N,"event":E}}`.
fn site_told(id : Int, event : String) -> Unit {
  guard views_tracer.val is Some(_) || taping() else { return }
  view_say({ "site": Json::object({ "view": Json::number(id.to_double()), "event": site_event_kept(event) }) })
}

///|
/// What a record keeps of a site's page's event: all but what would carry who it is (a record is committed with the
/// tests): a credential's header (Authorization, Cookie, Set-Cookie, one whose name says token, key, secret, auth or
/// session) and such a field of the path's query, each kept as "-", what a Tester's host then gives in its place.
fn site_event_kept(event : String) -> Json {
  match (try Some(@json.parse(event)) catch { _ => None }) {
    Some(Object(m)) => {
      let out = m.copy()
      match m.get("headers") {
        Some(Array(hs)) =>
          out["headers"] = Json::array(
            hs.map(fn(h) {
              match h {
                Array([String(k), String(_)]) if secret_name(k) => Json::array([Json::string(k), Json::string("-")])
                _ => h
              }
            }),
          )
        _ => ()
      }
      match m.get("path") {
        Some(String(p)) => out["path"] = Json::string(query_kept(p))
        _ => ()
      }
      Json::object(out)
    }
    _ => Json::string("-")
  }
}

///|
/// What a record keeps of a site's request's body: a JSON object's or a form's credential fields "-" (as
/// site_event_kept's); other words that name one, "-" whole; else as it was.
fn site_body_kept(b : Bytes) -> Bytes {
  // (its bytes a char each: the JSON's or the form's names are ASCII, what else is in it kept byte for byte)
  let s = String::from_array(Array::makei(b.length(), fn(i) { b[i].to_int().unsafe_to_char() }))
  let bytes_of = fn(t : String) -> Bytes {
    Bytes::makei(t.length(), fn(i) { t.unsafe_charcode_at(i).to_byte() })
  }
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Object(_) as j) => {
      let kept = json_kept(j)
      if kept == j {
        b
      } else {
        bytes_of(kept.stringify())
      }
    }
    _ =>
      if s.contains("=") && !s.contains(" ") && !s.contains("\n") {
        let kept = query_kept("?" + s)
        let kept = kept.unsafe_substring(start=1, end=kept.length())
        if kept == s {
          b
        } else {
          bytes_of(kept)
        }
      } else if secret_name(s) {
        b"-"
      } else {
        b
      }
  }
}

///|
/// A JSON value with its objects' credential fields "-".
fn json_kept(j : Json) -> Json {
  match j {
    Object(m) => {
      let out : Map[String, Json] = {}
      for k, v in m {
        out[k] = if secret_name(k) { Json::string("-") } else { json_kept(v) }
      }
      Json::object(out)
    }
    Array(xs) => Json::array(xs.map(json_kept))
    _ => j
  }
}

///|
/// Whether a header's or a query field's name says it carries a credential.
fn secret_name(name : String) -> Bool {
  let n = name.to_lower()
  n == "cookie" ||
  n == "set-cookie" ||
  ["auth", "token", "key", "secret", "session", "password", "sig"].iter().any(fn(w) { n.contains(w) })
}

///|
/// A path with its query's credential fields' values "-".
fn query_kept(path : String) -> String {
  match path.find("?") {
    None => path
    Some(q) => {
      let fields = path.unsafe_substring(start=q + 1, end=path.length()).split("&").map(fn(f) {
        let f = f.to_string()
        match f.find("=") {
          Some(i) if secret_name(f.unsafe_substring(start=0, end=i)) => f.unsafe_substring(start=0, end=i) + "=-"
          _ => f
        }
      })
      path.unsafe_substring(start=0, end=q) + "?" + fields.collect().join("&")
    }
  }
}

///|
/// What was last told of each site view's page (view_site_state's JSON), so that it is told as it changes.
let sites_told_state : Map[Int, String] = {}

///|
fn h_view_site_body(id : Int, req : Int) -> Bytes {
  match fake.val {
    // as the run recorded it (Tester::view_said); else none
    Some(f) => f.site_bodies.get((id, req)).unwrap_or(Bytes::new(0))
    None => {
      let b = @host.view_site_body(id, req)
      if views_tracer.val is Some(_) || taping() {
        view_say({
          "sitebody": Json::object({ "view": Json::number(id.to_double()), "req": Json::number(req.to_double()) }),
          "b": Json::string(hex_of(site_body_kept(b))),
        })
      }
      b
    }
  }
}

///|
fn h_view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  match fake.val {
    Some(f) => f.views.push("site head \{id} \{req} \{status} \{headers}")
    None => @host.view_site_head(id, req, status, headers)
  }
}

///|
fn h_view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  match fake.val {
    Some(f) => f.views.push("site chunk \{id} \{req} \{data.length()}")
    None => @host.view_site_chunk(id, req, data)
  }
}

///|
fn h_view_site_end(id : Int, req : Int, error : String) -> Unit {
  outside_answered(id)
  match fake.val {
    Some(f) => f.views.push("site end \{id} \{req} \{error}")
    None => @host.view_site_end(id, req, error)
  }
}

///|
fn h_view_site_state(id : Int) -> String {
  match fake.val {
    // as the run recorded the host's saying it (Tester::view_said); not said: at its start, loaded, untitled
    Some(f) =>
      f.site_states.get(id).unwrap_or(
        "{\"path\":\"/\",\"back\":false,\"forward\":false,\"loading\":false,\"title\":\"\"}",
      )
    None => {
      let st = @host.view_site_state(id)
      if st != "" && (views_tracer.val is Some(_) || taping()) && sites_told_state.get(id) != Some(st) {
        sites_told_state[id] = st
        let j : Json = @json.parse(st) catch { _ => Json::string(st) }
        view_say({ "sitestate": Json::object({ "view": Json::number(id.to_double()), "state": j }) })
      }
      st
    }
  }
}

///|
fn h_view_text(id : Int, what : Int) -> String? {
  match fake.val {
    // as the run recorded the host's saying it (Tester::view_said); not said yet: not known (a grab: none asked). A
    // grab said ready before its frame is said ("2", then the `still` line: a host says both in one frame, a replay may
    // give them a frame apart): still grabbing until the frame is here, not ready with none
    Some(f) =>
      match f.view_texts.get((id, what)) {
        Some("2") if what == 2 && !(f.view_stills.get(id) is Some(q) && q.length() > 0) => Some("1")
        Some(t) => Some(t)
        None => if what == 2 { Some("0") } else { None }
      }
    None => {
      let t = @host.view_text(id, what)
      match t {
        Some(text) => view_told(id, what, text)
        None => ()
      }
      t
    }
  }
}

///|
fn h_view_still(id : Int) -> Bytes {
  match fake.val {
    // the oldest grabbed, taken (the grab's state back to none asked, as a host's)
    Some(f) => {
      let b = match f.view_stills.get(id) {
        Some(q) if q.length() > 0 => q.remove(0)
        _ => b""
      }
      if f.view_texts.get((id, 2)) == Some("2") {
        f.view_texts[(id, 2)] = "0"
      }
      b
    }
    None => {
      let b = @host.view_still(id)
      if views_tracer.val is Some(_) || taping() {
        view_say({ "still": Json::object({ "view": Json::number(id.to_double()) }), "b": Json::string(hex_of(b)) })
      }
      b
    }
  }
}

///|
/// Who is told what the host says of its views (@ui.trace_views): a run's record of it.
// kept across runs: the app's own, set once as it starts (a Tester's host says nothing to it)
let views_tracer : Ref[((Map[String, Json]) -> Unit)?] = Ref::new(None)

///|
/// What was last told of each view's answers (view, what), so that each is told once as it changes.
let views_told_text : Map[(Int, Int), String] = {}

///|
/// What a real host says of its native views from now on given to `line`, a JSON object a time, as it changes: how a
/// view stands (`{"info":{"view":N,"state":S,"at":[view_info's ten numbers]}}`), a video's frames' times and a grab's
/// state (`{"view":{"view":N,"what":W,"text":T}}`) and a frame grabbed, its bytes in hex (`{"still":{"view":N},"b":HEX}`);
/// a site view's page's events (`{"site":…}`), its requests' bodies (`{"sitebody":…}`) and where it is
/// (`{"sitestate":…}`): what a run keeps beside its other messages (its own clock added), for a
/// Tester to be told again (Tester::view_said). Under a Tester, nothing.
pub fn trace_views(line : (Map[String, Json]) -> Unit) -> Unit {
  views_tracer.val = Some(line)
}

///|
fn view_told(id : Int, what : Int, text : String) -> Unit {
  guard views_tracer.val is Some(_) || taping() else { return }
  if views_told_text.get((id, what)) == Some(text) {
    return
  }
  views_told_text[(id, what)] = text
  view_say({
    "view": Json::object({
      "view": Json::number(id.to_double()),
      "what": Json::number(what.to_double()),
      "text": Json::string(text),
    }),
  })
}

///|
/// What was last told of each view's state (view_info: its state and numbers), so that it is told as it changes.
let views_told_info : Map[Int, String] = {}

///|
fn view_info_told(id : Int, state : Int, out : FixedArray[Double]) -> Unit {
  guard views_tracer.val is Some(_) || taping() else { return }
  let at = Json::array(Array::makei(10, fn(i) { Json::number(out[i]) }))
  let key = "\{state} " + at.stringify()
  if views_told_info.get(id) == Some(key) {
    return
  }
  views_told_info[id] = key
  view_say({
    "info": Json::object({
      "view": Json::number(id.to_double()),
      "state": Json::number(state.to_double()),
      "at": at,
    }),
  })
}

///|
/// What the host said of a view, told: to the app's tracer (@ui.trace_views), and on a run's tape (VIEWSAID lines in
/// their place among its frames: what Tester::replay_frames and a screen's Tester say again, Tester::view_said).
fn view_say(m : Map[String, Json]) -> Unit {
  if taping() {
    tape_line("VIEWSAID " + Json::object(m).stringify())
  }
  match views_tracer.val {
    Some(t) => t(m)
    None => ()
  }
}

///|
fn hex_of(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    out.write_char(digits.get_char(v >> 4).unwrap())
    out.write_char(digits.get_char(v & 15).unwrap())
  }
  out.to_string()
}

///|
fn h_view_site_load(id : Int, path : String) -> Unit {
  match fake.val {
    Some(f) => f.views.push("site load \{id} \{path}")
    None => @host.view_site_load(id, path)
  }
}

///|
fn h_view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    Some(f) => fake_read_next(f, id, out)
    None => @host.view_read_next(id, out)
  }
}

///|
fn h_view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit {
  outside_answered(id)
  match fake.val {
    Some(f) => f.read_answers.push((id, req, data.length(), total))
    None => @host.view_read_answer(id, req, data, total)
  }
}

// PDFs (native.mbt Pdf): the fake host's every PDF has 3 pages of 612 × 792 points; a page drawn is an image of that
// shape.

///|
fn h_pdf_open(data : Bytes) -> Int {
  let named = (bytes_name(data), data.length())
  match fake.val {
    Some(f) => {
      f.views.push("pdf \{data.length()}")
      let doc = 7 + f.pdfs.length()
      f.pdfs[doc] = named
      doc
    }
    None => {
      let doc = @host.pdf_open(data)
      if text_recording() {
        g().host_rec.pdfs[doc] = named
      }
      doc
    }
  }
}

///|
/// A PDF's answers' head: its bytes' name and length, and `more`.
fn pdf_head(named : (String, Int), more : Array[Int]) -> Json {
  let a : Array[Json] = [Json::string(named.0), Json::number(named.1.to_double())]
  for m in more {
    a.push(Json::number(m.to_double()))
  }
  Json::array(a)
}

///|
fn h_pdf_pages(doc : Int) -> Int {
  match fake.val {
    Some(f) =>
      match f.pdfs.get(doc) {
        // as the host counted them, when kept with the text; else the fake's 3
        Some(named) if text_table.val is Some(_) =>
          match kept_answer("pn", pdf_head(named, [])) {
            Some(Number(n, ..)) => n.to_int()
            _ => 3
          }
        Some(_) => 3
        None => -1
      }
    None => {
      let n = @host.pdf_pages(doc)
      match g().host_rec.pdfs.get(doc) {
        Some(named) if text_recording() => {
          let line : Json = { "pn": pdf_head(named, []), "r": Json::number(n.to_double()) }
          text_say(line.stringify(), line)
        }
        _ => ()
      }
      n
    }
  }
}

///|
fn h_pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  match fake.val {
    Some(f) => {
      out[0] = 612.0
      out[1] = 792.0
      match f.pdfs.get(doc) {
        Some(named) if text_table.val is Some(_) =>
          match kept_answer("ps", pdf_head(named, [page])) {
            Some(Array([Number(w, ..), Number(h, ..), ..])) => {
              out[0] = w
              out[1] = h
            }
            _ => ()
          }
        _ => ()
      }
    }
    None => {
      @host.pdf_page_size(doc, page, out)
      match g().host_rec.pdfs.get(doc) {
        Some(named) if text_recording() => {
          let line : Json = { "ps": pdf_head(named, [page]), "r": nums(out, 2) }
          text_say(line.stringify(), line)
        }
        _ => ()
      }
    }
  }
}

///|
fn h_pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  let id = match fake.val {
    Some(f) =>
      match f.pdfs.get(doc) {
        Some(named) if text_table.val is Some(_) => {
          f.image_loads.push(("pdf:\{doc}/\{page}", max_px))
          match kept_sizes(kept_answer("pi", pdf_head(named, [page, max_px]))) {
            Some((w, h, ow, oh)) => fake_image_sized(f, w, h, ow, oh)
            None => fake_image(f, 1224, 1584, max_px)
          }
        }
        _ => {
          f.image_loads.push(("pdf:\{doc}/\{page}", max_px))
          fake_image(f, 1224, 1584, max_px)
        }
      }
    None => {
      let id = @host.pdf_page_load(doc, page, max_px)
      match g().host_rec.pdfs.get(doc) {
        Some(named) if text_recording() => rec_image_asked(id, { "pi": pdf_head(named, [page, max_px]) })
        _ => ()
      }
      id
    }
  }
  outside_start(outside_image, id, "image \{id} (PDF \{doc}, page \{page})")
  id
}

///|
fn h_pdf_close(doc : Int) -> Unit {
  match fake.val {
    Some(f) => f.views.push("pdf close \{doc}")
    None => @host.pdf_close(doc)
  }
}

///|
/// The pointer's shape (desktop.mbt Cursor's code).
fn h_set_cursor(kind : Int) -> Unit {
  match fake.val {
    Some(f) => f.cursor = kind
    None => @host.set_cursor(kind)
  }
}

///|
/// The press under way drags the window (the app's own title row).
fn h_window_drag() -> Unit {
  match fake.val {
    Some(f) => f.window_drags = f.window_drags + 1
    None => @host.window_drag()
  }
}
