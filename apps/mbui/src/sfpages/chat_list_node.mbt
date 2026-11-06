// A chat's messages (chat_list.mbt's chat_list) made once in the window's tree: its rows by their keys in a page's list
// that holds those in sight alone (View::scrolls_window), from its end (at its foot while they are fewer than fill it,
// shown at its end, kept there as what comes comes while it is there); its column 760 wide at most in the pane's middle,
// 16 in where it is narrow; the rows the gap apart, one sent soon after the one before 4 under it; its room over the
// first row (the bar's) and under the last (the composer's) as they change. Each row's contents are retained nodes
// for its kind of message, activity, card or list marker.

///|
/// Chat `r`'s list in `v`: `view` as the core says it now (none while it is read the first time), its rows read by
/// index (sfbase ChatRows: a message come is that row's change alone),
/// `top` the room over its first row, `core` the settings' over its workspace; what covers its foot (the composer's
/// room, its own lift over that added there: ChatListNode's `lift`) given it by what holds it as that measures it
/// (Layout::measure's `foot`: its page's layout, the composer measured first, none under its window), its last row
/// (Foot) that tall;
/// `composer_across` the width the page gives its composer in a list as wide as given, so the floating actions align
/// with it; `follows` said whether it is kept at its end, as that changes.
pub fn chat_list_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  top : () -> Double,
  core : Core,
  foot_gap? : Double = 0.0,
  composer_across? : (Double) -> Double = composer_width,
  follows? : @signals.Signal[Bool] = @signals.signal(true, same=fn(a, b) { a == b }),
) -> ChatListNode {
  let rk = r.station + "\u{1}" + r.session
  let scroll = @view.Scroll::list()
  // The last row stands above the decision bell when the core says that it can cover the list's end (the old
  // list's ask_clear): that much more room under it than the composer's, given it with that (`lift`). The bell itself
  // stays over the composer's room, even while its post is elsewhere in the list.
  let lift = fn() { if view().map_or(false, @sfbase.ask_clears) { float_lift + float_side } else { 0.0 } }
  // The list reports the rows it actually drew after paint. Keep that observation outside the tree: it must never
  // become an input to another layout. Non-layout changes can still report the last drawn place.
  let last_sighted : Ref[@view.Sighted[String]?] = Ref(None)
  // (a card's field with the focus kept in view with the keyboard up: out from under the bar and the composer, 16 clear
  // of each, its foot giving way to its top where it does not fit between them, in the layout they or the window change
  // in (View::scrolls_anchored's `keep`); with touch (the old list's list_holds_field))
  let keep_field = fn() {
    guard !@sf.pointer_rests() &&
      @ui.current().keyboard_up() &&
      @ui.focused_field_in() is Some((island, (_, fy, _, fh))) &&
      v.tree.holds(v.id(), island) else {
      return None
    }
    Some((island, Some((fy, fy + fh)), field_held_room))
  }
  // Navigation is an input: returning to this retained page resumes its reply
  // deadlines even when no picture or layout has followed the return yet.
  let shown_by = fn() { @ui.page_shown(v) }
  @sfbase.reading_of(rk).shown_by = Some(shown_by)
  // (its reading not made again as it goes: let go with its page, the old list's way)
  v.owns(fn() {
    match @sfbase.readings.get(rk) {
      Some(rd) if rd.shown_by is Some(f) && physical_equal(f, shown_by) => rd.shown_by = None
      _ => ()
    }
  })
  |> ignore
  // (its pictures that could not be had for want of its station asked again as the chat comes into view: made; and
  // as its station is reached again, as the chat says it is)
  src.images.again(r.station)
  v.reacts(fn() { view().map(fn(cv) { cv.offline }) }, fn(off) {
    match off {
      Some(o) => src.images.seen(r.station, !o)
      None => ()
    }
  })
  // (an agent's message waiting its turn to come out of its avatar not in it yet: emit.mbt's emit_held)
  let em = @sfbase.emits_of(rk)
  let rd0 = @sfbase.reading_of(rk)
  let advance = @sfbase.chat_timeline(v, rk, rd0, view, shown_by)
  // (a row's key: the core's, else the key it was sent as from here; Reading's sent and sent_as, row_keys's)
  let id_of = fn(e : Entry) -> String {
    let k = match e {
      Said(m) => @sfbase.said_key(rd0, m)
      _ => e.id()
    }
    rd0.sent_as.get(k).unwrap_or(k)
  }
  // (the row of the message `seq` whose ts is `ts`: id_of its Said, without finding it in the list)
  let said_id = fn(seq : Double, ts : String) -> String {
    rd0.sent_as_told.get() |> ignore
    let k = match rd0.sent.get(seq) {
      Some(o) => "o:" + o
      None => "m:" + ts
    }
    rd0.sent_as.get(k).unwrap_or(k)
  }
  // its rows, one for each message, read by index (ChatRows): the messages' changes taken as they come, the rows at
  // its ends (what was sent from here, taken by the core's row once it has it: tail_taken, as the old list's row_keys;
  // an agent's line staying a moment after its turn, with_lingering) made again as the core's view changes, as words
  // set off and as a line stays or goes; an agent's message waiting its turn to come out of its avatar not in it yet
  // (emit.mbt's emit_held)
  let key_of = fn(m : @sfbase.SaidRow) { id_of(Said(m)) }
  let rows_now : @signals.Signal[@sfbase.ChatRows] = @signals.signal(
    @sfbase.ChatRows::new(@sfbase.ChatMessages::of_value(None), key_of, end_key=id_of),
    same=fn(a, b) { physical_equal(a, b) },
  )
  v.owns(fn() { @signals.untracked(fn() { rows_now.get() }).let_go() }) |> ignore
  v.reacts(fn() {
    em.read()
    (ListedFrom::{ cv: view(), f: @sfbase.send_flight.get(), lingered: rd0.linger_said.get(), emitted: em.said.get() }, shown_by(), app_in_front())
  }, fn(now) {
    let { cv, f, .. } = now.0
    guard cv is Some(cv) else { return }
    // The data delivery owns its rows. Publish them in that change, before its later observers request pictures
    // or locate a message. Geometry's landing notification below does not retake the data or rebuild these rows.
    @sfbase.chat_take(@ui.current(), rk, rd0, cv, shown=now.1, in_front=now.2)
    // (those waiting their turn as what came is decided: emit_take's)
    let held = @signals.untracked(fn() { @sfbase.emit_held_seqs(em) })
    let tail = @sfbase.tail_taken(rd0, rk, cv, f)
    let was = @signals.untracked(fn() { rows_now.get() })
    let cr = if physical_equal(was.messages, cv.messages) {
      was
    } else {
      was.let_go()
      @sfbase.ChatRows::new(cv.messages, key_of, end_key=id_of)
    }
    cr.take(cv, tail, empty=@sfbase.fresh_view(r) is None, held~)
    rows_now.set(cr)
    advance()
  })
  v.reacts(fn() { rd0.landing.get() }, fn(_) { advance() })
  // (the message the unread line is over, followed as that changes alone)
  let line_seq = @signals.computed(fn(_) { view().bind(fn(cv) { cv.unread_line }) }, same=fn(a, b) { a == b })
  // (a message's row: the unread line over it where it is over it, its own gap under the line (joined, 4; else the
  // rows' gap), the message (`body`), where it was sent elsewhere under it, each the rows' gap under the one before:
  // what were rows of their own, each its own)
  // (by the width the list is laid out at (`w`): 700 or less narrow, 20 apart; in from the pane's sides to the column
  // by row_side_in: 16 narrow, else the column 760 wide at most in its middle)
  let gap_of = fn(joined : Bool, w : Double) {
    if joined { joined_gap } else if w <= chat_narrow_w { list_gap_narrow } else { list_gap }
  }
  // (`lead` the room over the first of them, the row's (the line's, else the message's); `ground` the message's, lit
  // as a row is (its menu open, gone to) over the room over it and it alone, as the row it was)
  // (in from the pane's sides to the column, `top` over it: a row's room; a message's parts each their own, the band
  // of its own part across the whole of it as the row's was)
  // (by how wide the list is laid out, in the same layout (Roomed): nothing of its width read back)
  let row_room = fn(node : @view.View, top : (Double) -> Double) {
    node.padding(Roomed(v, fn(w, _) { let s = row_side_in(w); (s, top(w), s, 0.0) })) |> ignore
  }
  let parts = fn(
    row : @view.View,
    lined : () -> Bool,
    joined : () -> Bool,
    elsewhere : () -> Array[Elsewhere],
    here : () -> MessageHere,
    lead : (Double) -> Double,
    ground : () -> Int64,
    body : (@view.View) -> Unit,
  ) {
    row.show(lined, fn(l) {
      row_room(l, lead)
      l.box(fn(b) { unread_line_node(b) }) |> ignore
    })
    row.box(fn(said) {
      row_room(said, fn(w) { if lined() { gap_of(joined(), w) } else { lead(w) } })
      said.ground(By(ground)) |> ignore
      said.box(body) |> ignore
    })
    |> ignore
    row.pick(fn() { elsewhere().length() }, fn(sent, n) {
      for i in 0..<n {
        // (the gap over it its own box's: what it draws in its margin (its picture) placed from its top, as a row's)
        sent.box(fn(g) {
          row_room(g, fn(w) { gap_of(false, w) })
          g.box(fn(b) {
            sent_elsewhere_node(b, src, here, fn() { elsewhere().get(i).unwrap_or_else(fn() { elsewhere()[0] }) })
          })
          |> ignore
        })
        |> ignore
      }
    })
  }
  let said_parts = fn(
    row : @view.View,
    m : () -> Message,
    here : () -> MessageHere,
    lead : (Double) -> Double,
    ground : () -> Int64,
    body : (@view.View) -> Unit,
  ) {
    parts(row, fn() { line_seq.get() == Some(m().seq) }, fn() { m().joined }, fn() { m().elsewhere }, here, lead, ground, body)
  }
  // (the room over row `e`, `i`th: none over the first, 4 over a message joined to the one before, else the gap)
  let gap_kind = fn(e : Entry, i : Int) -> Int {
    let joined = match e {
      // (the unread line over it: the gap over the line, then its own under it, said_parts')
      Said(m) => m.joined && line_seq.get() != Some(m.seq)
      Out(o) => o.joined
      _ => false
    }
    if e is Top || e is Foot || i <= 1 {
      0
    } else if joined {
      1
    } else {
      2
    }
  }
  let draft = r.station + ":" + r.session
  let leaving = fn() {
    match @sfbase.flight_of(draft) {
      Some(f) => {
        f.way.ends() |> ignore
        Some(f)
      }
      None => None
    }
  }
  let sent_foot = Ref("")
  let row_sizes : @ui.ListRows[Entry] = @ui.ListRows::new()
  rd0.rows = row_sizes
  let foot_said = Ref(false)
  // (the room under the last row: another as what it is kept clear of changes (the bell's, ask_clears), and as words
  // sent let go of the composer, its version one more: list_size.mbt's Foot)
  v.reacts(fn() {
    match leaving() {
      Some(f) if f.placed => sent_foot.val = f.key
      _ => ()
    }
    "foot/\{view().map_or(false, @sfbase.ask_clears)}/\{sent_foot.val}"
  }, fn(_) {
    // (as it first is: the room it is made with, nothing changed)
    if foot_said.val {
      @signals.untracked(fn() { rows_now.get() }).said("foot")
    }
    foot_said.val = true
  })
  // The row rooms share the reply owner's navigation cause. Last layout's omissions can still describe the
  // covered page when its return has already delivered replies, or the shown page before it is covered.
  let sized = rows_sized(row_sizes, v, fn() { rows_now.get() }, watched=fn() { shown_by() && !view().map_or(false, fn(cv) { cv.newer }) },
    from=fn(_) {
      match leaving() {
        Some(f) if !f.carried => {
          let start = if f.placed { f.set_out } else { v.cause_at() }
          let at = start + @sfbase.flight_settle * f.ms
          if at > v.cause_at() { Some(at) } else { None }
        }
        _ => None
      }
    },
    ms=fn(k) {
      match leaving() {
        Some(f) if !f.carried && (f.key == k || k == "foot") => Some((1.0 - @sfbase.flight_settle) * f.ms)
        Some(f) if f.key == k => Some(@sfbase.flight_ms_of(f))
        _ => {
          em.read()
          match em.current {
            Some(t) if t.pose == @sfbase.Pose::Float => {
              if said_id(t.seq, t.ts) == k {
                // (as long as its avatar's way there, said by how far it is as the row comes in: emit_step)
                Some(t.span)
              } else {
                None
              }
            }
            _ => None
          }
        }
      }
    },
    comes=fn(e) {
      match e { Said(m) => m.said; Top | Foot => false; _ => true }
    },
    middle=fn(e) {
      !@sfbase.flight_takes(draft, id_of(e)) &&
      (match e { Said(m) => !emit_goes(em, m.seq); Top | Foot => false; _ => true })
    },
    grown=fn(e) {
      match e { Said(m) => !emit_words_only(em, m.seq); Working(_) => false; _ => true }
    },
    // (the room over a row, by the width the list is laid out at as it is laid out: the gap its padding has, gap_of's)
    lead_in_layout=fn(e, i) {
      let kind = gap_kind(e, i)
      fn(w) { if kind == 0 { 0.0 } else { gap_of(kind == 1, w) } }
    },
    own=fn(e) { e is Foot },
  )
  // (the row keyed `k` and where it is among them (one going too), followed by what it shows and by which is the first
  // under the bar (no gap over it))
  let row_of = fn(k : String) -> (Entry, Int)? {
    rows_now.get().lead() |> ignore
    (sized.item_of)(k)
  }
  // The chat, rather than a row made by layout, owns its image requests and their answers. Keep one data watch per
  // sighted row; a row only passed on the way is asked too, then its watch is let go.
  let pictures = ChatPictures::new(v, src, r, view)
  v.lends(chat_pictures_lent, pictures) |> ignore
  let picture_rows : Map[String, ChatPictureRow] = {}
  let forget_picture_row = fn(k : String) {
    match picture_rows.get(k) {
      Some(row) => {
        row.watch.stop()
        match row.reading { Some(reading) => reading.stop(); None => () }
        picture_rows.remove(k)
      }
      None => ()
    }
  }
  let request_picture_row = fn(k : String) {
    guard picture_rows.get(k) is Some(row) else { return }
    let entry = row.watch.read(fn() { if row.inside { row_of(k).map(fn(item) { item.0 }) } else { None } })
    guard @signals.untracked(view) is Some(cv) else { return }
    let width = row.width
    let here = here_of(r, cv, rk, @sfbase.turns_of(rk), em, None, core,
      inline=width <= chat_narrow_w, gutter=row_side_in(width))
    let message = match entry {
      Some(Said(s)) => {
        let m = s.message()
        row.message = Some(m)
        Some(m)
      }
      Some(Out(o)) => {
        pictures.want_files(here, o.attachments, o.quotes, true, width)
        None
      }
      _ => if row.inside { None } else { row.message }
    }
    if message is Some(m) {
      let needs_reading = picture_markdown(m) && !m.placed.is_empty() && m.md is None && m.text != ""
      if !needs_reading || row.reading_text != m.text {
        match row.reading { Some(reading) => reading.stop(); None => () }
        row.reading = None
        row.reading_text = ""
      }
      if needs_reading && row.reading is None {
        row.reading = Some(@sf.md_picture_reading(m.text, m.md))
        row.reading_text = m.text
      }
      let waiting = match row.reading {
        Some(reading) => row.watch.read(fn() {
          if row.inside { row_of(k) |> ignore }
          reading.waiting()
        })
        None => false
      }
      row.waiting = waiting
      pictures.want_message(here, m, width, !waiting)
      if !waiting {
        match row.reading { Some(reading) => reading.stop(); None => () }
        row.reading = None
        row.reading_text = ""
      }
    } else {
      row.waiting = false
      match row.reading { Some(reading) => reading.stop(); None => () }
      row.reading = None
    }
    if !row.inside && !row.waiting { forget_picture_row(k) }
  }
  v.owns(fn() {
    for row in picture_rows.values() {
      row.watch.stop()
      match row.reading { Some(reading) => reading.stop(); None => () }
    }
    picture_rows.clear()
  }) |> ignore
  // (the rows made now, by their keys: where each is, what is read)
  let row_views : Map[String, @view.View] = {}
  // Follow the data of the rows in that observation separately. A message can replace an outgoing row without
  // changing its geometry; that is a data change, not a new layout observation.
  let reading_data = @signals.signal(0)
  let reading_rows = @signals.watch(fn() {
    reading_data.set(@signals.untracked(fn() { reading_data.get() }) + 1)
  })
  v.owns(fn() { reading_rows.stop() }) |> ignore
  let read_sighted = fn(s : @view.Sighted[String]) {
    guard !v.shown_nowhere() && @signals.untracked(view) is Some(cv) else { return }
    let rows = reading_rows.read(fn() {
      s.rows.map(fn(row) { (row_of(row.0).map(fn(r) { r.0 }), row.1, row.2) })
    })
    let rd = rd0
    let room_top = s.cover.0
    let room_foot = s.height - s.cover.1
    let opening = @signals.untracked(sized.opening)
    let moving = @signals.untracked(fn() { scroll.glides_till_told() })
    let at_end = @signals.untracked(fn() { follows.get() })
    let mut top_seq = -1.0
    let mut top_off = 0.0
    let mut bottom_seq = -1.0
    let mut state_seen = false
    for (e, y, h) in rows {
      if y + h > 0.0 && y < s.height {
        match e {
          Some(Said(m)) if m.seq >= 0.0 => {
            if top_seq < 0.0 {
              top_seq = m.seq
              top_off = y
            }
            bottom_seq = m.seq
            if !cv.newer && !opening && y >= room_top - 0.5 && y + h <= room_foot + 0.5 && m.seq > rd.seen_whole {
              rd.seen_whole = m.seq
            }
          }
          Some(State(_, _, _)) => state_seen = true
          _ => ()
        }
      }
    }
    rd.state_seen = state_seen
    rd.top_seq = top_seq
    rd.top_off = top_off
    rd.bottom_seq = bottom_seq
    let seen = !cv.newer && at_end && moving is None && !opening
    rd.at_end = seen
    rd.scale = @ui.current().scale
    if rd.placed && moving is None {
      @sfbase.tell_place(src, r, cv, rd)
    }
    @sfbase.tell_focus(src, r, cv, rd, seen, rd.seen_whole)
  }
  // (where it is put once, by a row's key and how far under the list's top its top stands)
  let put : @signals.Signal[(String, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })
  // (the message gone to and when it was: its row lit whole as it flashes, flash_start's curve from then)
  let flash : @signals.Signal[(String, Double)] = @signals.signal(("", 0.0), same=fn(a, b) { a == b })
  // (the rows in sight, by their keys, in order)
  let shown : @signals.Signal[Array[String]] = @signals.signal([], same=fn(a, b) { a == b })
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  v.box(fn(col) {
    col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    col.scrolls_anchored(
      scroll,
      fn() { [] },
      indexed=sized.source,
      est=chat_row_est,
      // (what shows measured, nothing past it: a row out of sight counted as tall as its kind is guessed to be, measured
      // as it comes in; none of it made, its words shaped or its pictures decoded before)
      ahead=0.0,
      follows~,
      shown~,
      put~,
      sighted=fn(s) {
        last_sighted.val = Some(s)
        read_sighted(s)
        for k in s.came {
          if !picture_rows.contains(k) {
            let watch = @signals.watch(fn() {
              // The row's data changed: ask at that cause, with the last sighted width. Any picture follower made
              // here belongs to the chat, not to whichever effect happened to deliver the new message.
              @signals.untracked(fn() {
                let owner = @signals.set_owner(None)
                request_picture_row(k)
                @signals.set_owner(owner) |> ignore
              })
            })
            picture_rows[k] = {
              watch, width: s.width, inside: true, waiting: false, message: None,
              reading_text: "", reading: None,
            }
          }
          match picture_rows.get(k) {
            Some(row) => {
              row.inside = true
              row.width = s.width
            }
            None => ()
          }
          request_picture_row(k)
        }
        for k in s.left {
          match picture_rows.get(k) {
            Some(row) => {
              row.inside = false
              if row.waiting {
                // Only its unfinished Markdown answer is followed after it has left, not later message changes.
                request_picture_row(k)
              } else {
                forget_picture_row(k)
              }
            }
            None => ()
          }
        }
      },
      rooms=sized.room_now,
      // The flying copy needs its real landing before the glide brings the row into sight.
      kept_keys=fn() { @sfbase.flight_of(draft).map(fn(f) { [f.key] }).unwrap_or([]) },
      // (new to it: said while it shows, an agent starting, sent from here; not what is caught up on, at once)
      // (the bar over its top: what comes taller than what shows is read from its top under it)
      cover=top,
      keep=keep_field,
      // The composer covers the list without moving its rows. Report its cover with the drawn rows, so what is read
      // is updated when a message is uncovered even if its place does not change.
      fresh=fn(k) {
        match row_of(k) {
          Some((Said(m), _)) => m.said
          Some((Working(a), _)) => a.started
          Some((Out(_), _)) => true
          _ => false
        }
      },
      read_from_top=fn(k) {
        match row_of(k) {
          Some((Said(m), _)) => !m.mine
          Some((Out(_), _)) => false
          _ => true
        }
      },
      fn(slot, k) {
        (sized.lend)(slot, k)
        slot.lends(chat_picture_in_sight, fn() {
          picture_rows.get(k).map_or(false, fn(row) { row.inside })
        }) |> ignore
        match @signals.untracked(fn() { row_of(k) }) {
          Some((Top, _)) => { slot.height(By(fn() { Some(top()) })) |> ignore; return }
          // (as tall as what covers the list's foot (the composer's room, its own lift with it), given it as what holds
          // it measures it (Layout::given_foot), and the gap under its last row: in the same layout)
          Some((Foot, _)) => {
            slot.layout_box(Is(()), sized=true, fn(l, _) {
              l.size_to(l.given_foot().map(fn(g) { g.1 }).unwrap_or(0.0) + foot_gap)
            })
            |> ignore
            return
          }
          _ => ()
        }
        // (its node while it is made, for an event that needs its place)
        row_views[k] = slot
        slot.owns(fn() {
          match row_views.get(k) {
            Some(x) if physical_equal(x, slot) => row_views.remove(k)
            _ => ()
          }
        })
        |> ignore
        // (its menu open (right clicked, its ⋯): the row in the pointer's ground, easing in and out as a row's under the
        // pointer does: the old list's band)
        let menu_lit = @sf.EdgeWay::new(0.0)
        slot.reacts(fn() {
          match row_of(k) {
            Some((Said(m), _)) => @sfbase.message_menu_on("m:" + m.ts)
            _ => false
          }
        }, fn(on) { menu_lit.go_by(slot, if on { 1.0 } else { 0.0 }, @sf.nav_fade) })
        // (gone to: flashing in, held and out (flash_start's), with motion reduced whole for its flash's time)
        let flash_k = fn() {
          let (ts, from) = flash.get()
          match row_of(k) {
            Some((Said(m), _)) if ts != "" && m.ts == ts => {
              let t = slot.drawn_at() - from
              let lit = if t >= @sfbase.flash_ms {
                0.0
              } else if @ui.reduced_motion() || @sfbase.flash_held.val {
                1.0
              } else if t < @sfbase.flash_in_ms {
                @ui.Ease::Out.at(dmax(t, 0.0) / @sfbase.flash_in_ms)
              } else if t < @sfbase.flash_held_ms {
                1.0
              } else {
                1.0 - @ui.Ease::Leave.at((t - @sfbase.flash_held_ms) / (@sfbase.flash_ms - @sfbase.flash_held_ms))
              }
              flashing_now.val = (ts, lit)
              lit
            }
            _ => 0.0
          }
        }
        // (led there by a quote: the passage it quoted lit alone, where the message's words have it, on the accent as
        // a passage picked is, round at its two ends (pick.mbt's `lit`, passage_lit's); none where they have it not)
        slot.lends(@view.runs_liter, fn(words) {
          By(fn() {
            let passage = rd0.flash_passage
            let f = if passage == "" { 0.0 } else { flash_k() }
            if f <= 0.0 {
              return (0, 0, 0L, 0.0)
            }
            words.words_said() |> ignore
            let text = StringBuilder()
            for r in words.runs_set_now().0 {
              text.write_string(r.text)
            }
            match @sf.find_passage(text.to_string(), passage) {
              Some((a, b)) => (a, b, @sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha * f), @sf.ui_theme().corner(Md))
              None => (0, 0, 0L, 0.0)
            }
          })
        })
        |> ignore
        // (a quote's passage below four fifths of the pane: once its target row is placed and laid out, move the
        // anchored row so that the passage is in the middle; leave the row alone when its passage is already high)
        slot.reacts(fn() { (flash.get().0, put.get(), slot.owed_laid_window(), v.owed_laid_window()) }, fn(now) {
          guard rd0.flash_centre && now.0 != "" && now.1 is None &&
            row_of(k).map_or(false, fn(r) { match r.0 { Said(m) => m.ts == now.0; _ => false } }) &&
            now.2 is Some((_, row_y, _, _)) && now.3 is Some((_, py, _, ph)) else { return }
          let (ready, found) = quote_passage_rect(slot, now.0, rd0.flash_passage)
          guard ready else { return }
          rd0.flash_centre = false
          match found {
            Some((first, last)) => {
              let mid = (first.1 + last.1 + last.3) / 2.0 - py
              if mid > ph * 0.8 {
                let offset = row_y - py - (mid - ph / 2.0)
                // Change the list's anchor itself: scrolling without changing it would put this row back.
                put.set(Some((k, offset)))
              }
            }
            None => ()
          }
        })
        slot.reacts(fn() { flash.get() }, fn(f) {
          // (over once its time is: nothing more read of the clock for it)
          if f.0 != "" {
            slot.at_moment(f.1 + @sfbase.flash_ms, fn() {
              if @signals.untracked(fn() { flash.get() }) == f {
                flash.set(("", 0.0))
                flashing_now.val = (f.0, 0.0)
              }
            })
            |> ignore
          }
        })
        // (lit whole: a band in the accent's ground, square; its menu open, in the pointer's; a message's in its part,
        // said_parts')
        let lit = fn() -> Int64 {
          let f = if rd0.flash_passage == "" { flash_k() } else { 0.0 }
          if f > 0.0 {
            let g = @sf.theme().p.accent_bg
            return @sf.alpha(g, f)
          }
          let a = menu_lit.shown(slot)
          if a > 0.0 { @sf.alpha(@sf.theme().p.hover, a) } else { 0L }
        }
        slot.ground(By(fn() { if row_of(k) is Some((Said(_) | Out(_), _)) { 0L } else { lit() } })) |> ignore
        // (the room over a message's first part: the row's gap, as gap_kind says it)
        let said_lead = fn(w : Double) {
          match row_of(k) {
            Some((e, i)) => {
              let kind = gap_kind(e, i)
              if kind == 0 { 0.0 } else { gap_of(kind == 1, w) }
            }
            None => 0.0
          }
        }
        // (what it is: a message (message_node.mbt), what was sent from here, an agent at work, the line over what is new,
        // the pages coming, a chat with nothing in it, where it stands, what was said elsewhere (chat_rows_node.mbt);
        // made again as which of those it is changes)
        // (arranged by the room the list gives it, in the same layout (by_room): narrow (700 or less) or wide, made
        // again only where it goes from one to the other; how far in from the pane's sides its column is, what its
        // messages' tables scroll out into, lent as worked out from how wide it is laid out (Roomed), never kept from
        // the width it was made at)
        slot.by_room(Is(()), sized=true, fn(_, w, _) { w <= chat_narrow_w }, fn(holder, narrow) {
        holder.lends(chat_row_bleed, (holder, row_side_in)) |> ignore
        // (its room: in from the pane's sides to the column, the gap over it; under the bar over the first, the
        // composer under the last)
        holder
        .padding(Roomed(v, fn(w, _) {
          // (a message's row: the room over it its parts', said_parts')
          match row_of(k) {
            Some((Said(_) | Out(_), _)) => (0.0, 0.0, 0.0, 0.0)
            r => {
              let gap = match r {
                Some((e, i)) => { let kind = gap_kind(e, i); if kind == 0 { 0.0 } else { gap_of(kind == 1, w) } }
                None => 0.0
              }
              let side = row_side_in(w)
              (side, gap, side, 0.0)
            }
          }
        }))
        |> ignore
        let here = fn() {
          match view() {
            Some(cv) => here_of(r, cv, rk, @sfbase.turns_of(rk), @sfbase.emits_of(rk), None, core, inline=narrow)
            None => here_of(r, @sfbase.chat_view_made(Json::object({})), rk, @sfbase.turns_of(rk), @sfbase.emits_of(rk), None, core, inline=narrow)
          }
        }
        // (what it is as it was last found: a row going not found among them for a moment, as its list takes its going,
        // keeps showing what it showed)
        let kind_was = Ref(0)
        holder.pick(fn() {
          let kind = match row_of(k) {
            Some((Said(m), _)) => message_made_whole(m.message())
            Some((Out(_), _)) => 3
            Some((Working(_), _)) => 4
            Some((Older, _)) => 7
            Some((Newer, _)) => 8
            Some((Empty, _)) => 9
            Some((State(_, _, _), _)) => 10
            Some((Sent(_), _)) => 11
            _ => kind_was.val
          }
          kind_was.val = kind
          kind
        }, fn(row, whole) {
          // (the first of what was sent from here not in the chat yet: where a message out of an avatar comes in over
          // it, emit.mbt)
          emit_place_node(row, fn() { if row_of(k) is Some((Out(_), _)) { Some("emit-out/" + rk + "/" + k) } else { None } })
          if whole > 0 {
            // (as it is now; as it last was while its row goes)
            let last : Ref[Message?] = Ref(None)
            let m = fn() {
              match row_of(k) {
                Some((Said(r), _)) => {
                  let m = r.message()
                  last.val = Some(m)
                  m
                }
                _ => last.val.unwrap_or_else(fn() { @sfbase.message_of(Json::object({})) })
              }
            }
            if whole == 7 || whole == 8 {
              pages_coming_node(row, whole == 7)
            } else if whole == 9 {
              chat_empty_node(row)
            } else if whole == 10 {
              // (where it stands as it is now; as it last was while its row goes)
              let last_s = Ref(("", "", ""))
              chat_state_node(row, src, here, fn() {
                match row_of(k) {
                  Some((State(w, l, r), _)) => {
                    last_s.val = (w, l, r)
                    (w, l, r)
                  }
                  _ => last_s.val
                }
              })
            } else if whole == 11 {
              let last_e : Ref[Elsewhere?] = Ref(None)
              sent_elsewhere_node(row, src, here, fn() {
                match row_of(k) {
                  Some((Sent(e), _)) => {
                    last_e.val = Some(e)
                    e
                  }
                  _ => last_e.val.unwrap()
                }
              })
            } else if whole == 5 {
              said_parts(row, m, here, said_lead, lit, fn(b) { notice_node(b, src, here, m) })
            } else if whole == 4 {
              // (an agent at work as it is now; as it last was while its row goes; new to the list as it is
              // watched, its first words coming in from then)
              let last_a : Ref[Agent?] = Ref(None)
              let a = fn() {
                match row_of(k) {
                  Some((Working(a), _)) => {
                    last_a.val = Some(a)
                    a
                  }
                  _ => last_a.val.unwrap()
                }
              }
              let came = @signals.untracked(fn() { row_sizes.came(k) })
              activity_node(row, src, here, a, rk, came)
            } else if whole == 3 {
              // (the outbox entry as it is now; as it last was while its row goes)
              let last_o : Ref[Outgoing?] = Ref(None)
              let o = fn() {
                match row_of(k) {
                  Some((Out(o), _)) => {
                    last_o.val = Some(o)
                    o
                  }
                  _ => last_o.val.unwrap()
                }
              }
              // (in parts as a message's row is: the core's row going on from it, what it shows the same nodes)
              parts(row, fn() { false }, fn() { o().joined }, fn() { [] }, here, said_lead, lit, fn(b) {
                outbox_node(b, src, here, o, fn() { v.window().0 }, None, key=fn() { k })
              })
            } else if whole == 2 {
              said_parts(row, m, here, said_lead, lit, fn(b) { mine_message_node(b, src, here, m, fn() { v.window().0 }, None, key=fn() { k }) })
            } else {
              said_parts(row, m, here, said_lead, lit, fn(b) { others_message_node(b, src, here, m, None) })
            }
          }
        })
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
  // (what flies out of an activity's picture to its message and back, over the rows, under the composer and the bar)
  v.box(fn(fl) {
    fl
    .over(Is(true))
    |> ignore
    emit_flyer_node(fl, rk, view)
  })
  |> ignore
  // (the first of what was sent from here not in the chat yet, as the list has it: a message out of an avatar comes
  // in over it, emit.mbt; list_frame's out_key. The outbox lies at its end, before where it stands, its agents at work)
  v.reacts(fn() {
    let cr = rows_now.get()
    cr.changed() |> ignore
    let all = cr.tail()
    let mut at = ""
    let mut i = all.length() - 1
    while i >= 0 {
      match all[i] {
        Out(_) => at = id_of(all[i])
        State(_, _, _) | Working(_) | Foot => ()
        _ => break
      }
      i = i - 1
    }
    at
  }, fn(out_key) {
    if out_key != em.out_key {
      em.out_key = out_key
      em.changed()
    }
  })
  let to_end = fn() {
    // (further than list_glide_rows rows from its end, at once: an old view's list_to_end's glide_to_end)
    let far = @signals.untracked(fn() {
      match shown.get().last() {
        Some(last) =>
          match row_of(last) {
            Some((_, i)) => (sized.source.snapshot)().1 - 1 - i > chat_glide_rows
            None => true
          }
        None => true
      }
    })
    follows.set(true)
    scroll.glide_to(scroll.most(), glide=!far)
  }
  v.reacts(fn() { rd0.end_asked.get() }, fn(asked) {
    if asked {
      rd0.end_asked.set(false)
      to_end()
    }
  })
  // the pages before and after (list_after's): near its top (its first three rows in sight) the page before, once per
  // page (by entries: a page of what the chat does not show moves it too); near the end of a window short of the
  // chat's, the page after; the chat's latest page come in place of a window short of its end, asked for: at its end
  // at once. Asked as what is in sight changes, from where it is laid out then.
  v.reacts(fn() { view().map(fn(cv) { cv.newer }) }, fn(newer) {
    if rd0.latest_asked && newer == Some(false) {
      rd0.latest_asked = false
      follows.set(true)
      scroll.glide_to(scroll.most(), glide=false)
    }
  })
  v.reacts(fn() {
    let in_sight = shown.get()
    let first = in_sight.get(0).bind(fn(k) { row_of(k).map(fn(r) { r.1 }) })
    let last = in_sight.last().bind(fn(k) { row_of(k).map(fn(r) { r.1 }) })
    let page = view().map(fn(cv) {
      (cv.more, cv.newer, cv.first_entry, cv.last_entry, cv.thread, cv.messages.length(),
        cv.messages.get(0).map(fn(m) { m.seq }), cv.messages.last().map(fn(m) { m.seq }))
    })
    (first, last, (sized.source.snapshot)().1, page)
  }, fn(now) {
    let (first, last, count, page) = now
    let rd = rd0
    guard page is Some((more, newer, first_entry, last_entry, thread, messages, first_seq, last_seq)) else { return }
    if messages > 0 || more {
      rd.placed = true
    }
    guard thread is Some(thread) else { return }
    match first {
      Some(i) if more && rd.placed && i <= 2 => {
        let entry = match first_entry {
          Some(f) => f
          None => first_seq.unwrap_or(-1.0)
        }
        if @signals.untracked(fn() { rd.asked.get() }) != entry {
          rd.asked.set(entry)
          (src.call)("chat.older", { "station": Json::string(r.station), "thread": Json::number(thread) }, fn(res) {
            if res is Err(_) {
              rd.asked.set(-1.0)
            }
          })
        }
      }
      _ => ()
    }
    match last {
      Some(i) if newer && rd.placed && i >= count - 3 => {
        let entry = match last_entry {
          Some(l) => l
          None => last_seq.unwrap_or(-1.0)
        }
        if @signals.untracked(fn() { rd.asked_newer.get() }) != entry {
          rd.asked_newer.set(entry)
          (src.call)("chat.newer", { "station": Json::string(r.station), "thread": Json::number(thread) }, fn(res) {
            if res is Err(_) {
              rd.asked_newer.set(-1.0)
            }
          })
        }
      }
      _ => ()
    }
  })
  // put in place once (list_after's): at the unread line, else where it was left here this run (unless at its end with
  // nothing new since), else where the core opened it (that message's top as far below the list's as it was, else
  // under the bar), else at its end, where it starts
  v.reacts(fn() { (view().map(fn(cv) { cv.messages.length() }), rows_now.get().length()) }, fn(_) {
    let rd = rd0
    guard !rd.put && !@sfbase.at_end_asked() else { return }
    guard @signals.untracked(view) is Some(cv) else { return }
    guard cv.messages.length() > 0 || cv.more else { return }
    guard !cv.unread_above else { return }
    rd.placed = true
    rd.put = true
    let cr = @signals.untracked(fn() { rows_now.get() })
    let newest = cv.messages.last().map(fn(m) { m.seq }).unwrap_or(-1.0)
    let kept = @sfbase.kept_places.get(rk)
    let left_at_end = match kept {
      Some(p) => p.bottom >= 0.0 && p.bottom == newest
      None => false
    }
    let opened_at = if left_at_end { None } else { cv.at }
    // (each looked for among the messages by its seq, by halves: the unread line's over its message, in its row)
    let n = cv.messages.length()
    let line = match cv.unread_line {
      Some(seq) => {
        let i = cr.message_at(seq)
        if i >= 0 { Some(cr.message_key(i)) } else { None }
      }
      None => None
    }
    let at = match opened_at {
      Some(a) => {
        let i = cr.message_from(a)
        if i < n { Some(cr.message_key(i)) } else { None }
      }
      None => None
    }
    let was = match kept {
      Some(p) if !left_at_end => {
        let i = cr.message_from(p.top)
        if i < n && cv.messages[i].seq == p.top { Some(cr.message_key(i)) } else { None }
      }
      _ => None
    }
    rd.lined = line is Some(_)
    match (line, was, at) {
      (Some(k), _, _) => put.set(Some((k, @signals.untracked(top))))
      (None, Some(k), _) => put.set(Some((k, kept.unwrap().offset)))
      (None, None, Some(k)) =>
        put.set(Some((k, match cv.at_offset {
          Some(px) => px / @ui.current().scale
          None => @signals.untracked(top)
        })))
      _ => ()
    }
  })
  // the unread line come after the list was put in place (what came while the app was away, read after the chat
  // opened, the list at its end as it came): put there, as at a chat opened with it, while the reader is still at its
  // end (Chat.tsx `lined`)
  v.reacts(fn() {
    let cr = rows_now.get()
    (cr, cr.changed(), line_seq.get())
  }, fn(now) {
    let (cr, _, line_at) = now
    let rd = rd0
    // (the rows at its ends it has had, Reading's known: what words sent go on to)
    for e in cr.tail() {
      rd.known[id_of(e)] = true
    }
    rd.drawn = true
    guard rd.put && !rd.lined && line_at is Some(seq) else { return }
    let i = cr.message_at(seq)
    if i >= 0 {
      rd.lined = true
      if @signals.untracked(fn() { follows.get() }) {
        put.set(Some((cr.message_key(i), @signals.untracked(top))))
      }
    }
  })
  // a message gone to (go_to: a notification's, a quote's, the bell's), once the list is in place: there, its top under
  // the bar, flashing (only the passage a quote quoted, where its words have it); the pages before brought in until
  // it is (none left, or it is gone)
  v.reacts(fn() { (@sfbase.go_to_said.get(), rows_now.get().changed()) }, fn(_) {
    let rd = rd0
    guard rd.placed && @sfbase.go_tos.get(rk) is Some(target) else { return }
    guard @signals.untracked(view) is Some(cv) else { return }
    let cr = @signals.untracked(fn() { rows_now.get() })
    // (the first message's seq; the one gone to, looked for by halves)
    let first = cv.messages.get(0).map(fn(m) { m.seq }).unwrap_or(-1.0)
    let i = cr.message_from(target)
    let found = match cv.messages.get(i) {
      Some(m) if m.seq == target => Some((cr.message_key(i), m))
      _ => None
    }
    match found {
      Some((k, m)) => {
        @sfbase.go_tos.remove(rk)
        let passage = @sfbase.go_to_passages.get(rk).unwrap_or("")
        @sfbase.go_to_passages.remove(rk)
        match @sfbase.go_to_words.get(rk) {
          // (opened from a search: its words marked in it, nothing flashing (Chat.kt markWords, FOUND))
          Some(words) => {
            @sfbase.go_to_words.remove(rk)
            rd.found_at = m.ts
            rd.found_words = words
            rd.found_centre = true
            rd.found_told.set(@signals.untracked(fn() { rd.found_told.get() }) + 1)
          }
          None => {
            rd.flash = m.ts
            rd.flash_passage = passage
            rd.flash_centre = rd.flash_passage != ""
            @sfbase.flash_start(rd)
            flash.set((m.ts, v.cause_at()))
          }
        }
        put.set(Some((k, @signals.untracked(top))))
      }
      None =>
        match cv.thread {
          Some(thread) if cv.more && first > target =>
            if @signals.untracked(fn() { rd.asked.get() }) != first {
              rd.asked.set(first)
              (src.call)("chat.older", { "station": Json::string(r.station), "thread": Json::number(thread) }, fn(res) {
                if res is Err(_) {
                  @sfbase.go_tos.remove(rk)
                }
              })
            }
          _ => @sfbase.go_tos.remove(rk)
        }
    }
  })
  // A glide ending or the chat's data changing can change what is told even when no row moves. Observe only those
  // inputs here; the geometry comes from the list's last painted sighting, never from a followed layout result.
  @ui.read_drawn(v, fn() {
    (reading_data.get(), rows_now.get().changed(), scroll.glides_till_told(), follows.get(),
      view().map(fn(cv) { cv.newer }), (sized.opening)())
  }, fn(_) {
    match last_sighted.val { Some(s) => read_sighted(s); None => () }
  })
  // The old list offered the way back only after layout, more than 120 points from its end, except while gliding to it.
  // Following the end is already the reader's intent. Newly revealed rows can temporarily put the last laid-out
  // end outside the window; that does not offer a way back or start a fade when a later layout catches up.
  // A page short of the chat's newest page always offers it, even when the list itself is at its end.
  let newer = fn() { view().map(fn(cv) { cv.newer }).unwrap_or(false) }
  let jump_shown = fn() {
    let below = scroll.end_below_told()
    let going_to_end = scroll.to_end_told()
    newer() || (!follows.get() && !shown.get().is_empty() && below > 120.0 && !going_to_end)
  }
  v.reacts(fn() { (jump_shown(), follows.get(), newer()) }, fn(now) {
    rd0.jump = now.0
    // Following new rows is the reader's intent, even while their opening rooms mean the end is not yet seen.
    // Keep the avatar's turn watched through that movement, as the old list's following_row does.
    rd0.following_row = now.1 && !now.2
  })
  // what waits to be decided and does not show (ToAsk: the core's `asks`): a bell over the list right over the send
  // button, over the way to the end where both show; pressed, the chat goes to the first one's post, the next one's the
  // next time. Out of view once the list is laid out (nothing known to be out of view before); shown till every one
  // is in sight, as main's (asks_in_view): one in sight while another waits further on, the bell still goes to it.
  let asking = fn() {
    guard view() is Some(cv) else { return false }
    let asks = if cv.archived || cv.thread is None { [] } else { cv.asks }
    if asks.length() == 0 {
      return false
    }
    let in_sight = shown.get()
    if in_sight.length() == 0 {
      return false
    }
    // (an ask's row: its post's, or the chat's end where what an agent needs is said there, the core's `stateAsk`)
    let seen = fn(seq : Double) {
      in_sight.iter().any(fn(k) {
        match row_of(k) {
          Some((Said(m), _)) => m.seq == seq && cv.state_ask != Some(seq)
          Some((State(_, _, _), _)) => cv.state_ask == Some(seq)
          _ => false
        }
      })
    }
    !asks.iter().all(seen)
  }
  // Both actions stand six points inside the composer's end: the composer as wide as the page gives it in the list's
  // width, a panel's corners counted (composer_across), worked out as the list is laid out; over the composer's room
  // (the room under its last row given the list, less its own lift), as what holds them is laid out (floats_over).
  let float_right = fn(w : Double) { (w - composer_across(w)) / 2.0 + float_in }
  v.reacts(fn() { asking() }, fn(a) { rd0.ask = a })
  floats_over(v, fn() { lift() - float_lift - (if jump_shown() { float_above } else { 0.0 }) }, fn(f) {
    f
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .padding(Roomed(v, fn(w, _) { (0.0, 0.0, float_right(w), 0.0) }))
    |> ignore
    f.show(asking, fn(b) {
      b
      .width(Is(Some(float_side)))
      .height(Is(Some(float_side)))
      .lies_along(Is(Middle))
      .lines_up(Is(Some(Middle)))
      .radius(Is(float_side / 2.0))
      .ground(By(fn() { if @sf.lit_node(b) { @ui.tree_theme().color(Hover) } else { @ui.tree_theme().color(Surface) } }))
      .edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) }))
      .shadow(By(fn() {
        let (blur, dy) = @ui.Shadow::blur_y(Md)
        (blur, dy, @ui.tree_theme().shadow)
      }))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.asks.go"))) }))
      |> ignore
      @sf.presses_node(b, fn() {
        // (the list still moving by itself: stopped by the tap, which it takes as that alone)
        if scroll.glides_till() is Some(_) {
          scroll.stop()
          return
        }
        match @signals.untracked(view) {
          Some(cv) if cv.asks.length() > 0 => {
            let k = chat_key(r)
            let turn = ask_turns.get(k).unwrap_or(0)
            @sfbase.go_to(r, cv.asks[turn % cv.asks.length()])
            ask_turns[k] = turn + 1
          }
          _ => ()
        }
      })
      @sf.icon_node(b, "bell", float_icon, By(fn() { @sf.theme().p.text })) |> ignore
    })
  })
  |> ignore
  // the way to the newest (ToLatest): over the list right over the send button, the composer's room under it, a round
  // button with ↓ (and, short of the chat's end, how many new messages wait there); pressed, the list to its end, or,
  // short of the chat's end, the chat's latest page asked for
  let latest_coming = fn() {
    let thread = match view() {
      Some(cv) => cv.thread.map(fn(th) { th.to_int().to_string() }).unwrap_or("")
      None => ""
    }
    core_doing(src, ["chat.latest"], [("station", r.station), ("thread", thread)])
  }
  let jump_fade_ms = 160.0
  floats_over(v, fn() { lift() - float_lift }, fn(f) {
    f
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .padding(Roomed(v, fn(w, _) { (0.0, 0.0, float_right(w), 0.0) }))
    |> ignore
    let initial = Ref(true)
    f.show(jump_shown, fn(b) {
      let fade = @motion.trans(fade=0.0, spec=@motion.tween(jump_fade_ms, ease=Out))
      let look = @motion.presence_node(b, initial=initial.val, enter=fade, exit=fade)
      b
      .row(Is(true))
      .height(Is(Some(float_side)))
      .min_width(Is(Some(float_side)))
      .padding(Is((8.0, 0.0, 8.0, 0.0)))
      .gap(Is(4.0))
      .lies_along(Is(Middle))
      .lines_up(Is(Some(Middle)))
      .radius(Is(float_side / 2.0))
      .ground(By(fn() { if @sf.lit_node(b) { @ui.tree_theme().color(Hover) } else { @ui.tree_theme().color(Surface) } }))
      .edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) }))
      .alpha(By(fn() { look().alpha }))
      .hides(By(fn() { b.leaving() }))
      .shadow(By(fn() {
        let (blur, dy) = @ui.Shadow::blur_y(Md)
        (blur, dy, @ui.tree_theme().shadow)
      }))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.toLatest"))) }))
      |> ignore
      @sf.presses_node(b, fn() {
        if @signals.untracked(latest_coming) {
          return
        }
        match @signals.untracked(view) {
          Some(cv) if cv.newer =>
            match cv.thread {
              Some(th) => {
                rd0.latest_asked = true
                @sfbase.act(src, @sf.t("web-main.chat.toLatest"), "", "chat.latest", {
                  "station": Json::string(r.station),
                  "thread": Json::number(th),
                })
              }
              None => ()
            }
          _ => to_end()
        }
      }, on=fn() { !b.leaving() })
      b.pick(latest_coming, fn(icon, coming) {
        if coming {
          @sf.spinner_node(icon, size=float_icon) |> ignore
        } else {
          @sf.icon_node(icon, "arrow-down", float_icon, By(fn() { @sf.theme().p.text })) |> ignore
        }
      })
      b.show(fn() { view().map(fn(cv) { cv.newer && cv.unread > 0.0 }).unwrap_or(false) }, fn(n) {
        @sf.words_node(n, fn() {
          @sf.t("web-main.chat.newMessages", args=[("n", view().map(fn(cv) { cv.unread.to_int() }).unwrap_or(0).to_string())])
        }, fn() { float_count }) |> ignore
      })
    }, leave=jump_fade_ms)
    initial.val = false
  })
  |> ignore
  {
    to_latest: to_end,
    follows,
    lift,
    // (by its row as the list has it: its message's place, or its outbox entry's)
    landing_of: fn(k) {
      match row_of(k) {
        Some((Said(m), _)) => mine_landing(message_place(m.message()))
        Some((Out(o), _)) => mine_landing("o:" + o.id)
        _ => None
      }
    },
  }
}

