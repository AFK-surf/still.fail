// What a station's page shows of the machine and its software (ember web/src/components.tsx MeterDials, Dial;
// cloud/StationCards.tsx Net, HostDetails; Versions.tsx SoftwareList, SoftwareRow; MachineLogins.tsx LoginsSection,
// PastRow; their css.ts), all of it as the core says it.

///|
/// A machine's CPU, memory and disk (MeterDials): each what is left large over its cells, filled as far as is used,
/// its name and its total under them.
fn meter_dials(c : @ui.Ctx, meters : Array[Json]) -> Unit {
  @sf.dials(
    c,
    meters.map(fn(m) {
      let mv = Some(m)
      {
        number: text(mv, "big"),
        unit: text(mv, "unit"),
        fill: 100 - count(mv, "left"),
        level: text(mv, "level"),
        label: text(mv, "title"),
        note: text(mv, "total"),
      }
    }),
  )
}

///|
/// An allowance's windows on its profile's page (QuotaBars, not compact): each what is left large over its cells, as
/// far as is left, its name and when it refills.
pub fn quota_dials(c : @ui.Ctx, windows : Array[Json]) -> Unit {
  @sf.dials(
    c,
    windows.map(fn(w) {
      let wv = Some(w)
      let left = count(wv, "left")
      { number: left.to_string(), unit: "%", fill: left, level: text(wv, "level"), label: text(wv, "label"), note: text(wv, "refills") }
    }),
  )
}

