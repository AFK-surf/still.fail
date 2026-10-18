// The bookshelf: a grid of books, and a reader that turns pages and keeps
// the place (chapter and offset, as the media service stores it), over a
// Source.

///|
struct Reading {
  book : BookInfo
  mut chapter : Int
  /// the position the reader is at, kept across resizes and re-pagination
  mut offset : Int
  mut page : Int
  mut pages : @ui.Pages?
  mut menu : Bool
}

///|
struct App {
  mut reading : Reading?
}

///|
let app : App = { reading: None }

///|
fn open(book : BookInfo) -> Unit {
  let (chapter, offset) = book.place.unwrap_or((0, 0))
  app.reading = Some({ book, chapter, offset, page: 0, pages: None, menu: false })
}

///|
/// The chapter's pages at this size, cut again when the size changes; the
/// page shown is the one holding the reading position.
fn pages_for(
  r : Reading,
  blocks : Array[@ui.Block],
  w : Double,
  h : Double,
) -> @ui.Pages {
  match r.pages {
    Some(p) if p.width == w && p.height == h => p
    _ => {
      // room at the bottom for the page number
      let style = { ..@ui.PageStyle::default(), margin_y: 44.0 }
      let p = @ui.paginate(blocks, w, h, style~)
      r.pages = Some(p)
      r.page = p.page_of(r.offset)
      p
    }
  }
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
fn shelf(c : @ui.Ctx, src : Source) -> Unit {
  let books = match (src.books)() {
    Some(Ok(b)) => b
    Some(Err(why)) => {
      message(c, "书架读不到", why)
      return
    }
    None => {
      message(c, "正在读书架…", "")
      return
    }
  }
  let cols = if c.width < 520.0 { 3 } else if c.width < 900.0 { 4 } else { 6 }
  c.column(w=Fill(1.0), h=Fill(1.0), bg=0xF5F2EBFFL, fn() {
    c.box(dir=Row, padx=20.0, pady=14.0, align=ACenter, fn() {
      c.text("书架", size=22.0, weight=700, wrap=false) |> ignore
      c.spacer()
      c.text("\{books.length()} 本", size=13.0, color=0x8E8E93FFL, wrap=false)
      |> ignore
    })
    |> ignore
    c.list("shelf", (books.length() + cols - 1) / cols, 240.0, fn(r) {
      c.box(dir=Row, padx=14.0, pady=8.0, gap=14.0, align=AStart, fn() {
        for k in 0..<cols {
          let i = r * cols + k
          if i < books.length() {
            book_cell(c, books[i])
          } else {
            c.box(w=Fill(1.0), fn() {  }) |> ignore
          }
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
fn book_cell(c : @ui.Ctx, b : BookInfo) -> Unit {
  let id = c.id("book-" + b.id)
  if c.clicked(id) {
    open(b)
  }
  c.box(w=Fill(1.0), gap=6.0, id~, fn() {
    match b.cover {
      Some(src) =>
        c.image(src, h=Px(150.0), radius=6.0, bg=color_of(b.id)) |> ignore
      // no cover: the title on a colour
      None =>
        c.box(
          h=Px(150.0),
          radius=6.0,
          bg=color_of(b.id),
          shadow=4.0,
          pad=10.0,
          justify=JEnd,
          fn() {
            c.text(b.title, size=15.0, weight=700, color=0xFFFFFFFFL) |> ignore
            c.text(b.author, size=11.0, color=0xFFFFFFCCL, wrap=false) |> ignore
          },
        )
        |> ignore
    }
    c.text(b.title, size=13.0, weight=600, wrap=false) |> ignore
    let progress = match (b.read, b.place) {
      (Some(r), _) => "读了 \{(r * 100.0).round().to_int()}%"
      (_, Some((ch, _))) => "读到第 \{ch + 1} 章 / 共 \{b.chapters} 章"
      _ => "未读"
    }
    c.text(progress, size=11.0, color=0x8E8E93FFL, wrap=false) |> ignore
  })
  |> ignore
}

///|
fn reader(c : @ui.Ctx, src : Source, r : Reading) -> Unit {
  let w = c.width
  let h = c.height
  let blocks = match (src.chapter)(r.book.id, r.chapter) {
    Some(Ok(b)) => b
    Some(Err(why)) => {
      message(c, "这一章读不到", why)
      back_button(c)
      return
    }
    None => {
      message(c, "正在读第 \{r.chapter + 1} 章…", "")
      return
    }
  }
  let titles = (src.toc)(r.book.id).unwrap_or([])
  let title = if r.chapter < titles.length() {
    titles[r.chapter]
  } else {
    "第 \{r.chapter + 1} 章"
  }
  let pages = pages_for(r, blocks, w, h)
  c.column(w=Fill(1.0), h=Fill(1.0), bg=0xF7F3EAFFL, fn() {
    let shown = c.pager(
      "pages-\{r.chapter}",
      pages.count(),
      r.page,
      fn(i) { c.page(pages, i) |> ignore },
      on_edge=fn(dir) { go_chapter(r, r.chapter + dir, dir < 0) },
      on_middle=fn() { r.menu = !r.menu },
    )
    if shown != r.page && r.pages is Some(_) {
      r.page = shown
      r.offset = pages.pages[shown].start
      (src.save_place)(r.book.id, r.chapter, r.offset)
    }
  })
  |> ignore
  // over the page: its number at the bottom, and the menu on a tap in the
  // middle
  c.layer(fn() {
    if r.menu {
      c.box(
        dir=Row,
        padx=16.0,
        pady=12.0,
        gap=12.0,
        align=ACenter,
        bg=0xFFFFFFF2L,
        shadow=6.0,
        fn() {
          if c.button("书架", key="back", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
            app.reading = None
          }
          c.text(r.book.title, size=15.0, weight=600, wrap=false) |> ignore
          c.spacer()
          if c.button("上一章", key="prev", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
            go_chapter(r, r.chapter - 1, false)
          }
          if c.button("下一章", key="next", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
            go_chapter(r, r.chapter + 1, false)
          }
        },
      )
      |> ignore
    }
    c.spacer()
    c.box(dir=Row, padx=24.0, pady=10.0, fn() {
      c.text(title, size=11.0, color=0x8E8E93FFL, wrap=false)
      |> ignore
      c.spacer()
      c.text("\{r.page + 1} / \{pages.count()}", size=11.0, color=0x8E8E93FFL, wrap=false)
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The shelf, or the book being read.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  match app.reading {
    Some(r) => reader(c, src, r)
    None => shelf(c, src)
  }
}

///|
fn message(c : @ui.Ctx, head : String, line : String) -> Unit {
  c.column(w=Fill(1.0), h=Fill(1.0), bg=0xF5F2EBFFL, align=ACenter, justify=JCenter, gap=8.0, fn() {
    c.text(head, size=17.0, weight=600, wrap=false) |> ignore
    if line.length() > 0 {
      c.text(line, size=13.0, color=0x8E8E93FFL) |> ignore
    }
  })
  |> ignore
}

///|
fn back_button(c : @ui.Ctx) -> Unit {
  c.layer(pad=16.0, align=AStart, fn() {
    if c.button("书架", key="back-err", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
      app.reading = None
    }
  })
  |> ignore
}

///|
let palette : Array[Int64] = [
  0x3A6EA5FFL, 0x7A4E9CFFL, 0x2F7D5BFFL, 0xB5562AFFL, 0x1F3B5BFFL, 0x8C6D1FFFL,
  0xC2416BFFL,
]

///|
fn color_of(id : String) -> Int64 {
  palette[(id.hash() & 0x7FFFFFFF) % palette.length()]
}
