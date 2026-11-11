// A place something went to or came from (a Slack thread, a Feishu chat, a still.fail chat) as a node of the window's
// tree, made once: its platform's mark and its name, pressed where it leads somewhere (an agent's history's line, a
// message's route in a chat).

///|
/// Place `name` of platform `surface` (the core's: chat | ember | stillfail still.fail's mark, feishu Feishu's, else
/// Slack's), each as it changes, in `parent`: its mark `mark` across and its name in `words`, in a box of `look` (given
/// whether the hand is on it: lit_node's, where it is pressed; its ground, its padding, its corner), giving way in its
/// line (its name cut or wrapped where it is long, as `words` says). `press`: what pressing it does, while `on` says
/// it leads somewhere (None, or `on` false: it is not pressed, never lit). The node.
#callsite(autofill(loc))
pub fn place_node(
  parent : @view.View,
  surface : () -> String,
  name : () -> String,
  look : (Bool) -> @ui.Style,
  words : @ui.TextStyle,
  press? : (() -> Unit)? = None,
  on? : () -> Bool = fn() { true },
  mark? : Double = 12.0,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(p) {
    style_node(loc~, p, fn() { look(press is Some(_) && on() && lit_node(p)) })
    // (giving way in its line: its name wrapped or cut where it is long)
    p.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    match press {
      Some(go) => presses_node(p, go, on~)
      None => ()
    }
    p.pick(fn() { place_mark_name(surface(), theme().dark) }, fn(d, name) { drawable_node(d, name, mark) |> ignore })
    words_node(p, name, fn() { words }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
  })
}

///|
/// The drawable a place of platform `surface` is marked with (place_node's), in the dark theme where `dark`.
fn place_mark_name(surface : String, dark : Bool) -> String {
  match surface {
    "chat" | "ember" | "stillfail" => if dark { "stillfail_mark_dark" } else { "stillfail_mark" }
    "feishu" => "feishu"
    _ => "slack"
  }
}
