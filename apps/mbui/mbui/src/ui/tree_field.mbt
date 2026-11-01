// A field of words as a node of the window's tree (ui's field): the same editor an old view's field is (Ctx::editor:
// its EditorState, its keys, what the input method says, its caret and what is picked, its undo), held by a node in
// place of an old view's. What it is known by in the window is the id the node is read out by (tree_said_id): the
// focus on it, the keys and words typed to it (key_in, on_text_now), the host told where its caret is (sync_ime) go
// there as to an old view's. Laid out and drawn as an old view's field is, as it is placed (FieldBox: Ctx::lay_out_field,
// Ctx::paint_field), each frame where its node is drawn and as big; a pointer brought into its words by where that is
// (EditorState::drawn_now). A press on it is its node's (View::on_press) as an old view's field's is its: taken as it
// goes down (the caret put there, what is picked dragged on), or on Android's a tap's once let go where it went down,
// what holds it free to take a finger moving on over meanwhile (View::claims). What its words give up (Enter, where it sends) told once, at the moment of the
// input that gave them (tree_field_said), never as a frame is drawn.

///|
/// A field of the window's tree's: its editor, how its words are set (as Ctx::editor is told them), what it says it is
/// while empty, and what is told its words given up.
priv struct TreeField {
  st : EditorState
  /// its words' size, as said (followed: its paint and its measure read it)
  font_size : () -> Double
  line : Double
  max_lines : Int
  hint : String
  shorter : Array[String]
  trim : Bool
  submitted : (String) -> Unit
  pasted : (String) -> Unit
  /// what is told files pasted into it (⌘V with files or a picture on the clipboard), where it takes them
  files : ((Array[(String, Bytes)]) -> Unit)?
  /// where the press on it now went down (the window's terms), none held; whether it took it as it went down (the
  /// caret put there, what is picked dragged on from there); whether a finger waiting for a tap went past the slop
  mut down : (Double, Double)?
  mut editing : Bool
  mut strayed : Bool
  /// the node it is (what times a finger's hold on it: View::at_moment), what calls that hold's moment off
  view : @view.View
  mut hold_off : () -> Unit
  /// how many presses in a row the one held is (a double click's 2, a triple's 3), Shift held as it went down; the last
  /// press's run (how many, when, where: as the old frame counts them, app.mbt's press_run)
  mut clicks : Int
  mut shifted : Bool
  mut run : (Int, Double, Double, Double)
  /// a finger's: the word a long press picked dragged on (by words), a handle of its own dragged (Ctx's handle_which,
  /// 1 the caret's); the last tap (when, where: a second soon after near it picks the word there)
  mut word_drag : Bool
  /// a finger's drawn up or down on its words past the slop, where they can go that way: scrolling them, where it was last
  /// and when; how it went down from where it went down (how fast it goes as it is let go: as the old frame's track_y)
  mut scrolling : Bool
  /// its bar's thumb held by the pointer (Ctx's bar_drag, as the old frame holds one)
  mut bar : Bool
  mut last_y : (Double, Double)
  track : @view.Tracker
  mut handle : Int
  mut last_tap : (Double, Double, Double)
}

///|
/// The fields of the window's tree, by the node each is.
// kept across runs: put back as a run begins (view_forget); each let go with its node (tree_field_gone)
let tree_fields : Map[@view.NodeId, TreeField] = Map([])

