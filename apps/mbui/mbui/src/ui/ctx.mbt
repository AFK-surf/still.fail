// The per-window context: views build a fresh tree into it every frame,
// widget state persists in maps keyed by widget id, and input arrives from
// the host between frames.

///|
struct ListState {
  mut anchor : Int
  mut anchor_off : Double
  heights : Array[Double]
  // the rows' heights (est for those not measured) summed as a Fenwick
  // tree (1-based: sums[i] holds rows i - lowbit(i) until i): what is
  // above a row and the whole, without adding every row up (list.mbt)
  sums : Array[Double]
  est : Double
  mut count : Int
  mut vp_h : Double
  mut vel : Double
  mut at_end : Bool
  stick_end : Bool
  mut last_scroll : Double
  mut pending : Double
  // how to build a row, and the id scope it is built in
  mut row : (Int) -> Unit
  mut seed : Int
  // rows in view after the last layout, first to last (-1 when none)
  mut vis_first : Int
  mut vis_last : Int
  // the page its state belongs to (Ctx::own), which its rows' states do too
  mut owner : Int
  // how far the last row's bottom was below the view's after the last
  // layout (1e9 when it was not laid out)
  mut below : Double
  // gliding to its end (Ctx::list_to_end), until there or scrolled: set out at `glide_t0` (+inf: at its next layout)
  // from `glide_l0` px above its end, what is left of it e^(-t/list_glide_ms) of that, at its end at `glide_rest`;
  // how far it was above its end at the last layout
  mut glide : Bool
  mut glide_t0 : Double
  mut glide_l0 : Double
  mut glide_rest : Double
  mut glide_left : Double
  // a row followed from its top (Ctx::list_follow_from: still.fail's newest message, kept in view from its top as
  // Follow.kt's anchor), `follow_margin` under the view's top; -1 none. The reader's scroll lets it go
  mut follow_item : Int
  mut follow_margin : Double
  // the frame it was last built in (one not built is shown by nothing: at rest)
  mut built : Int
  // the frame it was last laid out in; where it stood as that frame's first layout of it began and where that frame's
  // last left it (the row it is anchored to, how far into it, what was scrolled not laid yet, whether at its end): laid
  // out again in that frame, it is laid from where it began, unless something moved it since (Ctx::place_list)
  mut laid : Int
  mut began : (Int, Double, Double, Bool)
  mut left : (Int, Double, Double, Bool)
  // the last scroll to a row asked of it (Ctx::list_scroll_to): the frame, the row and the offset (asked again as the
  // frame is built again, the same: done already)
  mut scroll_asked : (Int, Int, Double)
  // a fling (scroll.mbt): its kind (0 the desktop's, coasting on `vel`; 1
  // Android's spline; 2 iOS's deceleration), its velocity at the start (px
  // per ms, positive down the list), when it started (-1: at the next
  // frame), the spline's distance and duration, how far it has gone
  mut fling : Int
  mut fling_v : Double
  mut fling_t0 : Double
  mut fling_dist : Double
  mut fling_dur : Double
  mut fling_done : Double
  // what a finger scrolled since the last layout, and whether one drags it
  mut drag_pending : Double
  mut held : Bool
  // past an end: how far (Android: in the view's heights; iOS: points,
  // pulled while held, shown while springing back), at which end (1 the
  // top, -1 the bottom, 0 none), held (1) or springing back (2), its
  // velocity outward (Android: pixels per second; iOS: points per ms); going
  // back, its path (scroll_path.mbt)
  mut over : Double
  mut over_edge : Int
  mut over_state : Int
  mut over_v : Double
  mut back : BackPath
  // a wheel's notches eased in (Ctx::ease_list): what they come to all told (0 none), from when, how much of it has
  // come by the last frame, and what it is said to move by (Ctx::moving)
  mut ease : Double
  mut ease_t0 : Double
  mut ease_done : Double
  ease_mover : Mover
  // the size its rows are built for: the Ctx's as the list was (Ctx::sized), its rows built later, as it is laid out
  mut vw : Double
  mut vh : Double
  // whether its rows' words are picked with the pointer (Ctx::selectable), as where the list was
  mut sel : Bool
  // the theme and the direction in force where the list was (Ctx::with_theme, with_direction): its rows, built later,
  // as it is laid out, are built in them, as what is built beside the list is
  mut theme : Theme
  mut direction : Direction
  // the layer it was built in (Ctx::overlay, 0 the page): its rows, built as it is laid out, are of it as what is built
  // beside the list is (the keys they read, the focus they take)
  mut layer : Int
}

///|
struct EditorState {
  mut text : String
  mut caret : Int
  mut anchor : Int
  mut marked : String
  mut msel_a : Int
  mut msel_b : Int
  /// Android's: the handle under the caret is shown (a tap put the caret there, nothing typed since), and where its
  /// tip was drawn last (in the window; `handle_on` false: not drawn)
  mut handle : Bool
  mut handle_on : Bool
  mut handle_x : Double
  mut handle_y : Double
  /// Android's: words picked by a finger (a long press, a double tap, all selected from the menu): the selection's two
  /// handles shown, and where their tips were drawn last (`sel_on` false: not drawn); the word a long press picked
  /// first, which sliding on widens from
  mut sel_handles : Bool
  mut sel_on : Bool
  mut sel_ax : Double
  mut sel_ay : Double
  mut sel_bx : Double
  mut sel_by : Double
  mut word_a : Int
  mut word_b : Int
  /// Android's: the system's floating text menu asked for over its selection (or its caret)
  mut menu : Bool
  /// the composing region the input method said with the field's state it sends next (on_text kinds 6 and 5,
  /// Android's): -1 none
  mut comp_a : Int
  mut comp_b : Int
  mut blink0 : Double
  mut tl : TextLayout?
  mut ox : Double
  mut oy : Double
  mut submitted : String?
  mut pref_x : Double
  /// how far its words are scrolled up (taller than the field: the caret's line kept in view)
  mut scroll : Double
  /// what was put in at once that was `limit` characters or more, not put in (a long paste the app takes instead)
  mut pasted : String?
  mut limit : Int
  /// Enter sends (the words go to `submitted`); else it is a new line
  mut enter_sends : Bool
  /// the keys it leaves to the app, pressed with nothing held (a menu the field offers, chosen in by ↑ / ↓, picked
  /// from by Enter: the web's preventDefault on them)
  mut leaves : Array[Int]
  /// the input method's action key for it (@hostapi.ime_action_*: a search field's)
  mut ime_action : Int
  /// its look, as the last frame said it: the line's height (0: the font's), the words', the placeholder's, the
  /// caret's and the selection's colours
  mut line : Double
  mut color : Int64
  mut ph_color : Int64
  mut caret_color : Int64
  mut sel_color : Int64
  /// what it holds is a secret (a key, a token, a password): drawn as dots, never copied or cut out of it
  mut secret : Bool
  /// what people wrote (a message being written): set in the face given for it (faces.mbt, @hostapi.face_text)
  mut words : Bool
  /// how its words are drawn, as the app says (Ctx::editor's `look`): the same number of letters in the same places,
  /// and ranges of them in colours of their own
  mut look : ((String) -> (String, Array[(Int, Int, Int64)]))?
  /// what `look` made of the words it was last given, worked out once a build (the words, what shows, the colours)
  mut looked : (String, String, Array[(Int, Int, Int64)])?
  /// the caret's blinking starts again (shown at once) the next time the editor is built: the app wrote what it holds
  /// (Field::new, set, take)
  mut blink_again : Bool
  /// the frame it was last built in and the editor's key and id then: a Field given to a second editor (another id) in
  /// one frame is told
  mut built_frame : Int
  mut built_key : String
  mut built_id : Int
}

