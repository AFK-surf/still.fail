// What waits, drawn one way everywhere (web/ui waiting.tsx, waiting.css.ts, styles/spinner.css.ts; docs/ui-panels.md
// 「等待」; Android's ui/Waiting.kt the same), the phone's pages and the desktop's alike. Three kinds:
// - a page or a list read for the first time: `waiting`, what will come drawn as it will be, of made-up words, in its
//   bones (`bones`: its words bars, its pictures and icons shapes, its outline its own), breathing, no words; what
//   could not be read said over them in red;
// - a row or a button at work: `spinner` in its place, in one of two sizes (14, 12 in a line of small text);
// - what has a size on its way: `progress`; in a spinner's place (a line saying how far, a picture going up),
//   `progress_spinner`.
// Words (a pill, a line) come only after a moment (later_ms), so what is there at once shows none; what failed says so
// at once, in red.

///|
/// Words about a wait show only once it has taken this long.
pub let later_ms : Double = 400.0

///|
/// Whether `key` has been waited on for later_ms, since the first frame that asked (@kit.after's clock: a frame comes
/// when it has).
fn waited_long(c : @ui.Ctx, key : String) -> Bool {
  @kit.after(c, "sf-wait/" + key, true, later_ms)
}

///|
/// Forgets a wait, so the next one on `key` waits its 400ms again.
pub fn done_waiting(c : @ui.Ctx, key : String) -> Unit {
  @kit.after(c, "sf-wait/" + key, false, later_ms) |> ignore
}

///|
/// What waits, node `node`, breathing (the placeholders, to 0.5: waiting.css.ts breathe; a service restarting, its dot
/// to 0.35: Jobs.css.ts jobBreathe): whole to `low` and back in breath_ms, each way on CSS's ease-in-out, worked out as
/// each frame is drawn, never built anew for it (Ctx::cycle_look); still and whole when what it waits on failed (the
/// red words over them say so: faded, they were drawn too faint to be seen, docs/ui-panels.md 对比度). `resident`: a
/// state's for as long as it lasts (a service restarting), on the one clock's steps, not a wait's (Ctx::cycle).
pub fn breathe(
  c : @ui.Ctx,
  node : Int,
  failed? : Bool = false,
  low? : Double = 0.5,
  resident? : Bool = false,
) -> Unit {
  if failed {
    return
  }
  c.cycle_look(
    node,
    breath_ms,
    fn(f) {
      let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
      @ui.look(alpha=1.0 - (1.0 - low) * @ui.Ease::InOut.at(way))
    },
    resident~,
  )
}

///|
/// A placeholder bar (a title's, a line's, a picture's): in the line's grey, as what is drawn with nothing in it is
/// (contrast.mbt), round; `breathing`, on the placeholders' breath by itself (Stations.kt Bar).
pub fn bar(
  c : @ui.Ctx,
  w : @ui.Size,
  h : Double,
  radius? : Double = -1.0,
  breathing? : Bool = false,
) -> Unit {
  let t = theme()
  let b = c.box(w~, h=Px(h), bg=t.p.line, radius=if radius >= 0.0 { radius } else { h / 2.0 }, fn() {  })
  if breathing {
    breathe(c, b)
  }
}

///|
/// What is waited on (WaitPill: a spinner before it), or what is wrong (`error`: in red, at once, no spinner): a grey
/// capsule, its words 12 on 18; what is waited on only after later_ms.
pub fn wait_pill(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && !waited_long(c, "pill/" + key + text) {
    return
  }
  c.box(dir=Row, padx=12.0, pady=6.0, gap=8.0, bg=t.p.neutral_bg, radius=15.0, align=ACenter, fn() {
    if !error {
      spinner(c, size=spinner_inline) |> ignore
    }
    c.text(
      text,
      size=t.t.meta,
      color=if error { t.p.red } else { t.p.muted },
      line=18.0,
      center=true,
    )
    |> ignore
  })
  |> ignore
}

///|
/// WaitLine's words: 13/18 on every width (Waiting.kt: fontSize 13.sp, lineHeight 18.sp).
// kept across runs: a value (no field of it changes)
let wait_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5)

///|
/// A small part still on its way (WaitLine): a 12 spinner and grey words
/// after later_ms; red words and no spinner when it failed.
pub fn wait_line(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && !waited_long(c, "line/" + key + text) {
    c.box(h=Px(18.0), fn() {  }) |> ignore
    return
  }
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    if !error {
      spinner(c, size=12.0) |> ignore
    }
    c.text(text, style=wait_words, color=if error { t.p.red } else { t.p.muted }) |> ignore
  })
  |> ignore
}

///|
/// How much of `key` (what has a size: a download, a transfer) has come (Progress): mbui's progress bar (@kit.progress)
/// in still.fail's look, a 3 high pill on the line's grey, going to a part told anew over 200 ms; `part` None when
/// the whole is not known, a 40% piece sweeping across.
pub fn progress(c : @ui.Ctx, key : String, part : Double?, w? : @ui.Size = Fill(1.0), color? : Int64) -> Unit {
  let accent = color.unwrap_or(theme().p.accent)
  @kit.progress(
    c,
    key,
    match part {
      Some(k) => Some(k * 100.0)
      None => None
    },
    max=100.0,
    w~,
    look=@kit.progress_look_of(fill=accent),
  )
}


