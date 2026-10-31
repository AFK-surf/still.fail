// What happened to a widget since the last frame, in one value (egui's Response): clicked (a tap, a click, Enter or
// Space while it has the focus, the Activate action), held long, clicked with the secondary button, pointed at,
// pressed, focused, changed (what the widget's value became differs), and where it was drawn last frame. A widget
// that returned a Bool still does; the components return this (or it with their value: Changed).

///|
pub(all) struct Response {
  /// the widget's id (0: none, nothing happens to it)
  id : Int
  /// pressed and let go on it, without dragging; or Enter or Space while it had the focus; or Activate asked of it
  clicked : Bool
  /// held down for long_press_ms without moving (the press is then no click)
  long_pressed : Bool
  /// where it was clicked with the secondary button (a right click; Ctrl-click on macOS), in the window
  right_clicked : (Double, Double)?
  /// lit by the hand on it (Ctx::lit): a mouse's pointer resting on it, a finger pressing it
  hovered : Bool
  /// held down
  pressed : Bool
  /// has the keyboard's focus; and it shows (it came by the keyboard: a ring is drawn)
  focused : Bool
  focus_shown : Bool
  /// came to have the focus since the last frame
  gained_focus : Bool
  /// the widget's value changed this frame (said by the widget: Response::changed_to)
  changed : Bool
} derive(Show)

///|
/// A response of nothing (a widget not there, disabled).
pub fn Response::none() -> Response {
  {
    id: 0,
    clicked: false,
    long_pressed: false,
    right_clicked: None,
    hovered: false,
    pressed: false,
    focused: false,
    focus_shown: false,
    gained_focus: false,
    changed: false,
  }
}

///|
/// The same, `changed` when `yes`.
pub fn Response::changed_to(self : Response, yes : Bool) -> Response {
  { ..self, changed: self.changed || yes }
}

///|
/// Where the widget was drawn last frame, as far as it showed (x, y, w, h; all 0 the first frame and for none): read
/// only where it is read (a slider's track under the finger, what a select's menu opens by), for what reads it reads
/// the frame before (Ctx::rect_of).
pub fn Response::rect(self : Response) -> (Double, Double, Double, Double) {
  if self.id == 0 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  current().rect_of(self.id).unwrap_or((0.0, 0.0, 0.0, 0.0))
}

///|
/// What a widget with a value returns: its value now (what the view keeps: the widget only reports it), and what
/// happened to it.
pub(all) struct Changed[T] {
  value : T
  response : Response
}

///|
/// Whether its value changed this frame.
pub fn[T] Changed::changed(self : Changed[T]) -> Bool {
  self.response.changed
}

///|
/// What happened to widget `id` since the last frame (see the file's head); it is registered as able to take the
/// focus (unless not `focusable`, or `disabled`: nothing happens to it then but being pointed at), and as taking
/// presses (as Ctx::clicked asked: the pointer's hand over it; not `disabled`). `keys`: those of
/// Enter and Space that press it (press_enter, press_space); `focus_on_press`: a press gives it the focus (a slider's
/// thumb), else only the keyboard does. `node`: its node (as Ctx::box returns it), for where the focus goes in order.
/// `holds`: held however long, it is still pressed and let go a tap (a control that answers being held, its knob a
/// lens while a finger is on it), never long pressed.
pub fn Ctx::interact(
  self : Ctx,
  id : Int,
  node? : Int = -1,
  focusable? : Bool = true,
  disabled? : Bool = false,
  keys? : Int = 3,
  focus_on_press? : Bool = false,
  holds? : Bool = false,
) -> Response {
  if id == 0 {
    return Response::none()
  }
  if disabled {
    return { ..Response::none(), id, hovered: self.lit(id) }
  }
  if focusable {
    self.focusable(id, node~, keys~, on_press=focus_on_press)
  }
  self.takes_presses(id)
  let long = !holds && self.long_press(id)
  {
    id,
    clicked: self.click_seen(id),
    long_pressed: long,
    right_clicked: self.right_clicked(id),
    hovered: self.lit(id),
    pressed: self.held_down(id),
    focused: self.has_focus(id),
    focus_shown: self.focus_shown(id),
    gained_focus: self.focus_gained(id),
    changed: false,
  }
}

