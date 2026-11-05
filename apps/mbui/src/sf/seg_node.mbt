// A choice of a few as nodes of the window's tree (segmented's, parts.mbt, its wide way: the web's Segmented): a quiet
// pill track, the chosen one lifted out of it (the theme's lifted, a hairline round it) sliding to it as a thing moved
// does (@motion's move_spring), its options equal columns as wide as the widest of their words in the chosen weight with
// segmented_in either side, `item_w` at least; each chosen by a press, the arrows along it, a screen reader's
// Activate, read out as a radio of a group.

///|
/// Its options' columns as segmented has them: each as wide as the widest of their words in the chosen weight with
/// segmented_in either side, `item_w` at least.
fn seg_node_cols(labels : Array[String], item_w : Double) -> Double {
  let c = @ui.current()
  let size = c.sp(theme().t.ui)
  labels.fold(init=item_w, fn(m, l) { dmax(m, choice_words_w(c, l, size, weight=500, tree=true) + 2.0 * segmented_in) })
}

///|
/// A segmented choice of `labels` in `parent`, `chosen()` the one chosen, `choose` told the one a press, an arrow, a
/// screen reader or its pick chooses (the caller says it chosen then: `chosen` follows it), `item_w` each option at
/// least, `said` what a screen reader calls it. Its thumb slides from where it is to the one chosen as that changes, at
/// that moment. Where its columns need more room than there is (its track laid out narrower than they are: it gives
/// way, as segmented's cut to where it is), its options share what there is as option_widths has them, as segmented's
/// do: as alike as their words let them, their sides narrower, else their words smaller alike (to the system's own
/// size of words), else the chosen one alone in its track with a chevron, the others in a pick (@sf.pick) a press on
/// it opens. Always one line, each one's words whole.
pub fn seg_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  item_w? : Double = 0.0,
  said? : String = "",
) -> @view.View {
  // (measured again as all words are, the system's size of words changed: View::words_redone)
  let col = fn() {
    parent.words_redone() |> ignore
    seg_node_cols(labels(), item_w)
  }
  let gaps = fn() { segmented_gap * (labels().length() - 1).to_double() }
  // (as wide as its columns, its track round them: what it is laid out before it gives way)
  let whole = fn() { col() * labels().length().to_double() + gaps() + 2.0 * segmented_pad }
  // (a line of its own round its track, whatever way `parent` lays out what it holds: the track's basis its width
  // there; it gives way as the track does, down to nothing)
  parent.box(fn(line) {
    line.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    line.box(fn(track) {
      // (its options' nodes, for the focus the arrows move)
      let options : Array[@view.View] = []
      let ink = fn() { theme().p.text }
      track
      .row(Is(true))
      .radius(Is(segmented_corner + segmented_pad))
      .ground(By(fn() { alpha(ink(), 0.06) }))
      // (as wide as its columns where its line has the room, giving way to what it has: down to nothing, its options
      // fitted to it)
      .basis(By(fn() { Some(whole()) }))
      // (as high as its options with its pad round them: not stretched to its line's height)
      .height(Is(Some(segmented_h + 2.0 * segmented_pad)))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      // (a roving group, as @kit.toggle_group's: Tab stops at the chosen one alone; ← and → go to the one before and after,
      // round from the ends, Home and End to the first and the last, each chosen and its focus as it is)
      .on_key(fn(k) {
        let n = @signals.untracked(labels).length()
        let now = @signals.untracked(chosen)
        // (only while one of its options has the focus: none of the window's arrows else)
        let focused = options.iter().any(fn(o) { o.focused() })
        let to = if n == 0 || k.mods != 0 || !focused {
          None
        } else if k.code == @ui.key_code_left {
          Some((now + n - 1) % n)
        } else if k.code == @ui.key_code_right {
          Some((now + 1) % n)
        } else if k.code == @ui.key_code_home {
          Some(0)
        } else if k.code == @ui.key_code_end {
          Some(n - 1)
        } else {
          None
        }
        match to {
          Some(i) => {
            if i != now {
              choose(i)
            }
            match options.get(i) {
              Some(o) => o.ask_focus(visible=true) |> ignore
              None => ()
            }
            true
          }
          _ => false
        }
      })
      |> ignore
      // what it holds as the room its track is laid out in calls for (View::by_room, in the same layout: nothing of the
      // track's size read back): its columns whole where they fit, else fitted to it as segmented's (fitted), each way
      // its own child
      let fits : Map[String, Fitted?] = {}
      track.by_room(
          // (what the choice reads but the room: its words, their columns and gaps, the size of its words as the theme
          // and the system's size of words have it; taken before the layout, followed)
          By(fn() {
            track.words_redone() |> ignore
            (labels(), col(), gaps(), theme().t.ui)
          }),
          fn(at, room, _) {
            let (words, col, gaps, size) = at
            // (what its options have of the track's room: its pad round them, made by the child it picks)
            let w = room - 2.0 * segmented_pad
            if w < col * words.length().to_double() + gaps - 0.5 {
              let f = fitted(@ui.current(), words, w - gaps, size, 500, segmented_in, segmented_least, tree=true)
              let key = "\{f.fit} \{f.widths}"
              fits[key] = Some(f)
              key
            } else {
              fits["whole"] = None
              "whole"
            }
          },
          fn(v, key) {
            let f = fits.get(key).unwrap_or(None)
            // (what the pick worked out for it let go with it: one kept for each arrangement made, none for a room passed)
            v.owns(fn() { fits.remove(key) }) |> ignore
            // (each option's width: its column, or its share of the room as fitted; its words that much smaller)
            let widths = fn() {
              match f {
                Some({ widths, fit: Whole | Smaller(_) }) => widths
                _ => Array::make(labels().length(), col())
              }
            }
            let smaller = fn() {
              match f {
                Some({ fit: Smaller(k), .. }) => k
                _ => 1.0
              }
            }
            let x_of = fn(k : Int) {
              let ws = widths()
              let mut x = segmented_pad
              for i in 0..<k {
                x = x + ws.get(i).unwrap_or(0.0) + segmented_gap
              }
              x
            }
            let w_of = fn(k : Int) { widths().get(k).unwrap_or(0.0) }
            // not side by side: the chosen one's words as its option has them (cut short where they must be), a chevron at
            // its end; pressed, a pick of them all beside it, the chosen one marked (search none: a few short words)
            // (its pad round what it holds: the track's, laid out by its room and filled by it)
            v.padding(Is((segmented_pad, segmented_pad, segmented_pad, segmented_pad))) |> ignore
            if f is Some({ fit: Menu, .. }) {
              v.box(fn(m) {
              let words = fn() { labels().get(chosen()).unwrap_or("") }
              // (the pick it opened, as presented: 0, none yet; open while it is drawn, presented_drawn_of)
              let opened : @signals.Signal[Int] = @signals.signal(0)
              let open = fn() {
                let s = opened.get()
                s != 0 && presented_drawn_of(s)
              }
              m
              .row(Is(true))
              .grow(Is(1.0))
              .height(Is(Some(segmented_h)))
              .lines_up(Is(Some(Middle)))
              .padding(Is((segmented_least, 0.0, segmented_least, 0.0)))
              .gap(Is(segmented_least))
              .presses(Is(true))
              .focusable(Is(true))
              .says(By(fn() {
                Some(@view.said(Button, label=if said == "" { words() } else { said + " " + words() }, expanded=open()))
              }))
              .on_press(fn() {
                let (x, y, w, h) = m.rect()
                let all = @signals.untracked(labels)
                let now = @signals.untracked(chosen)
                pick(
                  "",
                  all.mapi(fn(i, l) { choice(i.to_string(), l) }),
                  now.to_string(),
                  fn(k) {
                    let i = labels_at(all, k, now)
                    if i != now {
                      choose(i)
                    }
                  },
                  from=At(x, y, w, h),
                  search=false,
                )
                opened.set(last_presented())
              })
              |> ignore
              m.box(fn(w) {
                w
                .grow(Is(1.0))
                .shrink(Is(1.0))
                .min_width(Is(Some(0.0)))
                .words(By(words))
                .words_look(By(fn() {
                  let size = theme().t.ui
                  { size, weight: 500, line: @ui.tree_theme().text_line * size, wrap: false, tracking: @view.letters_own, balance: false }
                }))
                .ink(By(ink))
                |> ignore
              })
              |> ignore
              icon_node(m, "chevron-down", segmented_chevron, By(fn() { theme().p.muted })) |> ignore
              })
              |> ignore
            } else {
              // side by side: the thumb, under the options' words, and the options; read out as a group, the whole of
              // the track
              v.says(Is(Some(@view.said(RadioGroup, label=said)))) |> ignore
              v.box(fn(strip) {
              options.clear()
              // (the thumb's way from where the chosen one is in this arrangement)
              let way = @motion.Way::new(@signals.untracked(fn() { x_of(chosen()) }))
              strip.row(Is(true)).gap(Is(segmented_gap)) |> ignore
              // (the thumb's way said at the moment the chosen one changes, from where it is then; where only where it is
              // changes, its columns another width (the words' size, their language, the room), there at once)
              let last = Ref(@signals.untracked(chosen))
              strip.reacts(fn() { (chosen(), x_of(chosen())) }, fn(at) {
                let (k, x) = at
                if k == last.val {
                  way.put(x)
                } else {
                  way.go(x, @motion.move_spring, at=strip.cause_at())
                }
                last.val = k
              })
              // the thumb: where its way has it, as each frame draws it while it goes, as wide as the chosen one
              strip.box(fn(th) {
                let x = fn() {
                  way.said()
                  let now = th.logic_at()
                  way.value_at(if way.goes_at(now) { th.drawn_at() } else { @double.infinity })
                }
                th
                .over(Is(true))
                .offset(By(fn() { (x() - segmented_pad, 0.0) }))
                .width(By(fn() { Some(w_of(chosen())) }))
                .height(Is(Some(segmented_h)))
                .radius(Is(segmented_corner))
                .ground(By(fn() { @ui.tree_theme().lifted }))
                .edge(By(fn() { (0.5, theme().p.line) }))
                .shadow(By(fn() { (1.0, 0.0, theme().p.shadow) }))
                |> ignore
              })
              |> ignore
              // its options (as many as there are as it is made; their words as they are said, in the language as it is): their
              // words in their middle, in the chosen weight and ink where chosen or pointed at, smaller as fitted
              for k in 0..<@signals.untracked(labels).length() {
                let label = fn() { labels().get(k).unwrap_or("") }
                let on = fn() { chosen() == k }
                strip.box(fn(o) {
                  o
                  .width(By(fn() { Some(w_of(k)) }))
                  .height(Is(Some(segmented_h)))
                  // (its words in its middle both ways, as the old view's option is: align and justify centre)
                  .lines_up(Is(Some(Middle)))
                  .lies_along(Is(Middle))
                  .presses(Is(true))
                  .focusable(Is(true))
                  .tab_stop(By(on))
                  .says(By(fn() { Some(@view.said(Radio, label=label(), check=if on() { On } else { Off })) }))
                  .on_press(fn() {
                    if !@signals.untracked(on) {
                      choose(k)
                    }
                  })
                  |> ignore
                  options.push(o)
                  o.box(fn(w) {
                    w
                    .words(By(label))
                    .words_look(By(fn() {
                      let size = theme().t.ui * smaller()
                      // (its line so many times its size as drawn, at the system's size of words: an old view's words' as
                      // Ctx::text has them, where none is said (a negative line: view_line's))
                      { size, weight: if on() { 500 } else { 400 }, line: -@ui.tree_theme().text_line, wrap: false, tracking: @view.letters_own, balance: false }
                    }))
                    .ink(By(fn() {
                      if on() || o.pointed() {
                        ink()
                      } else {
                        theme().p.muted
                      }
                    }))
                    |> ignore
                  })
                  |> ignore
                })
                |> ignore
              }
              })
              |> ignore
            }
          },
        )
        |> ignore
    })
    |> ignore
  })
}

