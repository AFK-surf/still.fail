// What waits, drawn one way everywhere (web/ui waiting.tsx, waiting.css.ts, styles/spinner.css.ts; docs/ui-panels.md
// 「等待」; Android's ui/Waiting.kt the same), the phone's pages and the desktop's alike. Three kinds:
// - a page or a list read for the first time: `waiting`, placeholders shaped as what will come (`wait_shapes`: rows,
//   messages, cards), breathing, no words; what could not be read said over them in red;
// - a row or a button at work: `spinner` in its place, in one of two sizes (14, 12 in a line of small text);
// - what has a size on its way: `progress`.
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
/// What waits breathing (the placeholders, to 0.5: waiting.css.ts breathe; a service restarting, its dot to 0.35:
/// Jobs.css.ts jobBreathe), how much of it shows now: whole to `low` and back in breath_ms, each way on CSS's
/// ease-in-out; 0.6 when what it waits on failed. `resident`: a state's for as long as it lasts (a service
/// restarting), on the one clock's steps, not a wait's (Ctx::cycle).
pub fn breath(
  c : @ui.Ctx,
  failed? : Bool = false,
  low? : Double = 0.5,
  resident? : Bool = false,
) -> Double {
  if failed {
    return 0.6
  }
  let f = c.cycle(breath_ms, resident~)
  let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
  1.0 - (1.0 - low) * @ui.Ease::InOut.at(way)
}

