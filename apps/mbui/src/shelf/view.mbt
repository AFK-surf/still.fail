// The bookshelf and the reader, in still.fail's design (ember web/ui: the
// reader is viewer/Reader.tsx and its bars, the shelf a page as the drive's
// is): a grid of books, and a reader that turns pages and keeps the place
// (chapter and offset, as the media service stores it), over a Source.

///|
priv enum Panel {
  NoPanel
  Contents
  Layout
} derive(Eq)

///|
struct Reading {
  book : BookInfo
  mut chapter : Int
  /// the position the reader is at, kept across resizes and re-pagination
  mut offset : Int
  mut page : Int
  mut pages : @ui.Pages?
  /// the phone's bars, shown by a tap in the middle
  mut bars : Bool
  mut panel : Panel
  /// the contents scrolled to the chapter read when opened
  mut contents_at : Int
}

///|
/// How the reader lays text out (viewer/readerStyle.ts): its size, its
/// lines' height, the room either side, indented paragraphs, the paper.
struct Prefs {
  mut size : Double
  mut line : Double
  mut margin : Double
  mut indent : Bool
  /// 0 white, 1 green, 2 grey (light papers; night is the app's dark)
  mut paper : Int
}

///|
struct App {
  mut reading : Reading?
  prefs : Prefs
}

///|
let app : App = {
  reading: None,
  prefs: { size: 18.0, line: 1.7, margin: 22.0, indent: true, paper: 0 },
}

///|
fn open(book : BookInfo) -> Unit {
  let (chapter, offset) = book.place.unwrap_or((0, 0))
  app.reading = Some({
    book,
    chapter,
    offset,
    page: 0,
    pages: None,
    bars: false,
    panel: NoPanel,
    contents_at: -1,
  })
}

///|
fn go_chapter(r : Reading, chapter : Int, at_end : Bool) -> Unit {
  if chapter < 0 || chapter >= r.book.chapters {
    return
  }
  r.chapter = chapter
  r.pages = None
  // the start of the chapter, or its end when going back
  r.offset = if at_end { 1 << 30 } else { 0 }
}

///|
/// The shelf, or the book being read.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  @sf.begin(c) |> ignore
  match app.reading {
    Some(r) => reader(c, src, r)
    None => shelf(c, src)
  }
}

// ---------------------------------------------------------------------------
// The shelf: a page (pages.css.ts) with its head, the books in a grid of
// tiles whose ground shows under the pointer (as the drive's entries)

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// How the grid fits: columns, a tile's width, the gap, and how far in the
/// tiles start (the page's padding less theirs: their ground reaches past
/// the line the page's words are on, the covers stand on it).
fn grid(c : @ui.Ctx) -> (Int, Double, Double, Double) {
  let t = @sf.theme()
  let pad = if small(c) { 16.0 } else { 40.0 }
  let tile_pad = tile_pad(c)
  let room = dmin(c.width - 2.0 * pad, 1120.0) + 2.0 * tile_pad
  let gap = if small(c) { 2.0 } else { 4.0 }
  let least = if small(c) { 104.0 } else { 152.0 }
  let mut cols = ((room + gap) / (least + gap)).floor().to_int()
  if cols < 2 {
    cols = 2
  }
  let tile = (room - gap * (cols - 1).to_double()) / cols.to_double()
  (cols, tile, gap, pad - tile_pad)
}

///|
fn tile_pad(c : @ui.Ctx) -> Double {
  if small(c) {
    6.0
  } else {
    8.0
  }
}

///|
/// A cover's height for its width: a book's proportions.
fn cover_h(w : Double) -> Double {
  (w * 1.42).round()
}

