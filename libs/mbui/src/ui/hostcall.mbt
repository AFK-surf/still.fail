// Every call to the platform goes through here, each asked of @hostapi's host whoever it is. A Tester's is its fake
// host (FakeHost, its answers in fake_host.mbt): no window, no GPU, deterministic text metrics and a clock the test
// advances.

///|
// generation_asks and view_reads are read by tests alone
#warnings("-unused_field")
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
  /// how many times the app asked for the host's next frame for what goes on by the clock (h_request_frame_on): owed
  /// no frame at this moment, as a host draws one at its next display frame (Tester::frames_on)
  mut frames_on : Int
  /// how many frames a second what moves on by the clock was last said to need (@hostapi.frames_paced), as a host is
  /// told it after the frame it asked for (0: none said since a frame was last asked for: the display's every frame)
  mut paced : Double
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
  /// the words of the app's own items of that menu as last told, a line each (text_menu_own)
  mut text_menu_own : String
  mut edit_can : Int
  mut clipboard : String
  /// the last words put there were a secret: taken off this long after (Ctx::copy_secret); -1 not a secret
  mut clipboard_secret : Double
  /// the picture last put on the clipboard (its bytes' length; -1 none)
  mut clipboard_image : Int
  // whether the app takes back (a page to go back to), as last told
  mut back_on : Bool
  // whether the last wheel handed in zoomed something of the app's, as told (@hostapi.wheel_kept)
  mut wheel_kept : Bool
  // how many times the window held (window_hold) was asked to be shown (@hostapi.window_show)
  mut window_shows : Int
  // the system it plays (as @hostapi.platform: 0 macOS, 1 iOS, 2 Android)
  platform : Int
  // the system whose keys are typed (keys_system: Tester::new's `keys`, by default `platform`'s; a browser's the one
  // under it)
  keys : Int
  // what the person points with (Tester::new's `pointing`: by default its system's; as the host says its events came,
  // where it does: Tester::host_says_finger)
  pointing : Pointing
  /// when the input event being handled happened, where the host says it so apart from its clock (a test's event
  /// taken late: Tester::touch_at); -1: as the clock has it
  mut event_at : Double
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
  /// what each decode asked for is of: its source (bytes handed over, the source they were handed for)
  image_srcs : Map[Int, String]
  images : Map[Int, FakeImage]
  /// the last decode's number: each new one the next, never one let go of again (as every host numbers them)
  mut image_ids : Int
  /// sources said to take a while to decode (Tester::decode_after): how many ms after each is asked for it is done
  decode_after : Map[String, Double]
  /// the decodes so said, by their id: the moment each is done (on the timeline: asked for, and that long after)
  decode_due : Map[Int, Double]
  /// the bytes handed over for each decode of bytes still kept (image_load_bytes, till image_free): what the host holds
  /// of them, as a phone's Java side kept a GIF's every frame's (#5301: 140 MB of a 256 MB heap); their sum now, and the
  /// most it came to in this Tester's run (Tester::host_image_bytes_most)
  image_bytes : Map[Int, Int]
  mut image_bytes_now : Int
  mut image_bytes_most : Int
  /// where the Tester was made (Tester::new's `loc`), said with what it held
  made_at : String
  // what bold adds to a cluster's advance, in ems (0 by default: weight
  // changes nothing)
  mut bold : Double
  // what the app's words' face (face_ui), once given, adds to a cluster's advance in what is set in it, in ems (0 by
  // default: a face given measures as the system's)
  mut ui_face : Double
  // its glyphs' generation (@hostapi.atlas_generation): moved on by Tester::glyphs_moved_on, as a host's is once a face
  // it was given is in (a page's, loaded after it is asked for), its scale changes or its atlas is lost
  mut generation : Int
  // Number of times a frame asks this fake host for its glyph generation.
  mut generation_asks : Int
  // Let a test model a host that advances its generation while installing a face.
  generation_on_face_add : Ref[Bool]
  // what a digit set all one width (@hostapi.style_tabular) adds to its advance, in ems (0 by default: the same either way)
  mut tabular : Double
  // whether the marks of East Asian Ambiguous width (U+2010 to U+206F) are a whole em unless set proportional
  // (@hostapi.style_proportional), as a CJK face draws them (false by default: half an em either way)
  mut cjk_marks : Bool
  // how big each glyph's picture is, in points (6 by 10 by default): what fills an atlas's plots, as large ones do
  mut glyph_box : (Double, Double)
  // what a face given by its number (face_add, a face's preview) adds to a cluster's advance in what is set in it, in
  // ems (none by default: each measures as the system's)
  faces_wider : Map[Int, Double]
  // each printable ASCII letter's advance in ems, regular and bold (weight 600 and more), as a real face measures it
  // (Tester::latin_advances; none by default: half an em each, 0.6 in the code face)
  mut latin : (FixedArray[Double], FixedArray[Double])?
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
  /// the pointer's shape as last told (desktop.mbt), how many times it was told, and how often the window was asked to be
  /// dragged
  mut cursor : Int
  mut cursors_told : Int
  mut window_drags : Int
  /// what the app asked of the window's own buttons (@hostapi.window_act: 1 minimize, 2 maximize or back, 3 close),
  /// oldest first; whether the window is maximized (Tester::set_window_zoomed); where the app last said its maximize
  /// button is (window_snap, (x, y, w, h)) and how the pointer stands on it as the host would say (Tester::set_window_snap)
  window_acts : Array[Int]
  mut zoomed : Bool
  mut snap : (Double, Double, Double, Double)
  mut snap_state : Int
  /// whether the app can open a window of its own (Tester::set_window_opens), and what it opened them for, oldest first
  /// (@hostapi.window_open); which of them have closed (Tester::close_window) and which came to the front, oldest first
  /// (@hostapi.window_front)
  mut window_opens : Bool
  windows_opened : Array[String]
  windows_closed : Array[String]
  windows_fronted : Array[String]
  /// the number on the app's icon as last told (@ui.set_badge)
  mut badge : Int
  /// what the app's own native calls say, by name, as its host would hand them on (Tester::set_app_said), and what
  /// the app told them, name and argument (Tester::app_told)
  app_said : Map[String, String]
  app_told : Array[(String, String)]
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
  /// how much lower the window's buttons go in the app's top row and over how long (@hostapi.window_buttons_down), as
  /// last told
  mut buttons_down : (Double, Double)
  /// how round the system draws the window's corners (Tester::new's `window_corner`; none filling the screen), and
  /// each of them where they differ (Tester::new's `window_corners`: top left, then round it)
  window_corner : Double
  window_corners : FixedArray[Double]?
  /// the system's size of words (font_scale: 1 as it is)
  mut font_scale : Double
  /// how far its local time is ahead of UTC, in minutes (utc_offset_min; Tester::set_utc_offset: 0 as it is)
  mut utc_offset : Int
  /// whether the system lays out the app's tabs itself (an iPhone Duo's: Tester::set_nav_able), and the bars the app
  /// handed it last (@hostapi.nav_bar's JSON; "" none yet)
  mut nav_able : Bool
  mut nav_said : String
  /// something reading the widgets out (a11y_on), the last update it was told (a11y.mbt), what it has of them as the
  /// updates left it, and how many times the app had told it as the Tester last held that to what is read out
  mut a11y : Bool
  mut a11y_said : String
  a11y_told : A11yMirror
  mut a11y_held : Int
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
  /// what the system lets the app show ("granted", "denied", "ask", "default", "unknown": Tester::set_notice_permission),
  /// what the person answers when asked (None: never), how often the app asked, and the answer due: from the frame after
  /// it
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
  /// a list's rows set on its pixels (rows_on_pixels): every platform's host does; a Tester's only where its test says
  /// so (Tester::set_rows_on_pixels), its frames' layout else as it always was
  mut rows_on_pixels : Bool
  /// it keeps groups of instances (groups_here): every platform's host does, a Tester's too unless its test says it
  /// keeps none (Tester::set_groups), as the web's host, a list drawn out flat in each frame
  mut groups : Bool
  /// the window's tree keeps where in the source each node was made (keeps_sources): a Tester's does, unless what it
  /// runs is measured as a device runs it (Tester::new's `keeps_sources`)
  keeps_sources : Bool
  /// the marks' drawings answered as the test says (Tester::marks_by_hand, Tester::marks_answer), not by the frame
  /// after each is asked
  mut marks_by_hand : Bool
  /// the pickers' answers told as the test says (Tester::picks_by_hand, Tester::pick_answer), not at each ask
  mut picks_by_hand : Bool
  /// what the app handed to the system's share sheet (@ui.share), oldest first
  shares : Array[(String, String, String, Bytes)]
  /// the device's performance record (@hostapi.perf_state: -1 none kept here, 0 off, 1 on; Tester::set_perf), and
  /// what the app said of it: each set_perf, each perf_line while it was on, oldest first (Tester::perf_said)
  mut perf : Int
  perf_sets : Array[Bool]
  perf_lines : Array[String]
  /// whether its folder can be opened (@hostapi.perf_opens; Tester::set_perf_opens), and how often it was
  /// (@hostapi.perf_open; Tester::perf_opened)
  mut perf_opens : Bool
  mut perf_opened : Int
  /// the record's files' bytes (@hostapi.perf_size; Tester::set_perf_size)
  mut perf_bytes : Double
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
  /// whether it decodes AV1 (Tester::set_av1; a run's ENV line)
  mut av1_here : Bool
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
  /// whether it takes a frame not to be shown (Tester::set_stream_hides), and what each stream says of its sound
  /// (Tester::set_stream_audio_clock: samples played, ms queued)
  mut stream_hides : Bool
  stream_audio_clock : Map[Int, (Double, Double)]
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
  /// and each one's size in pixels and what it drew, each instance as a test compares them (Tester::shot_drawn)
  shot_sizes : Array[(Int, Int)]
  shot_drawn : Array[Array[String]]
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
  f.image_ids += 1
  let id = f.image_ids
  f.wants = true
  f.images[id] = { state: if ow > 0.0 { 0 } else { -1 }, w, h, ow, oh }
  id
}

