// Tests drive a view without a window: a fake host with fixed text metrics,
// a clock the test advances, input sent the way a host sends it, and a text
// dump of the laid-out tree to compare against.

///|
pub struct Tester {
  fake : FakeHost
  mut w : Double
  mut h : Double
  mut frames : Int
}

///|
fn reset_globals() -> Unit {
  let c = g
  c.count = 0
  c.cur = -1
  c.id_seed = 17
  c.id_stack.clear()
  c.now = 0.0
  c.dt = 16.0
  c.last_now = -1.0
  c.frame_no = 0
  c.wants_frame = false
  c.wake_at = -1.0
  c.hit_ids.clear()
  c.hit_rects.clear()
  c.scroll_ids.clear()
  c.scroll_rects.clear()
  c.px = -1.0
  c.py = -1.0
  c.down = false
  c.hover = 0
  c.active = 0
  c.focus = 0
  c.clicked.clear()
  c.drag_scroll = 0
  c.dragging = false
  c.vel = 0.0
  c.editor_drag = false
  c.lists.clear()
  c.editors.clear()
  c.springs.clear()
  c.owner = 0
  c.owned.clear()
  c.back = None
  c.back_node = -1
  c.back_next = None
  c.back_node_next = -1
  c.back_told = false
  c.edge = 0
  c.ninst = 0
  c.ime_sig = ""
  c.bench_list = 0
  text_cache.shapes.clear()
  text_cache.metrics.clear()
  text_cache.glyphs.clear()
  text_cache.generation = -1
  image_cache.clear()
  pagers.clear()
  image_data.clear()
  bench.mode = 0
}

///|
/// A tester showing `view` in a window of w × h logical pixels; it has
/// already drawn the first frame. `images`: sources views may load, with
/// their size in pixels (others fail to load).
pub fn Tester::new(
  view : (Ctx) -> Unit,
  w? : Double = 390.0,
  h? : Double = 844.0,
  images? : Array[(String, Int, Int)] = [],
) -> Tester {
  let f = {
    time: 1000.0,
    wants: false,
    wake: -1.0,
    instances: 0,
    ime_active: false,
    ime_text: "",
    ime_sel: (0, 0),
    ime_rect: (0.0, 0.0, 0.0, 0.0),
    clipboard: "",
    back_on: false,
    logs: [],
    image_sizes: {},
    image_loads: [],
    images: {},
  }
  for im in images {
    f.image_sizes[im.0] = (im.1, im.2)
  }
  fake.val = Some(f)
  reset_globals()
  g_view.val = view
  let t = { fake: f, w, h, frames: 0 }
  t.frame()
  t
}

///|
/// Draws one frame, `ms` after the previous one.
pub fn Tester::frame(self : Tester, ms? : Double = 16.0) -> Unit {
  self.fake.time = self.fake.time + ms
  // decodes started last frame are done
  for _, im in self.fake.images {
    if im.state == 0 {
      im.state = 1
      self.fake.wants = true
    }
  }
  self.fake.wants = false
  on_frame(self.w, self.h, 2.0, self.fake.time)
  self.frames = self.frames + 1
}

///|
/// Draws frames until nothing asks for another (animations, scrolling and
/// re-layouts have finished); returns how many it took.
pub fn Tester::settle(self : Tester, max? : Int = 600) -> Int {
  let mut n = 0
  while n < max && (g.wants_frame || self.fake.wants) {
    self.frame()
    n = n + 1
  }
  n
}

///|
pub fn Tester::resize(self : Tester, w : Double, h : Double) -> Unit {
  self.w = w
  self.h = h
  self.frame()
  self.settle() |> ignore
}

///|
pub fn Tester::tap(self : Tester, x : Double, y : Double) -> Unit {
  on_pointer(0, x, y, 0)
  on_pointer(2, x, y, 0)
  self.frame()
  self.settle() |> ignore
}

///|
/// A finger or mouse drag from one point to another in `steps` moves, one
/// frame apart, then released.
pub fn Tester::drag(
  self : Tester,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  steps? : Int = 10,
) -> Unit {
  on_pointer(0, x0, y0, 0)
  for i in 1..=steps {
    let t = i.to_double() / steps.to_double()
    self.fake.time = self.fake.time + 16.0
    on_pointer(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0)
    self.frame(ms=0.0)
  }
  on_pointer(2, x1, y1, 0)
  self.frame()
}

///|
pub fn Tester::wheel(self : Tester, x : Double, y : Double, dy : Double) -> Unit {
  on_wheel(x, y, 0.0, dy, 0)
  self.frame()
  self.settle() |> ignore
}

