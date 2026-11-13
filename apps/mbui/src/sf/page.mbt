// A page's parts (the library: a page's parts): its frame, sections, groups of rows, rows (to
// another page, a value, a switch), cards, notes, choices. A page is drawn into whatever box it is given and laid out
// by that box's width, once, by its frame (`page`): narrower than the web's narrow app (640), as the web's mobile pages
// are (web/src/mobile/parts.tsx TopBack, LargeTitle, SectionHeader, ListCard, ListRow): back over a large title, its
// rows on rounded cards; wider, as the web's desktop pages are (web/src/styles/pages.css.ts page, pageHead, list, card;
// ui.tsx Section): their head, a column 760 wide at most in the pane's middle, sections with their titles, lists and
// cards. The parts in it read that arrangement (`look`), never measure their own box: a section in a wide page's
// 380 column is a wide one still. Their sizes are the theme's (touch's, keyboard and mouse's). How they answer the
// hand is the input's: what lights under a mouse lights under a finger's press, and a finger's press ripples.

///|
/// How a page is laid out: as the web's narrow app is (`Narrow`), or its desktop pages (`Wide`).
#derive(Eq, Debug)
pub(all) enum Look {
  Narrow
  Wide
}

///|
/// The arrangements of the pages being drawn, the innermost last (a page's frame says its own as it draws what it
/// holds; a presenter its own).
// kept across runs: pushed and popped round what a page draws (empty between them)
let looks : Array[Look] = []

///|
/// The arrangement of the page being drawn (wide, outside any).
pub fn look() -> Look {
  match looks.last() {
    Some(l) => l
    None => Wide
  }
}

///|
/// `body` drawn in arrangement `l` (a page's frame's, a presenter's).
pub fn with_look(l : Look, body : () -> Unit) -> Unit {
  looks.push(l)
  body()
  looks.pop() |> ignore
}

///|
/// How many heads' ends what is drawn now is at (head_end).
// kept across runs: counted up and down round what a head's end draws (0 between them)
let head_ends : Ref[Int] = Ref(0)

///|
/// What a page does, at the end of its head's line (a place's bar, a narrow page's title line: the web's PlaceHead
/// `trailing`), 10 apart: as wide as it is beside the title, which keeps its words whole; where the line has not the
/// room, what is here gives way first (a choice in it fitted to the room left: `segmented`), the title cut only where
/// it is longer than the line leaves it then. A choice here is as wide as its options, not filling the line
/// (not `fill`).
pub fn head_end(c : @ui.Ctx, actions : () -> Unit) -> Unit {
  head_ends.val = head_ends.val + 1
  c.box(style=pg_head_end, actions) |> ignore
  head_ends.val = head_ends.val - 1
}

///|
/// Whether what is drawn now is at a head's end (head_end).
pub fn at_head_end() -> Bool {
  head_ends.val > 0
}

///|
/// The arrangement of a page as wide as `w`.
pub fn look_for(w : Double) -> Look {
  if w < narrow_most {
    Narrow
  } else {
    Wide
  }
}

///|
/// A page that takes no frame's arrangement (a remote screen's, whole in what it is given), drawn as a page `w` wide is
/// arranged.
pub fn arranged(w : Double, wide~ : () -> Unit, narrow~ : () -> Unit) -> Unit {
  match look_for(w) {
    Wide => wide()
    Narrow => narrow()
  }
}

///|
/// The widest a page is laid out as the narrow app is (the web's: max-width 640, where its narrow app takes over).
pub let narrow_most : Double = 640.0

// ── the frame ───────────────────────────────────────────────────────────

///|
/// What the frame a page is shown in gives it (the stack's, the pane's): where back goes, said as its words (None:
/// nowhere, the page at the stack's root or beside a list that is the way back), how far down the page starts under
/// what stands over it (the status bar, a place's top bar), the room it keeps at its foot (the navigation bar, the
/// bottom bar), and whether the frame's own bar names the page already (a place's top page under Home's top bar: no
/// title of its own then). The page draws its bar and what it shows within these and works none of them out itself.
pub(all) struct PageFrame {
  back : String?
  top : Double
  foot : Double
  named : Bool
}

///|
/// What a page made once says of itself to the frame that names it (its bar: `named`), as it changes: its title, what
/// it is for said by a mark beside it ("" none; not its lead, what it holds says under its title). Compared by what it
/// says.
#derive(Eq)
pub(all) struct PageSaid {
  title : String
  about : String
}

///|
/// A frame that gives a page nothing: nowhere back, no room over or under it.
pub let no_frame : PageFrame = { back: None, top: 0.0, foot: 0.0, named: false }

///|
/// What a page says of itself to a bar of the frame's over it (a panel of its own on the tape: the bar a chat's page
/// has there): back (where it goes, said; what it does), its title, what it is for (`about`), what it is of (`small`),
/// whether it has a head of its own that says its name (`own_head`), what it does.
pub(all) struct PageBar {
  back : (String, () -> Unit)?
  title : String
  about : String
  small : String
  own_head : Bool
  actions : (() -> Unit)?
}

///|
/// The frame's bar over a page in a panel of its own (`in_pane`): it draws its bar from what the page says of itself,
/// then `page` under it. The shell's, given as the app starts (None: no such bar, the page its own head).
// kept across runs: a wire, said once as the app starts
pub let pane_bar : Ref[((@ui.Ctx, PageBar, () -> Unit) -> Unit)?] = Ref(None)

///|
/// What a place's top page under the frame's own bar does (its `named`), given to that bar as the page is drawn: the
/// bar holds it at its end and takes it from here (用量's days, 连接's filter).
// kept across runs: said by the page as it is drawn, taken by the bar over it
pub let named_actions : Ref[(() -> Unit)?] = Ref(None)

///|
/// A page titled `title`, holding `content` a block at a time (each laid out as it comes into view), laid out by the
/// width of its box. What its frame gives it (`frame`): back, the room over and under it, whether the frame's bar names
/// it (a place's top page: no title of its own, what it does given that bar, `named_actions`); `on_back` goes back.
/// `lead`: what it is for, under its title; `about`: the same said by a mark beside the title (wide); `actions`: what
/// it does, at its title's end; `head`: a head of its own in place of the title, which says its name (a station's, an
/// account's); `small`: what the page is of, over its large title (narrow: LargeTitle's small line). In a panel of its
/// own (`in_pane`), under the frame's bar there (`pane_bar`), which holds its title, back and what it does: what it
/// shows (a head of its own, what it is for, what it holds) right under that, nothing of those drawn here nor room
/// kept for them.
pub fn page(
  c : @ui.Ctx,
  key : String,
  title : String,
  content : Array[() -> Unit],
  on_back~ : () -> Unit,
  frame? : PageFrame = no_frame,
  lead? : String = "",
  about? : String = "",
  actions? : () -> Unit,
  head? : () -> Unit,
  small? : String = "",
  keys? : Array[(String, String)],
) -> Unit {
  let l = look_for(c.width)
  // (each block by its key and what it shows, while it is not waiting in its bones: page_keyed)
  page_keyed.val = match keys {
    Some(ks) if ks.length() == content.length() && page_bones.val is None => Some(ks)
    _ => None
  }
  let (title, content, head, actions, lead) = page_parts(c, title, content, head, actions, lead)
  // (what it holds drawn as its list lays it out, maybe after this returns: each block says its look as it is drawn)
  let content = content.map(fn(b) { fn() { with_look(l, b) } })
  let head = match head {
    Some(h) => Some(fn() { with_look(l, h) })
    None => None
  }
  let bar = { back: frame.back.map(fn(w) { (w, on_back) }), title, about, small, own_head: head is Some(_), actions }
  under_pane_bar(c, bar, fn() { with_look(l, fn() { barred_page(c, key, l, content, frame.foot, lead, head) }) }, fn() {
    with_look(l, fn() {
      match l {
        Wide =>
          wide_page(c, key, title, content, on_back, frame.back, frame.top, frame.foot, lead, about, actions, head)
        Narrow => narrow_page(c, key, title, content, on_back, frame, lead, actions, head, small)
      }
    })
  })
  // (taken by its list as it was built, or by none: not another page's)
  page_keyed.val = None
}

///|
/// A page's title, blocks, head, what it does and what it is for, as it draws them: as they are, or (while what it
/// shows is read the first time: page_waiting) its frame's title and the rest in its bones.
fn page_parts(
  c : @ui.Ctx,
  title : String,
  content : Array[() -> Unit],
  head : (() -> Unit)?,
  actions : (() -> Unit)?,
  lead : String,
) -> (String, Array[() -> Unit], (() -> Unit)?, (() -> Unit)?, Lead) {
  match page_bones.val {
    Some(pb) => {
      page_bones.val = None
      let bones_of = fn(f : () -> Unit) { fn() { bones(c, f) } }
      (
        pb.title,
        content.mapi(fn(i, b) {
          if i == 0 {
            fn() { waiting(c, b, error=pb.error, note?=pb.note, text=pb.text) }
          } else {
            bones_of(b)
          }
        }),
        head.map(bones_of),
        actions.map(bones_of),
        Lead::Bones(lead),
      )
    }
    None => (title, content, head, actions, Lead::Words(lead))
  }
}

///|
/// What a page is for, under its title: its words, or (while it is read the first time: page_waiting) their bones.
priv enum Lead {
  Words(String)
  Bones(String)
}

///|
fn Lead::is_empty(self : Lead) -> Bool {
  match self {
    Words(w) | Bones(w) => w == ""
  }
}

///|
/// Its words in `style`, or their bones.
fn Lead::draw(self : Lead, c : @ui.Ctx, style : @ui.TextStyle) -> Unit {
  match self {
    Words(w) => c.text(w, style~) |> ignore
    Bones(w) => bones(c, fn() { c.text(w, style~) |> ignore })
  }
}

///|
/// What the page drawn next by `view` says while what it shows is read the first time (page_waiting).
priv struct PageBones {
  title : String
  text : String
  error : String
  note : WaitNote?
}

///|
// kept across runs: set only while page_waiting draws its view, taken by the page it draws (page_parts)
let page_bones : Ref[PageBones?] = Ref(None)

///|
/// A page while what it shows is read the first time (sf/waiting.mbt): the page `view` draws, given made-up
/// data (what it will show, made of made-up words, through a core that answers nothing), drawn with its frame as it
/// is (its back; `title` the frame's, as the page's own is not known yet) and all it shows in its bones (its head, what
/// it is for, what it does, its blocks), breathing; what it waits on (`text`, `note`) said to a screen reader; over it
/// in red what could not be read (`error`, `note`'s failing).
pub fn page_waiting(
  c : @ui.Ctx,
  title : String,
  view : () -> Unit,
  text? : String = "",
  error? : String = "",
  note? : WaitNote,
) -> Unit {
  ignore(c)
  page_bones.val = Some({ title, text, error, note })
  view()
  page_bones.val = None
}

///|
/// In a panel of its own with the frame's bar (`pane_bar`): that bar from `bar`, `barred` under it; else `alone`.
fn under_pane_bar(c : @ui.Ctx, bar : PageBar, barred : () -> Unit, alone : () -> Unit) -> Unit {
  match pane_bar.val {
    Some(draw) if in_pane() => draw(c, bar, barred)
    _ => alone()
  }
}

///|
/// Under a bar of the frame's that holds its title, back and what it does (`pane_bar`): what is left of its head there
/// (a head of its own, as the arrangement has a head's room, 8 or 16 under the bar; what it is for, the line under the
/// title the bar holds, right under the bar), then what it holds as under a page's head, laid out as `l` lays them.
/// Narrow, the head and the lead stand in the page's room as its cards do (pg_room_now: 16 in a panel), as they do
/// under a large title (narrow_page); 2026-11-07 they were the frame's chrome there, against the panel's edge while
/// the cards and the parts' choice stood 16 in (a station's page on an iPhone Duo).
fn barred_page(
  c : @ui.Ctx,
  key : String,
  l : Look,
  content : Array[() -> Unit],
  foot : Double,
  lead : Lead,
  head : (() -> Unit)?,
) -> Unit {
  let blocks : Array[() -> Unit] = []
  match head {
    Some(h) => blocks.push(fn() { c.box(style=if l == Narrow { pg_barred_head } else { desk_first }, h) |> ignore })
    None => ()
  }
  if !lead.is_empty() {
    blocks.push(fn() {
      c.box(style=if l == Narrow { pg_lead_box } else { desk_barred_lead.then(desk_head_in_pane()) }, fn() {
        lead.draw(c, if l == Narrow { pg_lead } else { desk_muted })
      })
      |> ignore
    })
  }
  let chrome = blocks.length()
  match l {
    Narrow => {
      // (its head and what it is for in the page's room as its cards are, the page's own there: nothing of the
      // frame's stands from the page's edges under the bar, which holds back and the title)
      for b in content {
        blocks.push(b)
      }
      narrow_list(c, key, blocks, foot, chrome=0, own=chrome)
    }
    Wide => {
      // (what it holds as under a head: its first 16 under it, the head's own 12 over that)
      for i, b in content {
        blocks.push(fn() { c.box(style=if i == 0 { desk_first } else { desk_block }, fn() { b() }) |> ignore })
      }
      desk_lanes(c, key, blocks, foot~, chrome~)
    }
  }
}

///|
/// A page still drawn with the web's desktop pieces alone (until it is made of these parts), laid out wide whatever
/// its width (detlint's page-look counts the pages that ask for it). As `page`, but for what only a narrow page has.
pub fn page_wide(
  c : @ui.Ctx,
  key : String,
  title : String,
  content : Array[() -> Unit],
  on_back~ : () -> Unit,
  frame? : PageFrame = no_frame,
  lead? : String = "",
  about? : String = "",
  actions? : () -> Unit,
  head? : () -> Unit,
) -> Unit {
  let (title, content, head, actions, lead) = page_parts(c, title, content, head, actions, lead)
  let content = content.map(fn(b) { fn() { with_look(Wide, b) } })
  let head = match head {
    Some(h) => Some(fn() { with_look(Wide, h) })
    None => None
  }
  let back = frame.back.map(fn(w) { (w, on_back) })
  let bar = { back, title, about, small: "", own_head: head is Some(_), actions }
  with_look(Wide, fn() {
    under_pane_bar(c, bar, fn() { barred_page(c, key, Wide, content, frame.foot, lead, head) }, fn() {
      wide_page(c, key, title, content, on_back, frame.back, frame.top, frame.foot, lead, about, actions, head)
    })
  })
}

