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
  // a chat archived from its row: its 撤销 offered there toast_action_ms, as a toast's, then over (archived_here: its
  // line leaves the list, RowsMotion::undo_over); timed here, where a row's block made again does not take it along
  let undo_due = Ref(fn() {  })
  v.reacts(fn() { archived_here.get().map(fn(a) { a.n }) }, fn(n) {
    (undo_due.val)()
    undo_due.val = fn() {  }
    guard n is Some(n) else { return }
    undo_due.val = v.at_moment(
      v.cause_at() + @sf.toast_action_ms,
      fn() {
        match archived_here.untracked() {
          Some(a) if a.n == n && !a.undone => archived_here.set(None)
          _ => ()
        }
      },
      later=true,
    )
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
    let opened_before = filter_menu_opened.untracked()
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
  // (while the hand is on the list or it glides, its rows keep their places; a row the viewer moved goes at once)
  let held = fn() { v.pointed_in() || scroll.glides_till() is Some(_) }
  // its days in the order shown, and its rows by their names: worked out once as what is read, or the hand on it,
  // changes (held_order), what its lines and rows read
  let ordered : @signals.Signal[Array[ChatDay]] = @signals.signal([])
  let rows : @signals.Signal[Map[String, ChatItem]] = @signals.signal({})
  // (how many times the order shown has been said: what follows it told as it changes)
  let revision : @signals.Signal[Int] = @signals.signal(0)
  let seen : Ref[Array[ChatDay]] = Ref([])
  let stamp = Ref(0)
  // A count alone helps diagnose the work of opening a list, without recording any chat's name or contents.
  let recorded_rows = Ref(-1)
  // what of its rows and days comes, goes and goes ahead of others as the list changes while it is watched (ListRows'):
  // its lines as last shown, the rows going still among them (each after the line it came after, as it was), each
  // line coming or going and since when; told by a number as they change
  let motion = RowsMotion::new()
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
      // (and its page's stay on top: what changed while it was off the top said as it is put back there, RowsMotion::said)
      (stamp.val, held(), stint())
    },
    fn(at) {
      let days = seen.val
      let hold = at.1 && !@sfbase.viewer_moved(key, days)
      let shown = @sfbase.held_order(key, days, hold)
      let by_name : Map[String, ChatItem] = Map([])
      for d in shown {
        for item in d.items {
          by_name[@sfbase.row_name(item)] = item
        }
      }
      if @hostapi.perf_recording() && by_name.length() != recorded_rows.val {
        recorded_rows.val = by_name.length()
        @hostapi.perf_line("chat-list: filter=\{filter} rows=\{recorded_rows.val}")
      }
      motion.said(
        v,
        shown,
        by_name,
        @signals.untracked(current),
        @signals.untracked(current) && @signals.untracked(frame.watched),
        at.2,
        @sfbase.chats_window_asked(id, filter),
      )
      ordered.set(shown)
      rows.set(by_name)
      revision.set(revision.untracked() + 1)
    },
  )
  let days = fn() { ordered.get() }
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
        out.append(motion.lines(days()))
      }
    }
    out.push("foot")
    out
  }
  // (each row's chat by its name, as the days have it now)
  let item_of = fn(name : String) -> ChatItem? { rows.get().get(name) }
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
  // (how many more the core has, read anew only as its list changes, not each time the column is scrolled)
  let more = @signals.computed(fn(_) { @sfbase.chats_more(src, id, filter) })
  // (a window made taller: the list told the first window of it, where it holds fewer and the core has more; it never
  // shrinks)
  let held_rows = @signals.computed(fn(_) { @sfbase.chats_held(read().0) })
  v.reacts(fn() { (v.window().1, more.get(), held_rows.get()) }, fn(at) {
    @sfbase.chats_window_for(src, id, filter, at.0, at.2, at.1)
  })
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (a chat's row in line `line`, its key as it is now (`key`: "r/" and its name, another's as the row is taken for
  // another, View::scrolls_window's reused): as its chat is now, the last it was where it is gone from the list (its
  // archive's 撤销 offered in its line, made again as that is scrolled back to))
  let row_line = fn(line : @view.View, key : () -> String) {
    let open = motion.line_node(line, key)
    let name = fn() { key().exact_view(start=2).to_owned() }
    let found = match @signals.untracked(fn() { item_of(name()) }) {
      Some(i) => Some(i)
      None => motion.gone_item(@signals.untracked(key))
    }
    guard found is Some(first) else { return }
    // (looked up once as its key or the days change, not by each of what of the row reads it: the last it was where it
    // is gone)
    let now = @signals.computed(fn(was : ChatItem?) {
      match item_of(name()) {
        Some(i) => i
        None => was.unwrap_or(first)
      }
    })
    let item = fn() { now.get() }
    let on = fn() {
      match open_chat() {
        Some(r) => @sfbase.row_is(item(), r)
        None => false
      }
    }
    // (gone from the list: leaving as its room closes, drawn as it was, no longer pressed nor found; archived from it,
    // its line kept, the row's own node showing its tray there, till that is over and its room closes so)
    line.show(fn() { !motion.going_now(key()) || motion.undo_line(key()) }, leave=row_size_ms, fn(r) {
      // (its tray's line closing: held at its top, the room's foot coming up over it (line_node), half of what has
      // closed back down from the middle the room lays it out in)
      r
      .shift(By(fn() {
        match open() {
          Some(p) if motion.undo_line(key()) => (0.0, (1.0 - p) / 2.0)
          _ => (0.0, 0.0)
        }
      }))
      |> ignore
      chat_row_node(
        r,
        src,
        tips,
        item,
        @signals.untracked(lead),
        on,
        frame.at,
        stint,
        list_ground=frame.ground,
        more=true,
        kept=fn() { motion.going_now(key()) },
      )
      |> ignore
    })
  }
  // (an archive's 撤销 over, or another's said: the line of the one before leaves)
  v.reacts(fn() { archived_here.get().map(fn(a) { a.n }) }, fn(_) { motion.undo_over(v, archived_here.untracked()) }, at_start=false)
  // (its bar along its right, clear of what is over its top and at its foot: the band, the bars)
  v.scrolls_window(
    scroll,
    keys,
    est=@signals.untracked(fn() { @sf.theme().chat_list.row_h }),
    bar=@ui.tree_scroll_bar(),
    top_covered=frame.top,
    bar_clear=fn() { ((frame.top)(), (frame.foot)()) },
    // (at once, as it was: a debt of 方案 A, given its way list by list, shown to the owner: list-comes-off)
    at_once=true,
    // scrolled to within a screen of its foot while the core has more of its rows: its window a step more, the rows
    // added coming into the list it holds. A screen, not a screen and a half: its first window is what its room shows
    // and a screen more (sfbase's first_window), its foot a screen and a little below at rest, which a screen and a
    // half would have grown the moment it opened
    near_foot=(1.0, fn() { more.get() > 0 }, fn() {
      @sfbase.chats_grow(src, id, filter, @signals.untracked(fn() { held_rows.get() }), @signals.untracked(fn() { more.get() }))
    }),
    fn(b, k) {
    b.box(fn(line) {
      @sf.style_node(line, fn() { @sf.list_line(frame.at) })
      match k {
        "top" => line.height(By(fn() { Some((frame.top)() + @sf.theme().chat_list.top_in) })) |> ignore
        "foot" => line.height(By(fn() { Some((frame.foot)() + @sf.list_foot_in(frame.at)) })) |> ignore
        "search" => {
          let field = search_field_node(line, frame.at)
          // the list's first time with its rows: the search tucked over them out of view, the first line after it at the
          // foot of what covers the list (frame.under: a phone's top bar, not the room under it; a side column's band,
          // the room over the list), there once scrolled to (Scroll::tucks: as far as the room over the list and the
          // field's line come to past that foot)
          scroll.tucks(
            field,
            fn() {
              match frame.at {
                Side | Tape => (frame.top)()
                Whole => (frame.under)()
              }
            },
            kept=fn() { search_tucked(read().0) },
          )
        }
        "wait" => list_waiting_node(line, src, read, frame.at, tips, stint)
        "empty" => list_empty_node(line, read, filter, frame.at)
        _ if k.has_prefix("part/") => {
          let part = k.exact_view(start=5).to_owned()
          let (view, _) = @signals.untracked(read)
          let parts = (frame.before)(filter, view) + (frame.after)(filter, view)
          match parts.iter().find_first(fn(p) { p.key == part }) {
            Some(p) => (p.make)(line)
            None => ()
          }
        }
        _ if k.has_prefix("h/") => {
          motion.line_node(line, fn() { k }) |> ignore
          @sf.list_heading_node(line, fn() { k.exact_view(start=2).to_owned().replace_all(old=moved_mark, new="") }, frame.at)
        }
        _ => {
          // (a row gone, or the copy of one gone ahead of others where it was: as it was, drawn only)
          match motion.gone_item(k) {
            // (archived from its row: its line kept, its own row showing its tray, its 撤销 there)
            Some(_) if @signals.untracked(fn() { motion.undo_line(k) }) => {
              row_line(line, fn() { k })
              return
            }
            // (swiped off: out of sight already, its room closing alone)
            Some(gone) if swiped_gone(gone) => {
              motion.line_node(line, fn() { k }) |> ignore
              return
            }
            Some(gone) => {
              motion.line_node(line, fn() { k }) |> ignore
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
          row_line(line, fn() { k })
        }
      }
    })
    |> ignore
  },
    // (a chat's row, and a day's heading, as it no more shows, taken by the next of its kind to come to show: its key
    // that one's, not made and let go as the list is scrolled; one gone, as it was, not)
    reused=fn(k) {
      if k.contains(moved_mark) {
        None
      } else if k.has_prefix("r/") && motion.gone_item(k) is None {
        Some(0)
      } else if k.has_prefix("h/") {
        Some(1)
      } else {
        None
      }
    },
    make_reused=fn(b, key) {
      b.box(fn(line) {
        @sf.style_node(line, fn() { @sf.list_line(frame.at) })
        if @signals.untracked(key).has_prefix("h/") {
          motion.line_node(line, key) |> ignore
          @sf.list_heading_node(line, fn() { key().exact_view(start=2).to_owned() }, frame.at)
        } else {
          row_line(line, key)
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
    if at != Whole {
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
          @sf.drawable_node(b, if @sf.theme().dark { "illus_no_station_dark" } else { "illus_no_station" }, illustration_w) |> ignore
          @sf.words_node(b, fn() { @sf.t("android-settings.station.first") }, fn() { empty_title }) |> ignore
          @sf.words_node(b, fn() { @sf.t("android-settings.station.firstNote") }, fn() { empty_note }) |> ignore
        })
        |> ignore
      _ =>
        p.box(fn(b) {
          @sf.style_node(b, fn() { empty_box })
          @sf.drawable_node(b, if @sf.theme().dark { "illus_new_chat_dark" } else { "illus_new_chat" }, illustration_w) |> ignore
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
let list_scrolls : Map[String, @view.Scroll] = Map([])

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
/// Whether a list as `view` says has the search at its top (sidebar.mbt's lines'): out of view till the list is pulled
/// down past its first row (Telegram's; asked 2026-11-14, a mouse's as a finger's, ⌘K beside it), while it has rows to
/// look in; not where the system's glass has a search of its own (sfdesk's chats.mbt sidebar_glass).
fn search_tucked(view : ChatsView?) -> Bool {
  if @sf.native_able() {
    return false
  }
  match view {
    Some({ note: Some({ empty: true, .. }), .. }) | None => false
    Some(_) => true
  }
}

///|
/// What a row gone ahead of others leaves by where it was is keyed by: its line's key and this (ListRows' row_moved_mark).
let moved_mark : String = "\u{2}was"

///|
/// A list's lines coming and going as it changes while it is watched (ListRows::rows', for a list made once): a row or a
/// day new to it comes where it is, its room opening; one gone leaves where it was, a copy of it as it was while its room
/// closes; a row gone ahead of others both (the fewest whose order changed: in_order_most). Each over row_size_ms from
/// its cause's moment, at the end let go. Nothing of it the first time it has rows, or while it is not the list shown.
priv struct RowsMotion {
  mut last : Array[String]
  mut last_items : Map[String, ChatItem]
  mut had : Bool
  // (the page's stay on top it was last said in: Nav's stint)
  mut stint : Int
  // (how many rows it held as it was last said: rows held grown within a window asked past that, a page more came)
  mut held : Int
  going : Map[String, (ChatItem?, String)]
  moving : Map[String, (Bool, Double)]
  // (rows gone from it that were archived from their rows (archived_here's): kept among its lines, going, their room
  // whole (no way of theirs in `moving`) while their 撤销 is offered; closing as a row gone does once that is over
  // (undo_over), or the list's again as their chat comes back)
  undo_lines : Set[String]
  told : @signals.Signal[Int]
}

///|
fn RowsMotion::new() -> RowsMotion {
  {
    last: [],
    last_items: {},
    had: false,
    stint: 0,
    held: 0,
    going: {},
    moving: {},
    undo_lines: Set([]),
    told: @signals.signal(0),
  }
}

///|
/// The days `days` as lines (a heading and its rows each), by their keys.
fn day_keys(days : Array[ChatDay]) -> Array[String] {
  let out = []
  for d in days {
    out.push("h/" + d.label)
    for item in d.items {
      out.push("r/" + @sfbase.row_name(item))
    }
  }
  out
}

///|
/// The list's days now said (`shown`, its rows `by_name`) in node `v`'s timeline, `current` whether it is the list in view,
/// `watched` whether it is the list shown, in its page's stay on top `stint`, the window its list was last told it grows to `asked` (chats_window_asked):
/// what came, went and went ahead set off from the cause's moment. What changed while its page was off the top (on 小屏
/// kept on the stack's shelf at rest, its list said again only as it is taken back: a new stint) is there at once, as on
/// a page made anew; so are the rows a page more brings (its rows held grown within a window asked past what it held,
/// the lines new to it after the last it had), only a chat that arrives coming where it is (the coordinator of the
/// migration's ruling, 2026-11-13: a page more's rows opening one by one, measured as they opened, a fling into them
/// showed the list's ground).
fn RowsMotion::said(
  self : RowsMotion,
  v : @view.View,
  shown : Array[ChatDay],
  by_name : Map[String, ChatItem],
  current : Bool,
  watched : Bool,
  stint : Int,
  asked : Int,
) -> Unit {
  let lines = day_keys(shown)
  let was = self.last
  // (archived here and come back (撤销, or its archive refused): the list's again, in the line it kept, no way in)
  let back : Set[String] = Set([])
  for k in lines {
    if self.undo_lines.contains(k) {
      back.add(k)
      self.undo_lines.remove(k)
      self.going.remove(k)
      self.moving.remove(k)
    }
  }
  if !back.is_empty() {
    self.told.set(self.told.untracked() + 1)
  }
  // (a page more come: more rows held than before, a window past what it held asked)
  let held = by_name.length()
  let paged = held > self.held && asked > self.held
  self.held = held
  let watched = watched && self.had && !lines.is_empty() && stint == self.stint
  self.stint = stint
  if watched && !(was == lines) {
    let now = v.cause_at()
    let here : Set[String] = Set([])
    for k in lines {
      here.add(k)
    }
    let before : Map[String, Int] = Map([])
    for j, k in was {
      before[k] = j
    }
    // (new to it: comes where it is; after the last line it had, in a page more that came, there at once)
    let past = match was.last() {
      Some(l) if paged => lines.search(l)
      _ => None
    }
    for i, k in lines {
      if !before.contains(k) && !back.contains(k) && !(past is Some(p) && i > p) {
        self.moving[k] = (true, now)
      }
      self.going.remove(k)
    }
    // (gone ahead of others: the fewest rows whose order changed, each leaving where it was and coming where it is)
    let at : Array[String] = []
    let was_at : Array[Int] = []
    for k in lines {
      match before.get(k) {
        Some(b) if k.has_prefix("r/") => {
          at.push(k)
          was_at.push(b)
        }
        _ => ()
      }
    }
    let kept = kept_in_order(was_at)
    let ahead : Set[String] = Set([])
    for n, k in at {
      if !kept[n] {
        ahead.add(k)
        self.moving[k] = (true, now)
      }
    }
    // (gone, and the copies of those gone ahead where they were: each after the line it came after)
    let mut prev = ""
    let mut kept_after = ""
    for k in was {
      if ahead.contains(k) {
        let copy = k + moved_mark
        self.going[copy] = (self.last_items.get(k.exact_view(start=2).to_owned()), prev)
        self.moving[copy] = (false, now)
        prev = copy
        continue
      }
      if !here.contains(k) && !self.going.contains(k) {
        let name = k.exact_view(start=2).to_owned()
        match archived_here.untracked() {
          // (archived from its row: its line kept whole after the last line before it that stays, its 撤销 there)
          Some(a) if k.has_prefix("r/") && a.name == name && !a.undone => {
            self.going[k] = (self.last_items.get(name), kept_after)
            self.undo_lines.add(k)
          }
          _ => {
            self.going[k] = (if k.has_prefix("r/") { self.last_items.get(name) } else { None }, prev)
            self.moving[k] = (false, now)
          }
        }
      }
      if here.contains(k) {
        kept_after = k
      }
      prev = k
    }
    // (over at the way's end: what went out of the list then, what came there whole)
    let end = now + row_size_ms
    if end > rows_rest_at.val {
      rows_rest_at.val = end
    }
    v.at_moment(end, fn() {
      let done = self.moving.to_array().filter(fn(m) { m.1.1 + row_size_ms <= end + 0.001 }).map(fn(m) { m.0 })
      for k in done {
        self.moving.remove(k)
        self.going.remove(k)
      }
      self.told.set(self.told.untracked() + 1)
    })
    |> ignore
    self.told.set(self.told.untracked() + 1)
  }
  // (archived from its row in the list in view, its line not kept (the list's last row gone with it, or its page not
  // on top as the core said it gone): said in a toast with its 撤销 as from anywhere else, never left unsaid)
  if current {
    match archived_here.untracked() {
      Some(a) if !a.undone => {
        let k = "r/" + a.name
        if was.contains(k) && !lines.contains(k) && !self.undo_lines.contains(k) {
          archived_here.set(None)
          (a.toast)()
        }
      }
      _ => ()
    }
  }
  self.had = self.had || !lines.is_empty()
  self.last = lines
  self.last_items = by_name
}

///|
/// The days `days` as lines with what goes still among them, each after the line it came after (the first, before all).
fn RowsMotion::lines(self : RowsMotion, days : Array[ChatDay]) -> Array[String] {
  self.told.get() |> ignore
  let out = day_keys(days)
  if self.going.is_empty() {
    return out
  }
  let order = self.going.to_array()
  order.sort_by(fn(a, b) { a.0.compare(b.0) })
  for g in order {
    let (k, (_, after)) = g
    let mut at = 0
    if after != "" {
      for i, kk in out {
        if kk == after {
          at = i + 1
        }
      }
    }
    out.insert(at, k)
  }
  out
}

///|
/// Whether line `key` is a row archived from it whose line is kept (its 撤销 offered there, or its room closing once that
/// is over), followed.
fn RowsMotion::undo_line(self : RowsMotion, key : String) -> Bool {
  self.told.get() |> ignore
  self.undo_lines.contains(key)
}

///|
/// The lines of rows archived from them whose 撤销 is over (all but the one `here` says, while it is offered): each
/// leaves now as a row gone does, its room closing over row_size_ms from `v`'s cause's moment.
fn RowsMotion::undo_over(self : RowsMotion, v : @view.View, here : ArchivedHere?) -> Unit {
  let over = self.undo_lines
    .to_array()
    .filter(fn(k) { !self.moving.contains(k) && !(here is Some(a) && "r/" + a.name == k) })
  if over.is_empty() {
    return
  }
  let now = v.cause_at()
  for k in over {
    self.moving[k] = (false, now)
  }
  let end = now + row_size_ms
  if end > rows_rest_at.val {
    rows_rest_at.val = end
  }
  v.at_moment(end, fn() {
    for k in over {
      if self.moving.get(k) is Some((false, _)) {
        self.moving.remove(k)
        self.going.remove(k)
        self.undo_lines.remove(k)
      }
    }
    self.told.set(self.told.untracked() + 1)
  })
  |> ignore
  self.told.set(self.told.untracked() + 1)
}

///|
/// Whether line `key` is on its way out of the list (gone from it, its room closing), followed.
fn RowsMotion::going_now(self : RowsMotion, key : String) -> Bool {
  self.told.get() |> ignore
  self.going.contains(key)
}

///|
/// The chat of row `key` gone (or the copy of one gone ahead of others), as it was; None for a row in the list.
fn RowsMotion::gone_item(self : RowsMotion, key : String) -> ChatItem? {
  match @signals.untracked(fn() { self.going.get(key) }) {
    Some((item, _)) => item
    None => None
  }
}

///|
/// Line `key`'s (its key as it is now) node `line` coming or going (ListRows::enter, leave): its room opening or closing from its cause's
/// moment over row_size_ms, what it holds in the middle of it, as big as it is open and faded in from row_gone_at, cut
/// softly at both ends. A row archived from it (its tray there: undo_lines) is a recess the list closes over: its room
/// closes as a row's does, what it holds neither shrunk nor faded, cut hard at the room's foot (kept at its top by
/// what holds it: row_line). How open it is (None: neither coming nor going).
fn RowsMotion::line_node(self : RowsMotion, line : @view.View, key : () -> String) -> () -> Double? {
  let way = @sf.EdgeWay::new(1.0)
  let state = fn() {
    self.told.get() |> ignore
    self.moving.get(key())
  }
  line.reacts(state, fn(m) {
    match m {
      Some((comes, _)) =>
        way.go_from(line, if comes { 0.0 } else { 1.0 }, if comes { 1.0 } else { 0.0 }, @motion.tween(row_size_ms, ease=Out))
      None => ()
    }
  })
  let open = fn() {
    match state() {
      Some(_) => Some(dmax(0.0, dmin(1.0, way.shown(line))))
      None => None
    }
  }
  let recess = fn() { self.undo_line(key()) }
  line
  .opens(By(open))
  .cuts_softly(By(fn() { open() is Some(_) && !recess() }))
  .clips(By(fn() { open() is Some(_) && recess() }))
  .alpha(By(fn() {
    match open() {
      Some(p) if !recess() => dmax(0.0, (p - @ui.row_gone_at) / (1.0 - @ui.row_gone_at))
      _ => 1.0
    }
  }))
  .scale(By(fn() { if recess() { 1.0 } else { open().unwrap_or(1.0) } }))
  |> ignore
  open
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
/// Which of `was` (the rows' places before, in their order now) are among the most still in the order they had: a
/// longest increasing run of them (in_order_most's). The others are the fewest that moved.
fn kept_in_order(was : Array[Int]) -> Array[Bool] {
  let n = was.length()
  let ends : Array[Int] = []
  let back = Array::make(n, -1)
  for i in 0..<n {
    let mut lo = 0
    let mut hi = ends.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if was[ends[mid]] < was[i] {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo > 0 {
      back[i] = ends[lo - 1]
    }
    if lo == ends.length() {
      ends.push(i)
    } else {
      ends[lo] = i
    }
  }
  let kept = Array::make(n, false)
  let mut i = if ends.is_empty() { -1 } else { ends[ends.length() - 1] }
  while i >= 0 {
    kept[i] = true
    i = back[i]
  }
  kept
}

///|
/// How long a row's coming or going takes (mbui's ListRows: row_size_ms).
let row_size_ms : Double = @ui.row_size_ms

