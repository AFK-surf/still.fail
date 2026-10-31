// Picking a passage of a message where it is, in its chat, as both frames do it. With a finger (ember apps/android
// chat/screens/MessagePick.kt, ui/Pick.kt; web mobile/pick.tsx): held still on its words it picks the word under it
// and, sliding on, widens it by words (the list holds still meanwhile); lifted, the passage has handles at its ends to
// move, and a bar over it to quote it into the chat's draft, copy it, or take all of the message; a tap anywhere else
// lets go of it, as going back does. With a mouse on the desktop (web Chat.tsx useSelectionQuote, Chat.css.ts
// quotePop): the page's selection (Ctx::selectable), and once it is let go a small dark pill over what is picked, 引用,
// quoting it. How a finger picks is mbui's (@kit.Pick, over @ui.Ctx::words: a message's paragraphs as one text, where
// each is, the passage drawn behind them); what is here is the chat's: which message, its handles', its bar's and its
// pill's look. Where the words go is the frame's (`quote`). A message of a chat's list offers its turn shared as a
// picture too (`share`): on the finger's bar, and in the menu a right click on it opens (share_offered).

///|
/// What is picked in the chat: one passage of one message at a time (mbui's @kit.Pick), the message it is of, who
/// said it and as what (agent | person), what shares its turn (None: it is not a chat's list's), the link to it ("":
/// none); the press something else in the message took (a link's menu, an image quoted: its frame), which picks nothing.
pub(all) struct ChatPick {
  /// the message picked from ("" none)
  mut ts : String
  mut author : String
  mut role : String
  mut share : (() -> Unit)?
  mut link : String
  sel : @kit.Pick
  mut taken_at : Int
}

///|
pub let pk : ChatPick = { ts: "", author: "", role: "", share: None, link: "", sel: @kit.Pick::new(), taken_at: -1 }

///|
/// What is picked as told (picked): one passage at a time, by an identity of its own (`serial`: a number each passage
/// picked takes, never one given again; 0 none), the message it is of and where it ran as it was picked (from, to:
/// a finger's, in its words; -1 a mouse's, the page's selection holding it).
pub(all) struct Picked {
  serial : Int
  ts : String
  a : Int
  b : Int
} derive(Eq, Show, Debug)

///|
/// Nothing picked.
pub let picked_none : Picked = { serial: 0, ts: "", a: -1, b: -1 }

///|
/// What is picked, told once as a passage is picked (a new identity, what is known of it then said with it, once) and
/// once as it is let go: what follows picking reads it, never `pk` frame by frame. Where it is made is still a build's
/// (a finger's hold made into words, a mouse's selection read, as the old view builds: kit's Pick, Ctx::selection_box),
/// so it is told as that build makes it.
// kept across runs: nothing picked as a run begins (pick_reset); its identities only count on
pub let picked : @signals.Signal[Picked] = @signals.signal(picked_none, same=fn(a, b) { a == b })

///|
/// The identity the last passage picked took (picked's `serial`).
// kept across runs: only counts on (an identity a run before gave never given again)
let pick_serial : Ref[Int] = Ref(0)

///|
/// The mouse's selection last told picked (Ctx::selection_made's number; -1 none).
// kept across runs: none as a run begins (pick_reset)
let pick_mouse_made : Ref[Int] = Ref(-1)

///|
/// A passage of message `ts` picked anew (its metadata in `pk` already), told once: its identity, where it runs.
fn pick_told_new(ts : String, a : Int, b : Int) -> Unit {
  pick_serial.val = pick_serial.val + 1
  picked.set({ serial: pick_serial.val, ts, a, b })
}

///|
/// What was picked let go: told once (nothing told where nothing was picked).
fn pick_told_gone() -> Unit {
  picked.set(picked_none)
}

///|
/// A message right clicked with a mouse, and what shares its turn: the frame, where, the share and its link ("" none),
/// for the window's right click menu to offer as 复制消息链接 and 分享这一轮 with what else it has there (sfdesk's
/// context_menu.mbt). None once taken.
pub let share_offered : Ref[(Int, Double, Double, () -> Unit, String)?] = Ref(None)

