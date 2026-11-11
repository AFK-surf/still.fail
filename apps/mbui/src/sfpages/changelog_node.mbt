// 更新日志 made once as nodes (ChangelogPage; the narrow app's ChangelogScreen: page_node, laid out by the width its
// frame gives it): the core's `changelog`, a tab a part (the choice only where there is more than one), by day, each
// change's lines with their kind before them (narrow: a small tinted label in its words, one paragraph of pieces; wide:
// a label in a room of its own before them), its version, what is not out yet; while it is read the first time, two
// made-up days in their bones; opened, what the last update brought is read (`changelog.seen`), once each news.
//
// The core is asked for the tab in view alone (`part`, none while none is chosen) and its first changes (`limit`: a
// page, `changelog_page`), a page more as the list comes near the last of them while the core says it has more
// (`more`); the limits are the page's own, gone with it. A tab chosen, or a page more, shows what was shown till the
// core answers it (no bones: those only while the page has nothing at all). Each day's heading is a block of the
// page's list and each change one under it (a piece of the day's card: @sf.day_change_node), so the list makes only
// what shows (a day of the beta's had 62 changes, made whole in the frame it came into view, 2026-11-11).

///|
/// How many of a tab's changes are asked of the core at first, and how many more each time its list comes near the
/// last of them (the core's `PAGE`, client/core-ts/src/changelog.ts).
let changelog_page : Int = 30