///|
pub struct Ctx {
  nodes : Array[Node]
  mut count : Int
  mut cur : Int
  mut id_seed : Int
  id_stack : Array[Int]
  mut width : Double
  mut height : Double
  mut scale : Double
  /// whether the host sets things on whole device pixels (whole_px_layout), as the frame began
  mut whole_px : Bool
  mut now : Double
  mut dt : Double
  mut last_now : Double
  mut frame_no : Int
  /// the system's size of words this frame (font_scale): every word's size and line times it, as Compose's sp
  mut font_scale : Double
  /// the build's number (frame_body's passes, over every frame, counted over the program: app.mbt builds_made): what is
  /// said of a build, said again by the next (motion's keyed nodes, by node: another pass's nodes are other nodes)
  mut build_no : Int
  /// how many sideways boxes' content is being built now (Ctx::sideways): what is made in it is marked in_sideways
  mut sideways_depth : Int
  // the layout epoch: when it moves on, nothing laid out before is reused
  // (Ctx::flex_tree)
  mut epoch : Int
  mut wants_frame : Bool
  mut wake_at : Double
  /// the earliest wake asked for this frame that what is shown waits for (not `later`): -1 none
  mut wake_waited : Double
  // the last frame left nothing that ends to come (Ctx::at_rest, as it ended)
  mut frame_rest : Bool
  /// who asked for the next frame first this frame (Ctx::request_frame's caller), and for the wake it waits for
  /// (Ctx::wake_in's): what Tester::assert_idle says of what is left
  mut frame_by : SourceLoc?
  mut wake_by : SourceLoc?
  /// what is held near the top of a list as its row scrolls past (Ctx::stick), in the order built this frame
  stuck : Array[Int]
  // hit targets of the last frame, in paint order, and those being collected
  mut hit_ids : Array[Int]
  mut hit_rects : Array[Double]
  mut next_hit_ids : Array[Int]
  mut next_hit_rects : Array[Double]
  // what cut each hit target where it was drawn, 12 numbers each (scene.mbt clip_stack): a press in a corner its
  // rounded clip cut away misses it
  mut hit_clips : Array[Double]
  mut next_hit_clips : Array[Double]
  mut scroll_ids : Array[Int]
  mut scroll_rects : Array[Double]
  mut next_scroll_ids : Array[Int]
  mut next_scroll_rects : Array[Double]
  // pointer
  mut px : Double
  mut py : Double
  mut down : Bool
  mut hover : Int
  mut active : Int
  mut focus : Int
  clicked : Array[Int]
  /// what was clicked twice since the last frame, the second within double_click_ms of the first and where it was
  /// (Ctx::double_clicked); the last click (its id, when, where), for the next to be the second of two
  double_clicked : Array[Int]
  mut last_click : (Int, Double, Double, Double)
  mut drag_scroll : Int
  /// what scrolls or is dragged under the press, innermost first (claim.mbt): until one claims it (`claimed`), the
  /// press is none of theirs; `drag_scroll` is the innermost meanwhile
  mut press_chain : Array[Int]
  mut claimed : Bool
  mut dragging : Bool
  mut press_x : Double
  /// when the press under way went down (ms), and the press a link's hold was last told of
  mut press_at : Double
  /// Android's: the press went down in what scrolls, so it shows as pressed only once it has stayed tap_indication_ms
  /// (Compose's clickable in a scrollable container: a finger that goes on to scroll presses nothing on the way)
  mut press_late : Bool
  /// when the pointer's latest event (down, moved, up) came, its own time (Ctx::pointer_at)
  mut pointer_t : Double
  mut held_told : Double
  /// what a press told held long (Ctx::long_press) was on, and in which frame
  mut held_on : Int
  mut held_frame : Int
  /// the press as frames see it (Ctx::press, press.mbt): as the frame it was last worked out in saw it, whether a
  /// frame saw it down, when one first did
  mut press_seen : Press
  mut press_seen_frame : Int
  mut press_was_down : Bool
  mut press_seen_at : Double
  /// the keys held as the pointer last went down (Press::mods)
  mut press_mods : Int
  /// a tap this frame (a press let go without dragging, not taken by the app: Ctx::tapped_anywhere), and the press
  /// the app took (Ctx::take_press)
  mut tapped : (Double, Double)?
  mut taken_at : Double
  mut press_y : Double
  mut last_y : Double
  mut last_x : Double
  mut vel_x : Double
  mut last_t : Double
  mut vel : Double
  mut editor_drag : Bool
  /// the field whose caret handle a finger drags (0 none), and how far under the handle's tip the finger came down
  mut handle_drag : Int
  /// Android's: the field a finger came down on, which a tap gives the focus as it lifts (0 none)
  mut editor_tap : Int
  /// which handle `handle_drag` is: 1 the caret's, 2 the selection's start, 3 its end
  mut handle_which : Int
  /// Android's: the field whose words a long press picked, while that finger is still down (sliding widens them)
  mut word_drag : Int
  /// the last tap on a field as it lifted (its id, when, where): a second soon after picks the word there
  mut last_tap : (Int, Double, Double, Double)
  /// what the host was last told of the floating text menu (text_menu)
  mut menu_sig : String
  mut handle_dy : Double
  // persistent widget state
  lists : Map[Int, ListState]
  editors : Map[Int, EditorState]
  /// key catchers and the soft keyboard's height (device.mbt)
  dev : DeviceState
  springs : Map[Int, SpringPath]
  /// what is said to move (motion_data.mbt), the last id given to one, and whether a cycle was read this frame
  movers : Array[MoverEntry]
  mut cycling : Bool
  /// the cycles read this frame (their periods, who reads them), whether a motion said was not at rest at its end, and
  /// the latest rest of the stacks (Ctx::nav) built this frame: what a test asks (Tester::assert_idle, nav_rest)
  cycles : Array[(Double, SourceLoc)]
  /// what comes again every so often while shown this frame (Ctx::every): its period, who reads it
  periodic : Array[(Double, SourceLoc)]
  mut motion_left : Bool
  /// a fiber of the window's runtime waits for the next frame (@effect.next_frame): it comes as the clock goes, not at
  /// this moment, as a motion going on
  mut fiber_frame : Bool
  /// a motion said that has not started yet (its rest +inf: it starts at its first step, a frame to come)
  mut motion_unstarted : Bool
  /// inputs came before this frame (a frame more, for what they changed late in it)
  mut took_input : Bool
  /// what the view read changed as the frame was built or laid out (Ctx::read_changed: words laid out elsewhere, the
  /// focus given, a list scrolled): built again in this frame (frame_body); the last that changed (what it is)
  mut read_back_moved : Bool
  mut read_back_key : String
  /// what the view read of the layout as it built (readback.mbt), as read (and where, a laid rect): boxes' laid rects,
  /// lists' places, rows' heights, whether words are laid out; the boxes whose laid rect is read, and when last, with
  /// their rects as last laid out
  laid_reads : Map[Int, ((Double, Double, Double, Double)?, SourceLoc)]
  size_reads : Map[Int, ((Double, Double)?, SourceLoc)]
  place_reads : Map[Int, (String, (Int, Double, Double)?)]
  /// lists' places read as the view built (Ctx::list_info, list_info_as): each list's key, and whether what was made
  /// of its place is not what it makes of it now
  info_reads : Array[(String, () -> Bool)]
  row_reads : Map[(Int, Int), (String, Double?)]
  words_reads : Map[String, Bool]
  /// the boxes whose rows left them out as last laid out (Ctx::box `drop`), by id, and those the view asked about as
  /// it built (Ctx::left_out: what it was told); how many rows laid out this pass may leave something out
  left_ids : Map[Int, Bool]
  left_reads : Map[Int, (Bool, SourceLoc)]
  mut fit_rows : Int
  laid_watch : Map[Int, Int]
  laid_rects : Map[Int, (Double, Double, Double, Double)]
  /// the boxes whose parts shown across are asked (Ctx::shown_across): when last, and the name of the boxes whose parts
  /// are left out; what the last layout showed across in each
  shown_watch : Map[Int, (Int, String)]
  shown_spans : Map[Int, (Double, Double)]
  /// the boxes whose presses another takes (Ctx::presses_to), by node: that one's id and where it was said
  press_owners : Map[Int, (Int, SourceLoc)]
  mut nav_rest : Double
  /// what is under everything the frame draws (0-1: what the host clears to as it presents it; Ctx::set_clear)
  mut clear : (Double, Double, Double)
  /// what of the host's answers is being recorded (hostrec.mbt)
  host_rec : HostRec
  /// covers by their ids, and those asked for this frame (cover.mbt)
  covers : Map[Int, CoverState]
  cover_asks : Array[CoverAsk]
  // the page being built (a page of a Nav, by its serial; 0 none), and the
  // ids of the state each page's widgets made, forgotten with the page
  mut owner : Int
  // the time on top of the page being built (nav.mbt Ctx::page_stint)
  mut stint : Int
  owned : Map[Int, Array[Int]]
  // back: where it goes this frame (the Nav drawn that can go back) and the
  // node it is drawn in, as the last frame had them; whether the host was
  // told that the app takes back; a finger on the left edge (1: there, 2:
  // moving the page)
  mut back : ((Int, Double, Double, Double) -> Unit)?
  mut back_node : Int
  mut back_edge : Double
  mut back_next : ((Int, Double, Double, Double) -> Unit)?
  mut back_node_next : Int
  mut back_edge_next : Double
  mut back_told : Bool
  mut edge : Int
  // the theme and the direction in force where the view builds (theme.mbt); the themes set, wide and narrow, the
  // width below which it is the narrow one, and whether this frame's is
  mut theme : Theme
  mut theme_wide : Theme
  mut theme_narrow : Theme?
  mut narrow_below : Double
  mut narrow : Bool
  // the boxes built this frame whose corner is `Inner` (style.mbt): worked out once laid out (corners.mbt), and
  // those that could not be (Tester::corner_faults says them); of them, those `InnerOr`, their own corner where they lie
  // in no container's
  inners : Array[Int]
  inners_or : Array[Int]
  // what move_state moves (move_state.mbt): the moves going on; what each box named to be moved was shown as, this
  // frame (its build so far) and the last; how many boxes of each name this build has built
  move_runs : Array[MoveRun]
  mut shown_now : Map[String, MoveShown]
  mut shown_last : Map[String, MoveShown]
  move_seen : Map[String, Int]
  // the boxes built this frame whose corner is `Around`: worked out from what lies in their corner (corners.mbt)
  arounds : Array[Int]
  inner_faults : Array[String]
  mut direction : Direction
  // what the widgets built this frame say they are (semantics.mbt), and how deep in a part hidden from it the view
  // builds; the actions asked of them (by the host's accessibility, a test) for the next frame, and this frame's
  sems : Array[Sem]
  mut sem_hide : Int
  sem_hidden : Array[(Int, Int)]
  asked_actions : Array[(Int, Action)]
  actions : Array[(Int, Action)]
  // what the system's accessibility was last told the widgets are (a11y.mbt; "" nothing yet, or it is off)
  mut a11y_sent : String
  // the keyboard's focus beyond a field's (focus.mbt): whether it shows (it came by the keyboard), what had it as the
  // frame started; what can take it, as this frame builds it and as the last one did; roving groups' state, and the
  // group being built
  mut focus_visible : Bool
  mut focus_roved : Bool
  mut focus_before : Int
  mut focusables : Array[Focusable]
  mut last_focusables : Array[Focusable]
  groups : Map[Int, Group]
  mut group_cur : Int
  // what lies over the page (overlay.mbt): its layers as this frame builds them and as the last one did, the one
  // being built, the dismissals asked for since, where a press went down since the last frame
  mut layers : Array[Layer]
  mut last_layers : Array[Layer]
  /// the layers this frame has given the focus as they opened (their ids): once a frame, at the first build they are in
  layers_opened : Array[Int]
  /// what the view tells outside of what it built, by key, this build's (Ctx::after_build): done once the frame's
  /// builds are over
  tells : Array[(Int, () -> Unit)]
  /// what the frame's builds said to tell outside, by its key, the last said of each kept, whichever build said it
  /// (Ctx::tell)
  told : Array[(Int, () -> Unit)]
  mut layer_cur : Int
  /// the layer the keys go to this frame (the topmost open one that takes them, as the frame before built it; 0: the
  /// page): what is built under it reads none (Ctx::key_pressed, Ctx::keys)
  mut keys_layer : Int
  dismissals : Map[Int, Dismiss]
  layer_return : Map[Int, Int]
  mut press_down : (Double, Double)?
  // output
  mut inst : FixedArray[Double]
  mut ninst : Int
  // the pieces of the shapes painted this frame (shape.mbt): x0 y0 x1 y1 each, as shares of their instance's rect
  segs : Array[Double]
  mut ime_sig : String
  /// the input method's action last told the host (@hostapi.ime_action)
  mut ime_action_told : Int
  // stats
  mut t_build : Double
  mut t_layout : Double
  mut t_paint : Double
  mut t_present : Double
  mut bench_list : Int
}

