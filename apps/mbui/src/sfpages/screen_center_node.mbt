// 控制中心 (screen_panel.mbt's center_open) as nodes of the window's tree, made once in the panel its presenter gives it
// (@sf.panel_nodes: a sheet from the foot on 小屏, a panel beside what opened it on 中屏 and 大屏), each part following
// what it shows as that is told: the view's state (ScreenSess's `said`), the prefs, the link's figures, how long it has
// been seen, its sound and the stage's size (ScreenSess's and ScreenUi's signals).

///|
/// What 控制中心 holds in `v`, the most used first (as UU 远程's control bar has it): the combos as tiles (while driving:
/// their names, a tap sends their keys), how the view goes (live: its round trip, pressed its figures), 画质, 帧率 and
/// 缩放 (where the station changes it) a row each, then sending files, 在新窗口打开 (a desktop's), 全屏, and 断开. `c`
/// the screen page's, what its choices are told through; `done` closes it.
fn center_node(
  c : @ui.Ctx,
  v : @view.View,
  s : ScreenSess,
  u : ScreenUi,
  from : @sf.Anchor,
  close : () -> Unit,
  done : () -> Unit,
) -> Unit {
  let src = s.src
  // (what reads the view's state reads it again as another is taken)
  let state = fn() {
    s.said.get() |> ignore
    s.state
  }
  // (a simulator's page has its device's buttons beside the picture: screen_debug.mbt)
  v.show(fn() { state() |> ignore; s.driving() && !s.simulator() }, fn(d) {
    @sf.panel_group_node(d, fn() { @sf.t("web-pages.screen.combos") }, fn(g) {
      g.pick(fn() { screen_os(src, s.station) }, fn(b, os) { combo_tiles_node(b, s, combos_for(os), done) })
    })
    @sf.panel_group_node(d, fn() { @sf.t("web-pages.screen.commonKeys") }, fn(g) { key_tiles_node(g, s, u) })
    // the mouse's buttons shown or not (the keys row's, the floating pair), kept on this device
    @sf.panel_group_node(d, fn() { "" }, fn(g) {
      @sf.panel_switch_row_node(g, fn() { @sf.t("web-pages.screen.mouseButtons") }, fn() { state() |> ignore; mouse_shown(s, u) }, fn(
        on,
      ) {
        u.mouse_set.set(Some(on))
        prefs_chosen(c, s, "screenMouse", if on { "" } else { "off" })
      })
    })
  })
  v.show(fn() { state() |> ignore; s.phase() == "live" }, fn(l) {
    @sf.panel_group_node(l, fn() { "" }, fn(g) {
      @sf.panel_row_node(
        g,
        fn() { @sf.t("web-pages.screen.stats") },
        fn() {
          done()
          net_panel_open(s, u, from)
        },
        icon=fn() { "chart" },
        note=fn() {
          state() |> ignore
          let rtt = text(field(screen_net(s), "rtt"), "text")
          if rtt == "" { seen_for(u) } else { rtt + " · " + seen_for(u) }
        },
        end="chevron-right",
      )
    })
  })
  v.show(fn() { s.audio_ready.get() }, fn(a) {
    @sf.panel_row_node(
      a,
      fn() { @sf.t(if s.audio_muted.get() { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }) },
      fn() { s.toggle_audio() },
      icon=fn() { if s.audio_muted.get() { "volume-x" } else { "volume" } },
    )
  })
  @sf.panel_group_node(v, fn() { @sf.t("web-pages.screen.quality") }, fn(g) {
    let now = fn() {
      let quality = screen_quality(src)
      screen_qualities.search_by(fn(q) { q.0 == quality }).unwrap_or(0)
    }
    center_choice_node(g, fn() { screen_qualities.map(fn(q) { @sf.t("web-pages.screen.quality." + q.1) }) }, now, fn(
      chosen,
    ) {
      prefs_chosen(c, s, "screenQuality", screen_qualities[chosen].0)
    })
    @sf.panel_note_node(g, fn() { @sf.t("web-pages.screen.qualityHint." + screen_qualities[now()].1) })
  })
  // the most frames a second (自动: as many as the station and the link give), beside 画质
  @sf.panel_group_node(v, fn() { @sf.t("web-pages.screen.fps") }, fn(g) {
    center_choice_node(
      g,
      fn() { screen_fps_choices.map(fn(f) { if f == 0 { @sf.t("web-pages.screen.fps.auto") } else { "\{f}" } }) },
      fn() { screen_fps_choices.search(screen_fps(src)).unwrap_or(0) },
      fn(chosen) {
        let f = screen_fps_choices[chosen]
        prefs_set(c, s, "screenFps", "\{f}", if f == 0 { Json::null() } else { Json::number(f.to_double()) })
      },
    )
    @sf.panel_note_node(g, fn() { fps_note(screen_fps(src)) })
  })
  let scale = fn() {
    state() |> ignore
    s.scale()
  }
  v.show(fn() { scale() is Some(_) }, fn(sc) {
    let steps = fn() {
      match scale() {
        Some((_, _, steps)) => steps
        None => []
      }
    }
    @sf.panel_group_node(sc, fn() { @sf.t("web-pages.screen.scale") }, fn(g) {
      // (asked of the station as it is chosen)
      center_choice_node(
        g,
        fn() { steps().map(fn(p) { "\{p}%" }) },
        fn() {
          match scale() {
            Some((percent, _, steps)) => steps.search(percent).unwrap_or(-1)
            None => -1
          }
        },
        fn(chosen) {
          let steps = @signals.untracked(steps)
          s.input(src, Json::object({ "t": Json::string("scale"), "percent": Json::number(steps[chosen].to_double()) }))
        },
      )
      @sf.panel_note_node(g, fn() {
        let recommended = match scale() {
          Some((_, recommended, _)) => recommended
          None => 0
        }
        @sf.t("web-pages.screen.scaleRecommended", args=[("percent", "\{recommended}")])
      })
    })
  })
  // its resolution, the mode nearest the shape this device shows it in said (UU Remote's 分辨率)
  let resolution = fn() {
    state() |> ignore
    match s.resolution() {
      Some((size, all)) => {
        let fitting = resolution_fitting(all, u.box_w.get(), u.box_h.get())
        Some((size, all, fitting, resolution_shown(all, size, fitting)))
      }
      None => None
    }
  }
  v.show(fn() { resolution() is Some(_) }, fn(r) {
    @sf.panel_group_node(r, fn() { @sf.t("web-pages.screen.resolution") }, fn(g) {
      let modes = fn() {
        match resolution() {
          Some((_, _, _, modes)) => modes
          None => []
        }
      }
      // (the nearest marked in the list too, not only in the note under it: the user, 2026-10-29)
      center_choice_node(
        g,
        fn() {
          match resolution() {
            Some((_, all, fitting, modes)) =>
              modes.map(fn(m) {
                let size = "\{m.0}×\{m.1}"
                if fitting >= 0 && m == all[fitting] {
                  @sf.t("web-pages.screen.resolutionMark", args=[("size", size)])
                } else {
                  size
                }
              })
            None => []
          }
        },
        fn() {
          match resolution() {
            Some((size, _, _, modes)) => modes.search(size).unwrap_or(-1)
            None => -1
          }
        },
        // (asked of the station as it is chosen)
        fn(chosen) {
          let (w, h) = @signals.untracked(modes)[chosen]
          s.input(src, { "t": Json::string("resolution"), "width": Json::number(w.to_double()), "height": Json::number(h.to_double()) })
        },
      )
      let fits = fn() {
        match resolution() {
          Some((_, all, fitting, _)) if fitting >= 0 => Some(all[fitting])
          _ => None
        }
      }
      g.show(fn() { fits() is Some(_) }, fn(n) {
        @sf.panel_note_node(n, fn() {
          let (w, h) = fits().unwrap_or((0, 0))
          @sf.t("web-pages.screen.resolutionFits", args=[("size", "\{w}×\{h}")])
        })
      })
    })
  })
  @sf.panel_group_node(v, fn() { "" }, fn(g) {
    g.show(fn() { state() |> ignore; s.drops_to() is Some(_) }, fn(f) {
      @sf.panel_row_node(f, fn() { @sf.t("android-misc.screen.sendFile") }, fn() {
        done()
        send_asked(c, s, u)
      }, icon=fn() { "upload" })
    })
    // in a window of its own (a desktop's), as the web's ScreenPage: it leaves this one, so it is not open twice
    let alone : @sfbase.Page = Screen({ station: s.station, screen: s.screen, title: "", until_gone: false })
    if @sfbase.window_opens_for(alone) {
      @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.window") }, fn() {
        done()
        if @sfbase.open_window(alone) {
          close()
        }
      }, icon=fn() { "external" })
    }
    g.show(fn() { state() |> ignore; s.open_now() }, fn(o) {
      // (the window filling the screen is the host's, read as this is made: pressed, 控制中心 closes)
      @sf.panel_row_node(
        o,
        fn() { @sf.t(if full_now(u) { "android-misc.screen.unfull" } else { "android-misc.screen.full" }) },
        fn() {
          full_asked(c, u)
          done()
        },
        icon=fn() { if full_now(u) { "shrink" } else { "expand" } },
      )
    })
    // Its other views, this person's on other devices and others' alike.
    let others = fn() { items(state(), "otherViews") }
    g.show(fn() { others().length() > 0 }, fn(e) {
      @sf.panel_row_node(e, fn() { @sf.t("web-pages.screen.endOthers", args=[("count", others().length().to_string())]) }, fn() {
        for o in @signals.untracked(others) {
          let params = Map([("station", Json::string(s.station)), ("screen", Json::string(s.screen)), ("view", Json::string(text(Some(o), "id")))])
          (src.call)("screen.endView", Json::object(params), @sfbase.answer_unread)
        }
        done()
      }, icon=fn() { "close" })
    })
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.leave") }, fn() {
      done()
      close()
    }, icon=fn() { "close" }, danger=true)
  })
}

