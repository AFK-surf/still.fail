// What an app asks of the device beyond its window and its fields (as still.fail's Android app's remote screen does,
// apps/android/.../remote): the keyboard taken by a key catcher (a focus with no text of its own: what is typed is
// the app's, keys and all), the soft keyboard's height, the clipboard read (its words, its picture as PNG) and
// written (words or a PNG, with a label), the screen kept awake, a haptic. The backends' calls are device_native.mbt's
// and device_js.mbt's; each host has them all (android_device.h, apple_device.h, win_device.h, web/host.js).

///|
/// A read of the clipboard under way (`clip_read`): the host reads it off the app's thread (a picture of another kind
/// made a PNG) and tells it done (set_outside: kind 9, its id).
pub struct ClipRead {
  priv id : Int
}

///|
/// Its id, as the host's event names it.
pub fn ClipRead::id(self : ClipRead) -> Int {
  self.id
}

///|
/// What the clipboard held: its words ("" none), what of a picture it held (`clip_none`, `clip_png`: `png` its bytes,
/// `clip_too_large`, `clip_unreadable`).
pub(all) struct ClipGot {
  text : String
  picture : Int
  png : Bytes
}

///|
/// No picture on the clipboard.
pub let clip_none : Int = 0

///|
/// A picture, as PNG (another kind made one), at most `clip_png_max` bytes.
pub let clip_png : Int = 1

///|
/// A picture past the bounds: more than `clip_png_max` bytes as PNG, more than `clip_source_max` to read or
/// `clip_pixels_max` pixels to decode (another kind).
pub let clip_too_large : Int = 2

///|
/// A picture that could not be read or made a PNG.
pub let clip_unreadable : Int = 3

///|
/// The most a picture read off the clipboard is as PNG (still.fail's ScreenClips.kt CLIP_PNG_MAX).
pub let clip_png_max : Int = 8 * 1024 * 1024

///|
/// The most of a picture of another kind read to make it a PNG (CLIP_SOURCE_MAX).
pub let clip_source_max : Int = 32 * 1024 * 1024

///|
/// The most pixels of a picture of another kind decoded (CLIP_PIXELS_MAX).
pub let clip_pixels_max : Int = 16 * 1024 * 1024

///|
/// The clipboard read: its words, and its picture as PNG (Android: the primary clip's first item, its text or what it
/// says as text, a picture by its content URI where the clip's or the URI's type is image/*; macOS's and iOS's
/// pasteboard; Windows: its words; a browser's where the page may). None where the host cannot.
pub fn clip_read() -> ClipRead? {
  match cl_read() {
    0 => None
    id => Some({ id, })
  }
}

///|
/// What it read, once it has (None while it reads): taken once, the read forgotten as it is.
pub fn ClipRead::got(self : ClipRead) -> ClipGot? {
  match cl_state(self.id) {
    0 => None
    1 => {
      let got = { text: cl_text(self.id), picture: cl_picture(self.id), png: cl_png(self.id) }
      cl_end(self.id)
      Some(got)
    }
    _ => {
      cl_end(self.id)
      Some({ text: "", picture: clip_unreadable, png: Bytes::new(0) })
    }
  }
}

///|
/// Words put on the clipboard, `label` what the system shows of where they came from (Android's ClipData label; ""
/// none).
pub fn clip_set_text(text : String, label : String) -> Unit {
  cl_set(text, Bytes::new(0), label)
}

///|
/// A picture (`png`, PNG's bytes) put on the clipboard, `label` as clip_set_text's. Android keeps it as a file of the
/// cache's screen-clips (the newest 3) that the clip points at (image/png, read through the app's own provider);
/// macOS and iOS put the PNG on the pasteboard; Windows under its registered "PNG" format (what browsers and Office
/// read); a browser where the page may.
pub fn clip_set_png(png : Bytes, label : String) -> Unit {
  cl_set("", png, label)
}

///|
/// Whether the system says itself that something was copied (Android 13 and later show the clip with a preview): the
/// app need not say it again.
pub fn copy_shown() -> Bool {
  dv_copy_shown() != 0
}

///|
/// The focus is a key catcher's (`on`), or no longer: its input method and keys are the app's, as keys (Enter,
/// Backspace on an empty field, Escape, Tab, Page Up…, a letter with Ctrl, Alt or ⌘ as the key), with no text of the
/// host's own (@ui's Ctx::key_catcher). Said before set_ime as it changes.
pub fn key_catch(on : Bool) -> Unit {
  dv_key_catch(if on { 1 } else { 0 })
}

///|
/// How far the soft keyboard reaches over the window's foot, in points, as it moves (0: down, or none). The window
/// is laid out above it already (Android's view, iOS's keyboard layout guide).
pub fn ime_inset() -> Double {
  dv_ime_inset()
}

///|
/// The screen kept on (`on`) while the app is in front, or let sleep again (Android's FLAG_KEEP_SCREEN_ON, iOS's idle
/// timer, macOS's display sleep assertion, Windows' execution state, a browser's wake lock).
pub fn keep_awake(on : Bool) -> Unit {
  dv_keep_awake(if on { 1 } else { 0 })
}

///|
/// A haptic of `kind` (haptic_*): Android's View.performHapticFeedback with the constant Compose uses for it, iOS's
/// feedback generators, a Mac's trackpad; nothing on Windows and in a browser.
pub fn haptic(kind : Int) -> Unit {
  dv_haptic(kind)
}

///|
/// A long press taking something (Android LONG_PRESS, Compose's HapticFeedbackType.LongPress).
pub let haptic_long_press : Int = 0

///|
/// A context click, a menu's secondary press (CONTEXT_CLICK).
pub let haptic_context_click : Int = 1

///|
/// A step passed while dragging (a text handle moved, a swipe past its line: TEXT_HANDLE_MOVE).
pub let haptic_text_handle_move : Int = 2

///|
/// Something done (CONFIRM).
pub let haptic_confirm : Int = 3

///|
/// Something refused (REJECT).
pub let haptic_reject : Int = 4

///|
/// A key tapped (KEYBOARD_TAP).
pub let haptic_keyboard_tap : Int = 5