///|
fn Ctx::new() -> Ctx {
  {
    nodes: [],
    count: 0,
    cur: -1,
    id_seed: 17,
    id_stack: [],
    width: 800.0,
    height: 600.0,
    scale: 2.0,
    whole_px: false,
    now: 0.0,
    dt: 16.0,
    last_now: -1.0,
    frame_no: 0,
    font_scale: 1.0,
    build_no: 0,
    sideways_depth: 0,
    epoch: 0,
    wants_frame: false,
    wake_at: -1.0,
    wake_waited: -1.0,
    frame_rest: false,
    frame_by: None,
    wake_by: None,
    stuck: [],
    hit_ids: [],
    hit_rects: [],
    next_hit_ids: [],
    next_hit_rects: [],
    hit_clips: [],
    next_hit_clips: [],
    scroll_ids: [],
    scroll_rects: [],
    next_scroll_ids: [],
    next_scroll_rects: [],
    px: -1.0,
    py: -1.0,
    down: false,
    hover: 0,
    active: 0,
    focus: 0,
    clicked: [],
    double_clicked: [],
    last_click: (0, 0.0, 0.0, 0.0),
    drag_scroll: 0,
    press_chain: [],
    claimed: true,
    dragging: false,
    press_x: 0.0,
    press_at: -1.0,
    press_late: false,
    pointer_t: 0.0,
    held_told: -1.0,
    held_on: 0,
    held_frame: -1,
    press_seen: no_press,
    press_seen_frame: -1,
    press_was_down: false,
    press_seen_at: -1.0,
    press_mods: 0,
    tapped: None,
    taken_at: -1.0,
    press_y: 0.0,
    last_y: 0.0,
    last_x: 0.0,
    vel_x: 0.0,
    last_t: 0.0,
    vel: 0.0,
    editor_drag: false,
    handle_drag: 0,
    editor_tap: 0,
    handle_which: 0,
    word_drag: 0,
    last_tap: (0, -1.0e9, 0.0, 0.0),
    menu_sig: "",
    handle_dy: 0.0,
    lists: Map::new(),
    editors: Map::new(),
    dev: DeviceState::new(),
    springs: Map::new(),
    movers: [],
    cycling: false,
    cycles: [],
    periodic: [],
    motion_left: false,
    fiber_frame: false,
    motion_unstarted: false,
    took_input: false,
    read_back_moved: false,
    read_back_key: "",
    laid_reads: Map::new(),
    size_reads: Map::new(),
    place_reads: Map::new(),
    info_reads: [],
    row_reads: Map::new(),
    words_reads: Map::new(),
    left_ids: Map::new(),
    left_reads: Map::new(),
    fit_rows: 0,
    laid_watch: Map::new(),
    laid_rects: Map::new(),
    shown_watch: Map::new(),
    shown_spans: Map::new(),
    press_owners: Map::new(),
    nav_rest: -1.0,
    clear: (0.961, 0.961, 0.969),
    host_rec: HostRec::new(),
    covers: Map::new(),
    cover_asks: [],
    owner: 0,
    stint: 0,
    owned: Map::new(),
    back: None,
    back_node: -1,
    back_edge: 20.0,
    back_next: None,
    back_node_next: -1,
    back_edge_next: 20.0,
    back_told: false,
    edge: 0,
    theme: Theme::light(),
    theme_wide: Theme::light(),
    theme_narrow: None,
    narrow_below: 700.0,
    narrow: false,
    inners: [],
    inners_or: [],
    move_runs: [],
    shown_now: {},
    shown_last: {},
    move_seen: {},
    arounds: [],
    inner_faults: [],
    direction: Ltr,
    sems: [],
    sem_hide: 0,
    sem_hidden: [],
    asked_actions: [],
    actions: [],
    a11y_sent: "",
    focus_visible: false,
    focus_roved: false,
    focus_before: 0,
    focusables: [],
    last_focusables: [],
    groups: Map::new(),
    group_cur: 0,
    layers: [],
    last_layers: [],
    layers_opened: [],
    tells: [],
    told: [],
    layer_cur: 0,
    keys_layer: 0,
    dismissals: Map::new(),
    layer_return: Map::new(),
    press_down: None,
    inst: FixedArray::make(inst_size * 4096, 0.0),
    ninst: 0,
    segs: [],
    ime_sig: "",
    ime_action_told: 0,
    t_build: 0.0,
    t_layout: 0.0,
    t_paint: 0.0,
    t_present: 0.0,
    bench_list: 0,
  }
}

