// The bar of a page in a panel of its own on the tape (pane_page.mbt's pane_bar) as a node of the window's tree, made
// once: as high as a chat's bar there, its line on the tape's; back a round button before the title, concentric with
// the panel's top left corner; the title, what the page is of after it, the mark saying what it is for; its end clear
// of the panel's top right corner (tape_bar_end). Where it stands worked out from the panel's corners as they are told
// it (`corners`), none of it from the page being built (pane_round) nor the frame's said fields (wide's bar_*). What it
// shows bound to what it is told, each as it changes; the same node however the page's bar changes.

///|
/// What a page's bar on the tape shows (pane_page's: @sf.PageBar's, its title the one the bar shows), compared by
/// what it shows: back's words (none: no back), the title, what the page is of, what it is for.
#derive(Eq)
priv struct PaneBarSaid {
  back : String?
  title : String
  small : String
  about : String
}

///|
/// The bar in `parent`, as `said` says it as it changes (none: nothing in it), back done by `back` as it is pressed; the
/// panel's corners `corners` (its top left and top right where its ends stand), its ground `ground`, its tips in
/// `tips`; its words as a page `width` wide has them (@sf.look_for: the page's look, as its page's bar was built in);
/// nothing of it read out while `hidden` (the panel not in use, as what is under it: tape_behind); what its page does
/// (`actions`: what makes it, how tall it stands in a page laid out so) at its end. The node.
fn pane_bar_node(
  parent : @view.View,
  said : () -> PaneBarSaid?,
  back : () -> Unit,
  corners : () -> FixedArray[@ui.CornerOf],
  ground : () -> Int64,
  tips : @sf.TipLayer,
  width : () -> Double,
  hidden : () -> Bool,
  actions? : () -> ((@view.View) -> Unit, (@sf.Look) -> Double, Int)?,
) -> @view.View {
  let actions = match actions {
    Some(f) => f
    None => fn() { None }
  }
  let now = fn() {
    match said() {
      Some(s) => s
      None => { back: None, title: "", small: "", about: "" }
    }
  }
  parent.box(fn(bar) {
    bar
    .row(Is(true))
    .height(By(fn() { Some(pane_bar_h()) }))
    .padding(By(fn() { (0.0, @ui.Space::px(@sf.tape_bar_over_room()), 0.0, 1.0) }))
    .lines_up(Is(Some(Middle)))
    .ground(By(ground))
    .hides(By(hidden))
    |> ignore
    // (its rooms at its ends, what is in it 16 apart and not from them; back in the panel's top left corner concentric
    // with it)
    bar_room_node(bar, fn() { tape_bar_start_room(corners(), now().back is Some(_)) })
    bar.box(fn(inner) {
      bar_fills(inner.row(Is(true)).lines_up(Is(Some(Middle)))) |> ignore
      // (16 between back and the title, none where there is no back: chat_bar_inner's gap)
      inner.show(fn() { now().back is Some(_) }, fn(b) {
        b.padding(Is((0.0, 0.0, @ui.Space::px(S4), 0.0))) |> ignore
        @sf.icon_button_node(b, "chevron-left", fn() { now().back.unwrap_or("") }, back, tips~) |> ignore
      })
      inner.box(fn(t) {
        bar_fills(
          t
          .row(Is(true))
          .padding(Is((@ui.Space::px(S2), 0.0, @ui.Space::px(S1), 0.0)))
          .lines_up(Is(Some(Middle))),
        )
        |> ignore
        // (10 before each that follows the title, none for what is not there: chat_bar_title_row's gap)
        bar_words(t, fn() { now().title }, chat_title_words, width)
        t.show(fn() { now().small != "" }, fn(s) {
          s.padding(Is((@ui.Space::px(S2_5), 0.0, 0.0, 0.0))) |> ignore
          bar_words(s, fn() { now().small }, pane_bar_small, width)
        })
        t.show(fn() { now().about != "" }, fn(a) {
          a.padding(Is((@ui.Space::px(S2_5), 0.0, 0.0, 0.0))) |> ignore
          @sf.about_mark_node(a, fn() { now().about }, fn() { @sf.t("web-main.about") }, tips) |> ignore
        })
      })
      |> ignore
      // (what the page does at its end, as a bar's actions are laid out whatever the page's width (wide: the old
      // view's pane_bar called them outside the page's look, the library's look Wide where none is said), its keys
      // apart as a bar's are (pane_bar's keys_row); made again as the page that gives them is made again)
      inner.show(fn() { actions() is Some(_) }, fn(a) {
        // (16 after the title, as chat_bar_inner's gap)
        a.padding(Is((@ui.Space::px(S4), 0.0, 0.0, 0.0))) |> ignore
        a.pick(
          fn() {
            match actions() {
              Some((_, _, g)) => g
              None => 0
            }
          },
          fn(k, _) {
            @sf.pane_bar_actions_lent(k)
            k.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@sf.keys_apart())) |> ignore
            match @signals.untracked(actions) {
              Some((make, _, _)) => make(k)
              None => ()
            }
          },
        )
      })
    })
    |> ignore
    // (clear of the panel's top right corner; its last action there by its own height (pane_bar's); where the mark
    // saying what it is for may end it (the title cut short before it), by the mark's own height, concentric with the
    // corner as an action's there is: tape_bar_end's `side`)
    bar_room_node(bar, fn() {
      if actions() is Some((_, side, _)) {
        tape_bar_end_room(corners(), side=@sf.pane_bar_actions_side(side))
      } else if now().about != "" {
        tape_bar_end_room(corners(), side=@ui.Space::px(S5))
      } else {
        tape_bar_end_room(corners())
      }
    })
  })
}

