// A Markdown table as nodes of the window's tree (Md::table's, narrow: as a message's table is drawn): its columns as
// wide as table_widths shares the room it is laid out in, its head and its rows each a row of cells (the head's words
// muted, smaller, medium; the rest the words' own), ruled between them; wider than its room, it scrolls across
// (Scroll::across), `bleed` past its room either side, its bar under the room alone. Its table as the core read the
// Markdown (blocks_of: core_blocks), each cell's words in pieces as the message's (runs_of: bold, italic, code, struck
// through, links pressed where they lead: runs_links). As what it is told changes, each cell's words told anew, nothing
// made again but cells and rows come or gone. Its picture (the copy key's) its own frame's, made as nodes
// apart and taken whole (take_picture).

///|
/// The core's answers about each text read as Markdown, by the text, as they come: every reader of the same text
/// follows the one cell (md_answer), whichever asked (a tree's reader, md_ask, or an old view's markdown); what asked
/// it gone or not. Each kept while something of the window's tree reads its text (md_readers) or its answer is kept
/// (parsed): let go as both are gone, never kept for each text there ever was.
// kept across runs: put back as a run begins (on_reset)
let md_answered : Map[String, @signals.Signal[Int]] = Map([])

///|
/// How many of the window's tree's readers read each text now (table_node's, as made and as they say another).
// kept across runs: put back as a run begins (on_reset)
let md_readers : Map[String, Int] = Map([])

///|
/// The core's reading of each text something of the window's tree reads now (md_readers), held by them while they do,
/// whatever the texts read lately (blocks_of's, which others push out): from its answer, or as it was kept as the
/// first of them came; let go as the last goes.
// kept across runs: put back as a run begins (on_reset)
let md_held : Map[String, Array[MdBlock]] = Map([])

///|
fn init {
  @ui.on_reset(fn() {
    md_answered.clear()
    md_readers.clear()
    md_held.clear()
  })
}

///|
/// The cell told as the core answers about `text` (made as it is first asked for: no answer yet).
fn md_answer(text : String) -> @signals.Signal[Int] {
  match md_answered.get(text) {
    Some(c) => c
    None => {
      let c = @signals.signal(0)
      md_answered[text] = c
      c
    }
  }
}

///|
/// The core's answer about `text` (`value`, its tree: words alone where it says none) kept (blocks_of) and told to all
/// that read it (md_answer): what both an old view's markdown and a tree's reader do as it comes.
fn md_answered_now(text : String, value : Json?) -> Unit {
  let ready = match value {
    Some(Array(_)) => value
    _ => Some(Json::array([["p", [Json::string(text)]]]))
  }
  let blocks = blocks_of(text, ready)
  // (held by what reads it now, as long as it does: md_held)
  if md_readers.contains(text) {
    md_held[text] = blocks
  }
  match md_answered.get(text) {
    Some(c) => c.set(c.untracked() + 1)
    None => ()
  }
}

///|
/// `text`'s answer let go of as its kept reading is (blocks_of's budget): its cell gone where nothing reads it now.
fn md_forgotten(text : String) -> Unit {
  if md_readers.get(text).unwrap_or(0) == 0 {
    md_answered.remove(text)
  }
}

///|
/// A reader of the window's tree come to `text`, or gone from it (`by` 1 or -1): its cell let go as the last goes,
/// where its reading is not kept.
fn md_read_by(text : String, by : Int) -> Unit {
  if text == "" {
    return
  }
  let n = md_readers.get(text).unwrap_or(0) + by
  if n > 0 {
    md_readers[text] = n
    // (the first: what the core read of it already, held from now)
    if !md_held.contains(text) && core_parsed.contains(text) && parsed.get(text) is Some(b) {
      md_held[text] = b
    }
  } else {
    md_readers.remove(text)
    md_held.remove(text)
    if !parsed.contains(text) {
      md_answered.remove(text)
    }
  }
}

///|
/// The core asked to read `text` as Markdown (as @sf.markdown asks it), once for all its readers: its answer told to
/// them all (md_answered_now), at once if it answers at once. Nothing asked where it was read or asked already (by an
/// old view's markdown too), where those reading it hold its answer, or there is no core. At a cause (a reader made or told another text), never as it is read.
fn md_ask(text : String) -> Unit {
  // (none either where its readers hold its answer, pushed out of what was read lately or not: md_held)
  if text == "" || core_parsed.contains(text) || markdown_asked.contains(text) || md_held.contains(text) {
    return
  }
  match markdown_read.val {
    Some(f) => {
      markdown_asked[text] = true
      f(text, fn(value) { md_answered_now(text, value) })
    }
    None => ()
  }
}