///|
/// A field of words in `parent`, showing and editing `field`: as Ctx::editor's plain one (no frame of its own: what
/// holds it draws one) set so (`placeholder` and its `shorter` ways, `font_size`, `line`, `max_lines`, `trim`, its
/// colours, `enter_sends`, `leaves`, `ime_action`, `paste_limit`, `secret`, `words`, `look`: each as Ctx::editor takes
/// it; `files`: what it is told files pasted into it, where it takes them, as Ctx::editor's `files` and
/// Ctx::field_files), as tall as
/// its words lay out between a line and `max_lines` (Field::laid), read out as a field of its words. `submitted`: what
/// is told its words as they are given up (Enter, where it gives them up), once, at that key's moment; `pasted`, a
/// paste of `paste_limit` characters or more, not put in, once, at that paste's. The node made.
pub fn field(
  parent : @view.View,
  field : Field,
  placeholder? : String = "",
  font_size? : Double = 15.0,
  line? : Double = 0.0,
  max_lines? : Int = 5,
  color? : Int64 = 0x1D1D1FFFL,
  placeholder_color? : Int64 = 0x8E8E93FFL,
  caret_color? : Int64 = 0x0A84FFFFL,
  enter_sends? : Bool,
  shorter? : Array[String] = no_words,
  trim? : Bool = false,
  leaves? : Array[Int] = [],
  ime_action? : Int = 0,
  paste_limit? : Int = 0,
  secret? : Bool = false,
  words? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  submitted? : (String) -> Unit = fn(_) {  },
  pasted? : (String) -> Unit = fn(_) {  },
  files? : (Array[(String, Bytes)]) -> Unit,
  size_by? : () -> Double,
  colors_by? : () -> (Int64, Int64, Int64),
) -> @view.View {
  // (its size and its colours as said once, or followed as they change (`size_by`; `colors_by`: its words', its
  // placeholder's, its caret's): words written over a picture, as big as the picture is drawn, in the colour picked)
  let size = match size_by {
    Some(f) => f
    None => fn() { font_size }
  }
  parent.box(fn(f) {
    let id = f.id()
    let st = field.st
    // (one Field, one editor: held by another node still, it is told; an old view's editor given it then, Ctx::editor)
    match st.tree_node {
      Some(other) if other != id && tree_fields.contains(other) =>
        abort("field: one Field given to two fields of the tree's: a Field is one editor's")
      _ => ()
    }
    st.tree_node = Some(id)
    st.line = line
    st.color = color
    st.ph_color = placeholder_color
    st.caret_color = caret_color
    st.sel_color = (caret_color & 0xFFFFFF00L) | 0x40L
    match colors_by {
      Some(colors) =>
        // (said again as they change: painted again in them)
        f.reacts(colors, fn(k) {
          let (ink, hint, caret) = k
          st.color = ink
          st.ph_color = hint
          st.caret_color = caret
          st.sel_color = (caret & 0xFFFFFF00L) | 0x40L
          tree_field_redraw()
        })
      None => ()
    }
    st.enter_sends = enter_sends.unwrap_or(enter_sends_by(max_lines, ime_action))
    st.leaves = leaves
    st.ime_action = ime_action
    st.limit = paste_limit
    st.secret = secret
    st.words = words
    st.look = look
    st.looked = None
    tree_fields[id] = {
      st,
      font_size: size,
      line,
      max_lines,
      hint: placeholder,
      shorter,
      trim,
      submitted,
      pasted,
      files,
      down: None,
      editing: false,
      strayed: false,
      view: f,
      hold_off: fn() {  },
      clicks: 0,
      shifted: false,
      run: (0, -1.0e9, 0.0, 0.0),
      word_drag: false,
      scrolling: false,
      bar: false,
      last_y: (0.0, 0.0),
      track: @view.Tracker::new(),
      handle: 0,
      last_tap: (-1.0e9, 0.0, 0.0),
    }
    g().editors[tree_said_id(id)] = st
    // (more lines than it shows: its words scroll in it as an old view's field's do, the wheel, a finger (Ctx::editor's
    // scroll_state), how far the layout's (Ctx::lay_out_field))
    if max_lines > 1 {
      let sw = g().scroll_state(tree_said_id(id), true)
      sw.field = true
    }
    f
    // (laid out as what it shows, a secret's dots, what its look makes of its words, worked out here anew as they or what
    // the look reads change: the one working out its layout and its drawing take (EditorState::look_of's, kept);
    // where only its look's colours change, a frame for them all the same)
    .measured(
      By(fn() {
        let laid = field.laid(font_size=size(), line~, max_lines~, trim~)
        // (its words as written followed as well as with what is composed: what is composed put in as written shows
        // the same, its look's not, EditorState::look_shown)
        field.text() |> ignore
        st.looked = None
        let (shown, spans) = st.look_shown()
        ({ ..laid, words: if secret { st.shown() } else { shown } }, spans)
      }),
      fn(k, w) { k.0.size(w) },
    )
    .focusable(Is(true), keys=0)
    // (its words read out, a secret's none: as an old view's editor says them)
    .says(By(fn() {
      let value = field.composed_said()
      Some(@view.said(TextField, label=placeholder, value=if secret { "" } else { value }, actions=[SetText("")]))
    }))
    // (a press on it: taken as it goes down where the field takes it so, else a tap's as it is let go: tree_field_down)
    .on_press(fn() { tree_field_tapped(id) })
    // (the wheel over it: its words scrolled while they can go that way, else what holds it's, sideways_wheel)
    .on_wheel_moves(fn(w) { tree_field_wheel(id, w) })
    // (its editor no longer the window's as it is let go, whatever lets it go)
    .owns(fn() { tree_field_gone(id) })
    |> ignore
    // (the focus asked for it before it was held: given it now, it able to take it, Field::focus)
    if st.focus_asked {
      st.focus_asked = false
      tree_field_focus(id)
    }
  })
}

///|
/// The keyboard's focus given field `self`, as Ctx::focus_editor gives an old view's editor its: where a field of the
/// window's tree holds it, at once; else as one comes to hold it (words begun over a picture, a note opened: its node
/// made as what says so changes).
pub fn Field::focus(self : Field) -> Unit {
  match self.st.tree_node {
    Some(id) if tree_fields.contains(id) => tree_field_focus(id)
    _ => self.st.focus_asked = true
  }
}