///|
fn fake_image(f : FakeHost, ow : Int, oh : Int, max_px : Int) -> Int {
  let k = if ow > oh { max_px.to_double() / ow.to_double() } else { max_px.to_double() / oh.to_double() }
  let k = if k > 1.0 { 1.0 } else { k }
  f.image_ids += 1
  let id = f.image_ids
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
  @hostapi.now()
}

///|
fn h_wall_ms() -> Double {
  @hostapi.wall_ms()
}

///|
/// The frames' clock's moment the time of day is `ms` (@hostapi.clock_at_wall).
fn h_clock_at_wall(ms : Double) -> Double {
  @hostapi.clock_at_wall(ms)
}

///|
/// How far local time is ahead of UTC at `at_ms`, in minutes.
fn h_utc_offset_min(at_ms : Double) -> Int {
  @hostapi.utc_offset_min(at_ms)
}

///|
/// How far the local time is ahead of UTC now, in minutes: what a core trace keeps of the host (envrec.mbt's
/// settings_at_frame), the time of day read here where the host provides it.
fn h_utc_offset_now() -> Int {
  h_utc_offset_min(h_wall_ms())
}

///|
/// How much later than its time the frame before this one reached the screen (@hostapi.frame_late).
fn h_frame_late() -> Double {
  let late = @hostapi.frame_late()
  // (kept on the tape, before the frame's DRAWHASH, for a Tester to draw the run again by: Tester::replay_frames)
  if late > 0.0 && taping() && late_taped.val != g().frame_no {
    late_taped.val = g().frame_no
    tape_line("LATE \{late}")
  }
  late
}

