// still.fail's crash reports and timings, as its own Android app sends them (Crashes.kt,
// BarTiming.kt): the host's (android/app/src/main/java/dev/mbui: Crashes.java, BarTiming.java), told here what only
// the app knows: the account signed in (the crashes kept since the last report go as it), the core failing and started
// again (CoreFailed), what the UI could not do as asked (UiFault), the bottom bar's switches (src/sfapp/bar_timing.mbt)
// and the topics their pages subscribe, the window thread's hangs (mbui's src/ui/journal.mbt). iOS's host takes them
// too (src/host/apple_reports.m: MetricKit's crash and hang reports; the bar's timing not), and macOS's (the same file:
// the window thread's hangs and the errors got past, no MetricKit). Where no host takes them (Windows, the web, an
// Apple build without PostHog's key: host_tell answers 0) only UiFault is set, as the core's span.

///|
/// Whether the account signed in was told (once a process, as Android's MainActivity does).
let reported : Ref[Bool] = Ref(false)

///|
/// Which hangs are sent (hang_gate.mbt).
let hang_gate : HangGate = HangGate::new()

///|
/// The subscriptions a switch being timed took on (by their ids), until their first message.
let timed : Map[Int, Bool] = Map([])

///|
/// The host's reports set going, before the app's first frame.
fn reports_start() -> Unit {
  // what a call in flight as the core failed says (StillFailCore.restartedText)
  @core.restarted_text.val = @sfapp.tr("android-misc.core.restarted")
  if host_tell("hello", "", "", 0, 0) == 0 {
    // (no host's error report: what the UI could not do as asked goes as the core's `client.error` span, to Cloud Trace
    // with the rest of its traces, and to the host's log; a page showing 这部分显示出错了 said nothing otherwise)
    @view.fault_told.val = Some(fn(said) {
      let category = ui_fault_category(said)
      @hostapi.log("ui fault: " + category)
      @core.call("client.error", params={ "source": "ui_fault", "message": category })
    })
    return
  }
  @core.on_failed.val = Some(fn(reason) { host_tell("core_failed", reason, "", 0, 0) |> ignore })
  // what the UI was asked that it could not do as asked, shown in its place by the boundary round it (UiFault)
  @view.fault_told.val = Some(fn(said) { host_tell("ui_fault", ui_fault_category(said), "", 0, 0) |> ignore })
  // the settings' 发送使用统计和错误报告 (-1: a build that sends nothing, no row)
  if host_tell("reporting", "", "", 0, 0) >= 0 {
    @sfapp.reporting_host.set(
      Some({
        get: fn() { host_tell("reporting", "", "", 0, 0) == 1 },
        set: fn(on) { host_tell("set_reporting", "", "", if on { 1 } else { 0 }, 0) |> ignore },
      }),
    )
  }
  // the window thread's hangs (mbui's src/ui/journal.mbt), those hang_gate lets go; what the app did while shown as it
  // is hidden, its hangs all counted (hangs per hour shown), the heaviest held sent before it and how many were not
  @ui.hangs_told(
    Some(fn(h) {
      for s in hang_gate.offer(h) {
        host_tell("hang", s.json().stringify(), "", 0, 0) |> ignore
      }
    }),
  )
  @ui.hang_summary_told(
    Some(fn(s) {
      let (held, unsent) = hang_gate.flush()
      for h in held {
        host_tell("hang", h.json().stringify(), "", 0, 0) |> ignore
      }
      let json = match s.json() {
        Object(m) => {
          m["hangs_unsent"] = Json::number(unsent.to_double())
          // (what the core said meanwhile to ids nothing held, let be unread, by what the ids were: how many, their
          // length; none: not said)
          let unheld : Map[String, Json] = Map([])
          for u in @core.unheld_said() {
            unheld[u.0] = Json::array([Json::number(u.1.to_double()), Json::number(u.2.to_double())])
          }
          if !unheld.is_empty() {
            m["unheld"] = Json::object(unheld)
          }
          Json::object(m)
        }
        j => j
      }
      host_tell("hang_summary", json.stringify(), "", 0, 0) |> ignore
    }),
  )
  @sfapp.bar_timing.val = Some({
    placed: fn(from, to) { host_tell("placed", from, to, 0, 0) |> ignore },
    built: fn(place) { host_tell("built", place, "", 0, 0) |> ignore },
  })
  @core.time_topics(
    Some(fn(id, topic, value, first) {
      if !first {
        // (the host says whether a switch is being timed: a value's size is counted only then)
        if host_tell("followed", topic, "", id, 0) != 0 {
          timed[id] = true
        }
      } else if timed.contains(id) {
        timed.remove(id)
        // (what it weighs, and of one `weights_floor` heavy at least where its bytes are, by field: @core.weights,
        // names and numbers alone; no text of it made to count them)
        let (bytes, parts) = match value {
          Some(v) => {
            let (n, heavy) = @core.weights(v)
            let said : Map[String, Json] = Map([])
            if n >= weights_floor {
              for p in heavy {
                said[p.0] = Json::number(p.1.to_double())
              }
            }
            (n, if said.is_empty() { "" } else { Json::object(said).stringify() })
          }
          None => (-1, "")
        }
        host_tell("decoded", topic, parts, id, bytes) |> ignore
      }
    }),
  )
}

///|
/// The account signed in told to the host once the accounts are read (Android: Crashes.report, iOS: apple_reports.m,
/// as the first account's `sub`): what crashed before this start goes as it, and so do the reports after.
fn report_signed_in(c : @ui.Ctx, accounts : @core.Sub) -> Unit {
  if reported.val {
    return
  }
  let sub = match accounts.value {
    Some(Array(a)) if a.length() > 0 =>
      match a[0] {
        Object(m) =>
          match m.get("sub") {
            Some(String(s)) => s
            _ => return
          }
        _ => return
      }
    _ => return
  }
  c.after_build("crashes", fn() {
    if !reported.val {
      reported.val = true
      host_tell("signed_in", sub, "", 0, 0) |> ignore
    }
  })
}

///|
/// A topic's first value this heavy (bytes) says where its bytes are with the bar's timing (BarTiming's `parts`).
let weights_floor : Int = 32768