///|
/// The table `text` says (its Markdown, a table alone) as the core read it, followed (md_answer: as its answer comes);
/// `tree`, as told where that says one (a made-up one's: nothing asked). None till it is read, or with no table.
fn table_of(text : String, tree : Json?) -> MdTable? {
  if text == "" {
    return None
  }
  let blocks = match tree {
    Some(_) => blocks_of(text, tree)
    None => {
      md_answer(text).get() |> ignore
      // (what its readers hold, whatever the texts read lately pushed out; else as kept or read now)
      match md_held.get(text) {
        Some(b) => b
        None => blocks_of(text, None)
      }
    }
  }
  for b in blocks {
    match b {
      Table(t) => return Some(t)
      _ => ()
    }
  }
  None
}

///|
/// A cell's words as pieces the tree draws (View::words_runs: each its own way, as a message's: runs_of, a chat's
/// mention in the accent's ink), its links among them.
fn table_cell_runs(cell : Array[MdInline]) -> Array[@ui.Run] {
  let runs = []
  runs_of(cell, runs, false, false, false, "", theme().p.accent_text, {}, false)
  runs
}

///|
/// How a table's cell's pieces are set where a piece says nothing of it itself, as Md::words sets a message's
/// paragraph: links in the theme's blue, code in its code ink on no ground of its own at 0.9 of the words' size, the
/// words a person's.
fn table_runs_look() -> @view.RunsLook {
  let p = theme().p
  { link: p.blue, pressed: alpha(p.blue, 0.14), code_ink: p.code_ink, code_ground: 0L, code_scale: 0.9, words: true }
}

///|
/// The table `text` says (the core's reading of it: table_of; `tree`, its reading as told where that says one: a
/// made-up one's, nothing asked of the core), in `parent`: as Md::table draws it narrow, `bleed` past its room either
/// side where it scrolls across. Its columns' widths from the room it is given as it is laid out (View::by_room), at
/// the system's size of words.
#callsite(autofill(loc))
pub fn table_node(
  parent : @view.View,
  text : () -> String,
  bleed? : Double = 0.0,
  tree? : () -> Json? = fn() { None },
  copy? : Bool = true,
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
  loc~ : SourceLoc,
) -> Unit {
  let table = fn() { table_of(text(), tree()) }
  parent.box(made_for=loc, fn(outer) {
    // (its text asked of the core as it is made and as it says another, none where it is told its reading; read by it
    // till it says another or is let go: md_read_by)
    let reading = Ref("")
    outer.reacts(fn() { if tree() is None { text() } else { "" } }, fn(t) {
      md_read_by(t, 1)
      md_read_by(reading.val, -1)
      reading.val = t
      md_ask(t)
    })
    outer.owns(fn() {
      md_read_by(reading.val, -1)
      reading.val = ""
    })
    |> ignore
    md_table_body_node(outer, table, bleed, copy, on_link, on_link_hold)
  })
  |> ignore
}

