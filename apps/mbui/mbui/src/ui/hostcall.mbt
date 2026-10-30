// Every call to the platform goes through here, so tests can swap in a fake
// host: no window, no GPU, deterministic text metrics and a clock the test
// advances.

///|
struct FakeHost {
  mut time : Double
  /// how late the frame drawn at `late_after` reached the screen, as said of it (Tester::frame_late, a run's LATE line):
  /// what the first frame drawn after then says (frame `late_frame`, once it is drawn); every other frame's was on time
  mut late : Double
  mut late_after : Double
  mut late_frame : Int
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
  /// how many times the field was said to the host (set_ime)
  mut ime_told : Int
  /// the floating text menu as the host was last told it (text_menu): shown, where, what it offers; and what the menu
  /// bar's editing items can do (edit_can; -1 not told)
  mut text_menu : (Bool, Double, Double, Double, Double, Int)
  mut edit_can : Int
  mut clipboard : String
  /// the last words put there were a secret: taken off this long after (Ctx::copy_secret); -1 not a secret
  mut clipboard_secret : Double
  /// the picture last put on the clipboard (its bytes' length; -1 none)
  mut clipboard_image : Int
  // whether the app takes back (a page to go back to), as last told
  mut back_on : Bool
  // the system it plays (as @hostapi.platform: 0 macOS, 1 iOS, 2 Android)
  platform : Int
  // what the person points with (Tester::new's `pointing`: by default its system's; as the host says its events came,
  // where it does: Tester::host_says_finger)
  mut pointing : Pointing
  // what the host says the pointer's events come from (@hostapi.event_finger: 1 a finger, 0 a mouse, -1 not said)
  mut event_finger : Int
  // what the app was started to be used with (Tester::new's `native`: by default its system's)
  native : Pointing
  // a keyboard at hand (Tester::new's `keyboard`, by default its system's: a desktop's; Tester::set_keyboard)
  mut keyboard : Bool
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
  // what the app's words' face (face_ui), once given, adds to a cluster's advance in what is set in it, in ems (0 by
  // default: a face given measures as the system's)
  mut ui_face : Double
  // native views: what was asked of them, a line each ("open 1 video/mp4", "place 1 0 0 390 220 shown"…)
  views : Array[String]
  mut view_ids : Int
  /// the views' readiness as the host's event told it (1 ready, -1 failed); not here: not yet
  view_ready : Map[Int, Int]
  /// how many times the app read how a view stands (view_info): only as the host said it changed (outside_stood)
  mut view_reads : Int
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
  /// what the app asked of the window's own buttons (@hostapi.window_act: 1 minimize, 2 maximize or back, 3 close),
  /// oldest first; whether the window is maximized (Tester::set_window_zoomed); where the app last said its maximize
  /// button is (window_snap, (x, y, w, h)) and how the pointer stands on it as the host would say (Tester::set_window_snap)
  window_acts : Array[Int]
  mut zoomed : Bool
  mut snap : (Double, Double, Double, Double)
  mut snap_state : Int
  /// whether the app can open a window of its own (Tester::set_window_opens), and what it opened them for, oldest first
  /// (@hostapi.window_open)
  mut window_opens : Bool
  windows_opened : Array[String]
  /// the number on the app's icon as last told (@ui.set_badge)
  mut badge : Int
  /// this machine's station as its host would say it (Tester::set_local_station), what was done to it
  mut local_station : String
  local_acts : Array[String]
  /// the font families installed as its host would say them (Tester::set_local_fonts), JSON; the families given to
  /// faces, by face (@ui.face_add_family)
  mut local_fonts : String
  families_given : Map[Int, String]
  /// the font files (by where they are) its host could not read as a font (Tester::set_unreadable_font)
  unreadable_fonts : Array[String]
  /// the keys held down as the test says (Tester::hold_mods)
  mut mods : Int
  /// the URLs handed to the system (Ctx::open_url), oldest first
  opened : Array[String]
  /// what the app reads of where it runs (hostread.mbt): the system dark, the window's buttons in the app's top row,
  /// the environment, the build's version code
  mut dark : Bool
  mut inset : Bool
  /// the window filling the screen (Ctx::set_full_screen), as last made to
  mut full : Bool
  /// how round the system draws the window's corners (Tester::new's `window_corner`; none filling the screen), and
  /// each of them where they differ (Tester::new's `window_corners`: top left, then round it)
  window_corner : Double
  window_corners : FixedArray[Double]?
  /// the system's size of words (font_scale: 1 as it is)
  mut font_scale : Double
  /// whether the system lays out the app's tabs itself (an iPhone Duo's: Tester::set_nav_able), and the bars the app
  /// handed it last (@hostapi.nav_bar's JSON; "" none yet)
  mut nav_able : Bool
  mut nav_said : String
  /// something reading the widgets out (a11y_on), and what it was last told they are (a11y.mbt)
  mut a11y : Bool
  mut a11y_said : String
  env : Map[String, String]
  app_version : Int
  /// the system's notifications the app shows, oldest first (notify.mbt), and the one tapped, not yet taken
  notices : Array[Notice]
  mut notice_opened : String
  /// the packages handed to the system's installer (@ui.install_package), oldest first: their names
  installs : Array[String]
  /// what the notice holding the app up says (@ui.hold_words): its channel, title and line
  mut hold_words : (String, String, String)?
  /// how the app over another app was ended (@ui.over_done), each time: whether on into the app
  overs_done : Array[Bool]
  /// what the system lets the app show ("granted", "denied", "ask", "unknown": Tester::set_notice_permission), what
  /// the person answers when asked (None: never), how often the app asked, and the answer due: from the frame after it
  mut notice_perm : String
  mut notice_reply : Bool?
  mut notice_asks : Int
  mut notice_due : (Bool, Int)?
  /// how often the system's settings of the app's notifications were opened (notice_settings)
  mut notice_settings : Int
  /// the PDFs opened, by their ids: their bytes' name and length (what their kept answers are by)
  pdfs : Map[Int, (String, Int)]
  /// what the system's pickers give (Tester::picks), what was asked of them (files.mbt), the files kept on the device
  picks : Array[@hostapi.Picked]
  pick_asks : Array[FakePick]
  keeps : Array[FakeKeep]
  /// the device's gallery as the test says it is now (Tester::gallery; None: it gave none, the app not let read one),
  /// and the reads of it asked (files.mbt)
  mut gallery : Array[@hostapi.GalleryPhoto]?
  gallery_reads : Array[FakeGalleryRead]
  /// what its players ask of the app's bytes and let go of, not taken yet (Tester::view_reads, view_lets_go), and what
  /// the app gave, piece by piece: the view, the read, how many bytes, the whole's length, whether more comes
  /// (hostmedia.mbt)
  reads : Array[FakeRead]
  mut read_ids : Int
  read_answers : Array[(Int, Int, Int, Double, Bool)]
  /// where each read the app took is from, by its view and number
  read_from : Map[(Int, Int), Double]
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
  /// what each page's host says, by view, oldest first (Tester::view_says, site_no_answer, site_too_slow; a run's
  /// record of it): taken before the views' common queue (`site`)
  site_of : Map[Int, Array[String]]
  /// the native views: their kind, where each was last placed (its clip rect: x0 y0 x1 y1) and whether shown, and who
  /// takes a finger on it (NativeView::touch: its mode, the slop), and where what takes a press is drawn over it (its
  /// rects: a finger there is the canvas's)
  view_kinds : Map[Int, Int]
  view_at : Map[Int, (Double, Double, Double, Double, Bool)]
  view_touch : Map[Int, (String, Double)]
  view_covers : Map[Int, Array[Double]]
  /// a finger's press as the views take it (Tester's own presses): the view it is on, (0: the canvas's), where it went
  /// down, where it is
  mut touch_view : Int
  mut touch_down : (Double, Double)
  /// where the finger on a page's view is now, and whether it went sideways past the slop first (VerticalOut: the
  /// page's to its end)
  mut touch_at : (Double, Double)
  mut touch_sideways : Bool
  /// the scripts sent to each page, waiting for it to be there (loaded, or said something since it started), and those
  /// run; whether each page is there; every script sent, as its tape line has it ("view length hash")
  scripts_waiting : Map[Int, Array[String]]
  scripts_run : Map[Int, Array[String]]
  page_there : Map[Int, Bool]
  scripts_sent : Array[String]
  /// streams (stream.mbt): whether it decodes H.264 (Tester::new's `h264`; a run's ENV line), the streams opened, what
  /// each was handed (Tester::stream_fed), and each one's events to come (Tester::stream_shows, stream_drops,
  /// stream_broken; a run's, Tester::view_said), taken as the next frame begins
  mut audio_here : Bool
  mut h264 : Bool
  /// whether it decodes H.265 (Tester::set_h265; a run's ENV line)
  mut h265_here : Bool
  /// whether its H.264 decoder is driven from here (stream_feed.mbt: Tester::set_stream_feeds; a run's ENV line)
  mut stream_feeds : Bool
  /// whether a stream may be shown by a system video layer of the host's (stream.mbt: Tester::set_stream_layers; a
  /// run's ENV line)
  mut stream_layers : Bool
  /// whether those layers show a frame as sRGB, not in its tagged colours (Tester::set_stream_layers_srgb; a run's
  /// ENV line, "layer":2)
  mut stream_layers_srgb : Bool
  mut stream_ids : Int
  streams_fed : Map[Int, Array[String]]
  stream_said : Map[Int, Array[String]]
  /// the device beyond the window (device.mbt): awake, haptics, the clipboard's picture and reads, the keyboard's height
  dev : FakeDevice
  /// pictures' pixels as the test made them up (Tester::add_pixels), by source; and those of the images loaded from
  /// them, by image
  pixels_of_src : Map[String, FixedArray[Byte]]
  pixels_of : Map[Int, FixedArray[Byte]]
  /// a real host asked in its place for what is drawn by (Tester::new's `live`), and its pictures, by the fake's ids
  live : Live?
  live_images : Map[Int, Int]
  /// the words of each shot taken (shot.mbt), in the order they were drawn in it: a test's (Tester::shots)
  shots : Array[Array[String]]
}

