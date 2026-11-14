// A chat's row in the chats' lists (chat_row.mbt's) as a node of the window's tree, made once for its chat and
// following what the core says of it: its state's mark before its title (bolder while something in it is unread), what
// marks it (failed a moment ago, its station away, from Slack, opened by another chat, its station's mark), where it
// stands or the last thing said, who is in it; pressed, its chat; with a mouse, pointed at, its time in that place and
// 归档 at its top right, right clicked its menu at the pointer; with a finger, held a while its time, held long its
// menu. What only those read (its menu's, its swipe's question, its time in words) is its chat's whole row
// (@sfbase.whole_row: the list's rows are made without it), asked as the hand comes to it (a pointer down on it, a
// pointer coming to rest over it, a swipe setting out), held while what reads it is open: what opens waits for it and
// opens whole the frame it is answered.
//
// Archived from its row of a list made once (its swipe, its 归档 key, its menu: archive_row's `here`), what the row
// uncovers as it goes off to the left stays in its place and says so (its tray: tray_node): 归档 docked at its start
// with a check before it, 撤销 come in at its end with the row's way out. 撤销 brings the row back over it from the
// left; its time out, the line leaves the list as a row gone does (RowsMotion). Every place in it is a function of how
// far the row has gone, so its way back is its way out run backwards: nothing fades, nothing is put in another's place.