///|
/// A table (`table`, as it changes) as nodes in `outer` (table_node's, whatever reads its Markdown: a table alone, or
/// one of a message's blocks, markdown_node's): its columns' widths from the room `outer` is given (View::by_room), `bleed` past
/// it either side where it scrolls across; its copy key where `copy`; its links taken by `on_link` (`on_link_hold`); a
/// cell of only the message's images drawn as those (`cell_images`: md_cell_images, Md::cell_images').
#callsite(autofill(loc))
fn md_table_body_node(
  outer : @view.View,
  table : () -> MdTable?,
  bleed : Double,
  copy : Bool,
  on_link : (String) -> Unit,
  on_link_hold : ((String, (Double, Double, Double, Double)) -> Unit)?,
  fit? : Bool = false,
  cell_images? : (Array[MdInline]) -> Array[(Double, (@view.View, () -> Double) -> Unit)]?,
  loc~ : SourceLoc,
) -> Unit {
    outer.margin(Is((-bleed, 0.0, -bleed, 0.0))) |> ignore
    // (its columns by the room it is given, laid out in that same layout)
    outer.by_room(fn(outer, given) {
      let room = fn() {
        outer.words_redone() |> ignore
        given.width() - 2.0 * bleed
      }
      // (each cell's extent and the columns' widths, as Md::table works them out: table_widths)
      let widths_for = fn(t : MdTable) {
        let rows = [t.head]
        rows.append(t.rows)
        let extents = rows.mapi(fn(r, row) {
          row.map(fn(cell) {
            match cell_images.bind(fn(f) { f(cell) }) {
              // (a cell of images as wide as their row: Md::table's)
              Some(images) => {
                let w = cell_images_node_width(images)
                (w, w, true)
              }
              None => {
                let (lo, hi) = table_words_extent(cell, r == 0, fn(x) { node_sp(outer, x) })
                (lo, hi, false)
              }
            }
          })
        })
        table_widths(extents, room(), fit, fn(x) { node_sp(outer, x) })
      }
      let widths = fn() {
        match table() {
          Some(t) => widths_for(t)
          None => ([], 0.0)
        }
      }
      // (shown whole in the column where it fits not (`fit`, a chat's shared picture): its every part as much smaller
      // as makes it as wide as the room, nothing of it to scroll to: Md::table's)
      let scale = fn() {
        if fit {
          let total = widths().1
          let avail = room()
          if total > avail && avail > 0.0 {
            avail / total
          } else {
            1.0
          }
        } else {
          1.0
        }
      }
      // (at once: whether it fits is the room's, the width the window or the column gives it, an arrangement by it and
      // no coming or going of its own)
      outer.pick(fn() { scale() < 1.0 }, at_once=true, fn(outer, fitted) {
        if fitted {
          outer.box(made_for=loc, fn(whole) {
            whole.padding(Is((bleed, 0.0, bleed, 0.0))) |> ignore
            table_frame_node(
              whole,
              table,
              fn() {
                let (ws, total) = widths()
                let k = scale()
                (ws.map(fn(w) { w * k }), total * k)
              },
              scale~,
              on_link~,
              on_link_hold~,
              cell_images?,
            )
          })
          |> ignore
          return
        }
      // (its head's row's height, as it comes to in its room: where its copy key's middle is)
      let head_h : Ref[@view.View?] = Ref(None)
      // (its own key, whatever its words: two tables of the same each their own menu, copy and picture)
      table_nodes_made.val += 1
      let key = "sf-table/\{table_nodes_made.val}"
      outer.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), bar_in=bleed, fn(held) {
        held.padding(Is((bleed, 0.0, bleed, 0.0))) |> ignore
        // (it, then its copy key past it, from their tops: table_beside's; the key hung out in `bleed` where that has its
        // whole room, as Md::table has it)
        held.box(fn(beside) {
          beside
          .row(Is(true))
          .lines_up(Is(Some(Start)))
          // (pointed at as a whole, its key with it: what shows its key; taking no press nor hold for it)
          .points(Is(copy))
          .margin(Is((0.0, 0.0, if copy && bleed >= table_key_room { -table_key_room } else { 0.0 }, 0.0)))
          |> ignore
        table_frame_node(beside, table, widths, head_h~, on_link~, on_link_hold~, cell_images?)
        if copy {
          table_key_node(beside, key, fn() { table() }, fn() {
            match head_h.val {
              Some(h) => given.tall(h)
              None => 0.0
            }
          }, widths_for)
        }
        })
        |> ignore
      })
      |> ignore
      })
    })
    |> ignore
}

