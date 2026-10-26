// Photos, in still.fail's design (src/sf): the timeline as a page of days,
// each a grid of square pictures (their ThumbHash first, the picture fading
// in over it); a picture pressed opens over the whole window on black,
// turned sideways to the next, its bar a tap away.

///|
struct State {
  /// the item open in the viewer, in the timeline's order
  mut open : Int?
  mut bars : Bool
}

///|
let state : State = { open: None, bars: true }

///|
priv enum Row {
  Head
  DayHead(Int)
  /// a day's items from `start`, a row of the grid
  Cells(Int, Int)
  Foot
}

///|
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  @sf.begin(c) |> ignore
  let got = (src.days)()
  match (state.open, got) {
    (Some(i), Some(Ok(days))) => viewer(c, src, days, i)
    _ => timeline(c, src, got)
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// Dates

///|
fn digits(s : String, from : Int, n : Int) -> Int {
  let mut v = 0
  for i in from..<(from + n) {
    let ch = s.view(start_offset=i, end_offset=i + 1).to_string()
    let d = match ch.get_char(0) {
      Some(c) => c.to_int() - 48
      None => 0
    }
    v = v * 10 + (if d >= 0 && d <= 9 { d } else { 0 })
  }
  v
}

///|
/// "10月18日 周六" for "2026-10-18", the year before it when not `year`.
fn day_label(day : String, year : Int) -> String {
  if day.length() < 10 {
    return day
  }
  let y = digits(day, 0, 4)
  let m = digits(day, 5, 2)
  let d = digits(day, 8, 2)
  // Sakamoto's: 0 Sunday
  let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
  let yy = if m < 3 { y - 1 } else { y }
  let wd = (yy + yy / 4 - yy / 100 + yy / 400 + t[(m + 11) % 12] + d) % 7
  let names = ["日", "一", "二", "三", "四", "五", "六"]
  let date = if y == year { "\{m}月\{d}日" } else { "\{y}年\{m}月\{d}日" }
  date + " 周" + names[wd]
}

///|
fn duration_label(s : Double) -> String {
  let t = s.round().to_int()
  let sec = t % 60
  let min = t / 60 % 60
  let h = t / 3600
  let two = fn(v : Int) { if v < 10 { "0\{v}" } else { "\{v}" } }
  if h > 0 {
    "\{h}:\{two(min)}:\{two(sec)}"
  } else {
    "\{min}:\{two(sec)}"
  }
}

// ---------------------------------------------------------------------------
// The timeline

///|
/// The grid's measures: columns, a cell's side, the gap, the inset.
fn grid(c : @ui.Ctx) -> (Int, Double, Double, Double) {
  let t = @sf.theme()
  // edge to edge on a phone, as its photos are; in the page's column wide
  let inset = if small(c) { 0.0 } else { 40.0 }
  let gap = if small(c) { 2.0 } else { 4.0 }
  let room = dmin(c.width - 2.0 * inset, 1400.0)
  let least = if small(c) { 88.0 } else { 150.0 }
  let mut cols = ((room + gap) / (least + gap)).floor().to_int()
  if cols < 3 {
    cols = 3
  }
  let side = ((room - gap * (cols - 1).to_double()) / cols.to_double()).floor()
  (cols, side, gap, inset)
}

///|
fn timeline(c : @ui.Ctx, src : Source, got : Result[Array[Day], String]?) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let (cols, side, gap, inset) = grid(c)
  let head_pad = if small(c) { 20.0 } else { 40.0 }
  c.column(w=Fill(1.0), h=Fill(1.0), bg=p.bg, fn() {
    let days = match got {
      Some(Ok(d)) => d
      Some(Err(why)) => {
        head(c, head_pad, "")
        shapes(c, cols, side, gap, inset, error=Some(why))
        return
      }
      None => {
        head(c, head_pad, "")
        shapes(c, cols, side, gap, inset)
        return
      }
    }
    let mut n = 0
    for d in days {
      n = n + d.items.length()
    }
    if n == 0 {
      head(c, head_pad, "")
      empty(c)
      return
    }
    let rows : Array[Row] = [Head]
    for di, d in days {
      rows.push(DayHead(di))
      let mut k = 0
      while k < d.items.length() {
        rows.push(Cells(di, k))
        k = k + cols
      }
    }
    rows.push(Foot)
    let year = if days.length() > 0 { digits(days[0].day, 0, 4) } else { 0 }
    // where each day starts in the timeline's order (the viewer's index)
    let starts = []
    let mut at = 0
    for d in days {
      starts.push(at)
      at = at + d.items.length()
    }
    c.list("timeline", rows.length(), side + gap, fn(r) {
      if r >= rows.length() - 4 {
        (src.older)()
      }
      match rows[r] {
        Head => head(c, head_pad, "\{n} 张")
        DayHead(di) =>
          c.box(
            dir=Row,
            pl=if small(c) { 16.0 } else { inset },
            pr=inset,
            pt=if di == 0 { 4.0 } else { 20.0 },
            pb=8.0,
            gap=8.0,
            align=AEnd,
            fn() {
              c.text(
                day_label(days[di].day, year),
                size=t.t.ui,
                weight=600,
                color=p.text,
                wrap=false,
                line=t.t.ui_line,
              )
              |> ignore
              c.text(
                "\{days[di].items.length()} 张",
                size=t.t.meta,
                color=p.muted,
                wrap=false,
                line=t.t.ui_line,
              )
              |> ignore
            },
          )
          |> ignore
        Cells(di, start) =>
          c.box(dir=Row, pl=inset, pr=inset, pb=gap, gap~, fn() {
            let items = days[di].items
            for k in start..<(start + cols) {
              if k < items.length() {
                cell(c, src, items[k], starts[di] + k, side)
              }
            }
          })
          |> ignore
        Foot => c.box(h=Px(if small(c) { 24.0 } else { 64.0 }), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
fn head(c : @ui.Ctx, pad : Double, meta : String) -> Unit {
  let t = @sf.theme()
  c.box(
    pl=pad,
    pr=if small(c) { 12.0 } else { pad },
    pt=if small(c) { 14.0 } else { 32.0 },
    pb=if small(c) { 6.0 } else { 12.0 },
    fn() { @sf.page_head(c, "照片", meta~) },
  )
  |> ignore
}

///|
/// A picture in the grid: its ThumbHash, its picture fading in over it; a
/// video's length at its foot.
fn cell(c : @ui.Ctx, src : Source, it : Item, index : Int, side : Double) -> Unit {
  let t = @sf.theme()
  let id = c.id("cell-" + it.id)
  if c.clicked(id) {
    state.open = Some(index)
    state.bars = true
  }
  let radius = if small(c) { 0.0 } else { 6.0 }
  c.box(w=Px(side), h=Px(side), radius~, clip=true, bg=t.p.neutral_bg, id~, fn() {
    match thumbhash_image(it.thumbhash) {
      Some(k) =>
        c.image(k, w=Px(side), h=Px(side), radius~, bg=0L, fade=false) |> ignore
      None => ()
    }
    c.layer(fn() {
      c.image((src.thumb)(it), w=Px(side), h=Px(side), radius~, bg=0L) |> ignore
    })
    |> ignore
    if it.video {
      c.layer(align=AEnd, fn() {
        c.spacer()
        c.box(dir=Row, pad=6.0, fn() {
          c.box(dir=Row, padx=6.0, pady=2.0, gap=3.0, align=ACenter, bg=0x00000066L, radius=9.0, fn() {
            @sf.icon(c, "play", size=10.0, color=0xFFFFFFFFL) |> ignore
            match it.duration {
              Some(d) =>
                c.text(duration_label(d), size=t.t.caption, weight=500, color=0xFFFFFFFFL, wrap=false)
                |> ignore
              None => ()
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // pressed: a step darker
    if c.pressed(id) || (!small(c) && c.hovered(id)) {
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          bg=if c.pressed(id) { 0x00000033L } else { 0x00000014L },
          fn() {  },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The first read (Waiting): the grid's shapes, breathing; what could not
/// be read in a red pill over them, the shapes still.
fn shapes(
  c : @ui.Ctx,
  cols : Int,
  side : Double,
  gap : Double,
  inset : Double,
  error? : String? = None,
) -> Unit {
  let t = @sf.theme()
  match error {
    Some(why) =>
      c.box(align=ACenter, pt=14.0, pb=12.0, padx=20.0, fn() {
        @sf.wait_pill(c, why, error=true)
      })
      |> ignore
    None => ()
  }
  let wait = c.box(w=Fill(1.0), h=Fill(1.0), clip=true, gap~, fn() {
    c.box(pl=if small(c) { 16.0 } else { inset }, pt=4.0, pb=4.0, fn() {
      @sf.bar(c, Px(120.0), 13.0)
    })
    |> ignore
    for _ in 0..<8 {
      c.box(dir=Row, pl=inset, pr=inset, gap~, fn() {
        for _ in 0..<cols {
          @sf.bar(c, Px(side), side, radius=if small(c) { 0.0 } else { 6.0 })
        }
      })
      |> ignore
    }
  })
  @sf.breathe(c, wait, failed=error is Some(_))
}

///|
fn empty(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, gap=12.0, padx=40.0, fn() {
    @sf.icon(c, "photo", size=28.0, color=t.p.muted) |> ignore
    c.text("还没有照片", size=t.t.ui, weight=500, color=t.p.text, wrap=false)
    |> ignore
    c.text(
      "station 扫到的照片和视频会按拍摄日期排在这里。",
      size=t.t.ui,
      color=t.p.muted,
      line=t.t.ui_line,
    )
    |> ignore
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// The viewer

///|
fn flat(days : Array[Day]) -> Array[(Int, Item)] {
  let out = []
  for di, d in days {
    for it in d.items {
      out.push((di, it))
    }
  }
  out
}

///|
fn viewer(c : @ui.Ctx, src : Source, days : Array[Day], index : Int) -> Unit {
  let t = @sf.theme()
  let all = flat(days)
  if all.length() == 0 {
    state.open = None
    return
  }
  let index = if index >= all.length() { all.length() - 1 } else { index }
  let year = digits(days[0].day, 0, 4)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0x000000FFL, fn() {
    let shown = c.pager(
      "viewer",
      all.length(),
      index,
      fn(i) {
        let (_, it) = all[i]
        c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
          picture(c, src, it)
        })
        |> ignore
      },
      on_middle=fn() { state.bars = !state.bars },
    )
    if shown != index {
      state.open = Some(shown)
    }
  })
  |> ignore
  let (di, it) = all[index]
  let k = c.spring("viewer-bars", if state.bars { 1.0 } else { 0.0 }, stiffness=600.0, damping=50.0)
  if k > 0.01 {
    c.layer(fn() {
      c.box(align=ACenter, pt=8.0, opacity=k, ty=-6.0 * (1.0 - k), fn() {
        c.box(
          dir=Row,
          w=Px(dmin(c.width - 24.0, 720.0)),
          h=Px(48.0),
          padx=6.0,
          align=ACenter,
          bg=0x2A2C31B8L,
          radius=16.0,
          fn() {
            c.box(dir=Row, w=Px(84.0), fn() {
              if @sf.icon_button(
                  c,
                  "chevron-left",
                  key="viewer-back",
                  size=36.0,
                  icon_size=20.0,
                  ink=0xECECEDFFL,
                  quiet=0xECECEDFFL,
                ) {
                state.open = None
              }
            })
            |> ignore
            c.box(w=Fill(1.0), align=ACenter, fn() {
              c.text(
                day_label(days[di].day, year),
                size=t.t.ui,
                weight=600,
                color=0xECECEDFFL,
                wrap=false,
                line=18.0,
              )
              |> ignore
              c.text(
                it.time + " · \{index + 1} / \{all.length()}",
                size=t.t.caption,
                color=0x9A9DA3FFL,
                wrap=false,
                line=15.0,
              )
              |> ignore
            })
            |> ignore
            c.box(w=Px(84.0), fn() {  }) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// One picture, as large as the window lets it, its ThumbHash under it
/// while the large one comes; a video's play mark over it.
fn picture(c : @ui.Ctx, src : Source, it : Item) -> Unit {
  let k = if it.w > 0.0 && it.h > 0.0 {
    dmin(c.width / it.w, c.height / it.h)
  } else {
    1.0
  }
  // its size unknown: the window's, the picture fitted in it
  let known = it.w > 0.0 && it.h > 0.0
  let w = if known { (it.w * k).floor() } else { c.width }
  let h = if known { (it.h * k).floor() } else { c.height }
  let fit : @ui.Fit = if known { FitCover } else { FitContain }
  c.box(w=Px(w), h=Px(h), fn() {
    match thumbhash_image(it.thumbhash) {
      Some(key) =>
        c.image(key, w=Px(w), h=Px(h), fit=FitFill, bg=0L, fade=false) |> ignore
      None => ()
    }
    c.layer(fn() {
      // the grid's picture first (it is here already), the large over it
      c.image((src.thumb)(it), w=Px(w), h=Px(h), fit~, bg=0L) |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.image((src.large)(it), w=Px(w), h=Px(h), fit~, bg=0L) |> ignore
    })
    |> ignore
    if it.video {
      c.layer(align=ACenter, fn() {
        c.box(h=Fill(1.0), justify=JCenter, fn() {
          c.box(w=Px(64.0), h=Px(64.0), radius=32.0, bg=0x00000066L, align=ACenter, justify=JCenter, fn() {
            @sf.icon(c, "play", size=28.0, color=0xFFFFFFFFL) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// Laid out for a small screen (the window's width alone, @sf.layout): edge to edge, a phone's measures. The screen
/// says how the page is laid out; the colours are one on every screen (@sf.begin).
fn small(c : @ui.Ctx) -> Bool {
  @sf.layout(c.window_size().0) is Small
}