///|
/// A quoted passage in the message's own laid-out words, by its first and last lines. Words of separate paragraphs
/// are one text, separated by newlines, as they are when picked; the row's author and quote cards are not its words.
fn quote_passage_rect(row : @view.View, ts : String, passage : String) -> (Bool, ((Double, Double, Double, Double), (Double, Double, Double, Double))?) {
  let pending = [row]
  let mut body : @view.View? = None
  while pending.pop() is Some(node) {
    match pick_rows.get(node.id()) {
      Some(pick) =>
        match pick() {
          Some(r) if r.ts == ts => { body = Some(node); break }
          _ => ()
        }
      None => ()
    }
    let children = node.kids()
    for i in 0..<children.length() {
      pending.push(children[children.length() - 1 - i])
    }
  }
  guard body is Some(body) else { return (false, None) }
  let paragraphs : Array[(@ui.Words, Int)] = []
  let text = StringBuilder()
  let mut length = 0
  pending.clear()
  pending.push(body)
  while pending.pop() is Some(node) {
    if !node.runs_set_now().0.is_empty() {
      match @ui.runs_words_now(node) {
        Some(words) => {
          if !paragraphs.is_empty() {
            text.write_char('\n')
            length = length + 1
          }
          paragraphs.push((words, length))
          text.write_string(words.text)
          length = length + words.text.length()
        }
        None => ()
      }
    }
    let children = node.kids()
    for i in 0..<children.length() {
      pending.push(children[children.length() - 1 - i])
    }
  }
  guard @sf.find_passage(text.to_string(), passage) is Some((a, b)) else { return (true, None) }
  let lines : Array[(Double, Double, Double, Double)] = []
  for (words, start) in paragraphs {
    let from = if a > start { a - start } else { 0 }
    let to = if b - start < words.text.length() { b - start } else { words.text.length() }
    if from < to {
      lines.append(words.rects(from, to))
    }
  }
  if lines.is_empty() { (true, None) } else { (true, Some((lines[0], lines[lines.length() - 1]))) }
}

