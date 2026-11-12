// A web link's card over what draws it (peeks.mbt's web_peek) as nodes of the window's tree, made once: shown as a mouse
// has rested on its row hover_open_ms carrying no press (none down anywhere, from when it was let go), kept while the pointer is on the row or on the card, gone
// hover_close_ms after it has left both, at once by Escape or a press elsewhere; a finger shows none (hover.mbt's
// hover, @kit.hover_card's, each at its cause's moment: the rest's end and the leaving's a moment of the timeline).
// Beside its row on its `side`, lined up at its start, hover_offset off it (View::beside), over all of the window
// (View::over_all: over a sheet's modal layer too), coming in and going as hover_in and hover_out have it; its look
// hover_card's (hover_tile's, a page's tile) round a small panel, what it holds hover_inner in. What it holds as
// link_card's: a pull request's or an issue's card, a page's tile, the bones of the one it will be while it is read,
// its address to copy at its foot's end. Read as peek_read reads it: as the pointer comes onto the row and while the
// card is there, let go of once neither, so the next time it shows it is read again; the pictures its value names asked
// as it is read (@sfbase.link_pictures_ask), the card showing as it does while it is read till they are here.

///|
/// A web link's card (web_peek's) over `row` (what draws it: the node the pointer rests on, what is pressed) while a
/// mouse rests on it, as the link's station `station` reads it (`href` the link, `words` what the row says of it, as
/// they are now): opened at its `side` (under it, else beside a list it would cover: a chat's things'); `peek` the kind
/// the core says it is (pull, issue) while it is read, its bones that one's then. Nothing for what is no web link, nor
/// from a station not known.
pub fn web_peek_node(
  row : @view.View,
  src : Source,
  station : String,
  href : () -> String,
  words : () -> String,
  side? : @view.Side = Bottom,
  peek? : () -> String = fn() { "" },
) -> Unit {
  if station == "" {
    return
  }
  peek_cards.val = peek_cards.val + 1
  let scope = "link-peek-node/" + peek_cards.val.to_string()
  let web = fn() {
    let h = href()
    h.has_prefix("https://") || h.has_prefix("http://")
  }
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  // (the pointer on the card, as the card says; whether the card is made (shown, or going); shut by Escape till the
  // pointer has left the row and the card; the moment it opens or shuts at, as it is due)
  let on_card = @signals.signal(false, same=fn(a, b) { a == b })
  let card_made = Ref(false)
  let shut = Ref(false)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  let stop_due = fn() {
    (due.val)()
    due.val = fn() {  }
  }
  let holder : Ref[@view.View?] = Ref(None)
  // (what is read as the pointer comes onto the row, while it is: the pictures it names asked as it comes, so that they
  // are mostly here as the card opens)
  let warm : @signals.Signal[@signals.Computed[@sfbase.TopicState]?] = @signals.signal(None, same=fn(a, b) {
    match (a, b) {
      (None, None) => true
      (Some(x), Some(y)) => physical_equal(x, y)
      _ => false
    }
  })
  row.reacts(
    fn() {
      match warm.get() {
        Some(read) => read.get().value
        None => None
      }
    },
    fn(v) { @sfbase.link_pictures_ask(src, station, @signals.untracked(href), v) },
  )
  let set_open = fn(on : Bool) {
    if on == open.untracked() {
      return
    }
    if on && holder.val is None {
      holder.val = Some(peek_holder(row, src, scope, station, href, words, side, peek, open, on_card, card_made, fn() {
        shut.val = true
        stop_due()
      }))
    }
    open.set(on)
  }
  // (what decides it, as of each cause: a mouse over the row or what it holds, a press held anywhere in the window (a
  // pointer carrying one rests on nothing: @kit.hover_card's, counted from when it was let go), the pointer on the
  // card, the row taking input at all, a web link to show)
  let state = fn() { (@sf.hovered_in_node(row), row.window_held(), on_card.get(), row.takes_input(), web()) }
  row.reacts(state, fn(s) {
    let (over, pressed, card, takes, web) = s
    let at = row.cause_at()
    stop_due()
    if !over && !card {
      shut.val = false
    }
    // (read as the pointer comes onto it, so the card mostly opens with it there: Peeks.tsx Hover's `warm`)
    if over && web {
      warm.set(Some(@sfbase.hold(src, scope, "linkPreview", link_params(station, href()))))
    }
    let shows = open.untracked()
    if !web || !takes || shut.val {
      set_open(false)
    } else if shows {
      // (left both: gone once it has been off them a while)
      if !over && !card {
        due.val = row.at_moment(at + hover_close_ms, fn() { set_open(false) })
      }
    } else if over && !pressed {
      // (rested on a while from now, carrying no press: shown then, as it is then)
      due.val = row.at_moment(at + hover_open_ms, fn() {
        let (over, pressed, _, takes, web) = @signals.untracked(state)
        if over && !pressed && takes && web && !shut.val {
          set_open(true)
        }
      })
    }
    // (neither pointed at nor drawn: what it read let go of)
    if !over && !card_made.val {
      warm.set(None)
      @sfbase.let_go(src, scope)
    }
  })
  // (a press elsewhere, off the row and the card: gone at once, as a hover card's overlay is by a press outside)
  row.reacts(fn() { row.window_downs() }, fn(_) {
    if @signals.untracked(fn() { open.get() && !on_card.get() && !row.pointed_in() }) {
      stop_due()
      set_open(false)
    }
  })
  // (its row let go: nothing of it left pending, nothing read for it)
  row.owns(fn() {
    stop_due()
    warm.set(None)
    @sfbase.let_go(src, scope)
  })
  |> ignore
}

