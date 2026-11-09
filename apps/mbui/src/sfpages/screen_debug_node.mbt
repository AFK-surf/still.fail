// 日志, the panel of what debugs an app on a simulator (screen_debug.mbt's debug_logs_open), as nodes of the window's
// tree, made once in the panel its presenter gives it (@sf.panel_nodes: a sheet from the foot on 小屏, a panel beside
// what opened it on 中屏 and 大屏): App, 日志 and 设备 to choose between (segmented_node), each made as it is chosen,
// what it shows following DebugLogs as that is told (its signals: the pane beside the device reads the same). What is
// done is the same helpers' the pane's old views call.

///|
/// What 日志 holds in `v`: App, 日志 or 设备, chosen, and what that one holds. `c` the screen page's, what a recording's
/// movie is downloaded through and 安装 App asked by.
fn debug_logs_node(c : @ui.Ctx, v : @view.View, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  v.box(fn(b) {
    @sf.style_node(b, fn() { debug_body })
    b.box(fn(k) { @sf.segmented_node(k, debug_tab_labels, fn() { d.tab.get() }, fn(i) { d.tab.set(i) }) }) |> ignore
    b.pick(fn() { d.tab.get() }, fn(t, tab) {
      @sf.style_node(t, fn() { debug_tab_box })
      if tab == debug_tab_logs {
        debug_lines_node(t, s, d)
      } else {
        if tab == debug_tab_device {
          debug_device_node(t, s, u)
        } else {
          debug_app_node(c, t, s, u)
        }
        debug_said_node(t, d)
      }
    })
  })
  |> ignore
}

///|
/// 日志 in `t`: what came, the newest first, asked for again debug_logs_ms after each answer while it shows (the
/// station tells none of it by itself); 复制日志 over it once there is something to copy, and why it failed.
fn debug_lines_node(t : @view.View, s : ScreenSess, d : DebugLogs) -> Unit {
  fn ask() -> Unit {
    // (asked already, by the pane beside the device: looked at again then)
    if d.asking {
      t.at_moment(t.logic_at() + debug_logs_ms, ask, later=true) |> ignore
      return
    }
    debug_logs_ask(s, d, fn() { t.at_moment(t.logic_at() + debug_logs_ms, ask, later=true) |> ignore })
  }

  if d.asks == 0 {
    ask()
  } else {
    t.at_moment(t.logic_at() + debug_logs_ms, ask, later=true) |> ignore
  }
  t.show(fn() { !d.lines.get().is_empty() }, fn(k) {
    // (已复制 from each press till diag_said_ms after it, a press while it shows starting it again: the button's own,
    // let go with it; a time it shows for, not waited for)
    let (copied_now, copied) = k.holds_for(diag_said_ms, later=true)
    @sf.panel_button_node(
      k,
      fn() { @sf.t(if copied() { "web-pages.screen.stat.copied" } else { "web-pages.screen.debug.logsCopy" }) },
      fn() {
        @ui.clipboard_set(d.copied_text(), label="still.fail")
        copied_now()
      },
      tone=Quiet,
    )
    |> ignore
  })
  t.show(fn() { d.failed.get() != "" }, fn(n) { @sf.panel_note_node(n, fn() { d.failed.get() }) })
  t.show(fn() { d.lines.get().is_empty() }, fn(n) { @sf.panel_note_node(n, fn() { @sf.t("web-pages.screen.debug.logsNone") }) })
  t.each(
    fn() {
      let lines = d.lines.get()
      let n = lines.length()
      // (each by how many came before it: kept as more come)
      Array::makei(n, fn(i) { (d.dropped + n - 1 - i, lines[n - 1 - i]) })
    },
    fn(l) { l.0 },
    fn(r, l) {
      let line = fn() { l.get().1 }
      steps_run(r, fn() { line().at + " " + line().app + "  " + line().words }, debug_line, mono=true, ink=fn() {
        if line().level == "Error" || line().level == "Fault" {
          @sf.theme().p.red
        } else {
          0L
        }
      })
    },
  )
}

///|
/// What the last thing done came to, and why what was asked failed, in `t` (debug_said's).
fn debug_said_node(t : @view.View, d : DebugLogs) -> Unit {
  t.show(fn() { d.failed.get() != "" }, fn(n) { @sf.panel_note_node(n, fn() { d.failed.get() }) })
  t.show(fn() { d.acted.get() != "" }, fn(n) { @sf.panel_note_node(n, fn() { d.acted.get() }) })
}