///|
/// How wide the list's column is at most, in the pane's middle (Chat.css.ts chatColumn: 760).
let chat_column_most : Double = 760.0

///|
/// A chat's list made once (chat_list_node): to its end, following it again (glided there, at once from further than
/// chat_glide_rows rows off); whether it follows its end; where what was sent to its row `key` lands (by the key the
/// list has it by: what was sent from here by the key it was sent as), followed.
pub(all) struct ChatListNode {
  to_latest : () -> Unit
  follows : @signals.Signal[Bool]
  /// how much more room than the composer's it is to be given under its last row (the decision bell's, where the
  /// core says that can cover its end): what its page adds as it measures it (Layout::measure's `foot`)
  lift : () -> Double
  landing_of : (String) -> MineLanding?
}

///|
/// Further than this many rows from its end, the list goes there at once (an old view's list's list_glide_rows).
let chat_glide_rows : Int = 12

///|
/// What flies in each chat's page, by its chat (station and session): a node over its messages and its composer, under
/// its bar and what opens over it, cut by neither (its root's: chat_flight_layer_made), while that page is made.
// kept across runs: each let go with its page
let chat_flight_layers : Map[String, @view.View] = {}

///|
/// Chat `r`'s page's flight layer is `layer` (its root makes it), let go with it.
pub fn chat_flight_layer_made(r : ChatRef, layer : @view.View) -> Unit {
  let k = r.station + "\u{1}" + r.session
  chat_flight_layers[k] = layer
  layer.owns(fn() {
    match chat_flight_layers.get(k) {
      Some(l) if physical_equal(l, layer) => chat_flight_layers.remove(k)
      _ => ()
    }
  })
  |> ignore
}