///|
/// A choice of 控制中心's in `parent` (画质, 帧率, 缩放, 分辨率): a segmented row (segmented_node's, as the panel is laid
/// out) in by a panel row's padding.
fn center_choice_node(parent : @view.View, labels : () -> Array[String], chosen : () -> Int, choose : (Int) -> Unit) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { center_choice })
    @sf.segmented_node(b, labels, chosen, choose)
  })
  |> ignore
}

///|
/// The combos as tiles in `parent`, three to a row: an icon over its name (what it does, not its keys: a phone has no
/// keys to press for it), a tap sending its keys down and up, and 控制中心 closing (`done`).
fn combo_tiles_node(parent : @view.View, s : ScreenSess, combos : Array[Combo], done : () -> Unit) -> Unit {
  tiles_node(parent, combos.length(), 3, tile_gap, fn(row, i) {
    let k = combos[i]
    center_tile_node(row, tile_box, k.name, fn() {
      stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, k.mods)
      done()
    }, fn(t) {
      @sf.icon_node(t, k.icon, round_icon, By(fn() { @ui.tree_theme().color(Fg) })) |> ignore
      @sf.words_node(t, fn() { k.name }, fn() { tile_words }) |> ignore
    })
  })
}

///|
/// The keys of `screen_panel_keys` as small tiles in `parent`, six to a row, a tap sending the key down and up with the
/// modifiers the keys row holds; 控制中心 stays open (F5, Page Down… are pressed again and again).
fn key_tiles_node(parent : @view.View, s : ScreenSess, u : ScreenUi) -> Unit {
  let keys = screen_panel_keys
  tiles_node(parent, keys.length(), 6, key_tile_gap, fn(row, i) {
    let (label, key) = keys[i]
    center_tile_node(row, key_tile_box, label, fn() {
      let mods = u.held.take()
      stroke(fn(j) { s.input(s.src, j) }, key, key, mods)
    }, fn(t) {
      @sf.words_node(t, fn() { label }, fn() { key_tile_words }) |> ignore
    })
  })
}

