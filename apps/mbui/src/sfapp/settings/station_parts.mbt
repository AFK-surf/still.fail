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
  phone : @signals.Signal[Json?]
  mut asking : @ui.NativeCall?
  doing : Array[@ui.NativeCall]
}

///|
let adb_host : AdbHost = { phone: @signals.signal(None), asking: None, doing: [] }

///|
fn adb_reset() -> Unit {
  adb_host.phone.set(None)
  adb_host.asking = None
  adb_host.doing.clear()
}

///|
/// The host said what the phone has now (its message on "native:adb.phone": Wireless debugging switched, the app back
/// from Settings): src/sfapp/app.mbt hands it here.
pub fn adb_phone_said(json : String) -> Unit {
  adb_host.phone.set(Some(@json.parse(json) catch { _ => return }))
}

///|
/// The phone as its host last said it, asked once (as the page shows) and taken as it comes; what a tap asked of the
/// host taken too (an answer that changed the phone: asked again).
fn adb_phone(c : @ui.Ctx) -> Json? {
  match adb_host.asking {
    Some(k) =>
      match k.got() {
        Some(Ok(j)) => {
          adb_host.phone.set(Some(j))
          adb_host.asking = None
        }
        // a host without 共享调试: nothing it can lend
        Some(Err(_)) => {
          adb_host.phone.set(Some(obj([("supported", Json::boolean(false))])))
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
          adb_host.phone.set(None)
        }
      None => left.push(k)
    }
  }
  adb_host.doing.clear()
  adb_host.doing.append(left)
  if adb_host.phone.get() is None && adb_host.asking is None {
    c.tell("adb-phone", fn() { adb_host.asking = Some(@ui.native_call("adb.phone", obj([]))) })
  }
  adb_host.phone.get()
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
pub fn adb_texts() -> Json {
  let m : Map[String, Json] = {}
  for k in [
      "title", "notify.title", "notify.chats", "notify.on", "notify.idle", "stop", "turnOff", "pair.channel", "code", "pair.ask", "pair.auto", "typeCode", "enterCode", "connecting",
      "connected", "connected.left", "notPaired", "pair.popped", "off", "attaching", "pairing", "paired", "pairFailed",
      "shareFailed",
    ] {
    let key = "android-misc.adb." + k
    m[key] = Json::string(tr(key))
  }
  Json::object(m)
}

///|
/// The one thing to do next on 共享调试's page: what it is (`sub` how, where that needs saying), and at the row's end
/// where a tap goes (`go`, "" none) or the call it makes under way (`doing`); what the tap does (`act`: adb_do).
priv struct AdbStep {
  title : String
  sub : String
  go : String
  doing : String
  act : String
}

///|
/// The lendings chats' grants made (`adbShare`'s `lends`: each station's, how its adb holds the phone).
pub fn adb_lends(all : Json?) -> Array[Json] {
  match field(all, "lends") {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// The phone's lending to the station at `address`, as `adbShare` says the one it names at its top: that one, or the
/// station's among its `lends` (a phone granted to chats on two stations is lent to both; what the topic's top says is
/// only the one a person has something to do for), with the ports the app found for adbd (the phone's, the same for
/// each). Not lent there: the topic as it is.
pub fn adb_lend_view(all : Json?, address : String) -> Json? {
  if flag(all, "sharing") && text(all, "station") == address {
    return all
  }
  match adb_lends(all).iter().find_first(fn(l) { text(Some(l), "station") == address }) {
    Some(Object(l)) => {
      let out : Map[String, Json] = {}
      for k, v in l {
        out[k] = v
      }
      out["sharing"] = Json::boolean(true)
      for key in ["connectPort", "pairPort", "refusedPort"] {
        match field(all, key) {
          Some(v) => out[key] = v
          None => ()
        }
      }
      Some(Json::object(out))
    }
    _ => all
  }
}

///|
/// A step for adb_next to say.
fn adb_step(title : String, sub? : String = "", go? : String = "", doing? : String = "", act? : String = "") -> AdbStep? {
  Some({ title, sub, go, doing, act })
}

///|
/// What is next for the lending, as the phone has it and the station holds it: the first thing the phone lacks, else
/// what the station's adb waits on (pairing, the phone's 允许); None while nothing is asked of the person (lent and
/// connected, connecting, adb failing and tried again by itself).
fn adb_next(view : Json?, phone : Json?, there : Bool) -> AdbStep? {
  let adb = text(view, "adb")
  if !flag(phone, "developer") {
    return adb_step(tr("android-misc.adb.step.developer"), sub=tr("android-misc.adb.developer.how"))
  }
  if !flag(phone, "wifi") {
    return adb_step(tr("android-misc.adb.step.wifi"))
  }
  if !flag(phone, "wireless") || (there && adb == "off") {
    let can_switch = flag(phone, "canSwitch")
    return adb_step(
      tr("android-misc.adb.step.wireless"),
      go=tr(if can_switch { "android-misc.adb.wireless.turnOn" } else { "android-misc.adb.wireless.settings" }),
      act=if can_switch { "switch" } else { "wireless" },
    )
  }
  if !there || text(view, "phase") != "offered" {
    return None
  }
  match adb {
    "unpaired" if has(view, "pairPort") && flag(phone, "reads") => adb_step(tr("android-misc.adb.step.reading"))
    "unpaired" if has(view, "pairPort") =>
      adb_step(tr("android-misc.adb.enterCode"), go=tr("android-misc.adb.pair.action"), doing="adb.pair", act="code")
    "unpaired" =>
      adb_step(tr("android-misc.adb.pair.open"), sub=tr("android-misc.adb.step.pairHow"), go=tr("android-misc.adb.pair.go"), act="pairing")
    "unauthorized" => adb_step(tr("android-misc.adb.unauthorized"))
    "missing" => adb_step(tr("android-misc.adb.step.install"))
    _ => None
  }
}

///|
/// A step's tap (AdbStep `act`): Wireless debugging turned on by the app (`switch`) or in Settings (`wireless`), the
/// pairing dialog opened beside the app (`pairing`), the code asked for and paired with (`code`).
fn adb_do(core : Core, what : String, station? : String = "") -> Unit {
  match what {
    "switch" => adb_ask("adb.switch", obj([]))
    "wireless" => adb_ask("adb.open", obj([("what", str("wireless"))]))
    "pairing" => adb_ask("adb.open", obj([("what", str("wireless")), ("beside", Json::boolean(true))]))
    "code" =>
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
            obj([("code", str(digits.to_string())), ("station", str(station))]),
            done=tr("android-misc.adb.paired"),
          )
        },
      )
    _ => ()
  }
}