///|
/// The frame whose lateness was kept on the tape last (h_frame_late).
// kept across runs: its frames numbered on from one run to the next
let late_taped : Ref[Int] = Ref(-1)

///|
/// What the pointer's event being handled came from, as the host says (@hostapi.event_finger): 1 a finger, 0 a mouse
/// or a pen, -1 not said.
fn h_event_finger() -> Int {
  @hostapi.event_finger()
}

///|
/// When the input event being handled happened (the host's, else now).
fn h_event_time() -> Double {
  let t = @hostapi.event_time()
  if t >= 0.0 {
    t
  } else {
    @hostapi.now()
  }
}

///|
fn h_platform() -> Int {
  @hostapi.platform()
}

///|
/// The system whose keys the person types with (keys_system): the host's, but a browser's the system under it where
/// it says (@hostapi.keys_platform).
fn h_keys() -> Int {
  let k = @hostapi.keys_platform()
  if k >= 0 {
    k
  } else {
    h_platform()
  }
}

///|
/// Whose system's touches and fields this app has (`feel_as`): the host's own unless the app said another's.
fn h_feel() -> Int {
  if feel_over.val >= 0 {
    feel_over.val
  } else {
    platform()
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
// kept across runs: what the app's main said once (feel_as)
let feel_over : Ref[Int] = { val: -1 }

///|
fn h_request_frame() -> Unit {
  journal_wants()
  // (asked from outside a frame: what asked changed what the view is built from, frame_watch.mbt)
  if !in_frame.val && !frame_running.val {
    outside_counted()
  }
  @hostapi.request_frame()
}

///|
/// The host's next frame asked for what the frames' watch saw change (frame_watch.mbt): nothing come from outside.
fn h_frame_owed() -> Unit {
  journal_wants()
  @hostapi.request_frame()
}

///|
/// The host's next frame asked for what moves on by the clock (a motion going on, a cycle shown:
/// @hostapi.request_frame_on).
fn h_request_frame_on() -> Unit {
  journal_wants()
  @hostapi.request_frame_on()
}

///|
fn h_wake_after(ms : Double) -> Unit {
  @hostapi.wake_after(ms)
}

///|
fn h_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  @hostapi.font_metrics(size, weight, style, out)
  rec_metrics(size, weight, style, out)
}

///|
fn h_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  let k = @hostapi.shape(text, size, weight, style, out)
  rec_shape(text, size, weight, style, out, k)
  k
}

///|
/// The key of `text` drawn as one piece (a word of a joining script).
fn h_text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  let k = @hostapi.text_key(text, size, weight, style)
  rec_key(text, size, weight, style, k)
  k
}

///|
fn h_glyph(key : Int, out : FixedArray[Double]) -> Unit {
  @hostapi.glyph(key, out)
  rec_glyph(key, out)
}

///|
/// The picture of glyph `key`, drawn by the h_glyph asked last, put in the atlas at `x`, `y`.
fn h_glyph_put(key : Int, x : Int, y : Int) -> Unit {
  @hostapi.glyph_put(key, x, y)
}

///|
/// The picture of glyph `key`, drawn by the h_glyph asked last, given back into `out` (halo.mbt): false where the host
/// gives none.
fn h_glyph_picture(key : Int, out : FixedArray[Byte]) -> Bool {
  @hostapi.glyph_picture(key, out)
}

///|
/// Pixels made here (a halo, halo.mbt) put in the atlas at `x`, `y`: false where the host takes none.
fn h_atlas_put(x : Int, y : Int, w : Int, h : Int, px : FixedArray[Byte]) -> Bool {
  @hostapi.atlas_put(x, y, w, h, px)
}

///|
fn h_atlas_size(colour : Bool) -> Int {
  @hostapi.atlas_size(colour)
}

///|
/// The glyphs of the first `n` of `keys` for the host to draw ahead (text.mbt glyphs_ahead): a Tester's hosts, fake
/// or live, draw each as it is asked for (the default: nothing ahead).
fn h_glyphs_ahead(keys : FixedArray[Int], n : Int) -> Unit {
  @hostapi.glyphs_ahead(keys, n)
}