///|
/// The spinner's line: 2 wide (Waiting.kt Spinner: Stroke(2.dp)).
let spin_stroke : Double = 2.0

///|
/// How long the spinner takes to turn once (styles/spinner.css.ts: 0.8s).
pub let spinner_turn_ms : Double = 800.0

///|
/// The spinner (styles/spinner.css.ts, Waiting.kt Spinner): a ring of line_strong, a quarter of it in the accent,
/// turning in 0.8s; 14, or 12 in a line of small text. `sweep` (of a turn) and `period` for other rings that turn (a
/// chat's mark at work: three quarters, 1.2s). Its lines drawn once (mbui's Ctx::lines), turned by the clock as each
/// frame is drawn (Ctx::cycle_look): nothing built anew for it, nothing to make, nothing to wait for. `stroke` its
/// line's width (an icon's, where it is drawn as one: @sf.coming_mark).
pub fn spinner(
  c : @ui.Ctx,
  size? : Double = 14.0,
  stroke? : Double = spin_stroke,
  ring? : Int64,
  arc? : Int64,
  sweep? : Double = 0.25,
  period? : Double = spinner_turn_ms,
) -> Int {
  let t = theme()
  let ring = ring.unwrap_or(t.p.line_strong)
  let arc = arc.unwrap_or(t.p.accent)
  let pi = 3.141592653589793
  // the line's middle 1 in from the edge; the arc from a quarter before the top (the web's: a border whose top is
  // the arc), the two turned by the clock about the ring's middle
  let mid = size / 2.0
  let r = mid - stroke / 2.0
  let node = c.lines(
    [
      @ui.line(@ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi), width=stroke, color=ring),
      @ui.line(@ui.arc(mid, mid, r, from=-0.75 * pi, sweep=sweep * 2.0 * pi), width=stroke, color=arc),
    ],
    w=Px(size),
    h=Px(size),
  )
  c.cycle_look(node, period, fn(f) { @ui.look(rot=f * 2.0 * pi) })
  node
}

///|
/// A station gone for its update (a chat's row, the line over its composer): two arrows chasing each other round a
/// ring, each three eighths of it with its head at its end, turning the way they point, once in
/// `updating_turn_ms`, drawn in an icon's place (`size`, the box the icons beside it are drawn in, in `color`, a line as
/// wide as theirs; the ring where check-circle draws its circle, 3.5 to 20.5 of their 24 grid). The two the same half
/// a turn apart, so what it draws is as wide each side of its middle and turns about it (Ctx::cycle_look turns a look
/// about the middle of what it drew: one arrow alone, its head out to one side, wobbled as it turned). Turned by the
/// clock as each frame is drawn, smoothly, at the frame rate: an update is over in a little while, no mark that stays
/// for hours.
pub fn updating_mark(c : @ui.Ctx, size : Double, color : Int64) -> Int {
  let pi = 3.141592653589793
  let k = size / 24.0
  let stroke = 1.75 * k
  let mid = size / 2.0
  let r = 8.5 * k
  let back = 3.0 * k
  let side = 2.5 * k
  let sweep = 0.75 * pi
  let lines = []
  for from in [-0.5 * pi, 0.5 * pi] {
    // its arc, then its head at the end: two strokes `back` behind it along the ring, either side of it
    let end = from + sweep
    let (ex, ey) = (mid + r * @dmath.cos(end), mid + r * @dmath.sin(end))
    let (tx, ty) = (-@dmath.sin(end), @dmath.cos(end))
    let (nx, ny) = (@dmath.cos(end), @dmath.sin(end))
    lines.push(@ui.line(@ui.arc(mid, mid, r, from~, sweep~), width=stroke, color~))
    lines.push(
      @ui.line(
        [
          (ex - back * tx + side * nx, ey - back * ty + side * ny),
          (ex, ey),
          (ex - back * tx - side * nx, ey - back * ty - side * ny),
        ],
        width=stroke,
        color~,
      ),
    )
  }
  let node = c.lines(lines, w=Px(size), h=Px(size))
  c.cycle_look(node, updating_turn_ms, fn(f) { @ui.look(rot=f * 2.0 * pi) })
  node
}

///|
/// How long the update's mark takes to turn once (updating_mark).
pub let updating_turn_ms : Double = 1200.0