///|
/// Text committed by the input method (or typed on a hardware keyboard).
pub fn Tester::type_text(self : Tester, s : String) -> Unit {
  on_text(0, s, 0, 0)
  self.frame()
}

///|
/// The input method's composition, with the caret at its end.
pub fn Tester::compose(self : Tester, s : String) -> Unit {
  on_text(1, s, s.length(), 0)
  self.frame()
}

///|
pub fn Tester::key(self : Tester, code : Int, mods? : Int = 0) -> Unit {
  on_key(code, mods)
  self.frame()
  self.settle() |> ignore
}

///|
pub fn Tester::enter(self : Tester) -> Unit {
  self.key(key_enter)
}

///|
pub fn Tester::backspace(self : Tester) -> Unit {
  self.key(key_backspace)
}

///|
/// The centre of the first text node (or editor placeholder) containing `s`.
pub fn Tester::find(self : Tester, s : String) -> (Double, Double)? {
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_editor || n.kind == kind_rich) &&
      n.text.contains(s) {
      return Some((n.x + n.fw / 2.0, n.y + n.fh / 2.0))
    }
  }
  None
}

///|
pub fn Tester::tap_text(self : Tester, s : String) -> Unit {
  match self.find(s) {
    Some((x, y)) => self.tap(x, y)
    None => abort("no text \"\{s}\" on screen")
  }
}

///|
/// What the host was last told about the focused field: active, text,
/// selection start and end.
pub fn Tester::ime(self : Tester) -> (Bool, String, Int, Int) {
  let (a, b) = self.fake.ime_sel
  (self.fake.ime_active, self.fake.ime_text, a, b)
}

///|
pub fn Tester::clipboard(self : Tester) -> String {
  self.fake.clipboard
}

///|
pub fn Tester::instances(self : Tester) -> Int {
  self.fake.instances
}

///|
fn r(x : Double) -> Int {
  x.round().to_int()
}

///|
/// The laid-out tree as text: one node per line, indented by depth, with its
/// rectangle; text nodes with their text and line count.
pub fn Tester::dump(self : Tester) -> String {
  let sb = StringBuilder()
  dump_node(sb, 0, 0)
  sb.to_string()
}

///|
fn dump_node(sb : StringBuilder, i : Int, depth : Int) -> Unit {
  let c = g
  if i >= c.count {
    return
  }
  let n = c.nodes[i]
  for _ in 0..<depth {
    sb.write_string("  ")
  }
  let kind = if n.kind == kind_text {
    "text"
  } else if n.kind == kind_rich {
    "rich"
  } else if n.kind == kind_list {
    "list"
  } else if n.kind == kind_editor {
    "editor"
  } else if n.dir == Row {
    "row"
  } else {
    "col"
  }
  sb.write_string("\{kind} \{r(n.x)},\{r(n.y)} \{r(n.fw)}x\{r(n.fh)}")
  if n.kind == kind_text {
    let lines = match n.tl {
      Some(tl) => tl.line_start.length()
      None => 0
    }
    sb.write_string(" \{n.text.escape()} lines=\{lines}")
  }
  if n.kind == kind_rich {
    let lines = match n.rl {
      Some(rl) => rl.line_start.length()
      None => 0
    }
    sb.write_string(" \{n.text.escape()} lines=\{lines}")
  }
  if n.kind == kind_editor {
    match c.editors.get(n.id) {
      Some(st) => sb.write_string(" \{st.display().escape()} caret=\{st.caret}")
      None => ()
    }
  }
  if n.item >= 0 {
    sb.write_string(" item=\{n.item}")
  }
  sb.write_char('\n')
  let mut ch = n.first
  while ch >= 0 {
    dump_node(sb, ch, depth + 1)
    ch = c.nodes[ch].next
  }
}

///|
/// The rectangle of the first node whose text contains `s` (x, y, w, h).
pub fn Tester::rect_of(self : Tester, s : String) -> (Double, Double, Double, Double)? {
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_rich) && n.text.contains(s) {
      return Some((n.x, n.y, n.fw, n.fh))
    }
  }
  None
}

///|
/// Visible list rows: (item, y, height), top to bottom.
pub fn Tester::rows(self : Tester) -> Array[(Int, Double, Double)] {
  let c = g
  let out = []
  for i in 0..<c.count {
    if c.nodes[i].kind == kind_list {
      let mut r = c.nodes[i].first
      while r >= 0 {
        let n = c.nodes[r]
        out.push((n.item, n.y, n.fh))
        r = n.next
      }
    }
  }
  out
}

