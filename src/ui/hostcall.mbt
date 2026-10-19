// Every call to the platform goes through here, so tests can swap in a fake
// host: no window, no GPU, deterministic text metrics and a clock the test
// advances.

///|
struct FakeHost {
  mut time : Double
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
let fake : Ref[FakeHost?] = { val: None }

///|
fn h_now() -> Double {
  match fake.val {
    Some(f) => f.time
    None => @host.now()
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
let host_platform : Ref[Int] = { val: -1 }

///|
fn h_request_frame() -> Unit {
  match fake.val {
    Some(f) => f.wants = true
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
        // U+E000 plays a ligature's second letter: drawn as part of the cluster before it
        out[k * 4 + 3] = if c == 32 || c == 10 {
          -1.0
        } else if c == 0xE000 && k > 0 {
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
    None => @host.present(buf, count, 0.961, 0.961, 0.969)
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
  match fake.val {
    Some(_) => (-1, -1)
    None => @host.word_at(text, off)
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
// decoding (kind 1), a native view until it is ready (kind 2: a page loaded, a video's first frame). Each is a ticket
// of the window's runtime, ended by the host's event for it (@host.set_outside: kind, id, state) or when the app lets
// it go; what is shown is settled (Ctx::settled) once none is left. A host that sends no such events (set_outside
// answers false) gets no tickets: there, settled says nothing of its work.

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
  if kind == 2 && state != 0 {
    views_told[id] = true
  }
  outside_end(kind, id)
}

///|
/// The app answered what a view waits on (a read, a site's request): the host's again, until ready or it asks more.
fn outside_answered(id : Int) -> Unit {
  if !views_told.contains(id) && !outside_tickets.contains(outside_key(2, id)) {
    outside_start(2, id, "view \{id} (after the app's answer)")
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
  let id = match fake.val {
    Some(f) => {
      f.image_loads.push((src, max_px))
      let (w, h) = f.image_sizes.get(src).unwrap_or((0, 0))
      let id = fake_image(f, w, h, max_px)
      // one it does not know failed at once: nothing of it is left to wait for
      if w <= 0 {
        return id
      }
      id
    }
    None => @host.image_load(src, max_px)
  }
  outside_start(1, id, "image \{id} \{src}")
  id
}

///|
fn h_image_load_bytes(data : Bytes, max_px : Int) -> Int {
  let id = match fake.val {
    Some(f) => {
      f.image_loads.push(("bytes:\{data.length()}", max_px))
      fake_image(f, 400, 300, max_px)
    }
    None => @host.image_load_bytes(data, max_px)
  }
  outside_start(1, id, "image \{id} (\{data.length()} bytes)")
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
    None => @host.image_info(id, out)
  }
}

///|
fn h_image_free(id : Int) -> Unit {
  outside_end(1, id)
  match fake.val {
    Some(f) => f.images.remove(id)
    None => @host.image_free(id)
  }
}

// Native views (native.mbt): the fake host has views of every kind, ready at once, 10 s long and 640 × 360, that
// never ask to read; it notes what is asked of them (FakeHost.views).

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
  outside_start(2, id, "view \{id} (kind \{kind})")
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
  outside_end(2, id)
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
    // a test that says when views are ready: not yet, until it does
    Some(f) if !f.auto_finish && f.view_ready.get(id).unwrap_or(0) != 1 => {
      for i in 0..<10 {
        out[i] = 0.0
      }
      f.view_ready.get(id).unwrap_or(0)
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
    None => @host.view_info(id, out)
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
    None => @host.view_site_next(id)
  }
}

///|
fn h_view_site_body(id : Int, req : Int) -> Bytes {
  match fake.val {
    Some(_) => Bytes::new(0)
    None => @host.view_site_body(id, req)
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
    Some(_) => "{\"path\":\"/\",\"back\":false,\"forward\":false,\"loading\":false,\"title\":\"\"}"
    None => @host.view_site_state(id)
  }
}

///|
fn h_view_text(id : Int, what : Int) -> String? {
  match fake.val {
    // the fake player's video: three frames a 30th of a second apart
    Some(_) => if what == 1 { Some("0,33.333,66.667") } else { Some("0") }
    None => @host.view_text(id, what)
  }
}

///|
fn h_view_still(id : Int) -> Bytes {
  match fake.val {
    Some(_) => b""
    None => @host.view_still(id)
  }
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
    Some(_) => 0
    None => @host.view_read_next(id, out)
  }
}

///|
fn h_view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit {
  outside_answered(id)
  match fake.val {
    Some(_) => ()
    None => @host.view_read_answer(id, req, data, total)
  }
}

// PDFs (native.mbt Pdf): the fake host's every PDF has 3 pages of 612 × 792 points; a page drawn is an image of that
// shape.

///|
fn h_pdf_open(data : Bytes) -> Int {
  match fake.val {
    Some(f) => {
      f.views.push("pdf \{data.length()}")
      7
    }
    None => @host.pdf_open(data)
  }
}

///|
fn h_pdf_pages(doc : Int) -> Int {
  match fake.val {
    Some(_) => if doc == 7 { 3 } else { -1 }
    None => @host.pdf_pages(doc)
  }
}

///|
fn h_pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  match fake.val {
    Some(_) => {
      ignore(doc)
      ignore(page)
      out[0] = 612.0
      out[1] = 792.0
    }
    None => @host.pdf_page_size(doc, page, out)
  }
}

///|
fn h_pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  let id = match fake.val {
    Some(f) => {
      f.image_loads.push(("pdf:\{doc}/\{page}", max_px))
      fake_image(f, 1224, 1584, max_px)
    }
    None => @host.pdf_page_load(doc, page, max_px)
  }
  outside_start(1, id, "image \{id} (PDF \{doc}, page \{page})")
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
