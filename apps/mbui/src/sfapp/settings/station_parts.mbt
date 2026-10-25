// A station's page, past its machine and what runs on it (Stations.kt StationScreen): its screens (StationScreens),
// what macOS lets a Mac station's helper do (StationPermissions.kt), the variables its agents run with
// (StationAgentEnv, edited in a sheet), what its search finds (StationSearchSection), the workspaces it is in
// (StationWorkspaces), its versions (Versions.kt); and this device's adb lent to its agents (AdbShare.kt's page).

///|
/// A count of the variables' sheets opened: each its own draft (`form`).
let env_form : Ref[Int] = Ref(0)

///|
/// What changes of the versions from here are on their way (Versions.kt's own state: the one updating, checking, the
/// channel and the updating by itself as asked), and what failed: by the station.
priv struct VersionsState {
  updating : Map[String, String]
  checking : Map[String, Bool]
  switching : Map[String, String]
  turning : Map[String, Bool]
  failed : Map[String, String]
}

///|
let versions_state : VersionsState = {
  updating: {},
  checking: {},
  switching: {},
  turning: {},
  failed: {},
}

///|
/// A moment (ms since 1970) as Android's short date and time say it in Chinese (DateFormat.SHORT, SHORT: 2026/9/21
/// 22:13), in the device's local time.
pub fn short_date_time(ms : Double) -> String {
  let day_ms = 86400000.0
  let local = ms + @ui.utc_offset_min(ms).to_double() * 60000.0
  let days = (local / day_ms).floor()
  let minutes = ((local - days * day_ms) / 60000.0).floor().to_int()
  // the day's date from the days since 1970-01-01 (the proleptic Gregorian calendar: H. Hinnant's civil_from_days)
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 })
  let two = fn(n : Int) { if n < 10 { "0" + n.to_string() } else { n.to_string() } }
  "\{y}/\{m}/\{d} \{two(minutes / 60)}:\{two(minutes % 60)}"
}

///|
/// What this device's host says it has for 共享调试 (the app's Android's AdbShare.java, as `adb.phone` answers and
/// "native:adb.phone" says again: supported, developer, wireless, wifi, canSwitch, reads); None until it has said. The
/// native call asking it, and those taps made (adb.switch, adb.open, adb.start), while they are under way.
priv struct AdbHost {
  mut phone : Json?
  mut asking : @ui.NativeCall?
  doing : Array[@ui.NativeCall]
}

///|
let adb_host : AdbHost = { phone: None, asking: None, doing: [] }

///|
fn adb_reset() -> Unit {
  adb_host.phone = None
  adb_host.asking = None
  adb_host.doing.clear()
}

///|
/// The host said what the phone has now (its message on "native:adb.phone": Wireless debugging switched, the app back
/// from Settings): src/sfapp/app.mbt hands it here.
pub fn adb_phone_said(json : String) -> Unit {
  adb_host.phone = Some(@json.parse(json) catch { _ => return })
}

///|
/// The phone as its host last said it, asked once (as the page shows) and taken as it comes; what a tap asked of the
/// host taken too (an answer that changed the phone: asked again).
fn adb_phone(c : @ui.Ctx) -> Json? {
  match adb_host.asking {
    Some(k) =>
      match k.got() {
        Some(Ok(j)) => {
          adb_host.phone = Some(j)
          adb_host.asking = None
        }
        // a host without 共享调试: nothing it can lend
        Some(Err(_)) => {
          adb_host.phone = Some(obj([("supported", Json::boolean(false))]))
          adb_host.asking = None
        }
        None => ()
      }
    None => ()
  }
  let left = []
  for k in adb_host.doing {
    match k.got() {
      Some(r) =>
        if r is Ok(Object(m)) && m.contains("on") {
          adb_host.phone = None
        }
      None => left.push(k)
    }
  }
  adb_host.doing.clear()
  adb_host.doing.append(left)
  if adb_host.phone is None && adb_host.asking is None {
    c.tell("adb-phone", fn() { adb_host.asking = Some(@ui.native_call("adb.phone", obj([]))) })
  }
  adb_host.phone
}