///|
/// The row of the chat `item` says as it is now (chat_row's) in `parent`: `lead` whose pictures lead, `on` its chat the
/// page in view, `list_ground` the list's ground (round its faces), `more` another row under it, `at` where its list
/// stands; tips in `tips`, pictures asked for on `stint`. `kept`: in a list made once, whether its chat is gone from that
/// list, its line kept (its tray offering 撤销 there, then closing): its archive said there (archive_row's `here`). The
/// row's node.
pub fn chat_row_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  item : () -> ChatItem,
  lead : String,
  on : () -> Bool,
  at : @sf.ListAt,
  stint : () -> Int,
  list_ground? : () -> Int64 = fn() { @sf.theme().p.bg },
  more? : Bool = false,
  kept? : () -> Bool,
) -> @view.View {
  let t = fn() { @sf.theme() }
  // (a finger rests on nothing: a press reads ahead, a hold shows the time; a pointer's over it shows them)
  let finger = !@sf.pointer_rests()
  let first = @signals.untracked(item)
  // (which chat it is: another's as the row is taken for another, a list's rows not made and let go as it is scrolled
  // (View::scrolls_window's reused))
  let key = fn() { @sfbase.row_name(item()) }
  // (made again for its chat, asked back say: whatever swiped it off before is over)
  rows.swiped_off.remove(swiped_key(first))
  let r = fn() { row_ref(item()) }
  let offline = fn() { item().offline is Some(_) }
  let menu_ok = fn() { item().offline is None && !item().pending }
  let menu_on = fn() { row_menu_open(item()) }
  // (its title a field in its place, from a mouse's 重命名: rename_node)
  let renaming = fn() { row_renaming.get() == key() }
  let failed = fn() { row_failed(src, item()) }
  // (held by a finger a while: its time shows)
  let held : @signals.Signal[Bool] = @signals.signal(false)
  // (pressed by a finger, shown so once it has stayed tap_indication_ms: one going on to scroll lights nothing)
  let press_lit : @signals.Signal[Bool] = @signals.signal(false)
  let press_due : Ref[() -> Unit] = Ref(fn() {  })
  // (what a finger pressing it read ahead, let go as it is let go without opening it: a hold)
  let primed : Ref[@sfbase.TopicLease?] = Ref(None)
  let opened = Ref(false)
  // (its chat's whole row, asked as the hand comes to it: what it is held for, and what waits for it to be answered)
  let whole = @sfbase.WholeAsk::new()
  let pressing = Ref(false)
  let hovering = Ref(false)
  // (a press waiting for it: sfbase's press_wait, while what it was pressed in stays as it was)
  let whole_wait : Ref[@sfbase.PressWait?] = Ref(None)
  let whole_waits = fn() { whole_wait.val is Some(w) && w.waiting() }
  let ask_whole = fn() { whole.ask(src, @signals.untracked(item)) }
  // (what reads it done with: hovered no more, let go of, its menu gone, nothing waiting for it)
  let whole_idle = fn() {
    @signals.untracked(fn() {
      if !pressing.val && !hovering.val && !menu_on() && !whole_waits() {
        whole.let_go()
      }
    })
  }
  // (`run` with its chat's whole row: now where it is answered, else the frame it is, while what it was pressed in
  // stays as it was (sfbase's press_wait); else nothing, `gone` done, and what it asked let go of)
  let then_whole = fn(run : (ChatItem) -> Unit, gone : () -> Unit) {
    ask_whole()
    match whole_wait.val {
      Some(w) => {
        whole_wait.val = None
        w.end()
      }
      None => ()
    }
    let w = @sfbase.press_wait(fn() { @sfbase.whole_answered(src, item()) }, fn() {
      match @signals.untracked(fn() { @sfbase.whole_row(src, item()) }) {
        Some(i) => run(i)
        None => ()
      }
      whole_idle()
    }, let_go=fn() {
      gone()
      whole_idle()
    })
    whole_wait.val = if w.waiting() { Some(w) } else { None }
  }
  // (what waits for it ended with the row: gone, or taken for another chat, what it asked let go of by what follows,
  // what the row showed put back as it is made anew)
  let whole_wait_gone = fn() {
    match whole_wait.val {
      Some(w) => {
        whole_wait.val = None
        w.end()
      }
      None => ()
    }
  }
  // (where the last press went down, and its state line: pressed there, while the core says which message that is
  // about and nothing in it is unread, its chat goes there as it opens: ChatMark.tsx jumpFromLine)
  let down_at : Ref[(Double, Double)?] = Ref(None)
  let state_at : Ref[@view.View?] = Ref(None)
  let press = fn() {
    let i = @signals.untracked(item)
    opened.val = true
    let r = row_ref(i)
    // A quick tap has no prefetch yet. Keep a reader from the open event until the page has its own, even if the
    // graph that first read the chat changes in a core reply before that page's first frame.
    let early = match primed.val {
      Some(reader) => Some(reader)
      None if !src.read_only => Some(src.lease_topic("chat", chat_params(r)))
      None => None
    }
    primed.val = None
    let reader = match early { Some(reader) => @sfbase.prepare_chat_handoff(reader); None => None }
    let on_line = match (down_at.val, state_at.val) {
      (Some((x, y)), Some(l)) if l.alive() => {
        let (lx, ly, lw, lh) = l.placed_window_now()
        x >= lx && x < lx + lw && y >= ly && y < ly + lh
      }
      _ => false
    }
    match i.state_about {
      Some(seq) if on_line && !i.unread && i.thread is Some(_) => @sfbase.go_to(r, seq)
      _ => ()
    }
    open_page(Chat(r))
    match reader { Some(reader) => @sfbase.handoff_chat_open(r, reader); None => () }
  }
  parent.box(fn(slot) {
    // (in its slot, cut to its corners where its list stands: moved across in it, its tray beside it; a finger's in a
    // box of its own, its slot lifted round it; a mouse's its slot itself, the room under it its margin)
    @sf.style_node(slot, fn() {
      if finger {
        if more {
          @sf.list_more(at)
        } else {
          row_last
        }
      } else if more {
        @sf.list_row_slot(at).then(@ui.style(mb?=@sf.list_more(at).base.pb))
      } else {
        @sf.list_row_slot(at)
      }
    })
    let swipes = finger && @sf.more_held()
    let holder = if finger {
      slot.box(fn(sw) { @sf.style_node(sw, fn() { @sf.list_row_slot(at) }) })
    } else {
      slot
    }
    let row = holder.box(fn(_) {  })
    row.owns(fn() {
      match primed.val {
        Some(reader) => { primed.val = None; reader.cancel() }
        None => ()
      }
    }) |> ignore
    // held by a finger, it lifts off the list toward the finger (iOS's context menu): a little as its time shows, all
    // the way once its menu opens, back down as the menu goes (@sf.lift_of's), a card of the raised ground over the
    // menu's scrim, drawn in from the screen's sides (row_lifted, @sf.lift_over's)
    let lift = @sf.EdgeWay::new(0.0)
    let lifted = fn() { if finger { dmin(1.0, dmax(0.0, lift.shown(slot))) } else { 0.0 } }
    if finger {
      slot.reacts(
        fn() {
          if menu_on() {
            1.0
          } else if held.get() {
            @sf.lift_held
          } else {
            0.0
          }
        },
        fn(to) { lift.go_by(slot, to, @motion.lift_spring) },
      )
      slot
      .ground(By(fn() {
        let ink = lifted()
        if ink > 0.0 {
          @sf.alpha(t().p.raised, ink)
        } else {
          0L
        }
      }))
      .radius(Is(@sf.row_corner))
      .shadow(By(fn() {
        let ink = lifted()
        let r = @sf.held_raised
        (r.sigma * ink, r.dy * ink, @sf.alpha(r.color, ink))
      }))
      .scale(By(fn() { 1.0 - row_lift_inset * lifted() }))
      .over_scrim(By(fn() { lifted() > 0.0 }))
      |> ignore
    }
    let menu_now = fn(i : ChatItem, x : Double, y : Double, from_row : Bool) {
      let from = if from_row {
        let (x, y, w, h) = row.placed_window_now()
        @sf.Beside::At(x, y, w, h)
      } else {
        @sf.at_point(x, y)
      }
      // (held by a finger: felt as it opens)
      if from_row {
        @ui.haptic(LongPress)
      }
      @sf.menu(chat_menu_items(src, i, share_from=fn() { from }, here=kept is Some(_)), from~)
      rows.menu_for = @sfbase.row_name(i)
      rows.menu_serial = @sf.last_presented()
    }
    // (its menu is its whole row's: opened once that is answered, whole)
    let open_menu = fn(x : Double, y : Double, from_row : Bool) {
      guard @signals.untracked(menu_ok) else { return }
      then_whole(fn(i) { menu_now(i, x, y, from_row) }, fn() {  })
    }
    // (moved left in its slot, by so many points (a finger's swipe: swipe_node's; archived from it: off to the left),
    // and what it uncovers there: its tray)
    let tray = Tray::new()
    // (a mouse's: pointed at in its slot, its 归档 key there too, beside the row in what its tray is made in)
    let hover_in = if finger { row } else { holder }
    let hover = fn() { !finger && (@sf.lit_in_node(hover_in) || menu_on()) }
    // (said by its whole row: shown once that is answered, held meanwhile by what reads it here)
    let shows_time = fn() { (hover() || held.get() || (finger && menu_on())) && @sfbase.whole_answered(src, item()) }
    let archive_key = fn() { !finger && menu_ok() && hover() && !renaming() && !tray.parked.get() }
    // its ground: a finger's, held or its menu open the ink at 5%, its chat in view the selected one's; a mouse's, the
    // pointer's eased in and out, the selected one's while its chat is in view (nav_ground_by's)
    // a finger's: its chat's page in view, its ground on; gone back from it, the ground stays while the page slides off
    // and a while after (left_lit_ms), then fades (left_fade_ms); one row so, the chat last in view; in a side column,
    // beside the chat, it fades as a mouse's does (dur_ms), and the row pressed goes from its press's ground to the
    // selected one's over dur_ms, never through none (the user, 2026-11-07: active 那个状态好像切换的时候颜色会稍微有些闪)
    let left = @sf.EdgeWay::new(0.0)
    // (a finger's press's ground, beside the chat: on at once, off over dur_ms)
    let pressed = @sf.EdgeWay::new(0.0)
    let off = tray.off
    let hand = @sf.EdgeWay::new(0.0)
    let chosen = @sf.EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
    let ground = fn() {
      let p = t().p
      if finger {
        // (lifted, its card is its ground: the row's own drawn by the card round it, not square inside it)
        if lifted() > 0.0 {
          0L
        } else if held.get() || menu_on() || (at == Whole && press_lit.get()) {
          @sf.alpha(p.text, 0.05)
        } else if at != Whole && (pressed.shown(row) > 0.0 || chosen.shown(row) > 0.0 || left.shown(row) > 0.0) {
          let o = dmax(chosen.shown(row), left.shown(row))
          @sf.over(@sf.alpha(p.text, 0.05 * pressed.shown(row) * (1.0 - o)), @sf.alpha(p.selected, o))
        } else if on() {
          p.selected
        } else {
          let share = left.shown(row)
          if share > 0.0 {
            @sf.alpha(p.selected, share)
          } else if swipes && off.shown(row) < 0.0 {
            // moved across: over 归档's words, which it uncovers as it goes
            p.bg
          } else {
            0L
          }
        }
      } else {
        let h = hand.shown(row)
        let o = chosen.shown(row)
        if h <= 0.0 && o <= 0.0 {
          0L
        } else {
          @sf.over(@sf.alpha(p.hover, h * (1.0 - o)), @sf.alpha(p.selected, o))
        }
      }
    }
    // (in a side column who is in it stands in the row's foot's end corner, placed there by the corner rule; across the
    // whole screen at its second line's end; the row pointed at says when instead)
    let cornered = fn() { at != Whole && !shows_time() && row_aside_shows(item(), lead) }
    let face_ground = fn() { @sf.over(list_ground(), if lifted() > 0.0 { t().p.raised } else { ground() }) }
    @sf.list_row_node(
      row,
      at,
      ground~,
      high=true,
      // (归档 over its first line's end: Sidebar.css.ts rowArchive, 24)
      end_room=fn() { if archive_key() { @sf.row_keys_room(1) } else { 0.0 } },
      corner?=if at != Whole {
        Some(fn(k : @view.View) { row_aside_node(k, src, tips, item, lead, face_ground, stint) })
      } else {
        None
      },
      corner_shown=cornered,
      corner_w=fn() { row_aside_w_node(row, item(), lead) },
      // (in the slot it moves across in, every row: its corners the slot's, its own ground square)
      slotted=true,
      end_slot=kind_slot_w,
      corner_end=fn() { row_aside_end_w(item(), lead) },
      fn(h) {
        let tone = fn() { @sfbase.row_tone(item()) }
        // (the show's own box its slot: a box a part, no box round one)
        h.show(fn() { tone() != "" && !renaming() }, fn(m) {
          @sf.style_node(m, fn() { mark_slot }, in_row=true)
          chat_mark_node(m, tone)
        })
        h.pick(renaming, fn(n, on) {
          // (what is left of the line, from none: its title cut short in it, what stands at its end kept whole)
          n.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          if on {
            rename_node(n, src, item, at)
            return
          }
          @sf.words_node(n, fn() {
            if item().hidden == Some(true) { item().title + " · " + @sf.t("web-main.filter.hidden") } else { item().title }
          }, fn() {
            let look = t().chat_list
            let title = if item().unread { look.title_unread } else { look.title }
            if offline() || item().settled {
              title.then(title_dim)
            } else {
              title
            }
          })
          |> ignore
        })
        // failed a moment ago: a red mark, why on it
        h.show(fn() { failed() is Some(_) }, fn(s) {
          @sf.style_node(s, fn() { kind_slot }, in_row=true)
          let why = fn() { failed().unwrap_or("") }
          s.says(By(fn() { Some(@view.said(Image, label=why())) })) |> ignore
          chat_mark_node(s, fn() { "alert" })
          @sf.tip_node(tips, s, why, within=true) |> ignore
        })
        // its station offline, or its link coming back: unplugged (its update's mark while it updates); one from
        // elsewhere (Slack, Feishu) says so, by its platform's mark
        let away = fn() {
          match (item().offline, item().reconnecting) {
            (Some(why), _) | (None, Some(why)) => why
            _ => ""
          }
        }
        let away_which = fn() {
          if away() != "" {
            if item().updating { 2 } else { 1 }
          } else if item().connect {
            if item().origin_kind == "comma" { 4 } else { 3 }
          } else {
            0
          }
        }
        h.pick(away_which, fn(s, which) {
          guard which != 0 else { return }
          @sf.style_node(s, fn() { kind_slot }, in_row=true)
          let said = fn() {
            if which >= 3 {
              if item().origin_text != "" {
                item().origin_text
              } else {
                "Slack"
              }
            } else {
              away()
            }
          }
          s.says(By(fn() { Some(@view.said(Image, label=said())) })) |> ignore
          match which {
            2 => @sf.updating_mark_node(s, kind_glyph, fn() { t().p.subtle })
            1 => @sf.icon_node(s, "unplug", kind_glyph, By(fn() { t().p.subtle })) |> ignore
            // (Comma's mark is one colour: in the page's ink, as a one-colour maker's is)
            4 => @sf.drawable_node(s, "comma", kind_mark, tint=fn() { Some(t().p.text) }) |> ignore
            _ => @sf.origin_mark_node(s, fn() { item().origin_kind }, kind_mark) |> ignore
          }
          @sf.tip_node(tips, s, said, within=true) |> ignore
        })
        // opened by another chat's agent: marked so, that chat named on it
        h.show(fn() { item().opener is Some(_) && !renaming() }, fn(s) {
          @sf.style_node(s, fn() { kind_slot }, in_row=true)
          let said = fn() {
            match item().opener {
              Some(o) => if o.archived { o.text + " · " + o.note } else { o.text }
              None => ""
            }
          }
          s.says(By(fn() { Some(@view.said(Image, label=said())) })) |> ignore
          @sf.icon_node(s, "spawned", kind_glyph, By(fn() { t().p.subtle })) |> ignore
          @sf.tip_node(tips, s, said, within=true) |> ignore
        })
        // the station it runs on, by its mark: last, in the same column at every row's end
        // (as big as its kind of mark is: made again where another chat's is of another, the row taken for that one)
        h.pick(fn() {
          if @sf.has_station_mark(item().station_emoji, item().station_icon) && !renaming() {
            Some(kind_mark_of(item().station_icon))
          } else {
            None
          }
        }, fn(k, size) {
          guard size is Some(size) else { return }
          let s = k
          @sf.style_node(s, fn() { kind_slot }, in_row=true)
          s.says(By(fn() { Some(@view.said(Image, label=item().station_name)) })) |> ignore
          @sf.station_mark_node(
            s,
            fn() { item().station_emoji },
            fn() { item().station_icon },
            size,
            fn() { if offline() { t().p.subtle } else { t().p.muted } },
            stint,
          )
          @sf.tip_node(tips, s, fn() { item().station_name }, within=true) |> ignore
        })
      },
      fn(u) {
        @sf.list_row_line_node(u, fn(m) {
          let state = fn() {
            match item().state_text {
              Some(s) => Some(s)
              None => item().decision_text
            }
          }
          m.box(fn(s) {
            s.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            s.pick(fn() { state() is Some(_) }, fn(p, has) {
              if has {
                p.box(fn(b) {
                  state_at.val = Some(b)
                  @sf.style_node(b, fn() { state_box })
                  state_line_node(
                    b,
                    tips,
                    fn() { state().unwrap_or("") },
                    fn() { @sfbase.row_lead(item()) },
                    fn() { item().state_lead_text },
                    fn() { item().state_rest },
                    fn() { item().unsent },
                  )
                })
                |> ignore
              } else {
                @sf.words_node(p, fn() { item().last.unwrap_or("") }, fn() { t().chat_list.last }) |> ignore
              }
            })
          })
          |> ignore
          // (its day and time while pointed at, held or its menu open; else, across the whole screen, who is in it)
          m.pick(fn() { if shows_time() { 1 } else if at == Whole { 2 } else { 0 } }, fn(e, which) {
            match which {
              1 =>
                e.box(fn(time) {
                  let said = fn() { @sfbase.whole_row(src, item()).unwrap_or(item()) }
                  @sf.words_node(time, fn() { said().ago }, fn() { row_time }) |> ignore
                  @sf.tip_node(tips, time, fn() { said().full }, within=true) |> ignore
                })
                |> ignore
              2 => row_aside_node(e, src, tips, item, lead, face_ground, stint)
              _ => ()
            }
          })
        })
      },
    )
    // (held off past its slot's start once it is there, its tray in its place: Tray::parked_now)
    row
    .offset(By(fn() { (off.shown(row), 0.0) }))
    .shift(By(fn() { if tray.parked.get() { (-1.0, 0.0) } else { (0.0, 0.0) } }))
    |> ignore
    // archived here: its tray says so where it was, the row gone off to the left over it (where it was not swiped
    // there already) and held off; back over it from the left once 撤销 is pressed, or its archive refused
    let here = kept is Some(_)
    let gone = fn() {
      match kept {
        Some(k) => k()
        None => false
      }
    }
    // (its chat's archive the one said here, 撤销 not pressed)
    let mine = fn() {
      here &&
      (match archived_here.get() {
        Some(a) => a.name == key() && !a.undone
        None => false
      })
    }
    // (as wide as its slot as the cause comes: how far it goes)
    let slot_w = fn() {
      let (_, _, w, _) = holder.laid_window_now()
      dmax(w, 1.0)
    }
    let come_back = fn() {
      rows.swiped_off.remove(swiped_key(@signals.untracked(item)))
      tray.back(holder, slot_w(), fn() {
        match archived_here.untracked() {
          Some(a) if a.name == @signals.untracked(key) && a.undone => archived_here.set(None)
          _ => ()
        }
      })
    }
    // (made while its chat is archived here, or its line closing: held off at once, still, 撤销 in)
    if @signals.untracked(fn() { mine() || gone() }) {
      tray.parked_now()
    }
    if here {
      row.reacts(
        fn() { tray.pending.get() || mine() || (tray.decided.get() && gone()) },
        fn(away) {
          if away {
            if !tray.decided.untracked() {
              tray.away(holder, slot_w(), @motion.moved(), gone_at=0.0)
            }
          } else if tray.decided.untracked() {
            come_back()
          }
        },
        at_start=false,
      )
    }
    let undo_now = fn() {
      match archived_here.untracked() {
        Some(a) if a.name == @signals.untracked(key) && !a.undone => {
          archived_here.set(Some({ ..a, undone: true }))
          (a.undo)()
          come_back()
        }
        _ => ()
      }
    }
    // 归档 at the row's top right while a mouse points at it (concentric with the row's corner), going with the row
    // as it goes off (a mouse's alone: nothing of it made for a finger's row; in what its tray is made in, one
    // structure for both)
    let archive_keys = if finger {
      None
    } else {
      Some((archive_key, fn(o : @view.View) {
        o
        .over(Is(true))
        .lines_up(Is(Some(End)))
        .padding(Is((0.0, @ui.capsule_in(@sf.row_corner, row_key_side), @ui.capsule_in(@sf.row_corner, row_key_side), 0.0)))
        .offset(By(fn() { (off.shown(o), 0.0) }))
        |> ignore
        o.box(fn(k) {
          k
          .width(Is(Some(row_key_side)))
          .height(Is(Some(row_key_side)))
          .radius(Is(1.0e6))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .ground(By(fn() { if @sf.lit_node(k) { t().p.hover } else { 0L } }))
          |> ignore
          @sf.presses_node(k, fn() { then_whole(fn(w) { archive_row(src, w, here=kept is Some(_)) }, fn() {  }) })
          // (beside the row now, not in it: right clicked, the row's menu still, as on its name)
          k.on_menu(fn(m) { open_menu(m.wx, m.wy, false) }) |> ignore
          k.says(By(fn() {
            Some(@view.said(Button, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item().title)])))
          }))
          |> ignore
          @sf.icon_node(k, "archive", row_icon, By(fn() { if @sf.lit_node(k) { t().p.text } else { t().p.muted } })) |> ignore
          @sf.tip_node(tips, k, fn() { @sf.t("web-main.chat.archive") }) |> ignore
        })
        |> ignore
      }))
    }
    tray_node(holder, tray, at, here, mine, undo_now, keys?=archive_keys)
    if swipes {
      swipe_node(holder, src, item, tray, here, ask_whole, then_whole, come_back)
    }
    row.reacts(fn() { @sf.lit_in_node(hover_in) }, fn(h) { hand.go(row, if h { 1.0 } else { 0.0 }, @sf.dur_ms) })
    // (a pointer come to rest over it: its whole row asked for its time, its 归档 and its menu; gone, let go of)
    if !finger {
      row.reacts(fn() { @sf.lit_in_node(hover_in) }, fn(h) {
        hovering.val = h
        if h {
          ask_whole()
        } else {
          whole_idle()
        }
      })
    }
    // (its menu gone, what waited answered: let go of where nothing else holds it)
    row.reacts(fn() { menu_on() }, fn(on) { if !on { whole_idle() } })
    row.owns(fn() {
      whole_wait_gone()
      whole.let_go()
    })
    |> ignore
    // (its chat in view or no more, eased; taken for another chat, as that one's at once, as it would be made)
    let chosen_for = Ref(@sfbase.row_name(first))
    row.reacts(fn() { (key(), on()) }, fn(now) {
      let (k, o) = now
      let to = if o { 1.0 } else { 0.0 }
      if k == chosen_for.val {
        chosen.go(row, to, @sf.dur_ms)
      } else {
        chosen.put(to)
      }
      chosen_for.val = k
    })
    // (taken for another chat: what was the one before's let go, as it would be were it made anew for this one)
    let made_for = Ref(@sfbase.row_name(first))
    row.reacts(key, fn(k) {
      guard k != made_for.val else { return }
      made_for.val = k
      rows.swiped_off.remove(swiped_key(@signals.untracked(item)))
      // (its tray as this one's is: none, or held off where this chat is archived here)
      tray.put_by()
      if @signals.untracked(fn() { mine() || gone() }) {
        tray.parked_now()
      }
      held.set(false)
      (press_due.val)()
      press_due.val = fn() {  }
      press_lit.set(false)
      match primed.val {
        Some(reader) => {
          primed.val = None
          reader.cancel()
        }
        None => ()
      }
      opened.val = false
      down_at.val = None
      whole_wait_gone()
      pressing.val = false
      whole.let_go()
      // (put, never set going: a row taken for another chat is so as its list is laid out (a block given another key
      // as the list scrolls), what a frame found, no cause; what it shows is put back as it would be were it made anew
      // for that chat, as a list's reused row's looks always are (a way said here was the frame's, at 60 a second and
      // 120 at other moments and other times over: tape_wbtest's ways, 2026-11-11))
      for w in [left, pressed, hand] {
        w.put(0.0)
      }
      lift.put(0.0)
    })
    if finger {
      if at != Whole {
        row.reacts(fn() { press_lit.get() }, fn(lit) {
          if lit {
            pressed.go_from(row, 1.0, 1.0, @motion.Snap(0.0))
          } else {
            pressed.go(row, 0.0, @sf.dur_ms)
          }
        })
      }
      let was_on = Ref((@sfbase.row_name(first), @signals.untracked(on)))
      row.reacts(fn() { (key(), on()) }, fn(now) {
        let (k, o) = now
        // (gone back from its chat: not another chat it is taken for, which was never in view here)
        if was_on.val.0 == k && was_on.val.1 && !o {
          row_left_said.set(k)
          let since = row.cause_at()
          left.go_from(row, 1.0, 1.0, @motion.Snap(0.0))
          if at == Whole {
            row.at_moment(since + left_lit_ms, fn() { left.go(row, 0.0, left_fade_ms, ease=Leave) }) |> ignore
          } else {
            // (beside its chat, the list never covered: no page slides off it, its ground goes as a mouse's does)
            left.go(row, 0.0, @sf.dur_ms)
          }
        }
        was_on.val = (k, o)
      })
      // (another row gone back from since: this one's ground gone at once, put, no way set going (at once is no way,
      // and this is told as often by a row taken for another chat as its list is laid out, a frame's finding: #5420))
      row.reacts(fn() { row_left_said.get() }, fn(k) {
        if k != @signals.untracked(key) {
          left.put(0.0)
        }
      })
    }
    // pressed: its chat; right clicked, its menu at the pointer; held long by a finger, its menu from the row (its
    // time shown meanwhile); a finger that stays down as long as it takes to show pressed reads its chat ahead then
    row
    .says(By(fn() { if tray.parked.get() { None } else { Some(@view.said(Link, label=item().title)) } }))
    .on_menu(fn(m) { open_menu(m.wx, m.wy, false) })
    |> ignore
    @sf.presses_held_node(
      row,
      press,
      @ui.long_press_ms,
      fn(d) {
        if finger {
          held.set(true)
          open_menu(d.wx, d.wy, true)
        }
      },
      down=fn(d) {
        // (its whole row asked as it goes down: a hold's menu, a swipe's question find it answered)
        pressing.val = true
        ask_whole()
        down_at.val = Some((d.wx, d.wy))
        opened.val = false
        (press_due.val)()
        // (not as it goes down: each finger that scrolls the list goes down on a row, and would have its chat read,
        // the core's whole answer taken in as the drag begins, and let go again; a tap quicker than that opens its
        // chat as it is let go)
        press_due.val = row.at_moment(row.cause_at() + @ui.tap_indication_ms, fn() {
          press_lit.set(true)
          if finger && !src.read_only {
            match primed.val { Some(reader) => { primed.val = None; reader.cancel() }; None => () }
            primed.val = Some(src.lease_topic("chat", chat_params(@signals.untracked(r))))
          }
        })
      },
      up=fn() {
        held.set(false)
        (press_due.val)()
        press_lit.set(false)
        if !opened.val {
          let reader = primed.val
          primed.val = None
          unprime(src, @signals.untracked(r), reader)
        }
        primed.val = None
        pressing.val = false
        whole_idle()
      },
    )
    // (held off: nothing to the hand where it is drawn, past its slot's start)
    row.presses(By(fn() { !tray.parked.get() })) |> ignore
    // (Tab passes the rows, as the old list's: they are gone through by ⌥↑ ⌥↓, chat.prev and chat.next)
    row.tab_stop(Is(false)) |> ignore
  })
}

