// The per-window context: views build a fresh tree into it every frame,
// widget state persists in maps keyed by widget id, and input arrives from
// the host between frames.

///|
struct ListState {
  mut anchor : Int
  mut anchor_off : Double
  heights : Array[Double]
  /// how many times a row's height came out other than it was had as it was laid out (ListState::set_height), and the
  /// same as a signal: what its build drew from what it had (its bar, where its rows are) is built again
  mut learned : Int
  heights_learned : @signals.Signal[Int]
  /// how many times the hand moved it between frames (a finger dragging it, letting it go or catching it, a wheel):
  /// what lays it out reads it (Ctx::place_list), laid out again as it moves (ListState::hand_moved)
  hand_said : @signals.Signal[Int]
  /// whether it moved (a finger on it, flung, gliding, springing back) as it was last laid out, as a signal: what is built
  /// from it (Ctx::list_moving) is built again as that changes
  moving_said : @signals.Signal[Bool]
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
  // the bones its rows are built in, as the list was (Ctx::bones: 0 none)
  mut bones : Int64
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
  // how far it was above its end at the last layout, and how far the glide meant it to be after its last step (its
  // end moved meanwhile, a row come or grown under it, or a row it follows nearer: it sets out again from there)
  mut glide : Bool
  mut glide_t0 : Double
  mut glide_l0 : Double
  mut glide_rest : Double
  mut glide_left : Double
  mut glide_meant : Double
  // a row followed from its top (Ctx::list_follow_from: still.fail's newest message, kept in view from its top as
  // Follow.kt's anchor), `follow_margin` under the view's top; -1 none. The reader's scroll lets it go
  mut follow_item : Int
  mut follow_margin : Double
  // the frame it was last built in (one not built is shown by nothing: at rest), and the frame its own motions were
  // last stepped to (Ctx::list_step)
  mut built : Int
  mut stepped : Int
  /// whether what built it last may have built its rows otherwise (the frame built anew, or the part it is in built
  /// for what it read: kept_nodes.mbt): its rows built again, none kept
  mut fresh : Bool
  /// whether its rows show only what they read (Ctx::list's `rows_read`): kept as what builds it is built again,
  /// built again only where what they read changed
  mut rows_read : Bool
  // gliding to its end where it showed as the glide set out: its scroll bar shows meanwhile (not where it is put)
  mut glide_shows : Bool
  // its scroll bar (scroll_bar.mbt)
  bar : Bar
  // the frame it was last laid out in; where it stood as that frame's first layout of it began and where that frame's
  // last left it (the row it is anchored to, how far into it, what was scrolled not laid yet, whether at its end,
  // whether gliding to it): laid out again in that frame, it is laid from where it began, unless something moved it
  // since (Ctx::place_list); its glide with it, as it was then (`glide_began`: set out or not, its way)
  mut laid : Int
  // how far its last layout put its rows down to hold its foot at the view's, for what they lost (a row gone, one
  // shorter), not for what the hand scrolled past it: what is in view moved so by its change, not scrolled
  mut pinned_by : Double
  mut began : (Int, Double, Double, Bool, Bool)
  mut left : (Int, Double, Double, Bool, Bool)
  mut glide_began : (Double, Double, Double, Double, Double)
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
  // a wheel's notches eased in (Ctx::ease_list): what they come to all told (0 none), how fast it set out (px a ms),
  // from when, how much of it has come by the last frame, and what it is said to move by (Ctx::moving)
  mut ease : Double
  mut ease_v : Double
  mut ease_t0 : Double
  mut ease_done : Double
  ease_mover : Mover
  // words picked with the pointer held past its shown edge (desktop.mbt's select_edge): how fast it scrolls toward
  // the pointer (px a ms; 0 none) and until when it has (Ctx::step_edge)
  mut edge_v : Double
  mut edge_t : Double
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
  /// what changed its rows' heights (Ctx::row_size): what each row built said last, by the row's place, and each
  /// row's way from the height it had to the one it is laid out at, by the row's key (list_size.mbt)
  mut causes : RowCauses?
  sizes : Map[String, RowSizing]
  /// where the last way its rows were laid out on ends: what moves till then, laid out again each frame
  mut sizes_end : Double
  /// when the app last put it elsewhere at once (scrolled to a row, to its end): no row's motion (rows_steady.mbt)
  mut put_at : Double
  /// how tall each row was last laid out, by its key (list_size.mbt)
  shown_h : Map[String, Double]
  sizes_mover : Mover
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
  /// first (or a double click's, the paragraph a triple click's), which sliding on widens from
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
  /// the caret, where one line wraps into the next at it, shows at the end of the line before (a move to a line's end
  /// or the pointer past it put it there), not at the next one's start: while the caret is at this offset; -1 none
  mut upstream : Int
  /// the keyboard's trackpad (iOS's floating cursor: a long press on the space bar) moving the caret: where in the
  /// window the host said it began, and where the caret showed then in the field's words (from their top left, its
  /// line's middle); none while it is not
  mut floating : (Double, Double, Double, Double)?
  /// how far its words are scrolled up (taller than the field: scrolled by the wheel, a finger or its bar, as a box kept
  /// to a height is, sideways.mbt; the caret's line brought into view as the caret or the words change), and the caret, the
  /// anchor and how long the words were when it was last brought there
  mut scroll : Double
  /// A one-line field keeps its caret visible by moving its words sideways.
  mut scroll_x : Double
  mut followed : (Int, Int, Int)
  /// what was put in at once that was `limit` characters or more, not put in (a long paste the app takes instead)
  mut pasted : String?
  mut limit : Int
  /// Enter sends (the words go to `submitted`, none too, and stay in it); else it is a new line
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
  /// the person's edits kept to undo, each the field as it was before it (its words, anchor and caret), the last last;
  /// those undone, to do again; and the field as the last typing left it, which typing from there goes on in (none:
  /// something else was done since) (editor_undo.mbt)
  undos : Array[(String, Int, Int)]
  redos : Array[(String, Int, Int)]
  mut typed : (String, Int, Int)?
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
  /// the window's size this frame (width, height: the box being built's, Ctx::sized)
  mut window_w : Double
  mut window_h : Double
  mut scale : Double
  /// whether the host sets things on whole device pixels (whole_px_layout), as the frame began
  mut whole_px : Bool
  /// the frames' clock as the frame began (ms), read as it is, not followed: what reads it so reads a moment (a
  /// stamp, a wake's time); what shows it reads it followed (Ctx::now, frame_watch.mbt)
  mut clock : Double
  mut dt : Double
  mut last_now : Double
  mut frame_no : Int
  /// the system's size of words this frame (font_scale): every word's size and line times it, as Compose's sp
  mut font_scale : Double
  /// how much smaller words are drawn where they are now (Ctx::words_smaller: 1 none), times the system's size
  mut words_k : Double
  /// the build's number (frame_body's passes, over every frame, counted over the program: app.mbt builds_made): what is
  /// said of a build, said again by the next (motion's keyed nodes, by node: another pass's nodes are other nodes)
  mut build_no : Int
  /// how many sideways boxes' content is being built now (Ctx::sideways): what is made in it is marked in_sideways
  mut sideways_depth : Int
  /// the colour what is built now is drawn in as its bones (Ctx::bones), 0 none: what is made is marked so
  mut bones : Int64
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
  /// a stack's page in the hand this frame (Ctx::nav: swiped back, a finger's or the system's gesture), between where it
  /// rests and where it goes: what is drawn on it stands anywhere, as in a motion (Tester::hold_corners)
  mut page_in_hand : Bool
  // hit targets of the last frame, in paint order, and those being collected
  mut hit_ids : Array[Int]
  mut hit_rects : Array[Double]
  mut next_hit_ids : Array[Int]
  mut next_hit_rects : Array[Double]
  // what cut each hit target where it was drawn, 12 numbers each (scene.mbt clip_stack): a press in a corner its
  // rounded clip cut away misses it
  mut hit_clips : Array[Double]
  mut next_hit_clips : Array[Double]
  // what each hit target holds as it was drawn: one past the last target drawn in it (its own index and one, holding
  // none), for what holds the one under the pointer to be pointed at too (Ctx::hovered)
  mut hit_ends : Array[Int]
  mut next_hit_ends : Array[Int]
  // what each hit target's node was marked with as it was built (Node's `marks`): what the pointer's shape over it is
  // and what a press on it does besides (hit_marks)
  mut hit_marks : Array[Int]
  mut next_hit_marks : Array[Int]
  // the nodes this build made with each id, the last (Ctx::mark_id), and what was said of an id before its node was
  // made, to be marked on it as it is
  built_ids : Map[Int, Int]
  marks_ahead : Map[Int, Int]
  /// what was said to take the focus by its id before its node was made (Ctx::focusable), to be marked on it as it is
  focus_ahead : Map[Int, Focusable]
  // the hit targets of the last frame (and of this one, collected) that are pointed at and never pressed (Ctx::box's
  // `points`): a press, or a finger reaching round it, goes past them to what holds them
  mut points : Map[Int, Bool]
  // the hit targets of the last frame (and of this one, collected) the pointer goes through (Ctx::passes): never on
  // top for a pointer, a press or a finger reaching round it, still where they were drawn (Ctx::rect_of)
  mut passes : Map[Int, Bool]
  mut next_passes : Map[Int, Bool]
  // how many boxes the pointer goes through hold what is painted now
  mut passing : Int
  mut next_points : Map[Int, Bool]
  /// of this frame's, the places of their targets among next_hit_ids, in order (said.mbt's HitsSaid)
  next_point_hits : Array[Int]
  mut scroll_ids : Array[Int]
  mut scroll_rects : Array[Double]
  mut next_scroll_ids : Array[Int]
  mut next_scroll_rects : Array[Double]
  /// the scroll bars the last frame drew, and those being drawn (scroll_bar.mbt): where each runs, for the pointer;
  /// boxes scrolled as one seen in the rows being drawn (their id, x and width), drawn along their list; what floats
  /// over what scrolls, built this frame (Ctx::floats_over); the bar the pointer is along the edge of, and the one
  /// whose thumb it holds (0 none)
  mut bars : Array[BarAt]
  mut next_bars : Array[BarAt]
  across_seen : Array[(Int, Double, Double)]
  floating : Array[Int]
  mut bar_near : Int
  mut bar_drag : Int
  // pointer
  mut px : Double
  mut py : Double
  mut down : Bool
  mut hover : Int
  /// what holds the one under the pointer (`hover`), as the last frame drew them, outermost first (Ctx::hovered)
  hover_in : Array[Int]
  /// what the press went down on as the last frame drew it (the hit target) and what holds that one, outermost first
  /// (Ctx::press_within): not what only lies under it, a page under a layer over it
  press_on : Array[Int]
  mut active : Int
  mut focus : Int
  clicked : Array[Int]
  /// what was clicked twice since the last frame, the second within double_click_ms of the first and where it was
  /// (Ctx::double_clicked); the last click (its id, when, where), for the next to be the second of two
  double_clicked : Array[Int]
  mut last_click : (Int, Double, Double, Double)
  /// where the pointer let go of the last click since the last frame (none: a key's, a reader's Activate), for where in
  /// what was clicked it was (Ctx::clicked_on)
  mut click_at : (Double, Double)?
  /// how many presses in a row the last one was (NSEvent's clickCount: 2 a double click's second), and how many, when
  /// and where, for the next to count on from
  mut clicks : Int
  mut press_run : (Int, Double, Double, Double)
  mut drag_scroll : Int
  /// what scrolls or is dragged under the press, innermost first (claim.mbt): until one claims it (`claimed`), the
  /// press is none of theirs; `drag_scroll` is the innermost meanwhile
  mut press_chain : Array[Int]
  mut claimed : Bool
  mut dragging : Bool
  mut press_x : Double
  /// when the press under way went down (ms), and the press a link's hold was last told of
  mut press_at : Double
  /// whether the press under way has gone past the slop of where it went down, at any of its moves (then it holds
  /// nothing long, Android's: a finger that has swiped is no long press, even held still after it)
  mut press_strayed : Bool
  /// Android's: the press went down in what scrolls, so it shows as pressed only once it has stayed tap_indication_ms
  /// (Compose's clickable in a scrollable container: a finger that goes on to scroll presses nothing on the way)
  mut press_late : Bool
  /// when the pointer's latest event (down, moved, up) came, its own time (Ctx::pointer_at)
  mut pointer_t : Double
  mut held_told : Double
  /// what a press told held long (Ctx::long_press) was on, and in which build (frame_body's pass: one built again sees
  /// it no more, as it sees no click)
  mut held_on : Int
  mut held_build : Int
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
  /// what the host was last told of the floating text menu (text_menu), and of what the menu bar's editing items can
  /// do (edit_can; -1 nothing yet)
  mut menu_sig : String
  mut edit_can_told : Int
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
  /// words read as the view built only for their shape (Ctx::words_shape_of): read back as their lines change, not as
  /// they move
  words_shape_reads : Map[String, Bool]
  /// the boxes whose rows left them out as last laid out (Ctx::box `drop`), by id, and those the view asked about as
  /// it built (Ctx::left_out: what it was told)
  left_ids : Map[Int, Bool]
  left_reads : Map[Int, (Bool, SourceLoc)]
  laid_watch : Map[Int, Int]
  laid_rects : Map[Int, (Double, Double, Double, Double)]
  /// the boxes whose parts shown across are asked (Ctx::shown_across): when last, and the name of the boxes whose parts
  /// are left out; what the last layout showed across in each
  shown_watch : Map[Int, (Int, String)]
  shown_spans : Map[Int, (Double, Double)]
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
  // moving the page). Its steps: kind, x, width, time, the system's progress
  // (-1 none: mbui's own edge)
  mut back : ((Int, Double, Double, Double, Double) -> Unit)?
  mut back_node : Int
  mut back_edge : Double
  mut back_next : ((Int, Double, Double, Double, Double) -> Unit)?
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
  // the boxes of the frame whose corner is `Inner` (style.mbt): worked out once laid out (corners.mbt), and those
  // that could not be (Tester::corner_faults says them); of them, those `InnerOr`, their own corner where they lie in
  // no container's: found from the nodes once laid out (Node's `corner_by`, corners_found)
  inners : Array[Int]
  inners_or : Array[Int]
  // what move_state moves (move_state.mbt): the moves going on; what each box named to be moved was shown as, this
  // frame (its build so far) and the last; how many boxes of each name this build has built
  move_runs : Array[MoveRun]
  mut shown_now : Map[String, MoveShown]
  mut shown_last : Map[String, MoveShown]
  move_seen : Map[String, Int]
  // the boxes of the frame whose corner is `Around`: worked out from what lies in their corner (corners.mbt), found as
  // the inners are
  arounds : Array[Int]
  inner_faults : Array[String]
  // the corner ladder of the theme the view was built under (Theme::corner_ladder: the frame's, or one put in force
  // over it with with_theme that says one), what corner_faults holds corners to
  mut corner_ladder : Array[Double]
  // what the corner rule may make of what lies in a container's corner (Theme::corner_fit), and how round the system
  // draws the window's corners this frame (window_corner: the outermost container, corners.mbt)
  mut corner_fit : CornerFit?
  // the ids whose look asked this frame whether the hand is on them (Ctx::lit) or were drawn selected: what lights
  // up, and how far apart such things stand (Theme::lit_apart): the spacing rules' (gaps.mbt)
  lit_asked : Set[Int]
  // the ids whose choice the hand moves this frame (Ctx::hand_on: the one chosen follows the pointer), so chosen is not
  // kept lit while the hand is on another (gaps.mbt)
  hand_chooses : Set[Int]
  // where the pointer was as the last frame began, and whether it has moved since (Ctx::hand_on: a choice follows the
  // pointer as it moves, not while it rests)
  mut hand_was : (Double, Double)
  mut hand_moved : Bool
  mut lit_apart : Double
  // how far in from the sides of what holds it a row that lights up stands (Theme::lit_reach): gaps.mbt's rule 7
  mut lit_reach : Double
  // what is shown only while lit (Ctx::lit_shown) shown everywhere at once: a test's (Tester::lit_all_faults)
  mut lit_all : Bool
  // every id lit by the hand at once (Ctx::lit, and Ctx::hovered where the pointing is a mouse's): a test's, to hold
  // that the hand changes looks alone (Tester::hand_moves)
  mut lit_every : Bool
  /// whether something reads the widgets out this frame (a screen reader, any service of the system's accessibility:
  /// @hostapi.a11y_on), asked once as the frame begins
  mut reads_out : Bool
  mut window_corner : Double
  /// each of the window's corners as the system draws them (top left, then round it), window_corner the roundest
  window_corners : FixedArray[Double]
  mut direction : Direction
  // what the widgets of the frame say they are (semantics.mbt: found from the nodes, sems_found), and how deep in a
  // part hidden from it the view builds; the actions asked of them (by the host's accessibility, a test) for the next
  // frame, and this frame's
  sems : Array[Sem]
  mut sem_hide : Int
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
  /// the shots being taken, by their keys' (shot.mbt)
  shots : Map[Int, Shot]
  /// while a shot taken at its own pixels a point is built, those (Ctx::drawn_scale); else 0
  mut shot_scale : Double
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
    window_w: 800.0,
    window_h: 600.0,
    scale: 2.0,
    whole_px: false,
    clock: 0.0,
    dt: 16.0,
    last_now: -1.0,
    frame_no: 0,
    font_scale: 1.0,
    words_k: 1.0,
    build_no: 0,
    sideways_depth: 0,
    bones: 0L,
    epoch: 0,
    wants_frame: false,
    wake_at: -1.0,
    wake_waited: -1.0,
    frame_rest: false,
    frame_by: None,
    wake_by: None,
    page_in_hand: false,
    hit_ids: [],
    hit_rects: [],
    next_hit_ids: [],
    next_hit_rects: [],
    hit_clips: [],
    next_hit_clips: [],
    hit_ends: [],
    next_hit_ends: [],
    hit_marks: [],
    next_hit_marks: [],
    built_ids: {},
    marks_ahead: {},
    focus_ahead: {},
    points: {},
    passes: {},
    next_passes: {},
    passing: 0,
    next_points: {},
    next_point_hits: [],
    scroll_ids: [],
    scroll_rects: [],
    next_scroll_ids: [],
    next_scroll_rects: [],
    bars: [],
    next_bars: [],
    across_seen: [],
    floating: [],
    bar_near: 0,
    bar_drag: 0,
    px: -1.0,
    py: -1.0,
    down: false,
    hover: 0,
    hover_in: [],
    press_on: [],
    active: 0,
    focus: 0,
    clicked: [],
    double_clicked: [],
    last_click: (0, 0.0, 0.0, 0.0),
    click_at: None,
    clicks: 0,
    press_run: (0, -1.0e9, 0.0, 0.0),
    drag_scroll: 0,
    press_chain: [],
    claimed: true,
    dragging: false,
    press_x: 0.0,
    press_at: -1.0,
    press_strayed: false,
    press_late: false,
    pointer_t: 0.0,
    held_told: -1.0,
    held_on: 0,
    held_build: -1,
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
    edit_can_told: -1,
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
    words_shape_reads: Map::new(),
    left_ids: Map::new(),
    left_reads: Map::new(),
    laid_watch: Map::new(),
    laid_rects: Map::new(),
    shown_watch: Map::new(),
    shown_spans: Map::new(),
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
    corner_ladder: [],
    corner_fit: None,
    lit_asked: Set::new(),
    hand_chooses: Set::new(),
    hand_was: (-1.0, -1.0),
    hand_moved: false,
    lit_apart: 0.0,
    lit_reach: 0.0,
    lit_all: false,
    lit_every: false,
    reads_out: false,
    window_corner: 0.0,
    window_corners: FixedArray::make(4, 0.0),
    inner_faults: [],
    direction: Ltr,
    sems: [],
    sem_hide: 0,
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
    shots: Map::new(),
    shot_scale: 0.0,
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
/// Whether box `i` stands on a ground of its own (a button's, a card's: a colour more solid than not, glass, an edge),
/// not on what holds it (a row in a list or a card, lit only as it is pressed or pointed at).
pub fn Ctx::own_ground(self : Ctx, i : Int) -> Bool {
  if i < 0 || i >= self.count {
    return false
  }
  let n = self.nodes[i]
  (n.bg & 0xFFL) >= 0x80L || n.glass is Some(_) || n.border_w > 0.0
}

///|
/// The box whose body is being built now (what a part called in a box's body is in: a press's ripple's box); -1 none.
pub fn Ctx::building(self : Ctx) -> Int {
  self.cur
}

///|
/// A widget id from a key, unique within the current scope.
pub fn Ctx::id(self : Ctx, key : String) -> Int {
  mix(self.id_seed, key_hash(key))
}

///|
/// `key`'s stable_hash as an id's: the same string as one asked before (a literal key, the same each frame: a motion's
/// name, a part's) found by itself in a small table and not hashed again; another hashed and put there.
fn key_hash(key : String) -> Int {
  let n = key.length()
  if n == 0 {
    return stable_hash(key).to_int()
  }
  let at = (n * 31 + key.code_unit_at(0).to_int() * 7 + key.code_unit_at(n - 1).to_int()) & (key_hashes_n - 1)
  if physical_equal(key_hashes_of[at], key) {
    return key_hashes[at]
  }
  let h = stable_hash(key).to_int()
  key_hashes_of[at] = key
  key_hashes[at] = h
  h
}

///|
/// key_hash's table: its size, the strings in it and their hashes.
let key_hashes_n : Int = 512

///|
// kept across runs: what a pure function gave, found again only for the very string it was given
let key_hashes_of : FixedArray[String] = FixedArray::make(512, "")

///|
// kept across runs: what a pure function gave, found again only for the very string it was given
let key_hashes : FixedArray[Int] = FixedArray::make(512, 0)

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
fn Ctx::alloc_part(self : Ctx, kind : Int, look : Bool, words : Bool, key? : Int = 0) -> Int {
  let i = self.count
  if i < self.nodes.length() {
    self.node_known(i, kind, key)
    let n = self.nodes[i]
    n.reset_rest()
    if look {
      n.reset_look()
    }
    if words {
      n.reset_words()
    }
  } else {
    self.nodes.push(
      match spare_nodes.pop() {
        Some(sp) => sp
        None => Node::new()
      },
    )
    self.node_known(i, kind, key)
    let n = self.nodes[i]
    n.reset_rest()
    n.reset_look()
    n.reset_words()
  }
  self.count = i + 1
  let n = self.nodes[i]
  n.kind = kind
  n.in_sideways = self.sideways_depth > 0
  n.sem_hid = self.sem_hide > 0
  n.bones = self.bones
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
/// The key of what holds a list's item `k` (a row, a pager's page), who it is by its item (Ctx::node_known).
fn item_key(k : Int) -> Int {
  mix(0x6974656d, k + 1)
}

///|
/// Who each node of the frame's is, for a pass of a build to find it by (Ctx::node_known): those the last pass made,
/// and those made before and not since (a page covered a while, its nodes kept at the end of the frame's), until
/// their node is someone else's.
// kept across runs: let go of as a run begins (nodes_forget)
let known_nodes : IdentMap = IdentMap::new()

///|
/// How many nodes past twice those a pass made the frame's may hold, kept for one to come (Ctx::node_known).
let known_room : Int = 256

///|
/// How many nodes the last pass of a build made.
// kept across runs: only counts
let known_made : Ref[Int] = { val: 0 }

///|
/// The passes of a build so far, for a node to say which made it (Node's `made_pass`).
// kept across runs: only counts
let known_pass : Ref[Int] = { val: 0 }

///|
/// As a pass of a build begins, before the frame's nodes are made again: who each node the last one made is (its
/// `ident`), and where it is, for each made now to be put where that one of before is (Ctx::node_known); those made
/// before it and not since still known where they are.
fn Ctx::nodes_known(self : Ctx) -> Unit {
  known_pass.val = known_pass.val + 1
  known_made.val = self.count
  for k in 0..<self.count {
    let n = self.nodes[k]
    n.slot = k
    known_nodes.set(n.ident, n)
  }
}

///|
/// Node `i` about to be made as a `kind` under the one being built, with `key` (its id; 0: none): who it is is what
/// holds it, the scope it is built in (Ctx::scope: a stack's page's, a row's) and its key there, or how many before it
/// there have none, not its place in the frame's order (as
/// Compose's groups by their call, Flutter's elements by their type and key). The node that was it last pass is put in
/// slot `i`, with what is kept of it (its flex node, its layout, its words shaped): a node more or less built before
/// it elsewhere (a bar's button as it shows) leaves it as it was, laid out as before. One taken already, or not among
/// the frame's nodes still to be made (a list's row's, held by the row): `i` as it is.
fn Ctx::node_known(self : Ctx, i : Int, kind : Int, key : Int) -> Unit {
  let ident = if self.cur >= 0 {
    let p = self.nodes[self.cur]
    // (the first built in a scope of its own, under what was not: who it is is that scope's, wherever what holds it is
    // (a stack's page under its slot, whichever slot that is now))
    let at = if self.id_seed != p.seed {
      mix(self.id_seed, 0x73636f70)
    } else {
      p.ident
    }
    if key != 0 {
      mix(mix(at, kind + 1), key)
    } else {
      p.kids = p.kids + 1
      mix(mix(at, -kind - 1), p.kids)
    }
  } else {
    mix(mix(kind + 1, 1), self.id_seed)
  }
  let found = match known_nodes.get(ident) {
    Some(o) => {
      let j = o.slot
      if j > i &&
        j < self.nodes.length() &&
        physical_equal(self.nodes[j], o) &&
        o.made_pass != known_pass.val {
        let was = self.nodes[i]
        self.nodes[j] = was
        was.slot = j
        self.nodes[i] = o
        true
      } else {
        physical_equal(self.nodes[i], o)
      }
    }
    None => false
  }
  // (none was it: the node in slot `i` is another's of before, still to be made, a node more built before it: kept
  // for that one at the end of the frame's, a spare in its place; so far as the frame's nodes are not twice those
  // made last, what was kept so for one that did not come left there)
  if !found && self.nodes.length() < 2 * known_made.val + known_room {
    let was = self.nodes[i]
    match known_nodes.get(was.ident) {
      Some(o) if physical_equal(o, was) && was.made_pass != known_pass.val => {
        was.slot = self.nodes.length()
        self.nodes.push(was)
        self.nodes[i] = match spare_nodes.pop() {
          Some(sp) => sp
          None => Node::new()
        }
      }
      _ => ()
    }
  }
  let n = self.nodes[i]
  // (who it was of before let go of, where it is someone else now; who it is now known by it)
  if n.ident != ident {
    match known_nodes.get(n.ident) {
      Some(o) if physical_equal(o, n) => known_nodes.remove(n.ident)
      _ => ()
    }
  }
  known_nodes.set(ident, n)
  n.ident = ident
  n.keyless = key == 0 && self.cur >= 0
  n.seed = self.id_seed
  n.slot = i
  n.kids = 0
  n.made_pass = known_pass.val
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
/// `gone_empty`: built holding nothing, it takes no room, its padding and margins none (CSS's :empty { display: none }):
/// the room over a part that has nothing in it this time (a dialog's body) not left standing empty.
/// `label`: what it is called where it shows no words (an icon's button, as Compose's contentDescription), found by
/// them whole as words are (a drive's `=WORDS`, Tester::locate). `name`: what it stands for in another app's tree (the
/// web page's class it is ported from, `shellCss.dock`), read only by a tool comparing the two (Tester::boxes).
///
/// `style` (style.mbt) says how it looks, its state blocks picked by its own state: pressed, hovered, focused by `id`
/// (as Ctx::pressed, hovered, focus_shown read them), `selected` and `disabled` as said, dark and narrow by the theme
/// (Ctx::set_theme). What is said here besides (`pad=`, `bg=`…) wins over the style's same property; what neither
/// says is as without either (no padding, no ground). A padding below 0 is not said (Ctx::row passes -1). With an
/// `id` it takes the presses on its room (the innermost box with an id under the finger does); `taps` false: the id
/// only names it (to measure it, Ctx::laid_size; to move it by a look), what holds it taking the presses there; and
/// with `points`, it is pointed at all the same (Ctx::hovered, Ctx::rect_of: what says something over it while the
/// pointer rests there, a tip, a card), its presses still what holds it's, the pointer's shape too where it says none.
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
  gone_empty? : Bool = false,
  label? : String = "",
  name? : String = "",
  id? : Int = 0,
  taps? : Bool = true,
  points? : Bool = false,
  body : () -> Unit,
) -> Int {
  let i = self.alloc_part(kind_box, false, false, key=id)
  let n = self.nodes[i]
  if selected && id != 0 {
    self.lit_asked.add(id)
    built_used(fn() { g().lit_asked.add(id) })
  }
  // the style's look in this node's states, the tokens looked up in the theme in force
  let st : Patch = match style {
    None => no_patch
    Some(s) =>
      s.resolve(
        self.narrow,
        self.theme.dark,
        selected,
        id != 0 && self.lit(id),
        // (asked only where the style looks otherwise for it: what it is not built by is not read, nor looked up)
        id != 0 && s.focused is Some(_) && self.focus_shown(id),
        id != 0 && s.pressed is Some(_) && self.pressed(id),
        disabled,
      )
  }
  // (a ground it has in any of its states, whichever it is in now: the corner rule holds it as one with a ground)
  n.state_ground = match style {
    Some(s) =>
      s.hovered is Some({ bg: Some(_), .. }) ||
      s.pressed is Some({ bg: Some(_), .. }) ||
      s.selected is Some({ bg: Some(_), .. }) ||
      s.focused is Some({ bg: Some(_), .. })
    None => false
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
  // (each side picked from what says it, in turn, no option made on the way: a box's lengths are picked for every box
  // on every frame)
  n.pad_l = pad_side(pl, padx, pad, st.pl, st.px, st.p)
  n.pad_r = pad_side(pr, padx, pad, st.pr, st.px, st.p)
  // right to left, the start (left said) is the right
  if n.rtl {
    let l = n.pad_l
    n.pad_l = n.pad_r
    n.pad_r = l
  }
  n.pad_t = pad_side(pt, pady, pad, st.pt, st.py, st.p)
  n.pad_b = pad_side(pb, pady, pad, st.pb, st.py, st.p)
  // margins as the padding: one side said over both, both over all four, said here over the style's (below 0 too)
  n.mar_l = margin_side(ml, mx, m, st.ml, st.mx, st.m)
  n.mar_r = margin_side(mr, mx, m, st.mr, st.mx, st.m)
  if n.rtl {
    let l = n.mar_l
    n.mar_l = n.mar_r
    n.mar_r = l
  }
  n.mar_t = margin_side(mt, my, m, st.mt, st.my, st.m)
  n.mar_b = margin_side(mb, my, m, st.mb, st.my, st.m)
  n.at_l = left.unwrap_or(0.0 / 0.0)
  n.at_t = top.unwrap_or(0.0 / 0.0)
  n.at_r = right.unwrap_or(0.0 / 0.0)
  n.at_b = bottom.unwrap_or(0.0 / 0.0)
  n.min_w = bound_of(min_w, st.min_w, 0.0)
  n.min_w_within = min_w is None && st.min_w is Some(Within(_))
  n.max_w = bound_of(max_w, st.max_w, 1.0e9)
  n.min_h = bound_of(min_h, st.min_h, 0.0)
  n.max_h = bound_of(max_h, st.max_h, 1.0e9)
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
  n.shadow_y = match shadow_y {
    Some(y) => y
    None => sh_y.unwrap_or(-1.0)
  }
  n.gap = match gap {
    Some(g) => g
    None =>
      match st.gap {
        Some(s) => s.px()
        None => 0.0
      }
  }
  n.align = match align {
    Some(a) => a
    None => st.align.unwrap_or(AStretch)
  }
  n.justify = match justify {
    Some(j) => j
    None => st.justify.unwrap_or(JStart)
  }
  n.bg = match bg {
    Some(b) => b
    None =>
      match st.bg {
        Some(c) => th.color(c)
        None => 0L
      }
  }
  n.radius = match radius {
    Some(r) => r
    None =>
      match st.radius {
        Some(r) => th.corner(r)
        None => 0.0
      }
  }
  // each corner its own (`Corners`); else all four `radius` (the node's look is not reset before a box sets it: none
  // of a box's before it in this place kept)
  n.radii = None
  n.links = None
  n.corners_worked = false
  if radius is None {
    match st.radius {
      Some(r) => {
        match r.each() {
          Some(each) => n.set_radii(each)
          None => ()
        }
        // (where they come from, for the corner rule to hold it to: corner_faults)
        n.links = r.links()
      }
      None => ()
    }
  }
  // a corner said `Inner` (and not said here): worked out once laid out (corners.mbt); `InnerOr`, its own till then
  // `Around`: from what lies in its corner, once laid out
  n.corner_by = match (radius, st.radius) {
    (None, Some(Inner)) => corner_inner
    (None, Some(InnerOr(_))) => corner_inner_or
    (None, Some(Around)) => corner_around
    _ => 0
  }
  n.border_w = match border {
    Some(b) => b
    None =>
      match st.border {
        Some(b) => b.px()
        None => 0.0
      }
  }
  n.border_c = match border_color {
    Some(c) => c
    None =>
      match st.border_color {
        Some(c) => th.color(c)
        None => 0L
      }
  }
  n.dashed = st.dashed.unwrap_or(false)
  n.shadow = match shadow {
    Some(s) => s
    None => sh_blur.unwrap_or(0.0)
  }
  n.clip = match clip {
    Some(c) => c
    None => st.clip.unwrap_or(false)
  }
  n.tx = tx
  n.ty = ty
  // (placed by its own size only when told so this frame, Ctx::place_by_size: a slot a menu was placed in last
  // frame is not where a box built there now goes)
  n.place = None
  n.opacity = match opacity {
    Some(o) => o
    None =>
      match st.opacity {
        Some(o) => o.value()
        None => 1.0
      }
  }
  n.glass = glass
  n.glass_group = glass_group
  n.notch_y = notch_y
  n.notch_r = notch_r
  n.notch_f = notch_fillet
  if id != 0 {
    n.id = id
    self.id_built(i)
    // (`taps` false: an id only to be measured or moved by (laid_size, a look): what is pressed in it is what holds
    // it, not it, which would take every press on its room that nothing in it takes)
    n.hit = taps
    n.points = points && !taps
  }
  // moved by a move_state (move_state.mbt): what it is shown as while the move lasts, where it was to where it is built
  if moves != "" {
    n.moves = moves
    self.move_node(i)
  }
  self.with_parent(i, body)
  // holding nothing, no room of its own
  if gone_empty && n.first < 0 {
    n.pad_l = 0.0
    n.pad_r = 0.0
    n.pad_t = 0.0
    n.pad_b = 0.0
    n.mar_l = 0.0
    n.mar_r = 0.0
    n.mar_t = 0.0
    n.mar_b = 0.0
  }
  i
}

///|
/// A side's padding (Ctx::box): said for it alone, for both of its axis (`both`), for all four (`all`), each only when
/// 0 or more (one below 0 is not said: the -1 Ctx::row and the like pass on); else the style's, in the same order;
/// else none.
fn pad_side(one : Double?, both : Double?, all : Double?, st_one : Space?, st_both : Space?, st_all : Space?) -> Double {
  match one {
    Some(x) if x >= 0.0 => return x
    _ => ()
  }
  match both {
    Some(x) if x >= 0.0 => return x
    _ => ()
  }
  match all {
    Some(x) if x >= 0.0 => return x
    _ => ()
  }
  match st_one {
    Some(v) => return v.px()
    None => ()
  }
  match st_both {
    Some(v) => return v.px()
    None => ()
  }
  match st_all {
    Some(v) => v.px()
    None => 0.0
  }
}

///|
/// A side's margin (Ctx::box), as pad_side picks a padding, below 0 too.
fn margin_side(one : Double?, both : Double?, all : Double?, st_one : Space?, st_both : Space?, st_all : Space?) -> Double {
  match one {
    Some(x) => return x
    None => ()
  }
  match both {
    Some(x) => return x
    None => ()
  }
  match all {
    Some(x) => return x
    None => ()
  }
  match st_one {
    Some(v) => return v.margin_px()
    None => ()
  }
  match st_both {
    Some(v) => return v.margin_px()
    None => ()
  }
  match st_all {
    Some(v) => v.margin_px()
    None => 0.0
  }
}

///|
/// A bound (Ctx::box's min_w and the like): said, else the style's, else `none_is`.
fn bound_of(said : Double?, st : Len?, none_is : Double) -> Double {
  match said {
    Some(x) => x
    None =>
      match st {
        Some(l) => l.bound(none_is)
        None => none_is
      }
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
/// `tracking`: letter spacing in pixels; `max_lines`: wrapped words cut after that many lines, ending in an ellipsis;
/// `tabular`: digits all one width, a number keeping its width as it changes (the theme's `tabular` where unsaid).
/// `trim`: a font taller than the line not padded beyond its own reach where a host sets lines on whole pixels (as
/// Compose sets words in a TextStyle of their own; else as a theme's words: set_line).
/// `keep`: words cut short (`w=Cut`) in a row that may leave a part of it out (Ctx::box `drop`) kept whole till all
/// it may leave has left, cut only then (a way's last folder, its name before the folders over it).
/// Words that do not wrap are one line: their line breaks shown as spaces (CSS's white-space: nowrap), unless
/// `breaks` keeps them, each line as it is (code shown as written, in what scrolls sideways: CSS's pre).
/// `shorter`: other ways to say words on one line where they have less room, each shorter than the one before
/// (搜索全部内容, then 搜索): the longest of them all that fits is shown whole, the shortest cut with an ellipsis only
/// where none does; in a row they need no more than the shortest at least (SwiftUI's ViewThatFits).
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
  tabular? : Bool,
  keep? : Bool = false,
  breaks? : Bool = false,
  shorter? : Array[String] = no_words,
) -> Int {
  let st = self.text_patch(style)
  let (s_size, s_line) = self.text_sizes(st)
  let i = self.alloc_part(kind_text, true, false)
  let n = self.nodes[i]
  // (each picked from what says it, no option or closure made on the way: for every words' node on every frame)
  n.center = match center {
    Some(b) => b
    None => st.center.unwrap_or(false)
  }
  n.wrap = match wrap {
    Some(b) => b
    None => st.wrap.unwrap_or(true)
  }
  n.text = if n.wrap || breaks || !has_nl(s) {
    s
  } else {
    match one_line([s]) {
      Some(t) => t[0]
      None => s
    }
  }
  // (sizes as the original's sp: the system's size of words applied, fontscale.mbt)
  n.font_size = self.sp(
    match size {
      Some(v) => v
      None => s_size.unwrap_or(15.0)
    },
  )
  n.line_h = match line {
    Some(l) => self.sp(l)
    None =>
      match s_line {
        Some(l) => self.sp(l)
        None => self.theme.text_line * n.font_size
      }
  }
  n.line_trim = trim
  n.weight = match weight {
    Some(v) => v
    None => opt_weight(st.weight).unwrap_or(400)
  }
  n.color = match color {
    Some(c) => c
    None =>
      match st.color {
        Some(c) => self.theme.color(c)
        None => self.theme.fg
      }
  }
  n.w = match w {
    Some(v) => v
    None => opt_size(st.w).unwrap_or(Auto)
  }
  n.spacing = match (tracking, st.tracking) {
    (Some(v), _) => self.sp(v)
    (None, Some(t)) => t.px(n.font_size)
    (None, None) => 0.0
  }
  n.max_lines = match max_lines {
    Some(v) => v
    None => st.max_lines.unwrap_or(0)
  }
  n.tabular = match tabular {
    Some(b) => b
    None => st.tabular.unwrap_or(self.theme.tabular)
  }
  n.keep = keep
  n.shorter = shorter
  i
}

///|
/// How wide `s` is on one line in `style` in this frame, as Ctx::text lays it (the system's size of words, its weight,
/// tracking and digits): a column of words of a length known made as wide as the widest of them (a table's labels),
/// never cut. `mono`: in the code face, as a rich span said mono is.
pub fn Ctx::words_across(self : Ctx, s : String, style : TextStyle, mono? : Bool = false) -> Double {
  let st = self.text_patch(Some(style))
  let (s_size, _) = self.text_sizes(st)
  let size = self.sp(s_size.unwrap_or(15.0))
  let weight = opt_weight(st.weight).unwrap_or(400)
  let spacing = match st.tracking {
    Some(t) => t.px(size)
    None => 0.0
  }
  let tabular = st.tabular.unwrap_or(self.theme.tabular)
  let face = (if tabular { @hostapi.style_tabular } else { 0 }) | (if mono { @hostapi.style_mono } else { 0 })
  layout_text(s, size, weight, 1.0e9, false, spacing~, style=face).w
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
/// The size and the line `style` sets words in, in the theme in force, as Ctx::text and Ctx::editor take them (the
/// system's size of words not yet applied): for what is set apart from a text and must be set alike (a field's words
/// as their message will have them). Its line, said by neither its size nor its leading, the theme's share of its size.
pub fn Ctx::style_size(self : Ctx, style : TextStyle) -> (Double, Double) {
  let (size, line) = self.text_sizes(self.text_patch(Some(style)))
  let size = size.unwrap_or(15.0)
  (
    size,
    match line {
      Some(l) if l > 0.0 => l
      _ => self.theme.text_line * size
    },
  )
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
  if id == 0 {
    return false
  }
  // (read so: what reads it is built again as it is clicked twice, hand.mbt)
  hand.double.has(id) |> ignore
  self.double_clicked.contains(id)
}

///|
/// How soon after the first the second of two clicks is (macOS's default: 500 ms), and how near it (4).
pub let double_click_ms : Double = 500.0

///|
pub let double_click_slop : Double = 4.0

///|
/// Whether `id` was clicked since the last frame (pressed and let go on it, not dragged; Enter or Space while it has
/// the focus; the Activate a screen reader asks). Asked, `id` takes presses: the pointer is a hand over it (desktop.mbt
/// show_cursor). What only watches it pressed (a tip that shuts as its trigger is) asks Ctx::watch_press.
pub fn Ctx::clicked(self : Ctx, id : Int) -> Bool {
  self.takes_presses(id)
  self.click_seen(id)
}

///|
/// Whether `id` was clicked since the last frame on `part`, a box in it only pointed at (Ctx::box's `points`: a press
/// on it is `id`'s): where in it the pointer let go, for what a click there does more (a chat's row opens at the message
/// its state line is about). A key's click or a reader's Activate is on none of its parts.
pub fn Ctx::clicked_on(self : Ctx, id : Int, part : Int) -> Bool {
  if !self.clicked(id) {
    return false
  }
  match (self.click_at, self.rect_of(part)) {
    (Some((x, y)), Some((px, py, pw, ph))) => x >= px && x < px + pw && y >= py && y < py + ph
    _ => false
  }
}

///|
/// Whether `id` was clicked since the last frame, asked by nothing that takes the click.
fn Ctx::click_seen(self : Ctx, id : Int) -> Bool {
  // (what a click changes is drawn by the next frame wherever it was seen, as every input's: on_frame; the Activate
  // a screen reader asks of it is one: semantics.mbt)
  // (read so: what reads it is built again as it is clicked, hand.mbt)
  hand.clicked.has(id) |> ignore
  self.clicked.contains(id) || (id != 0 && self.action_asked(id, Activate))
}

///|
/// Whether `id` is pressed or was clicked since the last frame, as what stands beside it sees it (a tip that shuts as
/// its trigger is pressed, an edge's tip that goes): asked so, `id` is not taken to take presses (Ctx::clicked).
pub fn Ctx::watch_press(self : Ctx, id : Int) -> Bool {
  self.pressed(id) || self.click_seen(id)
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
/// Whether a mouse's pointer rests on `id`, or on what is drawn in it (a finger hovers over nothing: Pointing): a
/// tab's ×, a row's buttons pointed at, the tab and the row are still pointed at (the web's `:hover`, which holds for
/// what holds it). For what only a resting pointer is shown; a look that answers the hand on it is Ctx::lit.
pub fn Ctx::hovered(self : Ctx, id : Int) -> Bool {
  // (read so: what reads it is built again as the pointer comes over it or leaves it, hand.mbt)
  let over = hand.over.has(id)
  hand.pointing.get() |> ignore
  // (in a frame, where the frame took the pointer to rest as it began (hand_arrive): what moved under it as the frame
  // was painted is found under it as the frame ends, and lit by the next, built again or not)
  if in_frame.val && id != 0 {
    return over || (self.lit_every && pointing() is Mouse)
  }
  self.hover == id || (id != 0 && (self.hover_in.contains(id) || (self.lit_every && pointing() is Mouse)))
}

///|
/// What is shown only while `id` is lit (Ctx::lit: a row's 归档 and ⋯ under the pointer), built by `body` then; and
/// built whatever is lit where a test asks for everything so shown (Tester::lit_all), so that what shows only under the
/// hand is held to the corner rule as what shows at rest is, without pointing at each in turn.
pub fn Ctx::lit_shown(self : Ctx, id : Int, body : () -> Unit) -> Unit {
  self.hand_shown(self.lit(id), body)
}

///|
/// The same where what lights it is more than one id (a row pointed at in any of its parts, its menu open beside it):
/// `body` built while `lit`, and where a test asks for everything shown only under the hand (Tester::lit_all).
pub fn Ctx::hand_shown(self : Ctx, lit : Bool, body : () -> Unit) -> Unit {
  if self.hand_lit(lit) {
    body()
  }
}

///|
/// Whether what is shown only under the hand, lit by `lit`, is shown in this frame (hand_shown): while it is lit, and
/// where a test asks for all of it (Tester::lit_all). What makes room for it goes by this too, so it is laid out as it
/// is under the hand.
pub fn Ctx::hand_lit(self : Ctx, lit : Bool) -> Bool {
  lit || self.lit_all
}

///|
/// Whether `id` is lit by the hand on it: a mouse's pointer resting on it or on what is in it (Ctx::hovered), a finger
/// pressing it, itself (the web's `:hover` with a fine pointer, `:active` with a coarse one). What a style's `hovered`
/// patch and a widget's hovered look go by.
pub fn Ctx::lit(self : Ctx, id : Int) -> Bool {
  if id != 0 {
    self.lit_asked.add(id)
    built_used(fn() { g().lit_asked.add(id) })
  }
  self.hand_at(id)
}

///|
/// Whether the hand is on `id` as Ctx::lit has it, where what it changes is not `id`'s look but what is chosen (the
/// pointer over a found line choosing it, as the keys do: the one chosen shown so, one at a time). A mouse's pointer
/// chooses as it moves onto or over `id` (the web's mousemove), not while it rests there: the keys move the choice away
/// from under a resting pointer, and what moves under it (the list scrolled to the keys' choice, new lines come) is not
/// chosen by it. Not a look that lights up: the spacing rules hold what asks Ctx::lit (gaps.mbt).
pub fn Ctx::hand_on(self : Ctx, id : Int) -> Bool {
  if id != 0 {
    self.hand_chooses.add(id)
    built_used(fn() { g().hand_chooses.add(id) })
  }
  guard self.hand_at(id) else { return false }
  if self.lit_every || pointing() is Finger {
    return true
  }
  // (read so: built again as the pointer moves over it, Ctx::pointer)
  self.pointer() |> ignore
  self.hand_moved
}

///|
/// Whether the hand is on `id`: a mouse's pointer resting on it or on what is in it, a finger pressing it.
fn Ctx::hand_at(self : Ctx, id : Int) -> Bool {
  if self.lit_every && id != 0 {
    return true
  }
  match pointing() {
    Mouse => self.hovered(id)
    Finger => self.pressed(id)
  }
}

///|
/// The pointer at (x, y), as the last frame drew what is there: the topmost hit target under it, and what holds that
/// one (Ctx::hovered).
fn Ctx::point_at(self : Ctx, x : Double, y : Double) -> Unit {
  let k = hit_at(self.hit_ids, self.hit_rects, self.hit_clips, x, y)
  // (what a press there would be on, where it reaches what is drawn smaller than its room: that one lit, as a click
  // there is its, press_reach)
  let pressed = hit_at(self.hit_ids, self.hit_rects, self.hit_clips, x, y, pressed=true)
  let reached = press_reach(self.hit_ids, self.hit_rects, self.hit_clips, pressed, x, y)
  let k = if reached != pressed { reached } else { k }
  self.hover = if k >= 0 { self.hit_ids[k] } else { 0 }
  self.hover_in.clear()
  self.holders(k, self.hover_in)
}

///|
/// Whether the press (Ctx::press) went down on `id` or on what is in it, as the last frame drew them: what lies over it
/// (a layer over the page, a viewer over the chat) took a press there, not it, though it is under the place.
pub fn Ctx::press_within(self : Ctx, id : Int) -> Bool {
  if id == 0 {
    return false
  }
  // (read so: what reads it is built again as a press goes down on it or is let go, hand.mbt)
  hand.press_on.has(id) |> ignore
  self.press_on.contains(id)
}

///|
/// The press going down at (x, y) on `target`: it and what holds it, as the last frame drew them (Ctx::press_within).
fn Ctx::press_on_at(self : Ctx, target : Int, x : Double, y : Double) -> Unit {
  self.press_on.clear()
  if target == 0 {
    return
  }
  let k = hit_at(self.hit_ids, self.hit_rects, self.hit_clips, x, y)
  // (a finger reaching what is smaller than its tip from round it: what holds that one)
  let k = if k >= 0 && self.hit_ids[k] == target {
    k
  } else {
    let mut j = self.hit_ids.length() - 1
    while j >= 0 && self.hit_ids[j] != target {
      j = j - 1
    }
    j
  }
  self.holders(k, self.press_on)
  self.press_on.push(target)
  // a cover a finger is held through (Ctx::holds_through): what lies under it, and what holds that, too
  if k >= 0 && (hit_marks(target) & mark_holds) != 0 {
    let mut j = k - 1
    while j >= 0 {
      let r = j * 4
      let rects = self.hit_rects
      if self.hit_ids[j] != target &&
        x >= rects[r] &&
        x < rects[r + 2] &&
        y >= rects[r + 1] &&
        y < rects[r + 3] &&
        in_round_clip(self.hit_clips, j, x, y) &&
        !self.holds_hit(j, k) {
        break
      }
      j = j - 1
    }
    if j >= 0 {
      self.holders(j, self.press_on)
      self.press_on.push(self.hit_ids[j])
    }
  }
}

///|
/// Whether the last frame's hit target `j` holds target `k` (`k` drawn in it: Ctx::hit_ends), as Ctx::holders reads.
fn Ctx::holds_hit(self : Ctx, j : Int, k : Int) -> Bool {
  j < k && j < self.hit_ends.length() && self.hit_ends[j] > k
}

///|
/// What holds the last frame's hit target `k` (its index; -1 none) as it was drawn, outermost first, into `into`:
/// the targets it was drawn in (Ctx::hit_ends), itself left out. Not what only lies under it (a page under a layer
/// over it, a list under what floats over it): that holds nothing of it.
fn Ctx::holders(self : Ctx, k : Int, into : Array[Int]) -> Unit {
  if k < 0 {
    return
  }
  let me = self.hit_ids[k]
  for j in 0..<k {
    let id = self.hit_ids[j]
    if j < self.hit_ends.length() && self.hit_ends[j] > k && id != me && !into.contains(id) {
      into.push(id)
    }
  }
}

///|
/// The pointer over nothing (gone from the window, a finger lifted).
fn Ctx::point_nowhere(self : Ctx) -> Unit {
  self.hover = 0
  self.hover_in.clear()
}

///|
pub fn Ctx::pressed(self : Ctx, id : Int) -> Bool {
  // (read so: what reads it is built again as it is pressed or let go, hand.mbt)
  if id != 0 {
    hand.pressed.has(id) |> ignore
  }
  if self.active != id || !self.down {
    return false
  }
  if self.press_late && self.clock < self.press_at + tap_indication_ms {
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
  part_live()
  h_request_frame()
}

///|
/// An event for the next frame's start to take, come in a frame that took its events already (a stream's frame let
/// go as it builds: Stream::let_go): the next frame is owed to it, the host told now, as for a motion set out
/// (owe_start); building this one again would not take it.
fn Ctx::owe_next(self : Ctx) -> Unit {
  self.wants_frame = true
  part_live()
  h_request_frame()
}

///|
#callsite(autofill(loc))
pub fn Ctx::request_frame(self : Ctx, loc~ : SourceLoc) -> Unit {
  self.wants_frame = true
  part_live()
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
  (self.window_w, self.window_h)
}

///|
/// The frames' clock (ms): this frame's time, followed (frame_watch.mbt): what reads it as it is built or drawn is built
/// and drawn again each frame. What only changes at a moment says so (Ctx::wake_in, Ctx::every, a cycle's step) and
/// is not built again till then.
#callsite(autofill(loc))
pub fn Ctx::now(self : Ctx, loc~ : SourceLoc) -> Double {
  clock_read(loc)
  self.clock
}

///|
/// The moment now: the frame's time in a frame (Ctx::now), else the clock's as it stands between frames (an input's
/// handler, a fiber, a test's change): where what is told now starts from. Read as it is, not followed (frame_watch.mbt):
/// for a stamp, or a moment what reads it asks to be woken at (Ctx::wake_in), never for what shows the time going.
pub fn Ctx::moment(self : Ctx) -> Double {
  if self.in_frame() {
    self.clock
  } else {
    h_now()
  }
}

///|
/// `t` (ms) in whole ms, as a motion's and the runtime's time go: rounded down, a moment summed one way or another
/// (1316.9999999999998 for 1317) the same.
pub fn whole_ms(t : Double) -> Double {
  (t + same_moment_ms).floor()
}

///|
/// How far apart two moments summed one way and another may be and still be the same one (whole_ms; a motion done
/// by it at its end, the next of a chain from that end: Anim::animate's start_at).
pub let same_moment_ms : Double = 1.0e-6

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
  hand.pointer.get() |> ignore
  self.pointer_t
}

///|
/// How fast the pointer went at its latest event (points per ms, across and down; at most a fling's fastest): what a
/// list let go flings at (Compose's VelocityTracker over the press's events, by their own times), for what else a
/// finger lets go of moving (a picture zoomed in).
pub fn Ctx::pointer_velocity(self : Ctx) -> (Double, Double) {
  ignore(self)
  hand.pointer.get() |> ignore
  (dclamp(track_x.velocity(), -max_fling, max_fling), dclamp(track_y.velocity(), -max_fling, max_fling))
}

///|
/// Which of the hit targets `rects` (in paint order, cut by `clips`) is topmost at (x, y): its index, -1 none.
/// `pressed`: the one a press there goes to, past those only pointed at (Ctx::box's `points`).
fn hit_at(
  ids : Array[Int],
  rects : Array[Double],
  clips : Array[Double],
  x : Double,
  y : Double,
  pressed? : Bool = false,
) -> Int {
  let points = g().points
  let passes = g().passes
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if !(pressed && points.contains(ids[k])) &&
      !passes.contains(ids[k]) &&
      x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] &&
      in_round_clip(clips, k, x, y) {
      break
    }
    k = k - 1
  }
  // a column's edge drawn over a list's bar: the bar's thumb, shown, takes the pointer where it is (its edge the edge's
  // elsewhere: a strip either side of its line, as the web's)
  if k > 0 && as_drawn(ids[k]) {
    let bars = g().bars
    let mut j = k - 1
    while j >= 0 {
      let r = j * 4
      if x >= rects[r] &&
        x < rects[r + 2] &&
        y >= rects[r + 1] &&
        y < rects[r + 3] &&
        bars.iter().any(fn(b) { b.thumb == ids[j] }) &&
        in_round_clip(clips, j, x, y) {
        return j
      }
      j = j - 1
    }
  }
  k
}

///|
/// Whether target `id` is pressed only where it is drawn, no room grown round it (press_reach, rooms.mbt): a column's
/// edge, its pointer's shape a resize (the user, 2026-10-28: 左右各 6px, 同 web).
fn as_drawn(id : Int) -> Bool {
  match marked_cursor(hit_marks(id)) {
    Some(k) => k == Cursor::ResizeX.code() || k == Cursor::ResizeY.code()
    None => false
  }
}

///|
fn hit_in(ids : Array[Int], rects : Array[Double], x : Double, y : Double) -> Int {
  let targets = physical_equal(rects, g().hit_rects)
  let clips = if targets { g().hit_clips } else { [] }
  // (a press: past what is only pointed at)
  let k = hit_at(ids, rects, clips, x, y, pressed=targets)
  // what is drawn smaller than its room is reached from round it, by a finger or a pointer alike (press_reach)
  let k = if targets { press_reach(ids, rects, clips, k, x, y) } else { k }
  if k >= 0 {
    ids[k]
  } else {
    0
  }
}

///|
/// The least a target is across, each way, as a press reaches it (room_least: one room, press_reach's): for what a
/// view reaches by hand itself (a drag area's own taps).
pub fn finger_target() -> Double {
  room_least()
}

///|
/// The room a press has round what is drawn (x0, y0)–(x1, y1): each way it is drawn smaller than `room_least()`, it
/// grown to it round its middle (not drawn so, nor laid out); moved in where that passes an edge past which nothing is pressed
/// (`edge`: the window, what cuts it) rather than cut short there; cut where it passes what holds it that takes presses
/// (`cut`: a row's small button keeps to its row, the row's own room round it the row's). What the hit test reaches
/// (press_reach) and the room rules measure (rooms.mbt), one.
fn press_room(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cut : (Double, Double, Double, Double),
  edge : (Double, Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let (ax0, ax1) = room_across(x0, x1, cut.0, cut.2, edge.0, edge.2)
  let (ay0, ay1) = room_across(y0, y1, cut.1, cut.3, edge.1, edge.3)
  (ax0, ay0, ax1, ay1)
}

///|
/// One way of press_room: `lo`–`hi` grown to room_least() round its middle where shorter, moved in from `elo`–`ehi`'s
/// ends, cut to `clo`–`chi`.
fn room_across(
  lo : Double,
  hi : Double,
  clo : Double,
  chi : Double,
  elo : Double,
  ehi : Double,
) -> (Double, Double) {
  let mut a = lo
  let mut b = hi
  let least = room_least()
  if hi - lo < least {
    let mid = (lo + hi) / 2.0
    a = mid - least / 2.0
    b = mid + least / 2.0
    // (moved in from an edge it passes, not cut short at it)
    if a < elo {
      b = b + (elo - a)
      a = elo
    }
    if b > ehi {
      a = a - (b - ehi)
      b = ehi
    }
  }
  (dmax(a, dmax(clo, elo)), dmin(b, dmin(chi, ehi)))
}

///|
/// What a press (or the pointer) at (x, y) is on: `top` (the topmost target there, its index; -1 none), or a target
/// drawn over it and within it smaller than its room whose room (press_room, cut to `top`, moved in from what cuts it
/// and the window) holds (x, y), the nearest of several (where rooms meet, each has the part nearer it): a row's small
/// button from round it, not the row's neighbour's. On what takes the pointer (`capture`: a picture a drag pans) the
/// press is its own, nothing over it reached (a viewer's 下一张 over the picture: a drag beside it pans). By a finger
/// and a pointer alike (the user, 2026-10-26: drawn small with a keyboard and mouse, a press's room is not), so what
/// lights under the pointer is what a click there presses. What is only pointed at is never reached for.
fn press_reach(
  ids : Array[Int],
  rects : Array[Double],
  clips : Array[Double],
  top : Int,
  x : Double,
  y : Double,
) -> Int {
  if top >= 0 && captures.contains(ids[top]) {
    return top
  }
  let points = g().points
  let (ww, wh) = (g().width, g().height)
  let least = room_least()
  let mut best = top
  let mut best_d = 1.0e18
  for k in (top + 1)..<ids.length() {
    let r = k * 4
    let (x0, y0, x1, y1) = (rects[r], rects[r + 1], rects[r + 2], rects[r + 3])
    let (w, h) = (x1 - x0, y1 - y0)
    if points.contains(ids[k]) ||
      g().passes.contains(ids[k]) ||
      as_drawn(ids[k]) ||
      w <= 0.0 ||
      h <= 0.0 ||
      (w >= least && h >= least) {
      continue
    }
    // cut to what the press is on (drawn in it), moved in from what cuts it (a list's edge) and the window
    let mut cut = (0.0, 0.0, ww, wh)
    if top >= 0 {
      let t = top * 4
      if x0 < rects[t] || y0 < rects[t + 1] || x1 > rects[t + 2] || y1 > rects[t + 3] {
        continue
      }
      cut = (rects[t], rects[t + 1], rects[t + 2], rects[t + 3])
    }
    let mut edge = (0.0, 0.0, ww, wh)
    let b = k * clip_n
    if b + clip_n <= clips.length() {
      edge = (dmax(0.0, clips[b]), dmax(0.0, clips[b + 1]), dmin(ww, clips[b + 2]), dmin(wh, clips[b + 3]))
    }
    let (rx0, ry0, rx1, ry1) = press_room(x0, y0, x1, y1, cut, edge)
    // (and within the rounded corners of what cuts it, as a press on it is)
    if x < rx0 || x >= rx1 || y < ry0 || y >= ry1 || !in_round_clip(clips, k, x, y) {
      continue
    }
    let dx = dmax(0.0, dmax(x0 - x, x - x1))
    let dy = dmax(0.0, dmax(y0 - y, y - y1))
    let d = dx * dx + dy * dy
    if d < best_d {
      best_d = d
      best = k
    }
  }
  best
}

///|
/// Whether (x, y), in hit target `k`'s rect, is within the rounded corners of what cut it (`clips`, Ctx::hit_clips):
/// a corner as round, and as smooth, as the renderers cut it (smooth.mbt sd_clip: where its box has it, whatever the
/// clip's own size); and within its outer clip's too, where it has one (clip_stack: a pane round a rounded frame).
fn in_round_clip(clips : Array[Double], k : Int, x : Double, y : Double) -> Bool {
  let b = k * clip_n
  if b + clip_n > clips.length() {
    return true
  }
  let outer = clips[b + 16] > 0.0 || clips[b + 17] > 0.0 || clips[b + 18] > 0.0 || clips[b + 19] > 0.0
  in_round_rect(clips, b, x, y) && (!outer || in_round_rect(clips, b + 12, x, y))
}

///|
/// Whether (x, y) is within the rounded rect of `clips` at `b` (a clip_stack clip's 12 numbers) at its corners, as the
/// renderers cut it (sd_clip).
fn in_round_rect(clips : Array[Double], b : Int, x : Double, y : Double) -> Bool {
  let r = (clips[b + 4], clips[b + 5], clips[b + 6], clips[b + 7])
  if r.0 <= 0.0 && r.1 <= 0.0 && r.2 <= 0.0 && r.3 <= 0.0 {
    return true
  }
  sd_clip(
    x,
    y,
    clips[b],
    clips[b + 1],
    clips[b + 2],
    clips[b + 3],
    r,
    (clips[b + 8], clips[b + 9], clips[b + 10], clips[b + 11]),
  ) <=
  0.0
}

///|
/// A hit target drawn now: `id` where (x0 y0 x1 y1) shows (cut already to the clip's rect), and the clip itself; none
/// where nothing of it shows (cut to nothing: a link's line outside its words' clip), as what is drawn outside what
/// cuts it is not painted. Whether it was said.
fn Ctx::push_hit(
  self : Ctx,
  id : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  marks? : Int = 0,
) -> Bool {
  if x0 > x1 || y0 > y1 {
    return false
  }
  self.next_hit_ids.push(id)
  self.next_hit_marks.push(marks)
  if self.passing > 0 {
    self.next_passes[id] = true
  }
  // (holding none till what is drawn in it is: Ctx::paint)
  self.next_hit_ends.push(self.next_hit_ids.length())
  self.next_hit_rects.push(x0)
  self.next_hit_rects.push(y0)
  self.next_hit_rects.push(x1)
  self.next_hit_rects.push(y1)
  let k = clip_top()
  for j in 0..<clip_n {
    self.next_hit_clips.push(clip_stack[k + j])
  }
  true
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
    s.go(self.clock, target, what="c.spring \"" + key + "\"", loc~)
  }
  s.value(self.now_before(s.end()))
}

///|
/// When the spring `key` (Ctx::spring, in the same scope) is at rest (the frames' clock; -1: it is, or there is none):
/// what a test runs to.
pub fn Ctx::spring_rest(self : Ctx, key : String) -> Double {
  match self.springs.get(self.id(key)) {
    Some(s) if s.end() > self.clock => s.end()
    _ => -1.0
  }
}

///|
#callsite(autofill(loc))
fn Ctx::wake_at_time(self : Ctx, t : Double, later? : Bool = false, loc~ : SourceLoc) -> Unit {
  part_wake(self.clock, t, later)
  // (asked as a list's row is built: the row's, built again as it comes by what it read of it, kept_part.mbt's
  // KeptClock; not the frame's own, frame_watch.mbt)
  if nodes_run.building is None {
    looks_wake(t, loc)
  }
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
/// layout, read back). A link in words, drawn in pieces one after another (its runs, its lines), is the box round
/// them all, as a page's inline element is (what hangs by it lines up with its start).
#callsite(autofill(loc))
pub fn Ctx::rect_of(self : Ctx, id : Int, loc~ : SourceLoc) -> (Double, Double, Double, Double)? {
  // (read as a list's row is built: where the last frame drew it, read back by nothing; the row built every frame,
  // kept_nodes.mbt)
  if nodes_run.building is Some(_) {
    built_aside(why="where the last frame drew a target, read at \{loc}")
  }
  let mut k = self.hit_ids.length() - 1
  while k >= 0 && self.hit_ids[k] != id {
    k = k - 1
  }
  if k < 0 {
    return None
  }
  let mut x0 = self.hit_rects[k * 4]
  let mut y0 = self.hit_rects[k * 4 + 1]
  let mut x1 = self.hit_rects[k * 4 + 2]
  let mut y1 = self.hit_rects[k * 4 + 3]
  let mut j = k - 1
  while j >= 0 && self.hit_ids[j] == id {
    x0 = dmin(x0, self.hit_rects[j * 4])
    y0 = dmin(y0, self.hit_rects[j * 4 + 1])
    x1 = dmax(x1, self.hit_rects[j * 4 + 2])
    y1 = dmax(y1, self.hit_rects[j * 4 + 3])
    j = j - 1
  }
  Some((x0, y0, x1 - x0, y1 - y0))
}

///|
/// The pointer, and whether it is down.
pub fn Ctx::pointer(self : Ctx) -> (Double, Double, Bool) {
  // (read so: what reads it is built again as the pointer moves, goes down or is let go, hand.mbt)
  hand.pointer.get() |> ignore
  hand.down.get() |> ignore
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
/// The keys held down now (@hostapi.mods_held: mod_shift_key, mod_ctrl, mod_alt, mod_cmd). Under a Tester: as it holds
/// them (Tester::hold_mods).
pub fn mods_held() -> Int {
  match fake.val {
    Some(f) => f.mods
    None => @hostapi.mods_held()
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
/// Puts a secret on the system's clipboard: marked sensitive (Android masks its preview, Windows keeps it out of the
/// clipboard's history), taken off `clear_ms` later (0: kept) unless something else was copied meanwhile or another
/// secret since: on the app's clock (a host keeps no time of its own), nothing the app waits on.
pub fn Ctx::copy_secret(self : Ctx, s : String, clear_ms~ : Double) -> Unit {
  ignore(self)
  h_clipboard_secret(s, clear_ms)
  secret_copies.val += 1
  let copy = secret_copies.val
  if clear_ms > 0.0 {
    fx.val.after(
      clear_ms.to_int(),
      fn() { if copy == secret_copies.val { h_clipboard_secret_off() } },
      later=true,
      who="clipboard: a secret taken off",
    )
  }
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
  self.wake_at_time(self.clock + dmax(ms, 1.0), later~, loc~)
}