///|
/// The picture flying out of an activity to its message and back (chat_list.mbt's emit_flyer): the agent's, ringed,
/// where emit.mbt has it between where they are laid out as each frame is drawn (emit_flight: with the list as it
/// glides), from its activity's fold on till it is home; in `layer`, over chat `rk`'s list (under its composer and its bar,
/// as the old list's layer was). Drawn only.
fn emit_flyer_node(layer : @view.View, rk : String, view : () -> ChatView?) -> Unit {
  let em = @sfbase.emits_of(rk)
  // (the agent flying, its pose past the fold)
  let flying = fn() -> Agent? {
    em.read()
    match (em.current, view()) {
      (Some(t), Some(v)) if t.pose != @sfbase.Pose::Fold => v.agents.iter().find_first(fn(a) { a.key == t.agent })
      _ => None
    }
  }
  layer.show(fn() { flying() is Some(_) }, fn(f) {
    // (where it is as this frame draws it, from the layer's corner: its 18 face's top left, the ring round it)
    let at = fn(laid : @view.Laid) {
      let agents = match view() {
        Some(v) => v.agents.map(fn(a) { a.key })
        None => []
      }
      // This picture reads the rows' current placement directly. It publishes no endpoint back to the timeline.
      @sfbase.emit_flight_by(rk, em, agents, fn(k) { @sfbase.emit_place_drawn(laid, k) }, laid.at())
    }
    let a = fn() { flying() }
    f
    .over(Is(true))
    .width(Is(Some(ring_side)))
    .height(Is(Some(ring_side)))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .alpha(Painted(fn(laid) { if at(laid) is Some(_) { 1.0 } else { 0.0 } }))
    // (from where this frame laid the layer out, read as it is painted)
    .offset(Painted(fn(laid) {
      let (lx, ly, _, _) = laid.rect(layer).unwrap_or((0.0, 0.0, 0.0, 0.0))
      match at(laid) {
        Some((x, y, _, _)) => (x - ring_room - lx, y - ring_room - ly)
        None => (0.0, 0.0)
      }
    }))
    |> ignore
    agent_avatar_node(f, fn() { a().map(fn(a) { a.maker }).unwrap_or("") }, fn() {
      a().map(fn(a) { a.runtime }).unwrap_or("")
    }, fn() { "" })
    |> ignore
    // (its ring over it: stepping round while it works, still and whole while it waits on what it started)
    f.box(fn(ring) {
      ring.over(Is(true)) |> ignore
      ring.pick(fn() { a().map(fn(a) { a.wait is Some(_) }).unwrap_or(false) }, fn(w, waiting) {
        if waiting {
          w
          .width(Is(Some(ring_side)))
          .height(Is(Some(ring_side)))
          .radius(Is(ring_side / 2.0))
          .edge(By(fn() { (ring_stroke, @ui.tree_theme().color(Line)) }))
          |> ignore
        } else {
          @sf.segments_node(w, ring_side, ring_stroke, fn() { @sf.theme().p.accent }, fn() { @sf.theme().p.bg })
          |> ignore
        }
      })
    })
    |> ignore
  })
}