///|
/// A face's file given to the host (faces.mbt).
fn h_face_add(face : Int, path : String, weight : Int) -> Bool {
  @hostapi.face_add(face, path, weight)
}

///|
fn h_face_add_bytes(face : Int, data : Bytes, weight : Int) -> Bool {
  @hostapi.face_add_bytes(face, data, weight)
}

///|
fn h_face_add_family(face : Int, family : String) -> Bool {
  @hostapi.face_add_family(face, family)
}

///|
fn h_face_clear(face : Int) -> Unit {
  @hostapi.face_clear(face)
}

///|
fn h_atlas_generation() -> Int {
  @hostapi.atlas_generation()
}

///|
/// The host's glyph generation, read at the start of a frame and updated when a face changes it mid-frame.
// kept across runs: said as each frame begins, reset by Ctx::let_go
let atlas_said : Ref[Int?] = Ref(None)

///|
fn atlas_now() -> Int {
  match atlas_said.val {
    Some(g) => g
    None => h_atlas_generation()
  }
}

///|
fn h_present(buf : FixedArray[Double], count : Int) -> Unit {
  let c = g()
  let (r, gg, b) = c.clear
  // what of it differs from the frame presented before, the part a host that keeps its picture draws again
  let t0 = h_now()
  // (a frame of its looks alone with only lists moved by their headers (looks_frame): those headers compared alone)
  let moved = if looks_heads_only.val {
    presented.moved(buf, count, c.window_w, c.window_h, c.scale, r, gg, b, list_heads.map(fn(h) { h.at }), known=damage_known)
  } else {
    None
  }
  looks_heads_only.val = false
  let heads_moved = moved is Some(_)
  let parts = match moved {
    Some(parts) => parts
    None =>
      presented.next(
        buf,
        count,
        c.window_w,
        c.window_h,
        c.scale,
        r,
        gg,
        b,
        groups=!ride_spans.is_empty(),
        known=damage_known,
      )
  }
  damage_known.clear()
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
  // (what of it cannot be seen left out: drawn the same, to the byte, with less to draw; where only its lists' headers
  // moved, those alone asked again)
  let occluded = if heads_moved {
    presented.occlude_moved(buf, count, c.window_w, c.window_h, list_heads.map(fn(h) { h.at }))
  } else {
    None
  }
  let (shown, n) = match occluded {
    Some(o) => o
    None => presented.occlude(buf, count, c.window_w, c.window_h)
  }
  @hostapi.present(shown, n, r, gg, b)
  ride_groups_told()
}

///|
/// What of the frame being painted is known drawn anew, x0 y0 x1 y1 in points: where what scrolled shows (view_paint),
/// every instance there moved. Told to what works out what a host draws again (h_present), as its parts from the start.
// kept across runs: emptied as each frame is presented
let damage_known : Array[(Double, Double, Double, Double)] = []

///|
/// The old views' lists (their nodes' ids) that scrolled this frame: each, painted, told as known drawn anew where it
/// shows (Ctx::paint_held, damage_known).
// kept across runs: emptied as each frame begins
let lists_scrolled : Array[Int] = []

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
  @hostapi.reduce_transparency() || h_env("MBUI_GLASS") == "solid"
}

///|
fn h_gpu_ms() -> Double {
  @hostapi.gpu_ms()
}

///|
/// The memory the process holds, MB, as the system counts it (-1: not said).
fn h_mem_mb() -> Double {
  let b = @hostapi.mem_bytes()
  if b < 0.0 {
    -1.0
  } else {
    b / 1048576.0
  }
}

///|
/// The process's CPU time, ms (-1: not said).
fn h_cpu_ms() -> Double {
  @hostapi.cpu_ms()
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
  let z = window_zoom_drawn.val
  let (x, y, w, h) = (x * z, y * z, w * z, h * z)
  @hostapi.set_ime(active, x, y, w, h, text, a, b)
}

///|
fn h_text_menu(shown : Bool, x : Double, y : Double, w : Double, h : Double, can : Int) -> Unit {
  let z = window_zoom_drawn.val
  let (x, y, w, h) = (x * z, y * z, w * z, h * z)
  @hostapi.text_menu(shown, x, y, w, h, can)
}

///|
fn h_edit_can(can : Int) -> Unit {
  @hostapi.edit_can(can)
}

///|
fn h_text_menu_own(words : String) -> Unit {
  @hostapi.text_menu_own(words)
}

///|
fn h_clipboard_set(s : String) -> Unit {
  @hostapi.clipboard_set(s)
}

///|
/// The window made to fill the screen or back (@hostapi.set_full_screen).
fn h_set_full_screen(on : Bool) -> Unit {
  @hostapi.set_full_screen(on)
}

///|
/// A picture on the clipboard (@hostapi.clipboard_set_image).
fn h_clipboard_image(data : Bytes) -> Unit {
  @hostapi.clipboard_set_image(data)
}

///|
/// A secret on the clipboard (@hostapi.clipboard_set_secret).
fn h_clipboard_secret(s : String, clear_ms : Double) -> Unit {
  @hostapi.clipboard_set_secret(s, clear_ms~)
}

///|
/// How many secrets were copied (Ctx::copy_secret): one's taking off is for it alone, not a later one's.
let secret_copies : Ref[Int] = Ref(0)

