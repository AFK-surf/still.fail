// 已归档 as one of the sidebar's lists made once (archive_pane's, as nodes of the window's tree): what to look for, its
// days, an archived chat a row each (put back or deleted while pointed at, right clicked or held its menu), pressed its
// chat beside the list; opened, the newest of them open beside it; near its end, the next ones read.

///|
/// What the archive's list is looking for, and how many of it it reads (archive_side's, followed: the list made once
/// reads them; archive_side keeps them for what reads it as it is, keys.mbt).
// kept across runs: put back as a run begins (on_reset), with archive_side (wide_reset)
let archive_q : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
// kept across runs: put back as a run begins (on_reset)
let archive_limit : @signals.Signal[Int] = @signals.signal(archive_side_page, same=fn(a, b) { a == b })

///|
fn init {
  @ui.on_reset(fn() {
    archive_q.set("")
    archive_limit.set(archive_side_page)
  })
}

///|
/// 已归档 as the sidebar's list in node `p` (all of its lane), for the workspace in view, under the band's room
/// (`band`: its height as the block stands now): its lines read as the archive is (the core's `archive` for what is looked for, as many as read so far), made as they come to show.
fn archive_pane_node(
  p : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  band : () -> Double,
) -> Unit {
  p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  p.pick(fn() { workspace().map(fn(w) { w.id }) }, fn(v, id) {
    guard id is Some(id) else { return }
    archive_list_node(v, src, tips, id, band)
  })
}

