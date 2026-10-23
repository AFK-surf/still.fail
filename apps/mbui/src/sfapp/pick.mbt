// Picking a passage of a message where it is, in its chat (ember apps/android chat/screens/MessagePick.kt, ui/Pick.kt;
// web mobile/pick.tsx): a finger held still on its words picks the word under it and, sliding on, widens it by words
// (the list holds still meanwhile); lifted, the passage has handles at its ends to move, and a bar over it to quote it
// into the chat's draft, copy it, or take all of the message. A tap anywhere else lets go of it, as going back does.
// How a finger picks is mbui's (@kit.Pick, over @ui.Ctx::words: a message's paragraphs as one text, where each is,
// the passage drawn behind them); what is here is the chat's: which message, its handles' and its bar's look.

///|
/// What is picked in the chat: one passage of one message at a time (mbui's @kit.Pick), the message it is of, who
/// said it and as what (agent | person).
priv struct ChatPick {
  /// the message picked from ("" none)
  mut ts : String
  mut author : String
  mut role : String
  sel : @kit.Pick
}

///|
let pk : ChatPick = { ts: "", author: "", role: "", sel: @kit.Pick::new() }

///|
/// Let go of what is picked.
fn pick_clear() -> Unit {
  pk.ts = ""
  pk.sel.clear()
}

///|
/// As at the start (tests): nothing picked, no press remembered.
fn pick_reset() -> Unit {
  pick_clear()
  pk.author = ""
  pk.role = ""
  pk.sel.reset()
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
  let press = c.press()
  if c.clicked(id) && !press.long {
    c.blur()
  }
  let down = press.down
  let pressed_in = match c.rect_of(id) {
    Some((x, y, w, h)) => press.x >= x && press.x < x + w && press.y >= y && press.y < y + h
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
      found_strokes(c, key, found, found_marking.val.2, at.0, at.1, faint=found_marking.val.0 != ts)
    }
    body()
  })
  // its words kept as laid out while a press is in it or a passage of it is picked (what the hold and the handles
  // ask), or a search's words are marked in it
  if pk.ts == ts {
    c.words(box, key, a=pk.sel.a, b=pk.sel.b, color=@sf.alpha(@sf.theme().p.accent, 0.26))
  } else if (down && pressed_in) || !found.is_empty() {
    c.words(box, key)
  }
  let mine = pk.ts == ts
  // the press went down in it and holds still: a long press's time on, the word under the finger picked
  let holding = down &&
    pressed_in &&
    !press.moved &&
    pk.sel.handle == 0 &&
    !(mine && pk.sel.widening) &&
    link_menu.at != press.frame &&
    image_quoted_at.val != press.frame &&
    words.trim(chars=" \n\t") != ""
  if pk.sel.hold(c, key, holding) {
    pk.ts = ts
    pk.author = author
    pk.role = role
    // the press is the pick's: the list holds still, lifting it taps nothing
    c.take_press()
    feel_hold(c, "pick")
  }
  // sliding on: widened by words from the word first held
  if pk.ts == ts {
    pk.sel.slide(c)
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
  let quote = c.id("pick/quote")
  let copy = c.id("pick/copy")
  let all = c.id("pick/all")
  let ends = [c.id("pick/start"), c.id("pick/end")]
  // the bar's buttons
  if c.clicked(quote) {
    let text = words.slice(pk.sel.a, pk.sel.b).trim(chars=" \n\t").to_string()
    if text != "" {
      draft_quote(draft_of(c, src, r), pk.author, text, pk.ts, pk.role)
    }
    pick_clear()
    return
  }
  if c.clicked(copy) {
    c.copy_text(words.slice(pk.sel.a, pk.sel.b))
    say(c, tr("android-chat.annotate.copied"))
    pick_clear()
    return
  }
  if c.clicked(all) {
    pk.sel.all(words)
  }
  let first = lines[0]
  let last = lines[lines.length() - 1]
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
  if pk.sel.widening || pk.sel.handle != 0 || c.list_moving(list_key(r)) {
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
  let everything = pk.sel.a == 0 && pk.sel.b >= words.text.length()
  let button = fn(id : Int, label : String, icon : String) {
    c.box(
      dir=Row,
      h=Px(32.0),
      padx=12.0,
      gap=5.0,
      radius=16.0,
      align=ACenter,
      id~,
      fn() {
        if icon != "" {
          @sf.icon(c, icon, size=15.0, color=t.p.text) |> ignore
        }
        c.text(label, size=14.0, color=t.p.text, wrap=false) |> ignore
        // MessagePick.kt: clip(Smooth(16)).clickable
        @motion.ripple(c, id, 16.0)
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