///|
/// Lent to the agents of the station at `address` (`name`, its notification's): the notifications allowed first (the
/// pairing code is typed into one), Wireless debugging turned on by the app where it may and it is off; the lending
/// itself the host's (adb.start: the core's, as it has it).
pub fn adb_lend(address : String, name : String) -> Unit {
  if @ui.notice_permission() != "granted" {
    @ui.notice_ask() |> ignore
  }
  adb_switch_on()
  adb_ask("adb.start", obj([("station", str(address)), ("name", str(name)), ("texts", adb_texts())]))
}

///|
/// Wireless debugging turned on by the app, where it is off and the app may (adb.grant let it).
fn adb_switch_on() -> Unit {
  let phone = adb_host.phone.get()
  if !flag(phone, "wireless") && flag(phone, "canSwitch") {
    adb_ask("adb.switch", obj([]))
  }
}

///|
/// Whether a tap asked of the host (adb.start, adb.switch…) is still on its way.
pub fn adb_asking() -> Bool {
  !adb_host.doing.is_empty()
}

///|
/// What this device can do for 共享调试 from where a chat shows it (@sfbase's adb_link_card), as its host says the
/// phone stands: not known yet; lent from there (the phone has all it takes, or the app turns Wireless debugging on
/// itself); first what the phone lacks, a step only the system's settings take (its page says how); or nothing (a host
/// without it, an Android before 11), why.
pub(all) enum AdbReady {
  AdbUnknown
  AdbLends
  AdbLacks(String)
  AdbCannot(String)
} derive(Eq)

///|
/// What the phone has for 共享调试, as a chat's card of it goes by (AdbReady).
pub fn adb_ready(c : @ui.Ctx) -> AdbReady {
  let phone = adb_phone(c)
  if phone is None {
    return AdbUnknown
  }
  if !flag(phone, "supported") {
    return AdbCannot(tr("android-misc.adb.unsupported"))
  }
  match adb_next(None, phone, false) {
    Some(step) if step.act != "switch" => AdbLacks(step.title)
    _ => AdbLends
  }
}