///|
/// The keyboard's focus given field `field` by what holds it now: a field of the window's tree, at once (where it can
/// take it); an old view's editor drawn now, that one (where the old view it is in takes input); none, asked of the one
/// that comes to hold it, given as it does (a field of the tree's as it is made; an old view's editor as it is built),
/// the focus where it is till then.
pub fn Ctx::focus_field(self : Ctx, field : Field) -> Unit {
  let st = field.st
  // (held by a field of the window's tree: its)
  match st.tree_node {
    Some(id) if tree_fields.contains(id) => {
      tree_field_focus(id)
      return
    }
    _ => ()
  }
  // (held by an old view's editor drawn now, one of the frame's nodes: that one, where the old view it is in takes input)
  if st.built_id != 0 && st.tree_node is None {
    for i in 0..<self.count {
      let n = self.nodes[i]
      // (the node by the id it was built at, and that id's editor this Field's still: one built after at the same key
      // with another Field holds that one, not this)
      if n.kind == kind_editor && n.id == st.built_id && self.editors.get(n.id).map_or(false, fn(e) { physical_equal(e, st) }) {
        if island_allows(self.island_of_id(st.built_id)) {
          self.focus_moved(st.built_id)
        }
        return
      }
    }
  }
  // (held by none now: asked of whichever comes to hold it, taken as it does (field(), Ctx::editor), nothing moved before)
  st.focus_asked = true
}
///|
/// Field node `id` given the keyboard's focus where it can take it now (the tree's: under no modal layer that does not
/// hold it, able to take it); else the focus where it was.
fn tree_field_focus(id : @view.NodeId) -> Unit {
  guard view_app.val is Some(tree) && tree.can_focus(id) else { return }
  g().focus_moved(tree_said_id(id))
  tree_field_redraw()
}

///|
/// Field node `id` let go: its editor nobody's in the window.
fn tree_field_gone(id : @view.NodeId) -> Unit {
  match tree_fields.get(id) {
    Some(tf) => {
      tree_fields.remove(id)
      match tree_said_of.get(id) {
        Some(k) => {
          match g().editors.get(k) {
            Some(st) if physical_equal(st, tf.st) => g().editors.remove(k)
            _ => ()
          }
          sideways.remove(k)
        }
        None => ()
      }
      if tf.st.tree_node == Some(id) {
        tf.st.tree_node = None
      }
      if tree_field_hovered.val == Some(id) {
        tree_field_hovered.val = None
      }
    }
    None => ()
  }
}

///|
/// A primary press went down on field node `id` at (`x`, `y`) at `at`, as an old view's field takes it (app.mbt's): on
/// Android's, nothing yet: a tap's as the finger is let go where it went down (tree_field_tapped), a hold of
/// long_press_ms there the word there picked (tree_field_held), a finger moving on what holds it's to take over
/// (Compose's); elsewhere at once: the focus its, the caret put there (Shift held: what is picked widened to there; a
/// double click's second the word there, a triple's third the paragraph), what is picked dragged on from there, the
/// press its own (what holds it takes nothing over). Whether it took it so. Nothing for what is no field.
fn tree_field_down(id : @view.NodeId, x : Double, y : Double, at : Double) -> Bool {
  guard tree_fields.get(id) is Some(tf) else { return false }
  (tf.hold_off)()
  tf.down = Some((x, y))
  tf.strayed = false
  tf.editing = false
  tf.word_drag = false
  tf.handle = 0
  tf.track.reset()
  tf.track.add(at, y)
  // (its words flung on: stopped where they are, as an old view's field's are as a finger goes down, sideways_down)
  sideways_down(g(), tree_said_id(id), x, y)
  let st = tf.st
  if h_feel() == 2 {
    // (held still long_press_ms where it went down: at that moment, on the tree's timeline, whatever frames come)
    tf.hold_off = tf.view.at_moment(at + long_press_ms, fn() { tree_field_held(id) })
    return false
  }
  // (how many presses in a row: one soon after the last and near it counts on from it, as the old frame counts)
  let (n, was, ax, ay) = tf.run
  tf.clicks = if at - was <= double_click_ms && (x - ax).abs() <= double_click_slop && (y - ay).abs() <= double_click_slop {
    n + 1
  } else {
    1
  }
  tf.run = (tf.clicks, at, x, y)
  tf.shifted = (mods_held() & mod_shift_key) != 0
  g().focus_moved(tree_said_id(id))
  if tf.shifted {
    st.widen_by_pointer(x, y, at)
  } else {
    place_caret_at(st, x, y, at)
    if tf.clicks > 1 {
      st.pick_at(if tf.clicks == 2 { Words } else { Paragraphs })
    }
  }
  tf.editing = true
  tree_field_redraw()
  true
}

