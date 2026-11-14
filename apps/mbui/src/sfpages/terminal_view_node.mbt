// A terminal of a station's, viewed (the user, 2026-11-14, the mockup agreed in chat): over the whole window as a
// station's screen is, on every screen. The bar across its top is a viewer's (@sf.viewer_bar_node, a screen's and a
// file's): back to the page it was opened from by name; the folder it opened in, and under it where that is, or who
// types into it while someone else does, or that it ended; at its end 控制 while it is only looked at, 接管 while
// someone else types (the screen viewer's words), its ⋯ last (复制工作目录, 结束会话). A narrow page has a phone's bar
// instead (back, its name, the same at its end) and who types a line under it. Under the bar the screen, the whole of the room left, on the
// terminal's own dark ground whatever the theme, in the code face, its runs in the colours the program gave them.
//
// What it shows is the core's `terminal.view` stream (client/core-ts/src/terminals.ts) feeding a terminal the host keeps
// (@hostapi.Terminal: libghostty-vt on a device): the station's `screen` written into a terminal made anew of its size,
// what comes after it into that one. It is opened as wide and as tall as the window holds cells.

///|
// kept across runs: the views' numbers, each page its own (a core's view id is the app's to choose)
let terminal_views : Ref[Int] = Ref(0)

///|
/// The terminal's ground and its own ink, the same in either theme (terminal programs take a dark ground).
let terminal_ground : Int64 = 0x16171AFFL

///|
let terminal_ink : Int64 = 0xD8D9DBFFL

///|
/// The screen's words: the code face at 12.5, a line 19 high.
let terminal_size : Double = 12.5

///|
let terminal_line : Double = 19.0

///|
/// How far in from the screen's sides and top its cells start.
let terminal_in : Double = 14.0

///|
let terminal_over : Double = 10.0

///|
/// A run of a line as the host gives it: its text and how it looks.
fn terminal_run(r : Json) -> @ui.Run? {
  guard r is Array([String(t), String(fg), String(bg), Number(flags, ..)]) else { return None }
  let f = flags.to_int()
  let inverse = (f & 8) != 0
  let (fg, bg) = if inverse { (bg, fg) } else { (fg, bg) }
  let fg = terminal_colour(fg).unwrap_or(if inverse { terminal_ground } else { terminal_ink })
  let bg = terminal_colour(bg)
  let faint = (f & 16) != 0
  Some(
    @ui.span(
      t,
      mono=true,
      bold=(f & 1) != 0,
      italic=(f & 2) != 0,
      underline=(f & 4) != 0,
      color=if faint { (fg & 0xFFFFFF00L) | 0x99L } else { fg },
      bg=match bg { Some(b) => b; None => if inverse { terminal_ink } else { 0L } },
    ),
  )
}

///|
/// `#rrggbb` as the runs' colour (0xRRGGBBAA); None for the terminal's own.
fn terminal_colour(s : String) -> Int64? {
  guard s.length() == 7 && s.has_prefix("#") else { return None }
  let mut v = 0L
  for c in s.to_array()[1:] {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    v = v * 16L + d.to_int64()
  }
  Some((v << 8) | 0xFFL)
}