///|
/// A real host a Tester asks in place of its fake for what it draws by (Tester::new's `live`): its text (fonts'
/// metrics, shaping, the glyphs and their places in its atlas, its words), the faces given to it, its pictures,
/// decoded there (their sizes, their pixels). Only a program with the platform's host has one: a film's
/// (mbui/src/film, `@hostapi.host()` asked before the Tester is made), whose frames that host's renderer draws as
/// they are. A test never does. `turn`: the host given a moment for what it was asked (its main queue turned: a
/// picture's decode told).
pub(all) struct Live {
  host : &@hostapi.Host
  turn : () -> Unit
}

///|
/// The real host the Tester asks in place of its fake (Tester::new's `live`), None in a test.
fn live_of() -> Live? {
  match fake.val {
    Some(f) => f.live
    None => None
  }
}

///|
/// The most turns a live host is given to decode a picture (Live::turn): what it has not decoded by then failed.
let live_turns_most = 3000

///|
/// A picture asked of the live host (its id there `mine`), decoded there: the fake's image of its sizes (failed if it
/// did not decode), the host's kept by it (Tester::live_image); the answer recorded as a host's is.
fn live_image(f : FakeHost, l : Live, mine : Int, head : Json) -> Int {
  let info = FixedArray::make(4, 0.0)
  let mut st = l.host.image_info(mine, info)
  let mut turns = 0
  while st == 0 && turns < live_turns_most {
    (l.turn)()
    st = l.host.image_info(mine, info)
    turns = turns + 1
  }
  let id = if st == 1 {
    fake_image_sized(f, info[0], info[1], info[2], info[3])
  } else {
    fake_image_sized(f, 0.0, 0.0, 0.0, 0.0)
  }
  f.live_images[id] = mine
  rec_image_asked(id, head)
  if st == 1 {
    rec_image_ready(id, info)
  }
  id
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
    None => @hostapi.now()
  }
}

///|
fn h_wall_ms() -> Double {
  match fake.val {
    Some(f) => f.wall + f.time
    None => @hostapi.wall_ms()
  }
}

///|
/// How far local time is ahead of UTC at `at_ms`, in minutes: a Tester's is UTC's (0).
fn h_utc_offset_min(at_ms : Double) -> Int {
  match fake.val {
    Some(_) => 0
    None => @hostapi.utc_offset_min(at_ms)
  }
}