// ---------------------------------------------------------------------------
// Ids

///|
fn mix(a : Int, b : Int) -> Int {
  let mut h = a ^ (b * 0x5bd1e995)
  h = h ^ (h >> 15)
  h = h * 0x27d4eb2d
  h = h ^ (h >> 13)
  if h == 0 {
    1
  } else {
    h
  }
}

///|
/// A widget id from a key, unique within the current scope.
pub fn Ctx::id(self : Ctx, key : String) -> Int {
  mix(self.id_seed, stable_hash(key).to_int())
}

///|
/// Runs `body` with ids scoped by `key` (rows of a list use their index).
pub fn Ctx::scope(self : Ctx, key : Int, body : () -> Unit) -> Unit {
  self.id_stack.push(self.id_seed)
  self.id_seed = mix(self.id_seed, key + 1)
  body()
  self.id_seed = self.id_stack.pop().unwrap()
}

// ---------------------------------------------------------------------------
// Building

///|
fn Ctx::alloc(self : Ctx, kind : Int) -> Int {
  self.alloc_part(kind, true, true)
}

///|
/// A node of `kind` under the current one; its look and its words reset
/// only when asked: a box sets all of its look, a text all of its words,
/// and only texts, rich text and editors read words (an image only its
/// source, which it sets).
fn Ctx::alloc_part(self : Ctx, kind : Int, look : Bool, words : Bool) -> Int {
  let i = self.count
  if i < self.nodes.length() {
    let n = self.nodes[i]
    n.reset_rest()
    if look {
      n.reset_look()
    }
    if words {
      n.reset_words()
    }
  } else {
    self.nodes.push(Node::new())
  }
  self.count = i + 1
  let n = self.nodes[i]
  n.kind = kind
  n.in_sideways = self.sideways_depth > 0
  n.parent = self.cur
  if self.cur >= 0 {
    let p = self.nodes[self.cur]
    if p.last >= 0 {
      self.nodes[p.last].next = i
    } else {
      p.first = i
    }
    p.last = i
  }
  i
}

///|
fn Ctx::with_parent(self : Ctx, i : Int, body : () -> Unit) -> Unit {
  let saved = self.cur
  self.cur = i
  body()
  self.cur = saved
}

