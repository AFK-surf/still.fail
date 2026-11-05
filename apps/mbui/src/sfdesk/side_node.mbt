// The sidebar made once over the block (pane_view's and tape_view's `sides`): where the block lays its sidebar out
// (SideAt), the sidebar the block holds now (side_place), each made as nodes of the window's tree: the chats' lists for
// the chats' places. Those not made once yet are the block's old view's (lists.mbt sidebar).

///|
/// The sidebar the block holds now in node `n` (as large as what holds the block, over it), where `at` says the block
/// has it: cut to the block's room inside its line, its corners the block's; shown while what is in it is drawn.
fn side_node(n : @view.View, src : Source, tips : @sf.TipLayer, at : () -> SideAt) -> Unit {
  n.show(fn() { side_made(side_place()) }, fn(cut) {
    cut
    // (not shown, as the device waits in the lock: laid out nowhere, the same nodes, what had the focus in it given
    // it back as it is shown again, as an old view's focus waits for its node)
    .laid_nowhere(By(fn() { !at().shown }))
    .clips(Is(true))
    .width(By(fn() { Some(at().block.2) }))
    .height(By(fn() { Some(at().block.3) }))
    .offset(By(fn() { (at().block.0, at().block.1) }))
    .edge(By(fn() { (at().edge.0, 0L) }))
    |> ignore
    dock_round_node(cut, at)
    cut.box(fn(side) {
      side
      .width(By(fn() { Some(at().box.2) }))
      .height(By(fn() { Some(at().box.3) }))
      .offset(By(fn() { (at().box.0 - at().block.0, at().box.1 - at().block.1) }))
      |> ignore
      side.pick(fn() { side_place() }, fn(s, place) {
        match place {
          // (the chats' lists: a place of the rail's of theirs, or what the frame shows by default)
          _ => lists_side_node(s, src, tips, at)
        }
      })
    })
    |> ignore
  })
}

///|
/// Whether the sidebar of `place` (side_place's) is made once over the block, not drawn by its old view (sidebar's).
fn side_made(place : String) -> Bool {
  !(place is ("files" | "settings" | "stations" | "profiles"))
}

///|
/// The chats' sidebar (lists_side's) in node `s` as wide as the sidebar: the lists (sfpages' chats_lists_node: 全部,
/// 我参与的, 监控中, then 已归档 on its track) under the band (新建对话 and the filter) and over the foot; the band, the
/// foot and 已归档's list nodes too.
fn lists_side_node(s : @view.View, src : Source, tips : @sf.TipLayer, at : () -> SideAt) -> Unit {
  let workspace = fn() { @sfbase.workspace_in_view(src).0 }
  let mode = fn() {
    match workspace() {
      Some(w) => list_mode(src, w)
      None => 0
    }
  }
  let frame : @sfpages.ListsNodeFrame = {
    // (under the band and its top row: on the block's way between open and folded the taller end's all the way, the
    // band moving over them as it goes, so their rows are not laid out again each frame: list_band_h, list_top_h; read
    // again as the block is said to stand otherwise)
    top: fn() {
      at() |> ignore
      lists_room.get() |> ignore
      match workspace() {
        Some(w) => list_band_h(src, w)
        None => 0.0
      }
    },
    under: fn() {
      at() |> ignore
      lists_room.get() |> ignore
      list_top_h()
    },
    foot: fn() { 0.0 },
    ground: fn() { if side_folded() || wide.tape { apart_ground() } else { @sf.theme().p.sidebar } },
    before: fn(_, _) { [] },
    after: fn(_, _) { [] },
    others: [
      fn(p) {
        // (all of its lane, as a list is)
        archive_pane_node(p, src, tips, workspace, fn() {
          // (read again as the block is said to stand: band_h reads the frame's own)
          at() |> ignore
          lists_room.get() |> ignore
          match workspace() {
            Some(w) => band_h(src, w)
            None => 0.0
          }
        })
      },
    ],
    shown: mode,
    at: Side,
    watched: fn() { true },
  }
  // (while the app's first page waits for what it shows: drawn at none, the splash in its place, as the old views are)
  s.grow(Is(1.0)).min_height(Is(Some(0.0))).alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
  |> ignore
  // under a finger's search (sfpages' search.mbt): the band and the foot away with the lists, the search over them
  let away = @sfpages.search_away_node(s)
  s.box(fn(lists) {
    // (their room for the band held on the block's way: drawn where the band has them as it goes, lists_side's)
    lists
    .over(Is(true))
    .drawn_off(By(fn() {
      at() |> ignore
      lists_room.get() |> ignore
      match workspace() {
        Some(w) => (0.0, band_h(src, w) - list_band_h(src, w))
        None => (0.0, 0.0)
      }
    }))
    |> ignore
    @sfpages.chats_lists_node(lists, src, workspace, frame, tips, fn() { 0 })
  })
  |> ignore
  // the band over the lists (beside the system's tabs, its old view), the foot under them: each only
  // as tall as it is, the lists under them the rest (what the pointer is over and a press takes there)
  s.box(fn(o) {
    o.over(Is(true)).alpha(By(fn() { 1.0 - away() })) |> ignore
    // (beside the system's bars as they come to be, or as they go: the one or the other, as the system says it now)
    o.pick(@sf.native_on, fn(b, native) {
      if native {
        @ui.old(b, fn(c) {
          match workspace() {
            Some(w) => lists_band(c, src, w)
            None => ()
          }
        }, natural=true)
        |> @ui.old_takes_own
        |> ignore
      } else {
        lists_band_node(b, src, tips, workspace, at)
      }
    })
    o.box(fn(between) { between.grow(Is(1.0)) |> ignore }) |> ignore
    lists_foot_node(o, src, tips, workspace, at)
  })
  |> ignore
  s.show(@sfpages.search_on_lists, fn(k) {
    @sfpages.search_page_node(k, src, workspace, side_top_h, Side)
  })
}