///|
/// A row's way across its slot and what it uncovers there (its tray, tray_node): how far it is moved left (points), held
/// off past its slot's start once gone (`parked`: by its own width, `off` back at 0, so a window resized meanwhile does
/// not bring it in), whether letting it go would archive it (`past`), whether its tray is out, whether its archive is
/// decided (its tray's 撤销 coming in with its way out, from how far it had gone then: `since`), a swipe's archive not
/// asked yet (`pending`: it flies off first), on its way back over its tray (`going_back`); what is due at its way's end.
priv struct Tray {
  off : @sf.EdgeWay
  past : @signals.Signal[Bool]
  out : @signals.Signal[Bool]
  parked : @signals.Signal[Bool]
  decided : @signals.Signal[Bool]
  since : @signals.Signal[Double]
  pending : @signals.Signal[Bool]
  going_back : @signals.Signal[Bool]
  mut due : () -> Unit
}

///|
fn Tray::new() -> Tray {
  {
    off: @sf.EdgeWay::new(0.0),
    past: @signals.signal(false),
    out: @signals.signal(false),
    parked: @signals.signal(false),
    decided: @signals.signal(false),
    since: @signals.signal(0.0),
    pending: @signals.signal(false),
    going_back: @signals.signal(false),
    due: fn() {  },
  }
}

