// A chat's messages (chat_list.mbt's chat_list) made once in the window's tree: its rows by their keys in a page's list
// that holds those in sight alone (View::scrolls_window), from its end (at its foot while they are fewer than fill it,
// shown at its end, kept there as what comes comes while it is there); its column 760 wide at most in the pane's middle,
// 16 in where it is narrow; the rows the gap apart, one sent soon after the one before 4 under it; its room over the
// first row (the bar's) and under the last (the composer's) as they change. Each row's contents are retained nodes
// for its kind of message, activity, card or list marker.

///|
/// Chat `r`'s list in `v`: `view` as the core says it now (none while it is read the first time), its rows read by
/// index (sfbase ChatRows: a message come is that row's change alone),
/// `top` the room over its first row, `foot` under its last (the composer's), `core` the settings' over its workspace;
/// `follows` said whether it is kept at its end, as that changes.
pub fn chat_list_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  top : () -> Double,
  foot : () -> Double,
  core : Core,
  foot_gap? : Double = 0.0,
  follows? : @signals.Signal[Bool] = @signals.signal(true, same=fn(a, b) { a == b }),
) -> ChatListNode {
  let rk = r.station + "\u{1}" + r.session
  let scroll = @view.Scroll::list()
  // (its width as last laid out)
  let list_w = fn() { v.laid_size_told().map(fn(z) { z.0 }) }
  // The last row stands above the decision bell when the core says that it can cover the list's end (the old
  // list's ask_clear). The bell itself stays over the composer's room, even while its post is elsewhere in the list.
  let clear_foot = fn() {
    foot() + (if view().map_or(false, @sfbase.ask_clears) { float_lift + float_side } else { 0.0 })
  }
  // (a card's field with the focus kept in view with the keyboard up, as the window grows shorter under it: out from
  // under the bar and the composer, 16 clear of each, its foot giving way to its top where it does not fit between
  // them; with touch, as the keyboard comes up on asking (the old list's list_holds_field))
  v.reacts(fn() { (v.laid_window_told(), top(), clear_foot()) }, fn(now) {
    guard now.0 is Some((_, ly, _, lh)) &&
      !@sf.pointer_rests() &&
      @ui.current().ime_inset() > 0.0 &&
      @ui.focused_field_in() is Some((island, (_, fy, _, fh))) &&
      v.tree.holds(v.id(), island) &&
      v.tree.view_of(island) is Some(iv) else {
      return
    }
    let (_, iy, _, _) = iv.laid_window_now()
    let y = iy + fy
    let d = dmin(ly + lh - now.2 - field_held_room - (y + fh), 0.0)
    let d = dmax(ly + now.1 + field_held_room - y, d)
    if d.abs() > 0.5 {
      scroll.glide_to(scroll.at(v.tree) - d, glide=false)
    }
  })
  // (shown while it is laid out somewhere: what comes out of its avatars played on then, linger_tick)
  let shown_by = fn() { !v.shown_nowhere() }
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
  // (narrow: 700 or less, as the list is laid out: 20 apart, the pictures at their heads' start)
  let narrow = fn() {
    list_w().map(fn(w) { w <= chat_narrow_w }).unwrap_or(true)
  }
  // (the same as the list was last laid out, kept where its layout reads it: a layout reads no signal)
  let narrow_laid = Ref(true)
  v.reacts(fn() { narrow() }, fn(now) { narrow_laid.val = now })
  // (an agent's message waiting its turn to come out of its avatar not in it yet: emit.mbt's emit_held)
  let em = @sfbase.emits_of(rk)
  let rd0 = @sfbase.reading_of(rk)
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
  // (the same, read where no signal may be: the list's layout's)
  let rows_current : Ref[@sfbase.ChatRows] = Ref(@signals.untracked(fn() { rows_now.get() }))
  v.owns(fn() { rows_current.val.let_go() }) |> ignore
  v.reacts(fn() {
    em.read()
    ListedFrom::{ cv: view(), f: @sfbase.send_flight.get(), lingered: rd0.linger_said.get(), emitted: em.said.get() }
  }, fn(now) {
    let { cv, f, .. } = now
    guard cv is Some(cv) else { return }
    @sfbase.chat_take(@ui.current(), rk, rd0, cv, shown=shown_by(), in_front=app_in_front())
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
    rows_current.val = cr
    rows_now.set(cr)
  })
  // (in from the pane's sides to the column (row_side's): 16 narrow (as wide as the composer's words beside the
  // system's bars), else the column 760 wide at most in its middle (48 in beside the system's bars))
  let side = fn() {
    let w = match list_w() { Some(w) => w; None => v.window().0 }
    row_side_in(w)
  }
  // (the message the unread line is over, followed as that changes alone)
  let line_seq = @signals.computed(fn(_) { view().bind(fn(cv) { cv.unread_line }) }, same=fn(a, b) { a == b })
  // (a message's row: the unread line over it where it is over it, its own gap under the line (joined, 4; else the
  // rows' gap), the message (`body`), where it was sent elsewhere under it, each the rows' gap under the one before:
  // what were rows of their own, each its own)
  let gap_of = fn(joined : Bool) {
    if joined { joined_gap } else if narrow() { list_gap_narrow } else { list_gap }
  }
  // (`lead` the room over the first of them, the row's (the line's, else the message's); `ground` the message's, lit
  // as a row is (its menu open, gone to) over the room over it and it alone, as the row it was)
  // (in from the pane's sides to the column, `top` over it: a row's room; a message's parts each their own, the band
  // of its own part across the whole of it as the row's was)
  let row_room = fn(node : @view.View, top : () -> Double) {
    node.padding(By(fn() { let s = side(); (s, top(), s, 0.0) })) |> ignore
  }
  let parts = fn(
    row : @view.View,
    lined : () -> Bool,
    joined : () -> Bool,
    elsewhere : () -> Array[Elsewhere],
    here : () -> MessageHere,
    lead : () -> Double,
    ground : () -> Int64,
    body : (@view.View) -> Unit,
  ) {
    row.show(lined, fn(l) {
      row_room(l, lead)
      l.box(fn(b) { unread_line_node(b) }) |> ignore
    })
    row.box(fn(said) {
      row_room(said, fn() { if lined() { gap_of(joined()) } else { lead() } })
      said.ground(By(ground)) |> ignore
      said.box(body) |> ignore
    })
    |> ignore
    row.pick(fn() { elsewhere().length() }, fn(sent, n) {
      for i in 0..<n {
        // (the gap over it its own box's: what it draws in its margin (its picture) placed from its top, as a row's)
        sent.box(fn(g) {
          row_room(g, fn() { gap_of(false) })
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
    lead : () -> Double,
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
  let over = fn(e : Entry, i : Int) -> Double {
    match gap_kind(e, i) {
      0 => 0.0
      1 => joined_gap
      _ => if narrow() { list_gap_narrow } else { list_gap }
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
  let sized = rows_sized(row_sizes, v, fn() { rows_now.get() }, rows_current, watched=fn() { !view().map_or(false, fn(cv) { cv.newer }) },
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
                Some(@sfbase.pose_ms(t.pose, t.from))
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
    lead=over,
    lead_in_layout=fn(e, i) {
      let kind = gap_kind(e, i)
      fn() {
        if kind == 0 { 0.0 } else if kind == 1 { joined_gap }
        else if narrow_laid.val { list_gap_narrow } else { list_gap }
      }
    },
    own=fn(e) { e is Foot },
  )
  // (the row keyed `k` and where it is among them (one going too), followed by what it shows and by which is the first
  // under the bar (no gap over it))
  let row_of = fn(k : String) -> (Entry, Int)? {
    rows_now.get().lead() |> ignore
    (sized.item_of)(k)
  }
  // (the rows made now, by their keys: where each is, what is read)
  let row_views : Map[String, @view.View] = {}
  let row_rects : @sf.LiveMap[String, (Double, Double, Double, Double)] = @sf.LiveMap::new()
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
      rooms=sized.room_now,
      // The flying copy needs its real landing before the glide brings the row into sight.
      kept_keys=fn() { @sfbase.flight_of(draft).map(fn(f) { [f.key] }).unwrap_or([]) },
      // (new to it: said while it shows, an agent starting, sent from here; not what is caught up on, at once)
      // (the bar over its top: what comes taller than what shows is read from its top under it)
      cover=top,
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
        match @signals.untracked(fn() { row_of(k) }) {
          Some((Top, _)) => { slot.height(By(fn() { Some(top()) })) |> ignore; return }
          Some((Foot, _)) => { slot.height(By(fn() { Some(clear_foot() + foot_gap) })) |> ignore; return }
          _ => ()
        }
        // (its node while it is made, what is read of where it is: the reading's)
        row_views[k] = slot
        slot.owns(fn() {
          match row_views.get(k) {
            Some(x) if physical_equal(x, slot) => { row_views.remove(k); row_rects.remove(k) }
            _ => ()
          }
        })
        |> ignore
        slot.reacts(fn() { slot.laid_window_told() }, fn(rect) {
          match rect {
            Some(rect) => row_rects.set(k, rect)
            None => row_rects.remove(k)
          }
        })
        // (its room: in from the pane's sides to the column, the gap over it; under the bar over the first, the
        // composer under the last)
        slot
        .padding(By(fn() {
          // (a message's row: the room over it its parts', said_parts')
          match row_of(k) {
            Some((Said(_) | Out(_), _)) => (0.0, 0.0, 0.0, 0.0)
            r => {
              let gap = match r { Some((e, i)) => over(e, i); None => 0.0 }
              let side = side()
              (side, gap, side, 0.0)
            }
          }
        }))
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
        let said_lead = fn() {
          match row_of(k) {
            Some((e, i)) => {
              let kind = gap_kind(e, i)
              if kind == 0 { 0.0 } else { gap_of(kind == 1) }
            }
            None => 0.0
          }
        }
        // (what it is: a message (message_node.mbt), what was sent from here, an agent at work, the line over what is new,
        // the pages coming, a chat with nothing in it, where it stands, what was said elsewhere (chat_rows_node.mbt);
        // made again as which of those it is changes)
        let here = fn() {
          match view() {
            Some(cv) => here_of(r, cv, rk, @sfbase.turns_of(rk), @sfbase.emits_of(rk), None, core, inline=narrow(), gutter=@signals.untracked(side))
            None => here_of(r, @sfbase.chat_view_made(Json::object({})), rk, @sfbase.turns_of(rk), @sfbase.emits_of(rk), None, core, inline=narrow(), gutter=@signals.untracked(side))
          }
        }
        // (what it is as it was last found: a row going not found among them for a moment, as its list takes its going,
        // keeps showing what it showed)
        let kind_was = Ref(0)
        slot.pick(fn() {
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
      },
    )
    |> ignore
  })
  |> ignore
  // (what flies out of an activity's picture to its message and back, over the rows, under the composer and the bar)
  v.box(fn(fl) {
    fl
    .over(Is(true))
    .width(By(fn() { v.laid_size_told().map(fn(z) { z.0 }) }))
    .height(By(fn() { v.laid_size_told().map(fn(z) { z.1 }) }))
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
  // where the reader is (read_place's, as the list lays its rows out, never read back into what it draws): what of the
  // messages is seen whole between the bar's foot and the composer's room, the message at its top and how far below
  // the list's top its top is, the message at its foot; told the core as the list comes to rest (tell_place) and what
  // is read (tell_focus)
  @ui.read_drawn(v, fn() {
    let in_sight = shown.get().map(fn(k) {
      let e = row_of(k).map(fn(r) { r.0 })
      let seq = match e { Some(Said(m)) => m.seq; _ => -1.0 }
      (seq, row_rects.get(k), e is Some(State(_, _, _)))
    })
    (v.laid_window_told(), top(), clear_foot(), in_sight, scroll.glides_till_told(), follows.get(),
      view().map(fn(cv) { cv.newer }), (sized.opening)(), v.shown_nowhere())
  }, fn(now) {
    let (rect, bar, foot, in_sight, moving, at_end, _, opening, hidden) = now
    guard !hidden && rect is Some((_, list_y, _, list_h)) else { return }
    guard @signals.untracked(view) is Some(cv) else { return }
    let rd = rd0
    let room_top = list_y + bar
    let room_foot = list_y + list_h - foot
    let mut top_seq = -1.0
    let mut top_off = 0.0
    let mut bottom_seq = -1.0
    let mut state_seen = false
    for (seq, row_rect, state) in in_sight {
      match row_rect {
        // (in view: the rows the list holds past its edges, made to come in, none of what is read: read_place's
        // first and last in view)
        Some((_, y, _, h)) if y + h > list_y && y < list_y + list_h => {
          if seq >= 0.0 {
            if top_seq < 0.0 {
              top_seq = seq
              top_off = y - list_y
            }
            bottom_seq = seq
            if !cv.newer && !opening && y >= room_top - 0.5 && y + h <= room_foot + 0.5 && seq > rd.seen_whole {
              rd.seen_whole = seq
            }
          }
          if state { state_seen = true }
        }
        _ => ()
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
  })
  // (away from its end, or short of the chat's: told the page's reading, as the old list told it, Reading's `jump`)
  v.reacts(fn() { !follows.get() || view().map(fn(cv) { cv.newer }).unwrap_or(false) }, fn(away) {
    rd0.jump = away
    // Following new rows is the reader's intent, even while their opening rooms mean the end is not yet seen.
    // Keep the avatar's turn watched through that movement, as the old list's following_row does.
    rd0.following_row = !away
  })
  // what waits to be decided and does not show (ToAsk: the core's `asks`): a bell over the list right over the send
  // button, over the way to the end where both show; pressed, the chat goes to the first one's post, the next one's the
  // next time. Out of view once the list is laid out (nothing known to be out of view before).
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
    !in_sight.iter().any(fn(k) {
      match row_of(k) {
        Some((Said(m), _)) => asks.contains(m.seq)
        _ => false
      }
    })
  }
  v.reacts(fn() { asking() }, fn(a) { rd0.ask = a })
  v.box(fn(f) {
    f
    .over(Is(true))
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .padding(By(fn() {
      let w = v.laid_size_told().map(fn(z) { z.0 }).unwrap_or(0.0)
      let above = !follows.get() || view().map(fn(cv) { cv.newer }).unwrap_or(false)
      (0.0, 0.0, (w - composer_width(w)) / 2.0 + float_in, foot() + float_lift + (if above { float_above } else { 0.0 }))
    }))
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
  v.box(fn(f) {
    f
    .over(Is(true))
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .padding(By(fn() {
      let w = v.laid_size_told().map(fn(z) { z.0 }).unwrap_or(0.0)
      (0.0, 0.0, (w - composer_width(w)) / 2.0 + float_in, foot() + float_lift)
    }))
    |> ignore
    f.show(fn() { !follows.get() || view().map(fn(cv) { cv.newer }).unwrap_or(false) }, fn(b) {
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
      .shadow(By(fn() {
        let (blur, dy) = @ui.Shadow::blur_y(Md)
        (blur, dy, @ui.tree_theme().shadow)
      }))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.toLatest"))) }))
      |> ignore
      @sf.presses_node(b, fn() {
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
      })
      @sf.icon_node(b, "arrow-down", float_icon, By(fn() { @sf.theme().p.text })) |> ignore
      b.show(fn() { view().map(fn(cv) { cv.newer && cv.unread > 0.0 }).unwrap_or(false) }, fn(n) {
        @sf.words_node(n, fn() {
          @sf.t("web-main.chat.newMessages", args=[("n", view().map(fn(cv) { cv.unread.to_int() }).unwrap_or(0).to_string())])
        }, fn() { float_count }) |> ignore
      })
    })
  })
  |> ignore
  {
    to_latest: to_end,
    follows,
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
/// How wide the list's column is at most, in the pane's middle (Chat.css.ts chatColumn: 760).
let chat_column_most : Double = 760.0

///|
/// A chat's list made once (chat_list_node): to its end, following it again (glided there, at once from further than
/// chat_glide_rows rows off); whether it follows its end; where what was sent to its row `key` lands (by the key the
/// list has it by: what was sent from here by the key it was sent as), followed.
pub(all) struct ChatListNode {
  to_latest : () -> Unit
  follows : @signals.Signal[Bool]
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
    let at = fn() {
      f.drawn_at() |> ignore
      let agents = match view() {
        Some(v) => v.agents.map(fn(a) { a.key })
        None => []
      }
      // The flight's clock and both endpoints belong to this frame. A row's placement can change after the
      // clock was read; its published geometry must still invalidate the copy's position in that same pass.
      em.read()
      @sfbase.emit_flight(@ui.current(), rk, em, agents)
    }
    let a = fn() { flying() }
    f
    .over(Is(true))
    .width(Is(Some(ring_side)))
    .height(Is(Some(ring_side)))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .alpha(By(fn() { if at() is Some(_) { 1.0 } else { 0.0 } }))
    .offset(By(fn() {
      let (lx, ly, _, _) = layer.drawn_window_told().unwrap_or((0.0, 0.0, 0.0, 0.0))
      match at() {
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