///|
/// Told as a message offers its turn (share_offered): what shows the menu, built apart from the message (another old
/// view's), follows it.
// kept across runs: a count told, nothing reads what it is (only that it changed)
pub let share_offered_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// The turn of a message right clicked offered (share_offered), told.
fn share_offer(at : Int, x : Double, y : Double, go : () -> Unit, link : String) -> Unit {
  share_offered.val = Some((at, x, y, go, link))
  share_offered_told.set(@signals.untracked(fn() { share_offered_told.get() }) + 1)
}

///|
/// What a message offers of itself (its link, its turn's picture), at the end of its author's name and time, where a
/// mouse is the native input: one ⋯ shown while the pointer rests on the message (or its menu shows), the same two a
/// right click offers, each in its words: two bare marks there said neither what they did nor that they were the
/// message's (a picture's mark reads as a picture's, not as sharing). A finger has no resting pointer: where it is the
/// native input both are on the bar of what it holds picked instead (pick_layer), not on every message's head.
pub fn share_turn_tool(c : @ui.Ctx, key : String, row : Int, link : String, go : () -> Unit) -> Unit {
  match c.menu_asked(row) {
    Some((x, y)) => share_offer(c.frame_number(), x, y, go, link)
    None => ()
  }
  let menu = key + "/message-menu"
  c.box(style=share_turn_room, fn() {
    c.hand_shown(c.hovered(row) || @sf.menu_shown(menu), fn() {
      @sf.menu_of(c, menu, message_items(link, go), label=@sf.t("web-main.menu.more"), size=24.0) |> ignore
    })
  })
  |> ignore
}

///|
/// A message's own items (its ⋯, its right click's): 复制消息链接 (where it has one), 分享这一轮.
fn message_items(link : String, go : () -> Unit) -> Array[@sf.MenuItem?] {
  let items : Array[@sf.MenuItem?] = []
  if link != "" {
    items.push(
      Some(
        @sf.menu_item_of(@sf.t("web-main.chat.copyMessageLink"), icon="link", fn() {
          let c = @ui.current()
          c.copy_text(link)
          say(c, @sf.t("common.link.copied"))
        }),
      ),
    )
  }
  items.push(
    Some(
      @sf.menu_item_of(@sf.t("web-main.chat.shareTurn"), icon="photo", fn() {
        pick_clear()
        go()
      }),
    ),
  )
  items
}

///|
// kept across runs: a value (no field of it changes)
let share_turn_room : @ui.Style = @ui.css("w=S6 h=S6")

///|
/// Let go of what is picked.
pub fn pick_clear() -> Unit {
  pk.ts = ""
  pk.sel.clear()
  pick_told_gone()
}

///|
/// A passage picked here as the app is opened so (a fixture's): told as one picked by a hand is.
pub fn pick_told_given() -> Unit {
  if pk.ts != "" {
    pick_told_new(pk.ts, pk.sel.a, pk.sel.b)
  }
}

///|
/// As at the start (tests): nothing picked, no press remembered.
pub fn pick_reset() -> Unit {
  pick_clear()
  pk.author = ""
  pk.role = ""
  pk.share = None
  pk.link = ""
  share_offered.val = None
  pk.taken_at = -1
  pk.sel.reset()
  picked.set(picked_none)
  pick_mouse_made.val = -1
  // (the press last felt, by its frame: a Tester's frames count from 0 again, and a press another test's pick was felt
  // at took this one's feel, run after composer_wbtest or motion_wbtest, 2026-10-24)
  pick_felt.val = -1
}

///|
/// Whether words are picked as a desktop's (a mouse's selection over the page, its pill) rather than as a phone's
/// (held, the handles, the bar): by the hand alone, in any layout (@ui.pointing).
pub fn mouse_picks() -> Bool {
  @sf.pointer_rests()
}