///|
/// The archive's list of workspace `id` in `v`, under the band's room (`band`, as it stands now).
fn archive_list_node(v : @view.View, src : Source, tips : @sf.TipLayer, id : String, band : () -> Double) -> Unit {
  let topic = fn() {
    let params : Map[String, Json] = {
      "scope": Json::string(id),
      "limit": Json::number(archive_limit.get().to_double()),
    }
    if archive_q.get() != "" {
      params["q"] = Json::string(archive_q.get())
    }
    (src.topic)("archive", params)
  }
  // (what was read last, kept while the next is read: archive_side.last, what the keys read too)
  let last : @signals.Signal[Json?] = @signals.signal(archive_side.last)
  v.reacts(fn() { topic().value }, fn(value) {
    if value is Some(_) {
      archive_side.last = value
      last.set(value)
    }
  })
  let days = fn() { items(last.get(), "days") }
  let rows : Ref[Map[String, Json]] = Ref({})
  let errors_at : Ref[Map[String, Int]] = Ref({})
  let lines = fn() {
    let view = last.get()
    let out = ["top", "search"]
    let made : Map[String, Json] = {}
    if view is None {
      out.push(if topic().error is Some(_) { "fail" } else { "wait" })
    } else {
      let errs : Map[String, Int] = {}
      for i, _ in items(view, "errors") {
        errs["error/" + i.to_string()] = i
        out.push("error/" + i.to_string())
      }
      errors_at.val = errs
      if days().length() == 0 && text(view, "note") != "" {
        out.push("said")
      }
      for i, d in days() {
        out.push("h/" + i.to_string() + "/" + text(Some(d), "label"))
        for it in items(Some(d), "items") {
          let k = "r/" + text(Some(it), "station") + "/" + text(Some(it), "session")
          made[k] = it
          out.push(k)
        }
      }
    }
    out.push("foot")
    rows.val = made
    out
  }
  // opened: its newest chat beside it (ArchivePage), once
  v.reacts(
    fn() {
      if app.nav.top() == Archived && archive_q.get() == "" {
        match days().get(0) {
          Some(d) => items(Some(d), "items").get(0).map(fn(it) { Some(it) })
          None => if last.get() is Some(_) { Some(None) } else { None }
        }
      } else {
        None
      }
    },
    fn(first) {
      if archive_side.landed {
        return
      }
      match first {
        Some(Some(it)) => {
          archive_side.landed = true
          archive_open(it)
        }
        Some(None) => archive_side.landed = true
        None => ()
      }
    },
  )
  // near its end, the next ones (as it comes to show its last lines)
  let shown : @signals.Signal[Array[String]] = @signals.signal([])
  v.reacts(fn() { shown.get() }, fn(seen) {
    let all = @signals.untracked(lines)
    match seen.last() {
      Some(k) => {
        let at = all.search(k).unwrap_or(0)
        if flag(@signals.untracked(fn() { last.get() }), "more") && at >= all.length() - 12 &&
          @signals.untracked(topic).value is Some(_) {
          archive_limit.set(@signals.untracked(fn() { archive_limit.get() }) + archive_side_page)
          archive_side.limit = @signals.untracked(fn() { archive_limit.get() })
        }
      }
      None => ()
    }
  })
  let field = @ui.Field::new(text=archive_side.q)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  v.scrolls_window(@view.Scroll::list(), lines, est=54.0, bar=@ui.tree_scroll_bar(), shown~, fn(b, k) {
    b.box(fn(line) {
      @sf.style_node(line, fn() { @sf.list_line(Side) })
      match k {
        // (the band's room over it and its 4, as the band stands now: `band`, read again as the block is said to stand)
        "top" => line.height(By(fn() { Some(band() + 4.0) })) |> ignore
        "search" => archive_search_node(line, field, fn() {
            let all = lines()
            all.length() > 2 && (all[2] == "wait" || all[2].has_prefix("r/"))
          })
        "fail" =>
          side_said_node(line, fn() {
            match topic().error {
              Some(e) => text(Some(e), "message")
              None => ""
            }
          }, true)
        "wait" => @sf.waiting_node(line, fn(s) { archive_sample_node(s, tips) })
        "said" => side_said_node(line, fn() { text(last.get(), "note") }, false)
        "foot" => line.height(Is(Some(@sf.list_foot_in(Side)))) |> ignore
        _ if k.has_prefix("error/") => {
          let i = errors_at.val.get(k).unwrap_or(0)
          side_said_node(line, fn() { text(items(last.get(), "errors").get(i), "text") }, true)
        }
        _ if k.has_prefix("h/") => {
          let rest = k.view(start_offset=2).to_owned()
          let label = match rest.find("/") {
            Some(j) => rest.view(start_offset=j + 1).to_owned()
            None => rest
          }
          @sf.list_heading_node(line, fn() { label }, Side)
        }
        _ => {
          guard rows.val.get(k) is Some(first) else { return }
          let held : Ref[Json] = Ref(first)
          let item = fn() {
            lines() |> ignore
            match rows.val.get(k) {
              Some(it) => {
                held.val = it
                it
              }
              None => held.val
            }
          }
          let more = fn() {
            let all = lines()
            match all.search(k) {
              Some(i) => i + 1 < all.length() && all[i + 1].has_prefix("r/")
              None => false
            }
          }
          archive_row_node(line, src, tips, item, more)
        }
      }
    })
    |> ignore
  })
  |> ignore
  // what it looks for, as it is typed (each anew from its first page)
  v.reacts(fn() { field.text().trim(chars=" \t\n").to_string() }, fn(q) {
    if q != @signals.untracked(fn() { archive_q.get() }) {
      archive_side.q = q
      archive_side.limit = archive_side_page
      archive_q.set(q)
      archive_limit.set(archive_side_page)
    }
  })
}