///|
/// Where it rests, nothing uncovered, at once (a row taken for another chat: as were it made anew).
fn Tray::put_by(self : Tray) -> Unit {
  (self.due)()
  self.due = fn() {  }
  self.off.put(0.0)
  for s in [self.past, self.out, self.parked, self.decided, self.pending, self.going_back] {
    s.set(false)
  }
  self.since.set(0.0)
}

///|
/// Held off past its slot's start, its archive decided, its tray out with 撤销 in: at once, still.
fn Tray::parked_now(self : Tray) -> Unit {
  self.decided.set(true)
  self.out.set(true)
  self.since.set(0.0)
  self.parked.set(true)
  self.off.put(0.0)
}

///|
/// Off to the left out of its slot `w` wide as `spec` says from `n`'s cause's moment (at `velocity`: a finger letting it
/// go), its archive decided as it had gone `gone_at`; there, held off (parked_now) and `then` done.
fn Tray::away(
  self : Tray,
  n : @view.View,
  w : Double,
  spec : @motion.Spec,
  gone_at~ : Double,
  velocity? : Double,
  then? : () -> Unit = fn() {  },
) -> Unit {
  (self.due)()
  self.since.set(gone_at)
  self.decided.set(true)
  self.out.set(true)
  self.off.go_by(n, -w, spec, velocity?)
  self.due = n.at_moment(self.off.end(), fn() {
    self.due = fn() {  }
    self.parked_now()
    then()
  })
}