///|
/// A message's words to be picked from (MessagePick.kt messagePick), round what draws them (`body`): its ts, who said
/// it and as what, its words; `fill`, as wide as its column (else as its words: the viewer's bubble). With a mouse
/// (`mouse`), what of it the page's selection holds is told the pill, and a right click on it offers its turn shared
/// (`share`, where it is given: share_offered); held with a finger, its bar shares its turn and copies `link` too
/// (where they are given). `marks` drawn behind its words first (a search's strokes), its words
/// kept as laid out then too (`keep`); `lit`, a passage of them on its own ground (a quote's that led here: from, to,
/// the ground), its two ends round, while none is picked in it.
pub fn pickable(
  c : @ui.Ctx,
  ts : String,
  author : String,
  role : String,
  words : String,
  fill : Bool,
  mouse : Bool,
  body : () -> Unit,
  keep? : Bool = false,
  marks? : (Int) -> Unit = fn(_) {  },
  share? : (() -> Unit)? = None,
  link? : String = "",
  lit? : (Int, Int, Int64)? = None,
) -> Unit {
  let key = "pick/" + ts
  let id = c.id(key)
  // a tap on it: the keyboard goes (not a long press: Keyboard.kt letsGoOfKeyboard); a ground, its words the I-beam's
  c.cursor(id, Arrow)
  let press = c.press()
  if c.clicked(id) && !press.long {
    c.blur()
  }
  let pressed_in = press.down && c.press_within(id)
  // built first: a link held in it is the link's menu (its hold told while building), not a pick
  let box = c.box(style=if fill { pick_fill } else { pick_own }, id~, fn() {
    marks(id)
    body()
  })
  // its words kept as laid out while a press is in it or a passage of it is picked (what the hold and the handles
  // ask), or what is marked in it asks
  if pk.ts == ts {
    c.words(box, key, a=pk.sel.a, b=pk.sel.b, color=@sf.alpha(@sf.theme().p.accent, picked_alpha))
  } else if lit is Some((a, b, color)) {
    // (round at the passage's two ends, square where it runs on to the next line)
    c.words(box, key, a~, b~, color~, round=c.theme().corner(Md))
  } else if pressed_in || keep {
    c.words(box, key)
  }
  // a mouse picks words as a browser's selection (Ctx::selectable): what of this message it holds is told the pill,
  // whose message it is with it; no long press then
  if mouse {
    match c.selection_box() {
      Some((sx, sy, sw, sh)) =>
        match c.rect_of(id) {
          Some((x, y, w, h)) if sx >= x - 1.0 && sy >= y - 1.0 && sx + sw <= x + w + 1.0 && sy + sh <= y + h + 1.0 => {
            // (a selection the mouse began anew (Ctx::selection_made: its press's number), or none of this message's
            // before: picked anew)
            let anew = pk.ts != ts || c.selection_made() != pick_mouse_made.val
            pick_mouse_made.val = c.selection_made()
            pk.ts = ts
            pk.author = author
            pk.role = role
            pk.share = share
            pk.link = link
            // (told once; built again, the same)
            if anew {
              pick_told_new(ts, -1, -1)
            }
          }
          _ => ()
        }
      None => ()
    }
    // right clicked: its turn offered the window's right click menu (sfdesk's context_menu.mbt); not where something
    // in it has a menu of its own (a file's: the innermost asker's, Ctx::menu_asked)
    match share {
      Some(go) =>
        match c.menu_asked(id) {
          Some((x, y)) => share_offer(c.frame_number(), x, y, go, link)
          None => ()
        }
      None => ()
    }
    return
  }
  let mine = pk.ts == ts
  // held still on it a long press's time (the library's: where the press went down, as drawn), the word under the finger
  // picked; not while a handle or the passage it widens is held
  let may = pk.sel.handle == 0 &&
    !(mine && pk.sel.widening) &&
    pk.taken_at != press.frame &&
    words.trim(chars=" \n\t") != ""
  if pk.sel.hold(c, key, id, may~) {
    pk.ts = ts
    pk.author = author
    pk.role = role
    pk.share = share
    pk.link = link
    // (picked anew, its metadata said first: told once)
    pick_told_new(ts, pk.sel.a, pk.sel.b)
    // the press is the pick's: the list holds still, lifting it taps nothing
    c.take_press()
    let at = press.frame
    c.tell("haptic/hold/pick", fn() {
      if pick_felt.val != at {
        pick_felt.val = at
        @ui.haptic(LongPress)
      }
    })
  }
  // sliding on: widened by words from the word first held
  if pk.ts == ts {
    pk.sel.slide(c)
  }
}

///|
/// How much of the accent a picked passage's ground is.
pub let picked_alpha : Double = 0.26

///|
/// The press a pick was last felt for.
let pick_felt : Ref[Int] = Ref(-1)