///|
/// A choice of the device's in `g` (`labels`, the one `chosen` now), what is done as another is chosen (`choose`).
fn debug_choice_node(g : @view.View, labels : () -> Array[String], chosen : () -> Int, choose : (Int) -> Unit) -> Unit {
  g.box(fn(k) {
    @sf.segmented_node(k, labels, chosen, fn(i) {
      if i != @signals.untracked(chosen) && i >= 0 {
        choose(i)
      }
    })
  })
  |> ignore
}

///|
/// One setting of the device in `t` (debug_setting's): `label` over its `options`, the one it is set to now chosen;
/// chosen, set.
fn debug_setting_node(t : @view.View, s : ScreenSess, d : DebugLogs, label : String, name : String, options : Array[(String, String)]) -> Unit {
  @sf.panel_group_node(t, fn() { @sf.t(label) }, fn(g) {
    debug_choice_node(g, fn() { options.map(fn(o) { @sf.t(o.1) }) }, fn() {
      let now = text(d.settings.get(), name)
      options.search_by(fn(o) { o.0 == now }).unwrap_or(-1)
    }, fn(i) { debug_setting_chosen(s, d, name, options[i].0) })
  })
}

///|
/// How the device is set, asked once as App or 设备 first shows.
fn debug_settings_once(s : ScreenSess, d : DebugLogs) -> Unit {
  if !d.settings_asked {
    debug_settings_ask(s, d)
  }
}

///|
/// 设备 in `t` (debug_device's): how the device is set, what a page is checked against most often without going into
/// its 设置.
fn debug_device_node(t : @view.View, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  debug_settings_once(s, d)
  let done = fn() { @sf.t("web-pages.screen.debug.done") }
  debug_setting_node(t, s, d, "web-pages.screen.debug.appearance", "appearance", debug_appearances)
  debug_setting_node(t, s, d, "web-pages.screen.debug.textSize", "textSize", debug_text_sizes)
  @sf.panel_group_node(t, fn() { @sf.t("web-pages.screen.debug.location") }, fn(g) {
    let at = @ui.Field::new()
    let set = fn(at : String) {
      if at != "" {
        debug_act(s, d, "screen.location", { "at": Json::string(at) }, done())
      }
    }
    @sf.input_node(g, at, placeholder=@sf.t("web-pages.screen.debug.locationHint"), small=true, submitted=set) |> ignore
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.locationSet") }, fn() { set(at.text()) }, icon=fn() { "move" })
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.locationClear") }, fn() {
      debug_act(s, d, "screen.location", {}, done())
    }, icon=fn() { "close" })
  })
  @sf.panel_group_node(t, fn() { @sf.t("web-pages.screen.debug.statusBar") }, fn(g) {
    debug_choice_node(g, debug_status_labels, fn() { if d.tidy_bar.get() { 1 } else { 0 } }, fn(i) { debug_tidy_chosen(s, d, i == 1) })
  })
  @sf.panel_group_node(t, fn() { @sf.t("web-pages.screen.debug.biometrics") }, fn(g) {
    debug_choice_node(g, debug_enrolled_labels, fn() { if debug_enrolled(d) { 1 } else { 0 } }, fn(i) {
      debug_enrolled_chosen(s, d, i == 1)
    })
    // (a face or a finger matched, or not, once one is enrolled)
    g.show(fn() { debug_enrolled(d) }, fn(m) {
      @sf.style_node(m, fn() { debug_rows_box })
      @sf.panel_row_node(m, fn() { @sf.t("web-pages.screen.debug.bioMatch") }, fn() {
        debug_act(s, d, "screen.biometrics", { "what": Json::string("match") }, done())
      }, icon=fn() { "check" })
      @sf.panel_row_node(m, fn() { @sf.t("web-pages.screen.debug.bioNoMatch") }, fn() {
        debug_act(s, d, "screen.biometrics", { "what": Json::string("nomatch") }, done())
      }, icon=fn() { "close" })
    })
  })
  @sf.panel_group_node(t, fn() { "" }, fn(g) {
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.volumeUp") }, fn() { debug_device_input(s, "volume_up") }, icon=fn() {
      "volume"
    })
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.volumeDown") }, fn() { debug_device_input(s, "volume_down") }, icon=fn() {
      "volume-x"
    })
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.memoryWarning") }, fn() {
      debug_device_input(s, "memory_warning")
      d.acted.set(done())
    }, icon=fn() { "info" })
  })
}