///|
/// How much later than its time the frame before this one reached the screen (@hostapi.frame_late): a Tester's as
/// said for this frame (Tester::frame_late, a run's LATE line), else on time.
fn h_frame_late() -> Double {
  match fake.val {
    Some(f) => {
      let c = g()
      if f.late_after < 0.0 || c.clock <= f.late_after {
        return 0.0
      }
      if f.late_frame < 0 {
        f.late_frame = c.frame_no
      }
      if f.late_frame == c.frame_no {
        f.late
      } else {
        f.late_after = -1.0
        0.0
      }
    }
    None => {
      let late = @hostapi.frame_late()
      // (kept on the tape, before the frame's DRAWHASH, for a Tester to draw the run again by: Tester::replay_frames)
      if late > 0.0 && taping() && late_taped.val != g().frame_no {
        late_taped.val = g().frame_no
        tape_line("LATE \{late}")
      }
      late
    }
  }
}

///|
/// The frame whose lateness was kept on the tape last (h_frame_late).
// kept across runs: a real host's alone, its frames numbered on from one run to the next (a Tester's lateness is not
// taped)
let late_taped : Ref[Int] = Ref(-1)

///|
/// What the pointer's event being handled came from, as the host says (@hostapi.event_finger; the fake host's:
/// Tester::host_says_finger): 1 a finger, 0 a mouse or a pen, -1 not said.
fn h_event_finger() -> Int {
  match fake.val {
    Some(f) => f.event_finger
    None => @hostapi.event_finger()
  }
}

///|
/// When the input event being handled happened (the host's, else now).
fn h_event_time() -> Double {
  match fake.val {
    Some(f) => f.time
    None => {
      let t = @hostapi.event_time()
      if t >= 0.0 {
        t
      } else {
        @hostapi.now()
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
        host_platform.val = @hostapi.platform()
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
/// Whose system's touches and fields this app has (`feel_as`): the host's own unless the app said another's. A
/// Tester's is the system it plays.
fn h_feel() -> Int {
  match fake.val {
    Some(f) => f.platform
    None => if feel_over.val >= 0 { feel_over.val } else { platform() }
  }
}

///|
/// The system whose touches and fields the app has from now on (as @hostapi.platform numbers them: 1 iOS's, 2
/// Android's), whatever it runs on: a list's fling and its edges' give, a field's tap, caret, handles
/// and words picked by a finger. For an app held to one system's original on another (still.fail's Android app on
/// iOS: 2). Its keys stay the system's own (⌘ on Apple's).
pub fn feel_as(platform : Int) -> Unit {
  feel_over.val = platform
}

///|
// kept across runs: what the app's main said once (feel_as); a Tester never reads it (h_feel answers its fake's)
let feel_over : Ref[Int] = { val: -1 }

///|
fn h_request_frame() -> Unit {
  // (asked from outside a frame: what asked changed what the view is built from, frame_watch.mbt)
  if !in_frame.val && !frame_running.val {
    outside_counted()
  }
  match fake.val {
    Some(f) => f.wants = true
    None => @hostapi.request_frame()
  }
}

///|
/// The host's next frame asked for what the frames' watch saw change (frame_watch.mbt): nothing come from outside.
fn h_frame_owed() -> Unit {
  match fake.val {
    Some(f) => f.wants = true
    None => @hostapi.request_frame()
  }
}

///|
/// The host's next frame asked for what moves on by the clock (a motion going on, a cycle shown): a Tester's host owes
/// no frame at this moment for it (its time goes by run_for).
fn h_request_frame_on() -> Unit {
  match fake.val {
    Some(_) => ()
    None => @hostapi.request_frame()
  }
}

///|
fn h_wake_after(ms : Double) -> Unit {
  match fake.val {
    Some(f) =>
      if f.wake < 0.0 || f.time + ms < f.wake {
        f.wake = f.time + ms
      }
    None => @hostapi.wake_after(ms)
  }
}

///|
fn h_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  if live_of() is Some(l) {
    l.host.font_metrics(size, weight, style, out)
    rec_metrics(size, weight, style, out)
    return
  }
  match fake.val {
    Some(_) if kept_metrics(size, weight, style, out) => ()
    Some(_) => {
      out[0] = size * 0.8
      out[1] = size * 0.2
      out[2] = (size * 1.42).round()
    }
    None => {
      @hostapi.font_metrics(size, weight, style, out)
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
  if live_of() is Some(l) {
    let k = l.host.shape(text, size, weight, style, out)
    rec_shape(text, size, weight, style, out, k)
    return k
  }
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
          if (style & @hostapi.style_mono) != 0 {
            size * 0.6
          } else {
            size * 0.5
          }
        } else {
          size
        }
        let adv = if weight >= 600 && c != 10 { adv + size * f.bold } else { adv }
        let adv = if f.ui_face != 0.0 && c != 10 && in_ui_face(style) { adv + size * f.ui_face } else { adv }
        out[k * 4] = i.to_double()
        out[k * 4 + 1] = len.to_double()
        out[k * 4 + 2] = adv
        // U+E000 plays a ligature's second letter: drawn as part of the cluster before it (unless shaped with no
        // ligatures)
        out[k * 4 + 3] = if c == 32 || c == 10 {
          -1.0
        } else if c == 0xE000 && k > 0 && (style & @hostapi.style_no_ligatures) == 0 {
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
      let k = @hostapi.shape(text, size, weight, style, out)
      rec_shape(text, size, weight, style, out, k)
      k
    }
  }
}

///|
/// Whether words in `style` are set in the app's words' face (face_ui) as a host sets them: one is given and the style
/// names no other (code's, the serif one, what people wrote's, one by its number).
fn in_ui_face(style : Int) -> Bool {
  face_given(@hostapi.face_ui) &&
  @hostapi.face_of_style(style) == 0 &&
  (style & (@hostapi.style_mono | @hostapi.style_serif | @hostapi.style_words)) == 0
}

///|
/// The key of `text` drawn as one piece (a word of a joining script).
fn h_text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  if live_of() is Some(l) {
    let k = l.host.text_key(text, size, weight, style)
    rec_key(text, size, weight, style, k)
    return k
  }
  match fake.val {
    Some(_) if kept_key(text, size, weight, style) is Some(k) => k
    Some(_) => text.at(0).to_int()
    None => {
      let k = @hostapi.text_key(text, size, weight, style)
      rec_key(text, size, weight, style, k)
      k
    }
  }
}

///|
fn h_glyph(key : Int, out : FixedArray[Double]) -> Unit {
  if live_of() is Some(l) {
    l.host.glyph(key, out)
    rec_glyph(key, out)
    return
  }
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
      @hostapi.glyph(key, out)
      rec_glyph(key, out)
    }
  }
}