///|
/// Back into its slot `w` wide over its tray from where it is (held off: from the slot's start) on the spring what makes
/// way moves by, from `n`'s cause's moment, 撤销 going out as it comes (`since` none); there, its tray in no more and
/// `done` done. Once, from an archive decided.
fn Tray::back(self : Tray, n : @view.View, w : Double, done : () -> Unit) -> Unit {
  guard self.decided.untracked() && !self.going_back.untracked() else { return }
  (self.due)()
  self.going_back.set(true)
  self.pending.set(false)
  self.past.set(false)
  self.since.set(0.0)
  if self.parked.untracked() {
    self.parked.set(false)
    self.off.go_from(n, -w, 0.0, @motion.move_spring)
  } else {
    self.off.go_by(n, 0.0, @motion.move_spring)
  }
  self.due = n.at_moment(self.off.end(), fn() {
    self.due = fn() {  }
    self.going_back.set(false)
    self.decided.set(false)
    self.out.set(false)
    done()
  })
}

///|
/// Where the row's end is across its slot `w` wide as `n` is drawn (held off: at its start).
fn Tray::edge(self : Tray, n : @view.View, w : Double) -> Double {
  if self.parked.get() {
    0.0
  } else {
    dmax(0.0, dmin(w, w + self.off.shown(n)))
  }
}