///|
/// The lines of the first text node whose text contains `s`, as laid out.
pub fn Tester::lines_of(self : Tester, s : String) -> Array[String] {
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_text && n.text.contains(s) {
      match n.tl {
        Some(tl) =>
          return Array::makei(tl.line_start.length(), fn(l) {
            let (a, b) = tl.line_range(l)
            tl.text.unsafe_substring(start=a, end=b)
          })
        None => ()
      }
    }
    if n.kind == kind_rich && n.text.contains(s) {
      match n.rl {
        Some(rl) =>
          return Array::makei(rl.line_count(), fn(l) {
            let (a, b) = rl.line_range(l)
            rl.text.unsafe_substring(start=a, end=b)
          })
        None => ()
      }
    }
  }
  []
}

///|
/// The pointer moved to (x, y), no button down.
pub fn Tester::move(self : Tester, x : Double, y : Double) -> Unit {
  on_pointer(1, x, y, 0)
  self.frame()
}

///|
fn Tester::list_state(self : Tester) -> ListState {
  ignore(self)
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_list {
      match c.lists.get(n.id) {
        Some(st) => return st
        None => ()
      }
    }
  }
  abort("no list on screen")
}

///|
/// Scrolls the (first) list so that row `item` starts at its top, from the
/// next frame on.
pub fn Tester::scroll_to(self : Tester, item : Int) -> Unit {
  self.list_state().scroll_to(item)
}

///|
pub fn Tester::scroll_to_end(self : Tester) -> Unit {
  self.list_state().scroll_to_end()
}

///|
/// The first and last rows of the list in view (-1, -1 when none).
pub fn Tester::visible(self : Tester) -> (Int, Int) {
  let st = self.list_state()
  (st.vis_first, st.vis_last)
}

///|
pub fn Tester::at_end(self : Tester) -> Bool {
  self.list_state().at_end
}

///|
/// Where row `item` of the list is (x, y, w, h), if built.
pub fn Tester::row(self : Tester, item : Int) -> (Double, Double, Double, Double)? {
  ignore(self)
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.item == item && n.parent >= 0 && c.nodes[n.parent].kind == kind_list {
      // only rows the list kept (it may build some it doesn't show)
      let mut ch = c.nodes[n.parent].first
      while ch >= 0 {
        if ch == i {
          return Some((n.x, n.y, n.fw, n.fh))
        }
        ch = c.nodes[ch].next
      }
    }
  }
  None
}

///|
/// Checks the list's rows in view follow each other without gaps or
/// overlaps and fill the view from `top` to `bottom` (unless they run
/// out), as mygo's checkRows does.
pub fn Tester::check_rows(self : Tester, top : Double, bottom : Double) -> Unit raise {
  let (first, last) = self.visible()
  if last < first || first < 0 {
    fail("no row in view")
  }
  let (_, y0, _, h0) = self.row(first).unwrap()
  if y0 > top + 0.01 {
    fail("row \{first}, the first in view, starts at \{y0}, below the top \{top}")
  }
  let mut end = y0 + h0
  for i in (first + 1)..=last {
    match self.row(i) {
      Some((_, y, _, h)) => {
        if (y - end).abs() > 0.01 {
          fail("row \{i} starts \{y - end} from where row \{i - 1} ends")
        }
        end = y + h
      }
      None => fail("row \{i} in view was not built")
    }
  }
  if last < self.list_state().count - 1 && end < bottom - 0.01 {
    fail("row \{last}, the last in view, ends at \{end}, above the bottom \{bottom}")
  }
}

///|
/// A key by name: Home, End, PageUp, PageDown, Up, Down, Left, Right,
/// Enter, Backspace, Delete.
pub fn Tester::press(self : Tester, name : String) -> Unit {
  let code = match name {
    "Home" => key_home
    "End" => key_end
    "PageUp" => key_page_up
    "PageDown" => key_page_down
    "Up" => key_up
    "Down" => key_down
    "Left" => key_left
    "Right" => key_right
    "Enter" => key_enter
    "Backspace" => key_backspace
    "Delete" => key_delete
    _ => abort("no key \{name}")
  }
  self.key(code)
}

///|
/// Back, as a back button (or the system's back with no gesture) asks.
pub fn Tester::back(self : Tester) -> Unit {
  on_back(2, 0.0, 1.0, 0)
  self.frame()
  self.settle() |> ignore
}

///|
/// The system's back gesture (Android's predictive back) from the left
/// edge to `x`, in `steps` moves a frame apart; then gone back (`commit`)
/// or called off. Not settled: the page is where it was let go.
pub fn Tester::back_gesture(
  self : Tester,
  x : Double,
  commit : Bool,
  steps? : Int = 10,
) -> Unit {
  on_back(0, 0.0, 0.0, 0)
  for i in 1..=steps {
    self.fake.time = self.fake.time + 16.0
    on_back(1, x * i.to_double() / steps.to_double(), 0.0, 0)
    self.frame(ms=0.0)
  }
  on_back(if commit { 2 } else { 3 }, x, 1.0, 0)
  self.frame()
}