///|
/// The last secret copied taken off unless something else was copied since (@hostapi.clipboard_secret_off).
fn h_clipboard_secret_off() -> Unit {
  @hostapi.clipboard_secret_off()
}

///|
/// The word of `text` around `off` as the host's word boundaries have it, (-1, -1) where it has none.
fn h_word_at(text : String, off : Int) -> (Int, Int) {
  let (s, e) = @hostapi.word_at(text, off)
  if text_recording() {
    let head : Json = [Json::string(text), Json::number(off.to_double())]
    let line : Json = { "wa": head, "r": [Json::number(s.to_double()), Json::number(e.to_double())] }
    text_say("wa|" + head.stringify(), line)
  }
  (s, e)
}

///|
/// A URL handed to the system (its browser, or the app it belongs to).
fn h_open_url(url : String) -> Bool {
  @hostapi.open_url(url)
}

///|
/// A page in a browser's tab over the app (@hostapi.open_tab).
fn h_open_tab(url : String) -> Bool {
  @hostapi.open_tab(url)
}

///|
fn h_a11y_on() -> Bool {
  @hostapi.a11y_on()
}

///|
fn h_a11y_tree(tree : String) -> Unit {
  @hostapi.a11y_tree(tree)
}

///|
fn h_back_enabled(on : Bool) -> Unit {
  @hostapi.back_enabled(on)
}

///|
fn h_wheel_kept(kept : Bool) -> Unit {
  @hostapi.wheel_kept(kept)
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
// as the app takes the answer (MarkedImage::made, NativeView::grabbed): both are when the host's work for it is over.
// A pick's and a native call's answers are taken as their event comes (outside_take: Pick::take, NativeCall::take),
// into a signal what waits on them reads; a host answering them by the frame, as each frame begins.

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
/// The host wrote to the performance record (@hostapi.perf_state, perf_size): told as what it has written is on the
/// disk (iOS's, its writes gathered: one told for all written since the last it told), the app reading how much it
/// holds then (perf_size, a signal: what shows it follows it), nothing else of the frame built again for it.
let outside_perf = 14

///|
/// A run of the password manager's `op` ended (@hostapi.OpRun's id: passwords.mbt), told as it does (macOS, Windows):
/// what it said taken then into what reads it (OpRun::done).
let outside_op = 15

///|
/// The system's autofill gave the login the person picked (id 1: @hostapi's autofill.mbt), told as it does (Android):
/// taken then into what reads it (autofill_take).
let outside_autofill = 16

///|
/// Every kind above, by its name: each its own number (outside_kinds_wbtest.mbt), the hosts' named the same
/// (Native.java's OUTSIDE_*, apple.h's, win.h's and android_host.c's MB_OUTSIDE_*, web/host.js's OUTSIDE_*), every
/// `outside_*` here in it: scripts/chk outside-kinds, host_contract.sh HOST kinds
#warnings("-unused_value")
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
    ("perf", outside_perf),
    ("op", outside_op),
    ("autofill", outside_autofill),
  ]
}

///|
let outside_tickets : Map[Int64, Int] = Map([])

///|
let outside_told : Ref[Bool] = { val: false }

///|
fn outside_key(kind : Int, id : Int) -> Int64 {
  (kind.to_int64() << 32) | id.to_int64()
}