///|
/// This device's connection to it (Net, flush): how it goes and packets lost over its round trip; beside them ↑ over ↓,
/// the speed each way and what went that way since it opened (under them where the line has not the room: no figure
/// cut short, nothing over another). The figures in the words' ink, one off in its level's.
fn station_net(c : @ui.Ctx, net : Json?) -> Unit {
  c.box(style=nt_row, flow=true, line_gap=nt_lines, fn() {
    c.box(style=nt_part, fn() {
      c.box(style=nt_line, fn() {
        c.text(text(net, "path"), style=nt_words_cut) |> ignore
        match field(net, "loss") {
          Some(Object(_)) as f => figure(c, f)
          _ => ()
        }
      })
      |> ignore
      match field(net, "rtt") {
        Some(Object(_)) as f =>
          c.box(style=nt_line, fn() {
            let words = @sf.t("web-pages.stations.latency", args=[("latency", "\u{0}")])
            let parts = words.split("\u{0}").map(fn(p) { p.to_string() }).collect()
            c.text(parts.get(0).unwrap_or(""), style=nt_words) |> ignore
            figure(c, f)
            c.text(parts.get(1).unwrap_or(""), style=nt_words_cut) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
    c.box(style=nt_rates, fn() {
      for way in [("↑", "up", "upTotal"), ("↓", "down", "downTotal")] {
        c.box(style=nt_rate, fn() {
          c.text(way.0, style=nt_words) |> ignore
          c.box(style=nt_speed, fn() { c.text(text(net, way.1), style=nt_figure) |> ignore }) |> ignore
          let total = text(net, way.2)
          c.text(if total == "" { "" } else { @sf.t("web-pages.stations.total", args=[("total", total)]) }, style=nt_words)
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A figure (Figure): bold in the words' ink, in its level's colour when off.
pub fn figure(c : @ui.Ctx, f : Json?) -> Unit {
  c.text(
    text(f, "text"),
    style=match text(f, "level") {
      "amber" => nt_figure.then(@ui.text_style(color=WarnInk))
      "red" => nt_figure.then(@ui.text_style(color=Danger))
      _ => nt_figure
    },
  )
  |> ignore
}

///|
/// The rest of a machine (HostDetails), a quiet row each: its label beside it, quieter.
fn host_details(c : @ui.Ctx, rows : Array[(String, String)]) -> Unit {
  c.box(style=hd_grid, fn() {
    c.box(style=hd_labels, fn() {
      for r in rows {
        c.text(r.0, style=hd_label) |> ignore
      }
    })
    |> ignore
    c.box(style=hd_values, fn() {
      for r in rows {
        c.text(r.1, style=hd_value) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What is asked of a station's software (useSoftware): updating one, checking, its channel, updating by itself; what
/// went wrong with it, by station ("" nothing).
// kept across runs: said as an update fails or is asked again; station_cards_reset empties it
let software_failed : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
fn station_cards_reset() -> Unit {
  software_failed.clear()
}

///|
/// A software call (`software.update`, `.check`, `.channel`, `.auto`), what went wrong said under the list.
fn software_call(core : Core, station : String, name : String, params : Array[(String, Json)]) -> Unit {
  software_failed.remove(station)
  let p = [("station", str(station))]
  p.append(params)
  (core.call)(name, obj(p), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) =>
        software_failed[station] = if name == "software.check" {
          @sf.t("web-main.versions.checkFailedWhy", args=[("error", error_text(e))])
        } else {
          error_text(e)
        }
    }
  })
}

///|
/// A station's software (SoftwareList): a row each (its mark, name and version as the core says it, why it cannot be
/// updated from here under it; what is newer and updating it at its end), the station's own switches (its channel,
/// updating by itself) under its version for its managers; then when it was last checked, with checking again.
fn software_list(c : @ui.Ctx, core : Core, station : String, updates : Array[Json], manager : Bool, beta : Bool) -> Unit {
  if updates.length() == 0 {
    return
  }
  let batch = is_doing(core, ["software.updateAll"], [("station", station)])
  for u in updates {
    let v = Some(u)
    let id = text(v, "id")
    let busy = batch || is_doing(core, ["software.update"], [("station", station), ("id", id)])
    software_row(c, core, station, v, manager, busy, beta)
  }
  // (in lines: checking again after when it was last checked, under it where the line has not the room; why it failed
  // a line of its own)
  c.box(style=sw_foot, flow=true, line_gap=4.0, fn() {
    let checked = match field(Some(updates[0]), "checkedAt") {
      Some(Number(n, ..)) => Some(n)
      _ => None
    }
    c.text(
      match checked {
        None => @sf.t("web-main.versions.checkingVersions")
        Some(n) => @sf.t("web-main.versions.lastChecked", args=[("time", @settings.short_date_time(n))])
      },
      style=sw_foot_words,
    )
    |> ignore
    match software_failed.get(station) {
      Some(f) => c.text(f, style=sw_failed_line) |> ignore
      None => ()
    }
    if checked is Some(_) {
      let checking = is_doing(core, ["software.check"], [("station", station)])
      let cid = c.id("software-check/" + station)
      if !checking {
        if c.clicked(cid) {
          software_call(core, station, "software.check", [])
        }
      }
      c.box(style=sw_check, id=cid, fn() {
        c.text(
          if checking {
            @sf.t("web-main.versions.checking")
          } else {
            @sf.t("web-main.versions.check")
          },
          style=if c.hovered(cid) && !checking { sw_check_lit } else { sw_check_words },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// One piece of software (SoftwareRow).
fn software_row(c : @ui.Ctx, core : Core, station : String, v : Json?, manager : Bool, busy : Bool, beta : Bool) -> Unit {
  let id = text(v, "id")
  let state = text(v, "state")
  let installed = flag(v, "installed")
  let latest = text(v, "latest")
  let button = fn(label : String, primary : Bool) {
    if manager && flag(v, "updatable") {
      if @sf.button(c, label, key="software/" + station + "/" + id, tone=if primary { Primary } else { Plain }, disabled=busy) {
        software_call(core, station, "software.update", [("id", str(id))])
      }
    }
  }
  let own = id == "station"
  let switches = own && manager && ((beta && has(v, "channel")) || has(v, "auto"))
  @sf.item_row(c, fn() {
    c.box(style=sw_mark, fn() {
      if own {
        @sf.drawable(c, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, sw_glyph) |> ignore
      } else {
        @sf.maker_mark(c, "", id, sw_glyph) |> ignore
      }
    })
    |> ignore
    // its name and what is newer with updating it on its first line; its version, why it cannot be updated and its
    // own switches under them, as wide as its words (lines of their own)
    @sf.row_lines(c, spaced=true, fn() {
      c.box(style=sw_name_line.then(sw_name_grow), fn() {
        c.text(text(v, "name"), style=sw_name) |> ignore
        if text(v, "channel") == "beta" && !switches {
          c.box(style=sw_beta, fn() { c.text(@sf.t("web-main.versions.beta"), style=sw_beta_words) |> ignore }) |> ignore
        }
      })
      |> ignore
      c.box(style=sw_rest, fn() {
        if state == "updating" {
          match field(v, "percent") {
            Some(Number(p, ..)) => @sf.progress(c, "software/" + station + "/" + id, Some(p / 100.0), w=Px(sw_progress_w))
            _ => ()
          }
          c.text(text(v, "updatingText"), style=sw_newer) |> ignore
        } else if state == "failed" {
          let fid = c.id("software-failed/" + station + "/" + id)
          c.box(id=fid, fn() { c.text(text(v, "failedText"), style=sw_failed) |> ignore }) |> ignore
          if text(v, "message") != "" {
            @sf.tip(c, "software-failed-tip/" + station + "/" + id, fid, text(v, "message"))
          }
          button(@sf.t("common.retry"), false)
        } else if !installed {
          button(@sf.t("web-main.versions.install"), false)
        } else if flag(v, "newer") && latest != "" {
          c.text(latest, style=sw_newer) |> ignore
          button(@sf.t("web-main.versions.update"), true)
        } else if flag(v, "downgrade") && latest != "" {
          c.text(latest, style=sw_newer) |> ignore
          button(@sf.t("web-main.versions.backToStable"), false)
        } else if text(v, "done") != "" {
          c.text(text(v, "done"), style=sw_newer) |> ignore
        }
      })
      |> ignore
    }, fn() {
      let vid = c.id("software-version/" + station + "/" + id)
      c.box(id=vid, style=sw_version_box, fn() { c.text(text(v, "shownText"), style=sw_version) |> ignore }) |> ignore
      if text(v, "tipText") != "" {
        @sf.tip(c, "software-tip/" + station + "/" + id, vid, text(v, "tipText"))
      }
      if text(v, "note") != "" {
        c.text(text(v, "note"), style=sw_note) |> ignore
      }
      // the station's own: which releases it takes, and whether it takes them by itself
      if switches {
        c.box(style=sw_switches, fn() {
          if beta && has(v, "channel") {
            let busy_ch = is_doing(core, ["software.channel"], [("station", station)])
            // (what it means over it while it is pointed at: Versions.tsx's tips)
            let line = c.id("software-beta-line/" + station)
            c.box(style=sw_switch_line, id=line, taps=false, points=true, fn() {
              c.text(@sf.t("web-main.versions.beta"), style=sw_switch_word) |> ignore
              let on = text(v, "channel") == "beta"
              let now = @sf.switch(c, "software-beta/" + station, on, label=@sf.t("web-main.versions.betaStation"), small=true, busy=busy_ch, disabled=busy)
              if now != on {
                software_call(core, station, "software.channel", [("channel", str(if now { "beta" } else { "stable" }))])
              }
            })
            |> ignore
            @sf.tip(c, "software-beta-tip/" + station, line, @sf.t("web-main.versions.betaNote"))
          }
          if has(v, "auto") {
            let busy_auto = is_doing(core, ["software.auto"], [("station", station)])
            let line = c.id("software-auto-line/" + station)
            c.box(style=sw_switch_line, id=line, taps=false, points=true, fn() {
              c.text(@sf.t("web-main.versions.auto"), style=sw_switch_word) |> ignore
              let on = flag(v, "auto")
              let now = @sf.switch(c, "software-auto/" + station, on, label=@sf.t("web-main.versions.auto"), small=true, busy=busy_auto, disabled=busy)
              if now != on {
                software_call(core, station, "software.auto", [("on", Json::boolean(now))])
              }
            })
            |> ignore
            @sf.tip(c, "software-auto-tip/" + station, line, @sf.t(if flag(v, "idleOnly") {
              "web-main.versions.autoIdleTip"
            } else {
              "web-main.versions.autoTip"
            }))
          }
        })
        |> ignore
      }
    })
  })
}

///|
/// A station page's 登录 (LoginsSection): only the logins done there through still.fail; one under way its card (as in
/// its chat), those ended a row per program (用户定 2026-10-31: a row per try buried the page in 已取消; the core's
/// `tools`) naming it (devin, not its command line), who last logged in to it, from which chat, and how many tries,
/// pressed open to them. Nothing when there are none.
fn station_logins(c : @ui.Ctx, core : Core, station : String) -> Unit {
  let view = (core.topic)("machineLogins", { "station": str(station) }).value
  let logins = items(view, "logins")
  if !flag(view, "supported") || logins.length() == 0 {
    return
  }
  let active = logins.filter(fn(l) { flag(Some(l), "active") })
  let tools = items(view, "tools")
  st_section(c, @sf.t("web-main.logins.title"), description=@sf.t("web-main.logins.lead"), fn() {
    if active.length() > 0 {
      c.box(style=lg_cards, fn() {
        for l in active {
          login_card(c, core, station, text(Some(l), "id"))
        }
      })
      |> ignore
    }
    if tools.length() > 0 {
      @sf.group(c, fn() {
        for tool in tools {
          let tv = Some(tool)
          let name = text(tv, "name")
          let open = st_logins_open.get(station) == Some(name)
          let chat = match text(tv, "chatTitle") {
            "" => ""
            title => "「" + title + "」"
          }
          let said = join([text(tv, "summaryText"), chat].filter(fn(w) { w != "" }), " · ")
          // (none went through and the latest failed: said in red)
          let failed = flag(tv, "failed")
          if @sf.link_row(
              c,
              "login-tool/" + station + "/" + name,
              name,
              value=text(tv, "countText"),
              note=if failed { "" } else { said },
              trouble=if failed { said } else { "" },
              folds=open,
              lead=fn() { st_row_mark(c, "key") },
            ) {
            st_logins_open[station] = if open { "" } else { name }
          }
          if open {
            for l in items(tv, "tries") {
              let lv = Some(l)
              // who ended it says how it ended (张三 取消), else the status does (已取消)
              let by = text(lv, "doneByText")
              @sf.link_row(
                c,
                "",
                text(lv, "whenText"),
                value=if by == "" { text(lv, "statusText") } else { by },
                value_bad=text(lv, "state") == "failed",
                note=match text(lv, "chatTitle") {
                  "" => ""
                  title => "「" + title + "」"
                },
                goes=false,
                lead=fn() { c.box(style=lg_no_mark, fn() {  }) |> ignore },
              )
              |> ignore
            }
          }
        }
      })
    }
  })
}

///|
/// Which program's tries are open on a station's page, by station ("" none: closed again).
let st_logins_open : Map[String, String] = {}

// ── styles ──────────────────────────────────────────────────────────────

///|
/// The connection (net: 14 apart, 8 between its lines where the speeds go under, the ui's 13 muted, its figures bold
/// in the words' ink).
// kept across runs: a value (no field of it changes)
let nt_row : @ui.Style = @ui.css("row gap=S3_5 align=ACenter")

///|
let nt_lines : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let nt_part : @ui.Style = @ui.css("w=Cut gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let nt_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nt_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// The last of a line's words, cut short where the line is (netLine's last child).
// kept across runs: a value (no field of it changes)
let nt_words_cut : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let nt_figure : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
/// ↑ over ↓ (netRates: the speed 9.5 characters wide at least, so the totals line up; its total after it).
// kept across runs: a value (no field of it changes)
let nt_rates : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let nt_rate : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nt_speed : @ui.Style = @ui.css("min_w=S20")

///|
/// The rest of a machine (hostDetails: its labels beside each, 14 apart, rows 8 apart, the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let hd_grid : @ui.Style = @ui.css("row w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let hd_labels : @ui.Style = @ui.css("gap=S2")

///|
// kept across runs: a value (no field of it changes)
let hd_values : @ui.Style = @ui.style(w=@sf.grow, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let hd_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let hd_value : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
let sw_glyph : Double = 18.0

///|
let sw_progress_w : Double = 60.0

///|
// kept across runs: a value (no field of it changes)
let sw_mark : @ui.Style = @ui.css("w=S9 h=S9 radius=Full bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sw_name_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its name taking what its first line leaves what is newer and updating it.
// kept across runs: a value (no field of it changes)
let sw_name_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sw_version_box : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let sw_version : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// The test channel's tag beside a version (betaTag).
// kept across runs: a value (no field of it changes)
let sw_beta : @ui.Style = @ui.css("px=S1_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let sw_beta_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Medium, color=AccentText, wrap=false)

///|
/// A switch's word beside it (channel: the ui's 13, on one line).
// kept across runs: a value (no field of it changes)
let sw_switch_word : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_switches : @ui.Style = @ui.css("row pt=S1_5 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sw_switch_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sw_rest : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sw_newer : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_failed : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, wrap=false)

///|
/// Why checking failed, in the foot: a line of its own, in lines where it is long.
// kept across runs: a value (no field of it changes)
let sw_failed_line : @ui.TextStyle = sw_failed.then(@ui.text_style(wrap=true, w=Full))

///|
/// When it was last checked, checking again beside it (cardFoot).
// kept across runs: a value (no field of it changes)
let sw_foot : @ui.Style = @ui.css("row w=Full px=S3 pt=S2 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sw_foot_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_check : @ui.Style = @ui.css("px=S1")

///|
// kept across runs: a value (no field of it changes)
let sw_check_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_check_lit : @ui.TextStyle = sw_check_words.then(@ui.text_style(color=Fg))

///|
/// Logins under way, their cards 12 apart.
// kept across runs: a value (no field of it changes)
let lg_cards : @ui.Style = @ui.css("w=Full gap=S3 pb=S3")

///|
/// Where a try's mark would be, under its program's: its words where the program's name is.
// kept across runs: a value (no field of it changes)
let lg_no_mark : @ui.Style = @ui.css("w=S4")

///|
// kept across runs: a value (no field of it changes)
let sw_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)