///|
/// The screen's lines as the host gave them, as runs, a line a run of breaks.
fn terminal_runs(said : String) -> Array[@ui.Run] {
  let parsed = @json.parse(said) catch { _ => return [] }
  let out : Array[@ui.Run] = []
  match parsed {
    Object(o) =>
      match o.get("lines") {
        Some(Array(lines)) =>
          for i, line in lines {
            if i > 0 {
              out.push(@ui.span("\n", mono=true))
            }
            match line {
              Array(runs) => for r in runs { match terminal_run(r) { Some(run) => out.push(run); None => () } }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
/// How many cells a window `w` × `h` holds under the bar (`top` over it: a phone's status bar), at least 20 × 6.
fn terminal_cells(w : Double, h : Double, top : Double) -> (Int, Int) {
  let cell = @ui.text_advance("M", size=terminal_size, style=@hostapi.style_mono)
  let across = if cell > 0.0 { ((w - 2.0 * terminal_in) / cell).to_int() } else { 80 }
  let down = ((h - top - @sf.viewer_bar_h - 2.0 * terminal_over) / terminal_line).to_int()
  (if across < 20 { 20 } else { across }, if down < 6 { 6 } else { down })
}

///|
/// Station `at.station`'s terminal `at.terminal` (`new`: one opened for this page, in `at.cwd` where said), looked at
/// only where `at.watch`, in `v` (all of the window: the shell's), its bar's way back `back`'s words, `on_back` as it is
/// pressed, under `top` (a phone's status bar).
pub fn terminal_node(
  v : @view.View,
  src : Source,
  at : @sfbase.TerminalAt,
  back~ : () -> String,
  on_back~ : () -> Unit,
  top~ : () -> Double,
  width? : () -> Double,
) -> Unit {
  terminal_views.val += 1
  let view = "terminal-" + terminal_views.val.to_string()
  let (w, h) = v.window()
  let (cols, rows) = terminal_cells(w, h, @signals.untracked(top))
  // (what the core says of it, whole as it changes; and the screen drawn again as what feeds it comes)
  let state : @signals.Signal[Json?] = @signals.signal(None)
  let drawn : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })
  let kept : Ref[@hostapi.Terminal?] = Ref(@hostapi.Terminal::open(cols, rows))
  let fresh = fn() {
    match kept.val { Some(t) => t.close(); None => () }
    let s = @signals.untracked(fn() { state.get() })
    let c = number(s, "cols").to_int()
    let r = number(s, "rows").to_int()
    kept.val = @hostapi.Terminal::open(if c > 0 { c } else { cols }, if r > 0 { r } else { rows })
  }
  let params : Array[(String, Json)] = [
    ("station", str(at.station)),
    ("terminal", str(at.terminal)),
    ("view", str(view)),
    ("cols", Json::number(cols.to_double())),
    ("rows", Json::number(rows.to_double())),
    ("control", Json::boolean(!at.watch)),
    ..if at.cwd != "" && at.terminal == "new" { [("cwd", str(at.cwd))] } else { [] },
  ]
  let call = (src.stream)("terminal.view", obj(params), None, fn(value, bytes) {
    match value {
      Object(o) if o.contains("state") => state.set(o.get("state"))
      Object(o) if o.contains("screen") => {
        fresh()
        match (kept.val, bytes) { (Some(t), Some(b)) => t.write(b); _ => () }
        drawn.set(drawn.untracked() + 1)
      }
      Object(o) if o.contains("out") => {
        match (kept.val, bytes) { (Some(t), Some(b)) => t.write(b); _ => () }
        drawn.set(drawn.untracked() + 1)
      }
      _ => ()
    }
  }, @sfbase.answer_unread)
  v.owns(fn() {
    (src.cancel)(call)
    match kept.val { Some(t) => t.close(); None => () }
    kept.val = None
  })
  |> ignore
  let s = fn() { state.get() }
  let types = fn() { flag(s(), "types") }
  let typing = fn() { text(s(), "typing") }
  let ended = fn() { text(s(), "phase") == "ended" }
  let cwd = fn() {
    let said = text(s(), "cwd")
    if said == "" { at.cwd } else { said }
  }
  let title = fn() {
    let shown = cwd()
    match shown.split("/").collect().filter(fn(p) { p.length() > 0 }).last() {
      Some(last) => last.to_owned()
      None => if shown == "" { @sf.t("web-pages.terminal.title") } else { shown }
    }
  }
  let meta = fn() {
    if ended() { @sf.t("web-pages.terminal.ended") } else { cwd() }
  }
  // (one who may type: every member but a read-only one, as the station's terminals say)
  let listed = src.topic("terminals", { "station": str(at.station) })
  let may = fn() { flag(listed.get().value, "open") }
  let take = fn() { (src.call)("terminal.take", obj([("view", str(view))]), @sfbase.answer_unread) }
  v.grow(Is(1.0)).ground(By(fn() { @sf.theme().p.bg })) |> ignore
  // its head (@sf.opened_head_node: a viewer's bar in a wide frame, a phone's in a phone's): back, where it is, its ⋯
  // (复制工作目录; 结束会话 for one who may, while it runs); under it who else types and 接管, or 只看 and 控制
  @sf.opened_head_node(
    v,
    back,
    title,
    meta,
    cwd,
    top,
    width is Some(_),
    fn(m) {
      let (x, y, w, h) = m.placed_window_now()
      let id = text(@signals.untracked(s), "id")
      @sf.menu(
        [
          Some(@sf.menu_item_of(@sf.t("web-pages.terminal.copyCwd"), icon="copy", fn() { @ui.clipboard_set(@signals.untracked(cwd)) })),
          if @signals.untracked(may) && !@signals.untracked(ended) && id != "" {
            Some(@sf.menu_item_of(@sf.t("web-pages.terminal.end"), icon="close", danger=true, fn() {
              (src.call)("terminal.end", obj([("station", str(at.station)), ("terminal", str(id))]), @sfbase.answer_unread)
            }))
          } else {
            None
          },
        ],
        from=At(x, y, w, h),
        along=End,
      )
    },
    on_back,
    // (who else types, and 接管; or that it is only looked at, and 控制: for one who may, while it runs)
    fn() {
      if !may() || types() || ended() {
        ""
      } else if typing() != "" {
        @sf.t("web-pages.screen.controlling", args=[("names", typing())])
      } else {
        @sf.t("web-pages.screen.look")
      }
    },
    fn() { if typing() != "" { @sf.t("android-misc.screen.takeOver") } else { @sf.t("web-pages.screen.control") } },
    take,
  )
  // the screen under it: the rest of the window, on the terminal's own ground
  v.box(fn(k) {
    k
    .grow(Is(1.0))
    .min_height(Is(Some(0.0)))
    .ground(Is(terminal_ground))
    .padding(Is((terminal_in, terminal_over, terminal_in, terminal_over)))
    .clips(Is(true))
    |> ignore
    k.box(fn(w) {
      w
      .words_runs(By(fn() {
        drawn.get() |> ignore
        match kept.val {
          Some(t) => terminal_runs(t.lines())
          None => []
        }
      }), look={ size: terminal_size, weight: 400, line: terminal_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
      .words_breaks(Is(true))
      .ink(Is(terminal_ink))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