///|
/// Where what flies in chat `r`'s page goes (chat_flight_layer_made), while its page is made.
pub fn chat_flight_layer(r : ChatRef) -> @view.View? {
  chat_flight_layers.get(r.station + "\u{1}" + r.session)
}

///|
/// What a chat's list's rows are taken from (chat_list_node's `listed`): its entries and view as the core says them,
/// the words sent flying (each the same only as the very one), how many times the lines staying a moment changed.
priv struct ListedFrom {
  cv : ChatView?
  f : SendFlight?
  lingered : Int
  emitted : Int
}

///|
impl Eq for ListedFrom with equal(self, other) {
  self.lingered == other.lingered &&
  self.emitted == other.emitted &&
  (match (self.cv, other.cv) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => true
    _ => false
  }) &&
  (match (self.f, other.f) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => true
    _ => false
  })
}

///|
/// How far from what covers a chat's list a card's field in it is kept with the keyboard up (the old list's).
let field_held_room : Double = 16.0

///|
/// What floats over list `v`'s foot (its decision bell, its way to the newest) made by `make` in a node over all of it,
/// laid out over what covers its foot as what holds the list gave it (Layout::given_foot: the composer's room, with
/// the list's own lift), less `less` of that (the lift, less how far over the composer it stands): in the same layout,
/// nothing of the composer read back.
fn floats_over(v : @view.View, less : () -> Double, make : (@view.View) -> Unit) -> Unit {
  v.box(fn(o) {
    o.over(Is(true)) |> ignore
    let f = o.box(make)
    o.layout_box(By(less), fn(l, less) {
      let foot = l.given_foot().map(fn(g) { g.1 }).unwrap_or(0.0)
      l.measure(f, l.width, height=dmax(0.0, l.height - dmax(0.0, foot - less))) |> ignore
      l.place(f, 0.0, 0.0)
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far past its column a chat's row lets what it holds scroll across (a message's tables): the row, worked out from
/// how wide it is laid out (row_side_in), as it is laid out (TableBleed's BleedBy).
// kept across runs: the key each row lends; its value belongs to that row and is let go with it
let chat_row_bleed : @view.Lent[(@view.View, (Double) -> Double)] = @view.Lent::new()
