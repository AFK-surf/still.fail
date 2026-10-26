// Films and series, in still.fail's design (src/sf): a page with what is
// being watched, the films and the series, each a grid of posters (their
// ThumbHash first); one opened is its page: the poster, what it is, play
// (or go on from where it was left), and a series' seasons and episodes.

///|
struct State {
  /// the film or series open, by id, and the season shown
  mut open : String?
  mut season : Int
}

///|
let state : State = { open: None, season: 0 }

///|
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  @sf.begin(c) |> ignore
  match state.open {
    Some(id) => detail_page(c, src, id)
    None => library_page(c, src)
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

///|
/// 1:42:05, 42:05.
fn clock(s : Double) -> String {
  let t = s.floor().to_int()
  let two = fn(v : Int) { if v < 10 { "0\{v}" } else { "\{v}" } }
  let h = t / 3600
  if h > 0 {
    "\{h}:\{two(t / 60 % 60)}:\{two(t % 60)}"
  } else {
    "\{t / 60}:\{two(t % 60)}"
  }
}

///|
/// "1 小时 42 分", "42 分钟".
fn length(s : Double) -> String {
  let m = (s / 60.0).round().to_int()
  if m >= 60 {
    "\{m / 60} 小时 \{m % 60} 分"
  } else {
    "\{m} 分钟"
  }
}

// ---------------------------------------------------------------------------
// The library

///|
priv enum Row {
  Head
  Section(String, Int)
  Posters(Int, Int)
  Foot
}

///|
fn grid(c : @ui.Ctx) -> (Int, Double, Double, Double) {
  let t = @sf.theme()
  let pad = if small(c) { 16.0 } else { 40.0 }
  let tile_pad = if small(c) { 6.0 } else { 8.0 }
  let room = dmin(c.width - 2.0 * pad, 1400.0) + 2.0 * tile_pad
  let gap = if small(c) { 2.0 } else { 4.0 }
  let least = if small(c) { 108.0 } else { 160.0 }
  let mut cols = ((room + gap) / (least + gap)).floor().to_int()
  if cols < 3 {
    cols = 3
  }
  let tile = ((room - gap * (cols - 1).to_double()) / cols.to_double()).floor()
  (cols, tile, gap, pad - tile_pad)
}

///|
fn library_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let (cols, tile, gap, inset) = grid(c)
  let pad = if small(c) { 20.0 } else { 40.0 }
  c.column(w=Fill(1.0), h=Fill(1.0), bg=p.bg, fn() {
    let lib = match (src.library)() {
      Some(Ok(l)) => l
      Some(Err(why)) => {
        head(c, pad, "")
        shapes(c, cols, tile, gap, inset, error=Some(why))
        return
      }
      None => {
        head(c, pad, "")
        shapes(c, cols, tile, gap, inset)
        return
      }
    }
    if lib.movies.length() + lib.shows.length() == 0 {
      head(c, pad, "")
      empty(c)
      return
    }
    let lists = [lib.recent, lib.movies, lib.shows]
    let names = ["继续观看", "电影", "剧集"]
    let rows : Array[Row] = [Head]
    for k, list in lists {
      if list.length() > 0 {
        rows.push(Section(names[k], list.length()))
        // what is being watched: one row of them
        let n = if k == 0 && list.length() > cols { cols } else { list.length() }
        let mut i = 0
        while i < n {
          rows.push(Posters(k, i))
          i = i + cols
        }
      }
    }
    rows.push(Foot)
    let meta = "\{lib.movies.length()} 部电影 · \{lib.shows.length()} 部剧"
    c.list("videos", rows.length(), tile * 1.5 + 60.0, fn(r) {
      match rows[r] {
        Head => head(c, pad, meta)
        Section(name, n) =>
          c.box(
            dir=Row,
            pl=if small(c) { 20.0 } else { 40.0 },
            pr=pad,
            pt=20.0,
            pb=8.0,
            gap=8.0,
            align=AEnd,
            fn() {
              c.text(name, size=t.t.title, weight=600, color=p.text, wrap=false, line=t.t.title_line)
              |> ignore
              c.text("\{n}", size=t.t.meta, color=p.muted, wrap=false, line=t.t.title_line)
              |> ignore
            },
          )
          |> ignore
        Posters(k, start) =>
          c.box(dir=Row, pl=inset, pr=inset, pb=gap, gap~, align=AStart, fn() {
            let list = lists[k]
            for i in start..<(start + cols) {
              if i < list.length() {
                poster_tile(c, src, list[i], tile, k == 0)
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
    pb=if small(c) { 6.0 } else { 4.0 },
    fn() { @sf.page_head(c, "影视", meta~) },
  )
  |> ignore
}

///|
/// A poster at 2:3, its ThumbHash first; how far it was watched as a
/// hairline over its foot.
fn poster(c : @ui.Ctx, src : Source, it : Title, w : Double, radius : Double, part : Double?) -> Unit {
  let t = @sf.theme()
  let h = (w * 1.5).round()
  c.box(w=Px(w), h=Px(h), radius~, clip=true, bg=t.p.neutral_bg, border=1.0, border_color=@sf.alpha(t.p.text, 0.08), fn() {
    match @gallery.thumbhash_image(it.thumbhash) {
      Some(k) => c.image(k, w=Px(w), h=Px(h), radius~, bg=0L, fade=false) |> ignore
      None => ()
    }
    c.layer(fn() {
      c.image((src.poster)(it), w=Px(w), h=Px(h), radius~, bg=0L) |> ignore
    })
    |> ignore
    match part {
      Some(k) =>
        c.layer(fn() {
          c.spacer()
          c.box(dir=Row, h=Px(3.0), bg=0x00000066L, fn() {
            c.box(w=Fill(k), h=Px(3.0), bg=t.p.accent, fn() {  }) |> ignore
            c.box(w=Fill(1.0 - k), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
fn poster_tile(c : @ui.Ctx, src : Source, it : Title, tile : Double, recent : Bool) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let id = c.id("title-" + it.id + (if recent { "/r" } else { "" }))
  if c.clicked(id) {
    state.open = Some(it.id)
    state.season = 0
  }
  let pad = if small(c) { 6.0 } else { 8.0 }
  let inner = tile - 2.0 * pad
  let ground = if c.pressed(id) {
    @sf.alpha(p.text, 0.06)
  } else if c.hovered(id) && !small(c) {
    p.hover
  } else {
    0L
  }
  let line = match it.kind {
    Movie =>
      match (it.place, it.year) {
        (Some(pl), _) if recent && !pl.done => "看到 " + clock(pl.position)
        (_, Some(y)) => "\{y}"
        _ => ""
      }
    Show =>
      if it.unwatched > 0 {
        "\{it.unwatched} 集没看"
      } else {
        "\{it.seasons} 季 · \{it.episodes} 集"
      }
  }
  c.box(w=Px(tile), pad~, bg=ground, radius=@sf.r_field, id~, fn() {
    poster(c, src, it, inner, @sf.r_field - pad, None)
    c.box(h=Px(8.0), fn() {  }) |> ignore
    c.text(it.title, size=t.t.ui, weight=500, color=p.text, wrap=false, line=t.t.ui_line)
    |> ignore
    c.text(line, size=t.t.meta, color=p.muted, wrap=false, line=t.t.meta_line)
    |> ignore
  })
  |> ignore
}

///|
fn shapes(
  c : @ui.Ctx,
  cols : Int,
  tile : Double,
  gap : Double,
  inset : Double,
  error? : String? = None,
) -> Unit {
  match error {
    Some(why) =>
      c.box(align=ACenter, pt=14.0, pb=4.0, padx=20.0, fn() {
        @sf.wait_pill(c, why, error=true)
      })
      |> ignore
    None => ()
  }
  let t = @sf.theme()
  let pad = if small(c) { 6.0 } else { 8.0 }
  let inner = tile - 2.0 * pad
  c.box(w=Fill(1.0), h=Fill(1.0), clip=true, gap~, opacity=@sf.breath(c, failed=error is Some(_)), fn() {
    for _ in 0..<2 {
      c.box(dir=Row, pl=inset, pr=inset, pt=12.0, gap~, align=AStart, fn() {
        for _ in 0..<cols {
          c.box(w=Px(tile), pad~, gap=10.0, fn() {
            @sf.bar(c, Px(inner), (inner * 1.5).round(), radius=@sf.r_field - pad)
            @sf.bar(c, Px(inner * 0.7), 13.0)
            @sf.bar(c, Px(inner * 0.4), 10.0)
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn empty(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, gap=12.0, padx=40.0, fn() {
    @sf.icon(c, "file-video", size=28.0, color=t.p.muted) |> ignore
    c.text("片库里还没有影片", size=t.t.ui, weight=500, color=t.p.text, wrap=false)
    |> ignore
    c.text(
      "station 扫到的电影和剧集会排在这里。",
      size=t.t.ui,
      color=t.p.muted,
      line=t.t.ui_line,
    )
    |> ignore
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// A film's or a series' page

///|
fn find_title(src : Source, id : String) -> Title? {
  match (src.library)() {
    Some(Ok(lib)) => {
      for list in [lib.movies, lib.shows, lib.recent] {
        for it in list {
          if it.id == id {
            return Some(it)
          }
        }
      }
      None
    }
    _ => None
  }
}

///|
fn detail_page(c : @ui.Ctx, src : Source, id : String) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let got = (src.detail)(id)
  let title = find_title(src, id)
  c.column(w=Fill(1.0), h=Fill(1.0), bg=p.bg, fn() {
    // the way back, as a page's bar
    c.box(dir=Row, h=Px(48.0), padx=if small(c) { 6.0 } else { 28.0 }, align=ACenter, fn() {
      let bid = c.id("video-back")
      if c.clicked(bid) {
        state.open = None
      }
      c.box(
        dir=Row,
        h=Px(32.0),
        pl=4.0,
        pr=10.0,
        gap=2.0,
        align=ACenter,
        radius=@sf.r_field,
        bg=if c.hovered(bid) { p.hover } else { 0L },
        id=bid,
        fn() {
          @sf.icon(c, "chevron-left", size=20.0, color=p.text) |> ignore
          c.text("影视", size=t.t.ui, color=p.text, wrap=false) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
    let d = match got {
      Some(Ok(d)) => d
      Some(Err(why)) => {
        c.box(align=ACenter, pt=24.0, fn() { @sf.wait_pill(c, why, error=true) })
        |> ignore
        return
      }
      None => {
        c.box(pl=40.0, pt=24.0, gap=12.0, opacity=@sf.breath(c), fn() {
          @sf.bar(c, Px(200.0), 22.0)
          @sf.bar(c, Px(320.0), 12.0)
          @sf.bar(c, Px(280.0), 12.0)
        })
        |> ignore
        return
      }
    }
    let rows = detail_rows(d)
    c.list("detail-" + id, rows.length(), 52.0, fn(r) {
      match rows[r] {
        Top => detail_top(c, src, id, title, d)
        Seasons => seasons(c, d)
        Ep(si, ei) => episode_row(c, src, d.seasons[si].episodes[ei])
        End => c.box(h=Px(48.0), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
priv enum DRow {
  Top
  Seasons
  Ep(Int, Int)
  End
}

///|
fn detail_rows(d : Detail) -> Array[DRow] {
  let rows : Array[DRow] = [Top]
  if d.kind == Show && d.seasons.length() > 0 {
    let si = if state.season < d.seasons.length() { state.season } else { 0 }
    rows.push(Seasons)
    for ei, _ in d.seasons[si].episodes {
      rows.push(Ep(si, ei))
    }
  }
  rows.push(End)
  rows
}

///|
fn detail_top(c : @ui.Ctx, src : Source, id : String, title : Title?, d : Detail) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let side = if small(c) { 20.0 } else { 40.0 }
  let poster_w = if small(c) { 120.0 } else { 200.0 }
  let words = fn() {
    c.box(w=Fill(1.0), gap=8.0, fn() {
      c.text(d.title, size=t.t.heading, weight=600, color=p.text, line=t.t.heading_line)
      |> ignore
      let bits = []
      match d.year {
        Some(y) => bits.push("\{y}")
        None => ()
      }
      if d.genres.length() > 0 {
        bits.push(d.genres.join(" / "))
      }
      if d.kind == Movie && d.duration > 0.0 {
        bits.push(length(d.duration))
      }
      if d.kind == Show {
        bits.push("\{d.seasons.length()} 季")
      }
      if d.original != "" && d.original != d.title {
        bits.push(d.original)
      }
      c.text(bits.join(" · "), size=t.t.meta, color=p.muted, line=t.t.meta_line) |> ignore
      // play, or go on
      c.box(dir=Row, pt=8.0, gap=10.0, align=ACenter, fn() {
        let (what, at) = match d.kind {
          Movie =>
            match d.place {
              Some(pl) if !pl.done && pl.position > 5.0 => ("从 " + clock(pl.position) + " 继续", pl.position)
              _ => ("播放", 0.0)
            }
          Show =>
            match next_episode(d) {
              Some((e, at)) => (if at > 0.0 { "继续第 \{e.episode} 集" } else { "播放第 \{e.episode} 集" }, at)
              None => ("播放", 0.0)
            }
        }
        if @sf.button(c, what, key="play", tone=Primary, icon="play") {
          match d.kind {
            Movie => (src.play)(id, at)
            Show =>
              match next_episode(d) {
                Some((e, at)) => (src.play)(e.id, at)
                None => ()
              }
          }
        }
      })
      |> ignore
      if d.plot != "" {
        c.box(pt=12.0, max_w=640.0, fn() {
          c.text(d.plot, size=t.t.body, color=p.text, line=t.t.body_line) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  c.box(dir=Row, pl=side, pr=side, pt=12.0, pb=16.0, gap=if small(c) { 16.0 } else { 28.0 }, align=AStart, fn() {
    match title {
      Some(it) => poster(c, src, it, poster_w, @sf.r_field, None)
      None => ()
    }
    words()
  })
  |> ignore
}

///|
/// The episode to play: the first not seen to its end, from where it was
/// left.
fn next_episode(d : Detail) -> (Episode, Double)? {
  for s in d.seasons {
    for e in s.episodes {
      match e.place {
        Some(pl) if pl.done => continue
        Some(pl) => return Some((e, pl.position))
        None => return Some((e, 0.0))
      }
    }
  }
  match d.seasons {
    [s, ..] if s.episodes.length() > 0 => Some((s.episodes[0], 0.0))
    _ => None
  }
}

///|
fn seasons(c : @ui.Ctx, d : Detail) -> Unit {
  let t = @sf.theme()
  c.box(pl=if small(c) { 20.0 } else { 40.0 }, pt=8.0, pb=8.0, fn() {
    if d.seasons.length() > 1 {
      let labels = d.seasons.map(fn(s) { "第 \{s.season} 季" })
      state.season = @sf.segmented(c, "season", labels, state.season, item_w=84.0)
    } else {
      c.text("第 \{d.seasons[0].season} 季", size=t.t.title, weight=600, color=t.p.text, wrap=false)
      |> ignore
    }
  })
  |> ignore
}

///|
/// An episode (a list card's row): its number, its title, its length; how
/// far it was watched under it; its ground under the pointer.
fn episode_row(c : @ui.Ctx, src : Source, e : Episode) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let id = c.id("ep-" + e.id)
  if c.clicked(id) {
    let at = match e.place {
      Some(pl) if !pl.done => pl.position
      _ => 0.0
    }
    (src.play)(e.id, at)
  }
  let side = if small(c) { 8.0 } else { 28.0 }
  c.box(pl=side, pr=side, fn() {
    c.box(
      dir=Row,
      padx=12.0,
      pady=10.0,
      gap=12.0,
      align=ACenter,
      radius=@sf.row_corner,
      bg=if c.hovered(id) || c.pressed(id) { p.hover } else { 0L },
      max_w=760.0,
      id~,
      fn() {
        c.box(w=Px(28.0), fn() {
          c.text("\{e.episode}", size=t.t.meta, color=p.muted, wrap=false) |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), gap=4.0, fn() {
          c.text(
            if e.title != "" { e.title } else { "第 \{e.episode} 集" },
            size=t.t.ui,
            weight=500,
            color=p.text,
            wrap=false,
            line=t.t.ui_line,
          )
          |> ignore
          match e.place {
            Some(pl) if e.duration > 0.0 && !pl.done => {
              let k = dmin(pl.position / e.duration, 1.0)
              c.box(dir=Row, w=Px(160.0), h=Px(2.0), radius=1.0, clip=true, fn() {
                c.box(w=Fill(k), h=Px(2.0), bg=p.accent, fn() {  }) |> ignore
                c.box(w=Fill(1.0 - k), h=Px(2.0), bg=@sf.alpha(p.text, 0.1), fn() {  }) |> ignore
              })
              |> ignore
            }
            _ => ()
          }
        })
        |> ignore
        match e.place {
          Some(pl) if pl.done =>
            @sf.icon(c, "check", size=14.0, color=p.muted) |> ignore
          _ => ()
        }
        c.text(length(e.duration), size=t.t.meta, color=p.muted, wrap=false) |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Laid out for a small screen (the window's width alone, @sf.layout): edge to edge, a phone's measures. The screen
/// says how the page is laid out; the colours are one on every screen (@sf.begin).
fn small(c : @ui.Ctx) -> Bool {
  @sf.layout(c.window_size().0) is Small
}