///|
/// How far 撤销 has come in (0 out past the slot's end, 1 in its place) as `n` is drawn in a slot `w` wide: with the
/// row's way out from how far it had gone as its archive was decided (since), on its way back from none.
fn Tray::undo_in(self : Tray, n : @view.View, w : Double) -> Double {
  if !self.decided.get() {
    return 0.0
  }
  let gone = w - self.edge(n, w)
  let since = self.since.get()
  if w - since <= 0.0 {
    1.0
  } else {
    dmax(0.0, dmin(1.0, (gone - since) / (w - since)))
  }
}

///|
/// How wide a chat row's mark's column is (mark_slot), and the room after it before its title (the theme's first line's
/// gap): where a marked row's title starts past the row's own inset.
fn row_mark_w() -> Double {
  match mark_slot.base.w {
    Some(l) => l.points().unwrap_or(0.0)
    None => 0.0
  }
}

///|
fn row_mark_gap() -> Double {
  match @sf.theme().chat_list.head.base.gap {
    Some(g) => g.px()
    None => 0.0
  }
}

///|
/// How far 归档's words are after the check before them: the check in the middle of the row's mark's column, the words
/// where a marked row's title starts.
fn tray_check_to_words() -> Double {
  (row_mark_w() - tray_check) / 2.0 + row_mark_gap()
}

///|
/// Where 归档's words stand across a slot `w` wide (their start) as the row's end is at `edge`, they `words` wide, the
/// row's own inset `pad`: at the slot's end at first as the row uncovers them; once its end is close behind them, with
/// it, a point less behind it than the check is before them (so the check is never uncovered on the way); docked where
/// a marked row's title starts, the check in the row's mark's column, the row going on.
fn tray_words_x(w : Double, edge : Double, words : Double, pad : Double) -> Double {
  let rest = w - pad - words
  let dock = pad + row_mark_w() + row_mark_gap()
  dmax(dock, dmin(edge + tray_check_to_words() - 1.0, rest))
}

