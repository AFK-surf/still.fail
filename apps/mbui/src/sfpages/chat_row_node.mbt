// A chat's row in the chats' lists (chat_row.mbt's) as a node of the window's tree, made once for its chat and
// following what the core says of it: its state's mark before its title (bolder while something in it is unread), what
// marks it (failed a moment ago, its station away, from Slack, opened by another chat, its station's mark), where it
// stands or the last thing said, who is in it; pressed, its chat; with a mouse, pointed at, its time in that place and
// 归档 at its top right, right clicked its menu at the pointer; with a finger, held a while its time, held long its
// menu.

///|
/// The row of the chat `item` says as it is now (chat_row's) in `parent`: `lead` whose pictures lead, `on` its chat the
/// page in view, `list_ground` the list's ground (round its faces), `more` another row under it, `at` where its list
/// stands; tips in `tips`, pictures asked for on `stint`. The row's node.
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
  found? : Bool = false,
  opened? : (ChatRef) -> Unit,
) -> @view.View {
  let t = fn() { @sf.theme() }
  // (a finger rests on nothing: a press reads ahead, a hold shows the time; a pointer's over it shows them)
  let finger = !@sf.pointer_rests()
  let first = @signals.untracked(item)
  let key = @sfbase.row_name(first)
  // (made again for its chat, asked back say: whatever swiped it off before is over)
  rows.swiped_off.remove(swiped_key(first))
  let r = fn() { row_ref(item()) }
  let offline = fn() { item().offline is Some(_) }
  let menu_ok = fn() { !found && item().offline is None && !item().pending }
  let menu_on = fn() { row_menu_open(item()) }
  // (its title a field in its place, from a mouse's 重命名: rename_node)
  let renaming = fn() { row_renaming.get() == key }
  let failed = fn() { row_failed(src, item()) }
  // (held by a finger a while: its time shows)
  let held : @signals.Signal[Bool] = @signals.signal(false)
  // (pressed by a finger, shown so once it has stayed tap_indication_ms: one going on to scroll lights nothing)
  let press_lit : @signals.Signal[Bool] = @signals.signal(false)
  let press_due : Ref[() -> Unit] = Ref(fn() {  })
  // (what a finger going down on it read ahead, let go as it is let go without opening it: a scroll, a hold)
  let primed = Ref(false)
  let opened_once = Ref(false)
  // (where the last press went down, and its state line: pressed there, while the core says which message that is
  // about and nothing in it is unread, its chat goes there as it opens: ChatMark.tsx jumpFromLine)
  let down_at : Ref[(Double, Double)?] = Ref(None)
  let state_at : Ref[@view.View?] = Ref(None)
  let press = fn() {
    let i = @signals.untracked(item)
    opened_once.val = true
    let r = row_ref(i)
    match opened {
      Some(f) => { f(r); return }
      None => ()
    }
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
  }
  parent.box(fn(slot) {
    @sf.style_node(slot, fn() { if more { @sf.list_more(at) } else { row_last } })
    let swipes = finger && @sf.more_held()
    // (swiped: in its slot, cut to its corners where its list stands, 归档 under it)
    let holder = if swipes {
      slot.box(fn(sw) { @sf.style_node(sw, fn() { @sf.list_row_slot(at) }) })
    } else {
      slot
    }
    let row = holder.box(fn(_) {  })
    // held by a finger, it lifts off the list toward the finger (iOS's context menu): a little as its time shows, all
    // the way once its menu opens, back down as the menu goes (@sf.lift_of's), a card of the raised ground over the
    // menu's scrim, drawn in from the screen's sides (row_lifted, @sf.lift_over's)
    let lift = @sf.EdgeWay::new(0.0)
    let lifted = fn() { if finger && !found { dmin(1.0, dmax(0.0, lift.shown(slot))) } else { 0.0 } }
    if finger && !found {
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
    let open_menu = fn(x : Double, y : Double, from_row : Bool) {
      guard @signals.untracked(menu_ok) else { return }
      let i = @signals.untracked(item)
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
      @sf.menu(chat_menu_items(src, i, []), from~)
      rows.menu_for = @sfbase.row_name(i)
      rows.menu_serial = @sf.last_presented()
    }
    let hover = fn() { !finger && (@sf.lit_in_node(row) || menu_on()) }
    let shows_time = fn() { hover() || held.get() || (finger && menu_on()) }
    let archive_key = fn() { !finger && menu_ok() && hover() && !renaming() }
    // its ground: a finger's, held or its menu open the ink at 5%, its chat in view the selected one's; a mouse's, the
    // pointer's eased in and out, the selected one's while its chat is in view (nav_ground's)
    // a finger's: its chat's page in view, its ground on; gone back from it, the ground stays while the page slides off
    // and a while after (left_lit_ms), then fades (left_fade_ms); one row so, the chat last in view
    let left = @sf.EdgeWay::new(0.0)
    // (a finger's swiped left in its slot, by so many points: swipe_node's)
    let off = @sf.EdgeWay::new(0.0)
    let hand = @sf.EdgeWay::new(0.0)
    let chosen = @sf.EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
    let ground = fn() {
      let p = t().p
      if finger {
        // (lifted, its card is its ground: the row's own drawn by the card round it, not square inside it)
        if lifted() > 0.0 {
          0L
        } else if held.get() || menu_on() || press_lit.get() {
          @sf.alpha(p.text, 0.05)
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
    let cornered = fn() { at == Side && !shows_time() && row_aside_shows(item(), lead) }
    let face_ground = fn() { @sf.over(list_ground(), if lifted() > 0.0 { t().p.raised } else { ground() }) }
    @sf.list_row_node(
      row,
      at,
      ground~,
      high=true,
      // (归档 over its first line's end: Sidebar.css.ts rowArchive, 24)
      end_room=fn() { if archive_key() { @sf.row_keys_room(1) } else { 0.0 } },
      corner?=if at == Side {
        Some(fn(k : @view.View) { row_aside_node(k, src, tips, item, lead, face_ground, stint) })
      } else {
        None
      },
      corner_shown=cornered,
      corner_w=fn() { row_aside_w_node(item(), lead) },
      slotted=swipes,
      end_slot=kind_slot_w,
      corner_end=fn() { row_aside_end_w(item(), lead) },
      fn(h) {
        let tone = fn() { @sfbase.row_tone(item()) }
        h.show(fn() { tone() != "" && !renaming() }, fn(m) {
          m.box(fn(s) {
            @sf.style_node(s, fn() { mark_slot }, in_row=true)
            chat_mark_node(s, tone)
          })
          |> ignore
        })
        h.pick(renaming, fn(n, on) {
          // (what is left of the line, from none: its title cut short in it, what stands at its end kept whole)
          n.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          if on {
            rename_node(n, src, item)
            return
          }
          n.box(fn(w) {
            w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            @sf.words_node(w, fn() { item().title }, fn() {
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
          |> ignore
        })
        // failed a moment ago: a red mark, why on it
        h.show(fn() { failed() is Some(_) }, fn(f) {
          f.box(fn(s) {
            @sf.style_node(s, fn() { kind_slot }, in_row=true)
            let why = fn() { failed().unwrap_or("") }
            s.says(By(fn() { Some(@view.said(Image, label=why())) })) |> ignore
            chat_mark_node(s, fn() { "alert" })
            @sf.tip_node(tips, s, why, within=true) |> ignore
          })
          |> ignore
        })
        // its station offline, or its link coming back: unplugged (its update's mark while it updates); one from
        // elsewhere (Slack, Feishu) says so, by its platform's mark
        let away = fn() {
          match (item().offline, item().reconnecting) {
            (Some(why), _) | (None, Some(why)) => why
            _ => ""
          }
        }
        h.pick(fn() { if away() != "" { if item().updating { 2 } else { 1 } } else if item().connect { 3 } else { 0 } }, fn(
          a,
          which,
        ) {
          guard which != 0 else { return }
          a.box(fn(s) {
            @sf.style_node(s, fn() { kind_slot }, in_row=true)
            let said = fn() {
              if which == 3 {
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
              _ => @sf.origin_mark_node(s, fn() { item().origin_kind }, kind_mark) |> ignore
            }
            @sf.tip_node(tips, s, said, within=true) |> ignore
          })
          |> ignore
        })
        // opened by another chat's agent: marked so, that chat named on it
        h.show(fn() { item().opener is Some(_) && !renaming() }, fn(o) {
          o.box(fn(s) {
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
          |> ignore
        })
        // the station it runs on, by its mark: last, in the same column at every row's end
        h.show(fn() { @sf.has_station_mark(item().station_emoji, item().station_icon) && !renaming() }, fn(k) {
          k.box(fn(s) {
            @sf.style_node(s, fn() { kind_slot }, in_row=true)
            s.says(By(fn() { Some(@view.said(Image, label=item().station_name)) })) |> ignore
            @sf.station_mark_node(
              s,
              fn() { item().station_emoji },
              fn() { item().station_icon },
              kind_mark_of(@signals.untracked(item).station_icon),
              fn() { if offline() { t().p.subtle } else { t().p.muted } },
              stint,
            )
            @sf.tip_node(tips, s, fn() { item().station_name }, within=true) |> ignore
          })
          |> ignore
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
                  @sf.words_node(time, fn() { item().ago }, fn() { row_time }) |> ignore
                  @sf.tip_node(tips, time, fn() { item().full }, within=true) |> ignore
                })
                |> ignore
              2 => row_aside_node(e, src, tips, item, lead, face_ground, stint)
              _ => ()
            }
          })
        })
      },
    )
    if swipes {
      let past : @signals.Signal[Bool] = @signals.signal(false)
      let out : @signals.Signal[Bool] = @signals.signal(false)
      row.offset(By(fn() { (off.shown(row), 0.0) })) |> ignore
      swipe_under_node(row, off, past, out)
      swipe_node(holder, src, item, off, past, out)
    }
    row.reacts(fn() { @sf.lit_in_node(row) }, fn(h) { hand.go(row, if h { 1.0 } else { 0.0 }, @sf.dur_ms) })
    row.reacts(on, fn(o) { chosen.go(row, if o { 1.0 } else { 0.0 }, @sf.dur_ms) })
    if finger {
      let was_on = Ref(@signals.untracked(on))
      row.reacts(on, fn(o) {
        if was_on.val && !o {
          row_left_said.set(key)
          let at = row.cause_at()
          left.go_from(row, 1.0, 1.0, @motion.Snap(0.0))
          row.at_moment(at + left_lit_ms, fn() { left.go(row, 0.0, left_fade_ms, ease=Leave) }) |> ignore
        }
        was_on.val = o
      })
      // (another row gone back from since: this one's ground gone at once)
      row.reacts(fn() { row_left_said.get() }, fn(k) {
        if k != key {
          left.go_from(row, 0.0, 0.0, @motion.Snap(0.0))
        }
      })
    }
    // pressed: its chat; right clicked, its menu at the pointer; held long by a finger, its menu from the row (its
    // time shown meanwhile); a finger going down reads its chat ahead
    row
    .says(By(fn() { Some(@view.said(Link, label=item().title)) }))
    .on_menu(fn(m) { open_menu(m.wx, m.wy, false) })
    |> ignore
    if found {
      // A search result or recent chat has its press's ripple, with no hold menu; swiping is still the row's.
      @sf.pressed_node(row, press, Is(0.0), Link, fn() { item().title })
    } else {
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
        down_at.val = Some((d.wx, d.wy))
        opened_once.val = false
        (press_due.val)()
        press_due.val = row.at_moment(row.cause_at() + @ui.tap_indication_ms, fn() { press_lit.set(true) })
        if finger && !src.read_only {
          primed.val = true
          (src.topic)("chat", chat_params(@signals.untracked(r))) |> ignore
        }
      },
      up=fn() {
        held.set(false)
        (press_due.val)()
        press_lit.set(false)
        if primed.val && !opened_once.val {
          unprime(src, @signals.untracked(r))
        }
        primed.val = false
      },
    )
    }
    // (Tab passes the rows, as the old list's: they are gone through by ⌥↑ ⌥↓, chat.prev and chat.next)
    row.tab_stop(Is(false)) |> ignore
    // 归档 at the row's top right while a mouse points at it (concentric with the row's corner)
    row.show(archive_key, fn(o) {
      o
      .over(Is(true))
      .lines_up(Is(Some(End)))
      .padding(Is((0.0, @sf.capsule_in(@sf.row_corner, row_key_side), @sf.capsule_in(@sf.row_corner, row_key_side), 0.0)))
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
        @sf.presses_node(k, fn() { archive_row(src, @signals.untracked(item)) })
        k.says(By(fn() {
          Some(@view.said(Button, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item().title)])))
        }))
        |> ignore
        @sf.icon_node(k, "archive", row_icon, By(fn() { if @sf.lit_node(k) { t().p.text } else { t().p.muted } })) |> ignore
        @sf.tip_node(tips, k, fn() { @sf.t("web-main.chat.archive") }) |> ignore
      })
      |> ignore
    })
  })
}