///|
/// A box laying out its children in a row or a column, flexbox style. `notch_r` > 0 cuts a notch into its top edge
/// (its ground, border and glass alike): a circle of that radius about the middle of its top, `notch_y` below the edge
/// (above it when negative), met by the edge through fillets of `notch_fillet` (Bar.kt's notch). `aspect` > 0: its
/// width over its height, the side not said following the other (CSS's aspect-ratio). Built where the direction is
/// right to left (Ctx::rtl), a row runs from the right and its left and right padding swap. `keep`: in a row, as wide
/// as its content even where the row is short of room, its siblings squeezed instead (as Compose's Row measures what
/// has no weight whole, a weight(1f, fill = false) sibling given the rest: a bar's title cut short, not its buttons);
/// one that takes what its row leaves (`Fill`), never less than what it holds needs (CSS's flex: 1).
/// `drop` k > 0: there whole (as wide as what it holds) or left out of its row when the row has not the room, the
/// lowest k first (of the same k the last in the row first), laid out nowhere and not drawn (Ctx::left_out says so, for
/// a ⋯ that offers it instead); `more`: the row's ⋯, there only while something of it is left out.
/// `flow`: a row that goes on in lines when what it holds does not fit, each thing in it as wide as it is, `gap` apart
/// along the line and between the lines, or `line_gap` between the lines (Compose's FlowRow and its two spacedBy).
/// `label`: what it is called where it shows no words (an icon's button, as Compose's contentDescription), found by
/// them whole as words are (a drive's `=WORDS`, Tester::locate). `name`: what it stands for in another app's tree (the
/// web page's class it is ported from, `shellCss.dock`), read only by a tool comparing the two (Tester::boxes).
///
/// `style` (style.mbt) says how it looks, its state blocks picked by its own state: pressed, hovered, focused by `id`
/// (as Ctx::pressed, hovered, focus_shown read them), `selected` and `disabled` as said, dark and narrow by the theme
/// (Ctx::set_theme). What is said here besides (`pad=`, `bg=`…) wins over the style's same property; what neither
/// says is as without either (no padding, no ground). A padding below 0 is not said (Ctx::row passes -1). With an
/// `id` it takes the presses on its room (the innermost box with an id under the finger does); `taps` false: the id
/// only names it (to measure it, Ctx::laid_size; to move it by a look), what holds it taking the presses there.
///
/// What CSS says of a box and the flex engine lays out anyway: margins (`m`, `mx`, `my`, `ml`, `mr`, `mt`, `mb`, below
/// 0 too, the finer over the coarser as the padding), a size as a share of the parent's (`Pct`), and `left`, `top`,
/// `right`, `bottom`: any said, it is out of the flow, put that far from its parent's edges, the parent's padding not
/// kept (CSS's position: absolute, its parent the one it is placed in), drawn and pressed in the order it was built;
/// both of a pair said and no size across, it reaches from one to the other. `moves`: the name Ctx::move_state moves
/// it by.
pub fn Ctx::box(
  self : Ctx,
  style? : Style,
  selected? : Bool = false,
  disabled? : Bool = false,
  dir? : Dir,
  w? : Size,
  h? : Size,
  pad? : Double,
  padx? : Double,
  pady? : Double,
  pl? : Double,
  pr? : Double,
  pt? : Double,
  pb? : Double,
  m? : Double,
  mx? : Double,
  my? : Double,
  ml? : Double,
  mr? : Double,
  mt? : Double,
  mb? : Double,
  left? : Double,
  top? : Double,
  right? : Double,
  bottom? : Double,
  moves? : String = "",
  gap? : Double,
  align? : Align,
  justify? : Justify,
  bg? : Int64,
  radius? : Double,
  border? : Double,
  border_color? : Int64,
  shadow? : Double,
  shadow_color? : Int64,
  shadow_y? : Double,
  min_w? : Double,
  max_w? : Double,
  min_h? : Double,
  max_h? : Double,
  clip? : Bool,
  tx? : Double = 0.0,
  ty? : Double = 0.0,
  opacity? : Double,
  glass? : Glass,
  glass_group? : Bool = false,
  notch_y? : Double = 0.0,
  notch_r? : Double = 0.0,
  notch_fillet? : Double = 0.0,
  aspect? : Double = 0.0,
  keep? : Bool = false,
  drop? : Int = 0,
  more? : Bool = false,
  shadow_out? : Bool = false,
  flow? : Bool = false,
  line_gap? : Double = -1.0,
  label? : String = "",
  name? : String = "",
  id? : Int = 0,
  taps? : Bool = true,
  body : () -> Unit,
) -> Int {
  let i = self.alloc_part(kind_box, false, false)
  let n = self.nodes[i]
  // the style's look in this node's states, the tokens looked up in the theme in force
  let st : Patch = match style {
    None => no_patch
    Some(s) =>
      s.resolve(
        self.narrow,
        self.theme.dark,
        selected,
        id != 0 && self.lit(id),
        id != 0 && self.focus_shown(id),
        id != 0 && self.pressed(id),
        disabled,
      )
  }
  let th = self.theme
  n.dir = first(
    dir,
    match st.row {
      Some(true) => Some(Row)
      Some(false) => Some(Column)
      None => None
    },
  ).unwrap_or(Column)
  n.rtl = self.direction == Rtl
  n.aspect = aspect
  n.keep = keep
  n.drop = if more { -1 } else { drop }
  n.shadow_out = shadow_out
  n.flow = flow
  n.line_gap = line_gap
  n.label = label
  n.name = name
  n.w = first(
    w,
    match st.w {
      Some(l) => Some(l.size())
      None => None
    },
  ).unwrap_or(Auto)
  n.h = first(
    h,
    match st.h {
      Some(l) => Some(l.size())
      None => None
    },
  ).unwrap_or(Auto)
  // one side said on its own wins over both sides, both over all four; said here over the style's
  let pad = said(pad)
  let px = first(said(padx), pad)
  let py = first(said(pady), pad)
  let s_x = opt_px(first(st.px, st.p))
  let s_y = opt_px(first(st.py, st.p))
  n.pad_l = first(said(pl), first(px, first(opt_px(st.pl), s_x))).unwrap_or(0.0)
  n.pad_r = first(said(pr), first(px, first(opt_px(st.pr), s_x))).unwrap_or(0.0)
  // right to left, the start (left said) is the right
  if n.rtl {
    let l = n.pad_l
    n.pad_l = n.pad_r
    n.pad_r = l
  }
  n.pad_t = first(said(pt), first(py, first(opt_px(st.pt), s_y))).unwrap_or(0.0)
  n.pad_b = first(said(pb), first(py, first(opt_px(st.pb), s_y))).unwrap_or(0.0)
  // margins as the padding: one side said over both, both over all four, said here over the style's (below 0 too)
  let mx = first(mx, m)
  let my = first(my, m)
  let sm_x = opt_margin(first(st.mx, st.m))
  let sm_y = opt_margin(first(st.my, st.m))
  n.mar_l = first(ml, first(mx, first(opt_margin(st.ml), sm_x))).unwrap_or(0.0)
  n.mar_r = first(mr, first(mx, first(opt_margin(st.mr), sm_x))).unwrap_or(0.0)
  if n.rtl {
    let l = n.mar_l
    n.mar_l = n.mar_r
    n.mar_r = l
  }
  n.mar_t = first(mt, first(my, first(opt_margin(st.mt), sm_y))).unwrap_or(0.0)
  n.mar_b = first(mb, first(my, first(opt_margin(st.mb), sm_y))).unwrap_or(0.0)
  n.at_l = left.unwrap_or(0.0 / 0.0)
  n.at_t = top.unwrap_or(0.0 / 0.0)
  n.at_r = right.unwrap_or(0.0 / 0.0)
  n.at_b = bottom.unwrap_or(0.0 / 0.0)
  n.min_w = first(min_w, opt_bound(st.min_w, 0.0)).unwrap_or(0.0)
  n.max_w = first(max_w, opt_bound(st.max_w, 1.0e9)).unwrap_or(1.0e9)
  n.min_h = first(min_h, opt_bound(st.min_h, 0.0)).unwrap_or(0.0)
  n.max_h = first(max_h, opt_bound(st.max_h, 1.0e9)).unwrap_or(1.0e9)
  let (sh_blur, sh_y) = match st.shadow {
    Some(s) => {
      let (b, y) = s.blur_y()
      (Some(b), Some(y))
    }
    None => (None, None)
  }
  n.shadow_c = first(
    shadow_color,
    match st.shadow {
      Some(Cast(_, _, c)) => Some(c)
      Some(_) => Some(th.shadow)
      None => None
    },
  ).unwrap_or(0x0000002EL)
  n.shadow_y = first(shadow_y, sh_y).unwrap_or(-1.0)
  n.gap = first(gap, opt_px(st.gap)).unwrap_or(0.0)
  n.align = first(align, st.align).unwrap_or(AStretch)
  n.justify = first(justify, st.justify).unwrap_or(JStart)
  n.bg = first(bg, opt_color(th, st.bg)).unwrap_or(0L)
  n.radius = first(
    radius,
    match st.radius {
      Some(r) => Some(th.corner(r))
      None => None
    },
  ).unwrap_or(0.0)
  // a corner said `Inner` (and not said here): worked out once laid out (corners.mbt); `InnerOr`, its own till then
  if radius is None && st.radius is Some(Inner) {
    self.inners.push(i)
  }
  if radius is None && st.radius is Some(InnerOr(_)) {
    self.inners.push(i)
    self.inners_or.push(i)
  }
  // `Around`: from what lies in its corner, once laid out
  if radius is None && st.radius is Some(Around) {
    self.arounds.push(i)
  }
  n.border_w = first(
    border,
    match st.border {
      Some(b) => Some(b.px())
      None => None
    },
  ).unwrap_or(0.0)
  n.border_c = first(border_color, opt_color(th, st.border_color)).unwrap_or(0L)
  n.shadow = first(shadow, sh_blur).unwrap_or(0.0)
  n.clip = first(clip, st.clip).unwrap_or(false)
  n.tx = tx
  n.ty = ty
  // (placed by its own size only when told so this frame, Ctx::place_by_size: a slot a menu was placed in last
  // frame is not where a box built there now goes)
  n.place = None
  n.opacity = first(
    opacity,
    match st.opacity {
      Some(o) => Some(o.value())
      None => None
    },
  ).unwrap_or(1.0)
  n.glass = glass
  n.glass_group = glass_group
  n.notch_y = notch_y
  n.notch_r = notch_r
  n.notch_f = notch_fillet
  if id != 0 {
    n.id = id
    // (`taps` false: an id only to be measured or moved by (laid_size, a look): what is pressed in it is what holds
    // it, not it, which would take every press on its room that nothing in it takes)
    n.hit = taps
  }
  // moved by a move_state (move_state.mbt): what it is shown as while the move lasts, where it was to where it is built
  if moves != "" {
    n.moves = moves
    self.move_node(i)
  }
  self.with_parent(i, body)
  i
}

///|
/// A padding said in a call: one below 0 is not (the -1 Ctx::row and the like pass on).
fn said(v : Double?) -> Double? {
  match v {
    Some(x) if x >= 0.0 => v
    _ => None
  }
}

///|
fn opt_margin(v : Space?) -> Double? {
  match v {
    Some(v) => Some(v.margin_px())
    None => None
  }
}

///|
fn opt_px(v : Space?) -> Double? {
  match v {
    Some(v) => Some(v.px())
    None => None
  }
}

///|
fn opt_color(th : Theme, v : Color?) -> Int64? {
  match v {
    Some(v) => Some(th.color(v))
    None => None
  }
}

///|
fn opt_bound(v : Len?, none_is : Double) -> Double? {
  match v {
    Some(v) => Some(v.bound(none_is))
    None => None
  }
}

///|
/// A style that says nothing.
// kept across runs: a value (no field of it changes)
let no_patch : Patch = patch()

///|
pub fn Ctx::row(
  self : Ctx,
  w? : Size = Auto,
  h? : Size = Auto,
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  gap? : Double = 0.0,
  align? : Align = ACenter,
  justify? : Justify = JStart,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  self.box(
    dir=Row,
    w~,
    h~,
    pad~,
    padx~,
    pady~,
    gap~,
    align~,
    justify~,
    bg~,
    radius~,
    body,
  )
}

///|
pub fn Ctx::column(
  self : Ctx,
  w? : Size = Auto,
  h? : Size = Auto,
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  gap? : Double = 0.0,
  align? : Align = AStretch,
  justify? : Justify = JStart,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  self.box(
    dir=Column,
    w~,
    h~,
    pad~,
    padx~,
    pady~,
    gap~,
    align~,
    justify~,
    bg~,
    radius~,
    body,
  )
}

