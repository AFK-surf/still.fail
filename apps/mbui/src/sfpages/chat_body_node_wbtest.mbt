// A chat's messages as nodes (chat_body_node.mbt) set beside the old view's (chat_list.mbt chat_list) on the same
// fixture's chat: the same words where they were and the same rectangles drawn in the list, as it opens, at its top and
// in its middle; on 小屏 (a finger's, narrow), 中屏 and 大屏 (a mouse's, wide); as its view changes at rest.
//
// Those comparisons are a sweep of screens at rest, as the app's sweeps are (mbui's AGENTS.md, Time in a test is
// declared): run at the default rate alone (@ui.test_at_a_rate), their Testers' frames not judged for how what moves
// goes (Tester::motion_unjudged); they go with the old list. Not looked into for that: at 24 and 7 frames a second the
// old page's shell draws more of its round buttons over the list (317 things, 310 at the default rate: its bell and its
// outline's button come in a frame after the frame its list was laid out in, chat-viz's at its top and its middle);
// judged at 60 and 120, the old list put at a row at once by Tester::scroll_to is said to step, which is no motion but
// how each is put where it is compared. What only the nodes' list does (the page before read in, what was sent going on
// by its key, 正在发送 as the old shows it) is held at every rate and judged.

///|
/// The fixture's chat (open_fixture_mode's: the first row's).
// kept across runs: a value
let body_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
// kept across runs: a value
let body_ws : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "" }

///|
/// The composer's room under the rows in both (what the list keeps clear for it: chat_list's `room`).
let body_room : Double = 96.0

///|
/// The room under a chat's rows (chat_list's Foot row's): the composer's, the list's foot, and where something waits to be
/// decided the bell's room over it (ask_clears).
fn body_foot(v : ChatView) -> Double {
  body_room + list_foot + (if @sfbase.ask_clears(v) { float_lift + float_side } else { 0.0 })
}

///|
/// A screen a body is drawn on: its name, width, height and platform (0 a mouse's, 2 a finger's).
fn body_screens() -> Array[(String, Double, Double, Int)] {
  [("小屏", 390.0, 844.0, 2), ("中屏", 900.0, 760.0, 0), ("大屏", 1280.0, 800.0, 0)]
}

///|
/// What chat_list draws of fixture `mode`'s chat (`src`), `w` by `h` on `platform`: the chat's view and its entries as
/// view_of_chat says them, or as `given` says where it says them; told to `seen` as each build reads them; `unjudged`
/// where it is a sweep's screen at rest.
fn body_old(
  src : Source,
  w : Double,
  h : Double,
  platform : Int,
  given? : @signals.Signal[(ChatView, Array[Entry])?] = @signals.signal(None),
  seen? : Ref[(ChatView, Array[Entry])?] = Ref(None),
  px? : Double = 2.0,
  unjudged? : Bool = false,
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let old = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        let (v, read) = match given.get() {
          Some(g) => (Some(g.0), g.1)
          None => {
            let (v, read, _) = @sfbase.view_of_chat(src, body_ref)
            (v, read)
          }
        }
        match v {
          Some(v) => {
            seen.val = Some((v, read))
            chat_list(c, src, body_ref, v, read, body_room, @sfbase.settings_core(src, body_ws))
          }
          None => ()
        }
      })
    },
    w~,
    h~,
    platform~,
    scale=px,
  )
  // (its rows on the device's pixels as every platform's host lays them: body_pixels)
  old.set_rows_on_pixels(true)
  // (a sweep's screen at rest: how what moves goes not judged on its frames, `unjudged`)
  old.motion_unjudged(unjudged)
  old
}

