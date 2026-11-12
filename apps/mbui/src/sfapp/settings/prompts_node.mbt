// What the prompts the core's `lockPrompts` puts up over the pages share (vault_prompts.mbt, lock_prompts.mbt): each
// panel's ask as the core holds it now, and its panel gone by itself once the core holds it no more.

///|
/// The ask of the core's `lockPrompts` list `list` that `is_it` picks, as the core holds it now: None while that topic
/// is unread, Some(None) once it holds it no more.
fn prompt_now(core : Core, list : String, is_it : (Json) -> Bool) -> Json?? {
  let prompts = (core.topic)("lockPrompts", Map([])).get().value
  match prompts {
    None => None
    Some(_) => Some(items(prompts, list).iter().find_first(is_it))
  }
}

///|
/// A prompt's panel closed (`close`, given its body's node `v`) at the moment the core comes to hold its ask no more
/// (`now`, prompt_now: done or put away on another device), once; at once where it holds it no more as it opens.
fn prompt_goes(v : @view.View, now : () -> Json??, close : () -> Unit) -> Unit {
  v.reacts(fn() { now() is Some(None) }, fn(gone) {
    if gone {
      close()
    }
  })
}