///|
/// A finger held still on field node `id` long_press_ms where it went down (Android's long press): the focus its, the
/// word there picked, its handles and the floating menu as it is let go, felt; the finger sliding on from there widens
/// it by words, the press its own from here (what holds it takes nothing over).
fn tree_field_held(id : @view.NodeId) -> Unit {
  guard tree_fields.get(id) is Some(tf) else { return }
  // (the press still its: the tree's hold on its node, none called off since however it was (the window behind, a
  // second finger, taken over, its node taking no press); else nothing of it kept)
  guard tf.view.pressed() else {
    tree_field_let_go(id, 0.0, 0.0, false)
    return
  }
  guard !tf.strayed && !tf.editing && tf.down is Some((x, y)) else { return }
  let c = g()
  c.focus_moved(tree_said_id(id))
  let st = tf.st
  tf.editing = true
  match st.local(x, y) {
    Some((lx, ly)) => if st.pick_word(lx, ly, view_moment()) { tf.word_drag = true }
    None => ()
  }
  view_down.val = None
  haptic(LongPress)
  tree_field_redraw()
}

///|
/// A primary press at (`x`, `y`) at `at` on a handle of the focused field of the tree's (Android's: its words picked's
/// ends, its caret's), before what is under it: that handle the finger's (Ctx's handle_drag, as the old frame takes it),
/// the menu away meanwhile, the press the field's node's alone (nothing of the tree's under it or holding it takes it).
/// Whether it was on one.
fn tree_field_handle_down(x : Double, y : Double, at : Double) -> Bool {
  let c = g()
  guard tree_said_ids.get(c.focus_allowed()) is Some(id) else { return false }
  guard tree_fields.get(id) is Some(tf) else { return false }
  let st = tf.st
  guard st.local(x, y) is Some((lx, ly)) else { return false }
  let which = st.on_sel_handle(lx, ly)
  let (which, dy) = if which != 0 {
    (which, ly - (if which == 2 { st.sel_ay } else { st.sel_by }))
  } else if st.on_handle(lx, ly) {
    (1, ly - st.handle_y)
  } else {
    return false
  }
  (tf.hold_off)()
  tf.down = Some((x, y))
  tf.strayed = false
  tf.editing = true
  tf.word_drag = false
  tf.handle = which
  c.handle_which = which
  c.handle_drag = c.focus
  c.handle_dy = dy
  if which != 1 {
    st.menu = false
  }
  view_held.val = Some(Node(id))
  view_down.val = None
  ignore(at)
  tree_field_redraw()
  true
}

///|
/// The press on field node `id` moved to (`x`, `y`) at `at`: where it took it (as it went down, a long press, a handle),
/// what is picked or where the caret is followed there (true: its own); else how far it went told (a finger past the
/// slop no tap, no hold), what holds it free to take it over (false). False for what is no field.
fn tree_field_moved(id : @view.NodeId, x : Double, y : Double, at : Double) -> Bool {
  guard tree_fields.get(id) is Some(tf) else { return false }
  tf.track.add(at, y)
  match tf.down {
    Some((x0, y0)) if (x - x0).abs() > touch_slop() || (y - y0).abs() > touch_slop() => {
      tf.strayed = true
      if !tf.editing {
        (tf.hold_off)()
      }
    }
    _ => ()
  }
  if !tf.editing {
    return tree_field_scroll_move(id, tf, x, y, at)
  }
  let st = tf.st
  if tf.bar {
    // (its thumb held: what it is for scrolled as far as the thumb went, by its track as drawn, Ctx::bar_drag_move's)
    let (ly, _) = tf.last_y
    tf.last_y = (y, at)
    match (g().bar_drawn(tree_said_id(id)), sideways.get(tree_said_id(id))) {
      (Some(b), Some(sw)) => {
        let was = sw.x
        sw.x = dclamp(sw.x + (y - ly) * b.ratio, 0.0, dmax(sw.max, 0.0))
        if sw.x != was {
          g().sideways_scrolled(sw)
        }
      }
      _ => ()
    }
  } else if tf.handle != 0 {
    handle_move(g(), x, y, at)
  } else if tf.word_drag {
    match st.local(x, y) {
      Some((lx, ly)) => st.widen_to(lx, ly)
      None => ()
    }
    st.menu = false
  } else {
    match (st.tl, st.local(x, y)) {
      (Some(_), Some((lx, ly))) if tf.clicks > 1 && !tf.shifted =>
        st.widen_to(lx, ly, by=if tf.clicks == 2 { Words } else { Paragraphs })
      (Some(tl), Some((lx, ly))) => st.caret_to_point(tl, lx, ly)
      _ => ()
    }
  }
  tree_field_redraw()
  true
}