///|
/// A placeholder bar (a title's, a line's, a picture's): the neutral grey,
/// round; `breathing`, on the placeholders' breath by itself (Stations.kt Bar).
pub fn bar(
  c : @ui.Ctx,
  w : @ui.Size,
  h : Double,
  radius? : Double = -1.0,
  breathing? : Bool = false,
) -> Unit {
  let t = theme()
  let seen = if breathing { breath(c) } else { 1.0 }
  c.box(
    w~,
    h=Px(h),
    bg=t.p.neutral_bg,
    radius=if radius >= 0.0 { radius } else { h / 2.0 },
    opacity=seen,
    fn() {  },
  )
  |> ignore
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
/// in still.fail's look, a 3 high pill on 18% of the accent, going to a part told anew over 200 ms; `part` None when
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
/// chat's mark at work: three quarters, 1.2s). Its lines drawn as they are every frame (mbui's Ctx::lines), only where
/// the arc starts going round with the clock: nothing to make, nothing to wait for.
pub fn spinner(
  c : @ui.Ctx,
  size? : Double = 14.0,
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
  // the arc), turned by the clock
  let mid = size / 2.0
  let r = mid - spin_stroke / 2.0
  let from = -0.75 * pi + c.cycle(period) * 2.0 * pi
  c.lines(
    [
      @ui.line(@ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi), width=spin_stroke, color=ring),
      @ui.line(@ui.arc(mid, mid, r, from~, sweep=sweep * 2.0 * pi), width=spin_stroke, color=arc),
    ],
    w=Px(size),
    h=Px(size),
  )
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
/// The shapes of what will come (WaitShape): a list's rows (a title and a line, a picture at the end), a chat's
/// messages, a settings page's cards.
pub(all) enum WaitShape {
  Rows
  Messages
  Cards
} derive(Eq)

///|
/// The placeholders' widths (waiting.tsx TITLES, LINES, MESSAGES, CARDS): a row's title and line, a message (mine or
/// not, its width, its height), a card's height.
// kept across runs: a table, never written
let wait_titles : Array[Double] = [150.0, 110.0, 170.0, 130.0, 96.0, 160.0, 120.0]

///|
// kept across runs: a table, never written
let wait_lines : Array[Double] = [230.0, 190.0, 250.0, 170.0, 210.0, 200.0, 180.0]

///|
// kept across runs: a table, never written
let wait_messages : Array[(Bool, Double, Double)] = [
  (false, 220.0, 40.0),
  (false, 160.0, 58.0),
  (true, 180.0, 40.0),
  (false, 240.0, 76.0),
  (true, 120.0, 40.0),
  (false, 200.0, 40.0),
]

///|
// kept across runs: a table, never written
let wait_cards : Array[Double] = [120.0, 88.0, 152.0, 104.0]

///|
/// The shapes of what will come (WaitShapes, waiting.css.ts): `Rows` (7 by default) 66 high, 22 in at their start and
/// 16 at their end, a title 13 and a line 10 high 10 apart, a picture 22 round at the end (`dense`: 40 high, 10 in,
/// the bars 0.6 as long and lower, no picture); `Messages`: 14 apart, 8 under the top, 16 in, a face 28 before each not
/// mine, its bubble 18 round, 70% of the width at most; `Cards` (3) 16 apart, a card's corner. Breathing (`still`: at
/// 0.6, as what they wait on failed).
pub fn wait_shapes(
  c : @ui.Ctx,
  shape? : WaitShape = Rows,
  count? : Int,
  dense? : Bool = false,
  still? : Bool = false,
) -> Unit {
  let t = theme()
  let seen = breath(c, failed=still)
  match shape {
    Messages => {
      let most = c.width * wait_bubble_share
      c.box(style=wait_messages_box, opacity=seen, fn() {
        for m in wait_messages {
          let (mine, w, h) = m
          c.box(style=if mine { wait_message_mine } else { wait_message }, fn() {
            if !mine {
              c.box(style=wait_face, bg=t.p.neutral_bg, fn() {  }) |> ignore
            }
            c.box(w=Px(dmin(w, most)), h=Px(h), radius=wait_bubble_r, bg=t.p.neutral_bg, fn() {  }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    Cards =>
      c.box(style=wait_cards_box, opacity=seen, fn() {
        for i in 0..<count.unwrap_or(3) {
          c.box(style=wait_card, h=Px(wait_cards[i % wait_cards.length()]), bg=t.p.neutral_bg, fn() {  }) |> ignore
        }
      })
      |> ignore
    Rows =>
      c.box(style=wait_rows_box, opacity=seen, fn() {
        let k = if dense { wait_dense_share } else { 1.0 }
        for i in 0..<count.unwrap_or(7) {
          c.box(style=if dense { wait_row_dense } else { wait_row }, pl=if dense { wait_dense_in } else { wait_row_in }, fn() {
            c.box(style=if dense { wait_row_lines_dense } else { wait_row_lines }, gap=if dense { wait_dense_gap } else { wait_row_gap }, fn() {
              bar(c, Px(k * wait_titles[i % wait_titles.length()]), if dense { wait_title_dense } else { wait_title_h })
              bar(c, Px(k * wait_lines[i % wait_lines.length()]), if dense { wait_line_dense } else { wait_line_h })
            })
            |> ignore
            if !dense {
              bar(c, Px(wait_picture), wait_picture)
            }
          })
          |> ignore
        }
      })
      |> ignore
  }
}

///|
/// A page's or a list's content while it is read the first time (Waiting): its shapes breathing, what it waits on
/// (`note`'s words, else `text`, else 正在读取) said only to a screen reader; over them in red what could not be read
/// (`error`, `note`'s failing), each in a pill, the shapes then still. `fill`: it takes the room left (a page's body);
/// otherwise as tall as its shapes. What `body` holds goes between the pills and the shapes.
pub fn waiting(
  c : @ui.Ctx,
  shape? : WaitShape = Rows,
  count? : Int,
  dense? : Bool = false,
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
    wait_shapes(c, shape~, count?, dense~, still=!reading)
  })
  if reading && said != "" {
    c.semantics(w, Status, label=said)
  }
}

///|
/// A list with rows already, still waiting on some of it (WaitMore: a station not read yet, one that could not be):
/// under its rows a row's shape for what is still read, and each failure in red. Nothing once it waits on nothing.
pub fn wait_more(c : @ui.Ctx, note : WaitNote?, dense? : Bool = false) -> Unit {
  match note {
    Some(n) => {
      if n.reading {
        wait_shapes(c, count=1, dense~)
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
/// The pills over the shapes: 14 under the top, 20 in, 4 over the shapes, 8 apart, in the middle.
// kept across runs: a value (no field of it changes)
let wait_pills : @ui.Style = @ui.css("w=Full px=S5 pt=S3_5 pb=S1 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wait_rows_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let wait_row : @ui.Style = @ui.style(row=true, w=Full, h=Fixed(wait_row_h), pr=S4, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wait_row_dense : @ui.Style = @ui.css("row w=Full h=S10 pr=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wait_row_lines : @ui.Style = @ui.css("w=Grow(1.0) align=AStart")

///|
// kept across runs: a value (no field of it changes)
let wait_row_lines_dense : @ui.Style = @ui.css("w=Grow(1.0) align=AStart")

///|
// kept across runs: a value (no field of it changes)
let wait_messages_box : @ui.Style = @ui.css("w=Full pt=S2 gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let wait_message : @ui.Style = @ui.css("row w=Full px=S4 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let wait_message_mine : @ui.Style = wait_message.then(@ui.css("justify=JEnd"))

///|
// kept across runs: a value (no field of it changes)
let wait_face : @ui.Style = @ui.css("w=S7 h=S7 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let wait_cards_box : @ui.Style = @ui.css("w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let wait_card : @ui.Style = @ui.css("w=Full radius=Xl3")
