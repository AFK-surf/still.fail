// The shared folder picker's body, made once as nodes of the window's tree. The same state and requests are used by
// the favorite dialog and by a preset's embedded picker (drive_dialogs.mbt).

///|
/// The stations offered before choosing a folder, in the same order as the caller gave them.
fn picker_stations_node(parent : @view.View, stations : Array[DvStation], pick : (DvStation) -> Unit) -> Unit {
  parent.box(fn(list) {
    @sf.style_node(list, fn() { roots_list })
    for s in stations {
      list.box(fn(row) {
        @sf.style_node(row, fn() { pick_row })
        row.ground(By(fn() { if @sf.lit_node(row) { @ui.tree_theme().color(Hover) } else { 0L } }))
        .says(By(fn() { Some(@view.said(Button, label=s.name)) })) |> ignore
        @sf.presses_node(row, fn() { pick(s) })
        if @sf.has_station_mark(s.emoji, s.icon) {
          @sf.station_mark_node(row, fn() { s.emoji }, fn() { s.icon }, pick_icon, fn() { @sf.theme().p.muted },
            fn() { @ui.current().page_stint() })
        } else {
          @sf.icon_node(row, "server", pick_icon, By(fn() { @sf.theme().p.muted })) |> ignore
        }
        @sf.words_node(row, fn() { s.name }, fn() { pick_name }) |> ignore
        if !s.online {
          @sf.words_node(row, fn() { @sf.t("web-pages.stations.offline") }, fn() { pick_meta }) |> ignore
        }
      }) |> ignore
    }
  }) |> ignore
}

///|
/// The picker opened for `station`, in `parent`. Call folder_browse_open before making it; on a station change open
/// the new station and make its body anew. The parent lends its narrow or wide arrangement. Let go with
/// folder_browse_close when its containing panel is left.
pub fn folder_browse_node(parent : @view.View, src : Source, station : String) -> Unit {
  parent.show(fn() { dialogs.picking.get() == station }, fn(body) {
    if @signals.untracked(fn() {
        dialogs.value.get() is None && dialogs.error.get() == "" && !dialogs.denied.get() &&
        dialogs.last.get() is None && !dialogs.asking.get()
      }) {
      picker_go(@ui.current(), src, station, @signals.untracked(fn() { dialogs.at.get() }))
    }
    picker_body_node(body, src, station)
  })
}

///|
fn picker_folders(h : Json?, key : String) -> Array[(String, String, Bool, Bool)] {
  items(h, key).map(fn(x) {
    let x = Some(x)
    (text(x, "name"), text(x, "path"), flag(x, "unreadable"), flag(x, "disk"))
  })
}