///|
/// Field node `id` pressed (its press let go on it, not taken over): a tap where it waited for one (Android's), the
/// finger let go where it went down: the focus its (said to the host anew where it had it: its keyboard asked for
/// again); a second tap soon after the first and near it, the word there picked (Compose's double tap); else the caret
/// where it went down, its handle under it where it holds words. Nothing where it took the press otherwise.
fn tree_field_tapped(id : @view.NodeId) -> Unit {
  guard tree_fields.get(id) is Some(tf) else { return }
  guard !tf.editing && !tf.strayed && tf.down is Some((x, y)) else { return }
  (tf.hold_off)()
  let c = g()
  let said = tree_said_id(id)
  if c.focus == said {
    c.ime_sig = "tap"
  }
  c.focus_moved(said)
  let st = tf.st
  let t = view_moment()
  let (was, lx, ly) = tf.last_tap
  if t - was <= double_tap_ms && (x - lx).abs() <= 2.0 * touch_slop() && (y - ly).abs() <= 2.0 * touch_slop() {
    match st.local(x, y) {
      Some((px, py)) => st.pick_word(px, py, t) |> ignore
      None => ()
    }
    tf.last_tap = (-1.0e9, 0.0, 0.0)
  } else {
    place_caret_at(st, x, y, t)
    st.handle = st.text.length() > 0
    tf.last_tap = (t, x, y)
  }
  tree_field_redraw()
}

///|
/// The press on field node `id` let go (`up`) or called off at (`x`, `y`): a handle let go, the menu back over what is
/// picked (the caret's tapped, not moved: its menu shown or put away); a long press's word slid on from, the menu over
/// it; nothing of the press kept.
fn tree_field_let_go(id : @view.NodeId, x : Double, y : Double, up : Bool) -> Unit {
  guard tree_fields.get(id) is Some(tf) else { return }
  (tf.hold_off)()
  tf.hold_off = fn() {  }
  let st = tf.st
  let c = g()
  if up && tf.handle != 0 {
    if tf.handle == 1 {
      match tf.down {
        Some((x0, y0)) if (x - x0).abs() <= touch_slop() && (y - y0).abs() <= touch_slop() => st.menu = !st.menu
        _ => ()
      }
    } else {
      st.menu = true
    }
    tree_field_redraw()
  }
  if up && tf.word_drag {
    st.menu = true
    tree_field_redraw()
  }
  // (its words scrolled by a finger, let go: flung on at its speed, as an old view's field's are, sideways_up)
  if tf.scrolling {
    if up {
      tf.track.add(view_moment(), y)
    }
    sideways_up(c, tree_said_id(id), 0.0, if up { dclamp(tf.track.velocity(), -max_fling, max_fling) } else { 0.0 })
  }
  if tf.handle != 0 {
    c.handle_drag = 0
  }
  if tf.bar {
    c.bar_let_go()
  }
  tf.down = None
  tf.editing = false
  tf.strayed = false
  tf.word_drag = false
  tf.scrolling = false
  tf.bar = false
  tf.handle = 0
}

///|
/// Told as a field of the tree's is changed by what is its own (its node's press, its wheel, its scrolling, a screen
/// reader's words, a paste come): what its paint reads (Ctx::paint_tree_field), so the frame after paints it again,
/// whatever else that frame does.
// kept across runs: only counted on
let tree_fields_drawn : @signals.Signal[Int] = @signals.signal(0)

///|
/// A field of the tree's changed by what is its own: painted again from the next frame (tree_fields_drawn).
fn tree_field_redraw() -> Unit {
  tree_fields_drawn.set(@signals.untracked(fn() { tree_fields_drawn.get() }) + 1)
  h_frame_owed()
}

///|
/// Bar `b` of a field laid out with its top left at `laid`, where it is drawn: its top left at (`x`, `y`), `s` as big
/// about it, cut to `outer` (x0, y0, x1, y1) as well.
fn bar_drawn_at(
  b : BarAt,
  laid : (Double, Double),
  x : Double,
  y : Double,
  s : Double,
  outer : (Double, Double, Double, Double),
) -> BarAt {
  let (lx, ly) = laid
  let ax = fn(v : Double) { x + (v - lx) * s }
  let ay = fn(v : Double) { y + (v - ly) * s }
  let (c0, c1, c2, c3) = outer
  {
    ..b,
    x0: dmax(ax(b.x0), c0),
    y0: dmax(ay(b.y0), c1),
    x1: dmin(ax(b.x1), c2),
    y1: dmin(ay(b.y1), c3),
    top_in: b.top_in * s,
    foot_in: b.foot_in * s,
    tx: ax(b.tx),
    ty: ay(b.ty),
    tw: b.tw * s,
    th: b.th * s,
    ratio: if s > 0.0 { b.ratio / s } else { b.ratio },
  }
}

