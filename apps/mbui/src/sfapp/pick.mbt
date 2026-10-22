// Picking a passage of a message where it is, in its chat (ember apps/android chat/screens/MessagePick.kt, ui/Pick.kt;
// web mobile/pick.tsx): a finger held still on its words picks the word under it and, sliding on, widens it by words
// (the list holds still meanwhile); lifted, the passage has handles at its ends to move, and a bar over it to quote it
// into the chat's draft, copy it, or take all of the message. A tap anywhere else lets go of it, as going back does.
// The words are mbui's (@ui.Ctx::words: a message's paragraphs as one text, where each is, the passage drawn behind
// them; @ui.word_at: the system's word boundaries).

///|
/// What is picked in the chat: one passage of one message at a time.
priv struct Pick {
  /// the message picked from ("" none), its words' key, who said it and as what (agent | person)
  mut ts : String
  mut key : String
  mut author : String
  mut role : String
  /// the passage, in the words' text
  mut a : Int
  mut b : Int
  /// the word first held, which a finger sliding on widens from
  mut from_a : Int
  mut from_b : Int
  /// a finger widening it (held, sliding on)
  mut widening : Bool
  /// a handle a finger moves: 1 the start's, 2 the end's, 0 none; the finger's place off the end's middle
  mut handle : Int
  mut grab_x : Double
  mut grab_y : Double
  /// the press that picked it (its lifting is not a tap that lets go)
  mut picked_frame : Int
}

///|
let pk : Pick = {
  ts: "",
  key: "",
  author: "",
  role: "",
  a: 0,
  b: 0,
  from_a: 0,
  from_b: 0,
  widening: false,
  handle: 0,
  grab_x: 0.0,
  grab_y: 0.0,
  picked_frame: -1,
}

///|
/// Let go of what is picked.
fn pick_clear() -> Unit {
  pk.ts = ""
  pk.key = ""
  pk.widening = false
  pk.handle = 0
}

///|
/// As at the start (tests): nothing picked, no press remembered.
fn pick_reset() -> Unit {
  pick_clear()
  pk.author = ""
  pk.role = ""
  pk.a = 0
  pk.b = 0
  pk.from_a = 0
  pk.from_b = 0
  pk.grab_x = 0.0
  pk.grab_y = 0.0
  pk.picked_frame = -1
  link_menu.href = ""
  link_menu.items = []
  link_menu.pick = fn(_, _) {  }
  link_menu.x = 0.0
  link_menu.top = 0.0
  link_menu.bottom = 0.0
  link_menu.at = -1
  link_menu.open = false
}

///|
/// Back lets go of what is picked, and closes a link's menu, before it goes back a page (MessagePick.kt's
/// BackHandler): after the stack is drawn, as what lies over the pages.
fn pick_back(c : @ui.Ctx) -> Unit {
  if link_menu.open {
    c.take_back(fn() { link_menu.open = false })
  } else if pk.ts != "" {
    c.take_back(fn() { pick_clear() })
  }
}

///|
/// How long a finger is held still for a long press (ViewConfiguration's long press timeout, as Compose has it).
let long_press_ms : Double = @ui.long_press_ms