///|
/// 更新日志 made once in node `v`, as wide as `width` says (narrow where none is given).
pub fn changelog_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  // (how many changes of each tab are asked, by its part ("" none chosen): the page's own, a page at first)
  let limits : @signals.Signal[Map[String, Int]] = @signals.signal({})
  let limit_of = fn(part : String) { limits.get().get(part).unwrap_or(changelog_page) }
  let asked_of = fn(part : String, limit : Int) -> Map[String, Json] {
    let p : Map[String, Json] = { "limit": Json::number(limit.to_double()) }
    if part != "" {
      p["part"] = Json::string(part)
    }
    p
  }
  // (as it is asked now: the tab chosen, as many as asked of it)
  let asked = fn() {
    let part = changelog_part.get()
    asked_of(part, limit_of(part))
  }
  let read = fn(p : Map[String, Json]) { (core.topic)("changelog", p).get() }
  let answered = fn(r : @settings.Read) { r.value is Some(_) || r.error is Some(_) }
  // (what was last shown that the core had answered: shown while what is asked now has not come, as chats_shown keeps
  // a list's rows for a page more; let go of, no longer read, once it has)
  let showing : @signals.Signal[Map[String, Json]?] = @signals.signal(None)
  let shown = fn() {
    let a = asked()
    if answered(read(a)) {
      return a
    }
    match showing.get() {
      Some(s) => s
      None => a
    }
  }
  v.reacts(
    fn() {
      let a = asked()
      if answered(read(a)) {
        Json::object(a).stringify()
      } else {
        ""
      }
    },
    fn(now) {
      if now != "" {
        showing.set(Some(@signals.untracked(asked)))
      }
    },
  )
  let topic = fn() { read(shown()) }
  let value = fn() { topic().value }
  // opened: what the update brought is read, once each news (as it is said)
  v.reacts(
    fn() {
      match field(value(), "news") {
        Some(Null) | None => ""
        Some(n) => n.stringify()
      }
    },
    fn(news) {
      if news != "" && news != changelog_seen.val {
        changelog_seen.val = news
        (core.call)("changelog.seen", obj([]), @sfbase.answer_unread)
      }
    },
  )
  let tabs = fn() { items(value(), "tabs") }
  let index_of = fn(part : String) { tabs().search_by(fn(x) { text(Some(x), "part") == part }).unwrap_or(0) }
  // (the tab chosen, at once; the one whose changes show, the one the value shown was asked for: the first where it
  // named none, or one there is not, as the core has it)
  let at = fn() { index_of(changelog_part.get()) }
  let shown_at = fn() {
    match shown().get("part") {
      Some(String(p)) => index_of(p)
      _ => 0
    }
  }
  let days = fn() {
    match tabs().get(shown_at()) {
      Some(x) => items(Some(x), "days")
      None => []
    }
  }
  // (each day by which it is, the core's (`day`: where the device is, whatever else it lists or the list leaves off),
  // each change by its version (a change the same change whatever is said of it); one made up by where it is. Worked
  // out once for each value: what each block of them is, and where on its day's card a change is)
  let listed : @signals.Computed[(Array[String], Map[String, ListedPart])] = @signals.computed(fn(_) {
    let keys = []
    let parts : Map[String, ListedPart] = Map([])
    for i, d in days() {
      let dk = day_key(d, i)
      keys.push("day/" + dk)
      parts["day/" + dk] = DayHeading(d)
      let entries = items(Some(d), "entries")
      for j, e in entries {
        let ck = "change/" + change_key(e, dk, j)
        keys.push(ck)
        parts[ck] = DayChange(e, @sf.card_piece_of(j, entries.length()))
      }
    }
    (keys, parts)
  })
  let blocks = fn() {
    let out = []
    if tabs().length() > 1 {
      out.push("tabs")
    }
    let v = value()
    if v is None || flag(v, "loading") {
      out.push("waiting")
    } else if has(v, "error") {
      out.push("error")
    } else if days().length() == 0 {
      out.push("empty")
    } else {
      out.append(listed.get().0)
    }
    out
  }
  let lead = fn() {
    let v = value()
    if has(v, "build") && !(field(v, "build") is Some(Null)) {
      @sf.t("web-pages.changelog.build", args=[("build", count(v, "build").to_string())])
    } else {
      ""
    }
  }
  // (near the last change it holds while the core has more of the tab: a page more of it asked, once for what shows,
  // as sfbase's chats_grow tells a chats' list its window once for the rows it holds)
  let more = fn() { count(value(), "more") > 0 }
  let ask_more = fn() {
    let part = @signals.untracked(fn() { changelog_part.get() })
    let limit = @signals.untracked(fn() { limit_of(part) })
    if Json::object(@signals.untracked(shown)) == Json::object(asked_of(part, limit)) {
      let next = @signals.untracked(fn() { limits.get() }).copy()
      next[part] = limit + changelog_page
      limits.set(next)
    }
  }
  // (a page a part: its list its own, as the old view's list was by the part in view (its key, "changelog/<at>"), what
  // of it is picked none of another part's)
  // (as tall as where it is, never as what it holds: page_node's own, a part's page in it)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (where each part's list was scrolled to, kept while the page is: each as it was left, as the old view's lists by
  // their keys were till the page left the stack)
  let scrolls : Map[String, @view.Scroll] = Map([])
  // (the part whose changes show as it is, the first where none is said: what its page and where it was scrolled to
  // are by; another chosen, its page once the core has answered it)
  v.pick(fn() { text(tabs().get(shown_at()), "part") }, fn(pv, part) {
    let scroll = match scrolls.get(part) {
      Some(s) => s
      None => {
        let s = @view.Scroll::list()
        scrolls[part] = s
        s
      }
    }
    @sf.page_node(
      pv,
      fn() { @sf.t("web-pages.settings.nav.changelog") },
      on_back~,
      frame~,
      said?,
      width?,
      lead~,
      scroll~,
      near_foot=(1.5, more, ask_more),
      blocks,
      fn(b, key) {
        match key {
          "tabs" =>
            @sf.page_choice_node(
              b,
              fn() { tabs().map(fn(x) { text(Some(x), "label") }) },
              at,
              fn(k) {
                match @signals.untracked(tabs).get(k) {
                  Some(x) => changelog_part.set(text(Some(x), "part"))
                  None => ()
                }
              },
              item_w=cl_tab_w,
            )
          "waiting" =>
            @sf.waiting_node(b, fn(s) { changelog_sample_node(s) }, error=fn() {
              match topic().error {
                Some(e) => @settings.error_text(e)
                None => ""
              }
            })
          "error" => @sf.page_said_node(b, fn() { text(value(), "error") }, bad=true)
          "empty" => @sf.page_said_node(b, fn() { @sf.t("web-pages.changelog.empty") })
          _ => {
            let part = fn() { listed.get().1.get(key) }
            if key.has_prefix("day/") {
              @sf.day_heading_node(b, fn() {
                match part() {
                  Some(DayHeading(d)) => text(Some(d), "label")
                  _ => ""
                }
              })
            } else {
              // (as tall as its block, its piece of the card in it as tall: card_piece_node)
              b.grow(Is(1.0)) |> ignore
              let e = fn() {
                match part() {
                  Some(DayChange(e, _)) => Some(e)
                  _ => None
                }
              }
              let piece = fn() {
                match part() {
                  Some(DayChange(_, p)) => p
                  _ => @sf.CardPiece::CardWhole
                }
              }
              change_node(b, e, piece)
            }
          }
        }
      },
    )
  })
}

