// An app's own calls of its host (@ui.native_call): what is the app's alone (still.fail's 共享调试 reads Android's
// Wireless debugging, opens its settings, starts its service), named by the app and answered by what the app's own
// code put in the host for that name (Android: dev.mbui.Natives.put). The answer comes as an outside of kind 10
// (set_outside), at a frame's boundary: its JSON, or why not. A host with nothing for calls answers none (0): the app
// is told it cannot.

///|
/// A native call under way (`native_call`).
pub struct NativeCall {
  id : Int
}

///|
/// Its id, as the host's event names it (set_outside: kind 10).
pub fn NativeCall::id(self : NativeCall) -> Int {
  self.id
}

///|
/// `name` asked of the host with `params` (JSON); None where the host takes no native calls.
pub fn native_call(name : String, params : String) -> NativeCall? {
  match ncall_call(name, params) {
    0 => None
    id => Some({ id, })
  }
}

///|
/// Its answer, once the host has given it (None until then): (true, the answer's JSON) or (false, why not); taken once,
/// the call forgotten as it is.
pub fn NativeCall::got(self : NativeCall) -> (Bool, String)? {
  match ncall_state(self.id) {
    0 => None
    state => {
      let said = ncall_result(self.id)
      ncall_end(self.id)
      Some((state == 1, said))
    }
  }
}
