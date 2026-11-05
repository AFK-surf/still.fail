// Picking a passage of a message drawn by nodes (sfbase's pick.mbt as an old view's message has it): its words are
// picked as the window's tree's words are (mbui/ui's tree_select: a mouse dragging over them, a finger held still on
// them, the handles at a finger's passage's ends, a tap elsewhere letting it go); what is the chat's is here, over the
// list: which message it is of (its row's, as the list makes it: pick_row_node), and over the passage the finger's bar
// (引用, 复制, 全选, its turn shared, its link copied) or the mouse's pill (引用), in place of the system's text menu.

///|
/// A message's row as what is picked of it is told (pick.mbt's ChatPick): who said it and as what, the message quoted
/// (its source's where its row is not its own yet), its words whole, what shares its turn and the link to it.
pub(all) struct PickRow {
  /// what it is picked as (its row's: the same as the outbox's entry becomes the message), and the message quoted
  /// ("" while it is not at the station yet)
  key : String
  ts : String
  author : String
  role : String
  words : String
  share : (() -> Unit)?
  link : String
}

///|
/// The messages' words made now that are picked here, by their node.
// kept across runs: put back as each row is let go
let pick_rows : Map[@view.NodeId, () -> PickRow?] = {}

///|
/// The words in `words` (a message's) picked as the tree's are, its row in its list (`slot`) told what message it is
/// (`row`, as it is now): over what is picked of them, the chat's bar or pill, never the system's text menu.
fn pick_row_node(slot : @view.View, words : @view.View, row : () -> PickRow?) -> Unit {
  // (its passage on the accent at 26%, its handles lined in the accent, on every platform: MessagePick.kt)
  @ui.words_picked(words, color=@sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha), lined=true)
  let at = words.id()
  pick_tree.val = Some(words.tree)
  pick_rows[at] = row
  pick_rows_said()
  // (the same message actions as pickable's right click, including the viewer's own bubble; files and links
  // inside it keep their own innermost menu)
  words.on_menu(fn(mn) {
    if !@sf.more_held() {
      match row() {
        Some(r) => match r.share {
          Some(go) => @sfbase.offer_message_menu(mn.wx, mn.wy, go, r.link, r.words, "m:" + r.ts)
          None => ()
        }
        None => ()
      }
    }
  }) |> ignore
  // (let go with what made it, not once another made since in the same row has said it)
  words.owns(fn() {
    match pick_rows.get(at) {
      Some(f) if physical_equal(f, row) => {
        pick_rows.remove(at)
        pick_rows_said()
      }
      _ => ()
    }
  })
  |> ignore
  ignore(slot)
  @ui.tree_menu_own.val = fn(rows) { picked_in_one(rows) is Some(_) }
}

///|
/// The one message what is picked in `rows` is all of (its paragraphs each a row of their own), if it is.
fn picked_in_one(rows : Array[@view.NodeId]) -> PickRow? {
  let mut one : PickRow? = None
  for id in rows {
    match (pick_row_of(id), one) {
      (None, _) => return None
      (Some(r), None) => one = Some(r)
      (Some(r), Some(o)) => if r.key != o.key { return None }
    }
  }
  one
}

///|
/// How many times the messages' words made or let go changed (pick_rows): what reads which message is picked follows.
// kept across runs: counted on
let pick_rows_told : @signals.Signal[Int] = @signals.signal(0)

///|
fn pick_rows_said() -> Unit {
  pick_rows_told.set(@signals.untracked(fn() { pick_rows_told.get() }) + 1)
}

///|
/// The tree the messages' words picked are in (pick_row_node's), once one is.
// kept across runs: the window's tree, said again as each is made
let pick_tree : Ref[@view.Tree?] = Ref(None)

///|
/// The message whose words hold node `id` (a row of a list its words were picked in: what holds it, up to the words a
/// message's row said: pick_row_node), as it is now.
fn pick_row_of(id : @view.NodeId) -> PickRow? {
  pick_rows_told.get() |> ignore
  guard pick_tree.val is Some(tree) else { return None }
  // (a windowed row's name survives its slot: containment is by the node that has that name now)
  guard tree.view_of(id) is Some(held) else { return None }
  let current = held.id()
  let mut at = Some(held)
  while at is Some(v) {
    match pick_rows.get(v.id()) {
      Some(row) => return row()
      None => at = v.parent()
    }
  }
  // (a row of the list itself, its words in it with no row of their own (a person's words, not paragraphs): the words
  // said in it)
  for e in pick_rows {
    let mut up = tree.view_of(e.0)
    while up is Some(v) {
      if v.id() == current {
        return (e.1)()
      }
      up = v.parent()
    }
  }
  None
}