///|
/// The picture of glyph `key`, drawn by the h_glyph asked last, put in the atlas at `x`, `y`: a fake host has no
/// pictures.
fn h_glyph_put(key : Int, x : Int, y : Int) -> Unit {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.glyph_put(key, x, y)
    Some(_) => ()
    None => @hostapi.glyph_put(key, x, y)
  }
}

///|
/// The side of a fake host's atlas: Android's and Windows' (its glyphs placed in it as a host's are), colour glyphs in
/// it with the others.
let fake_atlas_size : Int = 2048

///|
fn h_atlas_size(colour : Bool) -> Int {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.atlas_size(colour)
    Some(_) => if colour { 0 } else { fake_atlas_size }
    None => @hostapi.atlas_size(colour)
  }
}

///|
/// The glyphs of the first `n` of `keys` for the host to draw ahead (text.mbt glyphs_ahead): a Tester's hosts, fake
/// or live, draw each as it is asked for.
fn h_glyphs_ahead(keys : FixedArray[Int], n : Int) -> Unit {
  match fake.val {
    Some(_) => ()
    None => @hostapi.glyphs_ahead(keys, n)
  }
}

///|
/// A face's file given to the host (faces.mbt); a Tester's fake host takes any (its words measured as ever).
fn h_face_add(face : Int, path : String, weight : Int) -> Bool {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.face_add(face, path, weight)
    Some(f) => !f.unreadable_fonts.contains(path)
    None => @hostapi.face_add(face, path, weight)
  }
}

///|
fn h_face_add_bytes(face : Int, data : Bytes, weight : Int) -> Bool {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.face_add_bytes(face, data, weight)
    Some(_) => data.length() > 0
    None => @hostapi.face_add_bytes(face, data, weight)
  }
}

///|
fn h_face_add_family(face : Int, family : String) -> Bool {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.face_add_family(face, family)
    Some(f) => {
      f.families_given[face] = family
      true
    }
    None => @hostapi.face_add_family(face, family)
  }
}

///|
fn h_face_clear(face : Int) -> Unit {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.face_clear(face)
    Some(_) => ()
    None => @hostapi.face_clear(face)
  }
}

///|
fn h_atlas_generation() -> Int {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.atlas_generation()
    Some(_) => 0
    None => @hostapi.atlas_generation()
  }
}

///|
fn h_present(buf : FixedArray[Double], count : Int) -> Unit {
  match fake.val {
    Some(f) => f.instances = count
    None => {
      let c = g()
      let (r, gg, b) = c.clear
      // what of it differs from the frame presented before, the part a host that keeps its picture draws again
      // (docs/partial-redraw.md)
      let t0 = h_now()
      let parts = presented.next(buf, count, c.window_w, c.window_h, c.scale, r, gg, b)
      presented_ms.val = h_now() - t0
      if presented.telling() && presented.why() == 5 {
        h_log("DAMAGE whole, the part more than half: \{presented.told()}")
      }
      let mut area = 0.0
      for p in parts {
        let (x, y, w, h) = p
        @hostapi.render_dirty(x, y, w, h)
        area = if w < 0.0 || area < 0.0 { -1.0 } else { area + w * h }
      }
      if parts.is_empty() {
        @hostapi.render_dirty(0.0, 0.0, 0.0, 0.0)
      }
      presented_share.val = if area < 0.0 {
        1.0
      } else if c.window_w > 0.0 && c.window_h > 0.0 {
        area / (c.window_w * c.window_h)
      } else {
        0.0
      }
      @hostapi.present(buf, count, r, gg, b)
    }
  }
}

///|
/// The frames presented, the next compared with the last (h_present).
// kept across runs: a host's, whose picture is the last frame it was given
let presented : @damage.Damage = @damage.Damage::new()

///|
/// How much of the window the frame presented last drew again (1 all of it, 0 none), for the probe (app.mbt).
// kept across runs: the probe's (MBUI_PROBE), set by each frame presented before it is read
let presented_share : Ref[Double] = { val: 1.0 }

///|
/// How long working out the part took, for the probe.
// kept across runs: the probe's (MBUI_PROBE), set by each frame presented before it is read
let presented_ms : Ref[Double] = { val: 0.0 }

///|
fn h_reduce_transparency() -> Bool {
  match fake.val {
    Some(f) => f.reduce_transparency
    None => @hostapi.reduce_transparency() || h_env("MBUI_GLASS") == "solid"
  }
}

///|
fn h_gpu_ms() -> Double {
  match fake.val {
    Some(_) => -1.0
    None => @hostapi.gpu_ms()
  }
}

///|
fn h_cpu_ms() -> Double {
  match fake.val {
    Some(_) => -1.0
    None => @hostapi.cpu_ms()
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
      f.ime_told = f.ime_told + 1
    }
    None => @hostapi.set_ime(active, x, y, w, h, text, a, b)
  }
}

///|
fn h_text_menu(shown : Bool, x : Double, y : Double, w : Double, h : Double, can : Int) -> Unit {
  match fake.val {
    Some(f) => f.text_menu = (shown, x, y, w, h, can)
    None => @hostapi.text_menu(shown, x, y, w, h, can)
  }
}

///|
fn h_edit_can(can : Int) -> Unit {
  match fake.val {
    Some(f) => f.edit_can = can
    None => @hostapi.edit_can(can)
  }
}

///|
fn h_clipboard_set(s : String) -> Unit {
  match fake.val {
    Some(f) => {
      f.clipboard = s
      f.clipboard_secret = -1.0
    }
    None => @hostapi.clipboard_set(s)
  }
}

///|
/// The window made to fill the screen or back (@hostapi.set_full_screen); the fake host keeps it (@ui.full_screen).
fn h_set_full_screen(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.full = on
    None => @hostapi.set_full_screen(on)
  }
}

///|
/// A picture on the clipboard (@hostapi.clipboard_set_image); the fake host keeps how long it was (Tester::clipboard_image).
fn h_clipboard_image(data : Bytes) -> Unit {
  match fake.val {
    Some(f) => f.clipboard_image = data.length()
    None => @hostapi.clipboard_set_image(data)
  }
}

///|
/// A secret on the clipboard (@hostapi.clipboard_set_secret); the fake host keeps it as any words (Tester::clipboard)
/// and says it was a secret (Tester::clipboard_secret).
fn h_clipboard_secret(s : String, clear_ms : Double) -> Unit {
  match fake.val {
    Some(f) => {
      f.clipboard = s
      f.clipboard_secret = clear_ms
    }
    None => @hostapi.clipboard_set_secret(s, clear_ms~)
  }
}