///|
/// A sliding group's lens's shadow, held all the way (@kit.toggle_group's): its blur and how far down.
let seg_lens_shadow : Double = 6.0

///|
let seg_lens_shadow_y : Double = 2.0

///|
/// A narrow page's choice of a few (seg's filling Seg, as nodes: segmented's on a narrow page) in `parent`: as wide as
/// where it is, `labels` sharing it alike, none narrower than its words with their sides (fitted: where they need more,
/// their sides narrower, else their words smaller alike, else the chosen one alone with a chevron, the others in a pick a
/// press on it opens), on a track the ink at 6%, 34 high, 2 in, 10 round; a thumb lifted out of it (the theme's lifted,
/// a hairline round it) under the chosen one's words, sliding to the one chosen as that changes, from where it is then,
/// as a cover does (@ui.Ctx::cover: on its spring, between where those options are laid out as it is drawn); a finger
/// held on an option (glass not drawn solid), the thumb there, fading under a lens of liquid glass growing over it, the
/// option chosen as it is let go on it. `chosen()` the one chosen; `choose` told the one a press, an arrow, a screen
/// reader or its pick chooses (the caller says it chosen then: `chosen` follows it); `said` what a screen reader calls
/// it. As wide as where it is laid out, its words at the system's size of words, in the language as it is, as those
/// change. `labels()` says how many options there are once, as it is made: their words may change (another language),
/// their number not.
pub fn seg_fill_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  said? : String = "",
) -> @view.View {
  parent.box(fn(track) {
    // how its options share the room its track is laid out in, as seg's, worked out as it is laid out (View::by_room:
    // nothing of its size read back): where their words with their sides come to more than it, fitted to it (seg's
    // fitted); else shared alike, none narrower than its words with their sides (Seg's flex, as the layout shared it):
    // each option's width, how much smaller its words, whether it is the chosen one alone with a chevron, and the track's
    // room (its corners'), by the arrangement's key
    let fits : Map[String, (Array[Double], Double)] = {}
    let options : Array[@view.View] = []
    track
    .row(Is(true))
    .height(Is(Some(segmented_narrow_h)))
    .radius(Is(seg_radius))
    .ground(By(fn() { alpha(theme().p.text, 0.06) }))
    // (a roving group, as @kit.toggle_group's: Tab stops at the chosen one alone; ← and → go to the one before and after,
    // round from the ends, Home and End to the first and the last, each chosen and its focus as it is)
    .on_key(fn(k) {
      let n = @signals.untracked(labels).length()
      let now = @signals.untracked(chosen)
      let focused = options.iter().any(fn(o) { o.focused() })
      let to = if n == 0 || k.mods != 0 || !focused {
        None
      } else if k.code == @ui.key_code_left {
        Some((now + n - 1) % n)
      } else if k.code == @ui.key_code_right {
        Some((now + 1) % n)
      } else if k.code == @ui.key_code_home {
        Some(0)
      } else if k.code == @ui.key_code_end {
        Some(n - 1)
      } else {
        None
      }
      match to {
        Some(i) => {
          if i != now {
            choose(i)
          }
          match options.get(i) {
            Some(o) => o.ask_focus(visible=true) |> ignore
            None => ()
          }
          true
        }
        _ => false
      }
    })
    |> ignore
    // the thumb's and the lens's cover (@ui.Ctx::cover's): the item it goes to, what it set out from (items by their
    // shares) and how far it is from there (0 to 1, on a cover's spring), sent on as it goes to another item (`aim`, as
    // the options laid out say it), from that moment; where it is laid out the blend of where those items are laid out
    // in the same layout (moved or resized meanwhile: with them). The track's: a thumb on its way goes on from where it
    // is whichever way its options share its room as it changes; at rest on the chosen one as they come back side by
    // side from the chosen one alone with a chevron (`apart`), as made again
    let first = @signals.untracked(chosen)
    let aim : @signals.Signal[Int] = @signals.signal(first)
    let cover : @signals.Signal[(Array[(Int, Double)], Int)] = @signals.signal(([(first, 1.0)], first))
    let way = EdgeWay::new(1.0)
    let apart = Ref(false)
    track.reacts(fn() { aim.get() }, fn(k) {
      let (from, to) = @signals.untracked(fn() { cover.get() })
      if k != to {
        let p = way.way.value_at(track.cause_at())
        cover.set((@ui.cover_set_out(from, to, p), k))
        way.go_from(track, 0.0, 1.0, @motion.cover_spring)
      }
    })
    // (the lens out while a finger holds an option of the options laid out (`lens_on`, as they say it), on the hand's
    // spring: let go as they are made again another way, with the finger's hold)
    let lens_on : @signals.Signal[Bool] = @signals.signal(false)
    let held = EdgeWay::new(0.0)
    track.reacts(fn() { lens_on.get() }, fn(down) { held.go_by(track, if down { 1.0 } else { 0.0 }, @motion.lift_spring) })
    let lens = fn() { if @ui.current().glass_solid() { 0.0 } else { held.shown(track) } }
    track.by_room(
      // (what the choice reads but the room: its words, and their size as the theme and the system's size of words have
      // it; taken before the layout, followed)
      By(fn() {
        track.words_redone() |> ignore
        (labels(), @ui.tree_theme().text_size(Base).0)
      }),
      fn(at, room, _) {
        let (words, base) = at
        let c = @ui.current()
        let size = c.sp(base)
        let w = room - 2.0 * seg_inset
        let need = words.fold(init=0.0, fn(s, l) { s + choice_words_w(c, l, size, tree=true) + 2.0 * seg_side })
        if need > w + 0.5 {
          let ft = fitted(c, words, w, base, 400, seg_side, seg_least, tree=true)
          match ft.fit {
            Menu => "menu"
            Whole | Smaller(_) => {
              let k = match ft.fit {
                Smaller(k) => k
                _ => 1.0
              }
              let key = "fitted \{ft.widths} \{k}"
              fits[key] = (ft.widths, k)
              key
            }
          }
        } else {
          "shared"
        }
      },
      fn(v, key) {
        let (fixed, smaller) = fits.get(key).unwrap_or(([], 1.0))
        // (what the pick worked out for it let go with it: one kept for each arrangement made)
        v.owns(fn() { fits.remove(key) }) |> ignore
        // (its pad round what it holds: the track's, laid out by its room and filled by it)
        v.row(Is(true)).padding(Is((seg_inset, seg_inset, seg_inset, seg_inset))) |> ignore
        options.clear()
        if key == "menu" {
          apart.val = true
          seg_fill_menu(v, labels, chosen, choose, said)
          return
        }
        // side by side: the thumb under the options' words, and the options; read out as a group, the whole track
        v.says(Is(Some(@view.said(RadioGroup, label=said)))) |> ignore
        v.box(fn(strip) {
          strip.grow(Is(1.0)) |> ignore
          // (a finger held on an option, where glass is not drawn solid: the thumb there, a lens over it; the one chosen
          // only as it is let go on it, @kit.toggle_group's. These options' own: let go with them as they are made
          // again another way, the lens with it)
          let fingered : @signals.Signal[Int] = @signals.signal(-1)
          let lensed = fn() { !@ui.current().glass_solid() && fingered.get() >= 0 }
          strip.reacts(lensed, fn(down) { lens_on.set(down) })
          let at = fn() { if lensed() { fingered.get() } else { chosen() } }
          strip.reacts(at, fn(k) {
            // (back side by side from the chosen one alone: the thumb on it, still)
            if apart.val {
              apart.val = false
              cover.set(([(k, 1.0)], k))
              way.put(1.0)
            }
            aim.set(k)
          })
          let h = segmented_narrow_h - 2.0 * seg_inset
          // (each of its corners as the corner rule makes it in the track's (@ui corners.mbt), from where it and the track
          // are laid out as it is painted: concentric with the track's where it lies in that corner as far from both its
          // edges, at an end or a hair short of it on its way there, as the theme's ranges let it be; else its own.
          // Nothing between them cuts a corner of the track's: the rule's own conditions, here, are these)
          let thumb_corners = fn(x : Double, w : Double, h : Double, room : Double) -> (Double, Double, Double, Double)? {
            let own = inner_corner(seg_radius, seg_inset)
            let (l, t, rr, d) = (x, seg_inset, room - x - w, seg_inset)
            let half = dmin(w, h) / 2.0
            let fit = @ui.tree_theme().corner_fit
            let rs = FixedArray::make(4, own)
            let mut moved = 0
            for k in 0..<4 {
              match @ui.corner_lies_in(k, l, t, rr, d, seg_radius) {
                Some(inset) =>
                  match @ui.corner_following(own, half, seg_radius, inset, fit) {
                    Some(kk) => {
                      rs[k] = kk
                      moved += 1
                    }
                    None => ()
                  }
                None => ()
              }
            }
            if @ui.corners_kept(rs, moved) {
              Some((rs[0], rs[1], rs[2], rs[3]))
            } else {
              None
            }
          }
          // the thumb: where its cover has it, its corner concentric in the track's; faded under the lens
          let make_thumb = fn(th : @view.View) {
            th
            .radius(Is(inner_corner(seg_radius, seg_inset)))
            .corners(Painted(fn(laid) {
              match (laid.rect(th), laid.rect(track)) {
                (Some((x, _, w, h)), Some((tx, _, tw, _))) => thumb_corners(x - tx, w, h, tw)
                _ => None
              }
            }))
            .ground(By(fn() { @ui.tree_theme().lifted }))
            .edge(By(fn() { (0.5, theme().p.line) }))
            // (as the old thumb: faded only while the lens is out, not past 1 as the hand's spring comes back past 0)
            .alpha(By(fn() {
              let l = lens()
              if l > 0.0 {
                1.0 - dmin(1.0, l)
              } else {
                1.0
              }
            }))
            |> ignore
          }
          // its options: its words in its middle, the chosen one's in the ink, the others muted, smaller as fitted
          let make_option = fn(o : @view.View, k : Int) {
            let label = fn() { labels().get(k).unwrap_or("") }
            let on = fn() { chosen() == k }
            // (another chosen by a finger: felt, as @kit.toggle_group's)
            let press = fn() {
              if !@signals.untracked(on) {
                if @ui.pointing() is Finger {
                  @ui.haptic(TextHandleMove)
                }
                choose(k)
              }
            }
            o
            .row(Is(true))
            .lines_up(Is(Some(Middle)))
            // (its words in its middle, as laid out: seg_full_option's justify)
            .lies_along(Is(Middle))
            .presses(Is(true))
            .focusable(Is(true))
            .tab_stop(By(on))
            .says(By(fn() { Some(@view.said(Radio, label=label(), check=if on() { On } else { Off })) }))
            .on_press(press)
            |> ignore
            // (a finger let go on it chooses it, however long it was held (no hold of its own: under a lens it is still its
            // press, as @kit.toggle_group's, Ctx::interact's `holds`) and wherever it went meanwhile, as an old view's
            // click; called off, or taken by what holds it (a list, as it moves), nothing)
            let on_it = fn(d : @view.Drag) { o.finger_target(d.wx, d.wy) }
            o.gesture(
              @ui.touch_slop(),
              tap=fn(d) { if on_it(d) { press() } },
              drag=fn(d) { if d.kind == Up && on_it(d) { press() } },
            )
            |> ignore
            o.reacts(fn() { o.pressed() && @ui.pointing() is Finger }, fn(down) {
              if down {
                fingered.set(k)
              } else if @signals.untracked(fn() { fingered.get() }) == k {
                fingered.set(-1)
              }
            })
            options.push(o)
            o.box(fn(w) {
              w
              .words(By(label))
              .words_look(By(fn() {
                // (Base, on its own line, as Seg's words: both that much smaller where fitted as drawn, after the system's size
                // of words applies, as Ctx::words_smaller has them: said by the size that draws them so)
                o.words_redone() |> ignore
                let (size, line) = @ui.tree_theme().text_size(Base)
                let k = smaller
                let c = @ui.current()
                let (size, line) = if k == 1.0 { (size, line) } else { (c.sp_of(c.sp(size) * k), c.sp_of(c.sp(line) * k)) }
                { size, weight: 400, line, wrap: false, tracking: @view.letters_own, balance: false }
              }))
              .ink(By(fn() { if on() { theme().p.text } else { theme().p.muted } }))
              |> ignore
            })
            |> ignore
          }
          // held by a finger: the thumb a lens of liquid glass over the options (iOS 26's), a capsule on the thumb's way,
          // larger as it is held (past the track's edges), raised off it by a shadow as far as it is in the finger
          let make_lens = fn(l : @view.View) {
            let full = fn() { dmin(1.0, lens()) }
            l
            // (round as a pill is said to be, Full, as the old lens's capsule: as round as it can be)
            .radius(Is(1.0e6))
            .glass(Is(Some(glass_knob())))
            .shadow(By(fn() { (seg_lens_shadow * full(), seg_lens_shadow_y * full(), @ui.tree_theme().shadow) }))
            .alpha(By(full))
            .scale(By(fn() { 1.0 + (seg_lens_grow - 1.0) * lens() }))
            |> ignore
          }
          // laid out by its room (View::layout_box: nothing of its size read back): each option's width as fitted, or
          // the room shared alike, none narrower than its words with their sides (Seg's flex); the thumb and the lens
          // where the cover has them among those, under the options and over them
          strip.layout_box(
            By(fn() {
              strip.words_redone() |> ignore
              let c = @ui.current()
              let size = c.sp(@ui.tree_theme().text_size(Base).0)
              let least = labels().map(fn(l) { choice_words_w(c, l, size, tree=true) + 2.0 * seg_side })
              (least, cover.get(), way.shown(track), lens())
            }),
            fn(l, at) {
              let (least, (from, to), p, lensing) = at
              let ws = if fixed.length() > 0 { fixed } else { seg_shared(least, l.width) }
              let xs = Array::make(ws.length(), 0.0)
              for k in 1..<ws.length() {
                xs[k] = xs[k - 1] + ws[k - 1]
              }
              let rect = @ui.cover_rect(from, to, p, fn(k) {
                if k >= 0 && k < ws.length() { Some((xs[k], 0.0, ws[k], h)) } else { None }
              })
              let shown = ws.get(to).unwrap_or(0.0) > 0.0
              match rect {
                Some((x, _, w, _)) if shown => {
                  let th = l.child("thumb", make_thumb)
                  l.measure(th, w, height=h) |> ignore
                  l.place(th, x, 0.0)
                }
                _ => ()
              }
              for k in 0..<ws.length() {
                let o = l.child("option \{k}", fn(o) { make_option(o, k) })
                l.measure(o, ws[k], height=h) |> ignore
                l.place(o, xs[k], 0.0)
              }
              match rect {
                Some((x, _, w, _)) if lensing > 0.0 => {
                  let lv = l.child("lens", make_lens)
                  l.measure(lv, w, height=h) |> ignore
                  l.place(lv, x, 0.0)
                }
                _ => ()
              }
            },
          )
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
}

///|
/// A narrow page's choice of a few too short for its options side by side (seg_fill_node's), in `v`: the chosen one's
/// words (cut short where they must be), a chevron at its end; pressed, a pick of them all beside it, the chosen one
/// marked.
fn seg_fill_menu(v : @view.View, labels : () -> Array[String], chosen : () -> Int, choose : (Int) -> Unit, said : String) -> Unit {
  v.box(fn(m) {
    let words = fn() { labels().get(chosen()).unwrap_or("") }
    let opened : @signals.Signal[Int] = @signals.signal(0)
    let open = fn() {
      let s = opened.get()
      s != 0 && presented_drawn_of(s)
    }
    m
    .row(Is(true))
    .grow(Is(1.0))
    .lines_up(Is(Some(Middle)))
    .padding(Is((seg_menu_in, 0.0, seg_menu_in, 0.0)))
    .gap(Is(seg_menu_gap))
    .presses(Is(true))
    .focusable(Is(true))
    .says(By(fn() {
      Some(@view.said(Button, label=if said == "" { words() } else { said + " " + words() }, expanded=open()))
    }))
    .on_press(fn() {
      let (x, y, w, h) = m.rect()
      let all = @signals.untracked(labels)
      let now = @signals.untracked(chosen)
      pick(
        "",
        all.mapi(fn(i, l) { choice(i.to_string(), l) }),
        now.to_string(),
        fn(k) {
          let i = labels_at(all, k, now)
          if i != now {
            choose(i)
          }
        },
        from=At(x, y, w, h),
        search=false,
      )
      opened.set(last_presented())
    })
    |> ignore
    // (where even its ellipsis has not the room, that drawn past its words' box into the gap before the chevron, as
    // seg_menu_words' `w=Cut` words are drawn)
    m.box(fn(w) { styled_words(w.grow(Is(1.0)), words, fn() { seg_menu_words }).ellipsis_past(Is(true)) |> ignore })
    |> ignore
    icon_node(m, "chevron-down", seg_chevron, By(fn() { theme().p.muted })) |> ignore
  })
  |> ignore
}

///|
/// Room `w` shared alike among options at least `least` wide each (flex's, each growing from nothing alike, none below
/// its least): those whose share is under their least held at it, the rest sharing what is left, until none is.
fn seg_shared(least : Array[Double], w : Double) -> Array[Double] {
  let n = least.length()
  let held = Array::make(n, false)
  let mut free = w
  let mut left = n
  let mut changed = true
  while changed && left > 0 {
    changed = false
    let share = free / left.to_double()
    for i in 0..<n {
      if !held[i] && least[i] > share {
        held[i] = true
        free = free - least[i]
        left = left - 1
        changed = true
      }
    }
  }
  let share = if left > 0 { free / left.to_double() } else { 0.0 }
  least.mapi(fn(i, l) { if held[i] { l } else { share } })
}

///|
/// A filling Seg's corner (seg's `radius`, 10).
let seg_radius : Double = 10.0

///|
/// How wide a filling Seg of `labels` is with their words whole at their size with their sides, and how narrow it may
/// go: the chosen one's (the widest's) words with the chevron (seg_room's, the old view's), as node `v` has the system's
/// size of words and the theme as they change (a binding reading it follows them).
fn seg_room_of(v : @view.View, labels : Array[String]) -> (Double, Double) {
  v.words_redone() |> ignore
  let c = @ui.current()
  let t = @ui.tree_theme()
  let size = c.sp(t.text_size(Base).0)
  let whole = labels.fold(init=2.0 * seg_inset, fn(s, l) { s + choice_words_w(c, l, size, tree=true) + 2.0 * seg_side })
  let menu = c.sp(t.text_size(Body).0)
  let widest = labels.fold(init=0.0, fn(m, l) { dmax(m, choice_words_w(c, l, menu, tree=true)) })
  (whole, 2.0 * seg_inset + 2.0 * seg_menu_in + widest + seg_menu_gap + seg_chevron)
}

///|
/// A narrow page's choice at a head's end (segmented's there: seg_room), in `parent`: a Seg as wide as its options
/// with their words whole at their size with their sides, as narrow as the chosen one's (the widest's) words with the
/// chevron where its line has less (giving way first: what is at a head's end does), filling what that leaves it, as
/// seg_fill_node is; its words at the system's size of words as that changes. `labels`, `chosen`, `choose`, `said`:
/// seg_fill_node's.
pub fn seg_head_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  said? : String = "",
) -> @view.View {
  parent.box(fn(b) {
    let room = fn() { seg_room_of(b, labels()) }
    b
    .width(By(fn() { Some(room().0) }))
    .min_width(By(fn() { Some(room().1) }))
    .shrink(Is(1.0))
    |> ignore
    seg_fill_node(b, labels, chosen, choose, said~) |> ignore
  })
}

///|
/// A choice of a few on a page made once (segmented's), by how the page is laid out (look_node), in `slot`, which it
/// lays out: narrow, Seg (seg_fill_node) sharing its line, the slot growing from none to what the line leaves it, or
/// at a head's end (`head`) as wide as its options (seg_head_node); wide, the web's Segmented (seg_node), as wide as
/// its options, the slot as wide as it. `labels`, `chosen`, `choose`, `said`: theirs.
pub fn segmented_node(
  slot : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  head? : Bool = false,
  said? : String = "",
) -> Unit {
  match look_node(slot) {
    Wide => seg_node(slot, labels, chosen, choose, said~) |> ignore
    Narrow if head => seg_head_node(slot, labels, chosen, choose, said~) |> ignore
    Narrow => {
      slot.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      seg_fill_node(slot, labels, chosen, choose, said~) |> ignore
    }
  }
}

///|
/// How high segmented_node stands in a page laid out `look`: wide, the web's Segmented's track round its options; narrow,
/// Seg's (segmented_height's).
pub fn segmented_node_height(look : Look) -> Double {
  match look {
    Narrow => segmented_narrow_h
    Wide => segmented_h + 2.0 * segmented_pad
  }
}