///|
/// What is picked now, of one message's row: what the tree says of it and that message.
fn picked_row() -> (@ui.TreePicked, PickRow)? {
  match @ui.tree_picked() {
    Some(t) => picked_in_one(t.rows).map(fn(r) { (t, r) })
    _ => None
  }
}

///|
/// Over a chat's list in `layer` (all of its page: what is picked is said in the window's terms): the bar over what a
/// finger picked of a message, the pill over what a mouse did (pick_layer's, pick_pop's); quoted into draft `draft`.
/// `top` the bar's room over the list, `foot` the composer's under it.
pub fn pick_bar_node(layer : @view.View, src : Source, draft : String, top : () -> Double, foot : () -> Double) -> Unit {
  let at : Ref[(Double, Double, Double, Double)?] = Ref(None)
  layer.reacts(fn() { layer.laid_window_told() }, fn(r) { at.val = r })
  let quote = fn(t : @ui.TreePicked, r : PickRow) {
    let text = t.words.trim(chars=" \n\t").to_string()
    if text != "" {
      @sfbase.writing_quote(src, @sfbase.writing(src, draft), {
        "author": Json::string(r.author),
        "text": Json::string(text),
        "ts": Json::string(r.ts),
        "role": Json::string(r.role),
      })
    }
    @ui.picked_none()
  }
  // (what the chat says is picked, as it changes: whose, the message, its share and link: sfbase's pk)
  layer.reacts(fn() { picked_row().map(fn(p) { p.1.key }) }, fn(_) {
    match @signals.untracked(picked_row) {
      Some((_, r)) => {
        @sfbase.picked_by_node.val = true
        @sfbase.pk.ts = r.key
        @sfbase.pk.source_ts = if r.key == r.ts { None } else { Some(r.ts) }
        @sfbase.pk.author = r.author
        @sfbase.pk.role = r.role
        @sfbase.pk.share = r.share
        @sfbase.pk.link = r.link
      }
      None =>
        if @sfbase.picked_by_node.val {
          @sfbase.picked_by_node.val = false
          @sfbase.pk.ts = ""
        }
    }
  })
  // (a passage picked anew told once, its identity its own; let go, told once: sfbase's `picked`; what is picked moved
  // on in the same message nothing more)
  layer.reacts(fn() { picked_row().map(fn(p) { p.1.key }) }, fn(key) {
    match (key, @signals.untracked(picked_row)) {
      (Some(_), Some((t, r))) => {
        let a = t.spans.get(0).map(fn(s) { s.0 }).unwrap_or(0)
        let n = t.words.length()
        let b = a + (if n > 0 { n } else { 1 })
        // (where it runs, as the chat's pick says it: pk.sel's, the old view's)
        @sfbase.pk.sel.a = a
        @sfbase.pk.sel.b = b
        @sfbase.picked_by_node_told(Some((r.key, a, b)))
      }
      _ =>
        if @signals.untracked(fn() { @sfbase.picked.get() }) != @sfbase.picked_none {
          @sfbase.picked_by_node_told(None)
        }
    }
  })
  layer.pick(fn() { picked_row().map(fn(p) { p.0.finger }) }, fn(over, which) {
    guard which is Some(finger) else { return }
    // (back lets go of what is picked before it goes back a page: MessagePick.kt's BackHandler, pick_back's)
    over.over(Is(true)).lines_up(Is(Some(Start))).takes_back(fn() { @sfbase.pick_clear() }) |> ignore
    // (where it stands: worked out as what is picked changes, from where that is drawn then)
    let place = fn() -> (Double, Double) {
      picked_row() |> ignore
      let (lx, ly, lw, lh) = at.val.unwrap_or((0.0, 0.0, 0.0, 0.0))
      match @signals.untracked(@ui.picked_box) {
        Some((x, y, w, h)) =>
          if finger {
            // (over the passage; under it where the bar over the list is too near; on the screen where it runs past)
            let least = ly + top() + 8.0
            let over = y - 52.0
            let yy = if over < least { y + h + 28.0 } else { over }
            let yy = dmax(least, dmin(yy, dmax(ly + lh - foot() - 48.0, least)))
            (x + w / 2.0 - lx, yy - ly)
          } else {
            // (8 over where the pointer let it go, its middle there: pick_pop's)
            match @signals.untracked(@ui.picked_end) {
              Some((ex, ey, _)) => (ex - lx, ey - 8.0 - pick_pop_h - ly)
              None => (x + w - lx, y - 8.0 - pick_pop_h - ly)
            }
          }
        None => (0.0, 0.0)
      }
    }
    over.box(fn(b) {
      // (a tap on it keeps what is picked: what it does is done with it)
      @ui.keeps_picked(b) |> ignore
      b.offset(By(fn() {
        let (x, y) = place()
        let half = b.laid_size_told().map(fn(z) { z.0 / 2.0 }).unwrap_or(0.0)
        let w = at.val.map(fn(r) { r.2 }).unwrap_or(0.0)
        // (kept on the screen, 8 in from its sides)
        (dmax(8.0, dmin(x - half, w - half * 2.0 - 8.0)), y)
      }))
      |> ignore
      if finger {
        pick_finger_bar(b, quote)
      } else {
        pick_mouse_pill(b, quote)
      }
    })
    |> ignore
  })
}