///|
/// How many secrets were copied (Ctx::copy_secret): one's taking off is for it alone, not a later one's.
let secret_copies : Ref[Int] = Ref(0)

///|
/// The last secret copied taken off unless something else was copied since (@hostapi.clipboard_secret_off); the fake
/// host's while it is there still (Tester::clipboard empty again, Tester::clipboard_secret None).
fn h_clipboard_secret_off() -> Unit {
  match fake.val {
    Some(f) =>
      if f.clipboard_secret >= 0.0 {
        f.clipboard = ""
        f.clipboard_secret = -1.0
      }
    None => @hostapi.clipboard_secret_off()
  }
}

///|
/// The word of `text` around `off` as the host's word boundaries have it, (-1, -1) where it has none (the fake host:
/// words.mbt's own).
fn h_word_at(text : String, off : Int) -> (Int, Int) {
  let head : Json = [Json::string(text), Json::number(off.to_double())]
  match fake.val {
    Some({ live: Some(l), .. }) => {
      let (s, e) = l.host.word_at(text, off)
      if text_recording() {
        let line : Json = { "wa": head, "r": [Json::number(s.to_double()), Json::number(e.to_double())] }
        text_say("wa|" + head.stringify(), line)
      }
      (s, e)
    }
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
      let (s, e) = @hostapi.word_at(text, off)
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
    None => @hostapi.open_url(url)
  }
}

///|
/// A page in a browser's tab over the app (@hostapi.open_tab); the fake host keeps it as one handed to the system
/// (Tester::opened).
fn h_open_tab(url : String) -> Bool {
  match fake.val {
    Some(f) => {
      f.opened.push(url)
      true
    }
    None => @hostapi.open_tab(url)
  }
}

///|
fn h_a11y_on() -> Bool {
  match fake.val {
    Some(f) => f.a11y
    None => @hostapi.a11y_on()
  }
}

///|
fn h_a11y_tree(tree : String) -> Unit {
  match fake.val {
    Some(f) => f.a11y_said = tree
    None => @hostapi.a11y_tree(tree)
  }
}

///|
fn h_back_enabled(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.back_on = on
    None => @hostapi.back_enabled(on)
  }
}

// What the app waits on from the host (effect.mb's outside, src/effect/outside.mbt): an image or a PDF's page
// decoding, a native view until it is ready (a page loaded, a video's first frame), what the system's pickers give, the
// gallery read, marks drawn onto an image, a video's frame grabbed, an update downloading (the kinds below, named as
// the hosts name them). Each is a ticket of the window's runtime, ended by the host's event for it (@hostapi.set_outside:
// kind, id, state) or when the app lets it go or takes it; a run to a declared moment keeps its clock still while any
// is (@hostapi.frame_awaiting). A host that sends no such events (set_outside answers false) gets no tickets. An answer
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
/// What the system's pickers give (@hostapi.Pick's id).
let outside_pick = 3

///|
/// The gallery's photos read (@hostapi.GalleryRead's id).
let outside_gallery = 4

///|
/// Marks drawn onto an image (@hostapi.MarkedImage's id).
let outside_marks = 5

///|
/// A video's frame grabbed (its view's id).
let outside_grab = 6

///|
/// An update downloading (id 1): state 0 each time how it goes changes, while the host works at it; 1 once the host
/// works at it no more (handed to the installer, waiting on the person's leave), -1 failed.
let outside_update = 7

///|
/// A stream's frame handed over (stream.mbt), until its event says it decoded or was let go: the framework's own
/// number for it (the host tells no event of this kind: the stream's own events end it, as they are taken).
let outside_stream = 8

///|
/// The clipboard read (@hostapi.ClipRead's id: device.mbt).
let outside_clip = 9

///|
/// An app's own native call (@hostapi.NativeCall's id: native_call.mbt).
let outside_native = 10

///|
/// Something posted since the last frame took what was (messages.mbt): told by a host that has the app take, between
/// frames, what changes only signals (messages_between), a frame asked for only where something is left for one.
let outside_posted = 11

///|
/// A stream's host said something since (stream.mbt): told by a host whose streams show themselves (a system video
/// layer: @hostapi.stream_layers), what changes nothing drawn taken between frames (streams_said), a frame asked for
/// only where something is left for one.
let outside_streamed = 12

///|
/// How a native view stands (view_info) changed (its view's id): told by the host as it does, each change (a player's
/// frame shown, its clock's tick where it shows none, its size known, ready, buffering, ended…) its own event; the app
/// reads it as the next frame begins (native.mbt's views_arrive) into the view's signals, not each frame.
let outside_stood = 13

///|
/// Every kind above, by its name: each its own number (outside_kinds_wbtest.mbt), the hosts' named the same
/// (Native.java's OUTSIDE_*, apple.h's, win.h's and android_host.c's MB_OUTSIDE_*, web/host.js's OUTSIDE_*), every
/// `outside_*` here in it: scripts/chk outside-kinds, host_contract.sh HOST kinds
fn outside_kinds() -> Array[(String, Int)] {
  [
    ("image", outside_image),
    ("view", outside_view),
    ("pick", outside_pick),
    ("gallery", outside_gallery),
    ("marks", outside_marks),
    ("grab", outside_grab),
    ("update", outside_update),
    ("stream", outside_stream),
    ("clip", outside_clip),
    ("native", outside_native),
    ("posted", outside_posted),
    ("streamed", outside_streamed),
    ("stood", outside_stood),
  ]
}

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
fn outside_end(kind : Int, id : Int, wake? : Bool = true) -> Unit {
  let k = outside_key(kind, id)
  match outside_tickets.get(k) {
    Some(t) => {
      outside_tickets.remove(k)
      runtime().outside_end(t, wake~)
    }
    None => ()
  }
}

///|
/// How many answers of each kind (outside_*) have come, a signal each: what waits on one reads it (answer_here), so a
/// part kept or a computed that does follows the host's answers, as it follows the core's.
// kept across runs: they only count on
let answers_told : Array[@signals.Signal[Int]] = Array::makei(outside_native + 1, fn(_) { @signals.signal(0) })

///|
/// The answers the host told of (outside_key) not taken yet.
// kept across runs: emptied by each Tester (reset_globals)
let answers_waiting : Map[Int64, Bool] = Map::new()