///|
/// What the phone lacks for it, at a row's end (AdbShare.kt Need: 14sp, C.red).
// kept across runs: a value (no field of it changes)
let adb_lacks : @ui.TextStyle = @sf.value.then(@sf.bad)

///|
/// Where a row goes to turn something on, at its end (AdbShare.kt: 14sp, C.link).
// kept across runs: a value (no field of it changes)
let adb_go : @ui.TextStyle = @sf.value.then(@sf.link)

///|
/// What a tap asks of the host (adb.switch, adb.open, adb.start), its answer taken as the page builds (adb_phone).
fn adb_ask(name : String, params : Json) -> Unit {
  adb_host.doing.push(@ui.native_call(name, params))
}

///|
/// The notifications' words, the app's own (AdbShare.java fills `{name}`, `{n}`, `{error}`).
fn adb_texts() -> Json {
  let m : Map[String, Json] = {}
  for k in [
      "title", "notify.title", "stop", "pair.channel", "code", "pair.ask", "pair.auto", "typeCode", "enterCode", "connecting",
      "connected", "connected.left", "notPaired", "pair.popped", "off", "attaching", "pairing", "paired", "pairFailed",
      "shareFailed",
    ] {
    let key = "android-misc.adb." + k
    m[key] = Json::string(tr(key))
  }
  Json::object(m)
}