///|
/// The band over the chats' lists (lists_band's) in `o`, where `at` says the block has it: on the sidebar's own ground
/// (the closed bar's as it closes), its top row, then 新建对话, what is catching up, the update where one
/// is offered and the filter (with stations to narrow) on one line; 待处理 under them where the rail has no bell.
fn lists_band_node(
  o : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  at : () -> SideAt,
) -> Unit {
  let band_at = fn() {
    let a = at()
    ({ brand: a.brand, band: a.band, tape: a.tape, in_bar: a.bar, roots: @ui.tree_corner_roots_now() } : BandAt)
  }
  let view = fn() {
    match workspace() {
      Some(w) => chats_of(src, w.id, "all").0
      None => None
    }
  }
  o.box(fn(band) {
    band.ground(By(fn() { @sf.mix(apart_ground(), band_at().band, @sf.theme().p.sidebar) })) |> ignore
    side_top_node(band, fn() { band_at().brand })
    band.box(fn(line) {
      @sf.style_node(line, fn() {
        let a = band_at()
        if a.tape {
          band_new_tape(at=a)
        } else {
          band_new_pane(at=a)
        }
      })
      line.box(fn(full) {
        full.row(Is(true)).grow(Is(1.0)) |> ignore
        @sf.band_row_node(full, fn() { app.nav.top() is NewChat }, fn() { @sf.t("web-main.sidebar.newChat") }, new_chat, fn(r) {
          @sf.icon_node(r, "compose", @sf.theme().chat_list.band_icon, By(fn() { @sf.theme().p.muted })) |> ignore
          @sf.nav_words_node(r, fn() { @sf.t("web-main.sidebar.newChat") })
        })
      })
      |> ignore
      // catching up on what changed while away (sync_key_node, only while it is: no tick once it stops, as the old
      // view's was here)
      line.show(fn() { view().map(fn(v) { v.syncing is Some(_) }).unwrap_or(false) }, fn(k) {
        @sf.sync_key_node(k, tips, update_key_side, update_key_mark, fn() { true }, fn() {
          match view() {
            Some({ syncing: Some(y), .. }) => y
            _ => ""
          }
        })
      })
      // 更新 before the filter where one is offered (brand.mbt update_in_row)
      line.show(update_shown, fn(k) {
        @sf.update_key_node(
          k,
          tips,
          update_key_side,
          update_key_mark,
          fn() { update_said().0 },
          fn() { update_said().1 },
          fn() { update_said().2 },
          fn() {
            match update_now() {
              Coming(_, part) => Some(part)
              _ => None
            }
          },
          fn() {
            match @signals.untracked(update_now) {
              Coming(_, _) => @sfbase.update_dialog(src)
              _ => update_go(src)
            }
          },
          offered=fn() { update_now() is Offered(_, ..) },
        )
      })
      // the filter: its menu (sfpages' filter_menu), a filter its list, 已归档 the archive's list
      line.show(fn() { view().map(fn(v) { v.stations > 0 }).unwrap_or(false) }, fn(k) {
        k.box(fn(f) {
          let shown = fn() {
            match workspace() {
              Some(w) => list_place(list_mode(src, w))
              None => "chats"
            }
          }
          let hot = @sf.EdgeWay::new(0.0)
          f.reacts(fn() { @sf.lit_node(f) || @sfpages.filter_menu_open() }, fn(on) {
            hot.go(f, if on { 1.0 } else { 0.0 }, @sf.dur_ms)
          })
          @sf.style_node(f, fn() { filter_box })
          // (round as its ground is while it shows one, as an old view's is drawn: at rest nothing of it stands in the
          // panel's corner; in the closed bar's, its corner linked, below)
          f.radius(By(fn() { if band_at().in_bar || hot.shown(f) > 0.0 { 1.0e6 } else { 0.0 } })) |> ignore
          // (in the closed bar's corner, its ground's corner linked to that corner, concentric with it: filter_box_bar)
          @ui.tree_corners_linked(f, fn() {
            if band_at().in_bar {
              Some(FixedArray::make(4, filter_bar_link()))
            } else {
              None
            }
          })
          f.ground(By(fn() { @sf.alpha(@sf.theme().p.hover, hot.shown(f)) })) |> ignore
          @sf.presses_node(f, fn() {
            guard @signals.untracked(workspace) is Some(w) else { return }
            let (x, y, wd, h) = f.placed_window_now()
            let now = @signals.untracked(shown)
            @sfpages.filter_menu(At(x, y, wd, h), if now == "chats" { "all" } else { now }, fn(pick) {
              rail_go_told(src, w, if pick == "all" { "chats" } else { pick }, fn(_, g) { g() })
            })
          })
          f.says(By(fn() {
            Some(@view.said(Button, label=@sf.t("web-main.filter.chats.named", args=[("named", filter_named(shown()))])))
          }))
          |> ignore
          @sf.icon_node(f, "filter", side_icon, By(fn() {
            let t = @sf.theme()
            @sf.mix(t.p.text, hot.shown(f), t.p.muted)
          }))
          |> ignore
          @sf.tip_node(tips, f, fn() { @sf.t("web-main.filter.chats") }) |> ignore
        })
        |> ignore
      })
    })
    |> ignore
    // 待处理 under 新建对话 where the rail has no bell
    band.show(fn() { workspace().map(fn(w) { todo_shown(src, w) }).unwrap_or(false) }, fn(k) {
      k.box(fn(t) {
        @sf.style_node(t, fn() { todo_box })
        let n = fn() { workspace().map(fn(w) { todo_all(src, w) }).unwrap_or(0) }
        @sf.band_row_node(t, fn() { wide.attention_open.get() }, fn() { @sf.t("web-main.attention.entry") }, fn() {
          attention_set(!@signals.untracked(fn() { wide.attention_open.get() }))
        }, fn(r) {
          @sf.icon_node(r, "bell", @sf.theme().chat_list.band_icon, By(fn() { @sf.theme().p.muted })) |> ignore
          @sf.nav_words_node(r, fn() { @sf.t("web-main.attention.entry") })
          r.box(fn(slot) {
            @sf.style_node(slot, fn() { todo_slot })
            slot.show(fn() { n() > 0 }, fn(c) {
              c.box(fn(count) {
                @sf.style_node(count, fn() { todo_count })
                @sf.words_node(count, fn() { n().to_string() }, fn() { todo_count_words }) |> ignore
              })
              |> ignore
            })
          })
          |> ignore
        })
      })
      |> ignore
    })
  })
  |> ignore
}


