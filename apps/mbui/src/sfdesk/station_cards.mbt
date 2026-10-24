// What a station's page shows of the machine and its software (ember web/src/components.tsx MeterDials, Dial;
// cloud/StationCards.tsx Net, HostDetails; Versions.tsx SoftwareList, SoftwareRow; MachineLogins.tsx LoginsSection,
// PastRow; their css.ts), all of it as the core says it.

///|
/// A machine's CPU, memory and disk (MeterDials): each what is left large over its cells, filled as far as is used,
/// its name and its total under them.
fn meter_dials(c : @ui.Ctx, meters : Array[Json]) -> Unit {
  c.box(style=dl_row, fn() {
    for m in meters {
      let mv = Some(m)
      dial(c, text(mv, "big"), text(mv, "unit"), 100 - dial_part(count(mv, "left")), text(mv, "level"), text(mv, "title"), text(mv, "total"))
    }
  })
  |> ignore
}

///|
/// An allowance's windows on its profile's page (QuotaBars, not compact): each what is left large over its cells, as
/// far as is left, its name and when it refills.
fn quota_dials(c : @ui.Ctx, windows : Array[Json]) -> Unit {
  c.box(style=dl_row, fn() {
    for w in windows {
      let wv = Some(w)
      let left = count(wv, "left")
      dial(c, left.to_string(), "%", dial_part(left), text(wv, "level"), text(wv, "label"), text(wv, "refills"))
    }
  })
  |> ignore
}

///|
/// A share kept in 0–100.
fn dial_part(n : Int) -> Int {
  @cmp.maximum(0, @cmp.minimum(100, n))
}

///|
/// A figure large (Dial), ten cells lit as far as `fill` (0–100) in the colour of its level (green while plenty), its
/// name and a quiet note under; the figure the words' ink until it runs low.
fn dial(c : @ui.Ctx, number : String, unit : String, fill : Int, level : String, label : String, note : String) -> Unit {
  let t = @sf.theme()
  let ink = match level {
    "amber" | "warn" => t.p.warn_ink
    "red" => t.p.red
    _ => t.p.green
  }
  let low = level == "amber" || level == "warn" || level == "red"
  let lit = (fill.to_double() / 10.0).round().to_int()
  c.box(style=dl_dial, fn() {
    c.box(style=dl_number_line, fn() {
      c.text(number, style=if low { dl_number.then(@ui.text_style(color=Data(ink))) } else { dl_number }) |> ignore
      c.text(unit, style=dl_unit) |> ignore
    })
    |> ignore
    c.box(style=dl_cells, fn() {
      for i in 0..<10 {
        c.box(style=if i < lit { dl_cell.then(@ui.style(bg=Data(ink))) } else { dl_cell }, fn() {  }) |> ignore
      }
    })
    |> ignore
    c.text(label, style=dl_label) |> ignore
    c.text(if note == "" { " " } else { note }, style=dl_reset) |> ignore
  })
  |> ignore
}