///|
/// What chat_body_node draws of chat view `view` (its entries `entries`, what was sent from here `sending`) over `src`,
/// `w` by `h` on `platform`; `place` where its list is asked to go; `made` told each row made; `unjudged` where it is a
/// sweep's screen at rest.
fn body_new(
  src : Source,
  w : Double,
  h : Double,
  platform : Int,
  view : @signals.Signal[ChatView],
  entries : @signals.Signal[Array[Entry]],
  place? : @view.ListPlace[String] = @view.ListPlace::new(),
  made? : (String, @view.View) -> Unit = fn(_, _) {  },
  begun? : (@view.View) -> Unit = fn(_) {  },
  px? : Double = 2.0,
  unjudged? : Bool = false,
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      let here : MessageNodeHere = {
        station: body_ref.station,
        session: body_ref.session,
        view: fn() { view.get() },
        width: fn() { w },
        tips,
        stint: fn() { 0 },
        jump: None,
      }
      root.box(fn(f) {
        f.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        chat_body_node(
          f,
          src,
          here,
          fn() { entries.get() },
          sending=fn() { @sfbase.sending_now(body_ref.station + "\u{1}" + body_ref.session) },
          core=Some(@sfbase.settings_core(src, body_ws)),
          foot=fn() { body_foot(view.get()) },
          place~,
          made~,
        )
        |> ignore
        begun(f)
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w~,
    h~,
    platform~,
    scale=px,
  )
  // (its rows on the device's pixels as every platform's host lays them: body_pixels)
  t.set_rows_on_pixels(true)
  // (a sweep's screen at rest: how what moves goes not judged on its frames, `unjudged`)
  t.motion_unjudged(unjudged)
  t
}

///|
/// Whether something the old view draws at `x` (`rw` by `rh`: a rectangle's; 0 a word's) in a window `w` wide floats
/// over its chat's list and is none of its rows: the way to the newest, the bell, the outline's round buttons (each a
/// float_side square, float_right in from the pane's end: float_box's) and the outline's rail at a wide pane's end,
/// past where any row reaches (row_side_least from it). Those are the page's shell's, drawn over the list, not the
/// list's (the nodes' list draws none of them yet); they go once the page's shell is made of nodes over it.
fn body_floats(w : Double, x : Double, rw : Double, rh : Double) -> Bool {
  let right = (w - composer_width(w)) / 2.0 + float_in
  (w > chat_narrow_w && x >= w - row_side_least) ||
  (rw == float_side && rh == float_side && body_r(x) == body_r(w - right - float_side))
}

///|
/// A place to a hundredth of a point (the old view's sums leave tails the nodes' do not).
fn body_r(x : Double) -> Double {
  (x * 100.0).round() / 100.0
}

///|
/// Something a Tester draws: where its top is, how high it is, its line as it is drawn with its top `y` (its words or
/// its rectangle, each place and size: body_r's).
priv struct BodyItem {
  y : Double
  h : Double
  line : (Double) -> String
}

///|
/// What a Tester draws, each a BodyItem (what of a row is drawn out of the window too: the row's, whole): not what
/// floats over the old view's list (`old`: body_floats'), nor a rectangle drawn with no colour (markdown_node's under
/// a list's mark, which shows nothing). How many things floated, apart.
fn body_items(t : @ui.Tester, w : Double, old : Bool) -> (Array[BodyItem], Int) {
  let items : Array[BodyItem] = []
  let mut floats = 0
  for x in t.words() {
    if old && body_floats(w, x.1, 0.0, 0.0) {
      floats += 1
      continue
    }
    items.push({
      y: x.2,
      h: x.4,
      line: fn(y) { "\{x.0}@\{body_r(x.1)},\{body_r(y)} \{body_r(x.3)}x\{body_r(x.4)} a\{x.5}" },
    })
  }
  for d in t.drawn_rects() {
    if (d.4 & 0xFFL) == 0L {
      continue
    }
    if old && body_floats(w, d.0, d.2, d.3) {
      floats += 1
      continue
    }
    items.push({ y: d.1, h: d.3, line: fn(y) { "\{body_r(d.0)},\{body_r(y)} \{body_r(d.2)}x\{body_r(d.3)} \{d.4}" } })
  }
  (items, floats)
}

///|
/// A row as a Tester draws it: its key, its top in the window, how high it is laid out (on whole pixels: row_slot's),
/// what is drawn in it, each from its top.
priv struct BodyRow {
  key : String
  top : Double
  h : Double
  items : Array[BodyItem]
}

///|
/// Row `r`'s lines, what is drawn in it from its top, in order: those seen between `lo` and `hi` from its top (what
/// both lists show of it: a list draws only what is in its window); those `from` or more down from its top drawn `by`
/// further down.
fn body_row_lines(
  r : BodyRow,
  lo? : Double = -1.0e9,
  hi? : Double = 1.0e9,
  from? : Double = 1.0e9,
  by? : Double = 0.0,
) -> Array[String] {
  let lines : Array[String] = []
  for i in r.items {
    let y0 = i.y - r.top
    let y = if y0 >= from { y0 + by } else { y0 }
    if y + i.h > lo && y < hi {
      lines.push((i.line)(y))
    }
  }
  lines.sort()
  lines
}

///|
/// What a Tester draws of a chat's list in its window: its rows shown, top to bottom; what is drawn in none of them
/// (from the window's top); how many things floated over it (body_floats'); the most bytes its host held for decodes.
priv struct BodyDrawn {
  rows : Array[BodyRow]
  out : Array[String]
  floats : Int
  bytes : Int
}

///|
/// What Tester `t` (the old view's where `old`) draws in its window `w` by `h`, its list's rows where `rows` says they
/// are (each its key, top and height), those seen in it, each thing drawn in the row its top is in; what is in none
/// of them, as far as it is seen.
fn body_drawn(t : @ui.Tester, w : Double, h : Double, rows : Array[(String, Double, Double)], old? : Bool = false) -> BodyDrawn {
  let (items, floats) = body_items(t, w, old)
  let shown = rows.filter(fn(r) { r.2 > 0.0 && r.1 + r.2 > 0.0 && r.1 < h })
  shown.sort_by(fn(a, b) { a.1.compare(b.1) })
  let drawn : Array[BodyRow] = shown.map(fn(r) { { key: r.0, top: r.1, h: r.2, items: [] } })
  let out : Array[String] = []
  for i in items {
    match drawn.iter().find_first(fn(r) { i.y >= r.top && i.y < r.top + r.h }) {
      Some(r) => r.items.push(i)
      None => if i.y + i.h > 0.0 && i.y < h { out.push((i.line)(i.y)) }
    }
  }
  out.sort()
  { rows: drawn, out, floats, bytes: t.host_image_bytes_most() }
}

///|
/// Fixture `mode`'s chat's source with the page before held back: its ask (chat.older) never answered, so neither
/// list reads a page in as it comes to its top and what both show is the screen before that answer, at every rate of
/// frames (a page read in is body_page_read's).
fn body_src(mode : String) -> Source {
  let src = @sffixture.fixture(mode)
  { ..src, call: fn(name, params, done) { if name != "chat.older" { (src.call)(name, params, done) } } }
}

///|
/// The nodes' key of each of chat view `v`'s entries `read` (chat_body_rows'; its Foot "foot", the list's room under
/// its rows and no row of the nodes').
fn body_keys(v : ChatView, read : Array[Entry]) -> Array[String] {
  let keys = chat_body_rows({ sent: {}, sent_as: {} }, v, read, []).keys
  let out : Array[String] = []
  let mut j = 0
  for e in read {
    if e is Foot {
      out.push("foot")
    } else if e is Top {
      out.push("top")
    } else {
      out.push(keys[j])
      j += 1
    }
  }
  out
}

///|
/// The old list's rows (Tester::rows: each its entry's place in `read`, its top, its height) by the nodes' keys, its
/// Foot not one (body_keys').
fn body_old_rows(old : @ui.Tester, v : ChatView, read : Array[Entry]) -> Array[(String, Double, Double)] {
  let keys = body_keys(v, read)
  old
  .rows()
  .filter_map(fn(r) {
    let k = keys[r.0]
    if k == "foot" {
      None
    } else {
      Some((k, r.1, r.2))
    }
  })
}

///|
/// The nodes' rows, each the node its row was made in (`views`, chat_body_node's `made`) while it is: its key, its top,
/// its height on whole pixels `g` a point (row_slot's, as the list lays its blocks on the pixels).
fn body_new_rows(views : Map[String, @view.View], g : Double) -> Array[(String, Double, Double)] {
  views
  .iter()
  .filter_map(fn(kv) {
    if kv.1.alive() {
      let r = kv.1.placed_window_now()
      Some((kv.0, r.1, (r.3 * g - 0.000001).ceil() / g))
    } else {
      None
    }
  })
  .collect()
}

///|
/// One case of the comparison: its name, its fixture's mode, the screen's width, what each row of the list is by its
/// key (chat_body_rows'), the row both lists were put at (None: at the list's end), what each draws, the nodes' audit
/// and the words their boxes do not hold.
priv struct BodyCase {
  name : String
  mode : String
  w : Double
  h : Double
  entries : Map[String, Entry]
  anchor : String?
  paged : Bool
  old : BodyDrawn
  new : BodyDrawn
  faults : Array[String]
  outgrown : Array[String]
}

///|
/// The fixture's modes of a chat (sffixture's, corner_modes' chat-* that put nothing over the chat but its rows' own
/// states): its first row's chat as each says it.
fn body_modes() -> Array[String] {
  [
    "chat", "chat-ask-end", "chat-working", "chat-done", "chat-cards", "chat-quote", "chat-image-coming", "chat-download",
    "chat-sending", "chat-failed", "chat-need", "chat-login", "chat-rig", "chat-vault", "chat-phone", "chat-md", "chat-long",
    "chat-letters", "chat-viz", "chat-screens", "chat-update", "chat-agent",
  ]
}

///|
/// Fixture `mode`'s chat on screen `s` with its list at `at` ("end": as it opens, at its end; "top"; "mid": its middle
/// row at the window's top), the system's words at `scale`, as the old view draws it and then as the nodes do. The
/// nodes' list put where the old one has the row it was put at: the same key, as far from the window's top (its
/// ListPlace::bring); where the old list read the page before in as it came to its top, the nodes' given the same view
/// once at its top, only its keys changing, what it shows held where it is by the list. None where the old view has
/// no view of the chat (it waits for it).
fn body_both(mode : String, s : (String, Double, Double, Int), at : String, scale? : Double = 1.0) -> BodyCase? {
  @sfbase.reset()
  reset()
  let src = body_src(mode)
  let seen : Ref[(ChatView, Array[Entry])?] = Ref(None)
  let old = body_old(src, s.1, s.2, s.3, seen~, unjudged=true)
  old.set_font_scale(scale)
  // (what was in the outbox as the chat opened: the old view's 正在发送 from its row's first build, the nodes' at once,
  // sent long since: both so once that is past)
  let rest = @ui.move_most_ms + (if mode == "chat-sending" { sending_shows_ms } else { 0.0 })
  old.run_for(rest)
  guard seen.val is Some((v0, read0)) else { return None }
  let keys0 = body_keys(v0, read0)
  let at_i = match at {
    "top" => 0
    "mid" => read0.length() / 2
    _ => read0.length() - 2
  }
  if at != "end" {
    old.scroll_to(at_i)
    old.run_for(@ui.move_most_ms)
  }
  let (v, read) = seen.val.unwrap_or((v0, read0))
  let paged = body_keys(v, read) != keys0
  let put = keys0[at_i]
  let old_rows = body_old_rows(old, v, read)
  let was = body_drawn(old, s.1, s.2, old_rows, old=true)
  // (put at its row's top, as Tester::scroll_to puts it, where a page read in after moved it)
  let put_y = if paged {
    0.0
  } else {
    match old_rows.iter().find_first(fn(r) { r.0 == put }) {
      Some(r) => r.1
      None => 0.0
    }
  }
  @sfbase.reset()
  reset()
  let src = body_src(mode)
  let view = @signals.signal(v0)
  let entries = @signals.signal(read0)
  let views : Map[String, @view.View] = Map([])
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  let t = body_new(src, s.1, s.2, s.3, view, entries, place~, made=fn(k, p) { views[k] = p }, unjudged=true)
  t.set_font_scale(scale)
  t.run_for(rest)
  if at != "end" {
    // (its top's room the list's head and what covers its top (list_top, the chat's bar's room): at its top, its first
    // row under it; else the row at its top as the old list had it, `put_y` under the list's window's top, a bring's
    // offset being from under that cover)
    if put == "top" {
      place.bring(keys0.iter().find_first(fn(k) { k != "top" }).unwrap(), offset=-put_y)
    } else {
      place.bring(put, offset=list_top - put_y)
    }
    t.run_for(@ui.move_most_ms)
  }
  if paged {
    view.set(v)
    entries.set(read)
    t.run_for(@ui.move_most_ms)
  }
  let now = body_drawn(t, s.1, s.2, body_new_rows(views, 2.0))
  // (where both are put: the list's end; the row put at the top; once a page came in over it, the row the old list
  // held where it was, its first message then)
  let anchor = if at == "end" {
    None
  } else if paged {
    keys0.iter().find_first(fn(k) { k.has_prefix("m:") || k.has_prefix("o:") })
  } else {
    Some(put)
  }
  Some({
    name: "\{mode} \{s.0} \{at}" + (if scale != 1.0 { " at \{scale}" } else { "" }),
    mode,
    w: s.1,
    h: s.2,
    entries: body_entries(v, read),
    anchor,
    paged,
    old: was,
    new: now,
    faults: t.audit(),
    outgrown: t.fixed_outgrown(),
  })
}

///|
/// What each row of chat view `v`'s entries `read` is, by its key (chat_body_rows').
fn body_entries(v : ChatView, read : Array[Entry]) -> Map[String, Entry] {
  let entries : Map[String, Entry] = Map([])
  for k, r in chat_body_rows({ sent: {}, sent_as: {} }, v, read, []).rows {
    entries[k] = r.entry
  }
  entries
}

///|
/// The row of what was said elsewhere, laid out narrow, its line of where it went route_line_down further down than the
/// old view's (sent_elsewhere_node: as far under the head as keeps the time's room and the place's whole, the
/// coordinator, 2026-11-11): the old row's lines from under its time on that much further down, the row that much
/// higher. Kept as long as the old view draws it so (it goes with the old row).
fn body_route_down(c : BodyCase, o : BodyRow, n : BodyRow, lo : Double, hi : Double) -> Bool {
  guard c.w <= chat_narrow_w && c.entries.get(o.key) is Some(Sent({ time: Some(t), .. })) else { return false }
  let d = route_line_down()
  guard body_r(n.h - o.h) == body_r(d) else { return false }
  guard o.items.iter().find_first(fn(i) { (i.line)(0.0).has_prefix(t.ago + "@") }) is Some(time) else {
    return false
  }
  // (from a line of the old row's under its time's top on: where its line of where it went is drawn, at any size of
  // words)
  let want = body_row_lines(n, lo~, hi~)
  o.items
  .iter()
  .filter(fn(i) { i.y > time.y })
  .any(fn(i) { body_row_lines(o, lo~, hi~, from=i.y - o.top, by=d) == want })
}

///|
/// Where the old view held a message's picture under the list's top as a long one scrolled past (message.mbt's
/// c.stick, avatar_held_at, its picture message_avatar_down under it): the picture's top in the window, as far down
/// as its row lets it.
let body_held_y : Double = avatar_held_at + 3.0

///|
/// A row whose picture the old view held under the list's top (c.stick) as it went past: what differs between the two
/// is only that picture and its mark, the same each but the old one's moved down the same way, the picture no further
/// down than where it is held (body_held_y; less where its row's foot keeps it up). The nodes' list holds none yet (a
/// list's ability, the list's line's; the coordinator, 2026-11-11); goes once it does.
fn body_held_picture(o : BodyRow, n : BodyRow, lo : Double, hi : Double) -> Bool {
  guard body_r(o.h) == body_r(n.h) else { return false }
  let (only_o, only_n) = body_apart(body_row_lines(o, lo~, hi~), body_row_lines(n, lo~, hi~))
  guard only_o.length() > 0 else { return false }
  let os = o.items.filter(fn(i) { only_o.contains((i.line)(i.y - o.top)) })
  guard os.length() == only_o.length() else { return false }
  let top = os.fold(init=1.0e9, fn(m, i) { if i.y < m { i.y } else { m } })
  guard body_r(top) <= body_r(body_held_y) else { return false }
  // (each the same thing in the nodes' row, the same but for how far down, seen there or not)
  let mut by = 0.0
  let mut first = true
  let theirs : Array[String] = []
  for i in os {
    guard n.items.iter().find_first(fn(j) { (j.line)(0.0) == (i.line)(0.0) }) is Some(j) else { return false }
    let d = body_r(i.y - o.top - (j.y - n.top))
    if first {
      by = d
      first = false
    } else if d != by {
      return false
    }
    theirs.push((j.line)(j.y - n.top))
  }
  by > 0.0 && only_n.iter().all(fn(l) { theirs.contains(l) })
}

///|
/// At the system's words set larger, a screen's card with its preview (chat-screens' m:ts12, the one such row): its
/// title's line and its line under it each as high as their words (23.6 and 20.2 at 1.3, where the old card keeps them
/// 20 and 16 and its words overlap), so the card and its row 8 higher (7.8, laid to the half). Meant, as
/// body_grown_capsule's: every box holds its words. At the system's own size the row is the old one's, compared whole.
fn body_grown_card(c : BodyCase, o : BodyRow, n : BodyRow) -> Bool {
  c.mode == "chat-screens" && o.key == "m:ts12" && body_r(n.h - o.h) == body_r(8.0)
}

///|
/// At the system's words set larger, a picture's pill of how far and a video's capsule as high as their words' line
/// (message_media_node's coming_pill_high, the library's video_capsule_node by box_at), each still concentric with its
/// corner: what differs in the row is only those, each the old one's ground (18 high, its words over its foot) as high
/// as the line its words are drawn in and as much further in from the corner as half of what it grew, its words
/// with it. Meant (BRIEF: words cut at 1.3 set right by what the library has).
fn body_grown_capsule(o : BodyRow, n : BodyRow, lo : Double, hi : Double) -> Bool {
  guard body_r(o.h) == body_r(n.h) else { return false }
  let (only_o, only_n) = body_apart(body_row_lines(o, lo~, hi~), body_row_lines(n, lo~, hi~))
  guard only_o.length() > 0 && only_o.length() == only_n.length() else { return false }
  let os = o.items.filter(fn(i) { only_o.contains((i.line)(i.y - o.top)) })
  let ns = n.items.filter(fn(i) { only_n.contains((i.line)(i.y - n.top)) })
  guard os.length() == ns.length() else { return false }
  // (each ground: the video's shade, 18 high; its words' line how high the words over it are)
  let grounds = os.filter(fn(i) { (i.line)(0.0).has_suffix(" 166") })
  guard grounds.length() > 0 else { return false }
  grounds.iter().all(fn(g) {
    // (its words: over it, as high as their line)
    guard os.iter().find_first(fn(w) { !(w.line)(0.0).has_suffix(" 166") && w.y < g.y + g.h && w.y + w.h > g.y }) is Some(w) else {
      return false
    }
    let grew = w.h - g.h
    let half = grew / 2.0
    // (the nodes' ground: as high as its words, half that further up and in; its words as far in with it)
    ns.iter().any(fn(j) { body_r(j.h) == body_r(w.h) && body_r(j.y - n.top) == body_r(g.y - o.top - half) && (j.line)(0.0).has_suffix(" 166") }) &&
    ns.iter().any(fn(j) { body_r(j.h) == body_r(w.h) && body_r(j.y - n.top) == body_r(w.y - o.top) && !(j.line)(0.0).has_suffix(" 166") }) &&
    grew > 0.0
  })
}

///|
/// Whether a fault of the nodes' audit is a press's room cut by the window's top (a row half over it, as a list
/// scrolled shows one): what is pressed there is measured as far as the window shows it.
fn body_cut_at_top(f : String) -> Bool {
  guard f.has_prefix("room: ") else { return false }
  match f.find("window's tree's at ") {
    Some(i) => {
      let rest = f.exact_view(start=i + "window's tree's at ".length()).to_owned()
      match rest.find(",") {
        Some(j) => rest.exact_view(start=j + 1).to_owned().has_prefix("-")
        None => false
      }
    }
    None => false
  }
}

///|
/// The rows not compared, each why: what the window's tree cannot draw yet. Each drawn by something else, its height
/// its own, held exactly (body_unmade_dh); each goes once the framework has it.
fn body_unmade(c : BodyCase, key : String) -> String? {
  match c.entries.get(key) {
    Some(Said(m)) if m.placed.iter().any(fn(n) { is_viz(n) }) =>
      // (its page drawn in its row as the old one's, as high: what is drawn over its view as it comes is not compared)
      Some("an HTML page it places, as high, not compared (P12)")
    _ => None
  }
}

///|
/// How much higher the nodes' row is than the old one (lower, less than 0), of the rows not compared (body_unmade), by
/// fixture mode and key, on every screen: held exactly.
fn body_unmade_dh(mode : String, key : String) -> Double? {
  match (mode, key) {
    ("chat-viz", "m:ts12") => Some(0.0)
    _ => None
  }
}

///|
/// Whether a fault of the nodes' audit is one known of a row's head (message_head_node.mbt's time, pressed in a room
/// short of a press's least where the old arrangement has it: 「刚刚」, 「昨天」), the agent rows' test's rule
/// (message_agent_node_wbtest's ag_rooms): the old arrangement's, held exactly, only to fall.
fn body_time_short(f : String) -> Bool {
  f.has_prefix("room: ") && f.contains("stillfail/src/sfpages/message_head_node.mbt:") && f.contains("to be pressed in, under")
}

///|
/// Whether a fault of the nodes' audit is a code block of an agent's words pressed in its own height, 42, where a
/// finger's press is 44 (markdown_node's, 小屏): the old one's the same height, drawn the same; the old arrangement's,
/// held exactly, only to fall.
fn body_code_short(f : String) -> Bool {
  f.has_prefix("room: ") && f.contains("stillfail/src/sf/markdown_node.mbt:") && f.contains("to be pressed in, under 44")
}

///|
/// How case `c` differs, row by row: what is none of the differences known and said here goes in `said`, a line
/// each; how many of each kind known it has, in `known`. The rows both show (a row only one shows only at the
/// window's edge, as the rows' heights between came apart); each as high and drawn the same, or one of the kinds known
/// (body_route_down, body_held_picture, body_unmade); its top where the old one's is, moved only by how much higher the
/// rows between it and where both were put came to be. What is drawn in no row, the same; the bytes its host held,
/// the same; the nodes' audit none but body_time_short's and body_code_short's.
fn body_cmp(c : BodyCase, known : Map[String, Int], said : Array[String]) -> Unit {
  let tally = fn(kind : String, n : Int) {
    if n > 0 {
      known[kind] = known.get(kind).unwrap_or(0) + n
    }
  }
  let ok = c.old.rows.map(fn(r) { r.key })
  let nk = c.new.rows.map(fn(r) { r.key })
  // (the page before held back by both sources: none read in)
  if c.paged {
    said.push(c.name + ": a page read in, held back (body_src)")
    return
  }
  let both = ok.filter(fn(k) { nk.contains(k) })
  let at_edge = fn(keys : Array[String]) {
    // (those only it shows: before all both show, or after)
    match (both.get(0), both.last()) {
      (Some(first), Some(last)) => {
        let i = keys.search(first).unwrap()
        let j = keys.search(last).unwrap()
        keys[i:j + 1].to_owned() == both
      }
      _ => false
    }
  }
  if !at_edge(ok) || !at_edge(nk) {
    said.push(c.name + ": rows " + ok.join(" ") + " | " + nk.join(" "))
    return
  }
  tally("a row one shows at the window's edge, the rows' heights between apart", ok.length() + nk.length() - 2 * both.length())
  let olds = c.old.rows.filter(fn(r) { both.contains(r.key) })
  let news = c.new.rows.filter(fn(r) { both.contains(r.key) })
  let dh : Array[Double] = []
  for i, o in olds {
    let n = news[i]
    dh.push(n.h - o.h)
    match body_unmade(c, o.key) {
      Some(why) => {
        match body_unmade_dh(c.mode, o.key) {
          Some(d) if body_r(d) == body_r(n.h - o.h) => ()
          _ => said.push(c.name + " " + o.key + ": " + why + ", \{body_r(n.h - o.h)} higher")
        }
        tally(why, 1)
        continue
      }
      None => ()
    }
    // (what of it both show)
    let lo = dmax(-o.top, -n.top)
    let hi = dmin(c.h - o.top, c.h - n.top)
    if body_r(n.h) == body_r(o.h) && body_row_lines(o, lo~, hi~) == body_row_lines(n, lo~, hi~) {
      continue
    }
    if body_route_down(c, o, n, lo, hi) {
      tally("where it went, narrow, route_line_down further down (meant)", 1)
    } else if body_held_picture(o, n, lo, hi) {
      tally("its picture held under the list's top (c.stick)", 1)
    } else if body_grown_capsule(o, n, lo, hi) {
      tally("a pill or a capsule as high as its words at a larger size (meant)", 1)
    } else if body_grown_card(c, o, n) {
      tally("a screen's card's lines as high as their words at a larger size (meant)", 1)
    } else {
      let (a, b) = body_apart(body_row_lines(o, lo~, hi~), body_row_lines(n, lo~, hi~))
      said.push(
        c.name + " " + o.key + ": \{body_r(o.h)} / \{body_r(n.h)} high, top \{body_r(o.top)} / \{body_r(n.top)}\n    OLD " +
        a.join("\n    OLD ") +
        "\n    NEW " +
        b.join("\n    NEW "),
      )
    }
  }
  // (each row where the old one is, moved by what the rows between it and where both are put grew by: up from the
  // list's end, down from the row put at the top)
  let keys = olds.map(fn(r) { r.key })
  let a = match c.anchor {
    Some(k) =>
      match keys.search(k) {
        Some(j) => j
        None => {
          said.push(c.name + ": the row both are put at, \{k}, not seen")
          return
        }
      }
    None => olds.length()
  }
  for i, o in olds {
    let mut want = 0.0
    if i < a {
      for j in i..<a {
        want -= dh[j]
      }
    } else {
      for j in a..<i {
        want += dh[j]
      }
    }
    let moved = news[i].top - o.top
    // (its top's room the list's head now: a chat too short to fill what shows has it at the top of what shows, its
    // rows at the foot, the room between them, where the old list had it over its rows (decided, 2026-11-12:
    // View::scrolls_window's head with from_end))
    if o.key == "top" && news[i].top == 0.0 && o.top > 0.0 {
      continue
    }
    if body_r(moved) != body_r(want) {
      said.push(c.name + " " + o.key + ": its top \{body_r(o.top)} / \{body_r(news[i].top)}, moved \{body_r(want)} by the rows' heights")
    }
  }
  let (oo, no) = body_apart(c.old.out, c.new.out)
  if oo.length() > 0 || no.length() > 0 {
    said.push(c.name + ": in no row\n    OLD " + oo.join("\n    OLD ") + "\n    NEW " + no.join("\n    NEW "))
  }
  tally("floats over the list (the page's shell's)", c.old.floats)
  if c.old.bytes != c.new.bytes {
    said.push(c.name + ": its host held \{c.old.bytes} / \{c.new.bytes} bytes")
  }
  tally("its head's time pressed short (message_head_node's)", c.faults.filter(body_time_short).length())
  tally("a code block pressed in 42 (markdown_node's)", c.faults.filter(body_code_short).length())
  tally("a press cut by the window's top", c.faults.filter(body_cut_at_top).length())
  for f in c.faults {
    if !body_time_short(f) && !body_code_short(f) && !body_cut_at_top(f) {
      said.push(c.name + ": " + f)
    }
  }
}

///|
/// What one drawing has that the other has not, a line each (what is twice in one and once in the other is once in
/// what it has more), `a`'s then `b`'s.
fn body_apart(a : Array[String], b : Array[String]) -> (Array[String], Array[String]) {
  let count : Map[String, Int] = Map([])
  for l in a {
    count[l] = count.get(l).unwrap_or(0) + 1
  }
  for l in b {
    count[l] = count.get(l).unwrap_or(0) - 1
  }
  let only_a : Array[String] = []
  let only_b : Array[String] = []
  for l, n in count {
    for _ in 0..<n {
      only_a.push(l)
    }
    for _ in 0..<(-n) {
      only_b.push(l)
    }
  }
  only_a.sort()
  only_b.sort()
  (only_a, only_b)
}

///|
/// The known kinds' counts, a line each: all but what floats over the old page's list (the way to the newest, the
/// bell, the outline: the old page's shell's own, left out of what is set side by side by their rectangles), whose
/// count is the old page's and changes as it does (#5667 made a chat open on fewer messages: 34 came to 104 in one
/// test), so it is told for people, never held.
fn body_known_said(known : Map[String, Int]) -> String {
  let lines = known
    .iter()
    .filter(fn(kv) { !kv.0.has_prefix("floats over the list") })
    .map(fn(kv) { "\{kv.0}: \{kv.1}" })
    .collect()
  lines.sort()
  lines.join("\n")
}

///|
/// Which of the comparisons' known counts (body_cmp's kinds) is held: the default size's over every fixture, screen and
/// place; 1.3's on 小屏 at the end; as the chat's view changes.
priv enum BodyHeld {
  HeldMain
  HeldLarge
  HeldChanges
}

///|
/// The counts held for `which`, a line each as body_known_said says them. Each kind is one of body_cmp's, its reason
/// where it is decided; each goes as what it waits for comes (the page's shell over the list made of nodes: floats; the
/// list holding a picture under its top: c.stick; holding what is read as a page comes in over it; P12), only
/// to fall.
fn body_held(which : BodyHeld) -> String {
  let lines = match which {
    HeldMain => [
    "an HTML page it places, as high, not compared (P12): 6",
    "its picture held under the list's top (c.stick): 43",
  ]
    HeldLarge => [
    "a pill or a capsule as high as its words at a larger size (meant): 2",
    "a screen's card's lines as high as their words at a larger size (meant): 1",
    "an HTML page it places, as high, not compared (P12): 1",
  ]
    // (its turn over no more compared with the old list, which came down there (the changes' sweep, turned on
    // purpose): one of the 7 counted before was of that step)
    HeldChanges => ["its picture held under the list's top (c.stick): 6"]
  }
  lines.sort()
  lines.join("\n")
}

///|
test "a chat's messages made once as nodes are drawn as the old list drew them, each fixture's chat on 小屏, 中屏 and 大屏, at its end, its top and its middle" {
  // (a sweep of screens at rest: the default rate's alone, its frames not judged; the file's head says why)
  if @ui.test_at_a_rate() {
    return
  }
  let said : Array[String] = []
  let known : Map[String, Int] = Map([])
  let mut cases = 0
  let mut same = 0
  for mode in body_modes() {
    for s in body_screens() {
      for at in ["end", "top", "mid"] {
        match body_both(mode, s, at) {
          None => said.push("\{mode} \{s.0} \{at}: no view")
          Some(c) => {
            cases += 1
            let before = said.length()
            let kinds = known.copy()
            body_cmp(c, known, said)
            if said.length() == before && known.length() == kinds.length() && known.iter().all(fn(kv) { kinds.get(kv.0) == Some(kv.1) }) {
              same += 1
            }
          }
        }
      }
    }
  }
  assert_eq(said, [], msg=said.join("\n"))
  // (held exactly: each kind its count over the cases, 22 fixtures × 3 screens × 3 places, each only to fall; how
  // many of them are the same throughout is told with it, not held: it moves with the old page's floats)
  let got = "\{same} of \{cases} the same\n" + body_known_said(known)
  assert_eq(body_known_said(known), body_held(HeldMain), msg=got)
}

///|
test "a chat's messages made once as nodes at the system's words set to 1.3, on 小屏: as the old list drew them, every box holding its words" {
  // (a sweep of screens at rest: the default rate's alone, its frames not judged; the file's head says why)
  if @ui.test_at_a_rate() {
    return
  }
  let said : Array[String] = []
  let known : Map[String, Int] = Map([])
  for mode in body_modes() {
    match body_both(mode, body_screens()[0], "end", scale=1.3) {
      None => said.push("\{mode} 1.3: no view")
      Some(c) => {
        body_cmp(c, known, said)
        for f in c.outgrown {
          said.push(c.name + ": " + f)
        }
      }
    }
  }
  assert_eq(said, [], msg=said.join("\n"))
  assert_eq(body_known_said(known), body_held(HeldLarge), msg=body_known_said(known))
}

///|
/// A paragraph of the core's Markdown saying `words`.
fn body_md(words : String) -> Json {
  Json::array([Json::array([Json::string("p"), Json::array([Json::string(words)])])])
}

///|
/// What a chat's view comes to, step by step, from the fixture's (`v`): its name and the view after it.
fn body_steps(v : ChatView) -> Array[(String, ChatView)] {
  let last = v.messages[v.messages.length() - 1]
  let came : Message = {
    ..last,
    seq: 900.0,
    ts: "ts900",
    text: "又来了一条：列表的高度也量过了。",
    md: Some(body_md("又来了一条：列表的高度也量过了。")),
    decision: None,
    options: None,
    card: None,
    asked: false,
    followed: false,
    joined: false,
  }
  let v1 = { ..v, messages: v.messages + [came] }
  let changed = { ..came, text: "改过的字：列表的高度量过一次就记住，换了宽度再量，滚到时才量没量过的那些行。", md: Some(body_md("改过的字：列表的高度量过一次就记住，换了宽度再量，滚到时才量没量过的那些行。")) }
  let v2 = { ..v1, messages: v.messages + [changed] }
  let a = v2.agents[0]
  let v3 = { ..v2, agents: [{ ..a, status: "running", started: true }] + v2.agents[1:].to_owned() }
  let v4 = { ..v3, agents: v2.agents }
  let failed : Outgoing = { ..chat_body_no_out, id: "o-9", text: "这条没发出去", state: "failed", error: "station 不在线" }
  let v5 = { ..v4, outbox: [failed] }
  let v6 = { ..v5, outbox: [{ ..failed, state: "sent", error: "", seq: 901.0, time: last.time }] }
  let mine : Message = {
    ..came,
    seq: 901.0,
    ts: "ts901",
    text: "这条没发出去",
    md: None,
    author_kind: "person",
    mine: true,
    outgoing: "o-9",
    by: { ..came.by, name: "林", agent: "" },
  }
  let v7 = { ..v6, outbox: [], messages: v2.messages + [mine] }
  [
    ("a message comes", v1),
    ("its words change", v2),
    ("its agent at work", v3),
    ("its turn over", v4),
    ("one not sent", v5),
    ("sent after all", v6),
    ("the core has it as a message", v7),
  ]
}

///|
test "a chat's messages as nodes as its view changes, at rest after each: the same as the old list's, a row made only as it comes, what was not sent going on by its key" {
  // (a sweep of screens at rest: the default rate's alone, its frames not judged; the file's head says why)
  if @ui.test_at_a_rate() {
    return
  }
  let said : Array[String] = []
  let known : Map[String, Int] = Map([])
  for s in [body_screens()[0], body_screens()[2]] {
    @sfbase.reset()
    reset()
    let src = @sffixture.fixture("chat")
    let seen : Ref[(ChatView, Array[Entry])?] = Ref(None)
    let given : @signals.Signal[(ChatView, Array[Entry])?] = @signals.signal(None)
    let old = body_old(src, s.1, s.2, s.3, seen~, given~, unjudged=true)
    old.run_for(@ui.move_most_ms)
    let v0 = seen.val.unwrap().0
    let steps = body_steps(v0)
    let olds : Array[BodyDrawn] = []
    for st in steps {
      let read = @sfbase.entries_of(st.1)
      given.set(Some((st.1, read)))
      old.run_for(@ui.move_most_ms)
      olds.push(body_drawn(old, s.1, s.2, body_old_rows(old, st.1, read), old=true))
    }
    @sfbase.reset()
    reset()
    let src = @sffixture.fixture("chat")
    let view = @signals.signal(v0)
    let entries = @signals.signal(@sfbase.entries_of(v0))
    let made : Map[String, Int] = Map([])
    let views : Map[String, @view.View] = Map([])
    let t = body_new(
      src,
      s.1,
      s.2,
      s.3,
      view,
      entries,
      made=fn(k, p) {
        made[k] = made.get(k).unwrap_or(0) + 1
        views[k] = p
      },
      unjudged=true,
    )
    t.run_for(@ui.move_most_ms)
    let mut before : BodyDrawn? = None
    for i, st in steps {
      let was = made.copy()
      let read = @sfbase.entries_of(st.1)
      view.set(st.1)
      entries.set(read)
      t.run_for(@ui.move_most_ms)
      let drawn = body_drawn(t, s.1, s.2, body_new_rows(views, 2.0))
      // (its turn over, its agent's line gone with nothing in its place: turned on purpose from the old list's, which
      // comes down by the line's height; the page made as nodes leaves its room under the last row, each row that stays
      // where it was at the step before (the user, 2026-11-12: a turn that ends with no answer must not carry what is
      // read up and let it fall back; #5914's leaves_room; the coordinator of the migration agreed the old page's cases
      // of it turn on purpose, 2026-11-13). The room as tall as the line was as the step before showed it)
      if st.0 == "its turn over" {
        match before {
          Some(b) => body_turn_over_held(s.0 + " " + st.0, b, drawn, said)
          None => said.push(s.0 + " " + st.0 + ": no step before it")
        }
      } else {
        body_cmp(
          {
            name: "\{s.0} \{st.0}",
            mode: "chat",
            w: s.1,
            h: s.2,
            entries: body_entries(st.1, read),
            anchor: None,
            paged: false,
            old: olds[i],
            new: drawn,
            faults: [],
            outgrown: [],
          },
          known,
          said,
        )
      }
      before = Some(drawn)
      // what was made for it: only the row that came (or came to be another kind of row), and a row the list let go
      // of as it went out of view coming into it again; none made again for nothing
      let again = made.iter().filter(fn(kv) { was.get(kv.0).unwrap_or(0) != kv.1 }).map(fn(kv) { kv.0 }).collect()
      let want = match st.0 {
        "a message comes" => ["m:ts900"]
        "its agent at work" => ["act:s-c1"]
        // (its agent's line gone leaving its room: nothing comes down, so none comes into view to be made; the old
        // list's case, which came down and made m:ts7 again on a phone's window, turned on purpose (above))
        "one not sent" => ["o:o-9"]
        // (what was sent from here as the core's message: its key the outbox entry's, its row the same, none made: what
        // is sent and what it becomes are one row, its words' node kept so a finger's pick over them stays)
        _ => []
      }
      again.sort()
      if again != want {
        said.push("\{s.0} \{st.0}: rows made " + again.join(" ") + ", wanted " + want.join(" "))
      }
    }
    let faults = t.audit()
    body_tally_time(known, faults)
    for f in faults {
      if !body_time_short(f) {
        said.push("\{s.0}: " + f)
      }
    }
  }
  assert_eq(said, [], msg=said.join("\n"))
  assert_eq(body_known_said(known), body_held(HeldChanges), msg=body_known_said(known))
}

///|
/// Its turn over on the page made as nodes (`name`), `now` against `before` (the step before, its agent's line the last
/// row): each row both draw where it was, no row of before's but the line gone, and the room under the last row as tall
/// as the line was drawn then (the line's foot where it was), in `said` where not.
fn body_turn_over_held(name : String, before : BodyDrawn, now : BodyDrawn, said : Array[String]) -> Unit {
  guard before.rows.iter().find_first(fn(r) { r.key.has_prefix("act:") }) is Some(line) else {
    said.push(name + ": no agent's line the step before")
    return
  }
  for r in now.rows {
    match before.rows.iter().find_first(fn(b) { b.key == r.key }) {
      Some(b) =>
        if body_r(b.top) != body_r(r.top) {
          said.push(name + " " + r.key + ": its top \{body_r(b.top)} the step before, \{body_r(r.top)} now (held)")
        }
      None => said.push(name + " " + r.key + ": a row not drawn the step before")
    }
  }
  for b in before.rows {
    if b.key != line.key && b.top + b.h > 0.0 && !now.rows.iter().any(fn(r) { r.key == b.key }) {
      said.push(name + " " + b.key + ": drawn the step before, not now")
    }
  }
  match now.rows.last() {
    Some(last) => {
      let room = line.top + line.h - (last.top + last.h)
      if body_r(room) != body_r(line.h) {
        said.push(name + ": the room under the last row \{body_r(room)}, the line \{body_r(line.h)} high the step before")
      }
    }
    None => said.push(name + ": no row drawn")
  }
  if now.rows.iter().any(fn(r) { r.key == line.key }) {
    said.push(name + ": the agent's line still drawn")
  }
}

///|
/// Of the nodes' audit `faults`, those known of a row's head's time (body_time_short) counted in `known`.
fn body_tally_time(known : Map[String, Int], faults : Array[String]) -> Unit {
  let n = faults.filter(body_time_short).length()
  if n > 0 {
    let k = "its head's time pressed short (message_head_node's)"
    known[k] = known.get(k).unwrap_or(0) + n
  }
}

///|
/// The fixture's chat's source, its time of day the Tester's clock (`t`'s, once it is made): what was sent counts from
/// when it was sent on it (chat_rows.mbt outbox_row's).
fn body_clocked(t : Ref[@ui.Tester?]) -> Source {
  { ..@sffixture.fixture("chat"), now: fn() { t.val.map(fn(t) { t.time() }).unwrap_or(0.0) } }
}

///|
/// How opaque each 正在发送 a Tester draws is.
fn body_sending(t : @ui.Tester) -> Array[Double] {
  t.words().filter(fn(w) { w.0 == @sf.t("web-main.chat.sending") }).map(fn(w) { w.5 })
}

///|
/// What is sent from here in fixture `case` ("pressed": words sent now; "opened": a chat opened on what has been on its
/// way 5 s; "taken": words sent now, the core's outbox entry taking it over, another id, half way to sending_shows_ms),
/// as a Tester draws it, `given` its view as each step says: how opaque its 正在发送 is half way to sending_shows_ms
/// from the press (or the opening), then at it, then after it.
fn body_sent_steps(
  t : @ui.Tester,
  src : Source,
  v0 : ChatView,
  case : String,
  give : (ChatView) -> Unit,
) -> Array[Array[Double]] {
  let rk = body_ref.station + "\u{1}" + body_ref.session
  let out : Outgoing = { ..chat_body_no_out, id: "core-1", text: "刚发的一句", state: "sending" }
  match case {
    "opened" => {
      let v = { ..v0, outbox: [{ ..out, created_at: (src.now)() - 5000.0 }] }
      give(v)
    }
    _ => {
      give(v0)
      @sfbase.sent_local(rk, Some(v0), "刚发的一句", [], now=(src.now)()) |> ignore
    }
  }
  let sent_at = (src.now)()
  let said : Array[Array[Double]] = []
  t.run_for(sending_shows_ms / 2.0)
  said.push(body_sending(t))
  if case == "taken" {
    give({ ..v0, outbox: [{ ..out, created_at: sent_at }] })
  }
  t.run_for(sending_shows_ms / 2.0)
  said.push(body_sending(t))
  t.run_for(sending_shows_ms / 2.0)
  said.push(body_sending(t))
  said
}

///|
test "words sent from here as nodes: 正在发送 seen sending_shows_ms after they were sent, as the old list shows it: just sent, opened on one long on its way, taken over by the core's outbox entry" {
  for case in ["pressed", "opened", "taken"] {
    @sfbase.reset()
    reset()
    let held : Ref[@ui.Tester?] = Ref(None)
    let src = body_clocked(held)
    let seen : Ref[(ChatView, Array[Entry])?] = Ref(None)
    let given : @signals.Signal[(ChatView, Array[Entry])?] = @signals.signal(None)
    let old = body_old(src, 390.0, 844.0, 2, seen~, given~)
    held.val = Some(old)
    old.run_for(@ui.move_most_ms)
    let v0 = seen.val.unwrap().0
    let was = body_sent_steps(old, src, v0, case, fn(v) { given.set(Some((v, @sfbase.entries_of(v)))) })
    @sfbase.reset()
    reset()
    let held : Ref[@ui.Tester?] = Ref(None)
    let src = body_clocked(held)
    let view = @signals.signal(v0)
    let entries = @signals.signal(@sfbase.entries_of(v0))
    let made : Map[String, Int] = Map([])
    let t = body_new(src, 390.0, 844.0, 2, view, entries, made=fn(k, _) { made[k] = made.get(k).unwrap_or(0) + 1 })
    held.val = Some(t)
    t.run_for(@ui.move_most_ms)
    let now = body_sent_steps(t, src, v0, case, fn(v) {
      view.set(v)
      entries.set(@sfbase.entries_of(v))
    })
    assert_eq(now, was, msg=case)
    let want = match case {
      "opened" => [[1.0], [1.0], [1.0]]
      _ => [[0.0], [1.0], [1.0]]
    }
    assert_eq(now, want, msg=case)
    if case == "taken" {
      // (the core's outbox entry is the row sent from here: no row of its own, the row not made again)
      assert_eq(made.get("o:core-1"), None, msg=case)
      assert_eq(made.get("o:local:1"), Some(1), msg=case)
    }
    assert_eq(t.audit(), [], msg=case)
  }
}

///|
test "what was sent from here goes on by the key it was sent as: the core's outbox entry, then its message, no row of their own" {
  @sfbase.reset()
  reset()
  let held : Ref[@ui.Tester?] = Ref(None)
  let src = body_clocked(held)
  // (a chat with a message in it already: the first sent into an empty one, its empty row and the room over the sent
  // one going in the frame it comes, is the list's way to make (xfer/l1-plan.md §5, PR C's), back here once it is)
  let first = @sfbase.message_of({
    "seq": 1,
    "thread": 7,
    "ts": "ts1",
    "authorKind": "agent",
    "text": "在这里。",
    "md": [["p", ["在这里。"]]],
    "by": { "name": "Claude", "agent": "s-c1" },
    "time": @sffixture.ago("刚刚", "2026-11-12 09:59"),
  })
  let v0 = @sfbase.chat_view_made({ "title": "整理发布清单", "messages": [], "thread": { "id": 7 } })
  let v0 = { ..v0, messages: [first] }
  let view = @signals.signal(v0)
  let entries = @signals.signal(@sfbase.entries_of(v0))
  let made : Map[String, Int] = Map([])
  let t = body_new(src, 390.0, 844.0, 2, view, entries, made=fn(k, _) { made[k] = made.get(k).unwrap_or(0) + 1 })
  held.val = Some(t)
  t.run_for(@ui.move_most_ms)
  let rk = body_ref.station + "\u{1}" + body_ref.session
  let key = @sfbase.sent_local(rk, Some(v0), "刚发的一句", [], now=(src.now)())
  t.run_for(@ui.move_most_ms)
  assert_eq(made.get(key), Some(1), msg="its row made as it is sent")
  let out : Outgoing = { ..chat_body_no_out, id: "core-1", text: "刚发的一句", state: "sent", seq: 3.0 }
  let v1 = { ..v0, outbox: [out] }
  view.set(v1)
  entries.set(@sfbase.entries_of(v1))
  t.run_for(@ui.move_most_ms)
  assert_eq(made.get("o:core-1"), None, msg="the core's outbox entry is the row sent from here")
  assert_eq(made.get(key), Some(1), msg="not made again for the core's entry")
  let m = @sfbase.message_of({
    "seq": 3,
    "thread": 7,
    "ts": "ts3",
    "authorKind": "person",
    "mine": true,
    "text": "刚发的一句",
    "outgoing": "core-1",
    "by": { "name": "林" },
    "time": @sffixture.ago("刚刚", "2026-11-12 10:00"),
  })
  let v2 = { ..v0, messages: [first, m] }
  view.set(v2)
  entries.set(@sfbase.entries_of(v2))
  t.run_for(@ui.move_most_ms)
  assert_eq(made.get("m:ts3"), None, msg="the core's message is the row sent from here")
  assert_eq(made.get("o:core-1"), None, msg="the core's message is the row sent from here")
  // (its block the same, by the key it was sent as, and what it holds not made again: what is sent and what it becomes
  // are one row, its words' node the one made as it was sent, so a finger's pick over them keeps its handles and menu)
  assert_eq(made.get(key), Some(1), msg="no row made as the core's message takes it over: its words' node the same")
  assert_true(t.words().iter().any(fn(w) { w.0 == "刚发的一句" }))
  assert_eq(t.audit().filter(fn(f) { !f.contains("刚刚") }), [])
}

///|
///|
test "the page before read in over a chat's list as nodes at its top: what is read does not move" {
  @sfbase.reset()
  reset()
  let src = @sffixture.fixture("chat-working")
  let s = body_screens()[0]
  // (the chat's view as its first frame reads it (view_of_chat in chat_list's build), then once the core has read the
  // page before in: both read as a list's frame reads them, no list drawn of them)
  let seen : Ref[(ChatView, Array[Entry])?] = Ref(None)
  body_old(src, s.1, s.2, s.3, seen~) |> ignore
  let (v0, read0) = seen.val.unwrap()
  let answered : Ref[Bool] = Ref(false)
  (src.call)("chat.older", { "station": Json::string(body_ref.station), "thread": Json::number(v0.thread.unwrap()) }, fn(
    r,
  ) {
    answered.val = r is Ok(_)
  })
  let paged : Ref[(ChatView, Array[Entry])?] = Ref(None)
  body_old(src, s.1, s.2, s.3, seen=paged) |> ignore
  let (v1, read1) = paged.val.unwrap()
  @sfbase.reset()
  reset()
  let src = @sffixture.fixture("chat-working")
  let view = @signals.signal(v0)
  let entries = @signals.signal(read0)
  let views : Map[String, @view.View] = Map([])
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  let t = body_new(src, s.1, s.2, s.3, view, entries, place~, made=fn(k, p) { views[k] = p })
  t.run_for(@ui.move_most_ms)
  let keys0 = body_keys(v0, read0)
  // (at its very top: its first row under its head, the chat's bar's room, what covers the list's top: a bring's
  // offset is from under it)
  place.bring(keys0.iter().find_first(fn(k) { k != "top" }).unwrap())
  t.run_for(@ui.move_most_ms)
  let read_key = keys0.iter().find_first(fn(k) { k.has_prefix("m:") }).unwrap()
  let before = views[read_key].placed_window_now().1
  // (the core's answer to the page before, asked as the list came to its top: the chat's view as it says it then)
  assert_true(body_keys(v1, read1).length() > keys0.length(), msg="the page before read in")
  view.set(v1)
  entries.set(read1)
  t.run_for(@ui.move_most_ms)
  // (what is read does not move: the page in over it, its head gone up with what comes in, the message read at its
  // top where it was, as the old list holds it)
  match views.get(read_key) {
    Some(p) if p.alive() =>
      assert_eq(body_r(p.placed_window_now().1), body_r(before), msg="\{read_key} where it was")
    _ => fail("\{read_key}, at \{body_r(before)} before, let go")
  }
  assert_eq(t.audit().filter(fn(f) { !body_time_short(f) }), [])
}

///|
/// How many of the tree's bindings were looked at again so far (Tree::work's `bound`).
fn body_bound() -> Int {
  @ui.view_tree().unwrap().work().bound
}

///|
test "a chat's list as nodes given the same entries again reads none of its rows again; one row changed, fewer than every row's" {
  @sfbase.reset()
  reset()
  let src = @sffixture.fixture("chat")
  let s = body_screens()[0]
  let seen : Ref[(ChatView, Array[Entry])?] = Ref(None)
  body_old(src, s.1, s.2, s.3, seen~) |> ignore
  let (v0, read0) = seen.val.unwrap()
  @sfbase.reset()
  reset()
  let src = @sffixture.fixture("chat")
  let view = @signals.signal(v0)
  let entries = @signals.signal(read0)
  let made : Map[String, Int] = Map([])
  let t = body_new(src, s.1, s.2, s.3, view, entries, made=fn(k, _) { made[k] = made.get(k).unwrap_or(0) + 1 })
  t.run_for(@ui.move_most_ms)
  let made0 = made.copy()
  // the same entries again (another array, each entry as it was): no row's binding looked at again
  let b0 = body_bound()
  entries.set(read0.copy())
  t.run_for(@ui.move_most_ms)
  let same = body_bound() - b0
  assert_eq(same, 0, msg="the same entries again looked at \{same} bindings")
  // the last message's words changed: that row's
  let mut last = -1
  for i, e in read0 {
    if e is Said(_) {
      last = i
    }
  }
  guard last >= 0 && read0[last] is Said(m) else { fail("no message") }
  let words = "改过的字：只有这一行重读。"
  let one = read0.copy()
  one[last] = Said({ ..m, text: words, md: Some(body_md(words)) })
  let b1 = body_bound()
  entries.set(one)
  t.run_for(@ui.move_most_ms)
  let one_row = body_bound() - b1
  assert_true(t.find(words) is Some(_), msg="its new words drawn")
  // every message another (each as it was, read anew): every row's
  let all = one.map(fn(e : Entry) -> Entry {
    match e {
      Said(m) => Said({ ..m, text: m.text })
      e => e
    }
  })
  let b2 = body_bound()
  entries.set(all)
  t.run_for(@ui.move_most_ms)
  let every = body_bound() - b2
  assert_true(
    one_row > 0 && one_row < every,
    msg="one row changed looked at \{one_row} bindings, every row \{every}",
  )
  assert_eq(made, made0, msg="no row made again")
}