///|
/// What a finger's row `row` swiped left uncovers in its slot as it has gone `off` (points, from 0 to as wide as the
/// slot), in a node past its end that goes with it: at that end as far as the row has gone and no further
/// (mobile/Home.tsx mSwipeUnder), quiet until letting go would archive it (`past`), then ink (over swipe_fill_ms); 归档
/// at the slot's end in it, laid out the slot across so it is whole (what of it the row has not uncovered yet, cut
/// with it). Nothing while the row is where it rests.
fn swipe_under_node(
  row : @view.View,
  off : @sf.EdgeWay,
  past : @signals.Signal[Bool],
  out : @signals.Signal[Bool],
) -> Unit {
  let fill = @sf.EdgeWay::new(0.0)
  row.reacts(fn() { past.get() }, fn(p) { fill.go(row, if p { 1.0 } else { 0.0 }, swipe_fill_ms) })
  row.show(fn() { out.get() }, fn(u) {
    // (over the row as big as it is, out of its row of parts: what is past its end as wide as it)
    u.over(Is(true)) |> ignore
    u.box(fn(g) {
      // (归档 cut to it: laid out at the slot's end, it shows only as far as the row has uncovered, as under the row)
      g
      .over(Is(true))
      .shift(Is((1.0, 0.0)))
      .clips(Is(true))
      .ground(By(fn() {
        let t = @sf.theme()
        @sf.mix(t.p.text, fill.shown(g), t.p.chip)
      }))
      |> ignore
      g.box(fn(w) {
        @sf.style_node(w, fn() { swipe_words_line })
        w.over(Is(true)).shift(Is((-1.0, 0.0))).offset(By(fn() { (-off.shown(w), 0.0) })) |> ignore
        @sf.words_node(w, fn() { @sf.t("android-chat.archive") }, fn() {
          let t = @sf.theme()
          swipe_words.then(@ui.text_style(color=Data(@sf.mix(t.p.bg, fill.shown(w), t.p.muted))))
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A finger's row (mobile/Home.tsx SwipeArchive) swiped left in its slot `sw` to archive its chat (swipe_to_archive's):
/// across and left first it is the swipe (the row's press and hold let go), else the list's (or what the row is on:
/// the tape's, to the right). The row follows the finger, `off` how far (points); let go past `archive_at_share` of
/// its width or flung left it goes off to the left as fast as the finger let it go and, there, its chat is archived
/// (refused, it comes back from there); else it springs back. One busy springs back; one keeping watch springs back
/// and asks first, as its menu's 归档. Passing the line letting go archives at is felt (Home.kt SwipeToArchive:
/// TextHandleMove), `past` said meanwhile; `out` from its first move until it is back where it rests.
fn swipe_node(
  sw : @view.View,
  src : Source,
  item : () -> ChatItem,
  off : @sf.EdgeWay,
  past : @signals.Signal[Bool],
  out : @signals.Signal[Bool],
) -> Unit {
  let from = Ref(0.0)
  let from_x = Ref(0.0)
  let due = Ref(fn() {  })
  // (back where it rests: nothing uncovered from its end's moment)
  let rests = fn() {
    (due.val)()
    due.val = sw.at_moment(off.end(), fn() { out.set(false) })
  }
  let back = fn(vx : Double) {
    off.go_by(sw, 0.0, @motion.move_spring, velocity=vx * 1000.0)
    rests()
  }
  sw
  .claims(fn(dx, dy) {
    let i = @signals.untracked(item)
    i.swipe_archive && !rows.swiped_off.contains(swiped_key(i)) && dx < 0.0 && dx.abs() > dy.abs()
  })
  .on_drag(fn(d) {
    let w = if d.w > 1.0 { d.w } else { 1.0 }
    let i = @signals.untracked(item)
    let key = swiped_key(i)
    guard !rows.swiped_off.contains(key) else { return }
    match d.kind {
      Down => {
        from.val = @signals.untracked(fn() { off.shown(sw) })
        from_x.val = d.wx
        (due.val)()
        off.put(from.val)
        out.set(true)
      }
      Moved => {
        let at = dclamp(from.val + (d.wx - from_x.val), -w, 0.0)
        off.put(at)
        let now = at < -w * archive_at_share
        if now && !@signals.untracked(fn() { past.get() }) {
          @ui.haptic(TextHandleMove)
        }
        past.set(now)
      }
      Up => {
        let at = @signals.untracked(fn() { off.target() })
        let fling = d.vx < -fling_speed && at < -fling_from
        past.set(false)
        if at < -w * archive_at_share || fling {
          if row_busy(src, i) {
            back(d.vx)
          } else if i.swipe_ask is Some(_) {
            // (one keeping watch, or at work: springs back and asks first, in the core's words: swipeAsk)
            back(d.vx)
            archive_row(src, i, ask=i.swipe_ask)
          } else {
            // off to the left, then archived there (no copy of it left behind as it leaves the list: it is out of
            // sight); refused, it comes back from there
            rows.swiped_off[key] = true
            off.go_by(sw, -w, @motion.move(), velocity=d.vx * 1000.0)
            sw.at_moment(off.end(), fn() {
              archive_row(src, i, failed=fn() {
                rows.swiped_off.remove(key)
                off.go_from(sw, -w, 0.0, @motion.move_spring)
                rests()
              })
            })
            |> ignore
          }
        } else {
          back(d.vx)
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
/// How wide what row_aside_node shows is (row_aside_w's), by its parts' sizes as the theme says them now.
fn row_aside_w_node(item : ChatItem, lead : String) -> Double {
  let l = @sf.theme().chat_list
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let th = @ui.tree_theme()
  let more_w = fn(n : Int) { @ui.text_advance("+\{n}", size=@ui.current().sp(th.text_size(Meta).0)) }
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
/// A row's title as a field in its place (row_rename's, Rename.tsx TitleInput, from a mouse's 重命名) in `n`: its words
/// the title's, the focus in it as it comes; Enter saves it (`chat.rename`), Esc or leaving it lets it be.
fn rename_node(n : @view.View, src : Source, item : () -> ChatItem) -> Unit {
  rows.rename_field.set(@signals.untracked(item).title)
  let done = fn() { stop_rename() }
  n.box(fn(b) {
    @sf.style_node(b, fn() { rename_box() }, in_row=true)
    b.row(Is(true)).lines_up(Is(Some(Middle))).edge(By(fn() { (1.0, @sf.theme().p.line_strong) })) |> ignore
    let f = @ui.field(
      b,
      rows.rename_field,
      font_size=rename_size,
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
          @ui.current().blur()
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