///|
/// The field of the tree's found at (`x`, `y`) as a press would be: nothing the old frame put over all of it there (its
/// layers, modal or not, found outside the tree), then the tree's topmost taking input there, nothing modal over it;
/// where it is one: its node.
fn tree_field_at(x : Double, y : Double) -> @view.NodeId? {
  guard view_app.val is Some(tree) else { return None }
  // (what the old frame put over all of it there first, a layer modal or not, as the pointer's events find it outside
  // the tree: view_pointer's old_root_hit, view_point_tell's old_layer_over)
  if old_layer_over(x, y) {
    return None
  }
  match tree.target_at(x, y) {
    Pressed(id) if tree_fields.contains(id) => Some(id)
    _ => None
  }
}

///|
/// Where the tree finds a field of its own at (`x`, `y`) (tree_field_at): the bar that is near the pointer there, its
/// own, as drawn (its said id; 0 none of it there); none where it finds none (what is there the old frame's to say).
fn tree_field_bar_near(x : Double, y : Double) -> Int? {
  guard tree_field_at(x, y) is Some(id) else { return None }
  let said = tree_said_id(id)
  match g().bar_drawn(said) {
    Some(b) if b.near(x, y) => Some(said)
    _ => Some(0)
  }
}

///|
/// Whether the mouse's pointer at (`x`, `y`) is on bar `b`'s thumb, as drawn (scroll_bar_grab round it, within what
/// shows of the bar, the bar showing at all).
fn thumb_under(b : BarAt, x : Double, y : Double) -> Bool {
  let gr = scroll_bar_grab
  pointing() is Mouse &&
  g().bar_shows(b) > 0.002 &&
  x >= b.tx - gr &&
  x < b.tx + b.tw + gr &&
  y >= b.ty - gr &&
  y < b.ty + b.th + gr &&
  x >= b.x0 &&
  x < b.x1 &&
  y >= b.y0 &&
  y < b.y1
}

///|
/// Whether the mouse's pointer, where it is over the window, is on field node `id`'s thumb drawn as `b` (the window's
/// terms), the tree finding the field there (tree_field_at).
fn tree_field_thumb_pointed(id : @view.NodeId, b : BarAt) -> Bool {
  match view_point.val {
    Some((x, y)) => tree_field_at(x, y) == Some(id) && thumb_under(b, x, y)
    None => false
  }
}

///|
/// The field of the tree's the mouse's pointer was last over, nothing held (tree_fields_pointed).
// kept across runs: put back with the fields (view_forget's tree_field_gone)
let tree_field_hovered : Ref[@view.NodeId?] = Ref(None)

///|
/// The mouse's pointer moved, nothing held, over field node `over` as the tree finds it there (none: over none): the
/// field it was over and the one it is over now, where each scrolls its words (its bar lit as its paint finds the
/// pointer on its thumb, tree_field_thumb_pointed), painted again: as the pointer goes, not as what it was last thought
/// to be on.
fn tree_fields_pointed(over : @view.NodeId?) -> Unit {
  let was = tree_field_hovered.val
  tree_field_hovered.val = over
  for id in [was, over] {
    match id {
      Some(n) =>
        match tree_said_of.get(n) {
          Some(k) if sideways.get(k).map_or(false, fn(sw) { sw.max > 1.0 }) => tree_field_redraw()
          _ => ()
        }
      None => ()
    }
  }
}

///|
/// A press of the pointer's (a mouse's) at (`x`, `y`) on field node `id` (the tree's press target there): on its bar's
/// thumb as drawn (scroll_bar_grab round it), that thumb held as an old view's is (Ctx::bar_press), the press its own
/// from here. Whether it was.
fn tree_field_bar_down(id : @view.NodeId, x : Double, y : Double, at : Double) -> Bool {
  guard pointing() is Mouse && tree_fields.get(id) is Some(tf) else { return false }
  let c = g()
  guard c.bar_drawn(tree_said_id(id)) is Some(b) else { return false }
  // (its thumb a target only as it is drawn at all, as an old view's is only where it shows: Ctx::paint_bar's)
  guard c.bar_shows(b) > 0.002 else { return false }
  let gr = scroll_bar_grab
  guard x >= b.tx - gr && x < b.tx + b.tw + gr && y >= b.ty - gr && y < b.ty + b.th + gr && x >= b.x0 && x < b.x1 &&
    y >= b.y0 && y < b.y1 else {
    return false
  }
  guard c.bar_press(b.thumb) else { return false }
  (tf.hold_off)()
  tf.down = Some((x, y))
  tf.editing = true
  tf.bar = true
  tf.last_y = (y, at)
  tree_field_redraw()
  true
}

///|
/// Whether `id`, a scrolling box's, is a field of the window's tree's (its node's said id): kept while its node is,
/// built by no old view (Ctx::sideways_after_layout).
fn tree_field_scrolls(id : Int) -> Bool {
  match tree_said_ids.get(id) {
    Some(n) => tree_fields.contains(n)
    None => false
  }
}

