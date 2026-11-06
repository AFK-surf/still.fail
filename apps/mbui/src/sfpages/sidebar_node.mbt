// The chats' lists (sidebar.mbt's) as nodes of the window's tree: 全部, 我参与的 and 监控中 side by side on one track,
// slid from one to another as the filter changes, each as the core's `chats` view lists it now: its days under their
// headings, a row each (chat_row_node), each line made only while it shows (View::scrolls_window); while it is read the
// rows to come, what is wrong over them, an empty list's words. While the hand is on a list its rows keep their places
// (sfbase's held_order).

///|
/// What the frame gives the lists made once (ListsFrame's, as they are now): the room over them and at their foot, how
/// far down what is over them covers their box (`under`), their ground, what stands at a list's top before its words and
/// rows (`before`) and after its words (`after`), each said for a list's filter and its view; the lists on the track
/// after the three, and which of all of them is shown; where the lists stand; whether they are in view (`watched`: what
/// changes meanwhile comes and goes; not while another page is over them, the list as it is come back to).
pub(all) struct ListsNodeFrame {
  top : () -> Double
  under : () -> Double
  foot : () -> Double
  ground : () -> Int64
  before : (String, ChatsView?) -> Array[NodePart]
  after : (String, ChatsView?) -> Array[NodePart]
  others : Array[(@view.View) -> Unit]
  shown : () -> Int
  at : @sf.ListAt
  watched : () -> Bool
}

///|
/// Something a frame puts in a list made once (ListPart's): its key among the list's lines, what makes it.
pub(all) struct NodePart {
  key : String
  make : (@view.View) -> Unit
}

///|
/// The chats' lists of the workspace in view (`workspace`) in node `v`, as `frame` says: the track the filter slides,
/// a list's width a step (the theme's slide), the lists on it each its whole width. Tips in `tips`, pictures asked for
/// on `stint`.
pub fn chats_lists_node(
  v : @view.View,
  src : Source,
  workspace : () -> Workspace?,
  frame : ListsNodeFrame,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let at = @sf.EdgeWay::new(@signals.untracked(frame.shown).to_double())
  // (as large as what holds it gives it: over all of it, its frame's)
  v.clips(Is(true)) |> ignore
  // (a list's width a step: the theme's slide, a Move as long as it goes, from as wide as the lists are as it is said)
  // (at rest the one shown alone drawn; sliding from one to another, those from the one it came from till it is there)
  let rest : @signals.Signal[Int] = @signals.signal(@signals.untracked(frame.shown))
  let due = Ref(fn() {  })
  v.reacts(frame.shown, fn(k) {
    let (_, _, w, _) = v.laid_window_now()
    at.go_by(v, k.to_double(), @sf.theme().chat_list.slide.per_unit(w))
    (due.val)()
    due.val = v.at_moment(at.end(), fn() { rest.set(k) })
  })
  // the search's page open over them (search.mbt: from a list's field, or by ⌘K laid out Small): the lists up and away
  // under it
  let away = search_away_node(v)
  v.pick(fn() { workspace().map(fn(w) { w.id }) }, fn(p, id) {
    guard id is Some(id) else { return }
    p
    .grow(Is(1.0))
    .min_height(Is(Some(0.0)))
    // (gone by half way, what the search finds coming in after: never the lists' words and its seen one over another)
    .alpha(By(fn() { dmax(0.0, 1.0 - 2.0 * away()) }))
    .offset(By(fn() { (0.0, -search_list_rise * away()) }))
    |> ignore
    let all = list_filters.length() + frame.others.length()
    // (which of the lists have been shown in this workspace: what is made of them is kept from then)
    let shown_once : Array[@signals.Signal[Bool]] = Array::makei(all, fn(i) {
      @signals.signal(@signals.untracked(frame.shown) == i)
    })
    p.reacts(frame.shown, fn(k) {
      if k >= 0 && k < all {
        shown_once[k].set(true)
      }
    })
    // (the filter's menu opened: the three lists read and made by the time one is picked, kept from then)
    let opened_before = @signals.untracked(fn() { filter_menu_opened.get() })
    p.reacts(fn() { filter_menu_opened.get() }, fn(n) {
      if n > opened_before {
        for k in 0..<list_filters.length() {
          if list_filters[k] != "hidden" { shown_once[k].set(true) }
        }
      }
    })
    for i in 0..<all {
      p.box(fn(lane) {
        lane
        .over(Is(true))
        .shift(By(fn() { (i.to_double() - at.shown(lane), 0.0) }))
        // (out of view: no taller than nothing, so its list makes none of its rows; its height back as it comes)
        .max_height(By(fn() {
          let (a, b) = ((frame.shown)(), rest.get())
          if i < (if a < b { a } else { b }) || i > (if a < b { b } else { a }) {
            Some(0.0)
          } else {
            None
          }
        }))
        .clips(Is(true))
        |> ignore
        // (made once it is shown, or as the filter's menu opens (what it would show read by the time one is picked),
        // kept from then while the workspace is: each row only while it is in view; where it is scrolled to its list's
        // own, kept by the list's key: list_scroll)
        lane.show(fn() { shown_once[i].get() }, fn(l) {
          l.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          if i < list_filters.length() {
            chats_pane_node(l, src, id, list_filters[i], frame, fn() { (frame.shown)() == i }, tips, stint)
          } else {
            (frame.others[i - list_filters.length()])(l)
          }
        })
      })
      |> ignore
    }
  })
}