///|
/// Looking for one (archive_search_side's) in `line`: a field at the list's top on the pointer's ground, as what stands
/// over a sidebar's list is (the theme's band's: its height, its words' room, its mark, its words); 4 under it where
/// rows or their bones come next (`gap`).
fn archive_search_node(line : @view.View, field : @ui.Field, gap : () -> Bool) -> Unit {
  line.box(fn(o) {
    // (4 under it only where rows or their bones come next, as it is now: arch_field_box's pb, else arch_field_alone)
    o.width_share(Is(1.0)).padding(By(fn() { (0.0, 0.0, 0.0, if gap() { @ui.Space::px(S1) } else { 0.0 }) })) |> ignore
    o.box(fn(f) {
      @sf.style_node(f, fn() {
        let l = @sf.theme().chat_list
        arch_field.then(@ui.style(h=Fixed(l.band_h), px=@sf.room_of(l.band_pad)))
      })
      @sf.icon_node(f, "search", @sf.theme().chat_list.band_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      @ui.field(
        f,
        field,
        placeholder=@sf.t("web-pages.archive.search"),
        max_lines=1,
        size_by=fn() { @ui.tree_theme().text_size(Ui).0 },
        line_by=fn() { @ui.tree_theme().text_size(Ui).1 },
        colors_by=fn() {
          let p = @sf.theme().p
          (p.text, p.subtle, p.accent)
        },
      )
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .shrink(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a list says in place of its rows (side_said's) in `line`: muted, or in red what went wrong (`bad`).
fn side_said_node(line : @view.View, words : () -> String, bad : Bool) -> Unit {
  line.box(fn(b) {
    @sf.style_node(b, fn() { side_said_box })
    @sf.words_node(b, words, fn() { if bad { side_words_bad } else { side_words } }) |> ignore
  })
  |> ignore
}

///|
/// The archive's rows to come while it is read (archive_sample's), as archive_row_node makes them.
fn archive_sample_node(s : @view.View, tips : @sf.TipLayer) -> Unit {
  let rows = [(7, 13), (10, 9), (6, 15), (12, 11), (8, 14), (9, 10)]
  for i, n in rows {
    let it : Json = {
      "station": "sample",
      "session": Json::string("sample" + i.to_string()),
      "title": Json::string(@sf.sample_words(n.0)),
      "last": Json::string(@sf.sample_words(n.1)),
      "clock": Json::string(@sf.sample_words(3)),
    }
    archive_row_node(s, @sfbase.sample_source, tips, fn() { it }, fn() { i + 1 < rows.length() })
  }
}

///|
/// An archived chat's row (archive_side_row's) in `parent`, `item()` as it is now: its title (its station's mark at its
/// end, where it was on hover), the last thing said under it, when it was archived there while pointed at (how, on
/// hover); over the title's end then, putting it back and deleting it (one under way: turning). Pressed, its chat
/// beside the list; right clicked, or held long by a finger, its menu. `more`: another row under it.
fn archive_row_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  item : () -> Json,
  more : () -> Bool,
) -> Unit {
  let v = fn() { Some(item()) }
  let station = fn() { text(v(), "station") }
  let session = fn() { text(v(), "session") }
  let on = fn() {
    match app.nav.top() {
      Chat(r) => r.station == station() && r.session == session()
      _ => false
    }
  }
  let busy = fn() { archive_doing(src, station(), session()) }
  parent.box(fn(slot) {
    @sf.style_node(slot, fn() { if more() { @sf.list_more(Side) } else { @sfpages.row_last } })
    slot.box(fn(row) {
      // its 恢复 and 删除 while pointed at (shown only under the hand), or one under way; where the native input is
      // touch they are held for (its menu): no keys drawn too small for a finger
      let over = fn() { busy() || (!@sf.more_held() && @sf.lit_in_node(row)) }
      let l = fn() { @sf.theme().chat_list }
      @sf.list_row_node(
        row,
        Side,
        high=true,
        end_room=fn() { if over() { @sf.row_keys_room(if flag(v(), "deletable") { 2 } else { 1 }) } else { 0.0 } },
        fn(h) {
          h.box(fn(w) {
            w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            @sf.words_node(w, fn() { text(v(), "title") }, fn() { l().title }) |> ignore
          })
          |> ignore
          h.show(fn() { @sf.has_station_mark(text(v(), "stationEmoji"), text(v(), "stationIcon")) }, fn(k) {
            k.box(fn(s) {
              @sf.style_node(s, fn() { @sfpages.kind_slot }, in_row=true)
              s.says(By(fn() { Some(@view.said(Image, label=text(v(), "place"))) })) |> ignore
              @sf.station_mark_node(
                s,
                fn() { text(v(), "stationEmoji") },
                fn() { text(v(), "stationIcon") },
                @sfpages.kind_mark_of(@signals.untracked(fn() { text(v(), "stationIcon") })),
                fn() { @sf.theme().p.muted },
                fn() { 0 },
              )
              @sf.tip_node(tips, s, fn() { text(v(), "place") }, within=true) |> ignore
            })
            |> ignore
          })
        },
        fn(u) {
          @sf.list_row_line_node(u, fn(m) {
            m.box(fn(w) {
              w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
              @sf.words_node(w, fn() { text(v(), "last") }, fn() { l().last }) |> ignore
            })
            |> ignore
            // (its clock while pointed at; always to a finger, which hovers over nothing; how it was archived over it)
            m.show(fn() { @sf.pointed_or_finger_node(row) }, fn(c) {
              @sf.words_node(c, fn() { text(v(), "clock") }, fn() { arch_clock }) |> ignore
              @sf.tip_node(tips, c, fn() { text(v(), "how") }, within=true) |> ignore
            })
          })
        },
      )
      // (its ground the pointer's in and out, the selected one's while its chat is beside the list: said after the
      // row's own, which it is in place of)
      @sf.nav_ground_node(row, on)
      // pressed: its chat beside the list; right clicked, its menu at the pointer; held by a finger, from the row
      row.says(By(fn() { Some(@view.said(Link, label=text(v(), "title"))) })).on_menu(fn(m) {
        if !@signals.untracked(busy) {
          archive_menu_from(src, @signals.untracked(item), @sf.at_point(m.wx, m.wy))
        }
      })
      |> ignore
      @sf.presses_held_node(
        row,
        fn() {
          archive_open(@signals.untracked(item))
          @sfbase.show_chosen()
        },
        @ui.long_press_ms,
        fn(_) {
          if !@sf.pointer_rests() && !@signals.untracked(busy) {
            let (x, y, w, h) = row.placed_window_now()
            archive_menu_from(src, @signals.untracked(item), At(x, y, w, h))
          }
        },
      )
      // 恢复 and 删除 at its top right while pointed at (or one under way), concentric with its corner
      @sf.row_corner_keys_node(row, over, fn(keys) {
        let title = fn() { text(v(), "title") }
        @sf.row_key_node(
          keys,
          tips,
          "retry",
          arch_icon,
          fn(lit) { if lit { @sf.theme().p.text } else { @sf.theme().p.muted } },
          fn() { @sf.t("web-pages.archive.restoreNamed", args=[("title", title())]) },
          fn() { @sf.t("web-pages.archive.restore") },
          fn() { archive_restore(src, @signals.untracked(item)) },
          busy~,
          spin=arch_spin,
        )
        |> ignore
        keys.show(fn() { flag(v(), "deletable") }, fn(d) {
          @sf.row_key_node(
            d,
            tips,
            "trash",
            arch_icon,
            fn(lit) { if lit { @sf.theme().p.red } else { @sf.theme().p.muted } },
            fn() { @sf.t("web-pages.archive.deleteNamed", args=[("title", title())]) },
            fn() { @sf.t("common.delete") },
            fn() { archive_delete(src, @signals.untracked(item)) },
            busy~,
          )
          |> ignore
        })
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// An archived chat's menu (archive_menu's) from `from`: 恢复 and, where it can be, 删除.
fn archive_menu_from(src : Source, it : Json, from : @sf.Beside) -> Unit {
  let items : Array[@sf.MenuItem?] = [
    Some(@sf.menu_item_of(@sf.t("web-pages.archive.restore"), icon="retry", fn() { archive_restore(src, it) })),
  ]
  if flag(Some(it), "deletable") {
    items.push(Some(@sf.menu_item_of(@sf.t("common.delete"), icon="trash", danger=true, fn() { archive_delete(src, it) })))
  }
  @sf.menu(items, from~, title=text(Some(it), "title"))
}