///|
/// What a block of the changelog's list is: a day's heading, or one of its changes and which piece of the day's card
/// it is.
priv enum ListedPart {
  DayHeading(Json)
  DayChange(Json, @sf.CardPiece)
}

///|
/// Which day `d` (the `i`th listed) is: the core's (`day`: which day it is where the device is, the same whatever else
/// that day lists or the list leaves off; its label only says it); where it is where it has none (one made up).
fn day_key(d : Json, i : Int) -> String {
  match field(Some(d), "day") {
    Some(Number(_, ..)) => "d" + count(Some(d), "day").to_string()
    _ => "at" + i.to_string()
  }
}

///|
/// Which change `e` (the `j`th of day `dk`) is: its version (the core's: a change the same change whatever is said of
/// it); where it is on its day where it has none (one made up).
fn change_key(e : Json, dk : String, j : Int) -> String {
  match field(Some(e), "version") {
    Some(Number(_, ..)) => "v" + count(Some(e), "version").to_string()
    _ => dk + "/at" + j.to_string()
  }
}

///|
/// The changes to come while they are read (two made-up days in their bones), as the list makes them: each day's
/// heading, its changes the pieces of its card.
fn changelog_sample_node(s : @view.View) -> Unit {
  for d, lines in changelog_sample_lines {
    @sf.day_heading_node(s, fn() { @sf.sample_words(if d == 0 { 2 } else { 5 }) })
    for i, n in lines {
      let e : Json = {
        "lines": [{ "label": Json::string(@sf.sample_words(2)), "text": Json::string(@sf.sample_words(n)) }],
        "versionName": Json::string(@sf.sample_words(5)),
      }
      let piece = @sf.card_piece_of(i, lines.length())
      change_node(s, fn() { Some(e) }, fn() { piece })
    }
  }
}

///|
/// One change of a day (@sf.day_change_node), `e` as it is now, the piece of its day's card `piece` says: its lines,
/// each led by its kind (the accent's for something new), its version, what is not out yet (in the accent where an
/// update would bring it).
fn change_node(parent : @view.View, e : () -> Json?, piece : () -> @sf.CardPiece) -> Unit {
  @sf.day_change_node(
    parent,
    piece,
    fn() {
      items(e(), "lines").map(fn(l) {
        let lv = Some(l)
        let line : @sf.ChangeLine = { label: text(lv, "label"), text: text(lv, "text"), fresh: text(lv, "kind") == "new" }
        line
      })
    },
    fn() { text(e(), "versionName") },
    fn() { text(e(), "note") },
    fn() { field(e(), "has") is Some(False) },
  )
}