///|
/// One of the lists (chats_pane's) of workspace `id` filtered by `filter` in node `v`: its states (being read, failing,
/// empty) and its days under the room `frame` keeps over them; `current`, the one shown.
fn chats_pane_node(
  v : @view.View,
  src : Source,
  id : String,
  filter : String,
  frame : ListsNodeFrame,
  current : () -> Bool,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let key = "chats/" + id + "/" + filter
  let read = fn() { @sfbase.chats_of(src, id, filter) }
  let scroll = list_scroll(key)
  // how far it is put to tuck its search out of view, as it was first placed (tucked_by's); the room its foot keeps for
  // that; whether it is to be put there still (the hand not on it since)
  let tuck : @signals.Signal[Double?] = @signals.signal(tucked_by.get(key))
  let slack : @signals.Signal[Double] = @signals.signal(0.0)
  let owed = Ref(false)
  // (while the hand is on the list or it glides, its rows keep their places; a row the viewer moved goes at once)
  let held = fn() { v.pointed_in() || scroll.glides_till() is Some(_) }
  // its days in the order shown, and its rows by their names: worked out once as what is read, or the hand on it,
  // changes (held_order), what its lines and rows read
  let ordered : @signals.Signal[Array[ChatDay]] = @signals.signal([])
  // (how many times the order shown has been said: what follows it told as it changes)
  let revision : @signals.Signal[Int] = @signals.signal(0)
  let seen : Ref[Array[ChatDay]] = Ref([])
  let stamp = Ref(0)
  v.reacts(
    fn() {
      // (the core's days, a new array each time they change: told by a number as they do)
      let days = match read().0 {
        Some(view) => view.days
        None => []
      }
      if !physical_equal(days, seen.val) {
        seen.val = days
        stamp.val += 1
      }
      (stamp.val, held())
    },
    fn(at) {
      let days = seen.val
      if at.1 {
        owed.val = false
      }
      let hold = at.1 && !@sfbase.viewer_moved(key, days)
      let shown = @sfbase.held_order(key, days, hold)
      ordered.set(shown)
      revision.set(@signals.untracked(fn() { revision.get() }) + 1)
    },
  )
  let days = fn() { ordered.get() }
  // The same keyed rows as every other retained list: old-position copies and departures retain their values, while
  // a row that stays reads its latest value. The sidebar's first nonempty reading appears at once.
  let sizes : @ui.ListRows[SidebarLine] = @ui.ListRows::new()
  let had = Ref(false)
  let lines = fn() {
    let out : Array[SidebarLine] = []
    for d in days() {
      out.push(Heading(d.label))
      for item in d.items { out.push(Chat(item)) }
    }
    out
  }
  let motion = sizes.in_node(v, lines, sidebar_line_key, fn(_) { "" },
    watched=fn() { current() && (frame.watched)() && !days().is_empty() },
    moves=fn(line) { line is Chat(_) },
    continuity=fn() {
      if !days().is_empty() { had.val = true }
      if had.val { Some("") } else { None }
    })
  let by_key = @signals.computed(fn(_) {
    let (items, keys) = (motion.read)()
    let out : Map[String, SidebarLine] = {}
    for i, k in keys { out[k] = items[i] }
    out
  })
  // A replay asks when the latest row change ends; this says the cause's declared end, not a sampled animation.
  v.reacts(fn() {
    let (_, keys) = (motion.read)()
    let mut end = -1.0
    for k in keys {
      let at = match sizes.came(k) { Some(t) => Some(t); None => sizes.went(k) }
      match at { Some(t) => end = dmax(end, t + row_size_ms); None => () }
    }
    end
  }, fn(end) { if end > rows_rest_at.val { rows_rest_at.val = end } })
  // its lines' keys: its room under the bar, what the frame puts at its top, its states, its days, its foot
  let keys = fn() {
    let (view, _) = read()
    let out = ["top"]
    if search_tucked(view) {
      out.push("search")
    }
    for p in (frame.before)(filter, view) {
      out.push("part/" + p.key)
    }
    match view {
      None => out.push("wait")
      Some(v) => {
        match v.note {
          Some(n) if v.days.length() == 0 && (n.reading || n.failing.length() > 0) => out.push("wait")
          _ => ()
        }
        match v.note {
          Some(n) if n.empty && v.days.length() == 0 => out.push("empty")
          _ => ()
        }
        for p in (frame.after)(filter, Some(v)) {
          out.push("part/" + p.key)
        }
        out.append((motion.read)().1)
      }
    }
    out.push("foot")
    out
  }
  // (the shown one's rows: those an archived chat's neighbour is looked for in)
  v.reacts(fn() { (current(), revision.get()) }, fn(_) {
    if @signals.untracked(current) {
      listed.val = @signals.untracked(days).map(fn(d) { d.items }).fold(init=[], fn(a, b) { a + b })
      match @signals.untracked(read).0 {
        Some(view) => @sfbase.open_listed(view)
        None => ()
      }
    }
  })
  let lead = fn() {
    match read().0 {
      Some(view) => view.leading
      None => "agents"
    }
  }
  // the list's first time with its rows: the search tucked over them out of view, the first line after it at the foot
  // of what covers the list (frame.under: a phone's top bar, not the room under it), there once scrolled to (as far as
  // the room over the list and the field's line come to past that foot)
  // (where the field is laid out, as it is first: put by where it is, never by what it is said to be)
  let search_line : Ref[@view.View?] = Ref(None)
  let search_laid : @signals.Signal[Bool] = @signals.signal(false)
  v.reacts(fn() { (search_tucked(read().0), search_laid.get()) }, fn(now) {
    if now.0 && now.1 && !placed.contains(key) && search_line.val is Some(line) && line.alive() {
      placed[key] = true
      // (what covers the list's top: Home's top bar to its foot; a side column's band, the room over the list)
      let cover = match frame.at {
        Side => (frame.top)()
        Whole => (frame.under)()
      }
      // (not scrolled yet: where it is in the list is where it is laid out in it)
      let (_, fy, _, fh) = line.placed_window_now()
      let (_, vy, _, _) = v.placed_window_now()
      let at = fy - vy + fh - cover
      tucked_by[key] = at
      tuck.set(Some(at))
      owed.val = true
      scroll.put(at)
    }
  })
  // (as far as it goes with fewer rows than it is tall: its foot keeps the room it lacks to go there, the search tucked
  // all the same however few they are; put there again where it came short of it as it was laid out, till the hand is
  // on it)
  v.reacts(fn() { (tuck.get(), scroll.reach(), search_tucked(read().0)) }, fn(now) {
    let had = @signals.untracked(fn() { slack.get() })
    let want = match now {
      (Some(at), most, true) => dmax(0.0, at - (most - had))
      _ => 0.0
    }
    if (want - had).abs() >= 0.5 {
      slack.set(want)
      return
    }
    match now.0 {
      Some(at) if owed.val && scroll.at(v.tree) < at - 0.5 && now.1 >= at - 0.5 => scroll.put(at)
      _ => ()
    }
  })
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (its bar along its right, clear of what is over its top and at its foot: the band, the bars)
  v.scrolls_window(
    scroll,
    keys,
    est=@signals.untracked(fn() { @sf.theme().chat_list.row_h }),
    bar=@ui.tree_scroll_bar(),
    bar_clear=fn() { ((frame.top)(), (frame.foot)()) },
    foot_room=fn() { slack.get() },
    fn(b, k) {
    b.box(fn(line) {
      @sf.style_node(line, fn() { @sf.list_line(frame.at) })
      match k {
        "top" => line.height(By(fn() { Some((frame.top)() + @sf.theme().chat_list.top_in) })) |> ignore
        "foot" => line.height(By(fn() { Some((frame.foot)() + @sf.list_foot_in(frame.at)) })) |> ignore
        "search" => {
          let field = search_field_node(line, frame.at)
          // (told as it is first laid out: where it is then)
          field.reacts(fn() { field.laid_size_told() is Some(_) }, fn(laid) {
            if laid {
              search_line.val = Some(field)
              search_laid.set(true)
            }
          })
        }
        "wait" => list_waiting_node(line, src, read, frame.at, tips, stint)
        "empty" => list_empty_node(line, read, filter, frame.at)
        _ if k.has_prefix("part/") => {
          let part = k.view(start_offset=5).to_owned()
          let (view, _) = @signals.untracked(read)
          let parts = (frame.before)(filter, view) + (frame.after)(filter, view)
          match parts.iter().find_first(fn(p) { p.key == part }) {
            Some(p) => (p.make)(line)
            None => ()
          }
        }
        _ if k.has_prefix("h/") => {
          sidebar_line_node(sizes, line, k)
          @sf.list_heading_node(line, fn() {
            match by_key.get().get(k) { Some(Heading(label)) => label; _ => "" }
          }, frame.at)
        }
        _ => {
          sidebar_line_node(sizes, line, k)
          // (a row gone, or the copy of one gone ahead of others where it was: as it was, drawn only)
          let entry = fn() {
            match by_key.get().get(k) { Some(Chat(item)) => Some(item); _ => None }
          }
          let gone = if @signals.untracked(fn() { sizes.went(k) is Some(_) }) { @signals.untracked(entry) } else { None }
          match gone {
            // (swiped off: out of sight already, its room closing alone)
            Some(gone) if swiped_gone(gone) => return
            Some(gone) => {
              line.box(fn(o) {
                o.presses(Is(false)) |> ignore
                chat_row_node(o, src, tips, fn() { gone }, @signals.untracked(lead), fn() { false }, frame.at, stint, list_ground=frame.ground, more=true)
                |> ignore
              })
              |> ignore
              return
            }
            None => ()
          }
          guard @signals.untracked(entry) is Some(first) else { return }
          let last : Ref[ChatItem] = Ref(first)
          let item = fn() {
            match entry() {
              Some(i) => {
                last.val = i
                i
              }
              None => last.val
            }
          }
          let on = fn() {
            match open_chat() {
              Some(r) => @sfbase.row_is(item(), r)
              None => false
            }
          }
          // (gone from the list: leaving as its room closes, drawn as it was, no longer pressed nor found)
          line.show(fn() { sizes.went(k) is None }, leave=row_size_ms, fn(r) {
            chat_row_node(r, src, tips, item, @signals.untracked(lead), on, frame.at, stint, list_ground=frame.ground, more=true)
            |> ignore
          })
        }
      }
    })
    |> ignore
  },
  )
  |> ignore
}

