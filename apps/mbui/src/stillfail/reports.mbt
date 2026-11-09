// still.fail's crash reports and timings, as its own Android app sends them (Crashes.kt,
// BarTiming.kt): the host's (android/app/src/main/java/dev/mbui: Crashes.java, BarTiming.java), told here what only
// the app knows: the account signed in (the crashes kept since the last report go as it), the core failing and started
// again (CoreFailed), what the UI could not do as asked (UiFault), the bottom bar's switches (src/sfapp/bar_timing.mbt)
// and the topics their pages subscribe, the window thread's hangs (mbui's src/ui/journal.mbt). iOS's host takes them
// too (src/host/apple_reports.m: MetricKit's crash and hang reports; the bar's timing not). Where
// no host takes them (macOS, Windows, the web, an iOS build without PostHog's key: host_tell answers 0) only UiFault
// is set, as the core's span.

///|
/// Whether the account signed in was told (once a process, as Android's MainActivity does).
let reported : Ref[Bool] = Ref(false)

///|
/// How many hangs have been sent in the ten minutes from `hangs_since` (the work clock's ms; below 0 none yet), and the
/// most sent in each: a phone slow throughout says so in each ten minutes' first and in each summary, not only in its
/// run's first twenty (a run of hours told nothing of its later stutters, 2026-11-09).
let hangs_sent : Ref[Int] = Ref(0)

///|
let hangs_since : Ref[Double] = Ref(-1.0)

///|
let hangs_most : Int = 20

///|
let hangs_span_ms : Double = 600000.0

///|
/// The subscriptions a switch being timed took on (by their ids), until their first message.
let timed : Map[Int, Bool] = {}

///|
/// The host's reports set going, before the app's first frame.
fn reports_start() -> Unit {
  // what a call in flight as the core failed says (StillFailCore.restartedText)
  @core.restarted_text.val = @sfapp.tr("android-misc.core.restarted")
  if host_tell("hello", "", "", 0, 0) == 0 {
    // (no host's error report: what the UI could not do as asked goes as the core's `client.error` span, to Axiom
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
  // the window thread's hangs (mbui's src/ui/journal.mbt), each at once while fewer than hangs_most were sent in its
  // ten minutes; what the app did while shown as it is hidden, its hangs all counted: hangs per hour shown
  @ui.hangs_told(
    Some(fn(h) {
      if hangs_since.val < 0.0 || h.end - hangs_since.val >= hangs_span_ms {
        hangs_since.val = h.end
        hangs_sent.val = 0
      }
      if hangs_sent.val < hangs_most {
        hangs_sent.val += 1
        host_tell("hang", h.json().stringify(), "", 0, 0) |> ignore
      }
    }),
  )
  @ui.hang_summary_told(Some(fn(s) { host_tell("hang_summary", s.json().stringify(), "", 0, 0) |> ignore }))
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
        let bytes = match value {
          Some(v) => utf8_length(v.stringify())
          None => -1
        }
        host_tell("decoded", topic, "", id, bytes) |> ignore
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
/// How many bytes `s` is in UTF-8 (a value's JSON as the core sent it: BarTiming's `bytes`).
fn utf8_length(s : String) -> Int {
  let mut n = 0
  for ch in s {
    let u = ch.to_int()
    let w = if u < 0x80 {
      1
    } else if u < 0x800 {
      2
    } else if u < 0x10000 {
      3
    } else {
      4
    }
    n += w
  }
  n
}