///|
/// An answer of `kind` came (the host's event; under a Tester, a frame: its fake host's answers come by the frame).
fn answer_told(kind : Int) -> Unit {
  let s = answers_told[kind]
  s.set(@signals.untracked(fn() { s.get() }) + 1)
}

///|
/// Whether the host's answer of `kind` for `id` may be taken now, read as a signal (what reads it follows the
/// answers as they come): once the host's event told of it, not asked of the host before; a Tester's (its answers
/// come by the frame) and a host's that tells no events, whenever it is read.
fn answer_here(kind : Int, id : Int) -> Bool {
  answers_told[kind].get() |> ignore
  fake.val is Some(_) || !outside_told.val || answers_waiting.contains(outside_key(kind, id))
}

///|
/// The host's answer of `kind` for `id` taken.
fn answer_taken(kind : Int, id : Int) -> Unit {
  answers_waiting.remove(outside_key(kind, id))
}

///|
/// A Tester's frame begins: its fake host's answers that were waited on may have come with it (each comes from the
/// frame after it was asked or given), told as a host's event tells them.
fn answers_by_the_frame() -> Unit {
  if fake.val is None {
    return
  }
  let kinds : Map[Int, Bool] = {}
  for k, _ in outside_tickets {
    kinds[(k >> 32).to_int()] = true
  }
  for kind, _ in kinds {
    if kind < answers_told.length() && kind != outside_update {
      answer_told(kind)
    }
  }
}

///|
/// The native views the host said were ready (or failed): their work is the host's no more, whatever is asked after.
let views_told : Map[Int, Bool] = Map::new()

///|
/// The host's event: what it did for the app is done (`state`: 1 done, -1 failed), or (a view, 0) it waits on the
/// app now: the bytes a player reads, a site's answer. Until the app answers, the host does nothing for it.
fn on_outside(kind : Int, id : Int, state : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_outside_now(kind, id, state) })
}

///|
fn on_outside_now(kind : Int, id : Int, state : Int) -> Unit {
  // (not an answer: what came taken as it is, a frame only where something is left for one)
  if kind == outside_posted {
    messages_between()
    return
  }
  if kind == outside_streamed {
    streams_said(id)
    return
  }
  if kind == outside_stood {
    view_stood(id)
    return
  }
  outside_came()
  if kind == outside_update {
    // (how it goes changed: what it says now set, followed by what reads it; held while the host works at it)
    if fake.val is None {
      update_told.set(@hostapi.update_state())
    }
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
    if @hostapi.image_info(id, out) == 1 {
      rec_image_ready(id, out)
    }
  }
  outside_end(kind, id)
  // an answer brought (what was picked, read, drawn, grabbed: told, followed by what waits on it; a view the host is
  // done opening): read as the next frame builds
  let answer = kind == outside_pick ||
    kind == outside_gallery ||
    kind == outside_marks ||
    kind == outside_grab ||
    kind == outside_clip ||
    kind == outside_native
  if answer {
    answers_waiting[outside_key(kind, id)] = true
    answer_told(kind)
  }
  if answer || (kind == outside_view && state != 0) {
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
    None => @hostapi.log(s)
  }
}

///|
fn h_image_load(src : String, max_px : Int) -> Int {
  let head : Json = [Json::string(src), Json::number(max_px.to_double())]
  let id = match fake.val {
    Some({ live: Some(l), .. } as f) => {
      f.image_loads.push((src, max_px))
      live_image(f, l, l.host.image_load(src, max_px), { "is": head })
    }
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
      match f.pixels_of_src.get(src) {
        Some(px) => f.pixels_of[id] = px
        None => ()
      }
      // one it does not know failed at once: nothing of it is left to wait for
      match f.images.get(id) {
        Some(im) if im.state < 0 => return id
        _ => ()
      }
      id
    }
    None => {
      let id = @hostapi.image_load(src, max_px)
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
    Some({ live: Some(l), .. } as f) => {
      f.image_loads.push(("bytes:\{data.length()}", max_px))
      live_image(f, l, l.host.image_load_bytes(data, max_px), { "ib": head })
    }
    Some(f) => {
      f.image_loads.push(("bytes:\{data.length()}", max_px))
      // as the host decoded these bytes, when kept with the text; else a made-up 400 × 300
      match (text_table.val, kept_sizes(kept_answer("ib", head))) {
        (Some(_), Some((w, h, ow, oh))) => fake_image_sized(f, w, h, ow, oh)
        _ => fake_image(f, 400, 300, max_px)
      }
    }
    None => {
      let id = @hostapi.image_load_bytes(data, max_px)
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
      let st = @hostapi.image_info(id, out)
      if st == 1 {
        rec_image_ready(id, out)
      }
      st
    }
  }
}

///|
/// A ready image's pixels read back (premultiplied RGBA, rows from the top) into `out`: the fake host's as the test
/// made them (Tester::add_pixels), else every pixel a mid grey, opaque.
fn h_image_pixels(id : Int, out : FixedArray[Byte]) -> Bool {
  match fake.val {
    Some({ live: Some(l), .. } as f) if f.live_images.get(id) is Some(mine) => l.host.image_pixels(mine, out)
    Some(f) =>
      match f.images.get(id) {
        Some(im) if im.state == 1 => {
          let n = im.w.to_int() * im.h.to_int() * 4
          match f.pixels_of.get(id) {
            Some(px) if px.length() == n => px.blit_to(out, len=n)
            _ =>
              for i in 0..<n {
                out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
              }
          }
          true
        }
        _ => false
      }
    None => @hostapi.image_pixels(id, out)
  }
}

///|
/// Instances never presented (a shot's: shot.mbt) drawn as a frame is on the frame's ground, `scale` pixels a point into
/// a picture `w` by `h` of their own, and its pixels (as h_drawn_pixels) into `out`: a live Tester's host's, its
/// pictures that host's own as a film draws a frame (film.mbt draw_frame: one it has not, nothing), the fake host's every
/// pixel a mid grey, opaque.
fn h_drawn_pixels_of(
  inst : FixedArray[Double],
  count : Int,
  scale : Double,
  w : Int,
  h : Int,
  out : FixedArray[Byte],
) -> Bool {
  let (r, gg, b) = g().clear
  match fake.val {
    Some({ live: Some(l), .. } as f) => {
      let len = count * inst_size
      let mine = FixedArray::make(if len > 0 { len } else { 1 }, 0.0)
      inst.blit_to(mine, len~)
      for k in 0..<count {
        let at = k * inst_size
        if mine[at + 5] == 4.0 {
          match f.live_images.get(mine[at + 20].to_int()) {
            Some(id) => mine[at + 20] = id.to_double()
            None => {
              // nothing drawn: a rect of no colour, no border, no blur
              mine[at + 5] = 0.0
              for j in 6..<12 {
                mine[at + j] = 0.0
              }
            }
          }
        }
      }
      l.host.drawn_pixels_of(mine, count, r, gg, b, scale, w, h, out)
    }
    Some(_) => {
      for i in 0..<(w * h * 4) {
        out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
      }
      true
    }
    None => @hostapi.drawn_pixels_of(inst, count, r, gg, b, scale, w, h, out)
  }
}