///|
/// A list read the first time, or with no rows to show while it waits on a station or cannot read one (list_waiting's)
/// in `v`: the rows to come in their bones, what is wrong over them in red, as many as the theme's chats' list has them.
fn list_waiting_node(
  v : @view.View,
  src : Source,
  read : () -> (ChatsView?, String?),
  at : @sf.ListAt,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let note = fn() {
    match read().0 {
      Some(v) => v.note
      None => None
    }
  }
  let reading = fn() {
    match note() {
      Some(n) => n.reading
      None => true
    }
  }
  @sf.waiting_node(
    v,
    fn(s) {
      let l = @sf.theme().chat_list
      let n = if @signals.untracked(reading) { l.waiting_rows } else { l.waiting_noted }
      for i in 0..<n {
        let item = sample_chat(i)
        chat_row_node(s, src, tips, fn() { item }, "agents", fn() { false }, at, stint, more=i + 1 < n) |> ignore
      }
    },
    error=fn() { read().1.unwrap_or("") },
    note=fn() {
      match note() {
        Some(nt) => { reading: nt.reading, text: nt.text.unwrap_or(@sf.t("common.reading")), failing: nt.failing }
        None => { reading: true, text: @sf.t("common.reading"), failing: [] }
      }
    },
  )
}

///|
/// A list with nothing in it (list_empty's) in `v`: across the whole screen, the phone's illustration and what to do (a
/// new chat; with no station, the stations); in a side column (`at`), the sidebar's words (with no station, its link to
/// them).
fn list_empty_node(v : @view.View, read : () -> (ChatsView?, String?), filter : String, at : @sf.ListAt) -> Unit {
  let stations = fn() {
    match read().0 {
      Some(v) => v.stations
      None => 0
    }
  }
  v.pick(fn() {
    if at == Side {
      0
    } else if stations() == 0 && filter == "all" {
      1
    } else {
      2
    }
  }, fn(p, which) {
    match which {
      0 =>
        p.box(fn(b) {
          @sf.style_node(b, fn() { said_box })
          match filter {
            "mine" => @sf.words_node(b, fn() { @sf.t("web-main.sidebar.noneMine") }, fn() { said_words }) |> ignore
            "watching" => @sf.words_node(b, fn() { @sf.t("web-main.sidebar.noneWatching") }, fn() { said_words }) |> ignore
            "hidden" => @sf.words_node(b, fn() { @sf.t("web-main.filter.hiddenEmpty") }, fn() { said_words }) |> ignore
            _ =>
              b.pick(fn() { stations() > 0 }, fn(q, some) {
                if some {
                  @sf.words_node(q, fn() { @sf.t("web-main.sidebar.none") }, fn() { said_words }) |> ignore
                } else {
                  @sf.note_link_node(q, fn() { @sf.t("web-main.sidebar.noStation.before") }, fn() {
                    @sf.t("web-main.sidebar.noStation.link")
                  }, fn() { open_page(Place("stations")) })
                }
              })
          }
        })
        |> ignore
      1 =>
        p.box(fn(b) {
          @sf.style_node(b, fn() { empty_first })
          @sf.drawable_node(b, fn() { if @sf.theme().dark { "illus_no_station_dark" } else { "illus_no_station" } }, illustration_w) |> ignore
          @sf.words_node(b, fn() { @sf.t("android-settings.station.first") }, fn() { empty_title }) |> ignore
          @sf.words_node(b, fn() { @sf.t("android-settings.station.firstNote") }, fn() { empty_note }) |> ignore
        })
        |> ignore
      _ =>
        p.box(fn(b) {
          @sf.style_node(b, fn() { empty_box })
          @sf.drawable_node(b, fn() { if @sf.theme().dark { "illus_new_chat_dark" } else { "illus_new_chat" } }, illustration_w) |> ignore
          match filter {
            "mine" => @sf.words_node(b, fn() { @sf.t("android-chat.home.empty.mine") }, fn() { empty_words }) |> ignore
            "watching" =>
              @sf.words_node(b, fn() { @sf.t("android-chat.home.empty.watching") }, fn() { empty_words }) |> ignore
            "hidden" => @sf.words_node(b, fn() { @sf.t("web-main.filter.hiddenEmpty") }, fn() { empty_words }) |> ignore
            _ => {
              @sf.words_node(b, fn() {
                @sf.t(if stations() > 1 { "android-chat.home.empty.many" } else { "android-chat.home.empty.one" })
              }, fn() { empty_note })
              |> ignore
              b.box(fn(k) {
                @sf.presses_node(k, fn() { open_page(NewChat) })
                k.says(By(fn() { Some(@view.said(Button, label=@sf.t("android-chat.newChat"))) })) |> ignore
                @sf.words_node(k, fn() { @sf.t("android-chat.newChat") }, fn() { empty_link }) |> ignore
              })
              |> ignore
            }
          }
        })
        |> ignore
    }
  })
}