///|
/// Narrow: back to where it was opened from (TopBack), then its large title (LargeTitle) or its own head, what it is
/// for under it, what it holds; 30 under that, then the frame's room.
fn narrow_page(
  c : @ui.Ctx,
  key : String,
  title : String,
  content : Array[() -> Unit],
  on_back : () -> Unit,
  frame : PageFrame,
  lead : Lead,
  actions : (() -> Unit)?,
  head : (() -> Unit)?,
  small : String,
) -> Unit {
  let { back, top, foot, named } = frame
  let blocks : Array[() -> Unit] = []
  // under what stands over it (a status bar)
  if top > 0.0 {
    blocks.push(fn() { c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore })
  }
  // (a head of its own under back: back's line is its first, what it does at that line's end)
  let back_in_head = head is Some(_) && !named && back is Some(_)
  match back {
    Some(label) if !back_in_head =>
      blocks.push(fn() {
        c.box(style=pg_back_line, fn() {
          nav_back(c, "settings-back", label, on_press=fn() {
            on_back()
          })
        })
        |> ignore
      })
    _ => ()
  }
  // (a place's top page: the frame's bar over it names it, and holds what it does at its end)
  if named {
    match actions {
      // (drawn in the frame's bar, as the page's own head: in its arrangement)
      Some(f) => named_actions.val = Some(fn() { with_look(Narrow, f) })
      None => ()
    }
  }
  if !named && head is None {
    // (with nothing over it, neither back nor what the frame keeps over it: as far down as a wide page's head stands,
    // not at the window's top)
    let alone = back is None && top <= 0.0
    blocks.push(fn() {
      c.box(style=if alone { pg_title_box_alone } else { pg_title_box }, fn() {
        if small != "" {
          c.text(small, style=secondary) |> ignore
        }
        c.box(style=pg_title_line, fn() {
          // (its words whole while what it does at its end can give way: head_end)
          c.box(style=pg_title_words, keep=true, fn() { c.text(title, style=pg_title, keep=true) |> ignore }) |> ignore
          match actions {
            Some(f) => head_end(c, f)
            None => ()
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  match (head, back) {
    (Some(h), Some(label)) if back_in_head =>
      blocks.push(fn() {
        own_head_back.val = Some(fn() {
          nav_back(c, "settings-back", label, on_press=fn() {
            on_back()
          })
        })
        c.box(style=pg_card_room, h) |> ignore
        own_head_back.val = None
      })
    _ => ()
  }
  // (what follows in the page's room: narrow_list)
  let chrome = blocks.length()
  // (a head of its own says its name in place of the title, 10 over what follows as a card is)
  match head {
    Some(h) if !named && !back_in_head => blocks.push(fn() { c.box(style=pg_card_room, h) |> ignore })
    _ => ()
  }
  if !lead.is_empty() {
    blocks.push(fn() { c.box(style=pg_lead_box, fn() { lead.draw(c, pg_lead) }) |> ignore })
  }
  let own = blocks.length()
  for b in content {
    blocks.push(b)
  }
  // (each drawn as its list lays it out, after this returns: its back, its title's line and what it does there in the
  // page's arrangement, as what it holds is)
  narrow_list(c, key, blocks.map(fn(b) { fn() { with_look(Narrow, b) } }), foot, chrome~, own~)
}

///|
/// What the app's fixtures ask of a page's list as it is laid out (scrolled down to a block: settings fixture.mbt's
/// fixture_open), given its key and how many rows it has; nothing in the app itself.
pub let page_list_opened : Ref[(@ui.Ctx, String, Int) -> Unit] = Ref(fn(_, _, _) {  })

///|
/// The keys of the blocks of the page being drawn (`page`'s `keys`: each block's own and what it shows), taken by the
/// list its blocks are laid out in (keyed_blocks); None: its blocks by their places.
// kept across runs: set by each page as it is drawn and taken by its list in the same build; put back by
// page_rows_reset, as a run begins (run_begin)
let page_keyed : Ref[Array[(String, String)]?] = Ref(None)

///|
/// Each page's blocks as given and as its list made of them, by the list's key (keyed_blocks).
// kept across runs: put back by page_rows_reset, as a run begins (run_begin)
let page_lists : Map[String, @ui.ListRows[(String, () -> Unit)]] = Map([])

///|
/// What every page's blocks were forgets (a run anew).
pub fn page_rows_reset() -> Unit {
  page_lists.clear()
  page_keyed.val = None
}

///|
/// List `key`'s `blocks` (the first `chrome` of them its page's own: back, title, head, what it is for), by the keys
/// the page gave its blocks (page_keyed, as many as those after `chrome`): a block new to it opens its room where it
/// is, one gone closes where it was, one showing another thing goes to its new height, as a chat's rows do (ListRows,
/// mbui's ui/list_size.mbt; 2026-11-03 the user: 「只给那几页加身份」); its rows' heights so (the list's `sized`). As
/// given, by their places, where the page gave no keys.
fn keyed_blocks(
  c : @ui.Ctx,
  key : String,
  blocks : Array[() -> Unit],
  chrome : Int,
) -> (Array[() -> Unit], @ui.RowCauses?) {
  let ks = match page_keyed.val {
    Some(ks) if ks.length() == blocks.length() - chrome => ks
    _ => return (blocks, None)
  }
  page_keyed.val = None
  let lr = match page_lists.get(key) {
    Some(l) => l
    None => {
      let l = @ui.ListRows::new()
      page_lists[key] = l
      l
    }
  }
  let keys = Array::makei(chrome, fn(i) { "~" + i.to_string() })
  let versions : Map[String, String] = Map([])
  for k in ks {
    keys.push(k.0)
    versions[k.0] = k.1
  }
  let items = Array::makei(blocks.length(), fn(i) { (keys[i], blocks[i]) })
  let (items, keys) = lr.rows(c, keys, items, fn(it) { versions.get(it.0).unwrap_or("") })
  let drawn = items.mapi(fn(i, it) {
    let k = keys[i]
    fn() {
      let n = c.box(style=full_width, it.1)
      lr.enter(c, n, k)
      lr.leave(c, n, k)
    }
  })
  (drawn, Some(lr.sized()))
}

///|
/// A narrow page's blocks in its list, those from `chrome` on (what it holds: its own head, what it is for, its
/// groups, cards, headings, notes) in the page's room 12 from its sides (pg_room), as a panel's are in the room it
/// leaves; the frame's own over them (back, the large title) from the page's edges; 30 under the last, then `foot`.
fn narrow_list(
  c : @ui.Ctx,
  key : String,
  blocks : Array[() -> Unit],
  foot : Double,
  chrome? : Int = 0,
  own? : Int = chrome,
) -> Unit {
  // (`own`: how many of them are the page's own, before what it holds: its keys are those after)
  let (blocks, sized) = keyed_blocks(c, "settings/" + key, blocks, own)
  let n = blocks.length()
  let pane = pane_round.val
  c.list("settings/" + key, n + 1, 80.0, sized?, fn(i) { with_pane(pane, fn() {
    if i == n {
      c.box(style=@ui.style(w=Full, h=Fixed(pg_foot + foot)), fn() {  }) |> ignore
    } else if i < chrome {
      (blocks[i])()
    } else {
      c.box(style=pg_room_now(), blocks[i]) |> ignore
    }
  }) })
  |> ignore
  (page_list_opened.val)(c, "settings/" + key, n + 1)
}

///|
/// Wide (pages.css.ts page, pageNarrow, pageHead): its head (back over it on a page under another, its title, what it
/// is for, what it does), or a head of its own as far down; then what it holds in the 760 column in the pane's middle,
/// 28 under the head, 80 room at its foot.
fn wide_page(
  c : @ui.Ctx,
  key : String,
  title : String,
  content : Array[() -> Unit],
  on_back : () -> Unit,
  back : String?,
  top : Double,
  foot : Double,
  lead : Lead,
  about_words : String,
  actions : (() -> Unit)?,
  head : (() -> Unit)?,
) -> Unit {
  let blocks : Array[() -> Unit] = []
  // the room the frame keeps over it (a status bar's)
  if top > 0.0 {
    blocks.push(fn() { c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore })
  }
  let deep = back is Some(_)
  let label = back.unwrap_or("")
  match head {
    // as far down as a title's head stands
    Some(h) =>
      blocks.push(fn() {
        c.box(style=(if deep { desk_own_head_deep } else { desk_own_head }).then(desk_head_in_pane()), fn() {
          if deep {
            desk_back(c, label, on_back)
          }
          h()
        })
        |> ignore
      })
    None =>
      blocks.push(fn() {
        c.box(style=(if deep { desk_head_deep } else { desk_head }).then(desk_head_in_pane()), fn() {
          if deep {
            desk_back(c, label, on_back)
          }
          c.box(style=desk_title_line, fn() {
            c.box(style=if about_words == "" { desk_title_words } else { desk_title_about }, fn() {
              // (short of room, cut short before what is at its end)
              c.text(title, style=desk_title) |> ignore
              if about_words != "" {
                about(c, "settings-about", about_words, label=t("web-main.about"))
              }
            })
            |> ignore
            match actions {
              Some(f) => f()
              None => ()
            }
          })
          |> ignore
          // what the page is for, said under its title (pageHead's p: 6 under it, the ui's 13 muted)
          if !lead.is_empty() {
            c.box(style=desk_head_lead_box, fn() { lead.draw(c, desk_muted) }) |> ignore
          }
        })
        |> ignore
      })
  }
  let chrome = blocks.length()
  for i, b in content {
    blocks.push(fn() { c.box(style=if i == 0 { desk_first } else { desk_block }, fn() { b() }) |> ignore })
  }
  desk_lanes(c, key, blocks, foot~, chrome~)
}

///|
/// The way back over a page's head (BackLink): its chevron and where it goes, the ink under the pointer.
fn desk_back(c : @ui.Ctx, back : String, on_back : () -> Unit) -> Unit {
  let th = theme()
  let id = c.id("settings-back")
  c.on_press(id, fn() {
    on_back()
  })
  let lit = c.lit(id)
  let b = c.box(style=desk_back_line, id~, fn() {
    icon(c, "chevron-left", size=desk_back_icon, color=if lit { th.p.text } else { th.p.muted }) |> ignore
    c.text(back, style=if lit { desk_back_lit } else { desk_back_words }) |> ignore
  })
  c.semantics(b, Link, id~, label=back)
}

///|
/// A page's blocks in a list, each laid out as it comes into view: in the pane's middle, 24 from its sides at least,
/// 80 room at its foot (and the frame's room under that). `chrome`: how many of them are its page's own (back, title,
/// head), before the blocks its page keys (keyed_blocks).
pub fn desk_lanes(
  c : @ui.Ctx,
  key : String,
  blocks : Array[() -> Unit],
  foot? : Double = 0.0,
  chrome? : Int = 0,
) -> Unit {
  let (blocks, sized) = keyed_blocks(c, "settings/" + key, blocks, chrome)
  let pane = pane_round.val
  c.list("settings/" + key, blocks.length() + 1, 80.0, sized?, fn(i) { with_pane(pane, fn() {
    if i == blocks.length() {
      if foot > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(desk_foot_h + foot)), fn() {  }) |> ignore
      } else {
        c.box(style=desk_foot, fn() {  }) |> ignore
      }
    } else {
      c.box(style=desk_lane_now(), fn() { c.box(style=desk_lane_column, fn() { (blocks[i])() }) |> ignore }) |> ignore
    }
  }) })
  |> ignore
  (page_list_opened.val)(c, "settings/" + key, blocks.length() + 1)
}

// ── sections, groups, rows ──────────────────────────────────────────────

///|
/// A section of the page: its title over what it holds, `note` what it holds said by it, `actions` what it does at its
/// title's end, `title_after` what its title holds after its words (a count, a mark). Wide: the web's Section (its title
/// 14 on 22, 600; 10 over what it holds, 28 under it all); narrow: SectionHeader (24 in, its words strong; what it holds
/// said at its end), where it `heads`, else what it holds alone, as the web's mobile pages leave a group's title out.
pub fn section(
  c : @ui.Ctx,
  title : String,
  body : () -> Unit,
  heads? : Bool = true,
  note? : String = "",
  actions? : () -> Unit,
  title_after? : () -> Unit,
) -> Unit {
  match look() {
    Wide => wide_section(c, title, body, note~, actions?, title_after?)
    Narrow => {
      // (what it holds said under its heading, in lines: the heading's line keeps its title and what it does)
      if heads && title != "" {
        heading(c, title, actions?)
        if note != "" {
          page_note(c, note)
        }
      }
      body()
    }
  }
}

///|
/// A setting of a few (a choice of a few, a button): its `title`, what it is for (`note`) and its `control`. Wide: a
/// row of its list card (`group`), as a switch's is (switch_row: the same row, a switch at its end): its title with
/// its note under it at its start, the control at its end across their middle (rule 5: what goes together on one
/// line, the control at the line's end); narrow: its title over the control, what it is for under it (the phone's
/// SectionHeader and its note under the choice). A choice drawn as its control (page_choice) is as wide as its
/// options there, not a block of its own.
pub fn setting(c : @ui.Ctx, title : String, control : () -> Unit, note? : String = "") -> Unit {
  match look() {
    Wide => {
      let row = fn() { control_row(c, title, fn() { in_setting(control) }, note~, title_style=setting_title()) }
      if in_list.val > 0 {
        c.box(style=wide_in_list(), row) |> ignore
      } else {
        row()
      }
    }
    // (in a card, a row of it: its title over the control, what it is for under it, as on the page, as far in as its
    // rows' words; a section of the page there stood at the card's edge, 2026-10-29 高级网络设置. Its words last, not
    // the control: a capsule as tall as a control is rounder than the card's corner, never concentric in it)
    Narrow if in_card.val > 0 =>
      c.box(style=narrow_row(false), fn() {
        c.box(style=pg_row_words, fn() {
          c.text(title, style=pg_switch_title) |> ignore
          c.box(style=setting_in_card_control, control) |> ignore
          if note != "" {
            c.text(note, style=meta.then(full_words)) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    // (a section of its own, not a card's: what is in it stands on the page)
    Narrow =>
      section(c, title, heads=true, fn() {
        control()
        if note != "" {
          page_note(c, note)
        }
      })
  }
}

///|
/// A narrow card's setting's control: between its title and its note, 8 from each.
// kept across runs: a value (no field of it changes)
let setting_in_card_control : @ui.Style = @ui.css("w=Full py=S2")

///|
/// A wide setting's title, using the shared row-title weight at the input's text size.
fn setting_title() -> @ui.TextStyle {
  theme().rows.title.then(row_title_weight)
}

///|
/// How many settings' controls what is drawn now is in (setting, wide).
// kept across runs: counted up and down round what a setting's control draws (0 between them)
let settings_in : Ref[Int] = Ref(0)

///|
fn in_setting(f : () -> Unit) -> Unit {
  settings_in.val += 1
  f()
  settings_in.val -= 1
}

///|
/// A heading over a group (narrow: SectionHeader, 24 in, its words strong, what the group holds or does at its end;
/// wide: a section's title, 20 over it).
pub fn heading(c : @ui.Ctx, title : String, note? : String = "", actions? : () -> Unit) -> Unit {
  match look() {
    Narrow =>
      c.box(style=pg_heading_line, fn() {
        c.text(title, style=pg_heading) |> ignore
        c.spacer()
        if note != "" {
          c.text(note, style=pg_heading_note) |> ignore
        }
        // on the title's line and no taller than it (line_end's way): words that do something on it, their room for
        // a finger past it into the heading's own over and under it, rather than the line as tall as their room and
        // the title under their words (2026-10-26: 当前 and 删除 a bar's, not in a line)
        match actions {
          Some(f) => {
            let line = c.text_size(Body).1
            c.box(style=pg_heading_ends.then(@ui.style(h=Fixed(c.sp(line)))), f) |> ignore
          }
          None => ()
        }
      })
      |> ignore
    Wide =>
      c.box(style=wide_heading_line, fn() {
        c.text(title, style=wide_heading) |> ignore
        if note != "" {
          c.text(note, style=wide_value) |> ignore
        }
      })
      |> ignore
  }
}

///|
/// Rows together, on a list card on every page (sf/page.mbt, 列表卡: what a group of settings is, the same
/// on a narrow page and a wide one; the user, 2026-10-26, 「设置感觉很乱」: a wide page's rows on the page and its cards
/// mixed for no reason): narrow, ListCard (12 from the page's sides, 10 under it, its rows 8 in); wide, at the column's
/// edges, its rows' grounds 10 in from its edges and 2 apart, their words 20 in, as a content card's (`card`: words on a
/// card, pages.css.ts card).
pub fn group(c : @ui.Ctx, body : () -> Unit, card? : Bool = false) -> Unit {
  // (in a panel's body (not a small panel's): a card of the panel's, `panel_card_in` from its sides, concentric with
  // it, its rows the ladder's inset in, each on a ground of its own concentric with it, their words a row's padding in
  // from that (a card's words, not the panel's line: the user, 2026-11-03, 面板里可以放卡片; 卡片里的字跟面板的字不需要对齐);
  // wide, its rows as a list's are (in_list: wide_in_list's cells), narrow, as a card's)
  if in_panel() && !in_small_panel() {
    let listed = if look() is Narrow { 0 } else { 1 }
    c.box(style=panel_card_group.then(panel_card_rows).then(panel_card_out()), fn() {
      in_card.val += 1
      in_list.val += listed
      body()
      in_list.val -= listed
      in_card.val -= 1
    })
    |> ignore
    return
  }
  match look() {
    Narrow =>
      c.box(style=pg_card_room, fn() {
        c.box(style=pg_card_now(), fn() {
          // (its rows' grounds round in its corner)
          in_card.val += 1
          body()
          in_card.val -= 1
        })
        |> ignore
      })
      |> ignore
    Wide =>
      wide_alone(c, fn() {
        c.box(style=if card { desk_card } else { desk_list_card() }, fn() {
          // (what is not one of its rows stands in as far as its rows' words; its rows' grounds round in its corners)
          in_list.val += if card { 0 } else { 1 }
          in_card.val += if card { 0 } else { 1 }
          body()
          in_card.val -= if card { 0 } else { 1 }
          in_list.val -= if card { 0 } else { 1 }
        })
        |> ignore
      })
  }
}

///|
/// Several groups of a section, one under another: narrow, each its own 10 under it; wide, where a group has none, 12
/// apart.
pub fn groups(c : @ui.Ctx, body : () -> Unit) -> Unit {
  match look() {
    Narrow => body()
    Wide => c.box(style=groups_wide, body) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let groups_wide : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A group's rows while they are read the first time (sf/waiting.mbt: a list's first read, a section's as
/// well): its card with `rows` in it (its own rows, drawn by what draws them, of made-up words) in their bones,
/// breathing, `text` what it waits on said to a screen reader. Its card as it will be, its rows where they will be:
/// not a wait's line at the card's edge (2026-10-26, 账号's devices: 「这个 loading 很怪」).
pub fn group_waiting(c : @ui.Ctx, rows : () -> Unit, text? : String = "") -> Unit {
  waiting(c, text~, fn() { group(c, rows) })
}

///|
/// A page's long list (its rows laid out as they come into view: `Ctx::list`), its rows drawn in the arrangement of
/// the page it is in: they are drawn after the page's frame has said it (group_row reads it). `sized`: what changed
/// its rows' heights, by their keys (a ListRows' answer: Ctx::list's `sized`).
pub fn rows_list(
  c : @ui.Ctx,
  key : String,
  count : Int,
  est : Double,
  row : (Int) -> Unit,
  sized? : @ui.RowCauses,
) -> Int {
  let (l, pane) = (look(), pane_round.val)
  c.list(key, count, est, fn(i) { with_pane(pane, fn() { with_look(l, fn() { rows_room(c, fn() { row(i) }) }) }) }, sized?)
}

///|
/// What a page's long list holds, in the page's room (narrow: 12 from its sides, as its frame's list gives what it
/// holds: narrow_list); what stands where its rows will, while they are read (their head), as well.
pub fn rows_room(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if look() is Narrow {
    c.box(style=pg_room_now(), body) |> ignore
  } else {
    body()
  }
}

///|
/// What stands over a page's list and stays while it scrolls (a field that filters it), in the page's column as the
/// list's blocks are: narrow, the page's room (pg_room: 12 from its sides); wide, the lanes' column (desk_lanes: in
/// the pane's middle, 792 at most, 24 from its sides at least).
pub fn over_rows(c : @ui.Ctx, body : () -> Unit) -> Unit {
  match look() {
    Narrow => c.box(style=pg_room_now(), body) |> ignore
    Wide => c.box(style=desk_lane_now(), fn() { c.box(style=desk_lane_column, body) |> ignore }) |> ignore
  }
}

///|
/// What stands over a group's rows and tells of them (a list's head: where it is, what it holds), in as far as their
/// words: narrow, those on its card (20); wide, a wide list's rows' (12); 6 between its lines; the rows as far under
/// it as under any small title over a card (title_card_gap). `first`: the first thing of a pane that keeps no room over
/// what it shows (a folder's page under its tools): its own room over it (narrow 2, wide 12); in a page, what is over it
/// is the page's to space.
pub fn rows_head(c : @ui.Ctx, body : () -> Unit, first? : Bool = false) -> Unit {
  let style = match look() {
    Narrow => if first { rows_head_narrow_first } else { rows_head_narrow }
    Wide => if first { rows_head_wide_first } else { rows_head_wide }
  }
  c.box(style~, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let rows_head_narrow : @ui.Style = @ui.css("w=Full px=S2 gap=S1_5").then(@ui.style(pb=room(title_card_narrow)))

///|
// kept across runs: a value (no field of it changes)
let rows_head_narrow_first : @ui.Style = rows_head_narrow.then(@ui.css("pt=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let rows_head_wide : @ui.Style = @ui.css("w=Full px=S3 gap=S1_5").then(@ui.style(pb=room(title_card_wide)))

///|
// kept across runs: a value (no field of it changes)
let rows_head_wide_first : @ui.Style = rows_head_wide.then(@ui.css("pt=S3"))

///|
/// How far a card stands under the small title over it, whichever part says it (a section's title, a heading, a
/// list's head): wide, the web's sectionHead's 10 (parts.css.ts); narrow, SectionHeader's 6.
pub let title_card_wide : Double = 10.0

///|
pub let title_card_narrow : Double = 6.0

///|
/// A row of rows together drawn one at a time (a long list's, each laid out as it comes into view), as `group` holds
/// them: narrow, on its share of a rounded card (ListCard, ListRow: 12 in from the box's sides, the first and last
/// carrying its corners, 10 under the last; each row list_pad in from the card's sides, and from its top on the first,
/// its bottom on the last; its ground concentric with the card's, lit under the pointer or a finger's press (`id`; 0:
/// none, the row lights itself), rippling under a finger); wide, the row alone, on the page.
pub fn group_row(c : @ui.Ctx, first : Bool, last : Bool, body : () -> Unit, id? : Int = 0) -> Unit {
  let ground = if id != 0 && c.lit(id) { Some(theme().p.hover) } else { None }
  if look() is Wide {
    // (on the page: lit under the pointer or a finger's press where it is pressed itself)
    if id == 0 {
      body()
    } else {
      c.box(style=group_wide_row, bg?=ground, id~, fn() {
        body()
        press_ripple(c, id, row_corner)
      })
      |> ignore
    }
    return
  }
  in_card.val += 1
  c.box(style=if last { group_room_last } else { group_room }, fn() {
    c.box(style=group_inner, fn() {
      // the card's ground: rounded where it ends (its first row's top, its last's bottom), square between rows
      c.layer(fn() {
        c.box(style=group_whole, fn() {
          if !first {
            c.box(style=group_corner_room, fn() {  }) |> ignore
          }
          c.box(style=if first || last { group_ground_end } else { group_ground }, fn() {  }) |> ignore
          if !last {
            c.box(style=group_corner_room, fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      if !first {
        c.layer(fn() { c.box(style=group_square, fn() {  }) |> ignore }) |> ignore
      }
      if !last {
        c.layer(fn() {
          c.spacer()
          c.box(style=group_square, fn() {  }) |> ignore
        })
        |> ignore
      }
      let room = match (first, last) {
        (true, true) => group_row_only
        (true, false) => group_row_first
        (false, true) => group_row_last
        (false, false) => group_row_mid
      }
      c.box(style=room, fn() {
        c.box(style=if first || last { group_row_ground_end } else { group_row_ground }, bg?=ground, id~, fn() {
          body()
          if id != 0 {
            press_ripple(c, id, if first || last { @ui.concentric(group_corner, list_pad) } else { row_corner })
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  in_card.val -= 1
}

///|
/// A row pressed itself on a wide page: the row's corner.
// kept across runs: a value (no field of it changes)
let group_wide_row : @ui.Style = @ui.css("w=Full radius=Xl2")

///|
/// A card's room in the page's (ListCard: 10 under the last row).
// kept across runs: a value (no field of it changes)
let group_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let group_room_last : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let group_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A card's row as tall as what it holds, the card's ground layered under it.
// kept across runs: a value (no field of it changes)
let group_inner : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let group_corner_room : @ui.Style = @ui.style(w=Full, h=Fixed(group_corner))

///|
// kept across runs: a value (no field of it changes)
let group_ground : @ui.Style = @ui.css("w=Full h=Full bg=Card")

///|
// kept across runs: a value (no field of it changes)
let group_ground_end : @ui.Style = @ui.css("w=Full h=Full radius=Xl2 bg=Card")

///|
/// Between rows the card goes on square to the row's edge (its corner's room twice).
// kept across runs: a value (no field of it changes)
let group_square : @ui.Style = @ui.style(w=Full, h=Fixed(group_square_h), bg=Card)

///|
let group_square_h : Double = group_corner * 2.0

///|
/// A row's room on its card: list_pad in from its sides, and from its top on the first, its bottom on the last.
// kept across runs: a value (no field of it changes)
let group_row_mid : @ui.Style = @ui.style(w=Full, px=list_room)

///|
// kept across runs: a value (no field of it changes)
let group_row_first : @ui.Style = @ui.style(w=Full, px=list_room, pt=list_room)

///|
// kept across runs: a value (no field of it changes)
let group_row_last : @ui.Style = @ui.style(w=Full, px=list_room, pb=list_room)

///|
// kept across runs: a value (no field of it changes)
let group_row_only : @ui.Style = @ui.style(w=Full, p=list_room)

///|
/// A row's own ground (lit): its corner the row's, concentric with the card's at its ends.
// kept across runs: a value (no field of it changes)
let group_row_ground : @ui.Style = @ui.css("w=Full radius=Xl2")

///|
// kept across runs: a value (no field of it changes)
let group_row_ground_end : @ui.Style = @ui.style(w=Full, radius=group_row_end_radius)

///|
/// How many wide lists what is drawn now is in (a switch's row, a block in one stands in as far as its rows' words).
// kept across runs: counted up and down round what a list draws (0 between them)
let in_list : Ref[Int] = Ref(0)

///|
/// How many narrow cards (a group's) what is drawn now stands in: a row's ground rounds in its card's corner there,
/// and stands square elsewhere (a sheet's row, its edge the sheet's).
let in_card : Ref[Int] = Ref(0)

///|
/// A narrow row's ground, pressed where it goes (`goes`), by where it stands: in a card round, else square, across
/// the page (what it holds on the page's line: as far in as the page's room, pg_room); as high as a row on this screen
/// is at least (Theme.rows: a finger's 48, keyboard and mouse's 40).
fn narrow_row(goes : Bool) -> @ui.Style {
  let ground = match (goes, in_card.val > 0) {
    (true, true) => pg_row
    (false, true) => pg_said_row
    (true, false) => pg_row_square
    (false, false) => pg_said_row_square
  }
  ground.then(@ui.style(min_h=Fixed(theme().items.least)))
}

///|
// kept across runs: a value (no field of it changes)
let pg_row_square : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter hovered{bg=Hover}").then(
  @ui.style(px=room(pg_room_in), py=list_words_room),
)

///|
// kept across runs: a value (no field of it changes)
let pg_said_row_square : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter").then(
  @ui.style(px=room(pg_room_in), py=list_words_room),
)

///|
/// A card of words on the page (narrow: Card, 12 from the page's sides, 10 under it; wide: pages.css.ts card, at the
/// column's edges), its rows 14 apart, 20 in.
/// `footed`: its buttons last (card_foot), its foot as far in as makes them concentric with its corners.
pub fn page_card(c : @ui.Ctx, body : () -> Unit, footed? : Bool = false) -> Unit {
  let card = if footed { desk_card.then(foot_pad(button_height())) } else { desk_card }
  let words = fn() {
    in_words.val += 1
    body()
    in_words.val -= 1
  }
  match look() {
    Narrow if in_layers.val > 0 => c.box(style=card, words) |> ignore
    Narrow => c.box(style=pg_card_room, fn() { c.box(style=card, words) |> ignore }) |> ignore
    Wide => wide_alone(c, fn() { c.box(style=card, words) |> ignore })
  }
}

///|
/// The layers of one thing on a page, one under another (a document's head, the tabs over its text, its text): one
/// block of the page, the room between them `body`'s own (what it says under each), not the room between a page's
/// blocks. A card in it (page_card) is the card alone, none of a block's room round it.
pub fn layers(c : @ui.Ctx, body : () -> Unit) -> Unit {
  in_layers.val += 1
  c.box(style=layers_box, body) |> ignore
  in_layers.val -= 1
}

///|
/// How many layers of one thing what is drawn is in (layers).
// kept across runs: counted up and down round what layers draws (0 between them)
let in_layers : Ref[Int] = Ref(0)

///|
// kept across runs: a value (no field of it changes)
let layers_box : @ui.Style = @ui.css("w=Full")

///|
/// How many cards of words (page_card) what is drawn now stands in: a switch's row there is words beside their switch,
/// no ground of its own (one would stand square, 20 in from the card's corner), on a narrow page as on a wide one.
// kept across runs: counted up and down round what a card draws (0 between them)
let in_words : Ref[Int] = Ref(0)

///|
/// A choice of a few (`segmented`: narrow, as wide as the page less 12 each side; wide, at the column's start, each
/// option `item_w` wide at least). Answers the one chosen (a press's, this frame).
pub fn page_choice(
  c : @ui.Ctx,
  key : String,
  labels : Array[String],
  at : Int,
  item_w? : Double = 0.0,
  on_pick? : (Int) -> Unit,
) -> Int {
  // (a wide setting's control: at its row's end, as wide as its options)
  if settings_in.val > 0 {
    return segmented(c, key, labels, at, item_w~, on_pick?)
  }
  let mut picked = at
  let choice = fn() {
    c.box(style=if look() is Narrow { pg_choice_box } else { desk_choice_row }, fn() {
      picked = segmented(c, key, labels, at, item_w~, on_pick?)
    })
    |> ignore
  }
  if look() is Narrow {
    choice()
  } else {
    wide_alone(c, choice)
  }
  picked
}

///|
/// What the choice over it does, in a line or two (narrow: mSegNote, 24 in, 8 over; wide: the web's hint under it, 8
/// under what is over it, the meta's 12 muted, 52em at most).
pub fn page_note(c : @ui.Ctx, words : String, bad? : Bool = false) -> Unit {
  match look() {
    Narrow =>
      c.box(style=pg_note_box, fn() { c.text(words, style=if bad { pg_note_bad } else { pg_note } ) |> ignore })
      |> ignore
    Wide =>
      c.box(style=desk_hint_box, fn() { c.text(words, style=if bad { desk_note_bad } else { desk_hint_words }) |> ignore })
      |> ignore
  }
}

///|
/// A row that goes somewhere: its title (and `note` under it, in amber where it says what it `lacks`; then `trouble`,
/// what is wrong, in red under that), what it says at its end (`value`, in the link's ink where `value_lit`, in red
/// where `value_bad`, a red dot before it where `value_dot`: something there is not right though nothing is wrong to
/// say), its title `strong` where it names who or what the row is, in red where it takes something away (`danger`:
/// 注销账号), and a chevron (none where not `chevron`: what it does is done here; down where it `folds` what follows
/// it, up while that is open), or an arrow out where it goes `out` of the app; `lead` before its words (a mark, a dot), `tail` after what it says (a pill, a spinner); going nowhere
/// where not `goes` (a value said); `chevron_room` keeps a chevron's space when there is none, so a list's ends align;
/// `below` under its note (its allowance's chips). Its note, what is wrong and what is
/// below are lines of their own as wide as its words, what it says, its tail and its chevron on its first line beside
/// its title (row_top). One that `acts` (does something at once where it is: 检查未决策的 chat) says so at either width:
/// its title in the link's ink, no chevron; one that `adds` one more to the list it ends (添加: an option, a station) is
/// one that acts, a ＋ before its title. `note_cut`: its note one line, cut short (what is in a memory, how a connect
/// runs). `face`: its `lead` is a round picture (a person's, a connect's: 28), which stands across the row's middle on
/// every width: by its first line it stands in the row's corner, 10 from both its edges, its 14 round in the row's 18,
/// which would want a corner of 24, on no step of the ladder (pane_corner); a mark (an icon, a dot) is
/// by its first line.
/// `title_style` supplies a wide row's title size and other properties; its weight follows the shared row-title role.
/// `title_after` after its title on its line (a pill: 你, 当前; a team's name), dropped before the title where
/// the line has not the room for both; `control` at its
/// end, last (a button, a switch, a choice: what is done here, no chevron), a button of words alone there with its
/// words on the line of what rows say at their ends, its ground under the hand reaching out past them to the card's
/// edge (row_end; sf/page.mbt: 文字按钮). `title_cut` and `value_cut` say when either is a summary that
/// may be shortened on its line, rather than words expected to fit whole. `on_press`: what pressing it does, as it is let go (press_does).
pub fn link_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  value? : String = "",
  value_lit? : Bool = false,
  value_bad? : Bool = false,
  value_dot? : Bool = false,
  strong? : Bool = false,
  danger? : Bool = false,
  out? : Bool = false,
  chevron? : Bool = true,
  chevron_room? : Bool = false,
  folds? : Bool,
  note? : String = "",
  lacks? : Bool = false,
  trouble? : String = "",
  lead? : () -> Unit,
  tail? : () -> Unit,
  below? : () -> Unit,
  below_open? : Double,
  goes? : Bool = true,
  acts? : Bool = false,
  adds? : Bool = false,
  title_after? : () -> Unit,
  control? : () -> Unit,
  note_cut? : Bool = false,
  face? : Bool = false,
  title_style? : @ui.TextStyle,
  title_cut? : Bool = false,
  value_cut? : Bool = false,
  tile? : Bool = false,
  on_press? : () -> Unit,
) -> Unit {
  let th = theme()
  // (one that acts: its title in the link's ink, no chevron; one that adds, after a ＋)
  let acts = acts || adds
  let ink = if acts { Some(link_ink()) } else { None }
  let lead = if adds {
    Some(fn() { row_lead_mark(c, "plus", color=link_ink()) })
  } else {
    lead
  }
  let chevron = chevron && !acts && control is None
  // (what follows its title on its line: a pill)
  let after = fn() {
    match title_after {
      Some(f) => f()
      None => ()
    }
  }
  // (wide under a finger, a control with lines under the first is by the whole row's side, as a face's: a wide row's
  // first line is too low for a finger's least room, and the row is wide enough for its lines beside it)
  let face = face ||
    (look() is Wide && native_input() is Finger && control is Some(_) && (note != "" || trouble != "" || below is Some(_)))
  // (a face's row with a control at its end, lines under its first: its words cut short where the control leaves them
  // less, the control by the whole row's side rather than its first line's)
  let note_cut = note_cut || (face && control is Some(_) && (note != "" || trouble != "" || below is Some(_)))
  // (what is done here, at its end: on its first line where lines are under it, as high as that line)
  let control_at_end = fn(under : Bool) {
    match control {
      Some(f) => if under { line_end(c, fn() { row_end(f) }) } else { row_end(f) }
      None => ()
    }
  }
  // (what is wrong in red, a line of its own under its note)
  let narrow_note = fn() {
    if note != "" {
      let style = if lacks { pg_link_note.then(lacking) } else { pg_link_note }
      c.text(note, style=if note_cut { style.then(cut_words) } else { style }) |> ignore
    }
    if trouble != "" {
      c.text(trouble, style=pg_link_note.then(bad)) |> ignore
    }
  }
  let id = if goes { c.id(key) } else { 0 }
  let mark = match (out, folds) {
    (true, _) => "arrow-up-right"
    (false, Some(true)) => "chevron-up"
    (false, Some(false)) => "chevron-down"
    (false, None) => "chevron-right"
  }
  // (lines under its first: its note, what is wrong and what is `below` them, as wide as its words, its end on its
  // first line)
  let under = note != "" || trouble != "" || below is Some(_)
  let more = fn() {
    match (below, below_open) {
      // (what comes and goes under it: as tall as `below_open` of it, its room with it, @motion.reveal)
      (Some(f), Some(open)) =>
        @motion.reveal(c, key + "/below", open, middle=true, fn() { c.box(style=row_below, f) |> ignore })
      (Some(f), None) => c.box(style=row_below, f) |> ignore
      _ => ()
    }
  }
  // (a tile leading it: link_row_node's LeadTile, the row as tall as the tile and the ladder's inset over and under it, or
  // its words and theirs, both across its middle)
  let narrow_style = if tile {
    narrow_row(goes).then(row_tile_row)
  } else if under && !face {
    narrow_row(goes).then(row_top)
  } else {
    narrow_row(goes)
  }
  let b = match look() {
    Narrow =>
      c.box(style=narrow_style.then(row_line(true)), id~, fn() {
        match lead {
          Some(f) => if under && !face && !tile { row_lead(c, Narrow, f) } else { f() }
          None => ()
        }
        let said = fn() {
          let words = fn() {
            let style = if value_bad { pg_value.then(bad) } else { pg_value }
            c.text(value, style=if value_cut { style.then(cut_words) } else { style }, color?=if value_lit {
              Some(link_ink())
            } else {
              None
            })
            |> ignore
          }
          if value_dot {
            c.box(style=value_dotted, fn() {
              status_dot(c, "error")
              words()
            })
            |> ignore
          } else {
            words()
          }
        }
        let titled = match (strong, danger) {
          (_, true) => pg_row_title.then(bad)
          (true, false) => pg_row_title.then(row_strong)
          (false, false) => pg_row_title
        }
        // its end: what follows what it says, its chevron
        let end = fn() {
          match tail {
            Some(f) => f()
            None => ()
          }
          if goes && (chevron || out) {
            icon(c, mark, size=pg_chevron, color=th.p.subtle) |> ignore
          } else if chevron_room {
            c.box(style=@ui.style(w=Fixed(pg_chevron), h=Fixed(pg_chevron)), fn() {  }) |> ignore
          }
          // (a face's row's control at the row's end in its middle, not on its first line: a control as tall as a
          // press's room (button_height) on a first line reaches past the row over it)
          if !(under && face) {
            control_at_end(under)
          }
        }
        if !under {
          if title_cut {
            // A name and what follows it can both give way, but the name keeps enough room to identify it.
            c.box(style=pg_row_words, keep=true, fn() {
              c.text(title, style=titled.then(cut_words), color?=ink) |> ignore
            }) |> ignore
          } else {
            c.text(title, style=titled, color?=ink) |> ignore
          }
          after()
          if value != "" {
            said()
          }
          end()
        } else {
          c.box(style=pg_row_words, fn() {
            c.box(style=row_first_line, fn() {
              if value == "" {
                if title_after is Some(_) {
                  c.box(style=title_line, keep=true, fn() {
                    c.text(title, style=titled.then(cut_words), color?=ink, allow_ellipsis=title_cut) |> ignore
                    after()
                  })
                  |> ignore
                } else if note_cut || title_cut {
                  // (cut short, in a box that takes the line's room: what is at its end stays at the row's end)
                  c.box(style=pg_row_words, fn() { c.text(title, style=titled.then(cut_words), color?=ink) |> ignore }) |> ignore
                } else {
                  c.text(title, style=titled, color?=ink) |> ignore
                }
              } else {
                // its title and what it says in a line (what it says under the title where the line has not the
                // room)
                c.box(style=pg_row_words, fn() {
                  c.box(style=pg_title_value, flow=true, line_gap=0.0, fn() {
                    // (what is after its title beside it, one piece: the line's ends are its title's and what it says)
                    let named = fn() {
                      let style = if strong { pg_row_title_in.then(row_strong) } else { pg_row_title_in }
                      c.text(title, style=if title_cut { style.then(cut_words) } else { style })
                      |> ignore
                      after()
                    }
                    if title_after is Some(_) {
                      c.box(style=title_beside, named) |> ignore
                    } else {
                      named()
                    }
                    said()
                  })
                  |> ignore
                })
                |> ignore
              }
              end()
            })
            |> ignore
            narrow_note()
            more()
          })
          |> ignore
          if face {
            control_at_end(false)
          }
        }
        if goes {
          row_ripple(c, id)
        }
      })
    Wide => {
      let mut row = None
      link_reach(c, id, goes, fn() {
      row = Some(c.box(style=(if under && !face { (if goes { desk_list_link() } else { wide_list_row() }).then(row_top) } else if goes {
        desk_list_link()
      } else {
        wide_list_row()
      }).then(row_line(false)), id~, fn() {
        match lead {
          Some(f) => if under && !face { row_lead(c, Wide, f) } else { f() }
          None => ()
        }
        let title_words = fn() {
          let title_style = title_style.unwrap_or(desk_list_title).then(row_title_weight)
          let style = match (strong, danger) {
            (_, true) => title_style.then(bad)
            (true, false) => title_style.then(row_strong)
            (false, false) => title_style
          }
          if title_after is Some(_) {
            c.box(style=title_line, keep=true, fn() {
              c.text(title, style=style.then(cut_words), color?=ink, allow_ellipsis=title_cut) |> ignore
              after()
            })
            |> ignore
          } else {
            c.text(title, style=if title_cut { style.then(cut_words) } else { style }, color?=ink) |> ignore
          }
        }
        // what it says, what follows it, its chevron
        let end = fn() {
          if value != "" {
            let words = fn() {
              let style = if value_bad { wide_value.then(bad) } else { wide_value }
              c.text(value, style=if value_cut { style.then(cut_words) } else { style }, color?=if value_lit {
                Some(th.p.accent_text)
              } else {
                None
              })
              |> ignore
            }
            if value_dot {
              c.box(style=value_dotted, fn() {
                status_dot(c, "error")
                words()
              })
              |> ignore
            } else {
              words()
            }
          }
          match tail {
            Some(f) => f()
            None => ()
          }
          if goes && (chevron || out) {
            icon(c, mark, size=desk_chevron, color=th.p.muted) |> ignore
          } else if chevron_room {
            c.box(style=@ui.style(w=Fixed(desk_chevron), h=Fixed(desk_chevron)), fn() {  }) |> ignore
          }
          // (a face's row's control at the row's end in its middle, as on a narrow page)
          if !(under && face) {
            control_at_end(under)
          }
        }
        if !under {
          c.box(style=desk_list_text, keep=title_cut, title_words) |> ignore
          end()
        } else {
          c.box(style=desk_list_text, fn() {
            c.box(style=row_first_line, fn() {
              c.box(style=desk_list_text, keep=title_cut, title_words) |> ignore
              end()
            })
            |> ignore
            if note != "" {
              let style = if lacks { wide_list_note.then(lacking) } else { wide_list_note }
              c.text(note, style=if note_cut { style.then(cut_words) } else { style }) |> ignore
            }
            if trouble != "" {
              c.text(trouble, style=desk_note_bad) |> ignore
            }
            more()
          })
          |> ignore
          if face {
            control_at_end(false)
          }
        }
      }))
      })
      row.unwrap()
    }
  }
  if goes {
    c.semantics(b, Link, id~, label=title, expanded?=folds)
  }
  press_does(c, id, goes, on_press)
}

///|
/// A row's title with what follows it on its line (link_row's `title_after`: a pill), 8 apart, across their middle;
/// the title cut short where the line leaves it less.
// kept across runs: a value (no field of it changes)
let title_line : @ui.Style = @ui.style(row=true, w=grow, gap=S2, align=ACenter)

///|
/// A title with what is after it (a pill: 你), as wide as they are, among what else is on its line.
// kept across runs: a value (no field of it changes)
let title_beside : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// Words on one line, cut short where their room is less.
// kept across runs: a value (no field of it changes)
let cut_words : @ui.TextStyle = @ui.text_style(w=Cut, wrap=false)

///|
/// How many rows' ends what is drawn now is at (row_end).
// kept across runs: counted up and down round what a row's end draws (0 between them)
let row_ends : Ref[Int] = Ref(0)

///|
/// What is done at a row's end (link_row's `control`): a button of words alone drawn in it stands its words where
/// the row's value would end, its ground reaching out past them (in_row_end).
fn row_end(f : () -> Unit) -> Unit {
  row_ends.val += 1
  f()
  row_ends.val -= 1
}

///|
/// Whether a button of words alone drawn now is at a row's end (row_end), on either width: its words on the line where
/// the row's value would end, its ground reaching past them by its own room, out to a list card's edge (the row's
/// words room and the card's pad, 16, a button's own), as one at a section's head reaches to the column's.
pub fn at_row_end() -> Bool {
  row_ends.val > 0
}

///|
/// A row's title, distinct from its note and value on every page width and input.
let row_title_weight : @ui.TextStyle = @ui.text_style(weight=Medium)

///|
/// A row's title said strongly (`strong`: who or what a row is, the account's, the workspace's).
// kept across runs: a value (no field of it changes)
let row_strong : @ui.TextStyle = @ui.text_style(weight=Bold)

///|
/// What a row says at its end with its dot before it, 6 apart, across its middle.
// kept across runs: a value (no field of it changes)
let value_dotted : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// A row with lines under its first (a note, what is wrong: words of no length known), each on a line of its own as
/// wide as the row's words: what the row has at its end (what it says, a button, a switch, a chevron) stands on its
/// first line, beside its title, and what it has before its words (`row_lead`) by that line too
/// (mbui ui/squeeze.mbt). Its parts from its top.
// kept across runs: a value (no field of it changes)
let row_top : @ui.Style = @ui.css("align=AStart")

///|
/// A row led by a tile (link_row's `tile`): the ladder's inset over and under what it holds.
let row_tile_row : @ui.Style = @ui.style(py=room(corner_inset))

///|
/// What a row has below its note (its allowance's chips), 6 under it, as wide as its words.
// kept across runs: a value (no field of it changes)
let row_below : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S1_5 align=ACenter")

///|
/// A row's first line: its title, what it has at its end, 12 apart, across their middle.
// kept across runs: a value (no field of it changes)
let row_first_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// A figure (a code to scan, a picture) and the words about it (FeishuConnect.css.ts scan: 24 apart, across their
/// middle, the words 10 apart): wide, the words beside it; narrow, under it, 16 apart, as wide as the page (beside a
/// 196 code a phone left them a hundred points: three lines a sentence, the button past the edge, 2026-10-26).
pub fn figure_words(c : @ui.Ctx, figure : () -> Unit, words : () -> Unit) -> Unit {
  let narrow = look() is Narrow
  c.box(style=if narrow { figure_under } else { figure_beside }, fn() {
    figure()
    c.box(style=if narrow { figure_words_under } else { figure_words_beside }, words) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let figure_beside : @ui.Style = @ui.css("row w=Full gap=S6 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let figure_under : @ui.Style = @ui.css("w=Full gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let figure_words_beside : @ui.Style = @ui.style(w=grow, gap=S2_5, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let figure_words_under : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStart")

///|
/// A name (a chat's, a file's, a station's), or a glimpse of what is in it (a chat's last words), taking what its line
/// leaves the rest of what is on it (a time, a mark), cut short there (`w=Cut`: the one kind of words cut for what is
/// beside them, mbui ui/squeeze.mbt). Its words' node.
pub fn name_words(c : @ui.Ctx, name : String, style : @ui.TextStyle, color? : Int64) -> Int {
  let mut i = 0
  // (keeping four of its size before what may leave its row does: Ctx::box drop)
  c.box(style=name_room, keep=true, fn() { i = c.text(name, style=style.then(name_cut), color?) }) |> ignore
  i
}

///|
// kept across runs: a value (no field of it changes)
let name_room : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let name_cut : @ui.TextStyle = @ui.text_style(wrap=false, w=Cut)

///|
/// A row's words with what it has at its end, as the library's rows lay them (link_row, switch_row): `head`, its first
/// line (its title and what stands at its end: a value, a button, a chevron), across the whole room, 12 apart; then
/// `under`, the lines under it (a note, a time, what is wrong: words of no length known), each a line of its own as
/// wide as the room (mbui ui/squeeze.mbt), `spaced` 2 apart (a wide list's). In place of a row holding
/// a column of words and, beside all of it, what is at its end.
pub fn row_lines(c : @ui.Ctx, head : () -> Unit, under : () -> Unit, spaced? : Bool = false) -> Unit {
  c.box(style=if spaced { desk_list_text } else { pg_row_words }, fn() {
    c.box(style=row_first_line, head) |> ignore
    under()
  })
  |> ignore
}

///|
/// What a row with lines under its first has at the end of that line when it is words (what it says, a button of words
/// alone: `Ghost`), on that line and as high as it (narrow: the body's; wide: a list's title, the UI's 20), 12 apart:
/// a button of words alone is as tall as a button, its words on the line and its ground under the hand reaching past
/// it into the row's room (sf/page.mbt: 文字按钮), rather than the line as tall as the button and the
/// lines under it lower than a row's without one (a 退出 or a 移除 on a device's or a person's first line put its
/// times or its email 8 lower than its neighbours', 2026-10-26). A button drawn with a ground of its own is not one:
/// its line is as tall as it.
pub fn line_end(c : @ui.Ctx, f : () -> Unit) -> Unit {
  let line = match look() {
    Narrow => c.text_size(Body).1
    Wide => c.theme().leading(L6).unwrap_or(c.text_size(Ui).1)
  }
  c.box(style=line_end_box.then(@ui.style(h=Fixed(c.sp(line)))), f) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let line_end_box : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
/// What a row with lines under its first has before its words (a mark, a dot, a face), by its first line: in the
/// middle of a line of its title's (narrow: the body's; wide: a list's title, the UI's 24), from the top where it is
/// taller.
fn row_lead(c : @ui.Ctx, look : Look, f : () -> Unit) -> Unit {
  c.box(style=@ui.style(min_h=Fixed(row_lead_line(c, at=look)), justify=JCenter), f) |> ignore
}

///|
/// A row of a list of choices, one of them `chosen` (a face, a place, a way to sign in): what it is given (`body`: its
/// mark, its words; or `lead` before `label` with `tag` after it on its line and `note` under them, a page row's), and
/// `trail` (a button of its own, which takes its own press) before a check at its end where it is the one chosen
/// (turning while `busy`); the rest of the row takes the press, lit under the pointer or a finger's press (narrow: a
/// card's row; wide: the web's list row), not while `disabled` (its words faint) or busy. `ink`: its label's own (red
/// for one that takes something away). Said to be `label`. `on_press`: what pressing it does, as it is let go; `c.lit(c.id(key))` says it
/// is pointed at.
pub fn choice_row(
  c : @ui.Ctx,
  key : String,
  chosen : Bool,
  label : String,
  body? : () -> Unit,
  note? : String = "",
  lead? : () -> Unit,
  tag? : () -> Unit,
  trail? : () -> Unit,
  ink? : Int64,
  disabled? : Bool = false,
  busy? : Bool = false,
  on_press? : () -> Unit,
) -> Unit {
  let th = theme()
  let id = c.id(key)
  let goes = !disabled && !busy
  press_does(c, id, goes, on_press)
  let narrow = look() is Narrow
  let end = fn(size : Double) {
    match trail {
      Some(f) => f()
      None => ()
    }
    if busy {
      spinner(c, size~) |> ignore
    } else if chosen {
      icon(c, "check", size~, color=th.p.accent) |> ignore
    }
  }
  // its words as a page's row has them: the label (its own ink; faint while it cannot be chosen), what follows it on
  // its line, and its end on that line where a note is under them, as wide as its words (ended: its end its own)
  let under = body is None && note != ""
  let words = fn() {
    match lead {
      Some(f) => if under { row_lead(c, if narrow { Narrow } else { Wide }, f) } else { f() }
      None => ()
    }
    let color = if disabled { Some(th.p.subtle) } else { ink }
    let label_line = fn() {
      c.box(style=choice_label_line, fn() {
        c.text(label, style=(if narrow { pg_row_title } else { desk_list_title }).then(in_lines), color?) |> ignore
        match tag {
          Some(f) => f()
          None => ()
        }
      })
      |> ignore
    }
    c.box(style=if narrow { pg_row_words } else { desk_list_text }, fn() {
      if under {
        c.box(style=row_first_line, fn() {
          c.box(style=pg_row_words, label_line) |> ignore
          end(if narrow { pg_chevron } else { desk_chevron })
        })
        |> ignore
        c.text(note, style=if narrow { pg_link_note } else { wide_list_note }) |> ignore
      } else {
        label_line()
      }
    })
    |> ignore
  }
  let ended = fn(size : Double) {
    if !under {
      end(size)
    }
  }
  let line = row_line(narrow)
  let top = if under { row_top } else { no_reach }
  let b = if narrow {
    c.box(style=narrow_row(goes).then(line).then(top), id=if goes { id } else { 0 }, fn() {
      match body {
        Some(f) => f()
        None => words()
      }
      ended(pg_chevron)
      if goes {
        row_ripple(c, id)
      }
    })
  } else {
    let mut row = None
    link_reach(c, id, goes, fn() {
    row = Some(c.box(style=(if goes { desk_list_link() } else { wide_list_row() }).then(line).then(top), id=if goes { id } else { 0 }, fn() {
      match body {
        Some(f) => f()
        None => words()
      }
      ended(desk_chevron)
    }))
    })
    row.unwrap()
  }
  c.semantics(b, Button, id~, label~, selected=chosen, disabled~)
}

///|
// kept across runs: a value (no field of it changes)
let no_reach : @ui.Style = @ui.css("")

///|
/// A list of a page's rows at a dialog's foot (a station's card's ways on), each pressed as a whole, `style` round
/// them: as dialog_rows' are, the rows round as their height (a wide row's, desk_row_least: no note under its title),
/// out past the dialog's words at its sides and its foot to where the last stands concentric with its foot corners,
/// their words back on the dialog's line (row_line); elsewhere (a sheet's) as they are.
pub fn dialog_foot_rows(c : @ui.Ctx, style : @ui.Style, body : () -> Unit) -> Unit {
  if !in_dialog.val {
    c.box(style~, body) |> ignore
    return
  }
  let was = foot_rows_now.val
  foot_rows_now.val = true
  c.box(style=style.then(@ui.style(mb=room(-foot_rows_out()))), body) |> ignore
  foot_rows_now.val = was
}

///|
/// How far a dialog's foot rows reach out past its words: from its side (dialog_pad) to where a capsule a wide row high
/// stands concentric with its corner.
fn foot_rows_out() -> Double {
  // (and across the room a panel's dialog stands what it holds in from its padding: column_in_now)
  dialog_pad - @ui.capsule_in(dialog_r, desk_row_least()) + column_in_now.val
}

///|
// kept across runs: said by dialog_foot_rows round the rows it draws, false between
let foot_rows_now : Ref[Bool] = { val: false }

///|
/// Where a row of a page's (link_row, choice_row, said_row, item_row) stands across: in a panel's column, its ground
/// reaching out across the room the panel leaves, its words on the column's line (row_reach); in a small panel, a
/// menu's row, at its padding, its words a row's padding in, concentric with it; at a dialog's foot (dialog_foot_rows),
/// a capsule out to where it is concentric with the dialog's foot corners, its words on the dialog's line; where a
/// panel's rows stand at its padding and its words in from it (a dialog's, a sheet opened by a press: panel_words_in),
/// its words that far in, as the panel's other words; on a card or a page, as its own.
fn row_line(narrow : Bool) -> @ui.Style {
  let reach = if in_card.val > 0 {
    0.0
  } else {
    row_reach(if narrow { card_pad - corner_inset } else { desk_list_out })
  }
  if foot_rows_now.val && !narrow {
    let out = foot_rows_out()
    @ui.style(mx=room(-out), px=room(out), radius=Full)
  } else if in_small_panel() {
    panel_row_in()
  } else if in_card.val == 0 && (words_in_now.val > 0.0 || rows_out.val > 0.0) {
    panel_row_in()
  } else if reach > 0.0 {
    @ui.style(mx=room(-reach), px=room(reach))
  } else {
    no_reach
  }
}

///|
/// A choice's label and what follows it on its line (a model's maker), 6 apart.
// kept across runs: a value (no field of it changes)
let choice_label_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// A row that turns something on or off (parts.tsx SwitchRow): its title, `note` quieter under it, the switch at its
/// end across their middle (a round control stays out of the row's corners: mbui ui/squeeze.mbt); the switch
/// alone takes the press, at every width (its reach a finger's least however small it is drawn), its words none. `busy`: what it set is on its
/// way (not turned again meanwhile). `lead`: what goes before its title on its line (a workspace's mark:
/// workspace_badge). Answers whether it is on now.
pub fn switch_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  on : Bool,
  note? : String = "",
  disabled? : Bool = false,
  busy? : Bool = false,
  lead? : (@ui.Ctx) -> Unit,
  on_change? : (Bool) -> Unit,
) -> Bool {
  match look() {
    // (on a narrow page in the words of its narrow rows)
    Narrow if in_words.val > 0 && in_card.val == 0 =>
      wide_switch_row(c, key, title, on, note~, disabled~, busy~, title_style=pg_switch_title, note_style=meta.then(full_words), lead?, on_change?)
    Wide =>
      // (on a settings card holding its rows the ladder's inset in (rows_held) as in a list: its words a row's padding in,
      // its switch out of the card's corner)
      if in_list.val > 0 || rows_held_now.val {
        // (its title as strong as its list's other rows' titles: link_row's, a setting's)
        let mut now = on
        c.box(style=wide_in_list(), fn() {
          now = wide_switch_row(c, key, title, on, note~, disabled~, busy~, title_style=setting_title(), lead?, on_change?)
        })
        |> ignore
        now
      } else {
        wide_switch_row(c, key, title, on, note~, disabled~, busy~, title_style=setting_title(), lead?, on_change?)
      }
    Narrow => {
      // (the switch alone answers: the row is its words, not a press of its own; 2026-10-27 用户「只有开关响应」)
      let mut now = on
      c.box(style=narrow_row(false).then(row_line(true)), fn() {
        // (its switch across the middle of its words: on its title's line it stood in the row's corner, not
        // concentric with it; a switch is narrow, its note keeps most of the row)
        c.box(style=pg_row_words, fn() {
          led_title(c, title, pg_switch_title, lead)
          if note != "" {
            // (in even lines where it takes two beside the switch, not a word or two left on the last)
            c.text(note, style=switch_row_note) |> ignore
          }
        })
        |> ignore
        now = switch(c, key, on, label=title, disabled~, busy~, on_change?)
      })
      |> ignore
      now
    }
  }
}

///|
// kept across runs: a value (no field of it changes)
let switch_row_note : @ui.TextStyle = meta.then(full_words).then(@ui.text_style(balance=true))

///|
/// A row that says how something stands, going nowhere: its title, a note under it, or `value` at its end (a control:
/// a model's picker, in the room its title leaves) (narrow: on its card; wide: the web's list row, no ground under the
/// pointer). `lead`: what goes before its title on its line (a workspace's mark: workspace_badge).
pub fn said_row(c : @ui.Ctx, title : String, note : String, value? : () -> Unit, lead? : (@ui.Ctx) -> Unit) -> Unit {
  let narrow = look() == Narrow
  c.box(style=(if narrow { narrow_row(false) } else { wide_list_row() }).then(row_line(narrow)), fn() {
    match value {
      // its title, and at its end, in the room the title leaves, a control (a model's picker) where a value is said
      Some(f) => {
        led_title(c, title, if narrow { pg_row_title_in } else { desk_list_title }, lead)
        c.box(style=pg_row_end, f) |> ignore
      }
      None =>
        c.box(style=if narrow { pg_row_words } else { desk_list_text }, fn() {
          led_title(c, title, if narrow { pg_row_title } else { desk_list_title }, lead)
          if note != "" {
            c.text(note, style=if narrow { secondary.then(full_words) } else { wide_list_note }) |> ignore
          }
        })
        |> ignore
    }
  })
  |> ignore
}

///|
/// A row's end holding a control: the room its title leaves, the control at its end.
// kept across runs: a value (no field of it changes)
let pg_row_end : @ui.Style = @ui.css("row justify=JEnd align=ACenter").then(@ui.style(w=grow))

///|
/// A row of a group holding what it is given (a piece of software: its mark, its words, its button), going nowhere:
/// narrow, a card's row (12 in, its corner concentric with the card's); wide, the web's list row.
pub fn item_row(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let narrow = look() == Narrow
  c.box(style=(if narrow { narrow_row(false) } else { wide_list_row() }).then(row_line(narrow)), body) |> ignore
}

///|
/// What a group holds that is not a row (a part's figures, its chips): narrow, on its card as far in as its rows'
/// words, 12 over and under; wide, on the page as it is. What it holds 12 apart.
pub fn block(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=if look() == Narrow { pg_block } else if in_list.val > 0 { wide_block.then(wide_in_list()) } else { wide_block }, body)
  |> ignore
}

///|
/// Words on a card (cardRowText): its title strong, `title_after` on its line, `words` under it, `note` quieter under
/// them, `bad` in red.
pub fn card_lines(
  c : @ui.Ctx,
  title : String,
  words? : String = "",
  note? : String = "",
  bad? : String = "",
  title_after? : () -> Unit,
) -> Unit {
  c.box(style=desk_card_text, fn() {
    if title != "" {
      match title_after {
        Some(f) =>
          c.box(style=title_line, keep=true, fn() {
            c.text(title, style=desk_strong.then(cut_words)) |> ignore
            f()
          })
          |> ignore
        None => c.text(title, style=desk_strong) |> ignore
      }
    }
    if words != "" {
      c.text(words, style=desk_words) |> ignore
    }
    if note != "" {
      c.text(note, style=desk_muted) |> ignore
    }
    if bad != "" {
      c.text(bad, style=desk_note_bad) |> ignore
    }
  })
  |> ignore
}

///|
/// A footed card's buttons, last on it (cardFoot: 8 apart), reaching its foot corners as far as they are tall: at its
/// start, or its end where `at_end`. Out across the card's words to its corners at its sides alone: its foot is the
/// footed card's own (page_card's `footed`: as far under them as concentric with its corner), not reached again (the
/// start's did, 4 past the card's edge: the spacing rule 4). The first button without an icon starts its words at the
/// card's words; the button itself remains in the corner.
pub fn card_foot(c : @ui.Ctx, body : () -> Unit, at_end? : Bool = false) -> Unit {
  let was = card_foot_first.val
  card_foot_first.val = !at_end
  c.box(style=(if at_end { pg_card_foot_end } else { pg_card_foot }).then(foot_across(button_height())), body) |> ignore
  card_foot_first.val = was
}

///|
/// The first button in a card foot at its start, while its body is built.
// kept across runs: set while a card foot is built and put back afterwards
let card_foot_first : Ref[Bool] = Ref(false)

///|
/// What a part does, at its heading's end (wide: the web's quiet button with its mark; narrow: SectionHeader's
/// trailing words in the link's ink, room round them for a finger), a spinner in its place while it is `busy`; `bad`:
/// one that takes something away (删除), in the red. `on_press`: what pressing it does, as it is let go (press_does).
pub fn action(
  c : @ui.Ctx,
  key : String,
  label : String,
  icon? : String = "",
  busy? : Bool = false,
  disabled? : Bool = false,
  bad? : Bool = false,
  on_press? : () -> Unit,
) -> Unit {
  match look() {
    Wide => button(c, label, key~, tone=if bad { GhostDanger } else { Ghost }, icon~, busy~, disabled~, on_press?)
    Narrow => {
      if busy {
        spinner(c, size=spinner_inline) |> ignore
        return
      }
      let id = if disabled { 0 } else { c.id(key) }
      let b = c.box(style=pg_action, id~, fn() {
        c.text(label, style=if bad { pg_action_bad } else { pg_action_words }) |> ignore
        if id != 0 {
          press_ripple(c, id, row_corner)
        }
      })
      c.semantics(b, Button, id~, label~)
      press_does(c, id, id != 0, on_press)
    }
  }
}

///|
/// A button of a mark alone (a page's head's: rename, check again, ⋯), said to be `label`: as wide as the screen's
/// hand needs (a finger's 44, a pointer's 32). `on_press`: what pressing it does, as it is let go (press_does).
pub fn icon_action(
  c : @ui.Ctx,
  icon : String,
  key : String,
  label : String,
  disabled? : Bool = false,
  on_press? : () -> Unit,
) -> Unit {
  if native_input() is Finger {
    icon_button(c, icon, key~, size=touch_target, icon_size=touch_glyph, round=true, label~, disabled~, on_press?)
  } else {
    icon_button(c, icon, key~, label~, disabled~, on_press?)
  }
}

///|
/// Figures side by side (the usage's tiles: what each is, its number large, a line under it where it has one), on the
/// page's ground as cards of their own (narrow, 12 from the page's sides as its cards). Always on one line, sharing it
/// (the web's minmax(0, 1fr)): narrow, closer (8 apart, 12 in) and their numbers a size smaller, so three stand on a
/// phone's page, each's line under it there only where it fits whole.
pub fn figures(c : @ui.Ctx, figures : Array[(String, String, String)]) -> Unit {
  let narrow = look() == Narrow
  c.box(style=if narrow { pg_card_room } else { wide_block }, fn() {
    c.box(style=if narrow { fig_row_narrow } else { fig_row }, fn() {
      for f in figures {
        c.box(style=if narrow { fig_tile_narrow } else { fig_tile }, fn() {
          c.text(f.0, style=fig_label) |> ignore
          c.text(f.1, style=if narrow { fig_value_narrow } else { fig_value }) |> ignore
          if f.2 == "" {
            ()
          } else if narrow {
            // (its line under it whole, or none: words cut short say nothing)
            c.box(style=fig_sub_line, fn() { c.box(drop=1, fn() { c.text(f.2, style=fig_sub_whole) |> ignore }) |> ignore })
            |> ignore
          } else {
            c.text(f.2, style=fig_sub) |> ignore
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
/// A dial's figure (Dial): what is left large (`number` and its `unit`), `fill` of its ten cells lit (0–100) in its
/// `level`'s colour (green while plenty; amber, warn, red), its `label` and a quiet `note` under.
pub(all) struct Dial {
  number : String
  unit : String
  fill : Int
  level : String
  label : String
  note : String
  // what `label` and `note` say where their line has not the room ("": nothing shorter)
  label_short : String
  note_short : String
}

///|
/// Dials side by side (MeterDials, QuotaBars: a machine's CPU, memory and disk; an allowance's windows), the figure
/// the words' ink until it runs low. Wide, the web's: each 96 wide at least, 36 apart, on as many lines as they take
/// (12 between). Narrow: sharing the line's width, 16 apart, their cells narrower (6, 2 apart), so three stand in a
/// line on a phone's card.
pub fn dials(c : @ui.Ctx, dials : Array[Dial], details? : Array[String] = [], columns? : Int = 0) -> Unit {
  let narrow = look() == Narrow
  let t = theme()
  let draw = fn(i : Int, short : Bool) {
      let d = dials[i]
      let ink = match d.level {
        "amber" | "warn" => t.p.warn_ink
        "red" => t.p.red
        _ => t.p.green
      }
      let low = d.level == "amber" || d.level == "warn" || d.level == "red"
      let fill = if d.fill < 0 { 0 } else if d.fill > 100 { 100 } else { d.fill }
      let lit = (fill.to_double() / 10.0).round().to_int()
      let cell = if narrow { dl_cell_narrow } else { dl_cell_wide }
      c.box(style=if narrow { dl_dial_narrow } else if columns > 0 { dl_dial_wide_fixed } else { dl_dial_wide }, fn() {
        c.rich(
          [@ui.span(d.number), @ui.span(d.unit, weight=500, scale=t.t.meta / dl_number_size, color=t.p.muted)],
          style=if low { dl_number.then(@ui.text_style(color=Data(ink))) } else { dl_number },
        )
        |> ignore
        c.box(style=if narrow { dl_cells_narrow } else { dl_cells_wide }, fn() {
          for i in 0..<10 {
            c.box(style=if i < lit { cell.then(@ui.style(bg=Data(ink))) } else { cell }, fn() {  }) |> ignore
          }
        })
        |> ignore
        c.text(if short && d.label_short != "" { d.label_short } else { d.label }, style=dl_label) |> ignore
        c.text(
          if d.note == "" { " " } else if short && d.note_short != "" { d.note_short } else { d.note },
          style=if details.is_empty() { dl_reset } else { dl_detail },
        )
        |> ignore
        match details.get(i) {
          Some(detail) if detail != "" => c.text(detail, style=dl_detail) |> ignore
          _ => ()
        }
      })
      |> ignore
  }
  if narrow && columns > 0 {
    c.box(style=dl_rows, fn() {
      for k in 0..<((dials.length() + columns - 1) / columns) {
        let start = k * columns
        let end = @cmp.minimum(start + columns, dials.length())
        c.box(style=dl_row_narrow, fn() {
          for i in start..<end {
            draw(i, false)
          }
          for _ in (end - start)..<columns {
            c.box(style=dl_dial_narrow, fn() {  }) |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
  } else {
    let row = fn(short : Bool) {
      c.box(style=if narrow { dl_row_narrow } else { dl_row_wide }, flow=!narrow, line_gap=dl_lines, fn() {
        for i in 0..<dials.length() {
          draw(i, short)
        }
      })
      |> ignore
    }
    if narrow && dials.iter().any(fn(d) { d.label_short != "" || d.note_short != "" }) {
      // all of them in their full words where the line has the room for all, else all in their short ones: one way for all
      c.box(style=dl_row_ways, one_of=true, fn() {
        row(false)
        row(true)
      })
      |> ignore
    } else {
      row(false)
    }
  }
}

///|
// kept across runs: a value (no field of it changes)
let dl_rows : @ui.Style = @ui.css("w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let dl_row_wide : @ui.Style = @ui.css("row gap=S9 align=AStart")

///|
/// The ways of a narrow row, the room of the line.
// kept across runs: a value (no field of it changes)
let dl_row_ways : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let dl_row_narrow : @ui.Style = @ui.css("row w=Full gap=S4 align=AStart")

///|
/// Between the dials' lines (quotaDials: 12).
let dl_lines : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let dl_dial_wide : @ui.Style = @ui.css("min_w=S24 gap=S0_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let dl_dial_wide_fixed : @ui.Style = @ui.css("w=S24 gap=S0_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let dl_dial_narrow : @ui.Style = @ui.style(w=grow, gap=S0_5, align=AStart)

///|
/// Its figure (quotaDialNumber: the display size, 600, the words' ink while there is plenty).
// kept across runs: a value (no field of it changes)
let dl_number : @ui.TextStyle = @ui.text_style(size=code_big_size, weight=Semibold, color=Fg, wrap=false)

///|
/// Its figure's size, which its unit (quotaDialUnit: the meta size, 500, muted) is a part of: the two are one line's
/// runs, so the unit stands on the figure's baseline.
let dl_number_size : Double = 28.0

///|
/// Its ten cells (quotaDialCells: 4 over and 6 under; a cell 8 by 14, 2 apart, round 2; narrow 6 wide), those not lit
/// in the line's colour: the least a mark with nothing in it is drawn, seen on the card they are on (the neutral
/// ground under words was not: 1.03 to 1 in the dark, 2026-10-26).
// kept across runs: a value (no field of it changes)
let dl_cells_wide : @ui.Style = @ui.css("row gap=SPx pt=S1 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let dl_cells_narrow : @ui.Style = @ui.css("row gap=S0_5 pt=S1 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let dl_cell_wide : @ui.Style = @ui.css("w=S2 h=S3_5 radius=Sm bg=Line mr=SPx")

///|
// kept across runs: a value (no field of it changes)
let dl_cell_narrow : @ui.Style = @ui.css("w=S1_5 h=S3_5 radius=Sm bg=Line")

///|
// kept across runs: a value (no field of it changes)
let dl_label : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dl_reset : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A dial's name and its note in lines of dials (dials_node's `lines`): as wide as its dial, going on under themselves
/// where they are longer, never cut.
// kept across runs: a value (no field of it changes)
let dl_label_lines : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let dl_reset_lines : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let dl_detail : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// A page's own head (an account's, a station's, a connect's: who it is), in place of its title: its `mark` in its box
/// (given the box's side), its `name`, renamed by `rename` (said `rename_label`) where it may be, `busy` while it is
/// saved; `tags` (its runtimes: what it is); `lines` of what it is and where, `dot` (a state's: online, offline …)
/// before the first; how it stands under them (`state`), what is wrong with it (`warnings`: its words, red or not),
/// what it does at the end of its name's line (`actions`). Wide, the web's identity: its mark 48, its name large with
/// its tags and a pencil after it, the lines under it as wide as its words. Narrow: its mark, its name and what it does
/// in one line, the name a size under the page's large title (on more lines only where it does not fit one), pressed
/// to rename it; its tags and lines under them, from the page's edge.
pub fn own_head(
  c : @ui.Ctx,
  mark : (Double) -> Unit,
  name : String,
  rename? : () -> Unit,
  rename_label? : String = "",
  busy? : Bool = false,
  tags? : () -> Unit,
  lines? : Array[String] = [],
  dot? : String = "",
  state? : () -> Unit,
  warnings? : Array[(String, Bool)] = [],
  actions? : () -> Unit,
) -> Unit {
  let narrow = look() == Narrow
  // what is under its name: the first line (the dot, narrow its tags, what it is), the others, how it stands, what is
  // wrong with it
  let below = fn() {
    let shown = lines.filter(fn(l) { l != "" })
    if shown.length() > 0 || dot != "" || (narrow && tags is Some(_)) {
      c.box(style=head_line_row, fn() {
        if dot != "" {
          status_dot(c, dot)
        }
        if narrow {
          match tags {
            Some(f) => f()
            None => ()
          }
        }
        if shown.length() > 0 {
          c.text(shown[0], style=if narrow { head_line_narrow } else { head_line }) |> ignore
        }
      })
      |> ignore
    }
    for i, l in shown {
      if i > 0 {
        c.text(l, style=if narrow { head_line_narrow } else { head_line }) |> ignore
      }
    }
    match state {
      Some(f) => c.box(style=head_state, flow=true, f) |> ignore
      None => ()
    }
    // (red where it does not work, else amber)
    for w in warnings {
      c.text(w.0, style=if w.1 { head_warn_red } else { head_warn_amber }) |> ignore
    }
  }
  let end = fn() {
    match actions {
      Some(f) => c.box(style=head_actions, f) |> ignore
      None => ()
    }
  }
  if narrow {
    // back's line over it, given by its page (narrow_page): what it does at that line's end, over the page's corner
    let back_line = own_head_back.val
    own_head_back.val = None
    match back_line {
      Some(b) =>
        c.box(style=pg_back_line, fn() {
          b()
          c.box(style=pg_row_words, fn() {  }) |> ignore
          end()
        })
        |> ignore
      None => ()
    }
    // (16 over what follows; under a state's line, its button's room is that room already)
    let body = fn() {
      c.box(style=if state is None { head_narrow.then(head_narrow_foot) } else { head_narrow }, fn() {
        c.box(style=head_top_narrow, fn() {
          c.box(style=head_mark_narrow, fn() { mark(head_mark_narrow_side) }) |> ignore
          c.box(style=pg_row_words, fn() {
            // its name a size under the page's large title (its mark beside it: a phone's line), on as many lines as
            // it takes (an address broken after its @ and its dots, not inside a word of it)
            let words = fn() {
              c.text(name.replace_all(old="@", new="@\u{200B}").replace_all(old=".", new=".\u{200B}"), style=head_name_lines)
              |> ignore
            }
            match rename {
              Some(f) => {
                let id = c.id("own-head-name")
                let b = c.box(style=head_name_press, id~, words)
                c.semantics(b, Button, id~, label=if rename_label == "" { name } else { rename_label })
                c.on_press(id, fn() {
                  f()
                })
              }
              None => words()
            }
            if busy {
              spinner(c, size=spinner_inline) |> ignore
            }
          })
          |> ignore
          if back_line is None {
            end()
          }
        })
        |> ignore
        below()
      })
      |> ignore
    }
    // (under back's line from the page's edges, in the page's room as the rest of it is)
    match back_line {
      Some(_) => c.box(style=pg_room, body) |> ignore
      None => body()
    }
    return
  }
  c.box(style=head_wide, fn() {
    c.box(style=head_mark_wide, fn() { mark(head_mark_wide_side) }) |> ignore
    c.box(style=head_identity, keep=true, fn() {
      // its name and what it does on the name's line, the lines under them as wide as its words (lines of their own)
      c.box(style=head_name_row, fn() {
        c.box(style=head_name_line.then(head_name_grow), fn() {
          // (short of room, its name is cut short, what follows it kept)
          c.text(name, style=head_name_wide) |> ignore
          if busy {
            spinner(c, size=spinner_inline) |> ignore
          }
          match tags {
            Some(f) => c.box(style=head_tags_wide, f) |> ignore
            None => ()
          }
          match rename {
            Some(f) => icon_action(c, "edit", "own-head-rename", rename_label, on_press=f)
            None => ()
          }
        })
        |> ignore
        end()
      })
      |> ignore
      below()
    })
    |> ignore
  })
  |> ignore
}

///|
/// Back's line a narrow page gives the own head it draws under it (narrow_page), taken by the head as it is drawn.
// kept across runs: said by a page round its head's drawing, None outside it
let own_head_back : Ref[(() -> Unit)?] = Ref(None)

///|
/// A finger's press rippling over a row (ListRow's, its corner concentric with its card's; square outside one).
pub fn row_ripple(c : @ui.Ctx, id : Int) -> Unit {
  let r = if in_card.val > 0 {
    row_corner
  } else if in_small_panel() {
    small_panel_inner(r_menu)
  } else if words_in_now.val > 0.0 || rows_out.val > 0.0 {
    row_corner
  } else {
    0.0
  }
  press_ripple(c, id, r)
}

// ── styles: narrow (web/src/mobile/parts.css.ts) ────────────────────────

///|
/// Back's line over the large title (TopBack: 10 in, 6 over, 4 under).
// kept across runs: a value (no field of it changes)
let pg_back_line : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S1_5 pb=S1 align=ACenter")

///|
/// The large title (LargeTitle: 16 in, 6 under it), what it does at its end.
// kept across runs: a value (no field of it changes)
let pg_title_box : @ui.Style = @ui.css("w=Full px=S4 pb=S1_5")

///|
/// The large title with nothing over it (no back, no frame's bar): 40 under the top, as a wide page's head (desk_head).
// kept across runs: a value (no field of it changes)
let pg_title_box_alone : @ui.Style = @ui.css("w=Full px=S4 pt=S10 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pg_title_line : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pg_title_words : @ui.Style = @ui.style(w=grow, min_w=S20)

///|
/// A head's end (head_end): what is in it in a line, 10 apart, as wide as it is where the head's line has the room, as
/// narrow as what is in it gives way to where it has less.
// kept across runs: a value (no field of it changes)
let pg_head_end : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pg_title : @ui.TextStyle = large_title.then(@ui.text_style(w=Cut))

///|
/// What the page is for under its title (PageNote: 24 from the page's sides, in its room 12; 10 under it, the
/// secondary words).
// kept across runs: a value (no field of it changes)
pub let pg_lead_box : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
pub let pg_lead : @ui.TextStyle = secondary.then(full_words)

///|
let pg_foot : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let pg_heading_note : @ui.TextStyle = secondary.then(one_line)

///|
/// SectionHeader's line: 24 from the page's side, 20 from its end (in its room, 12 and 8), 14 over, 6 under.
// kept across runs: a value (no field of it changes)
let pg_heading_line : @ui.Style = @ui.css("row w=Full pl=S3 pr=S2 pt=S3_5 gap=S2 align=AEnd").then(
  @ui.style(pb=room(title_card_narrow)),
)

///|
// kept across runs: a value (no field of it changes)
let pg_heading : @ui.TextStyle = body.then(strong)

///|
/// What a heading does at its end, 8 apart, in the middle of its title's line.
// kept across runs: a value (no field of it changes)
let pg_heading_ends : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A narrow page's room: what it holds 12 from its sides (ListCard's), its frame's to give (narrow_list; a frame of
/// its own, a long list's: rows_list), as a panel gives what it holds the room it leaves. What reaches the page's
/// sides on purpose goes out across it (page_bleed).
// kept across runs: a value (no field of it changes)
pub let pg_room : @ui.Style = @ui.style(w=Full, px=room(pg_room_in))

///|
let pg_room_in : Double = 12.0

///|
/// A narrow page's room in a panel of its own (the tape's, laid out Medium: in_pane): its cards cards of the panel's,
/// `panel_card_in` from its sides (the user, 2026-11-03: 面板里可以放卡片); on a phone's screen, pg_room.
pub fn pg_room_now() -> @ui.Style {
  if in_pane() {
    pg_room_pane
  } else {
    pg_room
  }
}

///|
// kept across runs: a value (no field of it changes)
let pg_room_pane : @ui.Style = @ui.style(w=Full, px=room(panel_card_in))

///|
/// A narrow page's card in a panel of its own: a card's corner, its rows the ladder's inset in.
fn pg_card_now() -> @ui.Style {
  if in_pane() {
    pg_card_pane
  } else {
    pg_card
  }
}

///|
// kept across runs: a value (no field of it changes)
let pg_card_pane : @ui.Style = @ui.css("w=Full bg=Card clip").then(@ui.style(p=room(corner_inset), radius=card_radius))

///|
/// A card on a narrow page (in its room): 10 under each.
// kept across runs: a value (no field of it changes)
pub let pg_card_room : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
/// A head of its own under a bar of the frame's (barred_page), narrow: in the page's room as its cards, 8 under the bar.
// kept across runs: a value (no field of it changes)
let pg_barred_head : @ui.Style = pg_card_room.then(@ui.css("pt=S2"))

///|
/// ListCard: its rows list_pad in, its corner concentric round theirs.
// kept across runs: a value (no field of it changes)
let pg_card : @ui.Style = @ui.style(w=Full, p=list_room, radius=list_card_radius, bg=Card, clip=true)

///|
/// A choice of a few on a narrow page: as far from what follows as a card is (pg_card_room's 10), a page's block.
// kept across runs: a value (no field of it changes)
let pg_choice_box : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
pub let pg_note_box : @ui.Style = @ui.css("w=Full px=S3 pt=S2 pb=S1")

///|
// kept across runs: a value (no field of it changes)
pub let pg_note : @ui.TextStyle = secondary.then(full_words)

///|
// kept across runs: a value (no field of it changes)
pub let pg_note_bad : @ui.TextStyle = pg_note.then(bad)

///|
/// A row of a card (ListRow): its words a row's room in all round (list_words_room: 16 from the card's edge, as a
/// menu's), what it holds 12 apart, its ground concentric with the card's; lit under the pointer, or a finger's press.
// kept across runs: a value (no field of it changes)
pub let pg_row : @ui.Style = @ui.css("row w=Full gap=S3 radius=Inner align=ACenter hovered{bg=Hover}").then(
  @ui.style(p=list_words_room),
)

///|
// kept across runs: a value (no field of it changes)
pub let pg_said_row : @ui.Style = @ui.css("row w=Full gap=S3 radius=Inner align=ACenter").then(@ui.style(p=list_words_room))

///|
// kept across runs: a value (no field of it changes)
pub let pg_row_words : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
pub let pg_row_title : @ui.TextStyle = body.then(row_title_weight).then(one_line).then(full_words)

///|
/// A row's title where what it says follows it in the line (narrow, over its note).
// kept across runs: a value (no field of it changes)
let pg_row_title_in : @ui.TextStyle = body.then(row_title_weight).then(one_line)

///|
/// Its title and what it says, at the line's two ends (one under the other where the line has not the room), 12 apart.
// kept across runs: a value (no field of it changes)
let pg_title_value : @ui.Style = @ui.css("row w=Full gap=S3 justify=JBetween align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pg_switch_title : @ui.TextStyle = body.then(row_title_weight).then(full_words)

///|
// kept across runs: a value (no field of it changes)
pub let pg_value : @ui.TextStyle = value

///|
/// A link row's mark before its title (its `lead`): icon `name` as large as its chevron at either width, in the title's
/// ink unless `color` says (the ＋ of one that adds, in the link's).
pub fn row_lead_mark(c : @ui.Ctx, name : String, color? : Int64) -> Unit {
  icon(c, name, size=if look() == Narrow { pg_chevron } else { desk_chevron }, color=color.unwrap_or(theme().p.text))
  |> ignore
}

///|
pub let pg_chevron : Double = 14.0

///|
/// The words under a row's title (the secondary's, in lines).
// kept across runs: a value (no field of it changes)
pub let pg_link_note : @ui.TextStyle = secondary.then(full_words)

// ── styles: wide (web/src/styles/pages.css.ts) ──────────────────────────

///|
// kept across runs: a value (no field of it changes)
let wide_heading_line : @ui.Style = @ui.css("w=Full pt=S5").then(@ui.style(pb=room(title_card_wide)))

///|
// kept across runs: a value (no field of it changes)
pub let wide_heading : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, w=Full)

///|
/// What a wide row says at its end (the meta's 12, muted, on one line).
// kept across runs: a value (no field of it changes)
pub let wide_value : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The page's head (pageHead): on a page under another (back over its title) 20 down, else 40; 12 under it; 16 in.
// kept across runs: a value (no field of it changes)
let desk_head : @ui.Style = @ui.css("w=Full px=S4 pt=S10 pb=S3 bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let desk_head_deep : @ui.Style = desk_head.then(@ui.css("pt=S5"))

///|
/// Its title and what is at its end, in a line; the title's words the room its line has left (the title grows, its
/// actions at its end; never under a few words).
// kept across runs: a value (no field of it changes)
let desk_title_line : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_title_words : @ui.Style = @ui.style(w=grow, min_w=S20)

///|
// kept across runs: a value (no field of it changes)
let desk_title_about : @ui.Style = desk_title_words.then(@ui.css("row gap=S1_5 align=ACenter"))

///|
/// Its title (22 on 32, 600: the web's 34 off the line scale, its nearest).
// kept across runs: a value (no field of it changes)
let desk_title : @ui.TextStyle = @ui.text_style(size=Heading, leading=L8, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let desk_head_lead_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
let desk_back_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let desk_back_line : @ui.Style = @ui.css("row pb=S2 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_back_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_back_lit : @ui.TextStyle = desk_back_words.then(@ui.text_style(color=Fg))

///|
/// A block's lane across the pane, its column in the middle: 792 at most, 24 from the pane's sides at least (its blocks'
/// own 16 inside it: the 760 column).
// kept across runs: a value (no field of it changes)
pub let desk_lane : @ui.Style = @ui.css("w=Full px=S6 align=ACenter")

///|
/// The same in a panel of its own (the tape's: in_pane): none in from the panel's sides, its blocks' own 16 there the
/// cards' panel_card_in (the user, 2026-11-03: 面板里可以放卡片), the column in the middle where it is wider.
pub fn desk_lane_now() -> @ui.Style {
  if in_pane() {
    desk_lane_pane
  } else {
    desk_lane
  }
}

///|
// kept across runs: a value (no field of it changes)
let desk_lane_pane : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// A wide page's head in a panel of its own: its words on the panel's words' line (panel_words), its cards 16 in;
/// none elsewhere.
fn desk_head_in_pane() -> @ui.Style {
  if in_pane() {
    desk_head_pane
  } else {
    no_desk_head
  }
}

///|
// kept across runs: a value (no field of it changes)
let desk_head_pane : @ui.Style = @ui.style(px=room(panel_words))

///|
// kept across runs: a value (no field of it changes)
let no_desk_head : @ui.Style = @ui.css("")

///|
// kept across runs: a value (no field of it changes)
pub let desk_lane_column : @ui.Style = @ui.style(w=Full, max_w=Fixed(desk_lane_most))

///|
pub let desk_lane_most : Double = 792.0

///|
pub let desk_lane_in : Double = 24.0

///|
/// The room at the page's foot.
// kept across runs: a value (no field of it changes)
let desk_foot : @ui.Style = @ui.css("w=Full h=S20")

///|
let desk_foot_h : Double = 80.0

///|
/// A page's head of its own (an account's): where a title's head would stand.
// kept across runs: a value (no field of it changes)
pub let desk_own_head : @ui.Style = @ui.css("w=Full px=S4 pt=S10")

///|
/// (with the way back over it: as high as a title's head with it stands)
// kept across runs: a value (no field of it changes)
let desk_own_head_deep : @ui.Style = @ui.css("w=Full px=S4 pt=S5")

///|
pub let desk_column_most : Double = 760.0

///|
pub let desk_column_in : Double = 16.0

///|
/// A block of the page, at the column's edges; the first 28 under the head (its own 12 and these 16).
// kept across runs: a value (no field of it changes)
let desk_block : @ui.Style = @ui.css("w=Full px=S4")

///|
// kept across runs: a value (no field of it changes)
let desk_first : @ui.Style = desk_block.then(@ui.css("pt=S4"))

///|
/// What the page is for under a bar of the frame's (barred_page), wide: the line under the title the bar holds, right
/// under the bar, in the column as its blocks; 12 under it as under a head (pageHead's), what it holds 16 under that.
// kept across runs: a value (no field of it changes)
let desk_barred_lead : @ui.Style = @ui.css("w=Full px=S4 pb=S3")

///|
// kept across runs: a value (no field of it changes)
pub let desk_hint_box : @ui.Style = @ui.style(w=Full, max_w=Fixed(desk_hint_most), pt=S2)

///|
let desk_hint_most : Double = 624.0

///|
// kept across runs: a value (no field of it changes)
pub let desk_hint_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// A card of words (pages.css.ts card: 20 in, its rows 14 apart, the settings' corner on the card's ground; a row of
/// it: cardRow, 12 apart in its middle; its words cardRowText, 2 apart, the ui's 13 on 20, the title in 600).
// kept across runs: a value (no field of it changes)
pub let desk_card : @ui.Style = @ui.css("w=Full gap=S3_5 radius=Xl3 bg=Card").then(@ui.style(p=room(card_pad)))

///|
// kept across runs: a value (no field of it changes)
pub let desk_card_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let desk_card_text : @ui.Style = @ui.style(w=grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
pub let desk_strong : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
pub let desk_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
pub let desk_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// A list on a wide page: a list card (the narrow page's ListCard, at the column's edges: list_pad in, its rows 2
/// apart), each row 52 high at least, 10 by 10 in, its parts 12 apart, its corner concentric with the card's; one that
/// opens on the pointer's ground; its title in 500, what is under it the meta's 12 muted, red where it is wrong; a chevron 16.
/// How high it is at least goes by the native input (the theme's items'): 36 with keyboard and mouse, a finger's 44 with
/// touch, no taller than a press needs (rule 2; the user, 2026-10-26: 「浪费空间」; 2026-10-27: 大屏最小 36).
pub fn desk_row_least() -> Double {
  theme().items.least
}

///|
pub let desk_chevron : Double = 16.0

///|
pub let desk_mark : Double = 14.0

///|
/// A card of a panel's, on its ground as its other cards are (the ink at 5%: info_list's, a choice's): a card's own ground is
/// the panel's, unseen on it.
// kept across runs: a value (no field of it changes)
let panel_card_group : @ui.Style = panel_card_ground.then(@ui.style(radius=rounded(card_corner)))

///|
/// A card of a panel's, its ground alone (panel_card_group's, its corners left to what draws it: a card's piece,
/// card_piece_node).
// kept across runs: a value (no field of it changes)
let panel_card_ground : @ui.Style = @ui.css("w=Full bg=A(Fg,O5) clip")

///|
// kept across runs: a value (no field of it changes)
let panel_card_rows : @ui.Style = @ui.style(p=room(corner_inset))

///|
pub let desk_list : @ui.Style = @ui.style(w=Full, p=list_room, gap=S0_5, radius=list_card_radius, bg=Card)

///|
/// The same in a panel of its own (in_pane): a card of the panel's, its words 24 in from its edges, its rows' grounds
/// the ladder's inset in (wide_list_link_pane: reaching past their rows to there), a card's corner, its rows as close
/// as a list card's; what stands at a row's end in its corners stands outside them, as far in as its words (the user,
/// 2026-11-03: 就按第 3 版).
pub fn desk_list_card() -> @ui.Style {
  if in_pane() {
    desk_list_pane
  } else {
    desk_list
  }
}

///|
// kept across runs: a value (no field of it changes)
let desk_list_pane : @ui.Style = @ui.style(
  w=Full,
  px=room(corner_inset),
  py=room(card_pad - wide_row_pad),
  gap=S0_5,
  radius=card_radius,
  bg=Card,
)

///|
/// How far a wide list's row's words stand under its top and over its foot (wide_list_row_ground's and
/// wide_in_list's py=S2_5).
let wide_row_pad : Double = 10.0

///|
pub let desk_list_out : Double = 12.0

///|
fn wide_list_row() -> @ui.Style {
  // (in a panel's card no ground of its own (one only where pressed: desk_list_link), so none in its corners)
  (if in_pane() { wide_list_row_bare } else { wide_list_row_ground }).then(@ui.style(min_h=Fixed(desk_row_least())))
}

///|
// kept across runs: a value (no field of it changes)
let wide_list_row_bare : @ui.Style = @ui.style(
  row=true,
  w=Full,
  pl=list_words_room,
  pr=room(card_control_end),
  py=S2_5,
  gap=S3,
  align=ACenter,
)

///|
/// How far in from its end a row on a panel's card has what it holds at its end (a model's picker, 更新): its words'
/// room, or as far as holds it out of the card's corner where that is more (the card's 26 round, its words 24 in: 2
/// more; the user's 第 3 版, 2026-11-03: a control stays out of its card's corner, its row's spacing as it was).
pub let card_control_end : Double = text_in + dmax(0.0, card_corner - panel_words)

///|
// kept across runs: a value (no field of it changes)
let wide_list_row_ground : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=list_words_room,
  py=S2_5,
  gap=S3,
  align=ACenter,
  radius=InnerOr(Xl2),
)

///|
fn desk_list_link() -> @ui.Style {
  if in_pane() && !rows_held_now.val {
    // (its ground the box round it's: link_reach)
    wide_list_row_bare.then(@ui.style(min_h=Fixed(desk_row_least())))
  } else if rows_held_now.val {
    // (on a card holding its rows the ladder's inset in: a ground of its own, concentric there)
    wide_list_row_ground.then(@ui.style(min_h=Fixed(desk_row_least()))).then(link_hover)
  } else {
    wide_list_row().then(link_hover)
  }
}

///|
/// Whether the card the rows now made stand on holds them the ladder's inset from its top and foot, each its own ground
/// (a settings page's list card: rows_held), so a pressed one's reaches past it none (link_reach).
// kept across runs: said around a card's rows as they are made, put back after
let rows_held_now : Ref[Bool] = Ref(false)

///|
/// `body`'s rows made on a card that holds them the ladder's inset from its top and foot (rows_held_now).
/// They are on a card (in_card) as a group's are: their words a row's padding in from their grounds, which round in
/// the card's corners (2026-11-06: a settings card's link rows 4 nearer its edge than its other rows' words, their
/// grounds square).
pub fn rows_held(body : () -> Unit) -> Unit {
  let was = rows_held_now.val
  rows_held_now.val = true
  in_card.val += 1
  body()
  in_card.val -= 1
  rows_held_now.val = was
}

///|
/// A row pressed as a whole (`id`, where it `goes`) made by `row`: on a panel's card in a box round it whose ground,
/// lit as the row is, reaches past it over and under to the card's rows' inset from its edges where it is first or
/// last (desk_list_pane: its words 24 in, its grounds 8), as far past it every way; the row itself where it stands,
/// what is pressed, a press beside it its neighbour's. Elsewhere the row alone.
fn link_reach(c : @ui.Ctx, id : Int, goes : Bool, row : () -> Unit) -> Unit {
  if goes && in_pane() && !rows_held_now.val {
    let ground = if c.lit(id) { theme().p.hover } else { 0L }
    c.box(style=wide_list_link_reach.then(@ui.style(bg=Data(ground))), row) |> ignore
  } else {
    row()
  }
}

///|
/// The box round a pressed row on a panel's card (link_reach): reaching `card_pad - wide_row_pad - corner_inset` past
/// it over and under, the row back where it was by as much room.
// kept across runs: a value (no field of it changes)
let wide_list_link_reach : @ui.Style = @ui.style(
  w=Full,
  my=room(-(card_pad - wide_row_pad - corner_inset)),
  py=room(card_pad - wide_row_pad - corner_inset),
  radius=InnerOr(Xl2),
)

///|
// kept across runs: a value (no field of it changes)
let link_hover : @ui.Style = @ui.css("hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
pub let desk_list_text : @ui.Style = @ui.style(w=grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
pub let desk_named : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let desk_list_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false).then(row_title_weight)

///|
// kept across runs: a value (no field of it changes)
pub let wide_list_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// A note on one line beside or under what it is about: cut short where it has less, never wrapped a letter a line.
// kept across runs: a value (no field of it changes)
pub let desk_note_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
pub let desk_note_bad : @ui.TextStyle = wide_list_note.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let desk_choice_row : @ui.Style = @ui.css("row w=Full")

// ── styles: what both arrangements share ────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let pg_block : @ui.Style = @ui.css("w=Full gap=S3").then(@ui.style(p=list_words_room))

///|
// kept across runs: a value (no field of it changes)
let wide_block : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A card's buttons at its foot (cardFoot).
// kept across runs: a value (no field of it changes)
let pg_card_foot : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// A heading's words that do something: room round them for a finger (4), the link's ink.
// kept across runs: a value (no field of it changes)
let pg_action : @ui.Style = @ui.css("p=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let pg_action_words : @ui.TextStyle = @ui.text_style(size=Body, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pg_action_bad : @ui.TextStyle = pg_action_words.then(bad)

///|
/// A finger's target (44 at least) and its mark in it.
let touch_target : Double = 44.0

///|
let touch_glyph : Double = 20.0

///|
/// The figures (the usage's tiles: 10 apart; each 112 wide at least, 16 by 14 in, its corner the cards', on the card's
/// ground; what it is the meta's, its number 22 strong, a line under it subtle).
// kept across runs: a value (no field of it changes)
let fig_row : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let fig_row_narrow : @ui.Style = @ui.css("row w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let fig_tile : @ui.Style = @ui.style(w=grow, min_w=S28, px=S4, py=S3_5, gap=S0_5, radius=Xl3, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let fig_tile_narrow : @ui.Style = @ui.style(w=grow, min_w=S0, px=S3, py=S3, gap=S0_5, radius=Xl3, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let fig_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let fig_value : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let fig_value_narrow : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let fig_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let fig_sub_whole : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let fig_sub_line : @ui.Style = @ui.css("row w=Full")

///|
/// A page's own head: wide, its mark 48 and its words beside it, 16 apart, 28 over what follows; narrow, its mark 40,
/// 12 from its words, 16 over what follows, its words from the top.
// kept across runs: a value (no field of it changes)
let head_wide : @ui.Style = @ui.css("row w=Full pb=S7 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_narrow : @ui.Style = @ui.css("w=Full px=S1 gap=S1_5")

///|
/// Narrow, its mark, its name and what it does: a line across its middle.
// kept across runs: a value (no field of it changes)
let head_top_narrow : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_narrow_foot : @ui.Style = @ui.css("pb=S4")

///|
// kept across runs: a value (no field of it changes)
let head_mark_wide : @ui.Style = @ui.css("w=S12 h=S12 radius=Lg bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let head_mark_narrow : @ui.Style = @ui.css("w=S10 h=S10 radius=Lg bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let head_identity : @ui.Style = @ui.style(w=grow, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let head_name_line : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_name_wide : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let head_name_lines : @ui.TextStyle = @ui.text_style(size=Heading, weight=Bold, color=Fg, w=Full)

///|
/// Wide, its tags 8 after its name.
// kept across runs: a value (no field of it changes)
let head_tags_wide : @ui.Style = @ui.css("pl=S2")

///|
// kept across runs: a value (no field of it changes)
let head_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// How it stands, under its lines (8 apart).
// kept across runs: a value (no field of it changes)
let head_state : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_actions : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// Its name's line: its name, what it does at its end (narrow: from the top, the large title in as many lines as it
/// takes; wide: across their middle), 12 apart.
// kept across runs: a value (no field of it changes)
let head_name_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)

///|
/// Its name and what follows it, wide, taking what the line leaves what it does.
// kept across runs: a value (no field of it changes)
let head_name_grow : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let head_warn_red : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let head_warn_amber : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=WarnInk, w=Full)

///|
// kept across runs: a value (no field of it changes)
let pg_card_foot_end : @ui.Style = @ui.css("row w=Full gap=S2 justify=JEnd align=ACenter")

///|
/// What a section holds that is neither rows nor a card (its chips, a field with its button): narrow, as far in as the
/// page's headings' words (24 from its sides, 12 in its room), 10 under it; wide, at the column's edges. What it holds
/// 12 apart.
pub fn loose(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=if look() == Narrow { pg_loose } else { wide_block }, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let pg_loose : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5 gap=S3")

///|
/// Its mark's box's side (what draws in it is given it): 48 wide, 40 narrow.
let head_mark_wide_side : Double = 48.0

///|
let head_mark_narrow_side : Double = 40.0

///|
/// What stands in a wide list that is not one of its rows: as far in as its rows' words (list_words_room in its
/// card's list_pad), 10 over and under: a row of it as its rows are, as high as one at least (desk_row_least), what it
/// holds in its middle, its corner the card's less the ladder's step (what stands in it, a switch at its end, is in
/// its corners, not the card's).
fn wide_in_list() -> @ui.Style {
  // (in a panel's card no ground of its own: what stands at its end in the card's corners stands outside them)
  (if in_pane() { wide_in_list_bare } else { wide_in_list_ground }).then(@ui.style(min_h=Fixed(desk_row_least())))
}

///|
// kept across runs: a value (no field of it changes)
let wide_in_list_bare : @ui.Style = @ui.css("w=Full py=S2_5 justify=JCenter").then(@ui.style(px=list_words_room))

///|
// kept across runs: a value (no field of it changes)
let wide_in_list_ground : @ui.Style = @ui.css("w=Full py=S2_5 justify=JCenter").then(
  @ui.style(pl=list_words_room, pr=room(list_control_end), radius=InnerOr(Xl2)),
)

///|
/// How far in from its end a row on a list card (not a panel's: wide_in_list_bare) has what it holds at its end (a
/// switch, a choice): its words' room, or as far as holds it out of the card's corner where that is more (a list
/// card's 24 round, its rows 6 in: 18; the user's 第 3 版, 2026-11-03: a control stays out of its card's corner).
pub let list_control_end : Double = dmax(text_in, list_card_corner - list_pad)

///|
/// What stands on the page as a section of its own without a title (a fold's row): wide, as far from what follows as a
/// section is (28); narrow, as it is (its card keeps its own room).
pub fn apart(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=if look() == Narrow { wide_block } else { wide_apart }, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wide_apart : @ui.Style = @ui.css("w=Full mb=S7")

///|
/// A head's first line: its dot, its tags (narrow), what it is, 6 apart.
// kept across runs: a value (no field of it changes)
let head_line_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_line_narrow : @ui.TextStyle = pg_lead

///|
/// Its name pressed to rename it (narrow): a title, faded under the finger (no ground of its own: it stands on the
/// page's).
// kept across runs: a value (no field of it changes)
let head_name_press : @ui.Style = @ui.css("w=Full pressed{opacity=O60}")

///|
/// How tall a row's lead stands at least where lines are under its first (row_lead's): its first line, as drawn.
pub fn row_lead_line(c : @ui.Ctx, at? : Look) -> Double {
  c.sp(match at.unwrap_or(look()) {
    Narrow => c.text_size(Body).1
    Wide => c.theme().leading(L6).unwrap_or(c.text_size(Ui).1)
  })
}

///|
/// How far a page's row's words stand in from its foot (narrow: text_in; wide: a list row's 10): what lies in its foot's
/// corner reaches out by that less the ladder's inset.
pub fn row_words_foot() -> Double {
  match look() {
    Narrow => text_in
    Wide => wide_row_pad
  }
}