///|
/// The wheel over field node `id`: its words scrolled while they can go that way (true), else what holds it's.
fn tree_field_wheel(id : @view.NodeId, w : @view.Wheel) -> Bool {
  if sideways_wheel(tree_said_id(id), w.dx, w.dy) {
    tree_field_redraw()
    true
  } else {
    false
  }
}

///|
/// A finger on field node `id` waiting for a tap, moved to (`x`, `y`) at `at`: up or down past the slop, more than across,
/// where its words can go that way, they are scrolled from there (the press its own, nothing holding it taking it over:
/// its focus kept, another field's let go, as an old view's field's words are dragged, sideways_move); scrolling, by
/// as far as it moved. Whether it scrolls them.
fn tree_field_scroll_move(id : @view.NodeId, tf : TreeField, x : Double, y : Double, at : Double) -> Bool {
  let said = tree_said_id(id)
  guard sideways.get(said) is Some(sw) && tf.down is Some((x0, y0)) else { return false }
  let c = g()
  if tf.scrolling {
    let (ly, _) = tf.last_y
    let was = sw.x
    sw.x = dclamp(sw.x - (y - ly), 0.0, sw.max)
    tf.last_y = (y, at)
    if sw.x != was {
      c.sideways_scrolled(sw)
      tree_field_redraw()
    }
    return true
  }
  let (along, across) = (y - y0, x - x0)
  let slop = touch_slop()
  let can = if along < 0.0 { sw.x < sw.max } else { sw.x > 0.0 }
  guard along.abs() > slop && along.abs() >= across.abs() && can else { return false }
  (tf.hold_off)()
  tf.scrolling = true
  sw.held = true
  sw.vel = 0.0
  sw.rest = -1.0
  view_down.val = None
  c.scroll_lets_go(said)
  let past = if along > 0.0 { along - slop } else { along + slop }
  sw.x = dclamp(sw.x - past, 0.0, sw.max)
  tf.last_y = (y, at)
  c.sideways_scrolled(sw)
  tree_field_redraw()
  true
}

///|
/// What is asked of field node `id` from outside the hand (a screen reader's SetText: its words in place of all it held,
/// as though typed, as an old view's editor takes it). Whether it was a field's.
fn tree_field_asked(id : @view.NodeId, action : Action) -> Bool {
  guard tree_fields.get(id) is Some(tf) else { return false }
  match action {
    SetText(t) => {
      let st = tf.st
      st.marked = ""
      st.anchor = 0
      st.caret = st.text.length()
      st.text_input(0, t, 0, 0, view_moment())
      // (what it gave up by them (a paste's limit reached), told it at this input's moment)
      tree_field_told(tf)
      tree_field_redraw()
      true
    }
    _ => false
  }
}

///|
/// ⌘V's words read from the clipboard for a field of the tree's (key_in: desk.pasting, its node's said id), taken as
/// they come (ClipboardRead::got: the host's answer told, a Tester's by the frame), once: in place of what is picked, as
/// a paste, before the frame they come with is laid out (its height, what comes after it, where its caret is told all
/// of them) and whether it is drawn or not; as an old view's editor takes them as it is built (Ctx::editor). `now`:
/// that input's moment (the frame's, or the host's answer's), what its caret blinks from.
fn tree_fields_pasting(now : Double) -> Unit {
  guard desk.pasting is Some((pid, r)) else { return }
  guard tree_said_ids.get(pid) is Some(id) && tree_fields.get(id) is Some(tf) else { return }
  match r.got() {
    Some(got) => {
      desk.pasting = None
      // (where it takes files: the files, else the picture as one, told it once; else the words, as Ctx::editor takes
      // them)
      match (tf.files, got.files, got.picture) {
        (Some(told), [_, ..] as fs, _) => told(fs)
        (Some(told), [], Png(png)) => told([(pasted_picture_name, png)])
        _ =>
          if got.text != "" {
            tf.st.text_input(text_paste, got.text, 0, 0, now)
            // (a paste too long to put in given up by it: told the field it was read for, whichever has the focus now)
            tree_field_told(tf)
            tree_field_redraw()
          }
      }
    }
    None => ()
  }
}

///|
/// What the focused field of the window's tree gave up of its words in the input just taken (Enter, where it gives them
/// up), told what it holds it is told so, once: as that input is taken (on_key, on_text), not as a frame is drawn.
fn tree_field_said() -> Unit {
  let c = g()
  guard tree_said_ids.get(c.focus) is Some(id) else { return }
  guard tree_fields.get(id) is Some(tf) else { return }
  tree_field_told(tf)
}