///|
/// A port the app found for adbd on the phone (`adbShare`'s `connectPort`, `pairPort`), at its row's end: the number,
/// marked when a tunnel found nothing there (`refusedPort`); `none` without one.
fn adb_port(view : Json?, key : String, none : String) -> (String, Bool) {
  match field(view, key) {
    Some(Number(n, ..)) => {
      let port = n.to_int().to_string()
      match field(view, "refusedPort") {
        Some(Number(r, ..)) if r == n => (fill("android-misc.adb.port.refused", [("port", port)]), false)
        _ => (port, true)
      }
    }
    _ => (none, key != "connectPort")
  }
}

///|
/// A station's 共享调试 page (AdbShareScreen): this device's adb lent to the station's agents, and only what is of use
/// for it: how it stands and why (the core's `adbShare`, the station's word on it), the one thing to do next
/// (adb_next), and what the phone has for it (as its host says: adb_phone) with the ports the app found for adbd. The
/// lending itself is the core's and the host's (AdbShare.java); this page shows and asks (`adb.stop`, `adb.pair`,
/// `adb.grant`; the host's adb.start, adb.switch, adb.open).
fn adb_page(c : @ui.Ctx, core : Core, here : Here, address : String) -> Unit {
  if address == "" {
    adb_settings(c, core, here)
    return
  }
  let t = @sf.theme()
  let name = match station_of(core, here, address) {
    Some(s) => text(Some(s), "name")
    None => station_name(address)
  }
  let all = (core.topic)("adbShare", Map([])).value
  let view = adb_lend_view(all, address)
  let sharing = flag(view, "sharing")
  let there = sharing && text(view, "station") == address
  // (lent with the app's switch from before grants, to one station: another's now)
  let elsewhere = !there && flag(all, "sharing") && text(all, "station") != address && adb_lends(all).is_empty()
  // (lent there for chats' grants, not with this page's switch)
  let granted = adb_lends(all).iter().any(fn(l) { text(Some(l), "station") == address })
  // (a device with no adb to lend, as the core says: so at once, not after asking its host)
  let card = (core.topic)("adbCard", { "station": str(address) }).value
  let cannot = card is Some(_) && !flag(card, "lendable") && !there
  let phone = if cannot { None } else { adb_phone(c) }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    nav_bar(c, core, "Station", tr("android-misc.adb.title"), sub=fn() {
      c.text(name, size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore
    })
    let blocks : Array[() -> Unit] = [fn() { gap(c, 12.0) }]
    if cannot || (phone is Some(_) && !flag(phone, "supported") && !there) {
      let why = if cannot { text(card, "line") } else { tr("android-misc.adb.unsupported") }
      blocks.push(fn() {
        list_card(c, fn() {
          list_row(c, fn() {
            c.text(why, size=t.t.body, color=t.p.muted, w=Fill(1.0), line=21.0) |> ignore
          })
          |> ignore
        })
      })
    } else if phone is None {
      // (until the host has said what the phone has: the rest as it comes)
      ()
    } else {
      // how it stands, and why
      blocks.push(fn() {
        list_card(c, fn() {
          // lent for chats' grants: not this page's to stop (its adb.stop ends only a lending its switch made, 2026-10-30:
          // the switch did nothing), so no switch, and settings' 共享调试, where its switch and the grants are, a tap away
          if granted {
            if list_row(c, key="adb-manage", fn() {
                row_title(c, tr("android-misc.adb.title"))
                let adb = text(view, "adb")
                doing_mark(c, text(view, "phase") != "offered" || adb == "" || adb == "connecting", None)
                c.text(tr("android-misc.adb.manage"), style=adb_go) |> ignore
              }) {
              (core.push)(AdbShare(""))
            }
          } else if list_row(c, key="adb-switch", fn() {
              row_title(c, tr("android-misc.adb.title"))
              let adb = text(view, "adb")
              doing_mark(c, there && (text(view, "phase") != "offered" || adb == "" || adb == "connecting"), None)
              switch(c, "adb-switch", there)
            }) {
            if there {
              act(core, tr("android-misc.adb.stopWhat"), "adb.stop", obj([]))
            } else {
              adb_lend(address, name)
            }
          }
          // how it stands, a row of its own (what the station says of it is as long as it is)
          let stopped = if !sharing { text(view, "message") } else { "" }
          let state = if there {
            adb_state(c, view, (core.now)())
          } else if elsewhere {
            tr("android-misc.adb.elsewhere")
          } else if stopped != "" {
            stopped
          } else {
            tr("android-misc.adb.hour")
          }
          let adb = text(view, "adb")
          list_row(c, fn() {
            c.text(
              state,
              size=t.t.meta,
              color=if there && (adb == "missing" || adb == "failed") { t.p.red } else { t.p.muted },
              w=Fill(1.0),
              line=18.0,
            )
            |> ignore
          })
          |> ignore
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
            // why, as the station said it, when it says more than the line above
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
      // the one thing to do next
      match adb_next(view, phone, there) {
        Some(step) => {
          blocks.push(fn() { section_header(c, tr("android-misc.adb.next"), start=S6) })
          blocks.push(fn() {
            list_card(c, fn() {
              let busy = step.doing != "" && is_doing(core, [step.doing], [])
              if list_row(c, key=if step.act != "" && !busy { "adb-next" } else { "" }, fn() {
                  row_lines(c, step.title, step.sub, wrap_title=true, wrap_sub=true, end=fn() {
                    if step.doing != "" && (busy || failed_of(core, [step.doing], []) is Some(_)) {
                      doing_mark(c, busy, failed_of(core, [step.doing], []))
                    } else if step.go != "" {
                      c.text(step.go, style=adb_go) |> ignore
                    }
                  })
                }) {
                adb_do(core, step.act, station=address)
              }
            })
          })
        }
        None => ()
      }
      // what the phone lacks for it, and what can be turned on for it: what is on and has nothing to tap is not said
      let lacks : Array[(String, String)] = []
      if !flag(phone, "developer") {
        lacks.push((tr("android-misc.adb.developer"), tr("android-misc.adb.offValue")))
      }
      if !flag(phone, "wifi") {
        lacks.push((tr("android-misc.adb.wifi"), tr("android-misc.adb.wifi.off")))
      }
      if !flag(phone, "wireless") {
        lacks.push((tr("android-misc.adb.wireless"), tr("android-misc.adb.offValue")))
      }
      if there {
        // (a port only where adbd is not found at it: the pairing one is the next step's while it is wanted)
        let (connect, found) = adb_port(view, "connectPort", tr("android-misc.adb.port.none"))
        if !found {
          lacks.push((tr("android-misc.adb.port.connect"), connect))
        }
        let (pair, open) = adb_port(view, "pairPort", tr("android-misc.adb.port.closed"))
        if !open {
          lacks.push((tr("android-misc.adb.port.pair"), pair))
        }
      }
      // the code read off the pairing dialog by itself, where the person turns that on (AdbCodeReader)
      let reader = there && text(view, "adb") == "unpaired" && !flag(phone, "reads")
      // from then on: the app turns Wireless debugging on itself, once the station's adb grants it
      let grant = there && text(view, "adb") == "connected" && !flag(phone, "canSwitch")
      if !lacks.is_empty() || reader || grant {
        blocks.push(fn() { section_header(c, tr("android-misc.adb.phone"), start=S6) })
        blocks.push(fn() {
          list_card(c, fn() {
            for lack in lacks {
              list_row(c, fn() {
                row_title(c, lack.0)
                c.text(lack.1, style=adb_lacks) |> ignore
              })
              |> ignore
            }
            if reader {
              // (where it is in Accessibility, and why it may be grey: a phone's makers put an app's services
              // apart, 2026-10-30: 「跳转的无障碍看不到自动填的选项」)
              if list_row(c, key="adb-reader", fn() {
                  row_lines(c, tr("android-misc.adb.reader.title"), tr("android-misc.adb.reader.note"), wrap_sub=true, end=fn() {
                    c.text(tr("android-misc.adb.reader.turnOn"), style=adb_go) |> ignore
                  })
                }) {
                adb_ask("adb.open", obj([("what", str("reader"))]))
              }
            }
            if grant {
              let busy = is_doing(core, ["adb.grant"], [])
              if list_row(c, key=if busy { "" } else { "adb-grant" }, fn() {
                  // (its switch across the row's middle: a round control out of the row's corners)
                  row_lines(c, tr("android-misc.adb.grant.title"), "", wrap_title=true)
                  doing_mark(c, busy, failed_of(core, ["adb.grant"], []))
                  switch(c, "adb-grant", false)
                }) {
                act(
                  core,
                  tr("android-misc.adb.grantWhat"),
                  "adb.grant",
                  obj([]),
                  done=tr("android-misc.adb.granted"),
                  then=fn(_) { adb_host.phone.set(None) },
                )
              }
            }
          })
        })
      }
    }
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

///|
/// Settings' 共享调试 (docs/adb-share.md, 2026-10-29: as the vault's page): a chat's agent asks for the phone and its
/// person grants it on the card in the chat. Here: on a phone, its switch (2026-10-30: off at first, on until turned
/// off, `adb.on`), lent to no chat while off; the chats it is granted to now, each taken back with 收回; the requests
/// waiting; and what the phone lacks for it (本机设置).
///|
/// Settings' 共享调试 as a whole, the page's room.
// kept across runs: a value (no field of it changes)
let adb_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What a row says when there is nothing to list, or nothing to lend (muted, the row's width).
// kept across runs: a value (no field of it changes)
let adb_quiet : @ui.TextStyle = @ui.text_style(size=Body, color=Muted, w=Full)

fn adb_settings(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let view = (core.topic)("adbShare", Map([])).value
  let phone = adb_phone(c)
  let grants = match field(view, "grants") {
    Some(Array(a)) => a
    _ => []
  }
  let live = grants.filter(fn(g) { text(Some(g), "status") == "granted" })
  let waiting = grants.filter(fn(g) { text(Some(g), "status") == "pending" })
  // a station by its name, as the workspace's stations have it
  let named = fn(address : String) {
    match station_of(core, here, address) {
      Some(st) => text(Some(st), "name")
      None => station_name(address)
    }
  }
  c.box(style=adb_whole, fn() {
    // (what it is, in the title's ⓘ: not a card of words over the page)
    nav_bar(c, core, tr("android-settings.title"), tr("android-misc.adb.title"), about=tr("android-misc.adb.chats.about"))
    let blocks : Array[() -> Unit] = [fn() { gap(c, 12.0) }]
    // the phone's switch: only a phone lends
    if flag(phone, "supported") {
      blocks.push(fn() {
        list_card(c, fn() {
          let on = flag(view, "on")
          // (the switch in the row's middle, off its corners, as settings' switches are)
          if list_row(c, key="adb-on", fn() {
              c.box(style=fill_words, fn() { row_lines(c, tr("android-misc.adb.title"), tr("android-misc.adb.on.note"), wrap_sub=true) })
              |> ignore
              switch(c, "adb-on-switch", on)
            }) {
            // (turned on: the notification it shows allowed, and Wireless debugging on where the app may)
            if !on {
              if @ui.notice_permission() != "granted" {
                @ui.notice_ask() |> ignore
              }
              adb_switch_on()
            }
            act(core, tr(if on { "android-misc.adb.turnOff" } else { "android-misc.adb.step.on" }), "adb.on", obj([("on", Json::boolean(!on))]))
          }
        })
      })
    }
    // 默认最长授权: the longest a chat's grant of the phone may last (as the vault's: pressed, the library's choices)
    blocks.push(fn() {
      list_card(c, fn() {
        let lasts = if text(view, "lasts") == "hour" { "hour" } else { "chat" }
        if @sf.link_row(c, "adb-lasts", tr("android-misc.adb.lasts"), note=tr("android-settings.vault.lasts." + lasts), tail=fn() {
            doing_mark(c, is_doing(core, ["adb.setLasts"], []), failed_of(core, ["adb.setLasts"], []))
          }) {
          @sf.pick(
            tr("android-misc.adb.lasts"),
            ["hour", "chat"].map(fn(l) { @sf.choice(l, tr("android-settings.vault.lasts." + l), note=tr("android-settings.vault.lasts." + l + "Detail")) }),
            lasts,
            fn(picked) {
              if picked != lasts {
                act(core, tr("android-misc.adb.lasts"), "adb.setLasts", obj([("lasts", str(picked))]))
              }
            },
            from=Of(c.id("adb-lasts")),
          )
        }
      })
    })
    // the stations its grants lend it to, each with how its adb holds the phone, and its own page (pairing, what is
    // next) a tap away (2026-10-30: a phone granted to chats on two stations, one of them not paired with it, and
    // nothing here said which, nor led to where it is paired)
    let stations : Array[String] = []
    for g in live {
      let st = text(Some(g), "station")
      if st != "" && !stations.contains(st) {
        stations.push(st)
      }
    }
    for l in adb_lends(view) {
      let st = text(Some(l), "station")
      if st != "" && !stations.contains(st) {
        stations.push(st)
      }
    }
    if !stations.is_empty() {
      blocks.push(fn() { section_header(c, tr("android-misc.adb.stations"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          for st in stations {
            let lent = adb_lend_view(view, st)
            let there = flag(lent, "sharing") && text(lent, "station") == st
            let state = if there { adb_state(c, lent, (core.now)()) } else { tr("android-misc.adb.stations.notLent") }
            if @sf.link_row(c, "adb-station/" + st, named(st), note=state) {
              (core.push)(AdbShare(st))
            }
          }
        })
      })
    }
    // the chats it is lent to now, each taken back here
    blocks.push(fn() { section_header(c, tr("android-misc.adb.chats.live"), start=S6) })
    blocks.push(fn() {
      list_card(c, fn() {
        if live.is_empty() {
          list_row(c, fn() {
            c.text(tr("android-misc.adb.chats.none"), style=adb_quiet) |> ignore
          })
          |> ignore
        }
        for g in live {
          let g = Some(g)
          let station = text(g, "station")
          let request = text(g, "id")
          let scope = if text(g, "scope") == "hour" { "hour" } else { "chat" }
          let busy = is_doing(core, ["adb.revoke"], [("request", request)])
          if list_row(c, key=if busy { "" } else { "adb-revoke/" + request }, fn() {
              row_lines(c, text(g, "reason"), named(station) + " · " + tr("android-settings.vault.scope." + scope), wrap_title=true, end=fn() {
                if busy {
                  doing_mark(c, true, None)
                } else {
                  c.text(tr("android-misc.adb.chats.revoke"), style=adb_go) |> ignore
                }
              })
            }) {
            act(core, tr("android-misc.adb.chats.revoke"), "adb.revoke", obj([("station", str(station)), ("request", str(request))]))
          }
        }
      })
    })
    if !waiting.is_empty() {
      blocks.push(fn() { section_header(c, tr("android-misc.adb.chats.waiting"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          for g in waiting {
            let g = Some(g)
            list_row(c, fn() { row_lines(c, text(g, "reason"), named(text(g, "station")), wrap_title=true) }) |> ignore
          }
        })
      })
    }
    // what the phone lacks for it (本机设置)
    match phone {
      Some(_) if flag(phone, "supported") => {
        let lacks : Array[(String, String)] = []
        if !flag(phone, "developer") {
          lacks.push((tr("android-misc.adb.developer"), tr("android-misc.adb.offValue")))
        }
        if !flag(phone, "wifi") {
          lacks.push((tr("android-misc.adb.wifi"), tr("android-misc.adb.wifi.off")))
        }
        if !flag(phone, "wireless") {
          lacks.push((tr("android-misc.adb.wireless"), tr("android-misc.adb.offValue")))
        }
        if !lacks.is_empty() {
          blocks.push(fn() { section_header(c, tr("android-misc.adb.phone"), start=S6) })
          blocks.push(fn() {
            list_card(c, fn() {
              for lack in lacks {
                list_row(c, fn() {
                  row_title(c, lack.0)
                  c.text(lack.1, style=adb_lacks) |> ignore
                })
                |> ignore
              }
            })
          })
        }
      }
      Some(_) =>
        blocks.push(fn() {
          list_card(c, fn() {
            list_row(c, fn() {
              c.text(tr("android-misc.adb.unsupported"), style=adb_quiet) |> ignore
            })
            |> ignore
          })
        })
      None => ()
    }
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "adb/", blocks)
  })
  |> ignore
}
