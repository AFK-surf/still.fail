// still.fail's crash reports and timings, as its own Android app sends them (docs/telemetry.md → 安卓: Crashes.kt,
// BarTiming.kt): the host's (android/app/src/main/java/dev/mbui: Crashes.java, BarTiming.java), told here what only
// the app knows: the account signed in (the crashes kept since the last report go as it), the core failing and started
// again (CoreFailed), the bottom bar's switches (src/sfapp/bar_timing.mbt) and the topics their pages subscribe. Where
// no host takes them (macOS, iOS, Windows, the web: host_tell answers 0) none of it is set.

///|
/// Whether the account signed in was told (once a process, as Android's MainActivity does).
let reported : Ref[Bool] = Ref(false)

///|
/// The subscriptions a switch being timed took on (by their ids), until their first message.
let timed : Map[Int, Bool] = {}

///|
/// The host's reports set going, before the app's first frame.
fn reports_start() -> Unit {
  // what a call in flight as the core failed says (StillFailCore.restartedText)
  @core.restarted_text.val = @sfapp.tr("android-misc.core.restarted")
  if host_tell("hello", "", "", 0, 0) == 0 {
    return
  }
  @core.on_failed.val = Some(fn(reason) { host_tell("core_failed", reason, "", 0, 0) |> ignore })
  // the settings' 发送使用统计和错误报告 (-1: a build that sends nothing, no row)
  if host_tell("reporting", "", "", 0, 0) >= 0 {
    @sfapp.reporting_host.set(
      Some({
        get: fn() { host_tell("reporting", "", "", 0, 0) == 1 },
        set: fn(on) { host_tell("set_reporting", "", "", if on { 1 } else { 0 }, 0) |> ignore },
      }),
    )
  }
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
/// The account signed in told to the host once the accounts are read (Android: Crashes.report, as the first account's
/// `sub`): what crashed before this start goes as it, and so do the reports after.
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