///|
/// What field `tf` gave up of its words told what holds it is told so, each once, taken from it as it is told: its
/// words (Enter, where it gives them up: `submitted`), a paste of its limit's length or more, not put in (`pasted`).
fn tree_field_told(tf : TreeField) -> Unit {
  match tf.st.submitted {
    Some(words) => {
      tf.st.submitted = None
      (tf.submitted)(words)
    }
    None => ()
  }
  match tf.st.pasted {
    Some(words) => {
      tf.st.pasted = None
      (tf.pasted)(words)
    }
    None => ()
  }
}

///|
/// Field node `id` drawn this frame at (`x`, `y`), laid out `w` by `h` (in its own terms), `s` as big, `alpha` opaque:
/// placed there, laid out and drawn as an old view's field is (Ctx::lay_out_field, Ctx::paint_field), then drawn as big
/// as it is about that place, as what its block draws is.
fn Ctx::paint_tree_field(
  self : Ctx,
  id : @view.NodeId,
  tf : TreeField,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  s : Double,
  alpha : Double,
  laid~ : (Double, Double),
) -> Unit {
  // (painted where its node is laid out (`laid`), its words set on the pixels by their lines there, then moved to where
  // it is drawn and made as big there: as the tree's own words are, view_blit; not placed on the pixels as a whole, as
  // an old view's field is with its old view, old_place)
  let (ux, uy) = laid
  let z = self.editor_sizing((tf.font_size)(), tf.line, tf.max_lines, true, tree_theme().text_line)
  let fb : FieldBox = {
    id: tree_said_id(id),
    x: ux,
    y: uy,
    w,
    h,
    pad_l: z.pad_x,
    pad_t: z.pad_y,
    pad_r: z.pad_x,
    pad_b: z.pad_y,
    font_size: z.font_size,
    weight: Node::new().weight,
    line_h: z.line,
    wrap: z.wrap,
    trim: tf.trim,
    hint: tf.hint,
    shorter: tf.shorter,
  }
  let st = tf.st
  // (painted again as what is its own changes it (tree_field_redraw), and with the clock while its words are flung on)
  tree_fields_drawn.get() |> ignore
  // (more lines than it shows: its words' scroll brought to this frame as an old view's field's is as it is built
  // (Ctx::editor: Ctx::scroll_state, its fling stepped, its bar's and its fling's motion told), kept as this frame's;
  // painted again with the clock while it is flung)
  if tf.max_lines > 1 {
    let sw = self.scroll_state(fb.id, true)
    sw.field = true
    sw.theme = self.theme
    sw.built_frame = self.frame_no
    if sw.rest >= 0.0 {
      frame_clock.get() |> ignore
    }
  }
  st.placed_x = ux
  st.placed_y = uy
  self.lay_out_field(st, fb)
  // (drawn where it is its own, cut by nothing it is drawn in but its own box (Ctx::paint_field's), then as big as it is
  // about its top left and within what cuts it where it is drawn: as a block of the tree's is composed, view_blit)
  let (outer, outer_r, outer_s) = clip_at(clip_top())
  let i0 = self.ninst
  push_unclipped()
  // (its bar, where its words scroll in it, found where it is drawn as an old view's field's is (Ctx::bar_at): kept for
  // the pointer with the frame's bars where those are found alone)
  self.paint_field(
    fb,
    fn() {
      match sideways.get(fb.id) {
        Some(sw) if sw.max > 1.0 => {
          let b = self.side_bar(fb.id, fb.x, fb.y, fb.w, fb.h, fb.h + sw.max, sw.x, fn() {
            // (what is over it found where it is drawn, in the window, as what is over it is; kept clear of in its own
            // units, as big as it is laid out)
            let (top, foot) = self.floated(None, x, y, x + fb.w * s, y + fb.h * s)
            if s > 0.0 {
              (top / s, foot / s)
            } else {
              (top, foot)
            }
          })
          // (kept for the pointer where it is drawn: as big as it is drawn, about its top left, within what cuts it
          // where it is drawn, `outer`; drawn itself as placed, made as big with the rest of it: transform_insts. Kept
          // here whether or not the frame's targets were found before its paint: those find no field of the tree's,
          // view_targets)
          match b {
            Some(at) => self.next_bars.push(bar_drawn_at(at, laid, x, y, s, outer))
            None => ()
          }
          b
        }
        _ => None
      }
    },
    alpha,
    bar_targets=false,
    // (lit as the pointer is on its thumb where it is drawn, as the tree finds the field there: worked out of where the
    // pointer is and where its bar is drawn, nothing kept; painted again as the pointer goes, tree_fields_pointed)
    bar_pointed=fn(b) { tree_field_thumb_pointed(id, bar_drawn_at(b, laid, x, y, s, outer)) },
  )
  pop_clip()
  self.transform_insts(i0, self.ninst, ux, uy, s, s, x - ux, y - uy, outer, outer_r, outer_s)
}