///|
/// The last frame's pixels in a rectangle of it (device pixels; premultiplied RGBA, rows from the top) into `out`: a
/// live Tester's host's as it drew the frame (a film's), the fake host's every pixel a mid grey, opaque.
fn h_drawn_pixels(x : Int, y : Int, w : Int, h : Int, out : FixedArray[Byte]) -> Bool {
  match fake.val {
    Some({ live: Some(l), .. }) => l.host.drawn_pixels(x, y, w, h, out)
    Some(_) => {
      for i in 0..<(w * h * 4) {
        out[i] = if i % 4 == 3 { b'\xFF' } else { b'\x80' }
      }
      true
    }
    None => @hostapi.drawn_pixels(x, y, w, h, out)
  }
}

///|
fn h_image_free(id : Int) -> Unit {
  outside_end(outside_image, id)
  match fake.val {
    Some({ live: Some(l), .. } as f) => {
      f.images.remove(id)
      match f.live_images.get(id) {
        Some(mine) => {
          f.live_images.remove(id)
          l.host.image_free(mine)
        }
        None => ()
      }
    }
    Some(f) => f.images.remove(id)
    None => @hostapi.image_free(id)
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
      f.view_kinds[f.view_ids] = kind
      f.view_ids
    }
    None => @hostapi.view_open(kind, arg)
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
  r0 : Double,
  r1 : Double,
  r2 : Double,
  r3 : Double,
  shown : Bool,
) -> Unit {
  match fake.val {
    Some(f) => {
      f.views.push(
        "place \{id} \{x} \{y} \{w} \{h} in \{cx0} \{cy0} \{cx1} \{cy1}" +
        (if r0 == r1 && r1 == r2 && r2 == r3 {
          if r0 > 0.0 {
            " round \{r0}"
          } else {
            ""
          }
        } else {
          " round \{r0} \{r1} \{r2} \{r3}"
        }) +
        (if shown { "" } else { " hidden" }),
      )
      f.view_at[id] = (dmax(x, cx0), dmax(y, cy0), dmin(x + w, cx1), dmin(y + h, cy1), shown)
    }
    None => @hostapi.view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, r0, r1, r2, r3, shown)
  }
}

///|
fn h_view_close(id : Int) -> Unit {
  outside_end(outside_view, id)
  views_told.remove(id)
  match fake.val {
    Some(f) => {
      f.views.push("close \{id}")
      f.view_at.remove(id)
      f.scripts_waiting.remove(id)
      if f.touch_view == id {
        f.touch_view = 0
      }
    }
    None => @hostapi.view_close(id)
  }
}

///|
fn h_view_control(id : Int, op : Int, value : Double) -> Unit {
  match fake.val {
    Some(f) => f.views.push("control \{id} \{op} \{value}")
    None => @hostapi.view_control(id, op, value)
  }
}

///|
fn h_view_info(id : Int, out : FixedArray[Double]) -> Int {
  let state = h_view_info_of(id, out)
  // (a fake page there now runs what was sent to it)
  match fake.val {
    Some(f) => fake_scripts_flush(f, id)
    None => ()
  }
  state
}

///|
fn h_view_info_of(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    Some(f) => f.view_reads += 1
    None => ()
  }
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
      let state = @hostapi.view_info(id, out)
      view_info_told(id, state, out)
      state
    }
  }
}