///|
/// App in `t` (debug_app's): what is done with the app being debugged, the first of it what is done over and over.
fn debug_app_node(c : @ui.Ctx, t : @view.View, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  debug_settings_once(s, d)
  // (a recording's movie, once it has ended, downloaded: debug_record_saved's)
  t.reacts(fn() { d.to_save.get() }, fn(save) {
    match save {
      Some((root, path)) => {
        d.to_save.set(None)
        @sfbase.download_drive_file(c, s.src, s.station, root, path, "recording.mp4")
      }
      None => ()
    }
  })
  @sf.panel_group_node(t, fn() { "" }, fn(g) {
    g.pick(fn() { d.last_app.get() }, fn(k, last) {
      @sf.style_node(k, fn() { debug_rows_box })
      match last {
        Some((id, name)) => {
          @sf.panel_row_node(k, fn() { @sf.t("web-pages.screen.debug.relaunch") }, fn() { debug_relaunch(s, d, id, name) }, icon=fn() {
            "refresh"
          }, note=fn() { name })
          @sf.panel_row_opens_node(k, fn() { @sf.t("web-pages.screen.debug.relaunchOther", args=[("name", name)]) }, fn(from) {
            debug_apps_open(s, u, from)
          }, icon=fn() { "refresh" })
        }
        None => @sf.panel_row_opens_node(k, fn() { @sf.t("web-pages.screen.debug.relaunch") }, fn(from) { debug_apps_open(s, u, from) }, icon=fn() { "refresh" })
      }
    })
    g.show(fn() { s.said.get() |> ignore; text(s.state, "install") != "" }, fn(i) {
      @sf.panel_row_node(i, fn() { @sf.t("web-pages.screen.debug.install") }, fn() { install_asked(c, s, u) }, icon=fn() { "upload" }, note=fn() {
        @sf.t("web-pages.screen.debug.installKinds")
      })
    })
    // 录屏 (beside the device it is by the device)
    @sf.panel_row_node(
      g,
      fn() { @sf.t(if debug_going(d) { "web-pages.screen.debug.recordStop" } else { "web-pages.screen.debug.recordStart" }) },
      fn() { debug_record_pressed(s, d, @signals.untracked(fn() { debug_going(d) })) },
      icon=fn() { if debug_going(d) { "stop" } else { "play" } },
      note=fn() { if debug_going(d) { @sf.t("web-pages.screen.debug.recordNote") } else { "" } },
    )
  })
  let done = fn() { @sf.t("web-pages.screen.debug.done") }
  @sf.panel_group_node(t, fn() { @sf.t("web-pages.screen.debug.openUrl") }, fn(g) {
    let url = @ui.Field::new()
    let open = fn(url : String) {
      if url != "" {
        debug_act(s, d, "screen.openUrl", { "url": Json::string(url) }, done())
      }
    }
    @sf.input_node(g, url, placeholder="https://", small=true, submitted=open) |> ignore
    @sf.panel_row_node(g, fn() { @sf.t("web-pages.screen.debug.openUrlGo") }, fn() { open(url.text()) }, icon=fn() { "external" })
  })
  @sf.panel_group_node(t, fn() { @sf.t("web-pages.screen.debug.push") }, fn(g) {
    let said = @ui.Field::new()
    @sf.input_node(g, said, placeholder=@sf.t("web-pages.screen.debug.pushHint"), small=true) |> ignore
    @sf.panel_row_opens_node(g, fn() { @sf.t("web-pages.screen.debug.pushGo") }, fn(from) {
      if said.text() != "" {
        debug_apps_open(s, u, from, push=said.text())
      }
    }, icon=fn() { "bell" })
  })
  @sf.panel_group_node(t, fn() { "" }, fn(g) {
    @sf.panel_row_opens_node(g, fn() { @sf.t("web-pages.screen.debug.uninstall") }, fn(from) { debug_apps_open(s, u, from, uninstall=true) }, icon=fn() { "trash" })
  })
}
