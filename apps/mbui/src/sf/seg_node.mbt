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
  labels.fold(init=item_w, fn(m, l) { dmax(m, choice_words_w(c, l, size, weight=500) + 2.0 * segmented_in) })
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
      // how its options fit the room its track was laid out in (none: their columns whole), as segmented's
      let fit : () -> Fitted? = fn() {
        match track.laid_size_told() {
          Some((w, _)) if w < whole() - 0.5 => {
            track.words_redone() |> ignore

            Some(fitted(@ui.current(), labels(), w - 2.0 * segmented_pad - gaps(), theme().t.ui, 500, segmented_in, segmented_least))
          }
          _ => None
        }
      }
      let menu = fn() { fit() is Some({ fit: Menu, .. }) }
      // (each option's width: its column, or its share of the room as fitted; its words that much smaller)
      let widths = fn() {
        match fit() {
          Some({ widths, fit: Whole | Smaller(_) }) => widths
          _ => Array::make(labels().length(), col())
        }
      }
      let smaller = fn() {
        match fit() {
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
      // (where its thumb is along the track, as its way has it: off to the chosen one's place as that changes, from where
      // it is then)
      let way = @motion.Way::new(@signals.untracked(fn() { x_of(chosen()) }))
      // (its options' nodes, for the focus the arrows move)
      let options : Array[@view.View] = []
      let ink = fn() { theme().p.text }
      track
      .row(Is(true))
      .padding(Is((segmented_pad, segmented_pad, segmented_pad, segmented_pad)))
      .radius(Is(segmented_corner + segmented_pad))
      .ground(By(fn() { alpha(ink(), 0.06) }))
      // (as wide as its columns where its line has the room, giving way to what it has: down to nothing, its options
      // fitted to it)
      .basis(By(fn() { Some(whole()) }))
      // (as high as its options with its pad round them: not stretched to its line's height)
      .height(Is(Some(segmented_h + 2.0 * segmented_pad)))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .says(By(fn() { if menu() { None } else { Some(@view.said(RadioGroup, label=said)) } }))
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
      // side by side: the thumb, under the options' words, and the options
      track.show(fn() { !menu() }, fn(strip) {
        options.clear()
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
            .lines_up(Is(Some(Middle)))
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
                { size, weight: if on() { 500 } else { 400 }, line: @ui.tree_theme().text_line * size, wrap: false }
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
      // not side by side: the chosen one's words as its option has them (cut short where they must be), a chevron at its
      // end; pressed, a pick of them all beside it, the chosen one marked (search none: a few short words)
      track.show(menu, fn(m) {
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
            { size, weight: 500, line: @ui.tree_theme().text_line * size, wrap: false }
          }))
          .ink(By(ink))
          |> ignore
        })
        |> ignore
        icon_node(m, "chevron-down", segmented_chevron, By(fn() { theme().p.muted })) |> ignore
      })
    })
    |> ignore
  })
}