///|
/// Where each list made once is scrolled to, by its key (its workspace's and filter's): kept while the app runs, the
/// same as it is left and come back to.
// kept across runs: put back as a run begins (sidebar_reset)
let list_scrolls : Map[String, @view.Scroll] = {}

///|
/// Each of the lists made once at its top (what is tucked over its rows in view): as a recording's list at its top
/// (sfapp's tape: listTop) has it.
pub fn lists_top() -> Unit {
  for _, s in list_scrolls {
    s.put(0.0)
  }
}

///|
/// List `key`'s scroll (list_scrolls'), made the first time it is asked for.
fn list_scroll(key : String) -> @view.Scroll {
  match list_scrolls.get(key) {
    Some(s) => s
    None => {
      let s = @view.Scroll::list()
      list_scrolls[key] = s
      s
    }
  }
}

///|
/// Whether a list as `view` says has the search at its top (sidebar.mbt's lines'): where the screen has no keys for ⌘K
/// (touch's: the theme's), while it has rows to look in.
fn search_tucked(view : ChatsView?) -> Bool {
  if @sf.theme().chat_list.keys || @sf.native_able() {
    return false
  }
  match view {
    Some({ note: Some({ empty: true, .. }), .. }) | None => false
    Some(_) => true
  }
}

///|
/// A day's heading or one of its chats, kept as it was while it leaves the list.
priv enum SidebarLine {
  Heading(String)
  Chat(ChatItem)
}

