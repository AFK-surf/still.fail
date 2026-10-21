// An app's own calls of its host (@host's native.mbt): what is the app's alone, by a name it gives (still.fail's
// 共享调试 on Android: "adb.phone", "adb.open"…), answered by what the app's own host code put there for that name. A
// call is an outside ticket of kind `native` (hostcall.mbt), asked from an event's handler or Ctx::tell, never while a
// frame builds (detlint's build-effect), and answered at a frame's boundary: the app reads NativeCall::got as its
// frames build. What the host says by itself (a setting changed, the app back from the system's settings) comes as a
// message on the channel "native:<name>" (messages.mbt: @ui.on_message; Tester::post).
//
// A real host's answer is kept on the run's tape as the app takes it, and given again to a Tester replaying it:
//
//   NATIVESAID {"name":NAME,"ok":JSON}     or {"name":NAME,"error":WHY}
//
// Under a Tester the host is the test's: a call waits (the app not at rest, Tester::rest_why says which) until the
// test answers it (Tester::answer_native, refuse_native), or a name's calls are answered as they are asked
// (Tester::native_answers), each from the frame after.

///|
/// A native call asked (`native_call`): its answer once the host has given it (`got`).
pub struct NativeCall {
  name : String
  host : @host.NativeCall?
  /// a Tester's: its place among the fake host's calls; -1 a real host's
  fake : Int
  /// a host without native calls: answered so at once
  none : Bool
  taken : Ref[Bool]
}

///|
/// A Tester's call: its name and params, and its answer with the frame it was given in.
priv struct FakeNative {
  name : String
  params : Json
  mut answer : (Result[Json, String], Int)?
}

///|
/// What a host without native calls answers: it has none.
pub let native_unsupported : String = "unsupported"

///|
/// `name` asked of the host with `params`. Ask it from an event's handler (or Ctx::tell), not while a frame builds:
/// a frame built again would ask it again.
pub fn native_call(name : String, params : Json) -> NativeCall {
  match fake.val {
    Some(f) => {
      let ask : FakeNative = { name, params, answer: None }
      let at = g().frame_no
      let mut held = -1
      for i, h in f.dev.native_held {
        if h.0 == name {
          held = i
          break
        }
      }
      if held >= 0 {
        ask.answer = Some((f.dev.native_held.remove(held).1, at))
      } else {
        match f.dev.native_auto.get(name) {
          Some(answer) => ask.answer = Some((answer(params), at))
          None => ()
        }
      }
      f.dev.natives.push(ask)
      let c : NativeCall = {
        name,
        host: None,
        fake: f.dev.natives.length() - 1,
        none: false,
        taken: Ref::new(false),
      }
      outside_start(outside_native, c.outside_id(), "the native call \{name} \{c.outside_id()}")
      if ask.answer is Some(_) {
        f.wants = true
      }
      c
    }
    None =>
      match @host.native_call(name, params.stringify()) {
        Some(h) => {
          let c : NativeCall = { name, host: Some(h), fake: -1, none: false, taken: Ref::new(false) }
          outside_start(outside_native, h.id(), "the native call \{name} \{h.id()}")
          c
        }
        None => { name, host: None, fake: -1, none: true, taken: Ref::new(false) }
      }
  }
}

///|
/// Its id as the host's event names it (outside_native), a Tester's its call's place, from 1.
fn NativeCall::outside_id(self : NativeCall) -> Int {
  match self.host {
    Some(h) => h.id()
    None => self.fake + 1
  }
}

///|
/// Its answer, from the frame after the host gave it (None until then, and once taken: keep it): Ok its JSON, Err why
/// not (`native_unsupported` on a host without native calls).
pub fn NativeCall::got(self : NativeCall) -> Result[Json, String]? {
  if self.taken.val {
    return None
  }
  if self.none {
    self.taken.val = true
    return Some(Err(native_unsupported))
  }
  let got = match self.host {
    Some(h) =>
      match h.got() {
        Some((true, said)) =>
          Some(
            Ok(
              @json.parse(said) catch {
                _ => Json::string(said)
              },
            ),
          )
        Some((false, why)) => Some(Err(why))
        None => None
      }
    None =>
      match fake.val {
        Some(f) if self.fake >= 0 && self.fake < f.dev.natives.length() =>
          match f.dev.natives[self.fake].answer {
            Some((r, at)) if g().frame_no > at => Some(r)
            _ => None
          }
        _ => None
      }
  }
  if got is Some(r) {
    self.taken.val = true
    outside_end(outside_native, self.outside_id())
    native_said(self.name, r)
  }
  got
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
  let j = @json.parse(line.view(start_offset=i + 11).to_owned()) catch { _ => return None }
  guard j is Object(m) else { return None }
  guard m.get("name") is Some(String(name)) else { return None }
  match (m.get("ok"), m.get("error")) {
    (Some(ok), _) => Some((name, Ok(ok)))
    (_, Some(String(why))) => Some((name, Err(why)))
    _ => None
  }
}

///|
/// `name`'s call asked first and not answered yet answered `r` (else its next call): taken from the next frame.
fn fake_native_give(f : FakeHost, name : String, r : Result[Json, String]) -> Unit {
  for a in f.dev.natives {
    if a.name == name && a.answer is None {
      a.answer = Some((r, g().frame_no))
      f.wants = true
      return
    }
  }
  f.dev.native_held.push((name, r))
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
/// The native call `id` (Tester::native_calls) answered `json`, now: taken from the next frame. Nothing if it is
/// answered already.
pub fn Tester::answer_native(self : Tester, id : Int, json : Json) -> Unit {
  fake_native_answer(self.fake, id, Ok(json))
}

///|
/// The native call `id` refused, `why`, now: taken from the next frame.
pub fn Tester::refuse_native(self : Tester, id : Int, why : String) -> Unit {
  fake_native_answer(self.fake, id, Err(why))
}

///|
fn fake_native_answer(f : FakeHost, id : Int, r : Result[Json, String]) -> Unit {
  guard id >= 1 && id <= f.dev.natives.length() else { return }
  let a = f.dev.natives[id - 1]
  guard a.answer is None else { return }
  a.answer = Some((r, g().frame_no))
  f.wants = true
}

///|
/// `name`'s calls answered by `answer` (given the call's params) as they are asked, each from the frame after: the
/// test's host, for calls whose answer is not what the test is about.
pub fn Tester::native_answers(self : Tester, name : String, answer : (Json) -> Json) -> Unit {
  self.fake.dev.native_auto[name] = fn(p) { Ok(answer(p)) }
}