///|
fn outside_start(kind : Int, id : Int, what : String) -> Unit {
  if id > 0 && (outside_told.val || @hostapi.answers_by_frame(kind)) {
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
let answers_waiting : Map[Int64, Bool] = Map([])

///|
/// An answer of `kind` came (the host's event; under a Tester, a frame: its fake host's answers come by the frame).
fn answer_told(kind : Int) -> Unit {
  let s = answers_told[kind]
  s.set(s.untracked() + 1)
}

///|
/// Whether the host's answer of `kind` for `id` may be taken now, read as a signal (what reads it follows the
/// answers as they come): once the host's event told of it, not asked of the host before; a host's that answers it
/// by the frame (@hostapi.answers_by_frame) or tells no events, whenever it is read.
fn answer_here(kind : Int, id : Int) -> Bool {
  answers_told[kind].get() |> ignore
  @hostapi.answers_by_frame(kind) || !outside_told.val || answers_waiting.contains(outside_key(kind, id))
}

///|
/// The host's answer of `kind` for `id` taken.
fn answer_taken(kind : Int, id : Int) -> Unit {
  answers_waiting.remove(outside_key(kind, id))
}

///|
/// A frame begins: the answers waited on of the kinds the host answers by the frame (@hostapi.answers_by_frame) may
/// have come with it, told as a host's event tells them.
fn answers_by_the_frame() -> Unit {
  if outside_tickets.is_empty() {
    return
  }
  let kinds : Map[Int, Bool] = Map([])
  for k, _ in outside_tickets {
    kinds[(k >> 32).to_int()] = true
  }
  for kind, _ in kinds {
    if kind < answers_told.length() &&
      kind != outside_update &&
      @hostapi.answers_by_frame(kind) {
      answer_told(kind)
    }
  }
}

///|
/// Who takes the host's answer of a kind that is taken as it comes (outside_pick, outside_native, outside_op,
/// outside_autofill), by its key
/// (outside_key): told by the host's event, it takes the answer from the host into what reads it, and says whether it
/// was there to take.
// kept across runs: emptied by each Tester (reset_globals)
let outside_takers : Map[Int64, () -> Bool] = Map([])

///|
/// `take` takes the host's answer of `kind` for `id` as its event comes (outside_take); now, where the event came
/// before it was asked to (a host's that answered at once).
fn outside_takes(kind : Int, id : Int, take : () -> Bool) -> Unit {
  let k = outside_key(kind, id)
  if answers_waiting.contains(k) {
    answers_waiting.remove(k)
    if take() {
      return
    }
  }
  outside_takers[k] = take
}

///|
/// What waited on the host's answer of `kind` for `id` let go of (an op's run ended by the app, an autofill's ask let
/// go): nothing takes it any more, a word that comes for it after is nothing.
fn outside_let_go(kind : Int, id : Int) -> Unit {
  let k = outside_key(kind, id)
  outside_takers.remove(k)
  answers_waiting.remove(k)
}

///|
/// What @hostapi waits on (its op's runs, its autofill's ask) waited on here: taken as the host's word comes.
fn init {
  @hostapi.outside_waits.val = fn(kind, id, take) { outside_takes(kind, id, take) }
  @hostapi.outside_lets_go.val = fn(kind, id) { outside_let_go(kind, id) }
}

///|
/// The host's event: its answer of `kind` for `id` came, taken now by who waits on it (outside_takes), into what reads
/// it; kept till one does where none does yet.
fn outside_take(kind : Int, id : Int) -> Unit {
  let k = outside_key(kind, id)
  match outside_takers.get(k) {
    Some(take) => if take() { outside_takers.remove(k) }
    None => answers_waiting[k] = true
  }
}

///|
/// A frame begins: the answers of a kind taken as it comes that a host answering it by the frame
/// (@hostapi.answers_by_frame: a Tester's, what it answers by itself) or telling no events has by now, taken as its
/// event would have them. Nothing reads them for it: what reads one is told as it is taken, and only then.
fn takers_by_the_frame() -> Unit {
  if outside_takers.is_empty() {
    return
  }
  let ks = []
  for k, _ in outside_takers {
    ks.push(k)
  }
  for k in ks {
    let kind = (k >> 32).to_int()
    if @hostapi.answers_by_frame(kind) || !outside_told.val {
      match outside_takers.get(k) {
        Some(take) => if take() { outside_takers.remove(k) }
        None => ()
      }
    }
  }
}

///|
/// The native views the host said were ready (or failed): their work is the host's no more, whatever is asked after.
let views_told : Map[Int, Bool] = Map([])

///|
/// How many times views_told changed: read by what asks whether a view's host is done (NativeView::host_done), so a
/// binding of the window's tree that asks it is done again as the host says so (a host says it at a moment of its own,
/// not always with how the view stands: outside_stood).
// kept across runs: only counts
let views_told_rev : @signals.Signal[Int] = @signals.signal(0)

///|
/// views_told changed: what read it told.
fn views_told_changed() -> Unit {
  views_told_rev.set(@signals.untracked(fn() { views_told_rev.get() }) + 1)
}

///|
/// The host's event: what it did for the app is done (`state`: 1 done, -1 failed), or (a view, 0) it waits on the
/// app now: the bytes a player reads, a site's answer. Until the app answers, the host does nothing for it.
fn on_outside(kind : Int, id : Int, state : Int) -> Unit {
  // (one event, at its own moment: view_host.mbt)
  view_event(fn() { on_outside_now(kind, id, state) }, what=if kind == outside_posted { "messages" } else { "host" })
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
    view_stood(id, state)
    return
  }
  // (the performance record written: what shows how much it holds follows it, perf.mbt's perf_size; a frame only
  // where something read it)
  if kind == outside_perf {
    perf_told()
    return
  }
  // (what was picked, a native call's answer: taken now into what reads it, Pick::files and NativeCall::got, each a
  // signal; nothing else of the frame built again for it, no frame asked but where something reads it)
  if kind == outside_pick || kind == outside_native || kind == outside_op || kind == outside_autofill {
    outside_take(kind, id)
    return
  }
  // (a ready view's player asking more of the app: nothing waited on ends, nothing built again for it)
  if kind == outside_view && state == 0 && views_told.contains(id) {
    view_asks(id)
    return
  }
  // (a picture decoded, or not to be: ready at this word's moment, what reads how big that picture is following it,
  // image.mbt's image_decoded)
  // what reads that picture told alone, by what is said of it: nothing else of the frame is built again for it (no
  // event from outside of the frame's whole)
  if kind == outside_image {
    if state != 0 {
      let at = view_moment()
      image_decoded(id, if at >= 0.0 { at } else { g().clock })
    }
    // (its sizes recorded now (hostrec.mbt), drawn or not: one never drawn is still asked of a Tester)
    if state == 1 && text_recording() {
      let out = FixedArray::make(4, 0.0)
      if @hostapi.image_info(id, out) == 1 {
        rec_image_ready(id, out)
      }
    }
    outside_end(kind, id)
    return
  }
  outside_came()
  if kind == outside_update {
    // (how it goes changed: what it says now set, followed by what reads it; held while the host works at it)
    update_told.set(@hostapi.update_state())
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
  if kind == outside_view && state != 0 && !views_told.contains(id) {
    views_told[id] = true
    views_told_changed()
  }
  outside_end(kind, id)
  if kind == outside_view && state == 0 {
    view_asks(id)
  }
  // an answer brought (what was picked, read, drawn, grabbed: told, followed by what waits on it; a view the host is
  // done opening): read as the next frame builds
  let answer = kind == outside_gallery || kind == outside_marks || kind == outside_grab || kind == outside_clip
  if answer {
    answers_waiting[outside_key(kind, id)] = true
    answer_told(kind)
    // (the clipboard's words for a field of the tree's: taken at the answer's moment, tree_field.mbt)
    if kind == outside_clip {
      tree_fields_pasting(view_moment())
    }
  }
  if answer || (kind == outside_view && state != 0) {
    h_request_frame()
  }
}

///|
/// View `id` waits on the app for its player's bytes: its reads taken now, not at a frame (none comes while the app's
/// window is off the screen, and a read left untaken there failed the player: native.mbt's take_reads).
fn view_asks(id : Int) -> Unit {
  for v in open_views.copy() {
    if v.id == id {
      v.take_reads()
    }
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
  @hostapi.log(s)
}

///|
fn h_image_load(src : String, max_px : Int) -> Int {
  let id = @hostapi.image_load(src, max_px)
  if text_recording() {
    rec_image_asked(id, { "is": [Json::string(src), Json::number(max_px.to_double())] })
  }
  outside_waits_image(id, "image \{id} \{src}")
  id
}

///|
/// A decode asked for waited on (outside_image) unless it failed at once (one the host does not know): nothing of it
/// is left to wait for.
fn outside_waits_image(id : Int, what : String) -> Unit {
  if @hostapi.image_info(id, FixedArray::make(4, 0.0)) >= 0 {
    outside_start(outside_image, id, what)
  }
}

///|
/// Bytes handed over for `src` (Ctx::image_bytes, add_image) decoded: its wait on outside named by `src` too, as a
/// picture loaded by its source is ("image N (B bytes) SRC": a scripted run's `decoded SRC`).
fn h_image_load_bytes(data : Bytes, max_px : Int, src : String) -> Int {
  let id = @hostapi.image_load_bytes(data, max_px)
  if text_recording() {
    rec_image_asked(id, { "ib": image_bytes_head(data, max_px) })
  }
  outside_start(outside_image, id, "image \{id} (\{data.length()} bytes) \{src}")
  id
}

///|
/// What a decode of bytes is kept by (hostrec.mbt): the bytes' name, their length, the size asked for.
fn image_bytes_head(data : Bytes, max_px : Int) -> Json {
  [
    Json::string(bytes_name(data)),
    Json::number(data.length().to_double()),
    Json::number(max_px.to_double()),
  ]
}

///|
fn h_image_info(id : Int, out : FixedArray[Double]) -> Int {
  let st = @hostapi.image_info(id, out)
  if st == 1 {
    rec_image_ready(id, out)
  }
  st
}

///|
/// A ready image's pixels read back (premultiplied RGBA, rows from the top) into `out`.
fn h_image_pixels(id : Int, out : FixedArray[Byte]) -> Bool {
  @hostapi.image_pixels(id, out)
}

///|
/// Instances never presented (a shot's: shot.mbt) drawn as a frame is on the frame's ground, `scale` pixels a point into
/// a picture `w` by `h` of their own, and its pixels (as h_drawn_pixels) into `out`.
fn h_drawn_pixels_of(
  inst : FixedArray[Double],
  count : Int,
  scale : Double,
  w : Int,
  h : Int,
  out : FixedArray[Byte],
) -> Bool {
  let (r, gg, b) = g().clear
  @hostapi.drawn_pixels_of(inst, count, r, gg, b, scale, w, h, out)
}

///|
/// The last frame's pixels in a rectangle of it (device pixels; premultiplied RGBA, rows from the top) into `out`.
fn h_drawn_pixels(x : Int, y : Int, w : Int, h : Int, out : FixedArray[Byte]) -> Bool {
  @hostapi.drawn_pixels(x, y, w, h, out)
}

///|
fn h_image_free(id : Int) -> Unit {
  outside_end(outside_image, id)
  @hostapi.image_free(id)
}

// Native views (native.mbt).

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
  let id = @hostapi.view_open(kind, arg)
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
  let z = window_zoom_drawn.val
  let (px, py, pw, ph) = (x * z, y * z, w * z, h * z)
  let (pcx0, pcy0, pcx1, pcy1) = (cx0 * z, cy0 * z, cx1 * z, cy1 * z)
  let (pr0, pr1, pr2, pr3) = (r0 * z, r1 * z, r2 * z, r3 * z)
  @hostapi.view_place(id, px, py, pw, ph, pcx0, pcy0, pcx1, pcy1, pr0, pr1, pr2, pr3, shown)
}

///|
fn h_view_close(id : Int) -> Unit {
  outside_end(outside_view, id)
  if views_told.contains(id) {
    views_told.remove(id)
    views_told_changed()
  }
  @hostapi.view_close(id)
}

///|
fn h_view_control(id : Int, op : Int, value : Double) -> Unit {
  @hostapi.view_control(id, op, value)
}

///|
fn h_view_info(id : Int, out : FixedArray[Double]) -> Int {
  let state = @hostapi.view_info(id, out)
  view_info_told(id, state, out)
  state
}

///|
fn h_view_site_next(id : Int) -> String {
  let e = @hostapi.view_site_next(id)
  // (what the page asked of its host, on a run's record: Tester::view_said gives it again)
  if e != "" {
    site_told(id, e)
  }
  e
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
    Bytes::makei(t.length(), fn(i) { t.unsafe_get(i).to_int().to_byte() })
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
      let out : Map[String, Json] = Map([])
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
        let f = f.to_owned()
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
let sites_told_state : Map[Int, String] = Map([])

///|
/// What the app tells a view's host beyond its controls (native.mbt): `what` 1 a script to run in its page
/// (NativeView::script), 2 who takes a finger on it (NativeView::touch: "all|through|pinch|vertical SLOP"), 3 a site's
/// settings (`{"head_wait_ms":…,"backlog":…}`), 4 where what takes a press is drawn over it ("x0 y0 x1 y1 …": a
/// finger there is the canvas's), 5 raised over the others.
fn h_view_tell(id : Int, what : Int, text : String) -> Unit {
  @hostapi.view_tell(id, what, text)
}

///|
fn h_view_site_body(id : Int, req : Int) -> Bytes {
  let b = @hostapi.view_site_body(id, req)
  if views_tracer.val is Some(_) || taping() {
    view_say({
      "sitebody": Json::object({ "view": Json::number(id.to_double()), "req": Json::number(req.to_double()) }),
      "b": Json::string(@codec.hex(site_body_kept(b))),
    })
  }
  b
}

///|
fn h_view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  @hostapi.view_site_head(id, req, status, headers)
}

///|
fn h_view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  @hostapi.view_site_chunk(id, req, data)
}

///|
fn h_view_site_end(id : Int, req : Int, error : String) -> Unit {
  outside_answered(id)
  @hostapi.view_site_end(id, req, error)
}

///|
fn h_view_site_state(id : Int) -> String {
  let st = @hostapi.view_site_state(id)
  if st != "" && (views_tracer.val is Some(_) || taping()) && sites_told_state.get(id) != Some(st) {
    sites_told_state[id] = st
    let j : Json = @json.parse(st) catch { _ => Json::string(st) }
    view_say({ "sitestate": Json::object({ "view": Json::number(id.to_double()), "state": j }) })
  }
  st
}

///|
fn h_view_text(id : Int, what : Int) -> String? {
  let t = @hostapi.view_text(id, what)
  match t {
    Some(text) => view_told(id, what, text)
    None => ()
  }
  t
}

///|
fn h_view_still(id : Int) -> Bytes {
  let b = @hostapi.view_still(id)
  if views_tracer.val is Some(_) || taping() {
    view_say({ "still": Json::object({ "view": Json::number(id.to_double()) }), "b": Json::string(@codec.hex(b)) })
  }
  b
}

///|
/// Who is told what the host says of its views (@ui.trace_views): a run's record of it.
// kept across runs: the app's own, set once as it starts (a Tester's host says nothing to it)
let views_tracer : Ref[((Map[String, Json]) -> Unit)?] = Ref(None)

///|
/// What was last told of each view's answers (view, what), so that each is told once as it changes.
let views_told_text : Map[(Int, Int), String] = Map([])

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
let views_told_info : Map[Int, String] = Map([])

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
  @hostapi.view_site_load(id, path)
}