///|
/// How many link cards have been made (web_peek_node), each one's reading named by its count (link-peek-node/<n>).
// kept across runs: it only names each card's reading apart from the others', never says what it shows
let peek_cards : Ref[Int] = Ref(0)

///|
/// Where a card over `row` is drawn (web_peek_node's), made as it first opens: a node over all of the window, in what
/// holds all of the window's tree (peek_layer), let go with `row`; the card in it while `open` (going over
/// hover_out_ms once not), telling `on_card` whether the pointer is on it and `card_made` whether it is made; Escape
/// while it shows shuts it (`escaped`: shut till the pointer has left it and the row). The node.
fn peek_holder(
  row : @view.View,
  src : Source,
  scope : String,
  station : String,
  href : () -> String,
  words : () -> String,
  side : @view.Side,
  peek : () -> String,
  open : @signals.Signal[Bool],
  on_card : @signals.Signal[Bool],
  card_made : Ref[Bool],
  escaped : () -> Unit,
) -> @view.View {
  let layer = peek_layer(row)
  let h = layer.box(fn(h) { h.over(Is(true)).over_all(Is(true)) |> ignore }).lives_with(row)
  h.on_key(fn(k) {
    if k.code == @ui.key_escape && open.untracked() {
      escaped()
      open.set(false)
      true
    } else {
      false
    }
  })
  |> ignore
  h.show(fn() { open.get() }, leave=hover_out_ms, fn(card) {
    card_made.val = true
    let read = @sfbase.hold(src, scope, "linkPreview", link_params(station, @signals.untracked(href)))
    // (how far in it is, from the moment it opened; out from the moment it closed: hover_in's, hover_out's)
    let way = @sf.EdgeWay::new(0.0)
    card.reacts(fn() { card.leaving() }, fn(going) {
      if going {
        way.go_by(card, 0.0, hover_out.spec)
      } else {
        way.go_by(card, 1.0, hover_in.spec)
      }
    })
    let look = fn() {
      let p = way.shown(card)
      if card.leaving() {
        hover_out.at(p, p)
      } else {
        hover_in.at(p, p)
      }
    }
    card
    .beside(row.id(), side~, along=Start, offset=hover_offset)
    .alpha(By(fn() { look().alpha }))
    .scale(By(fn() { look().sx }), about=FromBeside)
    .says(Is(Some(@view.said(Group))))
    // (going, nothing of it read out)
    .hides(By(fn() { card.leaving() }))
    // (a press on it its own, not the row's under it nor one elsewhere)
    |> @sf.ground_node
    |> ignore
    card.reacts(fn() { card.pointed_in() }, fn(on) { on_card.set(on) })
    card.owns(fn() {
      card_made.val = false
      on_card.set(false)
      // (gone, the pointer not on the row: what it read let go of)
      if !@signals.untracked(fn() { row.pointed_in() }) {
        @sfbase.let_go(src, scope)
      }
    })
    |> ignore
    // (its width (hover_card's; a page's tile as wide as it holds, hover_tile's), the small panel in it, what it holds
    // as small_panel's room holds it (held_reach, held_in), hover_inner in, its words as far in as its look says)
    // (a tile or a card by what the core says it is as it opens: what its width is bound by, said once)
    let tile = @signals.untracked(fn() { peek() == "" })
    card.box(fn(w) {
      @sf.style_node(w, fn() { if tile { hover_tile } else { hover_card } })
      // (kept within the room the window has (Ctx::place_most's: as tall as the window less peek_room_in at each end;
      // as wide as the window at most, as an old overlay's is), what it holds scrolling in it where it is taller with
      // the panel's own room over and under it (@kit.in_room's: as tall as the room then, by what it holds as it is
      // laid out whole))
      let most = fn() {
        let m = w.window().1 - 2.0 * peek_room_in
        if m > 0.0 {
          m
        } else {
          0.0
        }
      }
      w
      .max_width(By(fn() {
        let across = w.window().0
        match (tile, @sf.hover_tile_most) {
          (true, Fixed(m)) if m < across => Some(m)
          _ => Some(across)
        }
      }))
      |> ignore
      // (as tall as what it holds comes to whole in the room it is given, measured as it is laid out)
      w.by_room(fn(g, given) {
        g.box(fn(p) {
          @sf.small_panel_node(p).shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          let whole_at : Ref[@view.View?] = Ref(None)
          p.box(fn(reach) {
            @sf.style_node(reach, fn() { @sf.held_reach() })
            reach
            .shrink(Is(1.0))
            .min_height(Is(Some(0.0)))
            .scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
              held.box(fn(whole) {
                @sf.style_node(whole, fn() { @sf.held_in() })
                whole_at.val = Some(whole)
                whole.box(fn(inner) {
                  @sf.style_node(inner, fn() { hover_inner })
                  inner.alpha(By(fn() { look().words })) |> ignore
                  link_card_node(inner, src, station, read, href, words, peek, fn(at) { link_copy_node(at, href) })
                })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
          p
          .height(By(fn() {
            match whole_at.val {
              Some(whole) if given.tall(whole) + 2.0 * @sf.panel_pad > most() + peek_room_slop => Some(most())
              _ => None
            }
          }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  h
}

///|
/// How far inside the window a card is kept at each end (Ctx::place_most's padding, View::beside's), and how much
/// taller than its room what it holds is before it scrolls (@kit.in_room's half a point).
let peek_room_in : Double = 8.0

///|
let peek_room_slop : Double = 0.5

///|
/// What holds all of the window's tree `v` is in (its root): where a card goes over all of the window.
fn peek_layer(v : @view.View) -> @view.View {
  match v.parent() {
    Some(p) => peek_layer(p)
    None => v
  }
}

///|
/// What a link's card shows (link_card's): a pull request's card or an issue's; the bones of one (a pull request's
/// where `true`) while it is read and the core says it is one; else a page's tile.
#derive(Eq)
priv enum PeekShows {
  Change(Bool)
  Sample(Bool)
  Page
}

///|
/// The card (link_card's) in `parent`, of what `read` reads (`href`, `words`, `peek` as web_peek_node's) of station
/// `station`: what it shows made again as that changes kind, its words and facts as they are read, as it is while it is
/// read till the pictures they name are here (@sfbase.link_pictures_here_told); `copy` makes what copies it, at its foot's
/// end.
fn link_card_node(
  parent : @view.View,
  src : Source,
  station : String,
  read : @signals.Computed[@sfbase.TopicState],
  href : () -> String,
  words : () -> String,
  peek : () -> String,
  copy : (@view.View) -> Unit,
) -> Unit {
  // (the pictures its value names asked as it is read, as that changes: told to what reads them as each comes, none
  // asked as a binding runs)
  parent.reacts(fn() { (href(), read.get().value) }, fn(r) { @sfbase.link_pictures_ask(src, station, r.0, r.1) })
  let value = fn() -> Json? {
    match read.get().value {
      Some(Object(_)) as v if @sfbase.link_pictures_here_told(src, station, href(), v) => v
      _ => None
    }
  }
  // (a picture of it, as its image's key: "" none)
  let picture = fn(which : String) {
    @sfbase.picture_drawn(@sfbase.link_picture_told(src, station, href(), value(), which))
  }
  let shows = fn() {
    let v = value()
    match text(v, "kind") {
      "github_pull_request" => Change(true)
      "github_issue" => Change(false)
      _ => if v is None && read.get().error is None && peek() != "" { Sample(peek() == "pull") } else { Page }
    }
  }
  parent.pick(shows, fn(b, s) {
    @sf.style_node(b, fn() { peek_card_part })
    match s {
      Change(pr) => change_card_node(b, value, pr, copy, fn() { picture("avatar") })
      // (while it is read: a made-up one's, in its bones)
      Sample(pr) => @sf.waiting_node(b, fn(bones) { change_card_node(bones, peek_sample, pr, fn(_) {  }, fn() { "" }) })
      Page =>
        page_tile_node(
          b,
          href,
          words,
          fn() {
            let v = value()
            if text(v, "kind") == "page" {
              v
            } else {
              None
            }
          },
          copy,
          picture,
        )
    }
  })
}

///|
/// What a card holds as what it shows has it, laid out as hover_inner lays out what it holds: 8 apart.
// kept across runs: a value (no field of it changes)
let peek_card_part : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// The made-up pull request or issue a card's bones are made of while it is read (link_card's).
fn peek_sample() -> Json? {
  Some({
    "repository": Json::string(@sf.sample_words(8)),
    "number": 1,
    "title": Json::string(@sf.sample_words(18)),
    "time": { "updatedAt": { "ago": Json::string(@sf.sample_words(3)) } },
  })
}

///|
/// A page's tile (page_tile's) in `parent`: its icon in its thumb (GitHub's mark for a GitHub page, the globe for any
/// other), its title over where it goes; the page's picture over it where `page` has one; its foot, `copy` at its end.
/// `pictures`: a picture of it by which (`icon`, `image`), its image's key, "" none.
fn page_tile_node(
  parent : @view.View,
  href : () -> String,
  words : () -> String,
  page : () -> Json?,
  copy : (@view.View) -> Unit,
  pictures : (String) -> String,
) -> Unit {
  let picture = fn() { if page() is None { "" } else { pictures("image") } }
  let tile = fn(holder : @view.View) {
    holder.box(fn(t) {
      @sf.style_node(t, fn() { peek_tile })
      t.box(fn(th) {
        @sf.style_node(th, fn() { peek_thumb }, in_row=true)
        let thumb = fn() {
          let h = href()
          (if page() is None { "" } else { pictures("icon") }, h.has_prefix("https://github.com/") || h.contains(".github.com/"))
        }
        th.pick(thumb, fn(m, k) {
          match k {
            ("", true) => github_mark_node(m, peek_thumb_mark, fn() { @sf.theme().p.muted })
            ("", false) => @sf.icon_node(m, "web", peek_thumb_icon, By(fn() { @sf.theme().p.muted })) |> ignore
            (key, _) =>
              m
              .width(Is(Some(peek_thumb_mark)))
              .height(Is(Some(peek_thumb_mark)))
              .image(Is(Some((key, "", peek_image_most))))
              // (all of it in its square, as page_tile's FitContain: a site's icon not square kept as it is)
              .image_contains(Is(true))
              |> ignore
          }
        })
      })
      |> ignore
      t.box(fn(body) {
        @sf.style_node(body, fn() { peek_tile_body }, in_row=true)
        @sf.words_node(
          body,
          fn() {
            match text(page(), "title") {
              "" => if words() != "" { words() } else { href() }
              x => x
            }
          },
          fn() { peek_tile_title },
        )
        |> ignore
        // (as wide as its words, as the old view's (w=Cut): cut where it is longer, not stretched across)
        body.box(fn(u) {
          u.lines_up(Is(Some(@view.Along::Start))) |> ignore
          @sf.words_node(
            u,
            fn() {
              let site = text(page(), "site")
              if site != "" {
                site + " · " + destination(href())
              } else {
                destination(href())
              }
            },
            fn() { peek_tile_url },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  parent.pick(fn() { picture() != "" }, fn(b, pictured) {
    if pictured {
      // (its picture over it, as wide as the card, 16:9)
      @sf.style_node(b, fn() { peek_with_picture })
      b.box(fn(i) {
        i
        .height(Is(Some(peek_picture_h)))
        .radius(Is(peek_picture_r))
        .ground(By(fn() { @sf.theme().p.hover }))
        .image(By(fn() { Some((picture(), "", peek_image_most)) }))
        .image_covers(Is(true))
        |> ignore
      })
      |> ignore
    }
    tile(b)
  })
  // (its copy in its foot's end corner, as a file's card's is: file_foot)
  parent.box(fn(f) {
    @sf.style_node(f, fn() { peek_file_foot })
    f.box(fn(r) { @sf.style_node(r, fn() { peek_ref }, in_row=true) }) |> ignore
    copy(f)
  })
  |> ignore
}

///|
/// The most pixels a card's picture, a page's icon or a face is asked at (as a chat's things' tiles are).
let peek_image_most : Int = 8192

///|
/// A pull request's (`pr`) or an issue's card (change_card's) in `parent`, of `v` as it is read: its state's pill,
/// where it is and when it last changed; its title; who opened it (`avatar`: their picture's image's key, "" none) and
/// its facts, `copy` at their line's end.
fn change_card_node(
  parent : @view.View,
  v : () -> Json?,
  pr : Bool,
  copy : (@view.View) -> Unit,
  avatar : () -> String,
) -> Unit {
  let state = fn() { text(v(), "state") }
  parent.box(fn(rich) {
    @sf.style_node(rich, fn() { peek_rich })
    rich.box(fn(meta) {
      @sf.style_node(meta, fn() { peek_change_meta })
      state_pill_node(meta, state, fn() { if pr { pr_glyph(state()) } else { issue_glyph(state()) } }, fn() {
        @sf.t(if pr { pr_state_key(state()) } else { issue_state_key(state()) })
      })
      meta.box(fn(r) {
        @sf.style_node(r, fn() { peek_ref }, in_row=true)
        // (its words as wide as they are, cut where it has not the room, as an old view's in a column are)
        r.lines_up(Is(Some(@view.Along::Start))) |> ignore
        @sf.words_node(r, fn() { text(v(), "repository") + " #" + count(v(), "number").to_string() }, fn() {
          peek_meta_words
        })
        |> ignore
      })
      |> ignore
      let ago = fn() { text(field(field(v(), "time"), "updatedAt"), "ago") }
      meta.show(fn() { ago() != "" }, fn(a) { @sf.words_node(a, ago, fn() { peek_meta_words }) |> ignore })
    })
    |> ignore
    // (its title as wide as it is, cut to its lines where it has not the room, as an old view's words in a column are:
    // in a box across the card of its own, not stretched across it)
    rich.box(fn(b) {
      b.lines_up(Is(Some(@view.Along::Start))) |> ignore
      @sf.words_node(b, fn() { text(v(), "title") }, fn() { peek_title }) |> ignore
    })
    |> ignore
    // its facts, and at their line's end what is pressed to copy it (in the card's bottom end corner, as a file's is)
    rich.box(fn(line) {
      @sf.style_node(line, fn() { peek_facts_line })
      line.box(fn(facts) {
        @sf.style_node(facts, fn() { peek_facts }, in_row=true)
        // (what the copy at the line's end leaves of it, from none, its facts wrapping in that: not as wide as they all
        // are in a line)
        facts.wraps(Is(Some(@ui.Space::S2.px()))).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        facts.each(fn() { peek_facts_of(v(), pr, avatar).mapi(fn(i, f) { (i, f) }) }, fn(f) { f }, fn(cell, item) {
          peek_fact_node(cell, item.untracked().1)
        })
      })
      |> ignore
      line.box(fn(e) {
        @sf.style_node(e, fn() { peek_copy_end }, in_row=true)
        copy(e)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A fact a pull request's or an issue's card shows (change_card's): who opened it (their login, their picture's key),
/// a pull request's size (added, taken out), a fact in a pill, how its checks stand (as a state: failed, pending,
/// passed; in words).
#derive(Eq, Hash)
priv enum PeekFact {
  Person(String, String)
  Size(Int, Int)
  Chip(String)
  Checks(String, String)
}

///|
/// What facts `v` has (change_card's, in its order): who opened it; a pull request's (`pr`) size where it says one,
/// its files and how its checks stand; an issue's labels and how many comments it has. `avatar`: who opened it's
/// picture's image's key ("" none).
fn peek_facts_of(v : Json?, pr : Bool, avatar : () -> String) -> Array[PeekFact] {
  let out : Array[PeekFact] = []
  match field(v, "author") {
    Some(Object(_)) as a => out.push(Person(text(a, "login"), avatar()))
    _ => ()
  }
  if pr {
    if field(v, "additions") is Some(Number(_, ..)) || field(v, "deletions") is Some(Number(_, ..)) {
      out.push(Size(count(v, "additions"), count(v, "deletions")))
    }
    if field(v, "changedFiles") is Some(Number(_, ..)) {
      out.push(Chip(@sf.t("web-main.preview.files", args=[("count", count(v, "changedFiles").to_string())])))
    }
    match field(v, "checks") {
      Some(Object(_)) as ch =>
        out.push(
          if count(ch, "failed") > 0 {
            Checks("failed", @sf.t("web-main.preview.checks.failed", args=[("count", count(ch, "failed").to_string())]))
          } else if count(ch, "pending") > 0 {
            Checks("pending", @sf.t("web-main.preview.checks.pending", args=[("count", count(ch, "pending").to_string())]))
          } else {
            Checks("passed", @sf.t("web-main.preview.checks.passed", args=[("count", count(ch, "passed").to_string())]))
          },
        )
      _ => ()
    }
  } else {
    for l in items(v, "labels") {
      match l {
        String(s) => out.push(Chip(s))
        _ => ()
      }
    }
    if count(v, "comments") > 0 {
      out.push(Chip(@sf.t("web-main.preview.comments", args=[("count", count(v, "comments").to_string())])))
    }
  }
  out
}

///|
/// Fact `f` drawn in `cell` (its own node in the facts' line): who opened it, their picture (round, a capsule's
/// height; the line's ground where they have none) by their name; a size's two figures, green and red, in a pill; a
/// fact in a pill (fact_chip's); how its checks stand in a state's pill (state_pill's, no glyph).
fn peek_fact_node(cell : @view.View, f : PeekFact) -> Unit {
  match f {
    Person(login, avatar) => {
      @sf.style_node(cell, fn() { peek_person }, in_row=true)
      cell.box(fn(a) {
        if avatar == "" {
          @sf.style_node(a, fn() { peek_avatar })
        } else {
          a
          .width(Is(Some(peek_avatar_d)))
          .height(Is(Some(peek_avatar_d)))
          .radius(Is(peek_avatar_d / 2.0))
          .ground(By(fn() { @sf.theme().p.hover }))
          .image(Is(Some((avatar, "", peek_image_most))))
          .image_covers(Is(true))
          |> ignore
        }
      })
      |> ignore
      @sf.words_node(cell, fn() { login }, fn() { peek_person_words }) |> ignore
    }
    Size(add, del) => {
      @sf.style_node(cell, fn() { peek_chip }, in_row=true)
      @sf.words_node(cell, fn() { "+" + add.to_string() }, fn() { peek_add }) |> ignore
      @sf.words_node(cell, fn() { "\u{2212}" + del.to_string() }, fn() { peek_del }) |> ignore
    }
    Chip(words) => {
      @sf.style_node(cell, fn() { peek_chip }, in_row=true)
      @sf.words_node(cell, fn() { words }, fn() { peek_meta_words }) |> ignore
    }
    Checks(how, said) => state_pill_node(cell, fn() { how }, fn() { None }, fn() { said }, own=true)
  }
}

///|
/// A state in a tinted pill (state_pill's) in `parent`, or (`own`) drawn in `parent` itself: its glyph (GitHub's, 12)
/// where `glyph` says one and its name (`words`), 500, in the state's colours (state_colours), each as it changes.
fn state_pill_node(
  parent : @view.View,
  state : () -> String,
  glyph : () -> String?,
  words : () -> String,
  own? : Bool = false,
) -> Unit {
  let pill = fn(p : @view.View) {
    @sf.style_node(p, fn() { peek_state }, in_row=true)
    p.ground(By(fn() { state_colours(state()).1 })) |> ignore
    p.show(fn() { glyph() is Some(_) }, fn(g) {
      g
      .width(Is(Some(peek_glyph)))
      .height(Is(Some(peek_glyph)))
      .shapes(By(fn() {
        match glyph() {
          Some(d) => @ui.vector_shapes(glyph_of(d, state_colours(state()).0), peek_glyph, g.pixel_scale())
          None => []
        }
      }))
      |> ignore
    })
    @sf.words_node(p, words, fn() { peek_state_words }).ink(By(fn() { state_colours(state()).0 })) |> ignore
  }
  if own {
    pill(parent)
  } else {
    parent.box(pill) |> ignore
  }
}

///|
/// GitHub's mark (github_mark's) in `parent`, `w` wide, in `ink` as it changes.
fn github_mark_node(parent : @view.View, w : Double, ink : () -> Int64) -> Unit {
  parent.box(fn(g) {
    g
    .width(Is(Some(w)))
    .height(Is(Some(w)))
    .shapes(By(fn() { @ui.vector_shapes(glyph_of(github_path, ink()), w, g.pixel_scale()) }))
    |> ignore
  })
  |> ignore
}

///|
/// A web link's address to copy, on its card (link_copy's) in `parent`: 复制链接 to press, 已复制 for copied_ms once
/// copied (from the moment it was pressed: pressed again while it says so, from then). By the link, as link_copy's mark
/// is: a card of it made again while that lasts (gone and pointed at again) says 已复制 till its end.
fn link_copy_node(parent : @view.View, href : () -> String) -> Unit {
  let copied = @signals.signal(false, same=fn(a, b) { a == b })
  let off : Ref[() -> Unit] = Ref(fn() {  })
  // (said so from `at`, the moment it was copied, till copied_ms on; off as of then)
  let said_from = fn(at : Double) {
    (off.val)()
    if parent.cause_at() < at + @sf.copied_ms {
      copied.set(true)
      off.val = parent.at_moment(at + @sf.copied_ms, fn() { copied.set(false) })
    } else {
      copied.set(false)
    }
  }
  // (made while it says so from the last copy of the link, on another card of it: till that one's end)
  parent.reacts(fn() { () }, fn(_) {
    match peek_copied_at.get(@signals.untracked(href)) {
      Some(at) => said_from(at)
      None => ()
    }
  })
  // (its words, as a file's path's copy: the user, 2026-10-29: 图标改成文字复制链接吧)
  @sf.panel_button_node(
    parent,
    fn() { @sf.t(if copied.get() { "common.copied" } else { "common.link.copy" }) },
    fn() {
      let link = @signals.untracked(href)
      @ui.clipboard_set(link)
      let at = parent.cause_at()
      peek_copied_at[link] = at
      said_from(at)
    },
    tone=Quiet,
  )
  |> ignore
  parent.owns(fn() { (off.val)() }) |> ignore
}

///|
/// When each link's address was last copied from its card (link_copy_node's), by the link: what a card of it made again
/// says, as link_copy's mark by the link is kept.
// kept across runs: let go as the app begins anew (hover_reset)
let peek_copied_at : Map[String, Double] = Map([])