///|
/// `count` tiles in `parent`, `per` to a row, 8 apart, in by a panel row's padding, each made by `tile` in its row; the
/// last row's left as wide as the others (`gap`).
fn tiles_node(parent : @view.View, count : Int, per : Int, gap : @ui.Style, tile : (@view.View, Int) -> Unit) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { tiles_box })
    for r in 0..<((count + per - 1) / per) {
      b.box(fn(row) {
        @sf.style_node(row, fn() { tiles_row })
        for i in (r * per)..<(r * per + per) {
          if i >= count {
            row.box(fn(g) { @sf.style_node(g, fn() { gap }, in_row=true) }) |> ignore
          } else {
            tile(row, i)
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A tile in `row` (`look`: tile_box's, key_tile_box's), its ground the hover's while pressed, read out a button named
/// `label`, `press` as it is pressed; what is on it made by `face`.
fn center_tile_node(row : @view.View, look : @ui.Style, label : String, press : () -> Unit, face : (@view.View) -> Unit) -> Unit {
  row.box(fn(t) {
    @sf.style_node(t, fn() { if t.pressed() { look.then(tile_pressed) } else { look } }, in_row=true)
    t.says(Is(Some(@view.said(Button, label~)))) |> ignore
    @sf.presses_node(t, press)
    face(t)
  })
  |> ignore
}