///|
/// The finger's bar (pick_layer's): 引用, 复制, 全选 where not all of it is picked; after a line, its turn shared and
/// its link copied where the message offers them; coming as a small panel does (@kit.pop_in).
fn pick_finger_bar(b : @view.View, quote : (@ui.TreePicked, PickRow) -> Unit) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  b
  .row(Is(true))
  .height(Is(Some(40.0)))
  .padding(Is((4.0, 0.0, 4.0, 0.0)))
  .radius(Is(1.0e6))
  .lines_up(Is(Some(Middle)))
  .ground(By(fn() { theme().color(Raised) }))
  .edge(By(fn() { (1.0, theme().color(Line)) }))
  .shadow(By(fn() { (@sf.pick_raised.sigma, @sf.pick_raised.dy, @sf.pick_raised.color) }))
  |> ignore
  let button = fn(label : () -> String, icon : String, press : () -> Unit) {
    b.box(fn(k) {
      k
      .row(Is(true))
      .height(Is(Some(32.0)))
      .padding(Is((12.0, 0.0, 12.0, 0.0)))
      .gap(Is(5.0))
      .radius(Is(16.0))
      .lines_up(Is(Some(Middle)))
      .says(By(fn() { Some(@view.said(Button, label=label())) }))
      |> ignore
      @sf.presses_node(k, press)
      if icon != "" {
        @sf.icon_node(k, icon, pick_icon, By(fn() { @sf.theme().p.text })) |> ignore
      }
      @sf.words_node(k, label, fn() { pick_button_words }) |> ignore
    })
    |> ignore
  }
  let now = fn(f : (@ui.TreePicked, PickRow) -> Unit) {
    fn() {
      match @signals.untracked(picked_row) {
        Some((t, r)) => f(t, r)
        None => ()
      }
    }
  }
  button(fn() { @sf.t("android-chat.pick.quote") }, "quote", now(quote))
  button(fn() { @sf.t("common.copy") }, "copy", now(fn(t, _) {
    @ui.current().copy_text(t.words)
    toast_later(@sf.t("android-chat.annotate.copied"))
    @ui.picked_none()
  }))
  b.show(fn() { picked_row().map(fn(p) { p.0.words.trim(chars=" \n\t") != p.1.words.trim(chars=" \n\t") }).unwrap_or(false) }, fn(all) {
    all.row(Is(true)) |> ignore
    // (all of the message's words: those its words hold)
    button_in(all, fn() { @sf.t("android-chat.annotate.selectAll") }, fn() {
      match @signals.untracked(picked_row) {
        Some((_, r)) => @ui.picked_all(within=fn(id) { pick_row_of(id).map(fn(o) { o.key == r.key }).unwrap_or(false) })
        None => ()
      }
    })
  })
  // (a line 16 high 4 off what does with the passage, before what does with the message)
  b.show(fn() { picked_row().map(fn(p) { p.1.share is Some(_) || p.1.link != "" }).unwrap_or(false) }, fn(room) {
    room.padding(Is((4.0, 0.0, 4.0, 0.0))) |> ignore
    room.box(fn(rule) {
      rule.width(Is(Some(1.0))).height(Is(Some(16.0))).ground(By(fn() { theme().color(Line) })) |> ignore
    })
    |> ignore
  })
  b.show(fn() { picked_row().map(fn(p) { p.1.share is Some(_) }).unwrap_or(false) }, fn(s) {
    s.row(Is(true)) |> ignore
    mark_in(s, fn() { @sf.t("web-main.chat.shareTurn") }, "share", now(fn(_, r) {
      @ui.picked_none()
      match r.share {
        Some(go) => go()
        None => ()
      }
    }))
  })
  b.show(fn() { picked_row().map(fn(p) { p.1.link != "" }).unwrap_or(false) }, fn(l) {
    l.row(Is(true)) |> ignore
    mark_in(l, fn() { @sf.t("common.link.copy") }, "link", now(fn(_, r) {
      @ui.current().copy_text(r.link)
      toast_later(@sf.t("common.link.copied"))
      @ui.picked_none()
    }))
  })
}