///|
fn sidebar_line_key(line : SidebarLine) -> String {
  match line {
    Heading(label) => "h/" + label
    Chat(item) => "r/" + @sfbase.row_name(item)
  }
}

///|
/// The sidebar's own row look, on the shared list's causes: its original Out curve, sampled from the change's
/// moment even when a windowed row is made after that moment.
fn sidebar_line_node(sizes : @ui.ListRows[SidebarLine], line : @view.View, key : String) -> Unit {
  let open = fn() {
    let ease : @ui.Ease = Out
    match sizes.came(key) {
      Some(at) => Some(ease.at((line.drawn_at() - at) / row_size_ms))
      None =>
        match sizes.went(key) {
          Some(at) => Some(1.0 - ease.at((line.drawn_at() - at) / row_size_ms))
          None => None
        }
    }
  }
  line
  .opens(By(open))
  .cuts_softly(By(fn() { open() is Some(_) }))
  .alpha(By(fn() {
    match open() {
      Some(p) => dmax(0.0, (p - @ui.row_gone_at) / (1.0 - @ui.row_gone_at))
      None => 1.0
    }
  }))
  .scale(By(fn() { open().unwrap_or(1.0) }))
  |> ignore
}

///|
/// When the rows of the lists made once last set coming, going or ahead of others are at rest (-1: none yet), as a
/// scripted run waits for a list's rows to be in place (a row come in, its room open).
// kept across runs: put back by sidebar_reset
let rows_rest_at : Ref[Double] = Ref(-1.0)

///|
/// When the lists' rows set moving last are at rest (rows_rest_at's).
pub fn rows_rest() -> Double {
  rows_rest_at.val
}

///|
/// How long a row's coming or going takes (mbui's ListRows: row_size_ms).
let row_size_ms : Double = @ui.row_size_ms