///|
/// A table's frame as nodes in `beside` (md_table_body_node's, and its picture's: table_key_node): its head's row and
/// its rows (`table`, as it changes), each a row of cells its columns `widths` wide, ruled between them; its head's row
/// told `head_h` as it is made, its links taken by `on_link` (`on_link_hold`); a cell of only the message's images
/// those images in a row (`cell_images`, md_table_body_node's).
#callsite(autofill(loc))
fn table_frame_node(
  beside : @view.View,
  table : () -> MdTable?,
  widths : () -> (Array[Double], Double),
  head_h? : Ref[@view.View?] = Ref(None),
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
  scale? : () -> Double = fn() { 1.0 },
  cell_images? : (Array[MdInline]) -> Array[(Double, (@view.View, () -> Double) -> Unit)]?,
  loc~ : SourceLoc,
) -> Unit {
  beside.box(made_for=loc, fn(frame) {
    frame.width(By(fn() { Some(widths().1) })) |> ignore
    let rows = fn() {
      match table() {
        Some(t) => Array::makei(t.rows.length() + 1, fn(i) { i })
        None => []
      }
    }
    frame.each(rows, fn(r) { r }, fn(line, r) {
      let r = r.untracked()
      let head = r == 0
      line.box(fn(cells) {
        // (its head's row: where its copy key's middle is, as the frame measured it)
        if head {
          head_h.val = Some(cells)
        }
        cells.row(Is(true)).lines_up(Is(None)) |> ignore
        let cols = fn() { Array::makei(widths().0.length(), fn(k) { k }) }
        cells.each(cols, fn(k) { k }, fn(cell, k) {
          let k = k.untracked()
          let words = fn() {
            match table() {
              Some(t) => (if head { t.head } else { t.rows.get(r - 1).unwrap_or([]) }).get(k).unwrap_or([])
              None => []
            }
          }
          let pad = fn() { table_cell_pad(k, widths().0.length()) }
          cell
          .width(By(fn() { widths().0.get(k) }))
          .padding(By(fn() {
            let (pl, pr) = pad()
            let k = scale()
            (pl * k, table_cell_y * k, pr * k, table_cell_y * k)
          }))
          .lies_along(Is(Middle))
          |> ignore
          // its words (as a message's, in pieces, a press on a link where it leads: runs_links)
          let words_box = fn(cell : @view.View) {
            cell.box(fn(w) {
              let look = fn() -> @view.WordsLook {
                let size = (if head { 12.0 } else { 13.0 }) * scale()
                {
                  size,
                  weight: if head { 500 } else { 400 },
                  line: (Float::from_double(size) * (1.65 : Float)).to_double(),
                  wrap: true,
                  tracking: @view.letters_own,
                  balance: false,
                  max_lines: 0,
                }
              }
              let runs = fn() { table_cell_runs(words()) }
              w
              .words_runs(By(runs))
              .words_look(By(look))
              .runs_look(By(table_runs_look))
              .ink(By(fn() { if head { web().muted } else { theme().p.text } }))
              |> ignore
              @ui.runs_links(w, runs, on_link, hold?=on_link_hold) |> ignore
            })
            |> ignore
          }
          // its images in a row where it is only the message's images (CellImageRow: 6 apart, 4 over and under, each
          // cell_image_width wide), else its words, made again only as it comes to hold another number of them; where
          // it is given no images (`cell_images` none: every table but one of a message that places its files), its
          // words alone, nothing made for the choice
          match cell_images {
            None => words_box(cell)
            Some(of_cell) => {
              let images = fn() { of_cell(words()) }
              cell.pick(at_once=true, fn() { images().map_or(0, fn(ims) { ims.length() }) }, fn(cell, n) {
                if n > 0 {
                  cell.box(fn(row) {
                    row.row(Is(true)).gap(By(fn() { 6.0 * scale() })).padding(By(fn() { (0.0, 4.0 * scale(), 0.0, 4.0 * scale()) })) |> ignore
                    for i in 0..<n {
                      row.box(fn(im) {
                        let width = fn() {
                          cell_image_width(images().bind(fn(ims) { ims.get(i) }).map_or(1.0, fn(x) { x.0 })) * scale()
                        }
                        im.width(By(fn() { Some(width()) })) |> ignore
                        match @signals.untracked(fn() { images().bind(fn(ims) { ims.get(i) }) }) {
                          Some((_, draw)) => draw(im, width)
                          None => ()
                        }
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                  return
                }
                words_box(cell)
              })
              |> ignore
            }
          }
        })
      })
      |> ignore
      // (a rule under each but the last, as faint as is seen)
      line.show(fn() { r < rows().length() - 1 }, fn(rule) {
        rule
        .width(By(fn() { Some(widths().1) }))
        .height(By(fn() { Some(scale()) }))
        .ground(By(fn() { theme().p.line }))
        |> ignore
      })
    })
  })
  |> ignore
}

///|
/// How wide a table's cell of images is (cell_images_width's): their widths and the gaps between them.
fn cell_images_node_width(images : Array[(Double, (@view.View, () -> Double) -> Unit)]) -> Double {
  let mut w = 0.0
  for i, im in images {
    w = w + cell_image_width(im.0) + (if i > 0 { 6.0 } else { 0.0 })
  }
  w
}

///|
/// Tables made as nodes so far: each one's own key (table_node's).
// kept across runs: it goes on counting
let table_nodes_made : Ref[Int] = Ref(0)

///|
/// A table's copy key as nodes (table_key's), in `beside` past the table (it and its key, View::points): its
/// own `key`, table_key_gap past it and before what follows, its middle on its head's row's (`head_h`, as laid out);
/// pressed, its menu (copy it as Markdown, as CSV, as the core wrote them; as a picture: the table whole, its columns
/// `widths` as they are then, its frame as drawn here (table_frame_node) on the page's ground, taken once:
/// take_picture); once one is copied a check, copied_ms (said on its timeline). Faded in (nav_fade) as the table or
/// its key is pointed at (`beside` saying it is pointed at alone, View::points; what is over it taking the pointer:
/// not), its menu open or it saying it copied, always to a finger; its room kept either way, as tall as the key,
/// nothing in it to press or read out while it has faded out.
#callsite(autofill(loc))
fn table_key_node(
  beside : @view.View,
  key : String,
  table : () -> MdTable?,
  head_h : () -> Double,
  widths_for : (MdTable) -> (Array[Double], Double),
  loc~ : SourceLoc,
) -> Unit {
  let copied = @signals.signal(false)
  let copied_off : Ref[() -> Unit] = Ref(fn() {  })
  let menu_open = @signals.signal(false)
  beside.box(made_for=loc, fn(k) {
    // (its room kept, as tall as the key, whether it shows or not)
    let top = fn() { dmax(0.0, (head_h() - table_key_size) / 2.0) }
    k
    .width(Is(Some(table_key_gap + table_key_size + table_key_gap)))
    .min_height(By(fn() { Some(top() + table_key_size) }))
    .padding(By(fn() { (table_key_gap, top(), table_key_gap, 0.0) }))
    |> ignore
    let shown = fn() { beside.pointed_in() || menu_open.get() || copied.get() || @ui.pointing() is Finger }
    let seen = EdgeWay::new(0.0)
    // (there while it shows or fades: gone, as it fades out to nothing, at that moment)
    let there = @signals.signal(false)
    let gone_off : Ref[() -> Unit] = Ref(fn() {  })
    k.reacts(shown, fn(on) {
      (gone_off.val)()
      gone_off.val = fn() {  }
      seen.go(k, if on { 1.0 } else { 0.0 }, dur_ms)
      if on {
        there.set(true)
      } else {
        gone_off.val = k.at_moment(k.logic_at() + dur_ms, fn() { there.set(false) })
      }
    })
    k.owns(fn() {
      (gone_off.val)()
      (copied_off.val)()
    })
    |> ignore
    k.alpha(By(fn() { seen.shown(k) })) |> ignore
    k.show(fn() { there.get() }, fn(slot) {
      let button : Ref[@view.View?] = Ref(None)
      let said = fn() {
        // (a check a moment: said again, from then)
        (copied_off.val)()
        copied.set(true)
        copied_off.val = k.at_moment(k.logic_at() + copied_ms, fn() { copied.set(false) })
      }
      let press = fn() {
        match (table(), button.val) {
          (Some(tb), Some(b)) => {
            menu_open.set(true)
            let closed = fn() { menu_open.set(false) }
            let words = fn(s : String) {
              closed()
              @ui.clipboard_set(s)
              said()
            }
            let items : Array[MenuItem?] = []
            if tb.md != "" {
              items.push(Some(menu_item_of(t("web-main.prose.copyMarkdown"), fn() { words(tb.md) })))
            }
            if tb.csv != "" {
              items.push(Some(menu_item_of(t("web-main.prose.copyCsv"), fn() { words(tb.csv) })))
            }
            let album = picture_to_album()
            items.push(
              Some(
                menu_item_of(picture_out_way().0, fn() {
                  closed()
                  // (the table as it is as this is chosen, its rows and its columns' widths read together then, whole,
                  // past what scrolls)
                  // (the table now, or as the menu opened on it where it is not read now: its widths worked out for
                  // that one, never another's)
                  let (now, (ws, total)) = @signals.untracked(fn() {
                    let now = table().unwrap_or(tb)
                    (now, widths_for(now))
                  })
                  @ui.take_picture(
                    key + "/picture",
                    total + 2.0 * table_shot_in,
                    fn(paper) {
                      paper
                      .padding(Is((table_shot_in, table_shot_in, table_shot_in, table_shot_in)))
                      .ground(By(fn() { theme().p.bg }))
                      |> ignore
                      table_frame_node(paper, fn() { Some(now) }, fn() { (ws, total) })
                    },
                    fn(png) { if (picture_out_by.val)(@ui.current(), png, !album) && !album { said() } },
                    scale=dmax(slot.pixel_scale(), table_shot_scale),
                  )
                }),
              ),
            )
            let (x, y, w, h) = b.rect()
            menu(items, from=At(x, y, w, h), along=End, gone=closed)
          }
          _ => ()
        }
      }
      button.val = Some(
        icon_button_node(
          slot,
          "copy",
          fn() { if copied.get() { t("common.copied") } else { t("web-main.prose.copyTable") } },
          press,
          size=table_key_size,
          icon_now=fn() { if copied.get() { "check" } else { "copy" } },
        ),
      )
    })
  })
  |> ignore
}