///|
/// A column laid over its parent, the whole of it, in front of what the
/// parent holds before it: for bars and menus over a page. Taps go through
/// to what is under it except on what it holds that takes them.
pub fn Ctx::layer(
  self : Ctx,
  pad? : Double = 0.0,
  align? : Align = AStretch,
  body : () -> Unit,
) -> Int {
  let i = self.box(pad~, align~, body)
  self.nodes[i].layer = true
  i
}

///|
pub fn Ctx::spacer(self : Ctx) -> Unit {
  let i = self.alloc_part(kind_box, true, false)
  self.nodes[i].w = Fill(1.0)
  self.nodes[i].h = Fill(1.0)
}

///|
/// Words, in the theme's colour unless `color`. `style` (style.mbt) says how they look, its dark and narrow blocks by
/// the theme; what is said here besides wins over the style's same property (a size said here keeps the style's line).
/// `tracking`: letter spacing in pixels; `max_lines`: wrapped words cut after that many lines, ending in an ellipsis.
/// `trim`: a font taller than the line not padded beyond its own reach where a host sets lines on whole pixels (as
/// Compose sets words in a TextStyle of their own; else as a theme's words: set_line).
pub fn Ctx::text(
  self : Ctx,
  s : String,
  style? : TextStyle,
  size? : Double,
  weight? : Int,
  color? : Int64,
  wrap? : Bool,
  w? : Size,
  line? : Double,
  trim? : Bool = false,
  center? : Bool,
  tracking? : Double,
  max_lines? : Int,
) -> Int {
  let st = self.text_patch(style)
  let (s_size, s_line) = self.text_sizes(st)
  let i = self.alloc_part(kind_text, true, false)
  let n = self.nodes[i]
  n.center = first(center, st.center).unwrap_or(false)
  n.text = s
  // (sizes as the original's sp: the system's size of words applied, fontscale.mbt)
  n.font_size = self.sp(first(size, s_size).unwrap_or(15.0))
  n.line_h = first(line, s_line).map(fn(l) { self.sp(l) }).unwrap_or(self.theme.text_line * n.font_size)
  n.line_trim = trim
  n.weight = first(weight, opt_weight(st.weight)).unwrap_or(400)
  n.color = first(color, opt_color(self.theme, st.color)).unwrap_or(self.theme.fg)
  n.wrap = first(wrap, st.wrap).unwrap_or(true)
  n.w = first(w, opt_size(st.w)).unwrap_or(Auto)
  n.spacing = match (tracking, st.tracking) {
    (Some(v), _) => self.sp(v)
    (None, Some(t)) => t.px(n.font_size)
    (None, None) => 0.0
  }
  n.max_lines = first(max_lines, st.max_lines).unwrap_or(0)
  i
}

///|
/// Words' style in this frame's states (dark, narrow).
fn Ctx::text_patch(self : Ctx, style : TextStyle?) -> TextPatch {
  match style {
    None => no_text_patch
    Some(t) => t.resolve(self.narrow, self.theme.dark)
  }
}

///|
/// The size and the line a style's words have, in the theme in force: the line its `leading` when it says one, else
/// its size's. (A node's line_h 0 is the font's own: `Font`.)
fn Ctx::text_sizes(self : Ctx, st : TextPatch) -> (Double?, Double?) {
  let (size, line) = match st.size {
    Some(z) => {
      let (size, line) = self.theme.text_size(z)
      (Some(size), Some(line))
    }
    None => (None, None)
  }
  match st.leading {
    Some(l) => (size, Some(self.theme.leading(l).unwrap_or(0.0)))
    None => (size, line)
  }
}

///|
fn opt_weight(v : Weight?) -> Int? {
  match v {
    Some(v) => Some(v.value())
    None => None
  }
}

///|
fn opt_size(v : Len?) -> Size? {
  match v {
    Some(v) => Some(v.size())
    None => None
  }
}

///|
/// Words' style that says nothing.
// kept across runs: a value (no field of it changes)
let no_text_patch : TextPatch = text_patch()

// ---------------------------------------------------------------------------
// Interaction

///|
/// Whether `id` was clicked twice in a row since the last frame (a desktop's double click: the second within
/// double_click_ms of the first, both on it, as near as double_click_slop). Its first click was `clicked` too.
pub fn Ctx::double_clicked(self : Ctx, id : Int) -> Bool {
  id != 0 && self.double_clicked.contains(id)
}

///|
/// How soon after the first the second of two clicks is (macOS's default: 500 ms), and how near it (4).
pub let double_click_ms : Double = 500.0

///|
pub let double_click_slop : Double = 4.0

///|
pub fn Ctx::clicked(self : Ctx, id : Int) -> Bool {
  // (what a click changes is drawn by the next frame wherever it was seen, as every input's: on_frame; the Activate
  // a screen reader asks of it is one: semantics.mbt)
  self.clicked.contains(id) || (id != 0 && self.action_asked(id, Activate))
}

///|
/// What is under everything the frame draws, as an 0xAARRGGBB colour (its alpha not used): what the host clears to,
/// and what shows where the app has not drawn yet (under a soft keyboard as it moves, the frame before the app's
/// follows it). An app sets its ground, as a window's background is.
pub fn Ctx::set_clear(self : Ctx, color : Int64) -> Unit {
  self.clear = (
    ((color >> 16) & 0xFFL).to_double() / 255.0,
    ((color >> 8) & 0xFFL).to_double() / 255.0,
    (color & 0xFFL).to_double() / 255.0,
  )
}

///|
/// Whether a mouse's pointer rests on `id` (a finger hovers over nothing: Pointing). For what only a resting pointer
/// is shown; a look that answers the hand on it is Ctx::lit.
pub fn Ctx::hovered(self : Ctx, id : Int) -> Bool {
  self.hover == id
}

///|
/// Whether `id` is lit by the hand on it: a mouse's pointer resting on it, a finger pressing it (the web's `:hover`
/// with a fine pointer, `:active` with a coarse one). What a style's `hovered` patch and a widget's hovered look go by.
pub fn Ctx::lit(self : Ctx, id : Int) -> Bool {
  match pointing() {
    Mouse => self.hover == id
    Finger => self.pressed(id)
  }
}

///|
pub fn Ctx::pressed(self : Ctx, id : Int) -> Bool {
  if self.active != id || !self.down {
    return false
  }
  if self.press_late && self.now < self.press_at + tap_indication_ms {
    self.wake_at_time(self.press_at + tap_indication_ms)
    return false
  }
  true
}

///|
/// How long a press in what scrolls stays before it shows (Android's ViewConfiguration tap timeout, Compose's
/// TapIndicationDelay).
pub let tap_indication_ms : Double = 100.0

///|
/// Whether a frame is being built now (on_frame): a frame asked for outside one is the host's to be told of.
let in_frame : Ref[Bool] = Ref::new(false)

///|
/// What the view reads changed (`what`: said by an unsettled frame that never stops changing it): while the frame is
/// built or laid out, it is built again in it before it is drawn (frame_body), so no frame shows the state as it
/// was; between frames (a host's callback), the next frame builds from it.
#callsite(autofill(loc))
fn Ctx::read_changed(self : Ctx, what : String, loc~ : SourceLoc) -> Unit {
  if building.val {
    self.read_back_moved = true
    self.read_back_key = what
  } else {
    self.request_frame(loc~)
  }
}

///|
/// What the view built from changed as it was built, by what it took of the pointer (a column's edge dragged: the
/// column, built before its edge, built at the width it had): the frame is built again from it before it is drawn, as
/// for what mbui's own parts change (Ctx::read_changed), so what the pointer moved is under it in the frame it moved in.
/// Said only when it did change: the frame built again finds it as it is now and says nothing.
#callsite(autofill(loc))
pub fn Ctx::built_from_changed(self : Ctx, what : String, loc~ : SourceLoc) -> Unit {
  self.read_changed(what, loc~)
}

///|
/// A motion set out between frames (Ctx::set_out): a frame is owed to show it, the host told now, as a frame asked
/// between frames is.
fn Ctx::owe_frame(self : Ctx) -> Unit {
  self.wants_frame = true
  h_request_frame()
}

