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
/// `share`: how much of its breath it takes (0 … 1), what stops waiting going back to whole over a while, not at once.
pub fn breathe(
  c : @ui.Ctx,
  node : Int,
  failed? : Bool = false,
  low? : Double = 0.5,
  resident? : Bool = false,
  share? : Double = 1.0,
) -> Unit {
  if failed || share <= 0.0 {
    return
  }
  c.cycle_look(
    node,
    breath_ms,
    fn(f) {
      let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
      @ui.look(alpha=1.0 - (1.0 - low) * share * @ui.Ease::InOut.at(way))
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
/// The spinner (`spinner`'s) as a node of the window's tree in `parent`: the same ring and arc, their lines said once
/// (View::lines, in the theme's colours as they change, or `ring` and `arc`'s), turned by the clock about the middle of
/// what its pieces cover as each frame is drawn (View::cycle, View::turn): nothing made again for it while it turns; its turning let go with it.
/// The node.
pub fn spinner_node(
  parent : @view.View,
  size? : Double = 14.0,
  stroke? : Double = spin_stroke,
  ring? : () -> Int64,
  arc? : () -> Int64,
  sweep? : Double = 0.25,
  period? : Double = spinner_turn_ms,
) -> @view.View {
  let pi = 3.141592653589793
  let mid = size / 2.0
  let r = mid - stroke / 2.0
  let ring = ring.unwrap_or(fn() { theme().p.line_strong })
  let arc = arc.unwrap_or(fn() { theme().p.accent })
  // (its points worked out once: only its colours change as it lives)
  let round = @ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi)
  let part = @ui.arc(mid, mid, r, from=-0.75 * pi, sweep=sweep * 2.0 * pi)
  parent.box(fn(v) {
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .lines(By(fn() { [@ui.line(round, width=stroke, color=ring()), @ui.line(part, width=stroke, color=arc())] }))
    // (about the middle of what its pieces cover, as the old one's cycle look turns it)
    .turn(By(fn() { v.cycle(period) * 2.0 * pi }), drawn=true)
    |> ignore
  })
}

///|
/// A station gone for its update (a chat's row, the line over its composer): upgrading, said as it goes on: in a ring
/// (where check-circle draws its circle, 3.5 to 20.5 of the icons' 24 grid) an arrow up, standing a while, then off up
/// through its top as the next comes up from its bottom to stand where it stood, eased in and out, once every
/// `updating_rise_ms`; seen in a round window inside the ring. Drawn in an icon's place (`size`, the box the icons
/// beside it are drawn in, in `color`, a line as wide as theirs). Not a turning ring: that is any wait's (2026-10-29 the
/// user: 这只是个 loading); what goes up is what a newer version is. One arrow in the window at a time, the next a
/// window and an arrow under it: two in it at once drew a sign of their own as they passed. Moved by the clock as each
/// frame is drawn (Ctx::cycle_look), smoothly, at the frame rate: an update is over in a little while, no mark that
/// stays for hours.
pub fn updating_mark(c : @ui.Ctx, size : Double, color : Int64) -> Int {
  let pi = 3.141592653589793
  let k = size / 24.0
  let stroke = 1.75 * k
  let mid = size / 2.0
  // the window the arrows go through: round, inside the ring's line with room to spare
  let window = 13.0 * k
  let wmid = window / 2.0
  // one arrow: its head 3 either side of it and 3 down, its shaft 8 long, standing in the window's middle; the next
  // under it, out of sight until the first is going
  let length = 8.0 * k
  let pitch = window + length
  let arrow = fn(top : Double) -> Array[@ui.Line] {
    [
      @ui.line([(wmid, top), (wmid, top + length)], width=stroke, color~),
      @ui.line([(wmid - 3.0 * k, top + 3.0 * k), (wmid, top), (wmid + 3.0 * k, top + 3.0 * k)], width=stroke, color~),
    ]
  }
  let top = wmid - length / 2.0
  c.box(style=@ui.style(w=Fixed(size), h=Fixed(size), align=ACenter, justify=JCenter), fn() {
    c.lines([@ui.line(@ui.arc(mid, mid, 8.5 * k, from=0.0, sweep=2.0 * pi), width=stroke, color~)], w=Px(size), h=Px(size))
    |> ignore
    c.layer(fn() {
      c.box(style=update_ring_at, fn() {
        c.box(style=@ui.style(w=Fixed(window), h=Fixed(window), radius=Full, clip=true), fn() {
          let lines = arrow(top)
          lines.push_iter(arrow(top + pitch).iter())
          let node = c.lines(lines, w=Px(window), h=Px(window + pitch))
          // standing the first `updating_stand` of the cycle, then going up a pitch, eased in and out
          c.cycle_look(node, updating_rise_ms, fn(f) {
            let g = if f <= updating_stand { 0.0 } else { (f - updating_stand) / (1.0 - updating_stand) }
            let h = 2.0 - 2.0 * g
            let eased = if g < 0.5 { 4.0 * g * g * g } else { 1.0 - h * h * h / 2.0 }
            @ui.look(dy=-eased * pitch)
          })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// How long the update's mark takes from one arrow standing to the next (updating_mark), and how much of it the arrow
/// stands still.
pub let updating_rise_ms : Double = 1400.0

///|
/// (how much of updating_rise_ms an arrow stands)
let updating_stand : Double = 0.4

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
