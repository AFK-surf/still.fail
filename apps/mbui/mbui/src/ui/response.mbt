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
  /// the pointer is over it (a mouse's: a finger's only while down)
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
  /// where it was last frame, as far as it showed (x, y, w, h; all 0 the first frame)
  rect : (Double, Double, Double, Double)
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
    rect: (0.0, 0.0, 0.0, 0.0),
  }
}

///|
/// The same, `changed` when `yes`.
pub fn Response::changed_to(self : Response, yes : Bool) -> Response {
  { ..self, changed: self.changed || yes }
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
/// focus (unless not `focusable`, or `disabled`: nothing happens to it then but being pointed at). `keys`: those of
/// Enter and Space that press it (press_enter, press_space); `focus_on_press`: a press gives it the focus (a slider's
/// thumb), else only the keyboard does. `node`: its node (as Ctx::box returns it), for where the focus goes in order.
pub fn Ctx::interact(
  self : Ctx,
  id : Int,
  node? : Int = -1,
  focusable? : Bool = true,
  disabled? : Bool = false,
  keys? : Int = 3,
  focus_on_press? : Bool = false,
) -> Response {
  if id == 0 {
    return Response::none()
  }
  let rect = self.rect_of(id).unwrap_or((0.0, 0.0, 0.0, 0.0))
  if disabled {
    return { ..Response::none(), id, hovered: self.hover == id, rect }
  }
  if focusable {
    self.focusable(id, node~, keys~, on_press=focus_on_press)
  }
  let long = self.long_press(id)
  {
    id,
    clicked: self.clicked.contains(id) || self.action_asked(id, Activate),
    long_pressed: long,
    right_clicked: self.right_clicked(id),
    hovered: self.hover == id,
    pressed: self.active == id && self.down,
    focused: self.focus == id,
    focus_shown: self.focus == id && self.focus_visible,
    gained_focus: self.focus_gained(id),
    changed: false,
    rect,
  }
}

///|
/// Whether the press under way on `id` has just been held long_press_ms without moving: then it is the hold's (no
/// click when let go). A frame is asked for when it will have been.
fn Ctx::long_press(self : Ctx, id : Int) -> Bool {
  if !(self.down && self.active == id && !self.dragging) || self.press_at < 0.0 {
    return false
  }
  if self.held_told == self.press_at {
    return false
  }
  let held = self.now - self.press_at
  if held >= long_press_ms {
    self.held_told = self.press_at
    self.take_press()
    true
  } else {
    self.wake_in(long_press_ms - held)
    false
  }
}