///|
/// This device's connection to it (Net, flush): how it goes and packets lost over its round trip; beside them ↑ over ↓,
/// the speed each way and what went that way since it opened. The figures in the words' ink, one off in its level's.
fn station_net(c : @ui.Ctx, net : Json?) -> Unit {
  c.box(style=nt_row, fn() {
    c.box(style=nt_part, fn() {
      c.box(style=nt_line, fn() {
        c.text(text(net, "path"), style=nt_words) |> ignore
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
            c.text(parts.get(1).unwrap_or(""), style=nt_words) |> ignore
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
fn figure(c : @ui.Ctx, f : Json?) -> Unit {
  c.text(
    text(f, "text"),
    style=match text(f, "level") {
      "amber" => nt_figure.then(@ui.text_style(color=Warn))
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
let software_failed : Map[String, String] = {}

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
  c.box(style=desk_list, fn() {
    for u in updates {
      let v = Some(u)
      let id = text(v, "id")
      let busy = batch || is_doing(core, ["software.update"], [("station", station), ("id", id)])
      software_row(c, core, station, v, manager, busy, beta)
    }
    c.box(style=sw_foot, fn() {
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
        Some(f) => c.text(f, style=sw_failed) |> ignore
        None => ()
      }
      if checked is Some(_) {
        let checking = is_doing(core, ["software.check"], [("station", station)])
        let cid = c.id("software-check/" + station)
        if !checking {
          c.cursor(cid, Hand)
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
  c.box(style=sw_row, fn() {
    c.box(style=sw_mark, fn() {
      if own {
        @sf.drawable(c, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, sw_glyph) |> ignore
      } else {
        @sf.maker_mark(c, "", id, sw_glyph) |> ignore
      }
    })
    |> ignore
    c.box(style=desk_card_text, fn() {
      c.box(style=sw_name_line, fn() {
        c.text(text(v, "name"), style=desk_strong_line) |> ignore
        if text(v, "channel") == "beta" && !switches {
          c.box(style=sw_beta, fn() { c.text(@sf.t("web-main.versions.beta"), style=sw_beta_words) |> ignore }) |> ignore
        }
      })
      |> ignore
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
            c.box(style=sw_switch_line, fn() {
              c.text(@sf.t("web-main.versions.beta"), style=sw_switch_word) |> ignore
              let on = text(v, "channel") == "beta"
              let now = @sf.switch(c, "software-beta/" + station, on, label=@sf.t("web-main.versions.betaStation"), small=true, busy=busy_ch, disabled=busy)
              if now != on {
                software_call(core, station, "software.channel", [("channel", str(if now { "beta" } else { "stable" }))])
              }
            })
            |> ignore
          }
          if has(v, "auto") {
            let busy_auto = is_doing(core, ["software.auto"], [("station", station)])
            c.box(style=sw_switch_line, fn() {
              c.text(@sf.t("web-main.versions.auto"), style=sw_switch_word) |> ignore
              let on = flag(v, "auto")
              let now = @sf.switch(c, "software-auto/" + station, on, label=@sf.t("web-main.versions.auto"), small=true, busy=busy_auto, disabled=busy)
              if now != on {
                software_call(core, station, "software.auto", [("on", Json::boolean(now))])
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=sw_rest, fn() {
      if state == "updating" {
        match field(v, "percent") {
          Some(Number(p, ..)) => @sf.progress(c, Some(p / 100.0), w=Px(sw_progress_w))
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
  })
  |> ignore
}

///|
/// A station page's 登录 (LoginsSection): only the logins done there through still.fail; one under way its card (as in
/// its chat), one ended a row saying how it ended. Nothing when there are none.
fn station_logins(c : @ui.Ctx, core : Core, station : String) -> Unit {
  let t = @sf.theme()
  let view = (core.topic)("machineLogins", { "station": str(station) }).value
  let logins = items(view, "logins")
  if !flag(view, "supported") || logins.length() == 0 {
    return
  }
  let active = logins.filter(fn(l) { flag(Some(l), "active") })
  let past = logins.filter(fn(l) { !flag(Some(l), "active") })
  st_section(c, @sf.t("web-main.logins.title"), description=@sf.t("web-main.logins.lead"), fn() {
    if active.length() > 0 {
      c.box(style=lg_cards, fn() {
        for l in active {
          (core.login_card)(c, station, text(Some(l), "id"), false)
        }
      })
      |> ignore
    }
    if past.length() > 0 {
      c.box(style=desk_list, fn() {
        for l in past {
          let lv = Some(l)
          let by = text(lv, "doneByText")
          let rest = join([by, text(lv, "whenText"), if by == "" { text(lv, "statusText") } else { "" }], " · ")
          let started = if text(lv, "chat") != "" {
            @sf.t("web-main.logins.startedIn", args=[("chat", if text(lv, "chatTitle") == "" { @sf.t("web-main.logins.aChat") } else { text(lv, "chatTitle") })])
          } else {
            ""
          }
          c.box(style=desk_list_row, fn() {
            c.box(style=st_grant_mark, fn() { @sf.icon(c, "key", size=st_grant_glyph, color=t.p.text) |> ignore }) |> ignore
            c.box(style=desk_list_text, fn() {
              c.text(text(lv, "command"), style=desk_list_title) |> ignore
              c.text(join([started, rest], " · "), style=if text(lv, "state") == "failed" { desk_note_bad } else { desk_note })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
}

// ── styles ──────────────────────────────────────────────────────────────

///|
/// The dials in a line, 36 apart (12 when they wrap).
// kept across runs: a value (no field of it changes)
let dl_row : @ui.Style = @ui.css("row gap=S9 align=AStart")

///|
/// A dial (quotaDial: 96 wide at least, 2 apart).
// kept across runs: a value (no field of it changes)
let dl_dial : @ui.Style = @ui.css("min_w=S24 gap=S0_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let dl_number_line : @ui.Style = @ui.css("row gap=SPx align=AEnd")

///|
/// Its figure (quotaDialNumber: the display size, 600, the words' ink while there is plenty).
// kept across runs: a value (no field of it changes)
let dl_number : @ui.TextStyle = @ui.text_style(size=@sf.code_big_size, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dl_unit : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Muted, wrap=false)

///|
/// Its ten cells (quotaDialCells: 3 apart, 4 over and 6 under; a cell 8 by 14, round 2, the neutral ground).
// kept across runs: a value (no field of it changes)
let dl_cells : @ui.Style = @ui.css("row gap=SPx pt=S1 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let dl_cell : @ui.Style = @ui.css("w=S2 h=S3_5 radius=Sm bg=Neutral mr=SPx")

///|
// kept across runs: a value (no field of it changes)
let dl_label : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dl_reset : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// The connection (net: 14 apart, the ui's 13 muted, its figures bold in the words' ink).
// kept across runs: a value (no field of it changes)
let nt_row : @ui.Style = @ui.css("row gap=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nt_part : @ui.Style = @ui.style(gap=S0_5, min_w=Fixed(nt_part_w))

///|
let nt_part_w : Double = 182.0

///|
// kept across runs: a value (no field of it changes)
let nt_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nt_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nt_figure : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
/// ↑ over ↓ (netRates: the speed 9.5 characters wide, its total after it).
// kept across runs: a value (no field of it changes)
let nt_rates : @ui.Style = @ui.css("gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let nt_rate : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nt_speed : @ui.Style = @ui.css("w=S20")

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
let hd_label : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let hd_value : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false, w=Full)

///|
let sw_glyph : Double = 18.0

///|
let sw_progress_w : Double = 60.0

///|
/// A piece of software (softRow: a list's row, its mark, its words, what is done with it at its end).
// kept across runs: a value (no field of it changes)
let sw_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(desk_row_least), px=S3, py=S2_5, gap=S3, align=ACenter, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let sw_mark : @ui.Style = @ui.css("w=S9 h=S9 radius=Full bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sw_name_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_strong_line : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_version_box : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let sw_version : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
/// The test channel's tag beside a version (betaTag).
// kept across runs: a value (no field of it changes)
let sw_beta : @ui.Style = @ui.css("px=S1_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let sw_beta_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L4, weight=Medium, color=AccentText, wrap=false)

///|
/// A switch's word beside it (channel: the ui's 13, on one line).
// kept across runs: a value (no field of it changes)
let sw_switch_word : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

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
let sw_newer : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_failed : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Danger, wrap=false)

///|
/// When it was last checked, checking again beside it (cardFoot).
// kept across runs: a value (no field of it changes)
let sw_foot : @ui.Style = @ui.css("row w=Full px=S3 pt=S2 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sw_foot_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_check : @ui.Style = @ui.css("px=S1")

///|
// kept across runs: a value (no field of it changes)
let sw_check_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_check_lit : @ui.TextStyle = sw_check_words.then(@ui.text_style(color=Fg))

///|
/// Logins under way, their cards 12 apart.
// kept across runs: a value (no field of it changes)
let lg_cards : @ui.Style = @ui.css("w=Full gap=S3 pb=S3")