///|
/// Whether `id` has been held still long_press_ms since it was pressed: in the build it comes to, to whoever asks
/// (the widget's response, its tooltip); the press is then no tap. What a finger asks a menu or a tooltip by. Like a
/// click, an input of the frame's: the frame built again (frame_body) sees it no more, so what it opens opens once.
pub fn Ctx::held_long(self : Ctx, id : Int) -> Bool {
  if id != 0 {
    // (read so: hand.mbt)
    hand.held.has(id) |> ignore
  }
  self.long_press(id) ||
  (id != 0 && self.held_on == id && self.held_build == self.build_no && self.held_told == self.press_at)
}

///|
/// Whether the press under way on `id` has just been held long_press_ms without moving: then it is the hold's (no
/// click when let go). A frame is asked for when it will have been.
fn Ctx::long_press(self : Ctx, id : Int) -> Bool {
  // (read so: what reads it is built again as it is pressed or let go, hand.mbt; held long a moment, woken at)
  if id != 0 {
    hand.pressed.has(id) |> ignore
  }
  if !(self.down && self.active == id && !self.dragging && !self.press_strayed) || self.press_at < 0.0 {
    return false
  }
  if self.held_told == self.press_at {
    return false
  }
  let held = self.clock - self.press_at
  if held >= long_press_ms {
    self.held_told = self.press_at
    self.held_on = id
    self.held_build = self.build_no
    self.take_press()
    true
  } else {
    self.wake_in(long_press_ms - held)
    false
  }
}

///|
/// The press just down held long already, as the window's tree found it (a hold a cover of its handed on, as long held
/// as since the finger went down: view_through): what it is on held long as the build it comes to sees it (as
/// Ctx::long_press tells), its press no click, whatever frames come before it is let go. False where no press is
/// down on anything.
fn Ctx::held_through(self : Ctx) -> Bool {
  if !self.down || self.active == 0 || self.press_at < 0.0 {
    return false
  }
  self.held_told = self.press_at
  self.held_on = self.active
  // (the build it comes to: the next begun)
  self.held_build = builds_made.val + 1
  self.take_press()
  true
}

///|
/// Where the press went down, if the window's tree handed it to the old views held long already (a cover's hold handed
/// on: view_through, view_handed) and this is a build of the frame it comes to (the frame the first build begun after
/// it is of, each build of it: what it is held on lays out what it needs of it, words, and reads it back so), not
/// taken yet (Ctx::handed_taken), what it was handed to taking input still (no modal layer over it, not leaving, not
/// gone), no press down since: let go since or not, it is a long press there, once, whatever frames came between. What
/// a hold over words takes as held (kit's Pick::hold), as a held press is.
pub fn Ctx::handed_hold(self : Ctx) -> (Double, Double)? {
  hand.down.get() |> ignore
  match view_handed.val {
    Some(h) if !h.taken &&
      h.frame == self.frame_no &&
      h.down == downs_made.val &&
      old_owner_open(h.owner) => Some((h.x, h.y))
    _ => None
  }
}

///|
/// The hold handed here (Ctx::handed_hold) taken by what it is held on: none to take after it.
pub fn Ctx::handed_taken(self : Ctx) -> Unit {
  match view_handed.val {
    Some(h) => h.taken = true
    None => ()
  }
}

///|
/// Whether the press under way has been held still `ms` since it went down (its own moment, Ctx's `press_at`: a hold
/// the window's tree handed on, since the finger went down, Ctx::held_through), whatever is pressed: what a hold over
/// words asks (kit's Pick::hold). A frame asked for when it will have been.
pub fn Ctx::held_for(self : Ctx, ms : Double) -> Bool {
  // (read so: what reads it is built again as it is pressed or let go, hand.mbt; held long a moment, woken at)
  hand.down.get() |> ignore
  if !self.down || self.dragging || self.press_strayed || self.press_at < 0.0 {
    return false
  }
  let held = self.clock - self.press_at
  if held >= ms {
    true
  } else {
    self.wake_in(ms - held)
    false
  }
}

///|
/// Whether a press is down on `id`, from the moment it went down (no wait for what scrolls: Ctx::pressed has it, for
/// how a thing shows it is pressed), read so (hand.mbt): what a gesture on it follows, whatever it shows.
pub fn Ctx::held_down(self : Ctx, id : Int) -> Bool {
  if id != 0 {
    hand.pressed.has(id) |> ignore
  }
  self.active == id && self.down
}