///|
fn h_view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  let req = @hostapi.view_read_next(id, out)
  if req != 0 {
    view_read_told(id, req, out)
  }
  req
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
  @hostapi.view_read_answer(id, req, data, total, more)
}

// PDFs (native.mbt Pdf).

///|
fn h_pdf_open(data : Bytes) -> Int {
  let doc = @hostapi.pdf_open(data)
  if text_recording() {
    g().host_rec.pdfs[doc] = (bytes_name(data), data.length())
  }
  doc
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

///|
fn h_pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  @hostapi.pdf_page_size(doc, page, out)
  match g().host_rec.pdfs.get(doc) {
    Some(named) if text_recording() => {
      let line : Json = { "ps": pdf_head(named, [page]), "r": nums(out, 2) }
      text_say(line.stringify(), line)
    }
    _ => ()
  }
}

///|
fn h_pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  let id = @hostapi.pdf_page_load(doc, page, max_px)
  match g().host_rec.pdfs.get(doc) {
    Some(named) if text_recording() => rec_image_asked(id, { "pi": pdf_head(named, [page, max_px]) })
    _ => ()
  }
  outside_start(outside_image, id, "image \{id} (PDF \{doc}, page \{page})")
  id
}

///|
fn h_pdf_close(doc : Int) -> Unit {
  @hostapi.pdf_close(doc)
}

///|
/// The pointer's shape (desktop.mbt Cursor's code).
fn h_set_cursor(kind : Int) -> Unit {
  @hostapi.set_cursor(kind)
}

///|
/// The press under way drags the window (the app's own title row).
fn h_window_drag() -> Unit {
  @hostapi.window_drag()
}

///|
fn h_window_act(what : Int) -> Unit {
  @hostapi.window_act(what)
}

///|
fn h_window_open(what : String) -> Bool {
  @hostapi.window_open(what)
}

///|
fn h_window_front(what : String) -> Bool {
  @hostapi.window_front(what)
}

///|
fn h_window_snap(x : Double, y : Double, w : Double, h : Double) -> Unit {
  let z = window_zoom_drawn.val
  @hostapi.window_snap(x * z, y * z, w * z, h * z)
}