///|
/// An event for the next frame's start to take, come in a frame that took its events already (a stream's frame let
/// go as it builds: Stream::let_go): the next frame is owed to it, the host told now, as for a motion set out
/// (owe_start); building this one again would not take it.
fn Ctx::owe_next(self : Ctx) -> Unit {
  self.wants_frame = true
  h_request_frame()
}

///|
#callsite(autofill(loc))
pub fn Ctx::request_frame(self : Ctx, loc~ : SourceLoc) -> Unit {
  self.wants_frame = true
  // asked between frames (a host's callback, a timer's): the frame's own asking (on_frame's end) is past, so the
  // host is told now, else nothing comes (the next frame's start clears wants_frame)
  if !in_frame.val {
    h_request_frame()
  }
  if self.frame_by is None {
    self.frame_by = Some(loc)
  }
}

///|
/// The window's size in logical pixels (w, h), as this frame lays it out: what a dialog is put in the middle of.
pub fn Ctx::window_size(self : Ctx) -> (Double, Double) {
  (self.width, self.height)
}

///|
pub fn Ctx::now(self : Ctx) -> Double {
  self.now
}

///|
/// The moment now: the frame's time in a frame (Ctx::now), else the clock's as it stands between frames (an input's
/// handler, a fiber, a test's change): where what is told now starts from.
pub fn Ctx::moment(self : Ctx) -> Double {
  if self.in_frame() {
    self.now
  } else {
    h_now()
  }
}

///|
/// `t` (ms) in whole ms, as a motion's and the runtime's time go: rounded down, a moment summed one way or another
/// (1316.9999999999998 for 1317) the same.
pub fn whole_ms(t : Double) -> Double {
  (t + 1.0e-6).floor()
}

///|
pub fn Ctx::frame_ms(self : Ctx) -> Double {
  self.t_build + self.t_layout + self.t_paint
}

///|
pub fn Ctx::present_ms(self : Ctx) -> Double {
  self.t_present
}

///|
/// When the pointer's latest event came (pressed, moved, let go), by its own time: the host's time of the event on a
/// device, the clock as the event was handed in under a Tester. For how fast and how far apart what a finger did was
/// (a swipe's speed, a double tap's gap), not how far apart the frames that took it are.
pub fn Ctx::pointer_at(self : Ctx) -> Double {
  self.pointer_t
}

///|
/// How fast the pointer went at its latest event (points per ms, across and down; at most a fling's fastest): what a
/// list let go flings at (Compose's VelocityTracker over the press's events, by their own times), for what else a
/// finger lets go of moving (a picture zoomed in).
pub fn Ctx::pointer_velocity(self : Ctx) -> (Double, Double) {
  ignore(self)
  (dclamp(track_x.velocity(), -max_fling, max_fling), dclamp(track_y.velocity(), -max_fling, max_fling))
}

///|
fn hit_in(ids : Array[Int], rects : Array[Double], x : Double, y : Double) -> Int {
  let targets = physical_equal(rects, g().hit_rects)
  let clips = if targets { g().hit_clips } else { [] }
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] &&
      in_round_clip(clips, k, x, y) {
      break
    }
    k = k - 1
  }
  // a finger: what is smaller than a fingertip is reached from round it (Pointing)
  if targets && pointing() is Finger {
    match finger_reach(ids, rects, clips, k, x, y) {
      Some(id) => return id
      None => ()
    }
  }
  if k >= 0 {
    ids[k]
  } else {
    0
  }
}

///|
/// The least a finger's target is across, each way: the system's (Android's 48 dp, Compose's
/// minimumInteractiveComponentSize; iOS's 44 pt).
fn finger_target() -> Double {
  if h_platform() == 1 {
    44.0
  } else {
    48.0
  }
}

///|
/// What a finger at (x, y) reaches that it does not touch (Compose's minimum touch target): a target smaller than
/// finger_target, grown to it round its middle (not drawn so, nor laid out), drawn over `top` (the target the finger
/// is on, -1 none) and within it (a row's small button, not the row's neighbour: the one touched keeps it), within
/// what cuts it; of several, the nearest.
fn finger_reach(
  ids : Array[Int],
  rects : Array[Double],
  clips : Array[Double],
  top : Int,
  x : Double,
  y : Double,
) -> Int? {
  let least = finger_target()
  let mut best : Int? = None
  let mut best_d = 1.0e9
  for k in (top + 1)..<ids.length() {
    let r = k * 4
    let (x0, y0, x1, y1) = (rects[r], rects[r + 1], rects[r + 2], rects[r + 3])
    let (w, h) = (x1 - x0, y1 - y0)
    if w <= 0.0 || h <= 0.0 || (w >= least && h >= least) {
      continue
    }
    let gx = dmax(0.0, (least - w) / 2.0)
    let gy = dmax(0.0, (least - h) / 2.0)
    if x < x0 - gx || x >= x1 + gx || y < y0 - gy || y >= y1 + gy {
      continue
    }
    // within what cuts it (a list's edge), and within what the finger is on
    let b = k * clip_n
    if b + clip_n <= clips.length() &&
      (x < clips[b] || x >= clips[b + 2] || y < clips[b + 1] || y >= clips[b + 3]) {
      continue
    }
    if top >= 0 {
      let t = top * 4
      if x0 < rects[t] || y0 < rects[t + 1] || x1 > rects[t + 2] || y1 > rects[t + 3] {
        continue
      }
    }
    let dx = dmax(0.0, dmax(x0 - x, x - x1))
    let dy = dmax(0.0, dmax(y0 - y, y - y1))
    let d = dx * dx + dy * dy
    if d < best_d {
      best_d = d
      best = Some(ids[k])
    }
  }
  best
}

///|
/// Whether (x, y), in hit target `k`'s rect, is within the rounded corners of what cut it (`clips`, Ctx::hit_clips):
/// a corner as round, and as smooth, as the renderers cut it (smooth.mbt sd_corner; its radius at most half the clip's
/// shorter side).
fn in_round_clip(clips : Array[Double], k : Int, x : Double, y : Double) -> Bool {
  let b = k * clip_n
  if b + clip_n > clips.length() {
    return true
  }
  let (x0, y0, x1, y1) = (clips[b], clips[b + 1], clips[b + 2], clips[b + 3])
  let hx = dmax((x1 - x0) / 2.0, 0.0)
  let hy = dmax((y1 - y0) / 2.0, 0.0)
  let mx = x0 + hx
  let my = y0 + hy
  // the corner of the quarter it is in (top left, then clockwise)
  let j = if x < mx {
    if y < my {
      0
    } else {
      3
    }
  } else if y < my {
    1
  } else {
    2
  }
  let r = dmin(clips[b + 4 + j], dmin(hx, hy))
  r <= 0.0 || sd_corner(x - mx, y - my, hx, hy, r, clips[b + 8 + j]) <= 0.0
}

