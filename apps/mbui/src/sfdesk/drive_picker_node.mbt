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
/// the new station and make its body anew. Its arrangement follows the window as in the old presented picker.
/// Let go with folder_browse_close when its containing panel is left.
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
  // The old presenter laid these as separate parts: a sheet's gap is 10, a dialog's 16.
  body.gap(Is(@ui.Space::px(if @sf.look_node(body) is Narrow { S2_5 } else { S4 }))) |> ignore
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
  // The old panel drew the picker with the window's Ctx width, even when the dialog's body was narrower. Keep the
  // children across arrangements so that changing the window preserves the filter, focus and list scroll.
  body.box(fn(path) {
    path.padding(Is((0.0, 0.0, 0.0, @ui.Space::px(S2_5))))
    .layout_box(By(fn() {
      (!dialogs.denied.get() && dialogs.error.get() == "", @sf.look_for(body.window().0) is Narrow)
    }), sized=true, fn(l, at) {
      let (has_filter, narrow) = at
      let way_node = l.child("way", fn(part) {
        @sf.way_line_node(part, fn() { way().map(fn(w) { w.0 }) }, picker_way, fn(i) {
          match @signals.untracked(way).get(i) {
            Some((_, p)) => picker_go(@ui.current(), src, station, Some(p))
            None => ()
          }
        }) |> ignore
      })
      let gap = if has_filter { @ui.Space::px(if narrow { S2 } else { S3 }) } else { 0.0 }
      let field_w = if narrow { l.width } else { @ui.Space::px(S48) }
      let way_w = if narrow || !has_filter { l.width } else { dmax(0.0, l.width - field_w - gap) }
      let (_, way_h) = l.measure(way_node, way_w)
      let mut height = way_h
      if has_filter {
        let field = l.child("filter", fn(f) {
          @sf.input_node(f, dialogs.filter, placeholder_by=fn() { @sf.t("web-pages.drive.pickFilter") }) |> ignore
        })
        let (_, field_h) = l.measure(field, field_w)
        if narrow {
          l.place(way_node, 0.0, 0.0)
          l.place(field, 0.0, way_h + gap)
          height = way_h + gap + field_h
        } else {
          height = dmax(@ui.Space::px(S9) - @ui.Space::px(S2_5), dmax(way_h, field_h))
          l.place(way_node, 0.0, (height - way_h) / 2.0)
          l.place(field, way_w + gap, (height - field_h) / 2.0)
        }
      } else {
        if !narrow { height = dmax(@ui.Space::px(S9) - @ui.Space::px(S2_5), height) }
        l.place(way_node, 0.0, (height - way_h) / 2.0)
      }
      l.size_to(height)
    }) |> ignore
  }) |> ignore
  body.box(fn(box) {
    box.height(Is(Some(@ui.Space::px(S96))))
    .layout_box(By(fn() { (places().length(), @sf.look_for(body.window().0) is Narrow) }), fn(l, at) {
      let (count, narrow) = at
      let gap = if count > 0 { @ui.Space::px(S3) } else { 0.0 }
      let mut side_w = 0.0
      let mut side_h = 0.0
      if count > 0 {
        let side = l.child("places", fn(side) {
          side.layout_box(By(fn() { places().length() }), sized=true, fn(s, n) {
            let head = s.child("head", fn(head) {
              @sf.words_node(head, fn() { @sf.t("web-pages.drive.places") }, fn() { picker_head }) |> ignore
            })
            let (_, head_h) = s.measure(head, s.width)
            let list = s.child("list", fn(list) {
              list.scrolls_window(@view.Scroll::list(), fn() { places().mapi(fn(i, _) { i }) }, est=pick_row_h,
                slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(row, i) {
                  let place = fn() { places().get(i).unwrap_or(("", "", false, false)) }
                  picker_row_node(row, place, fn() { place().1 == here() }, fn() {
                    picker_go(@ui.current(), src, station, Some(@signals.untracked(place).1))
                  })
                }) |> ignore
            })
            let between = @ui.Space::px(S0_5)
            let list_h = if s.height == @double.infinity {
              dmin(n.to_double() * pick_row_h, picker_places_most)
            } else {
              dmax(0.0, s.height - head_h - between)
            }
            s.measure(list, s.width, height=list_h) |> ignore
            s.place(head, 0.0, 0.0)
            s.place(list, 0.0, head_h + between)
            s.size_to(head_h + between + list_h)
          }) |> ignore
        })
        side_w = if narrow { l.width } else { @ui.Space::px(S44) }
        let (_, h) = if narrow { l.measure(side, side_w) } else { l.measure(side, side_w, height=l.height) }
        side_h = h
        l.place(side, 0.0, 0.0)
      }
      let list = l.child("folders", fn(list) {
        @sf.style_node(list, fn() { picker_list })
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
      })
      let list_w = if narrow { l.width } else { dmax(0.0, l.width - side_w - gap) }
      let list_h = if narrow { dmax(0.0, l.height - side_h - gap) } else { l.height }
      l.measure(list, list_w, height=list_h) |> ignore
      l.place(list, if narrow { 0.0 } else { side_w + gap }, if narrow { side_h + gap } else { 0.0 })
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