///|
/// A room `w` wide at an end of a bar's row `row`, as wide as it is whatever is beside it (an old view's w=Fixed, never
/// given way): where the bar keeps clear of what is at its end (tape_bar_start_room, tape_bar_end_room).
fn bar_room_node(row : @view.View, w : () -> Double) -> Unit {
  row.box(fn(r) { r.width(By(fn() { Some(w()) })).shrink(Is(0.0)) |> ignore }) |> ignore
}

///|
/// How far a bar of the page's panel on the tape keeps in from the panel's start, its corners `corners` as they are
/// told it: with `back` before its title, that round button in the panel's top left corner concentric with it; without,
/// its title on the panel's words' line (as a chat's on the tape: wide.bar_pl). A page's bar's (pane_bar_node) and a
/// chat's (chat_bar_wide_node) alike.
fn tape_bar_start_room(corners : FixedArray[@ui.CornerOf], back : Bool) -> Double {
  if back {
    @sf.tape_bar_start_of(corners, @ui.tree_corner_roots_now(), bar_in)
  } else {
    @sf.panel_words - chat_bar_title_in
  }
}

///|
/// How far a bar of the page's panel on the tape keeps in from the panel's end, its corners `corners` as they are told
/// it: what ends it (`side` high: a round button's where none is said) concentric with the panel's top right corner, or
/// clear of it (@sf.tape_bar_end_of). A page's bar's (pane_bar_node) and a chat's (chat_bar_wide_node) alike.
fn tape_bar_end_room(corners : FixedArray[@ui.CornerOf], side? : Double = @sf.bar_key_side) -> Double {
  @sf.tape_bar_end_of(corners, @ui.tree_corner_roots_now(), bar_in, side~)
}

///|
/// Words of `style` in `parent`, `words` as they are said, as a page `width` wide sets them (its look's sizes), cut
/// short on their line where `style` says so.
fn bar_words(parent : @view.View, words : () -> String, style : @ui.TextStyle, width : () -> Double) -> Unit {
  parent.box(fn(w) {
    w
    .words(By(words))
    .words_look(By(fn() {
      let look = Ref(@ui.style_words(style))
      @sf.with_look(@sf.look_for(width()), fn() { look.val = @ui.style_words(style) })
      look.val
    }))
    .ink(By(fn() { @ui.style_ink(style) }))
    |> ignore
    if @ui.style_cut(style) {
      // (cut short where their line has not the room across: given way along a row, never squeezed down, View::cuts)
      w.cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}

///|
/// `v` taking the room its row leaves, shared alike whatever it holds and giving way down to nothing where the row has
/// too little (an old view's w=Grow in a row: chat_bar_inner's, chat_bar_title_row's), what is beside it kept whole.
fn bar_fills(v : @view.View) -> @view.View {
  v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0)))
}

///|
/// How high a page's bar on the tape is (a chat's there: chat_bar_box_tape's), as it is now: the tree's bar's, and the
/// room its page leaves for it under it (tape_bar_collected), one and the same.
fn pane_bar_h() -> Double {
  @sf.wide_bar_h + @sf.tape_bar_over()
}