///|
/// A message's words that a finger held still on picks from (MessagePick.kt messagePick): the word under the finger,
/// widened by words as it slides on; the passage drawn behind the words (the accent at 26%).
fn pickable(
  c : @ui.Ctx,
  ts : String,
  author : String,
  role : String,
  words : String,
  fill_w : Bool,
  body : () -> Unit,
) -> Unit {
  let key = "pick/" + ts
  let id = c.id(key)
  // a tap on it: the keyboard goes (not a long press: Keyboard.kt letsGoOfKeyboard)
  if c.clicked(id) && !cui.long {
    c.blur()
  }
  let (px, py, down) = c.pointer()
  let pressed_in = match c.rect_of(id) {
    Some((x, y, w, h)) => cui.down_x >= x && cui.down_x < x + w && cui.down_y >= y && cui.down_y < y + h
    None => false
  }
  // a search's words in it (search_marks.mbt): their strokes behind its words
  let found = found_words_of(ts)
  let at = if found.is_empty() {
    (0.0, 0.0)
  } else {
    match c.laid_rect(id) {
      Some((x, y, _, _)) => (x, y)
      None => (0.0, 0.0)
    }
  }
  // built first: a link held in it is the link's menu (its hold told while building), not a pick
  let box = c.box(w=if fill_w { Fill(1.0) } else { Auto }, id~, fn() {
    if !found.is_empty() {
      found_strokes(c, key, found, found_marking.val.2, at.0, at.1)
    }
    body()
  })
  // its words kept as laid out while a press is in it or a passage of it is picked (what the hold and the handles
  // ask), or a search's words are marked in it
  if pk.ts == ts {
    c.words(box, key, a=pk.a, b=pk.b, color=@sf.alpha(@sf.theme().p.accent, 0.26))
  } else if (down && pressed_in) || !found.is_empty() {
    c.words(box, key)
  }
  let mine = pk.ts == ts
  // the press went down in it and holds still: a long press's time on, the word under the finger picked
  let holding = down &&
    pressed_in &&
    !cui.moved &&
    pk.handle == 0 &&
    !(mine && pk.widening) &&
    pk.picked_frame != cui.down_frame &&
    link_menu.at != cui.down_frame &&
    words.trim(chars=" \n\t") != ""
  // (asked each frame, so that a press let go starts again from nothing; a frame asked for when it will have)
  let held = @kit.after(c, key + "/hold", holding, long_press_ms)
  if held {
    match c.words_of(key) {
      Some(w) if w.text != "" => {
        let (s, e) = w.word_at(w.offset_at(cui.down_x, cui.down_y))
        pk.ts = ts
        pk.key = key
        pk.author = author
        pk.role = role
        pk.a = s
        pk.b = e
        pk.from_a = s
        pk.from_b = e
        pk.widening = true
        pk.handle = 0
        pk.picked_frame = cui.down_frame
        // the press is the pick's: the list holds still, lifting it taps nothing
        c.take_press()
      }
      _ => ()
    }
  }
  // sliding on: widened by words from the word first held
  if pk.ts == ts && pk.widening {
    if !down {
      // lifted: the bar comes back (the lifting's input frame and the one after it draw it: the bar was built before
      // the rows)
      pk.widening = false
    } else {
      match c.words_of(key) {
        Some(w) => {
          let (s, e) = w.word_at(w.offset_at(px, py))
          if s >= pk.from_a {
            pk.a = pk.from_a
            pk.b = if e > pk.from_b { e } else { pk.from_b }
          } else {
            pk.a = s
            pk.b = pk.from_b
          }
        }
        None => ()
      }
    }
  }

}

