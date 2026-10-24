// What is asked of the core from a button, for both frames (the web's AppState.act, useAct, doing.ts): under way on
// its button until the core answers, said in a toast when done or when it could not be; nothing with MBUI_READONLY=1.

///|
/// What was set going and is not answered yet (AppState.isDoing), by its key; what failed a moment ago (the core's
/// doing keeps a failure 6 s: DoingMark's red mark), by its key, which failure it is (each its own 6 s).
pub(all) struct Acting {
  doing : Map[String, Bool]
  failed : Map[String, Int]
  mut failed_n : Int
}

///|
pub let acting : Acting = { doing: {}, failed: {}, failed_n: 0 }

///|
/// As at the start (the app's reset).
pub fn acting_reset() -> Unit {
  acting.doing.clear()
  acting.failed.clear()
}

///|
/// Says `words` in the toast from the next frame on (from a call's answer, between frames).
pub fn toast_later(words : String) -> Unit {
  app.toast = words
  app.toast_n += 1
}

///|
/// Has the core do something (AppState.act): `key` under way until it answers (its button's spinner), `done` said
/// when it did, why not said when it could not (`failed` told then). Nothing with MBUI_READONLY=1.
pub fn act(
  src : Source,
  what : String,
  key : String,
  call : String,
  params : Json,
  done? : String = "",
  ok? : (Json) -> Unit = fn(_) {  },
  failed? : () -> Unit = fn() {  },
) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    failed()
    return
  }
  if key != "" {
    acting.doing[key] = true
    acting.failed.remove(key)
  }
  (src.call)(call, params, fn(res) {
    if key != "" {
      acting.doing.remove(key)
    }
    if key != "" && res is Err(_) {
      // its 6 s from the frame that first shows it (failed_lately)
      acting.failed_n += 1
      acting.failed[key] = acting.failed_n
    }
    match res {
      Ok(v) => {
        if done != "" {
          toast_later(done)
        }
        ok(v)
      }
      Err(e) => {
        let code = text(Some(e), "code")
        toast_later(
          @sf.t(if code == "unconfirmed" { "android-misc.act.unconfirmed" } else { "android-misc.act.failed" }, args=[
            ("what", what),
            ("error", error_words(e)),
          ]),
        )
        failed()
      }
    }
  })
}

///|
/// What went wrong, in words (errorText): the core's message, else its code.
pub fn error_words(e : Json) -> String {
  match text(Some(e), "message") {
    "" => text(Some(e), "code")
    m => m
  }
}

///|
/// Whether `key` is under way (AppState.isDoing).
pub fn doing(key : String) -> Bool {
  acting.doing.contains(key)
}

///|
/// How long what failed keeps its red mark (the core's doing keeps a failure 6 s).
let failed_ms : Double = 6000.0

///|
/// Whether `key` failed within the last 6 s (AppState.failedOf); a frame asked for when its mark is to go.
pub fn failed_lately(c : @ui.Ctx, key : String) -> Bool {
  match acting.failed.get(key) {
    // (its going is not what is shown waits for: a screenshot of it failing shows the mark)
    Some(n) if @kit.after(c, "failed/\{key}/\{n}", true, failed_ms, later=true) => {
      acting.failed.remove(key)
      false
    }
    Some(_) => true
    None => false
  }
}