///|
fn shelf(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let got = (src.books)()
  let (cols, tile, gap, inset) = grid(c)
  let meta = match got {
    Some(Ok(b)) if b.length() > 0 => "\{b.length()} 本书"
    _ => ""
  }
  c.column(w=Fill(1.0), h=Fill(1.0), bg=p.bg, fn() {
    // the phone's head stays over what scrolls; the wide page's goes with it
    if small(c) {
      c.box(pl=20.0, pr=12.0, pt=14.0, pb=6.0, fn() { @sf.page_head(c, "书架", meta~) })
      |> ignore
    }
    let books = match got {
      Some(Ok(b)) => b
      Some(Err(why)) => {
        waiting(c, cols, tile, gap, inset, error=Some(why))
        return
      }
      None => {
        waiting(c, cols, tile, gap, inset)
        return
      }
    }
    if books.length() == 0 {
      if !small(c) {
        c.box(pl=40.0, pr=40.0, pt=32.0, fn() { @sf.page_head(c, "书架") }) |> ignore
      }
      empty(c)
      return
    }
    let rows = (books.length() + cols - 1) / cols
    let head = if small(c) { 0 } else { 1 }
    c.list("shelf", rows + head + 1, cover_h(tile) + 60.0, fn(r) {
      if r < head {
        c.box(pl=40.0, pr=40.0, pt=32.0, pb=12.0, fn() {
          @sf.page_head(c, "书架", meta~)
        })
        |> ignore
      } else if r == rows + head {
        // room under the last row (the page's 80 at its foot)
        c.box(h=Px(if small(c) { 40.0 } else { 72.0 }), fn() {  }) |> ignore
      } else {
        let row = r - head
        c.box(dir=Row, pl=inset, pr=inset, pb=gap, gap~, align=AStart, fn() {
          for k in 0..<cols {
            let i = row * cols + k
            if i < books.length() {
              book_tile(c, books[i], tile)
            } else {
              c.box(w=Px(tile), fn() {  }) |> ignore
            }
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A book: its cover, its name, how far it is read; its ground under the
/// pointer (or a finger held on it).
fn book_tile(c : @ui.Ctx, b : BookInfo, tile : Double) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let id = c.id("book-" + b.id)
  if c.clicked(id) {
    open(b)
  }
  let pad = tile_pad(c)
  let inner = tile - 2.0 * pad
  let ground = if c.pressed(id) {
    @sf.alpha(p.text, 0.06)
  } else if c.hovered(id) && !small(c) {
    p.hover
  } else {
    0L
  }
  c.box(w=Px(tile), pad~, gap=0.0, bg=ground, radius=@sf.r_field, id~, fn() {
    cover(c, b, inner, @sf.r_field - pad)
    c.box(h=Px(8.0), fn() {  }) |> ignore
    c.text(
      b.title,
      size=t.t.ui,
      weight=500,
      color=p.text,
      wrap=false,
      line=t.t.ui_line,
    )
    |> ignore
    let (line, part) = match (b.read, b.place) {
      (Some(r), _) if r >= 0.995 => ("读完了", None)
      (Some(r), _) if r > 0.0 => ("读了 \{(r * 100.0).round().to_int()}%", Some(r))
      (_, Some((ch, _))) if ch > 0 =>
        (
          "第 \{ch + 1} 章 / 共 \{b.chapters} 章",
          Some(ch.to_double() / dmax(b.chapters.to_double(), 1.0)),
        )
      _ => (if b.author != "" { b.author } else { "未读" }, None)
    }
    c.text(line, size=t.t.meta, color=p.muted, wrap=false, line=t.t.meta_line)
    |> ignore
    match part {
      // how far: a hairline in the accent (as the drive's uploads)
      Some(k) => {
        c.box(h=Px(6.0), fn() {  }) |> ignore
        c.box(dir=Row, h=Px(2.0), radius=1.0, clip=true, fn() {
          c.box(w=Fill(k), h=Px(2.0), bg=p.accent, fn() {  }) |> ignore
          c.box(w=Fill(1.0 - k), h=Px(2.0), bg=@sf.alpha(p.text, 0.1), fn() {  })
          |> ignore
        })
        |> ignore
      }
      None => ()
    }
  })
  |> ignore
}

///|
/// Its cover, or its name on the paper when it has none; a hairline round
/// it so a white cover still has an edge.
fn cover(c : @ui.Ctx, b : BookInfo, w : Double, radius : Double) -> Unit {
  let t = @sf.theme()
  let p = t.p
  let h = cover_h(w)
  match b.cover {
    Some(src) =>
      c.box(w=Px(w), h=Px(h), radius~, border=1.0, border_color=@sf.alpha(p.text, 0.08), fn() {
        c.image(src, w=Px(w), h=Px(h), radius~, bg=p.neutral_bg) |> ignore
      })
      |> ignore
    None =>
      c.box(
        w=Px(w),
        h=Px(h),
        radius~,
        bg=p.paper,
        border=1.0,
        border_color=@sf.alpha(p.text, 0.08),
        pad=12.0,
        gap=6.0,
        justify=JEnd,
        fn() {
          c.text(b.title, size=t.t.title, weight=600, color=p.text, line=22.0)
          |> ignore
          if b.author != "" {
            c.text(b.author, size=t.t.meta, color=p.muted, wrap=false) |> ignore
          }
        },
      )
      |> ignore
  }
}

///|
/// The shelf's first read (waiting.tsx Waiting): the tiles' shapes,
/// breathing; what could not be read in a red pill over them, the shapes
/// still and faded.
fn waiting(
  c : @ui.Ctx,
  cols : Int,
  tile : Double,
  gap : Double,
  inset : Double,
  error? : String? = None,
) -> Unit {
  let t = @sf.theme()
  let failed = error is Some(_)
  c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
    if !small(c) {
      c.box(pl=40.0, pr=40.0, pt=32.0, pb=12.0, fn() { @sf.page_head(c, "书架") })
      |> ignore
    }
    match error {
      Some(why) =>
        c.box(align=ACenter, pt=14.0, pb=4.0, padx=20.0, fn() {
          @sf.wait_pill(c, "书架读不到：" + why, error=true)
        })
        |> ignore
      None => ()
    }
    let pad = tile_pad(c)
    let inner = tile - 2.0 * pad
    let wait = c.box(gap~, fn() {
      for _ in 0..<3 {
        c.box(dir=Row, pl=inset, pr=inset, gap~, align=AStart, fn() {
          for _ in 0..<cols {
            c.box(w=Px(tile), pad~, gap=10.0, fn() {
              @sf.bar(c, Px(inner), cover_h(inner), radius=@sf.r_field - pad)
              @sf.bar(c, Px(inner * 0.7), 13.0)
              @sf.bar(c, Px(inner * 0.45), 10.0)
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    @sf.breathe(c, wait, failed~)
  })
  |> ignore
}

///|
/// No books yet (Drive.css.ts empty): what the shelf is, grey, in the
/// middle.
fn empty(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    align=ACenter,
    justify=JCenter,
    gap=12.0,
    padx=40.0,
    fn() {
      @sf.icon(c, "file-text", size=28.0, color=t.p.muted) |> ignore
      c.text(
        "书架上还没有书",
        size=t.t.ui,
        weight=500,
        color=t.p.text,
        wrap=false,
      )
      |> ignore
      c.text(
        "在 still.fail 的文件里把 EPUB 或 TXT 放上书架，就会出现在这里。",
        size=t.t.ui,
        color=t.p.muted,
        line=t.t.ui_line,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// Laid out for a small screen (the window's width alone, @sf.layout): edge to edge, a phone's measures. The screen
/// says how the page is laid out; the colours are one on every screen (@sf.begin).
fn small(c : @ui.Ctx) -> Bool {
  @sf.layout(c.window_size().0) is Small
}