///|
/// A station's 共享调试 page (AdbShareScreen): this device's adb lent to the station's agents, how it stands (the
/// core's `adbShare`), what the phone needs for it (as its host says: adb_phone), pairing the first time, and the app
/// turning Wireless debugging on itself from then on. The lending itself is the core's and the host's (AdbShare.java);
/// this page shows and asks (`adb.stop`, `adb.pair`, `adb.grant`; the host's adb.start, adb.switch, adb.open).
fn adb_page(c : @ui.Ctx, core : Core, here : Here, address : String) -> Unit {
  let t = @sf.theme()
  let name = match station_of(core, here, address) {
    Some(s) => text(Some(s), "name")
    None => station_name(address)
  }
  let view = (core.topic)("adbShare", Map([])).value
  let sharing = flag(view, "sharing")
  let there = sharing && text(view, "station") == address
  let elsewhere = sharing && text(view, "station") != address
  let phone = adb_phone(c)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    nav_bar(c, core, "Station", tr("android-misc.adb.title"), sub=fn() {
      c.text(name, size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore
    })
    let blocks : Array[() -> Unit] = [
      fn() { gap(c, 12.0) },
      fn() {
        c.box(w=Fill(1.0), padx=24.0, pb=10.0, fn() {
          c.text(fill("android-misc.adb.about", [("name", name)]), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0)
          |> ignore
        })
        |> ignore
      },
    ]
    if phone is None {
      // (until the host has said what the phone has: the rest as it comes)
      ()
    } else if !flag(phone, "supported") && !there {
      blocks.push(fn() {
        list_card(c, fn() {
          list_row(c, fn() {
            c.text(tr("android-misc.adb.unsupported"), size=t.t.body, color=t.p.muted, w=Fill(1.0), line=21.0) |> ignore
          })
          |> ignore
        })
      })
    } else {
      blocks.push(fn() {
        list_card(c, fn() {
          // lent or not, as settings' switches are; what it is doing under the title
          if list_row(c, key="adb-switch", fn() {
              c.box(w=Fill(1.0), fn() {
                c.text(tr("android-misc.adb.title"), size=t.t.body, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                let stopped = if !sharing { text(view, "message") } else { "" }
                let sub = if there {
                  adb_state(c, view, (core.now)())
                } else if elsewhere {
                  tr("android-misc.adb.elsewhere")
                } else if stopped != "" {
                  stopped
                } else {
                  tr("android-misc.adb.hour")
                }
                let adb = text(view, "adb")
                c.text(
                  sub,
                  size=t.t.meta,
                  color=if there && (adb == "missing" || adb == "failed") { t.p.red } else { t.p.muted },
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
              let adb = text(view, "adb")
              doing_mark(c, there && (text(view, "phase") != "offered" || adb == "" || adb == "connecting"), None)
              switch(c, "adb-switch", there)
            }) {
            if there {
              act(core, tr("android-misc.adb.stopWhat"), "adb.stop", obj([]))
            } else {
              // the pairing code is typed into a notification: they are asked for once, as the lending starts
              if @ui.notice_permission() != "granted" {
                @ui.notice_ask() |> ignore
              }
              adb_ask(
                "adb.start",
                obj([("station", str(address)), ("name", str(name)), ("texts", adb_texts())]),
              )
            }
          }
          if there {
            match opt_text(view, "serial") {
              Some(serial) if text(view, "adb") == "connected" =>
                list_row(c, fn() {
                  row_title(c, tr("android-misc.adb.agentsUse"))
                  mono(c, "adb -s " + serial, size=13.0, color=t.p.muted)
                })
                |> ignore
              _ => ()
            }
            // what the station said, when it says more than the line above
            let said = text(view, "message")
            let line = adb_state(c, view, (core.now)())
            if text(view, "adb") != "connected" && said != "" && said != line && !line.has_suffix(said) {
              list_row(c, fn() {
                c.text(said, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              })
              |> ignore
            }
          }
        })
      })
      // what the phone needs, and whether it has it
      blocks.push(fn() { section_header(c, tr("android-misc.adb.phone"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          let need = fn(title : String, ok : Bool, value : String) {
            list_row(c, fn() {
              row_title(c, title)
              c.text(value, style=if ok { @sf.value } else { adb_lacks }) |> ignore
            })
            |> ignore
          }
          let developer = flag(phone, "developer")
          need(
            tr("android-misc.adb.developer"),
            developer,
            if developer {
              tr("android-misc.adb.on")
            } else {
              tr("android-misc.adb.developer.how")
            },
          )
          let wifi = flag(phone, "wifi")
          need(
            tr("android-misc.adb.wifi"),
            wifi,
            if wifi {
              tr("android-misc.adb.wifi.on")
            } else {
              tr("android-misc.adb.wifi.needed")
            },
          )
          let wireless = flag(phone, "wireless")
          let can_switch = flag(phone, "canSwitch")
          if list_row(c, key="adb-wireless", fn() {
              row_title(c, tr("android-misc.adb.wireless"))
              c.text(
                if wireless {
                  tr("android-misc.adb.on")
                } else if can_switch {
                  tr("android-misc.adb.wireless.turnOn")
                } else {
                  tr("android-misc.adb.wireless.settings")
                },
                style=if wireless { @sf.value } else { adb_go },
              )
              |> ignore
            }) {
            if !wireless && can_switch {
              adb_ask("adb.switch", obj([]))
            } else {
              adb_ask("adb.open", obj([("what", str("wireless"))]))
            }
          }
        })
      })
      if there && text(view, "adb") == "unpaired" {
        let busy = is_doing(core, ["adb.pair"], [])
        let open = has(view, "pairPort")
        let reads = flag(phone, "reads")
        blocks.push(fn() { section_header(c, tr("android-misc.adb.pair.title"), start=S6) })
        blocks.push(fn() {
          list_card(c, fn() {
            // the code read off the dialog by itself, where the person turns that on (AdbCodeReader)
            if list_row(c, key="adb-reader", fn() {
                row_lines(c, tr("android-misc.adb.reader.title"), tr("android-misc.adb.reader.note"), wrap_sub=true)
                c.text(
                  if reads {
                    tr("android-misc.adb.on")
                  } else {
                    tr("android-misc.adb.reader.turnOn")
                  },
                  style=if reads { @sf.value } else { adb_go },
                )
                |> ignore
              }) {
              adb_ask("adb.open", obj([("what", str("reader"))]))
            }
            // the pairing dialog, beside the app where the screen splits
            if list_row(c, key="adb-pair-open", fn() {
                row_lines(
                  c,
                  tr("android-misc.adb.pair.open"),
                  tr(
                    if reads {
                      "android-misc.adb.pair.open.auto"
                    } else {
                      "android-misc.adb.pair.open.note"
                    },
                  ),
                  wrap_sub=true,
                )
                c.text(tr("android-misc.adb.pair.go"), style=adb_go) |> ignore
              }) {
              adb_ask("adb.open", obj([("what", str("wireless")), ("beside", Json::boolean(true))]))
            }
            // split screen: the code typed here
            if list_row(c, key=if open && !busy { "adb-pair-here" } else { "" }, fn() {
                row_lines(
                  c,
                  tr("android-misc.adb.pair.here"),
                  tr(if open { "android-misc.adb.pair.here.split" } else { "android-misc.adb.pair.here.wait" }),
                  title_color=if open { t.p.text } else { t.p.subtle },
                  wrap_sub=true,
                )
                doing_mark(c, busy, failed_of(core, ["adb.pair"], []))
              }) {
              ask(
                tr("android-misc.adb.pair.ask"),
                "",
                tr("android-misc.adb.code"),
                tr("android-misc.adb.pair.action"),
                hint=tr("android-misc.adb.pair.hint"),
                fn(code) {
                  let digits = StringBuilder()
                  for ch in code {
                    if ch >= '0' && ch <= '9' {
                      digits.write_char(ch)
                    }
                  }
                  act(
                    core,
                    tr("android-misc.adb.pair.action"),
                    "adb.pair",
                    obj([("code", str(digits.to_string()))]),
                    done=tr("android-misc.adb.paired"),
                  )
                },
              )
            }
          })
        })
      }
      // from then on: the app turns Wireless debugging on itself, once the station's adb grants it
      if there && text(view, "adb") == "connected" && !flag(phone, "canSwitch") {
        let busy = is_doing(core, ["adb.grant"], [])
        blocks.push(fn() { section_header(c, tr("android-misc.adb.later"), start=S6) })
        blocks.push(fn() {
          list_card(c, fn() {
            if list_row(c, key=if busy { "" } else { "adb-grant" }, fn() {
                row_lines(c, tr("android-misc.adb.grant.title"), tr("android-misc.adb.grant.note"), wrap_sub=true)
                doing_mark(c, busy, failed_of(core, ["adb.grant"], []))
                switch(c, "adb-grant", false)
              }) {
              act(
                core,
                tr("android-misc.adb.grantWhat"),
                "adb.grant",
                obj([]),
                done=tr("android-misc.adb.granted"),
                then=fn(_) { adb_host.phone = None },
              )
            }
          })
        })
      }
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), padx=24.0, pt=16.0, fn() {
        c.text(tr("android-misc.adb.warning"), size=t.t.caption, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
      })
      |> ignore
    })
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "adb/" + address, blocks)
  })
  |> ignore
}

///|
/// How the lending stands, in a line (AdbShare.kt state): lent, the minutes left of it as the time of day `now` has
/// them, said again as they change (AdbShare.kt: its `now` every 20 s).
fn adb_state(c : @ui.Ctx, view : Json?, now : Double) -> String {
  let adb = text(view, "adb")
  if text(view, "phase") != "offered" {
    return match opt_text(view, "message") {
      Some(m) => fill("android-misc.adb.connecting.why", [("why", m)])
      None => tr("android-misc.adb.connecting")
    }
  }
  match adb {
    "connected" =>
      match field(view, "until") {
        Some(Number(until, ..)) => {
          let left = until - now
          let n = if left > 0.0 { (left / 60000.0).floor() } else { 0.0 }
          // the next minute's change
          if left > 0.0 {
            c.wake_in(left - n * 60000.0 + 1.0, later=true)
          }
          fill("android-misc.adb.connected.left", [("n", n.to_int().to_string())])
        }
        _ => tr("android-misc.adb.connected")
      }
    "unpaired" => tr("android-misc.adb.unpaired")
    "unauthorized" => tr("android-misc.adb.unauthorized")
    "off" => tr("android-misc.adb.off")
    "missing" => tr("android-misc.adb.missing")
    "failed" => tr("android-misc.adb.failed")
    _ => tr("android-misc.adb.attaching")
  }
}

///|
/// The station at `address` as the workspace's `stations` has it.
pub fn station_of(core : Core, here : Here, address : String) -> Json? {
  match stations_of(core, here).value {
    Some(Array(a)) => a.iter().find_first(fn(x) { text(Some(x), "station") == address })
    _ => None
  }
}