///|
fn h_view_site_next(id : Int) -> String {
  match fake.val {
    Some(f) => {
      let e = match f.site_of.get(id) {
        Some(q) if q.length() > 0 => q.remove(0)
        _ => if f.site.length() > 0 { f.site.remove(0) } else { "" }
      }
      // (a page that said something is there: what was sent to it runs)
      if e.has_prefix("{\"said\"") {
        f.page_there[id] = true
        fake_scripts_flush(f, id)
      }
      e
    }
    None => {
      let e = @hostapi.view_site_next(id)
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
/// What the app tells a view's host beyond its controls (native.mbt): `what` 1 a script to run in its page
/// (NativeView::script), 2 who takes a finger on it (NativeView::touch: "all|through|pinch|vertical SLOP"), 3 a site's
/// settings (`{"head_wait_ms":…,"backlog":…}`), 4 where what takes a press is drawn over it ("x0 y0 x1 y1 …": a
/// finger there is the canvas's). The fake host notes each ("script 1 42 9a0b…", "touch 1 vertical 8",
/// "settings 1 …") and runs a page's scripts as a host does: once its page is there (ready and not loading, or said
/// something since it started), in the order sent.
fn h_view_tell(id : Int, what : Int, text : String) -> Unit {
  match fake.val {
    Some(f) => {
      if what == 1 {
        f.scripts_sent.push("\{id} \{text.length()} \{script_hash(text)}")
        match f.scripts_waiting.get(id) {
          Some(q) => q.push(text)
          None => f.scripts_waiting[id] = [text]
        }
        fake_scripts_flush(f, id)
      } else if what == 2 {
        let parts = text.split(" ").map(fn(p) { p.to_owned() }).to_array()
        let slop = match (try Some(@json.parse(parts.get(1).unwrap_or("0"))) catch { _ => None }) {
          Some(Number(n, ..)) => n
          _ => 0.0
        }
        f.view_touch[id] = (parts.get(0).unwrap_or("all"), slop)
        f.views.push("touch \{id} \{text}")
      } else if what == 4 {
        let rects : Array[Double] = []
        for p in text.split(" ") {
          match (try Some(@json.parse(p.to_owned())) catch { _ => None }) {
            Some(Number(n, ..)) => rects.push(n)
            _ => ()
          }
        }
        f.view_covers[id] = rects
      } else if what == 5 {
        f.views.push("raise \{id}")
      } else {
        f.views.push("settings \{id} \{text}")
      }
    }
    None => @hostapi.view_tell(id, what, text)
  }
}

///|
/// Whether a fake page is there for scripts: said something since it started, or ready and not loading.
fn fake_page_there(f : FakeHost, id : Int) -> Bool {
  if f.page_there.get(id) is Some(true) {
    return true
  }
  let ready = match f.view_infos.get(id) {
    Some((state, _)) => state == 1
    None => f.auto_finish || f.view_ready.get(id).unwrap_or(0) == 1
  }
  let loading = match f.site_states.get(id) {
    Some(st) =>
      match (try Some(@json.parse(st)) catch { _ => None }) {
        Some(Object(m)) => m.get("loading") is Some(True)
        _ => false
      }
    None => false
  }
  ready && !loading
}

///|
/// A fake page's scripts that wait run, in the order sent, once it is there.
fn fake_scripts_flush(f : FakeHost, id : Int) -> Unit {
  match f.scripts_waiting.get(id) {
    Some(q) if q.length() > 0 && fake_page_there(f, id) => {
      let run = match f.scripts_run.get(id) {
        Some(r) => r
        None => {
          let r = []
          f.scripts_run[id] = r
          r
        }
      }
      for js in q {
        run.push(js)
        f.views.push("script \{id} \{js.length()} \{script_hash(js)}")
      }
      q.clear()
    }
    _ => ()
  }
}

///|
fn h_view_site_body(id : Int, req : Int) -> Bytes {
  match fake.val {
    // as the run recorded it (Tester::view_said); else none
    Some(f) => f.site_bodies.get((id, req)).unwrap_or(Bytes::new(0))
    None => {
      let b = @hostapi.view_site_body(id, req)
      if views_tracer.val is Some(_) || taping() {
        view_say({
          "sitebody": Json::object({ "view": Json::number(id.to_double()), "req": Json::number(req.to_double()) }),
          "b": Json::string(@codec.hex(site_body_kept(b))),
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
    None => @hostapi.view_site_head(id, req, status, headers)
  }
}

///|
fn h_view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  match fake.val {
    Some(f) => f.views.push("site chunk \{id} \{req} \{data.length()}")
    None => @hostapi.view_site_chunk(id, req, data)
  }
}

///|
fn h_view_site_end(id : Int, req : Int, error : String) -> Unit {
  outside_answered(id)
  match fake.val {
    Some(f) => f.views.push("site end \{id} \{req} \{error}")
    None => @hostapi.view_site_end(id, req, error)
  }
}

///|
fn h_view_site_state(id : Int) -> String {
  match fake.val {
    // as the run recorded the host's saying it (Tester::view_said); not said: at its start, loaded, untitled
    Some(f) => {
      let st = f.site_states.get(id).unwrap_or(
        "{\"path\":\"/\",\"back\":false,\"forward\":false,\"loading\":false,\"title\":\"\"}",
      )
      fake_scripts_flush(f, id)
      st
    }
    None => {
      let st = @hostapi.view_site_state(id)
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
      let t = @hostapi.view_text(id, what)
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
      let b = @hostapi.view_still(id)
      if views_tracer.val is Some(_) || taping() {
        view_say({ "still": Json::object({ "view": Json::number(id.to_double()) }), "b": Json::string(@codec.hex(b)) })
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
/// (`{"sitestate":…}`); a stream's events as they are taken (`{"stream":{"id":N,"e":E}}`, stream.mbt): what a run keeps
/// beside its other messages (its own clock added), for a
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
fn h_view_site_load(id : Int, path : String) -> Unit {
  match fake.val {
    Some(f) => f.views.push("site load \{id} \{path}")
    None => @hostapi.view_site_load(id, path)
  }
}

///|
fn h_view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    Some(f) => fake_read_next(f, id, out)
    None => {
      let req = @hostapi.view_read_next(id, out)
      if req != 0 {
        view_read_told(id, req, out)
      }
      req
    }
  }
}

///|
/// A player's ask of the app's bytes (`req`, `out`'s offset and length), or one it let go of (`req` below 0), told to
/// the app's tracer as `{"read":{"view":N,"req":R,"offset":O,"length":L}}` (`{"read":{"view":N,"gone":R}}`): a run's
/// player's reads, for a Tester's host to ask again where the run's did (Tester::view_said). Not on a tape (what
/// mbui's own contracts replay asks none).
fn view_read_told(id : Int, req : Int, out : FixedArray[Double]) -> Unit {
  guard views_tracer.val is Some(t) else { return }
  let read : Map[String, Json] = { "view": Json::number(id.to_double()) }
  if req > 0 {
    read["req"] = Json::number(req.to_double())
    read["offset"] = Json::number(out[0])
    read["length"] = Json::number(out[1])
  } else {
    read["gone"] = Json::number((-req).to_double())
  }
  t({ "read": Json::object(read) })
}

///|
fn h_view_read_answer(id : Int, req : Int, data : Bytes, total : Double, more : Bool) -> Unit {
  outside_answered(id)
  match fake.val {
    Some(f) => f.read_answers.push((id, req, data.length(), total, more))
    None => @hostapi.view_read_answer(id, req, data, total, more)
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
      let doc = @hostapi.pdf_open(data)
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
      let n = @hostapi.pdf_pages(doc)
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
      @hostapi.pdf_page_size(doc, page, out)
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
      let id = @hostapi.pdf_page_load(doc, page, max_px)
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
    None => @hostapi.pdf_close(doc)
  }
}

///|
/// The pointer's shape (desktop.mbt Cursor's code).
fn h_set_cursor(kind : Int) -> Unit {
  match fake.val {
    Some(f) => f.cursor = kind
    None => @hostapi.set_cursor(kind)
  }
}

///|
/// The press under way drags the window (the app's own title row).
fn h_window_drag() -> Unit {
  match fake.val {
    Some(f) => f.window_drags = f.window_drags + 1
    None => @hostapi.window_drag()
  }
}

///|
fn h_window_act(what : Int) -> Unit {
  match fake.val {
    Some(f) => f.window_acts.push(what)
    None => @hostapi.window_act(what)
  }
}

///|
fn h_window_open(what : String) -> Bool {
  match fake.val {
    Some(f) => {
      if f.window_opens {
        f.windows_opened.push(what)
      }
      f.window_opens
    }
    None => @hostapi.window_open(what)
  }
}

///|
fn h_window_snap(x : Double, y : Double, w : Double, h : Double) -> Unit {
  match fake.val {
    Some(f) => f.snap = (x, y, w, h)
    None => @hostapi.window_snap(x, y, w, h)
  }
}
