// An agent at work, in one line of its chat's list, as nodes of the window's tree (chat_rows.mbt's activity_row,
// work_ring, steady_words, activity_change_glyphs, activity_glyphs; their styles the same): its picture ringed while it
// works (eight arcs turning; a still whole ring while it waits on what it started), what it does now as the core says
// (steadied: activity_steady_node.mbt), its first words coming in glyph by glyph and each step's giving way to the
// next's at each glyph's place, the line going from the one's width to the other's with its clock, and how long its
// turn has run; pressed, its history beside the chat; one of several agents, its own stop under the pointer. Each
// motion from the moment its cause was said (the step began showing; the row came into its list), as data. Not here
// yet: the card over its picture (P21). The list's, not the row's: the line folding to its picture as a message comes
// out of it, the picture away while its copy flies, the ring fading as the row goes.

///|
/// What agent `a` says it does now, as its row reads it (activity_row's `said`): what it waits on (important: a wait
/// is read), else what the core's `live` says it does (`now`), else that it is at work.
fn working_said(a : Agent, live : Json?) -> ActivitySaid {
  match a.wait {
    Some((_, _, w)) =>
      { key: "wait", words: if w != "" { w } else { @sf.t("web-main.activity.waiting") }, mono: false, important: true }
    None => {
      let n = field(field(live, "activity"), "now")
      match text(n, "text") {
        "" => { key: "busy", words: @sf.t("web-main.activity.busy"), mono: false, important: false }
        s => { key: text(n, "key"), words: s, mono: flag(n, "mono"), important: flag(n, "important") }
      }
    }
  }
}

///|
/// How long agent `a`'s turn has run is worked out from (activity_row's clock): when it began waiting and how long it
/// waits at most (seconds), or when its turn began; None, no clock.
fn working_clock_from(a : Agent) -> (Double, Double?)? {
  match a.wait {
    Some((since, most, _)) => Some((since, most))
    None => a.since.map(fn(s) { (s, None) })
  }
}

///|
/// The clock's words at the core's moment `now` from `since`, no further than `most` seconds after it (then said
/// against it: 1m 5s / 5m).
fn working_clock_words(since : Double, most : Double?, now : Double) -> String {
  match most {
    Some(sec) => {
      let waited = dmin(now, since + sec * 1000.0)
      elapsed(waited - since) + " / " + elapsed(sec * 1000.0)
    }
    None => elapsed(now - since)
  }
}