///|
/// What a row moved left in its slot `holder` uncovers there (`tray`'s), from its end to the slot's (the slot's corners
/// the row's: it is slotted), what it holds standing still in the slot: quiet (the chip's
/// ground) until letting go would archive it (`past`), then ink (over swipe_fill_ms); 归档 at the slot's end, uncovered
/// by the row, then going with its end and docked where a marked row's title starts (`at`'s inset), the check before
/// it in the row's mark's column, uncovered by the row's end as it goes on. Its archive decided `here` (a list made
/// once), 撤销 at its end come in from past it with the row's way out, pressed while `undo_on` (`undo`), and 已归档
/// said. Nothing while the row is where it rests. `keys`: what else is made in it while its own says (a mouse's 归档
/// key on the row, a structure for both).
fn tray_node(
  holder : @view.View,
  tray : Tray,
  at : @sf.ListAt,
  here : Bool,
  undo_on : () -> Bool,
  undo : () -> Unit,
  keys? : (() -> Bool, (@view.View) -> Unit),
) -> Unit {
  let fill = @sf.EdgeWay::new(0.0)
  holder.reacts(fn() { tray.past.get() }, fn(p) { fill.go(holder, if p { 1.0 } else { 0.0 }, swipe_fill_ms) })
  // (the row's own inset where its list stands: where its mark and title start, list_row_in's)
  let pad = fn() {
    match at {
      Whole => @sf.phone_row_in.px()
      Side | Tape => @sf.band_pad_in(at)
    }
  }
  // (撤销's capsule's end in from the slot's: as a row's 归档 key stands in a round slot, concentric with its corner;
  // across the whole screen its words where 归档's stood at first)
  let side = fn() { dmin(undo_in, pad()) }
  let end_in = fn() {
    match at {
      Whole => pad() - side()
      Side | Tape => @ui.capsule_in(@sf.row_corner, row_key_side)
    }
  }
  let key_shows = match keys {
    Some((shows, _)) => shows
    None => fn() { false }
  }
  holder.show(fn() { tray.out.get() || key_shows() }, fn(o) {
    o.over(Is(true)) |> ignore
    // (the key going with the row, under its tray)
    match keys {
      Some((shows, make)) => o.show(shows, make)
      None => ()
    }
    o.show(fn() { tray.out.get() }, fn(u) {
      let ink = fn(n : @view.View, of : (@sf.Palette) -> Int64) {
        let p = @sf.theme().p
        @sf.mix(p.bg, fill.shown(n), of(p))
      }
      // (as wide as the slot, moved to start at the row's end, cut to itself)
      u
      .over(Is(true))
      .clips(Is(true))
      .ground(By(fn() {
        let p = @sf.theme().p
        @sf.mix(p.text, fill.shown(u), p.chip)
      }))
      .says(By(fn() {
        if here && tray.decided.get() && !tray.going_back.get() {
          Some(@view.said(Status, label=@sf.t("web-main.filter.archived")))
        } else {
          None
        }
      }))
      .moved_by(fn(w, _, _) { (tray.edge(u, w), 0.0) }, fn(_, _) { 0.0 })
      |> ignore
      // (what it holds the slot across, standing still in it, laid out by its width)
      let held = u.by_room(fn(h, room) {
        h.grow(Is(1.0)).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        // 归档 and the check before it
        h.box(fn(l) {
          l
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .shrink(Is(0.0))
          .moved_by(
            fn(lw, _, _) {
              let w = room.width()
              let words = lw - tray_check - tray_check_to_words()
              (tray_words_x(w, tray.edge(l, w), words, pad()) - tray_check - tray_check_to_words(), 0.0)
            },
            fn(_, _) { 0.0 },
          )
          |> ignore
          @sf.icon_node(l, "check", tray_check, By(fn() { ink(l, fn(p) { p.muted }) }))
          .margin(By(fn() { (0.0, 0.0, tray_check_to_words(), 0.0) }))
          |> ignore
          @sf.words_node(l, fn() { @sf.t("android-chat.archive") }, fn() {
            swipe_words.then(@ui.text_style(color=Data(ink(l, fn(p) { p.muted }))))
          })
          |> ignore
        })
        |> ignore
        h.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        // 撤销: its room to the hand at least undo_reach high, its capsule as high as a row's key, lit under the hand
        h.box(fn(k) {
          k
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .shrink(Is(0.0))
          .min_height(Is(Some(undo_reach)))
          .says(By(fn() {
            if undo_on() {
              Some(@view.said(Button, label=@sf.t("android-chat.archived.undo")))
            } else {
              None
            }
          }))
          .moved_by(
            fn(kw, _, _) {
              let w = room.width()
              let q = if here { tray.undo_in(k, w) } else { 0.0 }
              (-end_in() + (1.0 - q) * (end_in() + kw), 0.0)
            },
            fn(_, _) { 0.0 },
          )
          |> ignore
          @sf.presses_node(k, undo, on=undo_on)
          k.box(fn(c) {
            c
            .row(Is(true))
            .lines_up(Is(Some(Middle)))
            .height(Is(Some(row_key_side)))
            .radius(Is(row_key_side / 2.0))
            .padding(By(fn() { (side(), 0.0, side(), 0.0) }))
            .ground(By(fn() { if undo_on() && @sf.lit_node(k) { @sf.alpha(@sf.theme().p.text, 0.08) } else { 0L } }))
            |> ignore
            @sf.words_node(c, fn() { @sf.t("android-chat.archived.undo") }, fn() {
              swipe_words.then(@ui.text_style(color=Data(ink(c, fn(p) { p.text }))))
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      held.over(Is(true)).moved_by(fn(w, _, _) { (-tray.edge(held, w), 0.0) }, fn(_, _) { 0.0 }) |> ignore
    })
  })
}

///|
/// The check before 归档 in a tray.
let tray_check : Double = 12.0

///|
/// How far 撤销's words are in from its capsule's ends (at most the row's own inset), and the least room to the hand
/// it has down (what always shows is pressed in 44 at least: the app's principles).
let undo_in : Double = 12.0

///|
let undo_reach : Double = 44.0

///|
/// A finger's row swiped left in its slot `sw` to archive its chat (swipe_to_archive's):
/// left past the slop and plainly across first it is the swipe (swipe_claims: the row's press and hold let go), else the list's (or what the row is on:
/// the tape's, to the right). The row follows the finger, `tray.off` how far (points); let go past `archive_at_share`
/// of its width or flung left it goes off to the left as fast as the finger let it go and, there, its chat is archived
/// (`here`: said by its tray; refused, it comes back over it: `come_back`); else it springs back. One busy springs
/// back; one keeping watch springs back and asks first, as its menu's 归档. Passing the line letting go archives at is
/// felt (Home.kt SwipeToArchive: TextHandleMove), `past` said meanwhile; its tray out from its first move until it is
/// back where it rests. What it asks is its chat's whole row's (`ask` asks for it as it sets out; `then_whole` runs with
/// it once answered: let go before, the row stays where it was let go till then). Its archive decided, nothing more to
/// swipe till it is back.
fn swipe_node(
  sw : @view.View,
  src : Source,
  item : () -> ChatItem,
  tray : Tray,
  here : Bool,
  ask : () -> Unit,
  then_whole : ((ChatItem) -> Unit, () -> Unit) -> Unit,
  come_back : () -> Unit,
) -> Unit {
  let off = tray.off
  let past = tray.past
  let from = Ref(0.0)
  let from_x = Ref(0.0)
  // (back where it rests: nothing uncovered from its end's moment)
  let rests = fn() {
    (tray.due)()
    tray.due = sw.at_moment(off.end(), fn() { tray.out.set(false) })
  }
  let back = fn(vx : Double) {
    off.go_by(sw, 0.0, @motion.move_spring, velocity=vx * 1000.0)
    rests()
  }
  sw
  .claims(fn(dx, dy) {
    let i = @signals.untracked(item)
    i.swipe_archive &&
    !rows.swiped_off.contains(swiped_key(i)) &&
    !tray.decided.untracked() &&
    swipe_claims(dx, dy)
  })
  .on_drag(fn(d) {
    let w = if d.w > 1.0 { d.w } else { 1.0 }
    let i = @signals.untracked(item)
    let key = swiped_key(i)
    guard !rows.swiped_off.contains(key) && !tray.decided.untracked() else { return }
    match d.kind {
      Down => {
        ask()
        from.val = @signals.untracked(fn() { off.shown(sw) })
        from_x.val = d.wx
        (tray.due)()
        tray.due = fn() {  }
        off.put(from.val)
        tray.out.set(true)
      }
      Moved => {
        let at = dclamp(from.val + (d.wx - from_x.val), -w, 0.0)
        off.put(at)
        let now = at < -w * archive_at_share
        if now && !past.untracked() {
          @ui.haptic(TextHandleMove)
        }
        past.set(now)
      }
      Up => {
        let at = @signals.untracked(fn() { off.target() })
        past.set(false)
        if swipe_archives(at, w, d.vx()) {
          let vx = d.vx()
          if row_busy(src, i) {
            back(vx)
          } else {
            then_whole(fn(i) {
              if i.swipe_ask is Some(_) {
                // (one keeping watch, or at work: springs back and asks first, in the core's words: swipeAsk)
                back(vx)
                archive_row(src, i, ask=i.swipe_ask, here~)
              } else {
                // off to the left, 撤销 coming in with it from how far it had gone, then archived there (no copy of it
                // left behind as it leaves the list: it is out of sight); refused, it comes back from there
                rows.swiped_off[key] = true
                tray.pending.set(true)
                tray.away(sw, w, @motion.moved(), gone_at=-at, velocity=vx * 1000.0, then=fn() {
                  tray.pending.set(false)
                  archive_row(src, i, here~, failed=come_back)
                })
              }
            }, fn() {
              // (what it was let go in is gone before it was answered: back where it rests, nothing asked)
              back(0.0)
            })
          }
        } else {
          back(d.vx())
        }
      }
      Off => {
        past.set(false)
        back(0.0)
      }
    }
  })
  |> ignore
}

///|
/// Whether `item`'s row was swiped off as it leaves its list (out of sight already: no copy of it left behind), its
/// mark let go then.
fn swiped_gone(item : ChatItem) -> Bool {
  let key = swiped_key(item)
  guard rows.swiped_off.contains(key) else { return false }
  rows.swiped_off.remove(key)
  true
}

///|
/// What a row swiped off to be archived is said by in rows.swiped_off, until its list has let it go.
fn swiped_key(item : ChatItem) -> String {
  "swipe/" + @sfbase.row_name(item)
}

///|
/// A row's key's side (row_key_box: S6).
let row_key_side : Double = 24.0

///|
/// How wide what row_aside_node shows is (row_aside_w's), by its parts' sizes as the theme says them now, its words at
/// the system's size of words where row `v` is drawn.
fn row_aside_w_node(v : @view.View, item : ChatItem, lead : String) -> Double {
  let l = @sf.theme().chat_list
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let th = @ui.tree_theme()
  let more_w = fn(n : Int) { @ui.text_advance("+\{n}", size=@sf.node_sp(v, th.text_size(Meta).0)) }
  let parts : Array[Double] = []
  if groups.length() > 0 {
    let shown = if groups.length() > aside_most { aside_most } else { groups.length() }
    let mut w = aside_in + shown.to_double() * aside_agent_w + (shown - 1).to_double() * aside_agent_gap
    if groups.length() > aside_most {
      w = w + aside_agent_gap + more_w(groups.length() - aside_most)
    }
    parts.push(w)
  }
  if row_with_people(item, lead) {
    let shown = if people.length() > aside_most { aside_most } else { people.length() }
    let mut w = aside_in + l.face_d + (shown - 1).to_double() * (l.face_d - face_over)
    if people.length() > 1 && people[:shown].iter().any(fn(p) { p.id == item.creator }) {
      w = w + face_gap_w
    }
    if people.length() > shown {
      w = w + more_w(people.length() - shown)
    }
    parts.push(w)
  }
  if parts.is_empty() {
    return 0.0
  }
  parts.fold(init=0.0, fn(a, b) { a + b }) + (parts.length() - 1).to_double() * aside_parts_gap
}

///|
/// A row's title as a field in its place (row_rename's, from a mouse's 重命名) in `n`: its words
/// the title's, the focus in it as it comes; Enter saves it (`chat.rename`), Esc or leaving it lets it be; as far in as where its list stands
/// (`at`) has it (rename_box).
fn rename_node(n : @view.View, src : Source, item : () -> ChatItem, at : @sf.ListAt) -> Unit {
  rows.rename_field.set(@signals.untracked(item).title)
  let done = fn() { stop_rename() }
  n.box(fn(b) {
    @sf.style_node(b, fn() { rename_box(at) }, in_row=true)
    b.row(Is(true)).lines_up(Is(Some(Middle))).edge(By(fn() { (1.0, @sf.theme().p.line_strong) })) |> ignore
    let f = @ui.field(
      b,
      rows.rename_field,
      font_size=rename_size,
      label=@sf.t("web-main.chat.rename"),
      line=rename_line,
      max_lines=1,
      enter_sends=true,
      colors_by=fn() {
        let p = @sf.theme().p
        (p.text, p.subtle, p.accent)
      },
      submitted=fn(title) {
        done()
        rename(src, @signals.untracked(item), title)
      },
    )
    f.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
    b.focus_opens(f) |> ignore
    // A press outside the field ends the rename even when its target cannot take the focus. It still reaches that
    // target. The press that opened the menu predates this field, so only later presses are considered.
    let opened = @signals.untracked(fn() { b.window_downs() })
    b.reacts(fn() { b.window_downs() }, fn(count) {
      if count > opened {
        let (x, y) = b.window_down_point()
        let (left, top, w, h) = b.placed_window_now()
        if x < left || x >= left + w || y < top || y >= top + h {
          b.focus_let_go()
          done()
        }
      }
    })
    // (left: let be)
    let seen = Ref(false)
    b.reacts(fn() { f.focused() }, fn(on) {
      if on {
        seen.val = true
      } else if seen.val {
        done()
      }
    })
  })
  |> ignore
}

///|
/// The chat whose row's title is a field now (its name: row_name; "" none), from a mouse's 重命名.
// kept across runs: put back by chat_rows_reset
let row_renaming : @signals.Signal[String] = @signals.signal("")

///|
/// The row last gone back from by a finger (its name: row_name), the one whose ground stays a while.
// kept across runs: put back by chat_rows_reset
let row_left_said : @signals.Signal[String] = @signals.signal("")
