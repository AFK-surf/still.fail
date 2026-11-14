// ⌘F's bar made once as nodes (find_bar_node.mbt) drawn as the old view's find_bar draws it, at the end of a bar's row
// as wide as a chat's bar is, with what is before it keeping its own width: what it did not look in, its field, its
// count and its buttons, each state of what the core said; its field giving way down to its least where the row has
// little room.

///|
/// The chat the bar is of (the fixture's), its thread.
let find_chat_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
let find_thread : Double = 1.0

///|
/// The row it is drawn in: a chat's bar's (45 high, its things 16 apart), `before` wide kept before it.
fn find_row(w : Double) -> @ui.Style {
  @ui.style(row=true, w=Fixed(w), h=Fixed(45.0), gap=S4, align=ACenter)
}

///|
/// The list it goes along: none.
fn find_list_none() -> FindList {
  { showing: fn() { (-1.0, -1.0) }, go: fn(_, _) {  }, forget: fn() {  } }
}

///|
/// What the find keeps put as `state` says, its field holding `typed`: as was asked of the core already (nothing asked
/// again).
fn find_state(state : String, typed : String) -> Unit {
  find_close()
  finding.chat.set(chat_key(find_chat_ref))
  finding.field.set(typed)
  finding.asked.set(typed)
  let found = fn(whole : Bool, n : Int) -> Found {
    { words: [typed], hits: Array::makei(n, fn(i) { (i.to_double() + 1.0, 1) }), held: 10, of: 40, whole }
  }
  match state {
    "found" => {
      finding.found.set(Some(found(true, 3)))
      finding.position.set(2)
      finding.total.set(3)
    }
    "none" => {
      finding.found.set(Some(found(true, 0)))
      finding.position.set(0)
      finding.total.set(0)
    }
    "partial" => {
      finding.found.set(Some(found(false, 3)))
      finding.position.set(1)
      finding.total.set(3)
    }
    "bringing" => {
      finding.found.set(Some(found(false, 0)))
      finding.bringing.set(true)
    }
    _ => ()
  }
}

///|
/// The old view's bar in a row `w` wide, `before` kept before it, as `state` says.
fn find_old(w : Double, before : Double, state : String, typed : String) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("chat")
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=find_row(w), fn() {
          c.box(style=@ui.style(w=Fixed(before), min_w=Fixed(before)), fn() {  }) |> ignore
          find_bar(c, src, find_chat_ref, find_thread, find_list_none())
        })
        |> ignore
      })
    },
    w=w + find_past,
    h=120.0,
    platform=0,
  )
  find_state(state, typed)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The nodes' bar in the same row.
fn find_new(w : Double, before : Double, state : String, typed : String) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("chat")
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      root.box(fn(row) {
        @sf.style_node(row, fn() { find_row(w) })
        row.box(fn(b) { b.width(Is(Some(before))).min_width(Is(Some(before))) |> ignore }) |> ignore
        find_bar_node(row, src, find_chat_ref, fn() { Some(find_thread) }, find_list_none(), tips) |> ignore
      })
      |> ignore
    },
    w=w + find_past,
    h=120.0,
    platform=0,
  )
  find_state(state, typed)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What `t` draws: its words (place, size, how seen) and the rectangles it draws, one a line.
fn find_drawn(t : @ui.Tester) -> String {
  t.words().map(fn(w) { "\{w.0}@\{w.1},\{w.2} \{w.3}x\{w.4} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(r) { "\{r.0},\{r.1} \{r.2}x\{r.3} \{r.4}" }).join("\n")
}

///|
/// How much wider the window is than the row (what is at the bar's end clear of the window's edge, as in a chat's bar).
let find_past : Double = 40.0

///|
test "⌘F's bar made once as nodes is drawn as the old view's: what it did not look in, its field, its count and buttons, each state of what the core said; its field giving way first where the row has little room" {
  for c in [
    ("typed, nothing said yet", 200.0, "typed", "截图"),
    ("nothing typed", 200.0, "typed", ""),
    ("found: which of how many", 200.0, "found", "截图"),
    ("none found", 200.0, "none", "截图"),
    ("found in part of the chat", 200.0, "partial", "截图"),
    ("the rest being read", 200.0, "bringing", "截图"),
    ("squeezed: its field narrower", 520.0, "found", "截图"),
    ("squeezed: what it did not look in gone, its field near its least", 560.0, "partial", "截图"),
  ] {
    let (name, before, state, typed) = c
    let old = find_old(760.0, before, state, typed)
    let was = find_drawn(old)
    let was_said = old.all(Button).map(fn(b) { (b.label, b.rect) })
    let t = find_new(760.0, before, state, typed)
    assert_eq(find_drawn(t), was, msg=name)
    assert_eq(t.all(Button).map(fn(b) { (b.label, b.rect) }), was_said, msg=name)
    // (squeezed near its field's least: the old bar's note cut to nothing in its box (find_note_box, clip), and what is
    // typed left 29 across by its count and buttons, drawn so by both; the old view held words to no rule, the nodes'
    // audit says them: those two, and only there; reported, 2026-11-11)
    let note = @sf.t("web-main.find.partial", args=[("held", "10"), ("of", "40")])
    let all = t.audit()
    let cut = fn(f : String) {
      (f.contains("「\{note}」") && f.contains("its words cut to 0 characters")) ||
      f.contains("its placeholder cut to 1 characters")
    }
    let known = all.filter(cut)
    let faults = all.filter(fn(f) { !cut(f) })
    assert_eq(known.length(), if before >= 560.0 { 2 } else { 0 }, msg="\{name}: \{Repr(known)}")
    assert_eq(faults, [], msg="\{name}: \{Repr(faults)}")
  }
  find_close()
}