///|
/// A hit target drawn now: `id` where (x0 y0 x1 y1) shows (cut already to the clip's rect), and the clip itself.
fn Ctx::push_hit(
  self : Ctx,
  id : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit {
  self.next_hit_ids.push(id)
  self.next_hit_rects.push(x0)
  self.next_hit_rects.push(y0)
  self.next_hit_rects.push(x1)
  self.next_hit_rects.push(y1)
  let k = clip_top()
  for j in 0..<clip_n {
    self.next_hit_clips.push(clip_stack[k + j])
  }
}

///|
/// A value that follows `target` with a spring.
#callsite(autofill(loc))
pub fn Ctx::spring(
  self : Ctx,
  key : String,
  target : Double,
  from? : Double,
  stiffness? : Double = 420.0,
  damping? : Double = 32.0,
  loc~ : SourceLoc,
) -> Double {
  let id = self.id(key)
  let s = match self.springs.get(id) {
    Some(s) => s
    None => {
      let s = SpringPath::new(from.unwrap_or(target), k=stiffness, c=damping)
      self.springs[id] = s
      self.own(id)
      s
    }
  }
  // where it is now: a function of the time since it set out (motion_data.mbt); a new target (or one born away from
  // it) sets it out again from here, as fast as it goes
  if target != s.target() {
    s.go(self.now, target, what="c.spring \"" + key + "\"", loc~)
  }
  s.value(self.now)
}

///|
/// When the spring `key` (Ctx::spring, in the same scope) is at rest (the frames' clock; -1: it is, or there is none):
/// what a test runs to.
pub fn Ctx::spring_rest(self : Ctx, key : String) -> Double {
  match self.springs.get(self.id(key)) {
    Some(s) if s.end() > self.now => s.end()
    _ => -1.0
  }
}

///|
fn Ctx::wake_at_time(self : Ctx, t : Double, later? : Bool = false) -> Unit {
  if self.wake_at < 0.0 || t < self.wake_at {
    self.wake_at = t
  }
  if !later && (self.wake_waited < 0.0 || t < self.wake_waited) {
    self.wake_waited = t
  }
}

///|
/// Where the thing with `id` was drawn last frame (x, y, w, h), as far as it
/// showed: for parts that follow the pointer across them (a slider). The hit area the last frame drew, cut to its
/// clips: for following a finger and hitting, not for sizing what is built (that is Ctx::laid_rect, this frame's
/// layout, read back).
pub fn Ctx::rect_of(self : Ctx, id : Int) -> (Double, Double, Double, Double)? {
  let mut k = self.hit_ids.length() - 1
  while k >= 0 {
    if self.hit_ids[k] == id {
      let r = k * 4
      return Some(
        (
          self.hit_rects[r],
          self.hit_rects[r + 1],
          self.hit_rects[r + 2] - self.hit_rects[r],
          self.hit_rects[r + 3] - self.hit_rects[r + 1],
        ),
      )
    }
    k = k - 1
  }
  None
}

///|
/// The pointer, and whether it is down.
pub fn Ctx::pointer(self : Ctx) -> (Double, Double, Bool) {
  (self.px, self.py, self.down)
}

///|
/// `url` handed to the system: its browser, or the app it belongs to (Android's ACTION_VIEW, macOS's NSWorkspace,
/// iOS's UIApplication, Windows' ShellExecute, the browser's window.open). False when nothing took it.
pub fn Ctx::open_url(self : Ctx, url : String) -> Bool {
  ignore(self)
  h_open_url(url)
}

///|
/// The number on the app's icon (@hostapi.set_badge: macOS's Dock tile), 0 none. Under a Tester: kept (Tester::badge).
pub fn set_badge(n : Int) -> Unit {
  match fake.val {
    Some(f) => f.badge = n
    None => @hostapi.set_badge(n)
  }
}

///|
/// This machine's station as the system says it (@hostapi.local_station), JSON; "" none. Under a Tester: as it is set
/// (Tester::set_local_station).
pub fn local_station() -> String {
  match fake.val {
    Some(f) => f.local_station
    None => @hostapi.local_station()
  }
}

///|
/// Something done to this machine's station (@hostapi.local_station_act). Under a Tester: kept (Tester::local_acts).
pub fn local_station_act(action : String) -> Unit {
  match fake.val {
    Some(f) => f.local_acts.push(action)
    None => @hostapi.local_station_act(action)
  }
}

///|
/// Whether there is a dock here (@hostapi.dock_available). Under a Tester: as it is set (Tester::set_dock).
pub fn dock_available() -> Bool {
  match fake.val {
    Some(f) => f.dock_on
    None => @hostapi.dock_available()
  }
}

///|
/// The keys held down now (@hostapi.mods_held: mod_shift_key, mod_ctrl, mod_alt, mod_cmd). Under a Tester: as it holds
/// them (Tester::hold_mods).
pub fn mods_held() -> Int {
  match fake.val {
    Some(f) => f.mods
    None => @hostapi.mods_held()
  }
}

///|
/// A line to the dock (@hostapi.dock_send). Under a Tester: kept (Tester::dock_lines).
pub fn dock_send(line : String) -> Unit {
  match fake.val {
    Some(f) => f.dock_lines.push(line)
    None => @hostapi.dock_send(line)
  }
}

///|
/// The dock stopped (@hostapi.dock_stop).
pub fn dock_stop() -> Unit {
  match fake.val {
    Some(f) => f.dock_stops = f.dock_stops + 1
    None => @hostapi.dock_stop()
  }
}

///|
/// The dock's settings as kept on this device (@hostapi.dock_kept), and kept (dock_keep).
pub fn dock_kept() -> String {
  match fake.val {
    Some(f) => f.dock_kept
    None => @hostapi.dock_kept()
  }
}

///|
pub fn dock_keep(json : String) -> Unit {
  match fake.val {
    Some(f) => f.dock_kept = json
    None => @hostapi.dock_keep(json)
  }
}

///|
/// `url` handed to the system, outside a frame (an answer that came between frames): as Ctx::open_url.
pub fn open_url(url : String) -> Bool {
  h_open_url(url)
}

///|
/// A package (an APK a chat has) handed to the system's installer, which asks the person to confirm
/// (@hostapi.install_package); what comes of it when it is not installed comes on @hostapi.system_channel. Under a Tester:
/// kept (Tester::installs); the test posts what the system says (Tester::post).
pub fn install_package(name : String, data : Bytes) -> Unit {
  match fake.val {
    Some(f) => {
      ignore(data)
      f.installs.push(name)
    }
    None => @hostapi.install_package(name, data)
  }
}

///|
/// The app over another app (@hostapi.system_channel `over`) done (@hostapi.over_done): back to the app it was over, or on
/// into the app's own window (`open_app`). Under a Tester: kept (Tester::overs_done).
pub fn over_done(open_app~ : Bool) -> Unit {
  match fake.val {
    Some(f) => f.overs_done.push(open_app)
    None => @hostapi.over_done(open_app~)
  }
}

///|
/// What the notice says that holds the app up while it listens for a browser coming back (@hostapi.hold_words), said
/// before the browser opens. Under a Tester: kept (Tester::hold_words).
pub fn hold_words(channel~ : String, title~ : String, body~ : String) -> Unit {
  match fake.val {
    Some(f) => f.hold_words = Some((channel, title, body))
    None => @hostapi.hold_words(channel~, title~, body~)
  }
}

///|
/// A page shown in a browser's tab over the app (Android's Custom Tab: a login's page), outside a frame too; elsewhere
/// as open_url. False when nothing took it.
pub fn open_tab(url : String) -> Bool {
  h_open_tab(url)
}

///|
/// Puts `s` on the system's clipboard.
pub fn Ctx::copy_text(self : Ctx, s : String) -> Unit {
  ignore(self)
  h_clipboard_set(s)
}

///|
/// The desktop's window made to fill the screen, or back as it was (@hostapi.set_full_screen).
pub fn Ctx::set_full_screen(self : Ctx, on : Bool) -> Unit {
  ignore(self)
  h_set_full_screen(on)
}

///|
/// Puts the picture `data` (an image file's bytes) on the system's clipboard, as a picture other apps paste.
pub fn Ctx::copy_image(self : Ctx, data : Bytes) -> Unit {
  ignore(self)
  h_clipboard_image(data)
}

///|
/// Puts a secret on the system's clipboard: marked sensitive (Android masks its preview), taken off `clear_ms` later
/// unless something else was copied meanwhile (the host's own timer: nothing the app waits on).
pub fn Ctx::copy_secret(self : Ctx, s : String, clear_ms~ : Double) -> Unit {
  ignore(self)
  h_clipboard_secret(s, clear_ms)
}

///|
/// A frame again `ms` from now (for what changes then: words that say
/// "copied" for a while), without frames in between. `later`: what is shown
/// does not wait for it (Tester::assert_idle does not count it: words going
/// back after a while, a refresh); by default it does (a press held long
/// enough, a menu opening once the pointer rests).
#callsite(autofill(loc))
pub fn Ctx::wake_in(self : Ctx, ms : Double, later? : Bool = false, loc~ : SourceLoc) -> Unit {
  if !later && self.wake_by is None {
    self.wake_by = Some(loc)
  }
  self.wake_at_time(self.now + dmax(ms, 1.0), later~)
}
