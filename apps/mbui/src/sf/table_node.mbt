// A Markdown table as nodes of the window's tree (Md::table's, narrow: as a message's table is drawn): its columns as
// wide as table_widths shares the room it is laid out in, its head and its rows each a row of cells (the head's words
// muted, smaller, medium; the rest the words' own), ruled between them; wider than its room, it scrolls across
// (Scroll::across), `bleed` past its room either side, its bar under the room alone. Its table as the core read the
// Markdown (blocks_of: core_blocks), each cell's words in pieces as the message's (runs_of: bold, italic, code, struck
// through, links pressed where they lead: runs_links). As what it is told changes, each cell's words told anew, nothing
// made again but cells and rows come or gone. Its picture (the copy key's) taken by what draws a message's table, as
// a shot (take_picture).

///|
/// The core's answers about each text read as Markdown, by the text, as they come: every reader of the same text
/// follows the one cell (md_answer), whichever asked (a tree's reader, md_ask, or an old view's markdown); what asked
/// it gone or not. Each kept while something of the window's tree reads its text (md_readers) or its answer is kept
/// (parsed): let go as both are gone, never kept for each text there ever was.
// kept across runs: put back as a run begins (on_reset)
let md_answered : Map[String, @signals.Signal[Int]] = {}

///|
/// How many of the window's tree's readers read each text now (table_node's, as made and as they say another).
// kept across runs: put back as a run begins (on_reset)
let md_readers : Map[String, Int] = {}

///|
/// The core's reading of each text something of the window's tree reads now (md_readers), held by them while they do,
/// whatever the texts read lately (blocks_of's, which others push out): from its answer, or as it was kept as the
/// first of them came; let go as the last goes.
// kept across runs: put back as a run begins (on_reset)
let md_held : Map[String, Array[MdBlock]] = {}

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
    Some(c) => c.set(@signals.untracked(fn() { c.get() }) + 1)
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
  { ..@view.runs_plain, link: p.blue, pressed: alpha(p.blue, 0.14), code_ink: p.code_ink, code_ground: 0L, code_scale: 0.9, words: true }
}