///|
/// A button of words in the bar (pick_finger_bar's), in `parent`.
fn button_in(parent : @view.View, label : () -> String, press : () -> Unit) -> Unit {
  parent.box(fn(k) {
    k
    .row(Is(true))
    .height(Is(Some(32.0)))
    .padding(Is((12.0, 0.0, 12.0, 0.0)))
    .radius(Is(16.0))
    .lines_up(Is(Some(Middle)))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(k, press)
    @sf.words_node(k, label, fn() { pick_button_words }) |> ignore
  })
  |> ignore
}

///|
/// A mark alone in the bar (pick_finger_bar's), 32 round, in `parent`.
fn mark_in(parent : @view.View, label : () -> String, icon : String, press : () -> Unit) -> Unit {
  parent.box(fn(k) {
    k
    .width(Is(Some(32.0)))
    .height(Is(Some(32.0)))
    .radius(Is(16.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(k, press)
    @sf.icon_node(k, icon, pick_icon, By(fn() { @sf.theme().p.text })) |> ignore
  })
  |> ignore
}

///|
/// The mouse's pill (pick_pop's): 引用 with its mark on the primary ground, a step towards the page under the pointer.
fn pick_mouse_pill(b : @view.View, quote : (@ui.TreePicked, PickRow) -> Unit) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  b
  .row(Is(true))
  .height(Is(Some(pick_pop_h)))
  .padding(Is((10.0, 0.0, 10.0, 0.0)))
  .gap(Is(4.0))
  .radius(Is(1.0e6))
  .lines_up(Is(Some(Middle)))
  .ground(By(fn() {
    let g = theme().color(Primary)
    if b.pointed() { @sf.mix(g, 0.15, theme().color(Bg)) } else { g }
  }))
  .shadow(By(fn() { (6.0, 4.0, @sf.theme().p.shadow) }))
  .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.quote"))) }))
  |> ignore
  @sf.presses_node(b, fn() {
    match @signals.untracked(picked_row) {
      Some((t, r)) => quote(t, r)
      None => ()
    }
  })
  @sf.icon_node(b, "quote", 12.0, By(fn() { @sf.theme().p.on_primary })) |> ignore
  @sf.words_node(b, fn() { @sf.t("web-main.chat.quote") }, fn() { pick_pop_words }) |> ignore
}

///|
let pick_icon : Double = 15.0

///|
let pick_pop_h : Double = 26.0

///|
// kept across runs: a value (no field of it changes)
let pick_button_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pick_pop_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Medium, color=OnPrimary, wrap=false)


///|
/// What holds the messages' words let go of, as their rows are once scrolled far off: what of them was picked goes.
pub fn pick_rows_let_go() -> Unit {
  pick_rows.clear()
  pick_rows_said()
}