///|
/// Over the list (MessagePick.kt PickLayer): the picked passage's handles and its bar (over it; under it when the bar
/// over the list is too near), the bar gone while the list moves or the passage is being changed. A tap anywhere else
/// lets go of it, as back does.
fn pick_layer(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  if pk.ts == "" {
    return
  }
  let words = match c.words_of(pk.key) {
    Some(w) => w
    // not laid out in this build: once the frame's builds are over (read back as it is laid out, words.mbt), still
    // none: scrolled far off, gone, and what was picked in it goes too
    None => {
      let key = pk.key
      c.after_build("pick-gone", fn() { if c.words_of(key) is None && pk.key == key { pick_clear() } })
      return
    }
  }
  let lines = words.rects(pk.a, pk.b)
  if lines.length() == 0 {
    return
  }
  let t = @sf.theme()
  let (px, py, down) = c.pointer()
  let bar = c.id("pick/bar")
  let quote = c.id("pick/quote")
  let copy = c.id("pick/copy")
  let all = c.id("pick/all")
  let ends = [c.id("pick/start"), c.id("pick/end")]
  let in_rect = fn(id : Int, x : Double, y : Double) {
    match c.rect_of(id) {
      Some((rx, ry, rw, rh)) => x >= rx && x < rx + rw && y >= ry && y < ry + rh
      None => false
    }
  }
  // the bar's buttons
  if c.clicked(quote) {
    let text = words.slice(pk.a, pk.b).trim(chars=" \n\t").to_string()
    if text != "" {
      draft_quote(draft_of(c, src, r), pk.author, text, pk.ts, pk.role)
    }
    pick_clear()
    return
  }
  if c.clicked(copy) {
    c.copy_text(words.slice(pk.a, pk.b))
    say(c, tr("android-chat.annotate.copied"))
    pick_clear()
    return
  }
  if c.clicked(all) {
    pk.a = 0
    pk.b = words.text.length()
  }
  let first = lines[0]
  let last = lines[lines.length() - 1]
  // a handle taken: the finger's place off the end's middle kept, so the end does not jump to under it
  if cui.press_new && pk.handle == 0 {
    for k, id in ends {
      if in_rect(id, cui.down_x, cui.down_y) {
        pk.handle = k + 1
        let (ex, ey) = if k == 0 {
          (first.0, first.1 + first.3 / 2.0)
        } else {
          (last.0 + last.2, last.1 + last.3 / 2.0)
        }
        pk.grab_x = ex - cui.down_x
        pk.grab_y = ey - cui.down_y
      }
    }
  }
  if pk.handle != 0 {
    if !down {
      pk.handle = 0
    } else {
      let at = words.offset_at(px + pk.grab_x, py + pk.grab_y)
      if pk.handle == 1 {
        pk.a = if at < pk.b - 1 { at } else { pk.b - 1 }
      } else {
        pk.b = if at > pk.a + 1 { at } else { pk.a + 1 }
      }
    }
  }
  // a tap anywhere but on the pick's bar and handles lets go of it (not the lifting of the press that picked it: that
  // press was taken)
  match c.tapped_anywhere() {
    Some((tx, ty)) if pk.handle == 0 &&
      !in_rect(bar, tx, ty) &&
      !in_rect(ends[0], tx, ty) &&
      !in_rect(ends[1], tx, ty) => {
      pick_clear()
      return
    }
    _ => ()
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
      c.box(tx=x - 18.0, ty=top, w=Px(36.0), h=Px(h), id~, fn() {
        c.layer(fn() {
          c.box(tx=17.0, ty=line_top, w=Px(2.0), h=Px(line.3), bg=t.p.accent, fn() {  }) |> ignore
        })
        |> ignore
        c.layer(fn() {
          c.box(tx=12.0, ty=knob_y, w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.accent, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    @ui.capture(c, id)
  }
  if pk.widening || pk.handle != 0 || c.list_moving(list_key(r)) {
    return
  }
  // over the passage; under it (clear of the end's knob) when the bar over the list is too near; on the screen when
  // the passage runs past it
  let top = status_top() + chat_bar_h + 8.0
  let over = first.1 - 52.0
  let y = if over < top { last.1 + last.3 + 28.0 } else { over }
  let y = dmax(top, dmin(y, dmax(c.height - composer_room_of(c) - 48.0, top)))
  let x = if lines.length() > 1 { c.width / 2.0 } else { first.0 + first.2 / 2.0 }
  let x = dmax(130.0, dmin(x, dmax(c.width - 130.0, 130.0)))
  let everything = pk.a == 0 && pk.b >= words.text.length()
  let button = fn(id : Int, label : String, icon : String) {
    c.box(
      dir=Row,
      h=Px(32.0),
      padx=12.0,
      gap=5.0,
      radius=16.0,
      align=ACenter,
      bg=@sf.alpha(t.p.text, 0.08 * @motion.pressing(c, id)),
      id~,
      fn() {
        if icon != "" {
          @sf.icon(c, icon, size=15.0, color=t.p.text) |> ignore
        }
        c.text(label, size=14.0, color=t.p.text, wrap=false) |> ignore
      },
    )
    |> ignore
  }
  c.layer(fn() {
    c.box(dir=Row, w=Fill(1.0), pt=y, justify=JCenter, fn() {
      c.box(tx=x - c.width / 2.0, fn() {
        c.box(
          dir=Row,
          h=Px(40.0),
          padx=4.0,
          radius=20.0,
          bg=t.p.raised,
          border=1.0,
          border_color=t.p.line,
          shadow=@sf.pick_raised.sigma,
          shadow_y=@sf.pick_raised.dy,
          shadow_color=@sf.pick_raised.color,
          align=ACenter,
          id=bar,
          fn() {
            button(quote, tr("android-chat.pick.quote"), "quote")
            button(copy, tr("common.copy"), "copy")
            if !everything {
              button(all, tr("android-chat.annotate.selectAll"), "")
            }
          },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