///|
/// The spinner, or how far what it waits on has come once that is known (docs/ui-panels.md 等待: a transfer in a
/// spinner's place, a message's files going up, a picture going up, an update round its key's mark): the same ring,
/// the accent from its top as far round as it has come (`coming`, 0 to 1), going to a part told anew as a progress
/// bar's fill does (`key` its own); None, the spinner's quarter turning. `size` across, its line `stroke` wide.
pub fn progress_spinner(
  c : @ui.Ctx,
  key : String,
  coming : Double?,
  size? : Double = 14.0,
  stroke? : Double = spin_stroke,
) -> Int {
  match coming {
    None => spinner(c, size~, stroke~)
    Some(k) => {
      let t = theme()
      let pi = 3.141592653589793
      let mid = size / 2.0
      let r = mid - stroke / 2.0
      let k = if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }
      let shown = @motion.animate(c, key + "/coming", k, spec=@motion.tween(@kit.progress_ms, ease=Out))
      let ring = @ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi)
      let lines = [@ui.line(ring, width=stroke, color=t.p.line_strong)]
      if shown > 0.0 {
        let arc = @ui.arc(mid, mid, r, from=-0.5 * pi, sweep=shown * 2.0 * pi)
        lines.push(@ui.line(arc, width=stroke, color=t.p.accent))
      }
      c.lines(lines, w=Px(size), h=Px(size))
    }
  }
}

///|
/// What a page or a list waits on (WaitNote), from the core's note (a list's ListNote) or the page's own words: still
/// reading (its placeholders breathe), what it waits on (正在读取会话, 正在连接 Studio: said to a screen reader), what
/// could not be read (each said in red).
pub(all) struct WaitNote {
  reading : Bool
  text : String
  failing : Array[String]
}

///|
/// Made-up words `n` letters long, for what a page's bones are drawn of (`waiting`'s `sample`): only how long they are
/// is seen, as a bar.
pub fn sample_words(n : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<n {
    out.write_char('字')
  }
  out.to_string()
}

///|
/// What will come, in its bones (@ui's Ctx::bones: its words bars, its pictures and icons shapes, on its own grounds,
/// in the line's grey), breathing; still and whole (`still`) as what they wait on failed. As wide as what it holds
/// where that stands in a row, as wide as its column in one; `fill`: the room left (a page's body).
pub fn bones(c : @ui.Ctx, sample : () -> Unit, still? : Bool = false, fill? : Bool = false) -> Unit {
  // (in bones already, as they are: one breath)
  if c.in_bones() {
    sample()
    return
  }
  let b = c.box(style=if fill { wait_fill } else { bones_box }, fn() { c.bones(theme().p.line, sample) })
  breathe(c, b, failed=still)
}

///|
/// A page's or a list's content while it is read the first time (Waiting): what will come in its bones (`sample`: what
/// it will show, made of made-up words by the parts that draw it when it comes, its rows, its cards, its messages:
/// their outline its own), breathing; what it waits on (`note`'s words, else `text`, else 正在读取) said only to a
/// screen reader; over them in red what could not be read (`error`, `note`'s failing), each in a pill, the bones then
/// still. `fill`: it takes the room left (a page's body); otherwise as tall as its bones. What `body` holds goes
/// between the pills and the bones.
pub fn waiting(
  c : @ui.Ctx,
  sample : () -> Unit,
  text? : String = "",
  error? : String = "",
  note? : WaitNote,
  fill? : Bool = false,
  body? : () -> Unit,
) -> Unit {
  let failing : Array[String] = if error != "" { [error] } else { [] }
  match note {
    Some(n) => failing.append(n.failing)
    None => ()
  }
  let reading = error == "" &&
    (match note {
      Some(n) => n.reading
      None => true
    })
  let said = match note {
    Some(n) if n.text != "" => n.text
    _ => text
  }
  let w = c.box(style=if fill { wait_fill } else { wait_box }, fn() {
    if failing.length() > 0 {
      c.box(style=wait_pills, fn() {
        for f in failing {
          wait_pill(c, f, error=true)
        }
      })
      |> ignore
    }
    match body {
      Some(f) => f()
      None => ()
    }
    bones(c, sample, still=!reading, fill~)
  })
  if reading && said != "" {
    c.semantics(w, Status, label=said)
  }
}

///|
/// A list with rows already, still waiting on some of it (WaitMore: a station not read yet, one that could not be):
/// under its rows one more of them in its bones (`sample`) for what is still read, and each failure in red. Nothing
/// once it waits on nothing.
pub fn wait_more(c : @ui.Ctx, note : WaitNote?, sample : () -> Unit) -> Unit {
  match note {
    Some(n) => {
      if n.reading {
        bones(c, sample)
      }
      for f in n.failing {
        wait_line(c, f, error=true)
      }
    }
    None => ()
  }
}

///|
// kept across runs: a value (no field of it changes)
let wait_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let wait_fill : @ui.Style = @ui.css("w=Full h=Grow(1.0)")

///|
// kept across runs: a value (no field of it changes)
let bones_box : @ui.Style = @ui.css("")

///|
/// The pills over the bones: 14 under the top, 20 in, 4 over the bones, 8 apart, in the middle.
// kept across runs: a value (no field of it changes)
let wait_pills : @ui.Style = @ui.css("w=Full px=S5 pt=S3_5 pb=S1 gap=S2 align=ACenter")
