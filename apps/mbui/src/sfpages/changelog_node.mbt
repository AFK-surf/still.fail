// 更新日志 made once as nodes (changelog_page's: page_node, laid out by the width its frame gives it): the core's
// `changelog`, a tab a part (the choice only where there is more than one), by day, each change's lines with their
// kind before them (narrow: a small tinted label in its words, one paragraph of pieces; wide: a label in a room of its
// own before them), its version, what is not out yet; while it is read the first time, two made-up days in their
// bones; opened, what the last update brought is read (`changelog.seen`), once each news.

///|
/// 更新日志 made once in node `v` (changelog_page's), as wide as `width` says (narrow where none is given).
pub fn changelog_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let topic = fn() { (core.topic)("changelog", Map([])) }
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
        (core.call)("changelog.seen", obj([]), fn(_) {  })
      }
    },
  )
  let tabs = fn() { items(value(), "tabs") }
  let at = fn() {
    let part = changelog_part.get()
    tabs().search_by(fn(x) { text(Some(x), "part") == part }).unwrap_or(0)
  }
  let days = fn() {
    match tabs().get(at()) {
      Some(x) => items(Some(x), "days")
      None => []
    }
  }
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
      // (each day by which it is, the core's (`day`: where the device is, whatever else it lists or the list leaves
      // off); one made up by where it is)
      for i, d in days() {
        out.push("day/" + day_key(d, i))
      }
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
  // (a page a part: its list its own, as the old view's list was by the part in view (its key, "changelog/<at>"), what
  // of it is picked none of another part's)
  // (as tall as where it is, never as what it holds: page_node's own, a part's page in it)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (where each part's list was scrolled to, kept while the page is: each as it was left, as the old view's lists by
  // their keys were till the page left the stack)
  let scrolls : Map[String, @view.Scroll] = {}
  // (the part in view as it is, the first where none is said: what its page and where it was scrolled to are by)
  v.pick(fn() { text(tabs().get(at()), "part") }, fn(pv, part) {
    let scroll = match scrolls.get(part) {
      Some(s) => s
      None => {
        let s = @view.Scroll::list()
        scrolls[part] = s
        s
      }
    }
    @sf.page_node(pv, fn() { @sf.t("web-pages.settings.nav.changelog") }, on_back~, frame~, said?, width?, lead~, scroll~, blocks, fn(
      b,
      key,
    ) {
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
          let k = key.view(start_offset=4).to_string()
          day_node(b, fn() {
            let all = days()
            let mut found = Json::null()
            for i, d in all {
              if day_key(d, i) == k {
                found = d
                break
              }
            }
            found
          })
        }
      }
    })
  })
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
/// A day of the changelog as nodes (day_blocks'), `day` as it is now: its label over its changes (@sf.day_group_node),
/// each by its version.
fn day_node(b : @view.View, day : () -> Json) -> Unit {
  // (each change by its version (the core's: a change the same change whatever is said of it); one made up while the
  // changes are read, by where it is)
  let entries_keyed = fn() {
    items(Some(day()), "entries").mapi(fn(i, e) {
      let v = field(Some(e), "version")
      (if v is Some(Number(_, ..)) { "v" + count(Some(e), "version").to_string() } else { "at" + i.to_string() }, e)
    })
  }
  @sf.day_group_node(b, fn() { text(Some(day()), "label") }, fn(g) {
    g.each(entries_keyed, fn(e) { e.0 }, fn(row, e) { change_node(row, fn() { Some(e.get().1) }) })
  })
}

///|
/// The changes to come while they are read (changelog_sample's), as day_node makes them.
fn changelog_sample_node(s : @view.View) -> Unit {
  for d, lines in changelog_sample_lines {
    let entries = lines.map(fn(n) {
      Json::object({
        "lines": [{ "label": Json::string(@sf.sample_words(2)), "text": Json::string(@sf.sample_words(n)) }],
        "versionName": Json::string(@sf.sample_words(5)),
      })
    })
    let day : Json = { "label": Json::string(@sf.sample_words(if d == 0 { 2 } else { 5 })), "entries": Json::array(entries) }
    day_node(s, fn() { day })
  }
}

///|
/// One change of a day (@sf.change_node), `e` as it is now: its lines, each led by its kind (the accent's for something
/// new), its version, what is not out yet (in the accent where an update would bring it).
fn change_node(parent : @view.View, e : () -> Json?) -> Unit {
  @sf.change_node(
    parent,
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