///|
/// Agent `a` at work (activity_row's, as nodes), as it says as it changes, in its row's room (message_row_frame_node:
/// `key`, its list's Entry::id `act:<agent>`; `side`, `top`; `over`): its picture ringed, what it does now steadied by
/// its key in `steadies` (the row come into its list at `came`, None: there as the chat opened) and changing glyph by
/// glyph in the room the row gives its words (working_words_node; its glyphs' noise by `key`), its clock from then
/// (seen from `came` over row_size_ms); the line pressed opens its history beside the chat; where the chat has more
/// than one agent, its stop under the pointer (session.stop). Read out as who and what it does.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn working_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  a : () -> Agent,
  came : () -> Double?,
  steadies : ActivitySteadies,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  let live = fn() {
    @sfbase.hold(src, @sfbase.chat_scope(here.station, here.session), "live", {
      "station": Json::string(here.station),
      "key": Json::string(a().key),
    }).get().value
  }
  let said = fn() { working_said(a(), live()) }
  message_row_frame_node(v, key, side, top, over~, fn(r) {
    // (made by the room the row gives it: how much of the line its words have, activity_visible_width's)
    r.by_room(fn(held, room) {
      held.box(fn(area) {
        @sf.style_node(area, fn() { activity_row_box })
        // the clock's words as they show now ("" none): what they take of the line
        let clock_said : @signals.Signal[String] = @signals.signal("")
        // (how wide they are with the gap before them, worked out as they change, not as what reads it is drawn)
        let clock_w = @signals.computed(fn(_) {
          let clock = clock_said.get()
          if clock == "" {
            0.0
          } else {
            cells_wide(working_cells(clock, @ui.style_words(activity_clock), area.words_scale())) + @ui.Space::S2.px()
          }
        })
        // (what of the row its words have: the row's width less where they start, a stop that shows, its clock and the
        // gap before it)
        let visible = fn() {
          let ml = if message_inline(here) { 0.0 } else { -@sf.message_avatar_reach }
          let start = ml + @ui.Space::S6.px() - 2.0 * ring_room + @ui.Space::S2.px()
          let stop = if (here.view)().agents.length() > 1 && @sf.lit_in_node(area) {
            @ui.Space::S6.px() + @ui.Space::S1.px()
          } else {
            0.0
          }
          dmax(room.width() - start - stop - clock_w.get(), 0.0)
        }
        area.box(fn(line) {
          @sf.style_node(line, fn() { if message_inline(here) { activity_line_narrow } else { activity_line } })
          // (giving way where the row has not the room, down to nothing: what it does now is cut short, as its stop
          // shows beside it, the rest whole)
          line.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
          line.says(By(fn() { Some(@view.said(Button, label=a().who + "：" + said().words)) })) |> ignore
          @sf.presses_node(line, fn() {
            open_detail(src, message_node_ref(here), @signals.untracked(a).key)
          })
          line.box(fn(face) {
            @sf.style_node(face, fn() { activity_face })
            face.box(fn(av) { agent_avatar_node(av, fn() { a().maker }, fn() { a().runtime }, fn() { "" }) |> ignore })
            |> ignore
            // (its agent's card over its picture and the ring over it under a pointer, as over a message's picture:
            // the line's press and hold its own as ever)
            message_agent_card_node(face, src, here, @signals.untracked(a).key, pointed=true)
            // (its ring over its picture)
            face.box(fn(ring) {
              ring.over(Is(true)) |> ignore
              @sf.style_node(ring, fn() { ring_room_style })
              ring.pick(fn() { a().wait is Some(_) }, fn(k, waiting) {
                if waiting {
                  k.box(fn(w) { @sf.style_node(w, fn() { ring_waiting }) }) |> ignore
                } else {
                  @sf.segments_node(k, ring_side, ring_stroke, fn() { @sf.theme().p.accent }, fn() { @sf.theme().p.bg })
                  |> ignore
                }
              })
            })
            |> ignore
          })
          |> ignore
          // what it does now, and how long
          line.box(fn(tail) {
            @sf.style_node(tail, fn() { activity_tail }, in_row=true)
            // (giving way as the line does, its words cut short and its clock whole: a box in a row that says nothing
            // of it is laid out as wide as what it holds, whatever the room)
            tail.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
            let shown = activity_steady_node(tail, steadies, key, said, came)
            let style = fn() { if @sf.hovered_node(line) { now_words_hot } else { now_words } }
            tail.box(fn(words) { working_words_node(words, shown, came, style, visible, key.length()) }) |> ignore
            tail.pick(fn() { working_clock_from(a()) }, fn(k, from) {
              match from {
                Some((since, most)) => {
                  let tick = steps_seconds(k, src, since, till?=most.map(fn(sec) { sec * 1000.0 }))
                  let words = fn() {
                    tick() |> ignore
                    working_clock_words(since, most, (src.now)())
                  }
                  let clock = @sf.words_node(k, words, fn() { activity_clock })
                  k.reacts(words, fn(s) { clock_said.set(s) })
                  // (seen from when the row came into its list, as its rows' size goes)
                  let seen = @motion.Way::new(1.0)
                  k.reacts(came, fn(at) {
                    match at {
                      Some(at) => {
                        seen.put(0.0)
                        seen.go(1.0, @motion.tween(@ui.row_size_ms, ease=Out), at~)
                      }
                      None => seen.put(1.0)
                    }
                  })
                  clock.alpha(By(fn() { seen.shown_on(clock) })) |> ignore
                }
                None => k.reacts(fn() { "" }, fn(s) { clock_said.set(s) })
              }
            })
          })
          |> ignore
        })
        |> ignore
        // one of several agents: stopped alone from its row, under the pointer
        // (a mouse over its line or its stop: an old view's row hovered by any of its parts)
        area.show(fn() { (here.view)().agents.length() > 1 && @sf.lit_in_node(area) }, fn(s) {
          working_stop_node(s, src, here, a)
        })
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Agent `a`'s stop (activity_row's) in `v`: its icon in the muted ink, the text's and the hover ground under the
/// pointer, its words in its tip; pressed, its turn asked to stop (session.stop). Read out a button.
fn working_stop_node(v : @view.View, src : Source, here : MessageNodeHere, a : () -> Agent) -> Unit {
  let label = fn() { @sf.t("web-main.activity.stop", args=[("who", a().who)]) }
  v.box(fn(b) {
    let hot = fn() { @sf.hovered_node(b) }
    @sf.style_node(b, fn() { if hot() { activity_stop_hot } else { activity_stop } })
    b.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    @sf.presses_node(b, fn() {
      act(src, @sf.t("web-pages.chat.stop"), "", "session.stop", {
        "station": Json::string(here.station),
        "key": Json::string(@signals.untracked(a).key),
      }, done=@sf.t("web-pages.chat.stopAsked"))
    })
    @sf.icon_node(b, "stop", stop_icon, By(fn() {
      let p = @sf.theme().p
      if hot() {
        p.text
      } else {
        p.muted
      }
    }))
    |> ignore
    @sf.tip_node(here.tips, b, label) |> ignore
  })
  |> ignore
}

///|
/// The ring's room over the picture: all of the face (activity_face's 24).
// kept across runs: a value (no field of it changes)
let ring_room_style : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A change of what an agent's line says, under way (steady_words' two steps at once): the words it was and is, each
/// in its face and cut into its cells (@ui.glyph_cells), how wide each is whole, how many places of them show
/// (activity_change_places, as the change began), the noise of its row (`salt`); taking over one still under way, the
/// width it set out from and where each of the words it was had come to then (each glyph moved and narrowed), none
/// otherwise.
#derive(Eq, Debug)
struct WorkingChange {
  was : String
  was_mono : Bool
  now : String
  now_mono : Bool
  was_cells : Array[(Double, Double)]
  now_cells : Array[(Double, Double)]
  whole_from : Double
  whole_to : Double
  places : Int
  salt : Int
  from : Double?
  set_out : Array[(Double, Double)]
}

///|
/// How many times an agent's line has cut words into their cells (working_cells), for its tests to hold how often.
// kept across runs: only counted on, read by its tests alone
let working_cells_made : Ref[Int] = Ref(0)

///|
/// The cells `words` on one line are cut into as an agent's line draws them (@ui.glyph_cells), counted.
fn working_cells(words : String, look : @view.WordsLook, scale : Double, mono? : Bool = false) -> Array[(Double, Double)] {
  working_cells_made.val = working_cells_made.val + 1
  @ui.glyph_cells(words, look, scale, mono~)
}

///|
/// How wide words cut into `cells` are on their line: to their last glyph's end (0: none).
fn cells_wide(cells : Array[(Double, Double)]) -> Double {
  match cells.last() {
    Some((x, w)) => x + w / 2.0
    None => 0.0
  }
}

///|
/// How wide change `ch`'s line is as its width's way is `k` of the way there (0 to 1), `visible` of the row its words
/// have: from the one's width to the other's, each cut to what shows (steady_words' `across`).
fn WorkingChange::across(self : WorkingChange, k : Double, visible : Double) -> Double {
  let from = self.from.unwrap_or(dmin(self.whole_from, visible))
  let to = dmin(self.whole_to, visible)
  from + (to - from) * k
}

///|
/// Where glyph `i` of change `ch`'s words it was (or is: `incoming`) is moved by, and how much narrower it is drawn, as
/// the line's width is `k` of the way (activity_change_glyphs): a glyph of the one and the other at the same place go
/// together from where the old one set out to the new one's place, the wider of them narrowed to the width between;
/// the old words' glyphs past the new's last follow its end, the new's past the old's last come from after its end.
fn WorkingChange::place(self : WorkingChange, k : Double, i : Int, incoming : Bool) -> (Double, Double) {
  let olds = self.was_cells
  let news = self.now_cells
  let set_out = fn(n : Int) { if n < self.set_out.length() { self.set_out[n] } else { (0.0, 1.0) } }
  if i < olds.length() && i < news.length() {
    let (old_x, old_w) = olds[i]
    let (new_x, new_w) = news[i]
    let (d0, s0) = set_out(i)
    let distance = new_x - old_x - d0
    let width = old_w * s0 + (new_w - old_w * s0) * k
    let face_w = if incoming { new_w } else { old_w }
    (
      if incoming { -distance * (1.0 - k) } else { d0 + distance * k },
      if face_w > 0.0 { dmin(width / face_w, 1.0) } else { 1.0 },
    )
  } else if i < olds.length() && news.length() > 0 {
    // (the old words longer: their tail follows the end of the glyphs paired)
    let n = news.length() - 1
    let (old_x, old_w) = olds[n]
    let (new_x, new_w) = news[n]
    let (d0, s0) = set_out(i)
    (d0 + (new_x + new_w / 2.0 - old_x - old_w / 2.0 - d0) * k, s0 + (1.0 - s0) * k)
  } else if i < news.length() && olds.length() > 0 {
    // (the new words longer: their tail comes from after the old's end, its own spacing kept as the room opens)
    let n = olds.length() - 1
    let (old_x, old_w) = olds[n]
    let (new_x, new_w) = news[n]
    let (dn, _) = set_out(n)
    ((old_x + old_w / 2.0 + dn - new_x - new_w / 2.0) * (1.0 - k), 1.0)
  } else {
    (0.0, 1.0)
  }
}

///|
/// How glyph `at` of change `ch`'s words it was (or is: `incoming`) is drawn as its glyphs' way is `reveal` of the way
/// (0 to 1, over glyph_change_in_ms) and the line's width `k` (activity_change_glyphs): at each place the old glyph
/// fades before the new comes (sfbase's glyph_change), in reading order over what shows, each where WorkingChange::place
/// has it.
fn WorkingChange::look(self : WorkingChange, reveal : Double, k : Double, at : @ui.GlyphAt, incoming : Bool) -> @ui.GlyphLook {
  let intervals = if self.places > 1 { self.places - 1 } else { 1 }
  let along = dmin(at.index.to_double() / intervals.to_double(), 1.0)
  let look = @sfbase.glyph_change(
    reveal * @sfbase.glyph_change_in_ms,
    along * @sfbase.glyph_change_line_ms,
    at.index,
    self.salt,
    incoming,
  )
  let (dx, sx) = self.place(k, at.index, incoming)
  { ..look, dx, sx }
}

///|
/// Glyph `at` of a line's first words as they come in, `reveal` of the way (0 to 1, over activity_glyph_in_ms), the
/// line `w` wide as it shows (activity_glyphs): in reading order along it, as a message's words come out (sfbase's
/// glyph_in).
fn working_glyph_in(reveal : Double, w : Double, salt : Int, at : @ui.GlyphAt) -> @ui.GlyphLook {
  let along = if w > 0.0 { dmax(dmin(at.x / w, 1.0), 0.0) } else { 0.0 }
  @sfbase.glyph_in(reveal * activity_glyph_in_ms - activity_glyph_delay_ms, along * @sfbase.glyph_line_ms, at.index, salt)
}

///|
/// What an agent at work says it does in `v` (steady_words' line, as nodes): what `shown` shows (steadied), in `style`
/// (its ink under the pointer), cut short where the line has not the room; its first words coming in glyph by glyph
/// where the row came into its list as they began showing (`came`); each step after them giving way to the next at each
/// glyph's place, the line going from the one's width to the other's (a Move as long as that), cut to `visible` (what
/// of the row its words have), what is past it fading out. Each way from the moment its step began showing, never the
/// frame it was seen; a row made again goes on where its ways are then. The same step's new words show once a change
/// under way is over, as they do at once where none is. `salt`: its row's noise (glyph_noise).
fn working_words_node(
  v : @view.View,
  shown : () -> ActivityShown,
  came : () -> Double?,
  style : () -> @ui.TextStyle,
  visible : () -> Double,
  salt : Int,
) -> Unit {
  @sf.style_node(v, fn() { now_room }, in_row=true)
  v.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
  let arrive = @motion.Way::new(1.0)
  let reveal = @motion.Way::new(1.0)
  let swap = @motion.Way::new(1.0)
  let changing : @signals.Signal[WorkingChange?] = @signals.signal(None)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  v.owns(fn() { (due.val)() }) |> ignore
  v.reacts(
    fn() {
      let s = shown()
      (s.was, s.was_mono, s.at, came())
    },
    fn(_) {
      let s = @signals.untracked(shown)
      (due.val)()
      due.val = fn() {  }
      let under_way = changing.untracked()
      // (its first words: in glyph by glyph where its row came into its list as they began showing, else whole)
      if s.was == "" {
        changing.set(None)
        reveal.put(1.0)
        swap.put(1.0)
        if @signals.untracked(came) == Some(s.at) {
          arrive.put(0.0)
          arrive.go(1.0, @motion.tween(activity_glyph_in_ms, ease=Linear), at=s.at)
        } else {
          arrive.put(1.0)
        }
        return
      }
      arrive.put(1.0)
      let look = @ui.style_words(@signals.untracked(style))
      let scale = v.words_scale()
      let seen = @signals.untracked(visible)
      // (what shows as it begins: the words it was, or where a change still under way had come to then)
      let (was, was_mono, from, set_out) = match under_way {
        Some(p) if swap.goes_at(s.at) => {
          let k = swap.value_at(s.at)
          (p.now, p.now_mono, Some(p.across(k, seen)), p.now_cells.mapi(fn(i, _) { p.place(k, i, true) }))
        }
        _ => (s.was, s.was_mono, None, [])
      }
      let was_cells = working_cells(was, look, scale, mono=was_mono)
      let now_cells = working_cells(s.said.words, look, scale, mono=s.said.mono)
      let ch : WorkingChange = {
        was,
        was_mono,
        now: s.said.words,
        now_mono: s.said.mono,
        was_cells,
        now_cells,
        whole_from: cells_wide(was_cells),
        whole_to: cells_wide(now_cells),
        places: activity_change_places(was_cells, now_cells, seen),
        salt,
        from,
        set_out,
      }
      // (a Move as long as the line's change in width, a line's height at the least)
      let widened = dmin(ch.whole_to, seen) - ch.across(0.0, seen)
      let line = @ui.tree_theme().text_size(Meta).1
      reveal.put(0.0)
      reveal.go(1.0, @motion.tween(@sfbase.glyph_change_in_ms, ease=Linear), at=s.at)
      swap.put(0.0)
      swap.go(1.0, @motion.moved(over=dmax(line, widened.abs())), at=s.at)
      let ends = dmax(reveal.end(), swap.end())
      if ends <= v.cause_at() {
        changing.set(None)
      } else {
        changing.set(Some(ch))
        due.val = v.at_moment(ends, fn() { changing.set(None) })
      }
    },
  )
  v.pick(fn() { changing.get() }, fn(k, ch) {
    match ch {
      None => {
        k.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
        k.box(fn(w) {
          // (how wide its words are whole, worked out as they, their face, their style or their size change, not as
          // they are drawn: what shows told again from another moment, the same words, changes none of those)
          let said = @signals.computed(fn(_) { (shown().said.words, shown().said.mono) }, same=fn(a, b) { a == b })
          let whole = @signals.computed(fn(_) {
            let (words, mono) = said.get()
            cells_wide(working_cells(words, @ui.style_words(style()), w.words_scale(), mono~))
          })
          working_words(w, fn() { shown().said.words }, fn() { shown().said.mono }, style)
          // (cut short where the line has not the room: now_words' w=Cut, what holds it giving way with it)
          .cuts(Is(true))
          .min_width(Is(Some(0.0)))
          .allow_ellipsis(Is(true))
          .glyphs_by(
            By(fn() { (arrive.shown_on(w), dmin(whole.get(), visible())) }),
            fn(st, at) { working_glyph_in(st.0, st.1, salt, at) },
          )
          |> ignore
        })
        |> ignore
      }
      Some(ch) => {
        k.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
        k.box(fn(window) {
          let across = fn() { ch.across(swap.shown_on(window), visible()) }
          window
          .max_width(By(fn() { Some(across()) }))
          .cuts(Is(true))
          .min_width(Is(Some(0.0)))
          .clips(Is(true))
          // (its end faded where the line widens, narrows, or cuts the words short)
          .fades(By(fn() {
            let seen = visible()
            let k = swap.shown_on(window)
            let gone = (ch.across(1.0, seen) - ch.across(0.0, seen)).abs()
            let from_fade = if ch.whole_from > seen + 0.5 { @ui.cut_soft_most } else { 0.0 }
            let to_fade = if ch.whole_to > seen + 0.5 { @ui.cut_soft_most } else { 0.0 }
            (0.0, 0.0, dmax(@ui.cut_soft(gone * k, gone * (1.0 - k)), from_fade * (1.0 - k) + to_fade * k), 0.0)
          }))
          |> ignore
          // (both words whole, one over the other: as wide as the wider, or the line where either is cut)
          window.box(fn(both) {
            both
            .lines_up(Is(Some(Start)))
            .width(By(fn() {
              let seen = visible()
              Some(
                if ch.whole_from > seen + 0.5 || ch.whole_to > seen + 0.5 {
                  across()
                } else {
                  dmax(ch.whole_from, ch.whole_to)
                },
              )
            }))
            |> ignore
            both.box(fn(w) {
              working_words(w, fn() { ch.was }, fn() { ch.was_mono }, style).glyphs_by(
                By(fn() { (reveal.shown_on(w), swap.shown_on(w)) }),
                fn(st, at) { ch.look(st.0, st.1, at, false) },
              )
              |> ignore
            })
            |> ignore
            both.box(fn(layer) {
              layer.over(Is(true)) |> ignore
              @sf.style_node(layer, fn() { now_glyph_layer })
              layer.box(fn(w) {
                working_words(w, fn() { ch.now }, fn() { ch.now_mono }, style).glyphs_by(
                  By(fn() { (reveal.shown_on(w), swap.shown_on(w)) }),
                  fn(st, at) { ch.look(st.0, st.1, at, true) },
                )
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
    }
  })
}

///|
/// Words `words` (in the monospaced face where `mono`) in `w` as an agent's line says them (steady_words' rich words),
/// in `style`.
fn working_words(w : @view.View, words : () -> String, mono : () -> Bool, style : () -> @ui.TextStyle) -> @view.View {
  w
  .words_runs(By(fn() { [@ui.span(words(), mono=mono())] }))
  .words_look(By(fn() { @ui.style_words(style()) }))
  .ink(By(fn() { @ui.style_ink(style()) }))
}