///|
fn picker_body_node(body : @view.View, src : Source, station : String) -> Unit {
  let narrow = @sf.look_node(body) is Narrow
  // Ctx::list keyed the folder list by path, retaining its scroll when that folder was revisited.
  let folder_scrolls : Map[String, @view.Scroll] = {}
  let way = fn() {
    match dialogs.last.get() {
      Some(h) => way_of(h)
      None => []
    }
  }
  let places = fn() { picker_folders(dialogs.last.get(), "places") }
  let here = fn() {
    match dialogs.value.get() {
      Some(v) => text(Some(v), "path")
      None => match way().last() { Some((_, p)) => p; None => "" }
    }
  }
  let wanted = fn() { dialogs.filter.text().trim(chars=" ").to_owned() }
  let shown = fn() {
    let value = dialogs.value.get()
    let path = text(value, "path")
    let home = text(value, "home")
    let q = wanted()
    let ps = places()
    picker_folders(value, "entries").filter(fn(e) {
      (q == "" || e.0.to_lower().contains(q.to_lower())) &&
      !(path == home && q == "" && ps.iter().any(fn(p) { p.1 == e.1 }))
    })
  }
  body.box(fn(path) {
    @sf.style_node(path, fn() { if narrow { picker_path_narrow } else { picker_path } })
    @sf.way_line_node(path, fn() { way().map(fn(w) { w.0 }) }, picker_way, fn(i) {
      match @signals.untracked(way).get(i) {
        Some((_, p)) => picker_go(@ui.current(), src, station, Some(p))
        None => ()
      }
    }, in_row=!narrow) |> ignore
    path.show(fn() { !dialogs.denied.get() && dialogs.error.get() == "" }, fn(f) {
      @sf.style_node(f, fn() { if narrow { picker_filter_narrow } else { picker_filter } }, in_row=!narrow)
      @sf.input_node(f, dialogs.filter, placeholder_by=fn() { @sf.t("web-pages.drive.pickFilter") }) |> ignore
    })
  }) |> ignore
  body.box(fn(box) {
    @sf.style_node(box, fn() { if narrow { picker_box_narrow } else { picker_box } })
    box.show(fn() { !places().is_empty() }, fn(side) {
      @sf.style_node(side, fn() { if narrow { picker_places_narrow } else { picker_places } }, in_row=!narrow)
      @sf.words_node(side, fn() { @sf.t("web-pages.drive.places") }, fn() { picker_head }) |> ignore
      side.box(fn(list) {
        if narrow {
          list.height(By(fn() { Some(dmin(places().length().to_double() * pick_row_h, picker_places_most)) })) |> ignore
        } else {
          list.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
        }
        list.scrolls_window(@view.Scroll::list(), fn() { places().mapi(fn(i, _) { i }) }, est=pick_row_h,
          slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(row, i) {
            let place = fn() { places().get(i).unwrap_or(("", "", false, false)) }
            picker_row_node(row, place, fn() { place().1 == here() }, fn() {
              picker_go(@ui.current(), src, station, Some(@signals.untracked(place).1))
            })
          }) |> ignore
      }) |> ignore
    })
    box.box(fn(list) {
      @sf.style_node(list, fn() { picker_list }, in_row=!narrow)
      list.min_height(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      list.show(fn() { dialogs.denied.get() || dialogs.error.get() != "" }, fn(shut) {
        @sf.style_node(shut, fn() { picker_shut })
        @sf.icon_node(shut, "folder", shut_icon, By(fn() { @sf.theme().p.muted })) |> ignore
        @sf.words_node(shut, fn() {
          if dialogs.denied.get() { @sf.t("web-pages.drive.pickNeedsAccess") } else { dialogs.error.get() }
        }, fn() { shut_words }) |> ignore
      })
      list.show(fn() { !dialogs.denied.get() && dialogs.error.get() == "" && dialogs.value.get() is None }, fn(wait) {
        @sf.wait_line_node(wait, fn() { @sf.t("common.reading") }) |> ignore
      })
      list.show(fn() { !dialogs.denied.get() && dialogs.error.get() == "" && dialogs.value.get() is Some(_) }, fn(contents) {
        contents.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).gap(Is(@ui.Space::px(S0_5))) |> ignore
        contents.show(fn() { shown().is_empty() }, fn(empty) {
          @sf.words_node(empty, fn() {
            @sf.t(if wanted() != "" { "web-pages.drive.pickNoMatch" } else { "web-pages.drive.noSubfolders" })
          }, fn() { picker_head }) |> ignore
        })
        contents.show(fn() { !shown().is_empty() }, fn(has) {
          has.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).gap(Is(@ui.Space::px(S0_5))) |> ignore
          @sf.words_node(has, fn() { @sf.t("web-pages.drive.foldersHere") }, fn() { picker_head }) |> ignore
          // A different path has its own list and scroll position, as the old list's key did.
          has.pick(fn() { text(dialogs.value.get(), "path") }, fn(list, path) {
            let scroll = match folder_scrolls.get(path) {
              Some(s) => s
              None => {
                let s = @view.Scroll::list()
                folder_scrolls[path] = s
                s
              }
            }
            list.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
            list.scrolls_window(scroll, fn() { shown().mapi(fn(i, _) { i }) }, est=pick_row_h,
              slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(row, i) {
                let entry = fn() { shown().get(i).unwrap_or(("", "", false, false)) }
                picker_row_node(row, entry, fn() { false }, fn() {
                  picker_go(@ui.current(), src, station, Some(@signals.untracked(entry).1))
                })
              }) |> ignore
          })
        })
      })
    }) |> ignore
  }) |> ignore
}

///|
/// One place or folder, followed by path as the answer or filter changes. Its keyboard, touch and accessibility
/// activation all use the same action.
fn picker_row_node(
  parent : @view.View,
  item : () -> (String, String, Bool, Bool),
  here : () -> Bool,
  go : () -> Unit,
) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { pick_row })
    row.ground(By(fn() {
      if @sf.lit_node(row) { @ui.tree_theme().color(Hover) }
      else if here() { @ui.tree_theme().color(ListGround) }
      else { 0L }
    })).says(By(fn() { Some(@view.said(Button, label=item().0)) })) |> ignore
    @sf.presses_node(row, go)
    @sf.icon_node(row, "folder", pick_icon, By(fn() { @sf.theme().p.muted }),
      name_now=fn() { if item().3 { "disk" } else { "folder" } }) |> ignore
    row.box(fn(words) {
      @sf.style_node(words, fn() { root_text }, in_row=true)
      @sf.words_node(words, fn() { item().0 }, fn() { if here() { pick_name_here } else { pick_name } }) |> ignore
      words.show(fn() { item().2 }, fn(note) {
        @sf.words_node(note, fn() { @sf.t("web-pages.drive.pickUnreadable") }, fn() { pick_meta }) |> ignore
      })
    }) |> ignore
  }) |> ignore
}
