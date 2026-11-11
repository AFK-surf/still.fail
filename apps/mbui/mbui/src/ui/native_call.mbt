// An app's own calls of its host (@hostapi's native.mbt): what is the app's alone, by a name it gives (still.fail's
// 共享调试 on Android: "adb.phone", "adb.open"…), answered by what the app's own host code put there for that name. A
// call is an outside ticket of kind `native` (hostcall.mbt), asked from an event's handler or Ctx::tell, never while a
// frame builds (detlint's build-effect), and answered by the host's event between frames, which takes the answer into
// the call's signal (NativeCall::take): what reads NativeCall::got, a node's binding or `reacts`, an old view's build,
// is told then, and nothing looks for it frame by frame. What the host says by itself (a setting changed, the app back from the system's settings) comes as a
// message on the channel "native:<name>" (messages.mbt: @ui.on_message; Tester::post).
//
// A real host's answer is kept on the run's tape as it is taken, and given again to a Tester replaying it:
//
//   NATIVESAID {"name":NAME,"ok":JSON}     or {"name":NAME,"error":WHY}
//
// Under a Tester the host is the test's: a call waits (the app not at rest, Tester::rest_why says which) until the
// test answers it (Tester::answer_native, refuse_native), or a name's calls are answered as they are asked
// (Tester::native_answers), each told at that moment as a host's event tells it (FakeHost::due: after the event that
// asked or answered, before the clock moves on or an input comes), at any rate of frames.

///|
/// A native call asked (`native_call`): its answer once the host has given it (`got`).
pub struct NativeCall {
  name : String
  host : @hostapi.NativeCall?
  /// a host without native calls: answered so at once
  none : Bool
  /// its answer, taken as the host's event says it came (NativeCall::take): what reads it is told then
  said : @signals.Signal[Result[Json, String]?]
}

///|
/// A Tester's call: its name and params, its answer once given, and whether its host's event told it (fake_native_due).
priv struct FakeNative {
  name : String
  params : Json
  mut answer : Result[Json, String]?
  mut said : Bool
}

///|
/// What a host without native calls answers: it has none.
pub let native_unsupported : String = "unsupported"

///|
/// `name` asked of the host with `params`. Ask it from an event's handler (or Ctx::tell), not while a frame builds:
/// a frame built again would ask it again. `on_got`: given its answer once, in the event that takes it (as a core
/// call's `on_done`), outside any tracking, to write state: what a call asked of a press does with its answer, where no
/// node waits on it (NativeCall::got is that). None: nobody reads it here.
pub fn native_call(
  name : String,
  params : Json,
  on_got? : (Result[Json, String]) -> Unit,
) -> NativeCall {
  match @hostapi.native_call(name, params.stringify()) {
    Some(h) => {
      let c : NativeCall = { name, host: Some(h), none: false, said: @signals.signal(None) }
      outside_start(outside_native, h.id(), "the native call \{name} \{h.id()}")
      outside_takes(outside_native, h.id(), fn() { c.take(on_got) })
      c
    }
    None => {
      let r : Result[Json, String] = Err(native_unsupported)
      // (answered as it is asked: told so in the event that asks it)
      match on_got {
        Some(f) => @signals.untracked(fn() { f(r) })
        None => ()
      }
      { name, host: None, none: true, said: @signals.signal(Some(r)) }
    }
  }
}

///|
/// The host's answer taken, as its event says it came (or, a host answering by the frame, as a frame begins): kept
/// on the run's tape, the call's wait over, said (NativeCall::got), given to `on_got`. Whether it was there to take.
fn NativeCall::take(self : NativeCall, on_got : ((Result[Json, String]) -> Unit)?) -> Bool {
  guard self.host is Some(h) && self.said.untracked() is None else { return false }
  let r = match h.got() {
    Some((true, said)) =>
      Ok(
        @json.parse(said) catch {
          _ => Json::string(said)
        },
      )
    Some((false, why)) => Err(why)
    None => return false
  }
  outside_end(outside_native, h.id(), wake=false)
  native_said(self.name, r)
  self.said.set(Some(r))
  match on_got {
    Some(f) => @signals.untracked(fn() { f(r) })
    None => ()
  }
  true
}