///|
/// The table `text` says (the core's reading of it: table_of; `tree`, its reading as told where that says one: a
/// made-up one's, nothing asked of the core), in `parent`: as Md::table draws it narrow, `bleed` past its room either
/// side where it scrolls across. Its columns' widths from the room it is laid out in (as it is laid out), at the system's
/// size of words.
pub fn table_node(
  parent : @view.View,
  text : () -> String,
  bleed? : Double = 0.0,
  tree? : () -> Json? = fn() { None },
  copy? : Bool = true,
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
) -> Unit {
  let table = fn() { table_of(text(), tree()) }
  parent.box(fn(outer) {
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
/// one of a message's blocks, markdown_node's): its columns' widths from the room it is laid out in, `bleed` past it
/// either side where it scrolls across; its copy key where `copy`; its links taken by `on_link` (`on_link_hold`).
fn md_table_body_node(
  outer : @view.View,
  table : () -> MdTable?,
  bleed : Double,
  copy : Bool,
  on_link : (String) -> Unit,
  on_link_hold : ((String, (Double, Double, Double, Double)) -> Unit)?,
  files? : (String) -> PlacedNode? = fn(_) { None },
) -> Unit {
    outer.margin(Is((-bleed, 0.0, -bleed, 0.0))) |> ignore
    // (each cell's extent, as Md::table works them out: table_widths's, the head's row first)
    let extents_of = fn(t : MdTable) {
      let c = @ui.current()
      let rows = [t.head]
      rows.append(t.rows)
      rows.mapi(fn(r, row) {
        row.map(fn(cell) {
          // (a cell of only images as wide as their row: Md::table's)
          match cell_images_of(cell, files) {
            Some(images) => {
              let w = cell_images_width(images.map(fn(im) { (im.0, fn(_) {  }) }))
              (w, w, true)
            }
            None => {
              let (lo, hi) = table_words_extent(cell, r == 0, fn(x) { c.sp(x) })
              (lo, hi, false)
            }
          }
        })
      })
    }
    // (its key hung out in `bleed` where that has its whole room, as Md::table has it; else past the table, in its room)
    let key_w = if copy { table_key_room } else { 0.0 }
    let hang = if copy && bleed >= table_key_room { table_key_room } else { 0.0 }
    // (its own key, whatever its words: two tables of the same each their own menu, copy and picture)
    table_nodes_made.val += 1
    let key = "sf-table/\{table_nodes_made.val}"
    // where its key cannot hang in the bleed and the room lies between the table at its narrowest and at its widest
    // with its key, the table as wide as the room (its columns sharing all of it) and its key past it, scrolled across to
    // (Md::table's): that room given its grid as said, the arrangement made by it (View::by_room: nothing read back);
    // else the grid shares the room it is laid out in
    let rooms : Map[String, Double] = {}
    outer.by_room(
      // (what the arrangement reads but the room: each cell's extent, at the system's size of words; taken before the
      // layout, followed)
      By(fn() {
        outer.words_redone() |> ignore
        let extents = match table() {
          Some(t) => extents_of(t)
          None => []
        }
        (extents, @ui.current().sp(13.0))
      }),
      fn(at, w, _) {
        let (extents, sp13) = at
        let room = w - 2.0 * bleed
        let narrowest = table_widths(extents, 0.0, false, fn(_) { sp13 }).1
        let widest = table_widths(extents, @double.infinity, false, fn(_) { sp13 }).1
        if copy && hang == 0.0 && room > narrowest && room < widest + key_w {
          let k = "room \{room}"
          rooms[k] = room
          k
        } else {
          "shared"
        }
      },
      sized=true,
      fn(v, arrangement) {
        let given = rooms.get(arrangement)
        v.owns(fn() { rooms.remove(arrangement) }) |> ignore
        v.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), bar_in=bleed, fn(held) {
          // (as wide as it shows at the least, its room in it: the table laid out by that room; wider where the table is,
          // scrolling across)
          held.grow(Is(1.0)).padding(Is((bleed, 0.0, bleed, 0.0))) |> ignore
          // its columns, its rows and the rules between them, and its copy key past it, from their tops (table_beside's), laid
          // out by the room it is given (View::layout_box: nothing of it read back): its columns' widths as table_widths
          // shares that room (less its key's where that is not hung out), each cell as wide as its column, a row as tall as
          // its tallest cell, the key's middle on the head's row's
          held.box(fn(beside) {
            beside
            // (pointed at as a whole, its key with it: what shows its key; taking no press nor hold for it)
            .points(Is(copy))
            .margin(Is((0.0, 0.0, -hang, 0.0)))
            // (never narrower than the table at its narrowest with its key: past the room, scrolled across)
            .min_width(By(fn() {
              let c = @ui.current()
              match table() {
                Some(t) =>
              Some(table_widths(extents_of(t), given.unwrap_or(0.0), false, fn(x) { c.sp(x) }).1 + key_w - hang)
                None => None
              }
            }))
            |> ignore
            let cell_node = fn(cell : @view.View, r : Int, k : Int) {
              let head = r == 0
              let words = fn() {
                match table() {
                  Some(t) => (if head { t.head } else { t.rows.get(r - 1).unwrap_or([]) }).get(k).unwrap_or([])
                  None => []
                }
              }
              let cols = fn() {
                match table() {
                  Some(t) => t.head.length()
                  None => 0
                }
              }
              cell
              .padding(By(fn() {
                let (pl, pr) = table_cell_pad(k, cols())
                (pl, table_cell_y, pr, table_cell_y)
              }))
              .lies_along(Is(Middle))
              |> ignore
              // (a cell of only the message's images: each as wide as cell_image_width says, 6 apart, 4 over and under;
              // else its words as a message's, in pieces, a press on a link where it leads: runs_links. Made by which
              // files it shows, in order ("" its words): another file, one more or fewer, or words, made anew; one told
              // again at another size the same)
              let shows = fn() {
                guard cell_images_of(words(), files) is Some(_) else { return "" }
                let names = md_cell_picture_names(words(), fn(name) {
                  files(name).bind(fn(f) { f.image }).map(fn(im) { im.0 })
                })
                names.map(fn(ns) { ns.map(fn(n) { n.0 }).join("\n") }).unwrap_or("")
              }
              cell.pick(shows, fn(q, shown) {
                if shown != "" {
                  let list = @signals.untracked(fn() { cell_images_of(words(), files) }).unwrap_or([])
                  // (their proportions now, a file told again at another size: worked out once for the cell, again
                  // only as they change)
                  let ratios : @signals.Computed[Array[Double]] = @signals.computed(
                    fn(_) {
                      match cell_images_of(words(), files) {
                        Some(now) => now.map(fn(x) { x.0 })
                        None => list.map(fn(x) { x.0 })
                      }
                    },
                    same=fn(a, b) { a == b },
                  )
                  q.row(Is(true)).gap(Is(6.0)).padding(Is((0.0, 4.0, 0.0, 4.0))) |> ignore
                  for j, im in list {
                    // (as wide as its proportion now says; the picture filling it, made once, the same as it changes)
                    q.box(fn(one) {
                      one.width(By(fn() { Some(cell_image_width(ratios.get().get(j).unwrap_or(im.0))) })) |> ignore
                      one.box(fn(fill) { (im.1)(fill) }) |> ignore
                    })
                    |> ignore
                  }
                  return
                }
                let look = fn() -> @view.WordsLook {
                  let size = if head { 12.0 } else { 13.0 }
                  {
                    size,
                    weight: if head { 500 } else { 400 },
                    line: (Float::from_double(size) * (1.65 : Float)).to_double(),
                    wrap: true,
                    tracking: @view.letters_own,
                    balance: false,
                  }
                }
                let runs = fn() { table_cell_runs(words()) }
                q
                .words_runs(By(runs), look=look())
                .runs_look(By(table_runs_look))
                .ink(By(fn() { if head { web().muted } else { theme().p.text } }))
                |> ignore
                @ui.runs_links(q, runs, on_link, hold?=on_link_hold) |> ignore
              })
            }
            let rule_node = fn(rule : @view.View) { rule.ground(By(fn() { theme().p.line })) |> ignore }
            // (the widths its picture is taken at: the table's as it is laid out then, shown as it is pressed)
            let widths_for = fn(t : MdTable) {
              let c = @ui.current()
              let room = given.unwrap_or(beside.rect().2 + hang - key_w)
              table_widths(extents_of(t), room, false, fn(x) { c.sp(x) })
            }
            let key_node = fn(k : @view.View) { table_key_node(beside, k, key, fn() { table() }, widths_for) }
            beside.layout_box(
              // (what it is laid out by but its room: its rows and columns, each cell's extent, at the system's size of
              // words; taken before the layout, followed)
              By(fn() {
                beside.words_redone() |> ignore
                let extents = match table() {
                  Some(t) => extents_of(t)
                  None => []
                }
                // (and its words' size as the system has it: table_widths's least readable column is read in it)
                (extents, @ui.current().sp(13.0))
              }),
              sized=true,
              fn(l, at) {
                let (extents, sp13) = at
                let rows = extents.length()
                // (the room said where it is given, else the room it is given less its key's)
            let (ws, total) = table_widths(extents, given.unwrap_or(l.width + hang - key_w), false, fn(_) { sp13 })
                let mut y = 0.0
                let mut head_h = 0.0
                for r in 0..<rows {
                  let cells = []
                  let mut h = 0.0
                  for k in 0..<ws.length() {
                    let cell = l.child("cell \{r} \{k}", fn(v) { cell_node(v, r, k) })
                    let (_, ch) = l.measure(cell, ws[k])
                    h = dmax(h, ch)
                    cells.push(cell)
                  }
                  let mut x = 0.0
                  for k, cell in cells {
                    // (each as tall as its row, its words at its top: a row's cells stretched as a flex row's)
                    l.measure(cell, ws[k], height=h) |> ignore
                    l.place(cell, x, y)
                    x = x + ws[k]
                  }
                  if r == 0 {
                    head_h = h
                  }
                  y = y + h
                  // (a rule under each but the last, as faint as is seen)
                  if r < rows - 1 {
                    let rule = l.child("rule \{r}", rule_node)
                    l.measure(rule, total, height=1.0) |> ignore
                    l.place(rule, 0.0, y)
                    y = y + 1.0
                  }
                }
                if copy {
                  let k = l.child("key", key_node)
                  let kh = l.measure(k, key_w).1
                  l.place(k, total, dmax(0.0, (head_h - table_key_size) / 2.0))
                  y = dmax(y, dmax(0.0, (head_h - table_key_size) / 2.0) + kh)
                }
                l.size_to(y)
              },
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
}

///|
/// Tables made as nodes so far: each one's own key (table_node's).
// kept across runs: it goes on counting
let table_nodes_made : Ref[Int] = Ref(0)

///|
/// A table's copy key as nodes (table_key's), `k`, which `beside` (the table and its key, View::points) lays out past the
/// table, its middle on its head's row's: its own `key`, table_key_gap past it and before what follows;
/// pressed, its menu (copy it as Markdown, as CSV, as the core wrote them; as a picture: the table whole, its columns
/// `widths` as they are then, drawn as an old view's table is on the page's ground, taken once: take_picture); once one
/// is copied a check, copied_ms (said on its timeline). Faded in (nav_fade) as the table or its key is pointed at
/// (`beside` saying it is pointed at alone, View::points; what is over it taking the pointer: not), its menu open or it
/// saying it copied, always to a finger; its room kept either way, as tall as the key, nothing in it to press or read
/// out while it has faded out.
fn table_key_node(
  beside : @view.View,
  k : @view.View,
  key : String,
  table : () -> MdTable?,
  widths_for : (MdTable) -> (Array[Double], Double),
) -> Unit {
  let copied = @signals.signal(false)
  let copied_off : Ref[() -> Unit] = Ref(fn() {  })
  let menu_open = @signals.signal(false)
  {
    // (its room kept, as tall as the key, whether it shows or not)
    k
    .width(Is(Some(table_key_gap + table_key_size + table_key_gap)))
    .min_height(Is(Some(table_key_size)))
    .padding(Is((table_key_gap, 0.0, table_key_gap, 0.0)))
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
                  let rows = [now.head]
                  rows.append(now.rows)
                  @ui.take_picture(
                    key + "/picture",
                    total + 2.0 * table_shot_in,
                    fn(c) {
                      c.box(style=table_shot_paper, fn() { table_md(c).table_frame(rows, ws, total, key + "/picture-head") })
                      |> ignore
                    },
                    fn(png) { if (picture_out_by.val)(@ui.current(), png, !album) && !album { said() } },
                    scale=dmax(@ui.current().drawn_scale(), table_shot_scale),
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
  }
}

///|
/// What draws a table's picture (table_frame, as its copy key takes it): a message's Markdown as @sf.markdown sets it,
/// its links taken nowhere, its tables copied by none.
fn table_md(c : @ui.Ctx) -> Md {
  let t = theme()
  {
    c,
    size: t.t.body,
    ink: t.p.text,
    on_link: fn(_) {  },
    on_link_hold: None,
    on_link_shown: None,
    n: 0,
    files: fn(_) { None },
    found: [],
    code: fn(_, _) { None },
    screens: None,
    chat_title: fn(_) { None },
    paths: false,
    line: 0.0,
    serif: false,
    text_face: None,
    code_face: None,
    document: false,
    bleed: 0.0,
    copy: false,
    fit_tables: false,
  }
}

///|
/// A table's cell of only the message's images (Md::cell_images', of the window's tree): each one's proportion and its
/// drawing in a node as wide as it is given; None for any other cell, drawn as words.
fn cell_images_of(cell : Array[MdInline], files : (String) -> PlacedNode?) -> Array[(Double, (@view.View) -> Unit)]? {
  let names = match md_cell_picture_names(cell, fn(name) { files(name).bind(fn(f) { f.image }).map(fn(im) { im.0 }) }) {
    Some(images) => images
    None => return None
  }
  let out = []
  for im in names {
    match files(im.0).bind(fn(f) { f.image }) {
      Some((_, draw)) => out.push((im.1, draw))
      None => return None
    }
  }
  Some(out)
}