///|
/// The lists' foot band (lists_foot's) in `o`, where `at` says the block has it: what is wrong with the stations
/// (their glyph and its words, red while one fails, leading to them) and 运行中 N (the services left up long, their
/// panel over it); nothing when neither is, nor with the bell in the rail (they are in its panel). On the sidebar's own
/// ground, the closed bar's as it closes, as the band over the lists.
fn lists_foot_node(
  o : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  at : () -> SideAt,
) -> Unit {
  ignore(tips)
  let chats = fn() {
    match workspace() {
      Some(w) => (src.topic)("chats", { "scope": Json::string(w.id), "mine": Json::boolean(false) }).value
      None => None
    }
  }
  let trouble = fn() { field(chats(), "trouble") }
  let jobs = fn() {
    match workspace() {
      Some(w) => long_jobs(src, w)
      None => 0
    }
  }
  let shown = fn() {
    match workspace() {
      Some(w) => !rail_items(src, w.id).contains("attention") && !(trouble() is None && jobs() == 0)
      None => false
    }
  }
  o.show(shown, fn(f) {
    f.box(fn(band) {
      @sf.style_node(band, fn() { foot_band })
      band.ground(By(fn() { @sf.mix(apart_ground(), at().band, @sf.theme().p.sidebar) })) |> ignore
      // what is wrong with the stations, leading to them
      // (the shown node itself the row: what holds it in the band takes what the band leaves, as foot_trouble's w=Full)
      band.show(fn() { trouble() is Some(Object(_)) }, fn(r) {
        @sf.style_node(r, fn() { foot_trouble }, in_row=true)
        r.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        r.ground(By(fn() { if @sf.lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
        @sf.pressed_node(r, fn() { @sfbase.go_place("stations") |> ignore }, By(fn() { @ui.tree_theme().corner(@sf.side_row_radius) }), Button, fn() {
          text(trouble(), "text")
        })
        @sf.station_glyph_node(
          r,
          fn() {
            match workspace() {
              Some(w) => stations_at_glance(src, w.id).0
              None => { online: 0, dim: 0, failing: 0, working: 0, asleep: false, connecting: 0 }
            }
          },
          foot_glyph,
          fn() { @sf.theme().p.text },
          fn() { @sf.theme().p.red },
        )
        |> ignore
        r.box(fn(w) {
          w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          @sf.words_node(w, fn() { text(trouble(), "text") }, fn() {
            if text(trouble(), "state") == "error" {
              foot_trouble_red
            } else {
              foot_trouble_words
            }
          })
          |> ignore
        })
        |> ignore
      })
      // 运行中 N: the services left up long, their panel over it
      band.show(fn() { jobs() > 0 }, fn(k) {
        let chip = k.box(fn(c) {
          @sf.style_node(c, fn() { foot_chip }, in_row=true)
          @sf.pressed_node(c, fn() { wide.jobs_open.set(!@signals.untracked(fn() { wide.jobs_open.get() })) }, Is(1.0e6), Button, fn() {
            @sf.t("web-main.jobs.long")
          })
          c.box(fn(d) { @sf.style_node(d, fn() { foot_chip_dot }) }) |> ignore
          @sf.words_node(c, fn() { @sf.t("web-main.jobs.chip", args=[("n", jobs().to_string())]) }, fn() { foot_chip_words })
          |> ignore
        })
        @sf.panel_by_node(
          k,
          "side/open-jobs",
          fn() { jobs() > 0 && wide.jobs_open.get() },
          fn(_) { chip },
          fn(c, _) {
            match @signals.untracked(workspace) {
              Some(w) => open_jobs(c, src, w)
              None => ()
            }
          },
          fn() { wide.jobs_open.set(false) },
          w=open_jobs_pop_w,
          side=Top,
          along=End,
        )
      })
    })
    |> ignore
  })
}