///|
/// Over list `list` (MessagePick.kt PickLayer): the picked passage's handles and its bar (over it; under it when the
/// bar over the list is too near: `top`, where the list's bar ends; `foot`, what is kept clear at its foot), the bar
/// gone while the list moves or the passage is being changed; with a mouse (`mouse`), the pill. A tap anywhere else
/// lets go of it, as back does. Quoted: `quote` told whose words, the words, their message and its role. After what
/// the bar does with the passage, a line and what it does with the message, each a mark alone (named, as a reader
/// says it): share its turn as a picture (its `share`), copy the link to it (its `link`), where it has them.
pub fn pick_layer(
  c : @ui.Ctx,
  list : String,
  top : Double,
  foot : Double,
  mouse : Bool,
  quote : (String, String, String, String) -> Unit,
) -> Unit {
  if mouse {
    pick_pop(c, quote)
    return
  }
  if pk.ts == "" {
    return
  }
  let words = match c.words_of(pk.sel.key) {
    Some(w) => w
    // not laid out in this build: once the frame's builds are over (read back as it is laid out, words.mbt), still
    // none: scrolled far off, gone, and what was picked in it goes too
    None => {
      let key = pk.sel.key
      c.after_build("pick-gone", fn() { if c.words_of(key) is None && pk.sel.key == key { pick_clear() } })
      return
    }
  }
  let lines = words.rects(pk.sel.a, pk.sel.b)
  if lines.length() == 0 {
    return
  }
  let t = @sf.theme()
  let bar = c.id("pick/bar")
  let quote_id = c.id("pick/quote")
  let copy = c.id("pick/copy")
  let all = c.id("pick/all")
  let share = c.id("pick/share")
  let link = c.id("pick/link")
  let ends = [c.id("pick/start"), c.id("pick/end")]
  // the bar's buttons
  if c.clicked(quote_id) {
    let text = words.slice(pk.sel.a, pk.sel.b).trim(chars=" \n\t").to_string()
    if text != "" {
      quote(pk.author, text, pk.ts, pk.role)
    }
    pick_clear()
    return
  }
  if c.clicked(copy) {
    c.copy_text(words.slice(pk.sel.a, pk.sel.b))
    say(c, @sf.t("android-chat.annotate.copied"))
    pick_clear()
    return
  }
  if c.clicked(all) {
    pk.sel.all(words)
  }
  match pk.share {
    Some(go) if c.clicked(share) => {
      pick_clear()
      go()
      return
    }
    _ => ()
  }
  if pk.link != "" && c.clicked(link) {
    c.copy_text(pk.link)
    say(c, @sf.t("common.link.copied"))
    pick_clear()
    return
  }
  let first = lines[0]
  let last = lines[lines.length() - 1]
  // (where the layers they are in start in the window, as this frame lays them out: the passage's lines are said in
  // the window's, and a pane beside the sidebar starts away from its corner)
  let frame = c.id("pick/frame")
  let (fx, fy, fw, fh) = match c.laid_rect(frame) {
    Some(r) => r
    None => (0.0, 0.0, c.width, c.height)
  }
  c.layer(fn() { c.box(style=pick_pop_frame, id=frame, fn() {  }) |> ignore }) |> ignore
  // a handle taken and moved (its end following the finger from where it was taken); a tap anywhere but on the pick's
  // bar and handles lets go of it (not the lifting of the press that picked it: that press was taken)
  pk.sel.handles(c, words, ends)
  if pk.sel.tapped_away(c, [bar, ends[0], ends[1]]) {
    pick_clear()
    return
  }
  // the two ends, each a handle: a line down its side with a knob (over the start's line, under the end's), the
  // finger's room 36 wide round them
  for k, id in ends {
    let line = if k == 0 { first } else { last }
    let x = if k == 0 { line.0 } else { line.0 + line.2 }
    let top = if k == 0 { line.1 - 28.0 } else { line.1 }
    let h = line.3 + 28.0
    let line_top = if k == 0 { h - line.3 } else { 0.0 }
    let knob_y = if k == 0 { line_top - 11.0 } else { line_top + line.3 - 1.0 }
    c.layer(fn() {
      c.box(style=pick_handle.then(@ui.style(h=Fixed(h))), tx=x - fx - handle_half, ty=top - fy, id~, fn() {
        c.layer(fn() {
          let lh = line.3
          c.box(style=pick_line.then(@ui.style(h=Fixed(lh))), tx=handle_half - 1.0, ty=line_top, fn() {  })
          |> ignore
        })
        |> ignore
        c.layer(fn() { c.box(style=pick_knob, tx=handle_half - 6.0, ty=knob_y, fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
    @ui.capture(c, id)
  }
  if pk.sel.widening || pk.sel.handle != 0 || c.list_moving(list) {
    return
  }
  // over the passage; under it (clear of the end's knob) when the bar over the list is too near; on the screen when
  // the passage runs past it
  let least = fy + top + 8.0
  let over = first.1 - 52.0
  let y = if over < least { last.1 + last.3 + 28.0 } else { over }
  let y = dmax(least, dmin(y, dmax(fy + fh - foot - 48.0, least)))
  let x = if lines.length() > 1 { fx + fw / 2.0 } else { first.0 + first.2 / 2.0 }
  // (kept on the screen, 8 in from its sides: as wide as it was laid out last)
  let half = match c.laid_rect(bar) {
    Some((_, _, w, _)) => w / 2.0 + 8.0
    None => 130.0
  }
  let x = dmax(fx + half, dmin(x, dmax(fx + fw - half, fx + half)))
  let everything = pk.sel.a == 0 && pk.sel.b >= words.text.length()
  let button = fn(id : Int, label : String, icon : String) {
    c.box(style=pick_button, id~, fn() {
      if icon != "" {
        @sf.icon(c, icon, size=pick_icon, color=t.p.text) |> ignore
      }
      c.text(label, style=pick_button_words) |> ignore
      // MessagePick.kt: clip(Smooth(16)).clickable
      @motion.ripple(c, id, pick_button_round)
    })
    |> ignore
  }
  let mark = fn(id : Int, label : String, icon : String) {
    let b = c.box(style=pick_mark_button, id~, fn() {
      @sf.icon(c, icon, size=pick_icon, color=t.p.text) |> ignore
      @motion.ripple(c, id, pick_button_round)
    })
    c.semantics(b, Button, id~, label~)
  }
  c.layer(fn() {
    // (its row `y` down the layer)
    c.box(style=@ui.style(h=Fixed(y - fy)), fn() {  }) |> ignore
    c.box(style=pick_bar_row, fn() {
      c.box(tx=x - fx - fw / 2.0, fn() {
        let b = c.box(
          style=pick_bar,
          id=bar,
          fn() {
            button(quote_id, @sf.t("android-chat.pick.quote"), "quote")
            button(copy, @sf.t("common.copy"), "copy")
            if !everything {
              button(all, @sf.t("android-chat.annotate.selectAll"), "")
            }
            if pk.share is Some(_) || pk.link != "" {
              c.box(style=pick_bar_rule, fn() {  }) |> ignore
            }
            if pk.share is Some(_) {
              mark(share, @sf.t("web-main.chat.shareTurn"), "photo")
            }
            if pk.link != "" {
              mark(link, @sf.t("common.link.copy"), "link")
            }
          },
        )
        // coming as a small panel does (@kit.pop_in), each passage picked anew; a handle moved, or the list let go of,
        // it is where it is
        match @motion.presence(c, "pick/bar/\{pk.ts}/\{pk.taken_at}", true, enter=@kit.pop_in, initial=true) {
          Some(l) => c.look(b, l)
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What the mouse picked in a message (Chat.tsx useSelectionQuote, Chat.css.ts quotePop): once it is let go, a small
/// dark pill 8 over where the pointer let it go (Ctx::selection_end: the end it dragged, on its line), 引用 with its
/// mark, quoting it (whose words they are, as the message says: pickable). ⌘C copies it (Ctx::selectable); a press
/// elsewhere lets it go.
fn pick_pop(c : @ui.Ctx, quote : (String, String, String, String) -> Unit) -> Unit {
  let (x, y) = match c.selection_end() {
    Some((ex, ey, _)) if pk.ts != "" => (ex, ey - 8.0 - pick_pop_h)
    _ => {
      if pk.ts != "" {
        pk.ts = ""
        pick_told_gone()
      }
      return
    }
  }
  let pop = c.id("pick/pop")
  if c.clicked(pop) {
    let text = c.selected_text().trim(chars=" \n\t").to_string()
    if text != "" {
      quote(pk.author, text, pk.ts, pk.role)
    }
    c.selection_clear()
    pk.ts = ""
    pick_told_gone()
    return
  }
  // (pressed, what is picked stays picked: it is what is quoted)
  c.keeps_selection(pop)
  // (where the layer it is in starts in the window, as this frame lays it out: what is picked is said in the window's)
  let frame = c.id("pick/pop-frame")
  let (fx, fy, fw) = match c.laid_rect(frame) {
    Some((fx, fy, fw, _)) => (fx, fy, fw)
    None => (0.0, 0.0, c.width)
  }
  // (its middle there, the whole of it in the layer: let go at the end of a line by its edge, it stands in from it)
  let half = match c.laid_rect(pop) {
    Some((_, _, w, _)) => w / 2.0
    None => 0.0
  }
  let pop_x = dmax(half, dmin(x - fx, fw - half))
  c.layer(fn() {
    c.box(style=pick_pop_frame, id=frame, fn() {
      c.box(style=pick_pop_row, ty=dmax(0.0, y - fy), fn() {
        c.box(tx=pop_x - fw / 2.0, fn() {
          let hot = c.lit(pop)
          c.box(style=if hot { pick_pop_hot } else { pick_pop_box }, id=pop, fn() {
            @sf.icon(c, "quote", size=12.0, color=@sf.theme().p.on_primary) |> ignore
            c.text(@sf.t("web-main.chat.quote"), style=pick_pop_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A handle (the finger's room 36 wide round an end), its line (2, the accent) and its knob (12 round, the accent).
// kept across runs: a value (no field of it changes)
let pick_handle : @ui.Style = @ui.css("w=S9")

///|
let handle_half : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let pick_line : @ui.Style = @ui.css("w=S0_5 bg=Accent")

///|
// kept across runs: a value (no field of it changes)
let pick_knob : @ui.Style = @ui.css("w=S3 h=S3 radius=Full bg=Accent")

///|
/// The bar (MessagePick.kt PickBar): in the middle of its row, 40 high, 4 in, round, raised on its line and shadow;
/// its buttons 32 high, 12 in, their mark 5 before their words (14, the ink).
// kept across runs: a value (no field of it changes)
let pick_bar_row : @ui.Style = @ui.css("row w=Full justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pick_bar : @ui.Style = @ui.style(
  row=true,
  h=S10,
  px=S1,
  radius=Full,
  bg=Raised,
  border=B1,
  border_color=Line,
  shadow=@sf.pick_raised.cast(),
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let pick_button : @ui.Style = @ui.css("row h=S8 px=S3 gap=S1_25 radius=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pick_button_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// What the bar does with the message, a mark alone 32 round, after a line 16 high 4 off what does with the passage.
// kept across runs: a value (no field of it changes)
let pick_mark_button : @ui.Style = @ui.css("h=S8 w=S8 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pick_bar_rule : @ui.Style = @ui.css("w=SPx h=S4 mx=S1 bg=Line")

///|
let pick_icon : Double = 15.0

///|
let pick_button_round : Double = 16.0

///|
/// A message's words to be picked: as wide as their column, or as what they say (the viewer's bubble).
// kept across runs: a value (no field of it changes)
let pick_fill : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let pick_own : @ui.Style = @ui.css("w=Hug")

///|
/// What the pill, and a finger's handles and bar, are placed by: all of the layer (where it starts in the window).
// kept across runs: a value (no field of it changes)
let pick_pop_frame : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The pill's height (quotePop: 26).
let pick_pop_h : Double = 26.0

///|
// kept across runs: a value (no field of it changes)
let pick_pop_row : @ui.Style = @ui.css("row w=Full justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pick_pop_box : @ui.Style = @ui.style(
  row=true,
  h=@sf.quote_pop_h,
  px=S2_5,
  gap=S1,
  radius=Full,
  bg=Primary,
  shadow=Md,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
/// Pointed at: a step towards the page, as every solid ground (docs/ui-panels.md 悬停).
// kept across runs: a value (no field of it changes)
let pick_pop_hot : @ui.Style = pick_pop_box.then(@ui.css("bg=Over(Primary, A(Bg, O15))"))

///|
// kept across runs: a value (no field of it changes)
let pick_pop_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Medium, color=OnPrimary, wrap=false)

///|
/// How long the pick's bar takes to come (@kit.pop_in's).
pub let pick_bar_in_ms : Double = @kit.pop_ms