///|
/// Its answer once the host has given it (None until then): Ok its JSON, Err why not (`native_unsupported` on a host
/// without native calls). A signal's read: what reads it (a binding, a `reacts`, an old view's build) is told as the
/// answer comes, and reads the same however often.
pub fn NativeCall::got(self : NativeCall) -> Result[Json, String]? {
  self.said.get()
}

///|
/// The name it was asked by.
pub fn NativeCall::name(self : NativeCall) -> String {
  self.name
}

///|
/// A native call's answer as the app took it, on the run's tape (NATIVESAID), for a Tester replaying it to give again.
fn native_said(name : String, r : Result[Json, String]) -> Unit {
  if !taping() {
    return
  }
  let m : Map[String, Json] = { "name": Json::string(name) }
  match r {
    Ok(j) => m["ok"] = j
    Err(why) => m["error"] = Json::string(why)
  }
  tape_line("NATIVESAID " + Json::object(m).stringify())
}

///|
/// A NATIVESAID line's call and answer (None: not one).
fn native_of_line(line : String) -> (String, Result[Json, String])? {
  guard line.find("NATIVESAID ") is Some(i) else { return None }
  let j = @json.parse(line.exact_view(start=i + 11).to_owned()) catch { _ => return None }
  guard j is Object(m) else { return None }
  guard m.get("name") is Some(String(name)) else { return None }
  match (m.get("ok"), m.get("error")) {
    (Some(ok), _) => Some((name, Ok(ok)))
    (_, Some(String(why))) => Some((name, Err(why)))
    _ => None
  }
}

///|
/// `name`'s call asked first and not answered yet answered `r` (else its next call, as it is asked): told now.
fn fake_native_give(f : FakeHost, name : String, r : Result[Json, String]) -> Unit {
  for i, a in f.dev.natives {
    if a.name == name && a.answer is None {
      a.answer = Some(r)
      fake_native_due(f, i + 1)
      return
    }
  }
  f.dev.native_held.push((name, r))
}

///|
/// Call `id`'s answer, given now, told by its host's event at this moment (FakeHost::due: after the event under way,
/// before the clock moves on), as a device's host tells it as it comes (MB_OUTSIDE_NATIVE).
fn fake_native_due(f : FakeHost, id : Int) -> Unit {
  f.due(f.time, "a native call answered", fn() {
    guard f.dev.natives.get(id - 1) is Some(a) && !a.said && a.answer is Some(r) else { return }
    a.said = true
    on_outside(outside_native, id, if r is Ok(_) { 1 } else { -1 })
  })
}

///|
/// The app's native calls not answered yet, oldest first: (id, name, params), id what Tester::answer_native takes.
pub fn Tester::native_calls(self : Tester) -> Array[(Int, String, Json)] {
  let out = []
  for i, a in self.fake.dev.natives {
    if a.answer is None {
      out.push((i + 1, a.name, a.params))
    }
  }
  out
}

///|
/// Every native call the app asked, answered or not, oldest first: (name, params).
pub fn Tester::native_asked(self : Tester) -> Array[(String, Json)] {
  self.fake.dev.natives.map(fn(a) { (a.name, a.params) })
}

///|
/// The native call `id` (Tester::native_calls) answered `json`, now: told at this moment, as a host's event (after
/// what is going on, before the clock moves on or an input comes). Nothing if it is answered already.
pub fn Tester::answer_native(self : Tester, id : Int, json : Json) -> Unit {
  fake_native_answer(self.fake, id, Ok(json))
}

///|
/// The native call `id` refused, `why`, now: told at this moment, as answer_native's.
pub fn Tester::refuse_native(self : Tester, id : Int, why : String) -> Unit {
  fake_native_answer(self.fake, id, Err(why))
}

///|
fn fake_native_answer(f : FakeHost, id : Int, r : Result[Json, String]) -> Unit {
  guard id >= 1 && id <= f.dev.natives.length() else { return }
  let a = f.dev.natives[id - 1]
  guard a.answer is None else { return }
  a.answer = Some(r)
  fake_native_due(f, id)
}

///|
/// `name`'s calls answered by `answer` (given the call's params) as they are asked, each told at that moment (after
/// the event that asked): the test's host, for calls whose answer is not what the test is about.
pub fn Tester::native_answers(self : Tester, name : String, answer : (Json) -> Json) -> Unit {
  self.fake.dev.native_auto[name] = fn(p) { Ok(answer(p)) }
}