///|
/// Whether the host was told the app takes back.
pub fn Tester::takes_back(self : Tester) -> Bool {
  self.fake.back_on
}

///|
/// A finger down at (x, y) and moved to (x1, y1) in `steps` moves, a frame
/// apart, not let go (a page followed: see where it is).
pub fn Tester::hold_drag(
  self : Tester,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  steps? : Int = 10,
) -> Unit {
  on_pointer(0, x0, y0, 0)
  for i in 1..=steps {
    let t = i.to_double() / steps.to_double()
    self.fake.time = self.fake.time + 16.0
    on_pointer(1, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0)
    self.frame(ms=0.0)
  }
}

///|
/// The finger let go at (x, y).
pub fn Tester::release(self : Tester, x : Double, y : Double) -> Unit {
  on_pointer(2, x, y, 0)
  self.frame()
}

///|
/// The finger down at (x, y), held (a frame drawn so).
pub fn Tester::press_at(self : Tester, x : Double, y : Double) -> Unit {
  on_pointer(0, x, y, 0)
  self.frame()
}

///|
/// The plain rectangles drawn in the last frame, as (x, y, w, h, colour
/// RRGGBBAA with its opacity applied).
pub fn Tester::drawn_rects(self : Tester) -> Array[(Double, Double, Double, Double, Int64)] {
  ignore(self)
  let c = g
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 {
      let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
      let color = (ch(c.inst[b + 8]) << 24) |
        (ch(c.inst[b + 9]) << 16) |
        (ch(c.inst[b + 10]) << 8) |
        ch(c.inst[b + 11])
      out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], color))
    }
  }
  out
}

///|
/// The glyphs drawn in the last frame: (x, y, colour).
pub fn Tester::drawn_glyphs(self : Tester) -> Array[(Double, Double, Int64)] {
  ignore(self)
  let c = g
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 1.0 {
      let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
      let color = (ch(c.inst[b + 8]) << 24) |
        (ch(c.inst[b + 9]) << 16) |
        (ch(c.inst[b + 10]) << 8) |
        ch(c.inst[b + 11])
      out.push((c.inst[b], c.inst[b + 1], color))
    }
  }
  out
}

///|
/// The rich paragraph whose text contains `s`, as laid out, and where it
/// is (its content's top left).
pub fn Tester::rich_of(self : Tester, s : String) -> (RichLayout, Double, Double)? {
  ignore(self)
  let c = g
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_rich && n.text.contains(s) {
      match n.rl {
        Some(rl) => return Some((rl, n.x + n.pad_l, n.y + n.pad_t))
        None => ()
      }
    }
  }
  None
}

///|
/// Where the words `s` of a rich paragraph are drawn: one rectangle a line
/// (x, y, w, h).
pub fn Tester::run_rects(self : Tester, s : String) -> Array[(Double, Double, Double, Double)] {
  match self.rich_of(s) {
    Some((rl, x, y)) =>
      match rl.text.find(s) {
        Some(a) =>
          rl
          .rects(a, a + s.length())
          .map(fn(r) { (r.0 + x, r.1 + y, r.2, r.3) })
        None => []
      }
    None => []
  }
}

///|
/// A tap on the middle of the first piece of the words `s` of a rich
/// paragraph (a link).
pub fn Tester::tap_run(self : Tester, s : String) -> Unit {
  let rs = self.run_rects(s)
  if rs.length() == 0 {
    abort("no rich text \"\{s}\" on screen")
  }
  let (x, y, w, h) = rs[0]
  self.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// Makes up an image at `src`, `w` × `h` pixels, for views to load.
pub fn Tester::add_image(self : Tester, src : String, w : Int, h : Int) -> Unit {
  self.fake.image_sizes[src] = (w, h)
}

///|
/// The images loaded so far: source and the size asked for.
pub fn Tester::image_loads(self : Tester) -> Array[(String, Int)] {
  self.fake.image_loads
}

///|
/// How many decoded images are kept.
pub fn Tester::images_kept(self : Tester) -> Int {
  self.fake.images.length()
}

///|
/// The image instances drawn in the last frame: (x, y, w, h, u0, v0, du,
/// dv, opacity).
pub fn Tester::drawn_images(self : Tester) -> Array[Array[Double]] {
  ignore(self)
  let c = g
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      out.push([
        c.inst[b],
        c.inst[b + 1],
        c.inst[b + 2],
        c.inst[b + 3],
        c.inst[b + 12],
        c.inst[b + 13],
        c.inst[b + 14],
        c.inst[b + 15],
        c.inst[b + 11],
      ])
    }
  }
  out
}
